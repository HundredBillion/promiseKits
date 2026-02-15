# Data Model — Order Export & Email (.xlsx)

This document defines the database schema, important constraints, indexes, and access patterns required by the Order Export feature described in `spec.md`. The goal is a small, auditable set of tables that: (1) let us reserve orders atomically for an export run, (2) guarantee each order is exported at most once, and (3) provide rich metadata for observability and troubleshooting.

Table of contents
- Summary
- Entities & fields
  - `order_exports`
  - `exported_orders`
- Indexes and constraints
- Example Rails migrations
- Model associations & key methods
- Reservation algorithm (SQL / AR patterns)
- Backfill & re-export considerations
- Tests to add
- Operational notes

---

## Summary

Primary requirements encoded in the data model:

- Persist an `OrderExport` record per run (scheduled or manual) with start/end window metadata, recipient, status and any error message.
- Persist `ExportedOrder` join rows to record which orders were included in which run.
- Enforce an application-level and DB-level guarantee that an order is exported at most once: add a unique index on `exported_orders.order_id`.
- Use `created_at` timestamp ranges for selection: (created_at > last_export.ends_at) AND (created_at <= current_run.ends_at). Lower bound is exclusive; upper bound inclusive.

---

## Entities & fields

### `order_exports` (records each export run)

- Purpose: Track export runs, their scheduling metadata, status, recipient, filename and errors.
- Recommended columns:

  - `id` : bigint, primary key
  - `status` : string, NOT NULL — enum values: `"pending"`, `"running"`, `"succeeded"`, `"failed"`
  - `scheduled_for` : datetime (UTC) — the canonical scheduled time (the job should be invoked with this)
  - `started_at` : datetime (UTC), nullable
  - `ends_at` : datetime (UTC) — inclusive upper bound for included orders (populated before reservation)
  - `recipient` : string — email used for this run (can be overridden on manual exports)
  - `filename` : string, nullable — persisted filename of generated attachment
  - `error_message` : text, nullable — store failure reasons
  - `created_at`, `updated_at` : timestamps

- Typical status flow:
  - created as `pending` (scheduler or UI)
  - when reservation begins set to `running` and `started_at` set
  - when all done set to `succeeded` with `filename`
  - on failure set to `failed` and `error_message` populated

### `exported_orders` (join rows)

- Purpose: Record the fact that a specific `Order` was reserved/included in a specific `OrderExport` run.
- Recommended columns:

  - `id` : bigint, primary key
  - `order_export_id` : bigint, NOT NULL, foreign key -> `order_exports.id`
  - `order_id` : bigint, NOT NULL, foreign key -> `orders.id`
  - `created_at` : datetime

- Important constraints:
  - UNIQUE constraint on `order_id` (enforces "exactly once" semantics).
    - Rationale: The acceptance criteria require each order to appear in exactly one export. A DB-level unique index provides a strong guard in concurrent scenarios.
    - If re-export capability is desired later, this unique constraint can be removed and application-level logic adjusted; for current spec we recommend keeping it.

- Alternate (less strict) approach:
  - Unique composite index on `(order_export_id, order_id)` only, and rely entirely on transactional reservation logic to avoid duplicates. We choose `unique order_id` for stronger DB-level enforcement.

---

## Indexes & constraints (recommended)

- `order_exports`:
  - index `index_order_exports_on_scheduled_for(scheduled_for)`
  - index `index_order_exports_on_status(status)`

- `exported_orders`:
  - unique index `index_exported_orders_on_order_id(order_id)` — enforces single export per order
  - index `index_exported_orders_on_order_export_id(order_export_id)` — for quick lookups of orders in a run
  - foreign key constraints for data integrity:
    - `exported_orders.order_export_id` -> `order_exports.id` (ON DELETE RESTRICT or CASCADE per policy)
    - `exported_orders.order_id` -> `orders.id` (ON DELETE RESTRICT recommended to keep historical audit)

Notes:
- Consider `ON DELETE RESTRICT` to prevent accidental data loss if referenced records are removed.
- If audits require permanent historical linkage even if `orders` are deleted, consider soft-deleting orders rather than removing them.

---

## Example Rails migrations

Below are concise examples to use as a starting point. Adapt column types / options to your DB and conventions (timestamps precision, nullability).

Migration 1 — create `order_exports`:

```ruby
class CreateOrderExports < ActiveRecord::Migration[7.0]
  def change
    create_table :order_exports do |t|
      t.string :status, null: false, default: "pending"
      t.datetime :scheduled_for, null: false
      t.datetime :started_at
      t.datetime :ends_at
      t.string :recipient
      t.string :filename
      t.text :error_message

      t.timestamps
    end

    add_index :order_exports, :scheduled_for
    add_index :order_exports, :status
  end
end
```

Migration 2 — create `exported_orders`:

```ruby
class CreateExportedOrders < ActiveRecord::Migration[7.0]
  def change
    create_table :exported_orders do |t|
      t.references :order_export, null: false, foreign_key: true, index: true
      t.references :order, null: false, foreign_key: true, index: true

      t.timestamps
    end

    # Enforce each order can only be exported once (exactly-once semantics)
    add_index :exported_orders, :order_id, unique: true, name: "index_exported_orders_on_order_id_unique"
  end
end
```

Migration notes:
- If your production DB is PostgreSQL and you expect extremely large exports, consider tuning statement timeouts and using batched inserts.
- If you prefer allowing re-exports, replace the unique index with:
  ```ruby
  add_index :exported_orders, [:order_export_id, :order_id], unique: true
  ```

---

## Model associations & key methods (Rails)

`app/models/order_export.rb` (summary)

```ruby
class OrderExport < ApplicationRecord
  has_many :exported_orders, dependent: :restrict_with_exception
  has_many :orders, through: :exported_orders

  enum status: { pending: 'pending', running: 'running', succeeded: 'succeeded', failed: 'failed' }

  validates :status, :scheduled_for, presence: true

  def self.last_successful
    where(status: 'succeeded').order(ends_at: :desc).limit(1).first
  end

  # Reserve orders for this export. See Reservation algorithm below for primitives.
  def reserve_orders!(ends_at:, starts_at: nil)
    # Implementation detail: determine candidate order ids,
    # create ExportedOrder rows inside a transaction, handle uniqueness conflicts.
  end

  def mark_succeeded!(filename = nil)
    update!(status: 'succeeded', filename: filename, error_message: nil)
  end

  def mark_failed!(msg)
    update!(status: 'failed', error_message: msg.to_s)
  end
end
```

`app/models/exported_order.rb` (summary)

```ruby
class ExportedOrder < ApplicationRecord
  belongs_to :order_export
  belongs_to :order

  validates :order_id, uniqueness: true
end
```

---

## Reservation algorithm (patterns & SQL)

Reservation goal: atomically claim the set of orders with:

- created_at > previous_export.ends_at (exclusive)
- AND created_at <= current_run.ends_at (inclusive)

High-level steps (transactional pattern):

1. Determine `starts_at`:
   - `last_success = OrderExport.last_successful`
   - `starts_at = last_success&.ends_at` (may be `nil` → include all earlier orders)

2. Compute candidate order ids (ordered by created_at):
   - SQL:
     ```sql
     SELECT id FROM orders
     WHERE (created_at > :starts_at OR :starts_at IS NULL)
       AND created_at <= :ends_at
     ORDER BY created_at ASC;
     ```
   - In Rails:
     ```ruby
     scope = Order.all
     scope = scope.where('created_at > ?', starts_at) if starts_at.present?
     scope = scope.where('created_at <= ?', ends_at)
     order_ids = scope.order(:created_at).pluck(:id)
     ```

3. Inside a DB transaction:
   - Update the `OrderExport` row: set `status: 'running', started_at: Time.current.utc, ends_at: ends_at`.
   - Insert `ExportedOrder` rows for the candidate ids.
     - Use batched inserts (e.g., slices of 500).
     - Handle unique constraint violations (another worker may have claimed some IDs): on conflict skip or rescue `ActiveRecord::RecordNotUnique` and continue.
     - Track which ids were successfully inserted (those are the reserved set).
   - Commit.

4. Return the reserved `Order` records in chronological order for builder consumption:
   ```ruby
   ::Order.where(id: reserved_ids).order(:created_at)
   ```

Concurrency notes:
- The unique index on `exported_orders.order_id` ensures concurrent transactions cannot both succeed for the same order.
- If a race causes unique constraint violation for some rows, the transaction should not fail entirely — handle the exception per-row or use DB-level "INSERT ... ON CONFLICT DO NOTHING" for bulk insert where supported.
- In high-concurrency environments use `INSERT ... ON CONFLICT DO NOTHING` (Postgres) for efficient bulk inserts.

Example Postgres bulk insertion pattern:

```sql
INSERT INTO exported_orders (order_export_id, order_id, created_at, updated_at)
VALUES
  (1, 101, now(), now()),
  (1, 102, now(), now())
ON CONFLICT (order_id) DO NOTHING;
```

---

## Backfill & re-export considerations

- Backfill scenario:
  - If the system is running for the first time and you want to seed an initial export_cutoff, create an initial `OrderExport` record with `status: 'succeeded'` and `ends_at` set to an appropriate epoch. Alternatively, allow the first scheduled run to include all historic orders.
- Re-exporting specific orders:
  - With `unique order_id` enforced, re-export requires manual deletion of `exported_orders` rows for those `order_id`s or adding a special admin/repair task that creates a new `order_exports` run and moves rows.
  - If re-send capability is required frequently, prefer a different model (for example, keep `exported_orders` non-unique and have an `export_attempts` log) — but this contradicts the acceptance criteria of exactly-once.
- Auditability:
  - Keep `exported_orders` rows even after `order_exports` are purged (if you ever purge, archive the rows to a safe store).

---

## Tests to add (data-model focused)

- Model specs:
  - `OrderExport#reserve_orders!`:
    - given a set of candidate orders, ensure `ExportedOrder` rows are created and `reserved_ids` are returned in order.
    - simulate concurrency: run two reservations in threads/processes and assert no duplicate exported orders exist.
  - Uniqueness behavior:
    - attempting to create two `ExportedOrder` rows with the same `order_id` should raise / be caught; test that `reserve_orders!` handles this gracefully.
- Migration tests:
  - Verify indexes and unique constraint exist (schema spec test).
- Integration tests:
  - After running job, `order_exports` row should be `succeeded` and `exported_orders` rows count equals exported_count passed to mailer.

---

## Operational notes

- Retention & housekeeping:
  - Keep export records and exported orders for audit for a period required by policy (e.g., 1 year). Add a cleanup rake task to archive older exports if needed.
- Monitoring:
  - Log reservation counts and mail delivery success/failure. Consider incrementing metrics (Prometheus counters) for exports succeeded/failed.
- Error handling:
  - On job failure, ensure `order_exports` is set to `failed` and `error_message` captures actionable information. Let ActiveJob retry as configured.
- Permissions:
  - Only admins should be able to trigger manual exports in UI. The job runs without UI credentials.
- Files:
  - Generated .xlsx files are written to a Tempfile in the job; ensure temp cleanup in `ensure` block. Keep file names consistent:
    - `orders_export_YYYYMMDD_HHMMSS_UTC.xlsx`

---

If you want, I can now:
- Create `data-model.md` in the repository (done in this step),
- Create `research.md` and `quickstart.md` next, or
- Add the actual migration files and model skeletons consistent with this design.

Which would you like me to do next?