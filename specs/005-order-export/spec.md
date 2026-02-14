# Feature 005 — Order Export & Email (.xlsx)  
Spec: Export orders to Excel and email them to the configured recipient on Mon/Wed/Fri at 07:00 EST; support ad-hoc/admin-triggered exports; guarantee every order is exported exactly once (no duplicates), and allow admins to jump sequence numbers without breaking export logic.

---

## Summary / Goal
Provide a reliable, auditable, and testable background process that:
- Creates an Excel (.xlsx) file containing all order rows (columns matching the `orders` table).
- Emails that file to a single configured recipient on scheduled times (Mon/Wed/Fri at 07:00 EST).
- Supports ad-hoc/manual export requests from the admin UI.
- Ensures each order is included in exactly one exported email (no duplication across exports).
- Works robustly with SQLite (production environment) and tolerates admin changes to order confirmation numbering.

Implementation choices (defaults)
- Use `caxlsx` gem for .xlsx generation (industry-standard maintained fork of axlsx).
- Use ActiveJob to enqueue/execute export jobs. In production you may use Sidekiq; the code will work with whichever adapter is configured.
- Persist an `OrderExport` record per export run (scheduled or manual) and `ExportedOrder` join rows to record which orders were exported in that run. This gives auditability and idempotency.
- Use `created_at` timestamp ranges to identify orders to include, not order_confirmation numbers (to avoid problems if confirmations are re-sequenced). Use DB transactions to atomically reserve the set of orders to be exported for a given run.

---

## User stories

1. As an admin, I want to trigger an ad-hoc export from the admin UI so I can email current orders now.
2. As an admin, I want the system to automatically email an Excel file of orders on Mon/Wed/Fri at 07:00 EST containing orders since the last export run.
3. As an admin, I want to see a list of past exports (timestamp, recipient, number of orders) so I can audit which orders were sent.
4. As an admin, I want to be able to set the recipient email (a constant configuration or an editable setting) so exports go to the right address.
5. As an admin, I want to be able to set the sequence manually (already supported by `Sequence`/coupon logic) but not cause export duplication; exports should be robust to sequence jumps.

---

## Acceptance criteria (executable)

A. Scheduled export:
  - On Mon/Wed/Fri at 07:00 EST the system enqueues a single export job for the export window (the job is scheduled in UTC-equivalent time).
  - The export includes exactly the orders created after the previous export's end_time and up to the scheduled run time (inclusive policy described below).
  - Each order appears in exactly one export: orders exported once are recorded as exported (via ExportedOrder rows) so they are excluded from future exports.

B. Manual export:
  - Admins can visit Admin → Order Exports and run an export for a date range or "since last export". The manual export uses the same atomic reservation behavior and produces the same format.

C. Excel content:
  - The spreadsheet contains one row per order.
  - Columns correspond to the `orders` table columns:
    - `order_confirmation` (formatted 6-digit string)
    - `created_at` (ISO 8601, store in UTC)
    - `first_name`, `last_name`, `email`, `phone`
    - `address1`, `address2`, `city`, `state`, `zip`
    - `promise_fitness_kit_id` (or kit name/slug)
    - `coupon_code_id` (or coupon code string)
    - `description`
    - `id` (order id)
  - Column header row included as first row.

D. Delivery:
  - The mail is sent to the configured recipient(s).
  - The .xlsx is attached with a filename like: `orders_export_YYYYMMDD_HHMMSS_UTC.xlsx`.
  - If the job fails, it retries according to ActiveJob retry rules and notifies admin(s) via logging and an alert (email to admin if configured).

E. Correctness & Robustness:
  - For any cron interval, each order is included in some export exactly once.
  - Export process is atomic regarding reservation of orders to avoid duplicates across concurrently running jobs.
  - If admin resets order confirmation numbering, exports continue to use timestamps and are unaffected.

F. Tests:
  - Unit tests for the builder produce the correct columns and contents for sample orders.
  - Mailer test ensures attachment present and filename format correct.
  - Job tests ensure builder called and email delivered/enqueued.
  - Request spec verifies only authenticated admins can trigger manual exports.
  - Concurrency/integration spec simulates parallel exports and ensures no duplicates.

---

## Clarifying decisions & scheduling logic exploration (you asked me to explore different approaches)

We must guarantee "every order that gets placed is included in an email exactly once". Two major strategies were considered:

A) Confirmation-number-based ranges (store last_confirmation_sent)
- Pros:
  - Simple numeric range logic.
  - Small metadata: `last_confirmation_sent` integer.
- Cons:
  - Admins can change order confirmation numbering (jump generations); that may lead to re-sending or skipping orders because numeric monotonicity is not guaranteed.
  - If confirmation numbers are re-used or reset improperly, it becomes unsafe.
- Verdict: Not chosen as primary due to the admin-reset requirement.

B) Timestamp-based ranges using `created_at` with exported-record tracking (chosen)
- Mechanism:
  - Maintain an `OrderExport` record with `starts_at`, `ends_at`, `scheduled_for` and `status`.
  - To prepare an export run, compute `ends_at = current_scheduled_time` (the time job runs). Compute `starts_at = last_successful_export.ends_at` (or nil => earliest epoch).
  - In a DB transaction: select orders where `created_at > last_export.ends_at` AND `created_at <= ends_at` (strict exclusive lower bound, inclusive upper bound), then create `ExportedOrder` rows referencing those order IDs and link them to the `OrderExport`. This reserves those orders atomically.
  - Build .xlsx from reserved orders and send.
- Pros:
  - Works regardless of how confirmation numbers are changed.
  - With DB transactional reservation, no duplicate exports.
  - Explicit audit trail.
- Cons:
  - Slightly more bookkeeping (new tables).
  - Requires careful handling of clock and timezones. We will store times in UTC and schedule the job in UTC converted from target EST.
- Boundary precision:
  - Use exclusive lower bound (created_at > last_export.ends_at) and inclusive upper bound (created_at <= ends_at).
  - Reason: If last export ended at T, any order with created_at == T was included previously; avoid re-including.
  - Because of sub-second precision issues, store times as full-precision datetimes (Rails handles sub-second if DB supports it). Ensure job timestamp is derived deterministically from the scheduler (e.g., scheduled_for in UTC), not from job start runtime.
- Atomic reservation rule ensures no race: selecting and inserting ExportedOrder rows are done in a single transaction using `SELECT ... FOR UPDATE` semantics or insert based on IDs.

C) Event-sourced or inserted-id-based approach
- Alternative: create a tiny `export_counters` table and mark each order with `exported_in_export_id` (update orders). But updating orders breaks immutability and may not be desirable.
- Verdict: prefer `ExportedOrder` join table to avoid mutating core order data.

D) Deterministic schedule windows (Fri 07:00 → Mon 07:00, Mon 07:00 → Wed 07:00, Wed 07:00 → Fri 07:00)
- Equivalent to timestamp windows described above. We will compute start and end times from last export or fixed schedule windows. Where windows are explicit (e.g., Fri 07:00 - Mon 07:00) minor edge case if export job misses a run — fallback logic: compute `starts_at = last_successful_export.ends_at` rather than relying on exact calendar windows, so missed runs do not lose orders.

Chosen approach summary:
- Use timestamp windows derived from last successful export record. This satisfies "every order included exactly once" and tolerates admin sequence changes.

---

## Data model changes / Additions

1. `order_exports` table (new)
   - Columns:
     - id: bigint (PK)
     - status: string, enum: `pending`, `running`, `succeeded`, `failed`
     - scheduled_for: datetime (UTC) — when this run was supposed to run (useful for scheduled runs)
     - started_at: datetime
     - ends_at: datetime — the inclusive upper bound for included orders
     - created_at: datetime
     - updated_at: datetime
     - recipient: string (email used for this export run; derived from config unless overridden)
     - filename: string (the generated filename)
     - error_message: text (nullable) — store failure text if failed
   - Index: `scheduled_for`, `status`

2. `exported_orders` table (new)
   - Columns:
     - id: bigint (PK)
     - order_export_id: bigint (FK -> order_exports)
     - order_id: bigint (FK -> orders)
     - created_at: datetime
   - Indexes: unique index on `(order_export_id, order_id)` and index on `order_id` to audit quickly.

3. Optional `order_exports` model methods:
   - `reserve_orders!(ends_at:, recipient:)` — atomically build selection and create ExportedOrder entries and set status to `running` when job starts.

Note: We keep the unique constraint on orders.order_confirmation; we don't rely on that for export selection.

---

## API / Services (planned files)

- `app/models/order_export.rb`
  - has_many :exported_orders
  - enum status
  - instance method `reserve_orders!(ends_at:, scope: Order.all)`

- `app/models/exported_order.rb`
  - belongs_to :order_export
  - belongs_to :order

- `app/services/order_export/builder.rb`
  - Public API: `.build_to_tempfile(order_scope_or_array)` or `#build_to_tempfile(orders:)` returns a Tempfile with .xlsx content.
  - Uses `caxlsx` to build sheet with header row and rows per order.
  - Writes to Tempfile in binary and returns it.

- `app/jobs/admin/send_order_export_job.rb`
  - `perform(scheduled_for_utc = Time.current.utc, recipient: DEFAULT_RECIPIENT, manual: false)`
  - Flow:
    1. compute `ends_at = scheduled_for_utc`.
    2. find `last_succeeded = OrderExport.where(status: 'succeeded').order(ends_at: :desc).first`
    3. `starts_at = last_succeeded&.ends_at` (nil => earliest)
    4. Create `OrderExport.create!(status: 'pending', scheduled_for: scheduled_for_utc, ends_at: ends_at, recipient: recipient)` to get export id.
    5. Call `order_export.reserve_orders!(ends_at: ends_at)` inside transaction, which:
       - selects order IDs `where(created_at > starts_at AND created_at <= ends_at)` (careful for starts_at nil).
       - creates `exported_orders` rows for those orders linked to the export; if none found, still proceed (export with 0 rows).
    6. Call `OrderExport::Builder.build_to_tempfile(orders: reserved_orders)` and attach the result to mailer.
    7. Mail via `Admin::OrderExportMailer.export_email(recipient:, file:, filename:, export_id:)` and set export status to succeeded.
    8. On exceptions, set export status to failed and store error_message; re-raise or let ActiveJob retry.

- `app/mailers/admin/order_export_mailer.rb`
  - `export_email(recipient:, file:, filename:, export_id:)` — attaches file and includes export summary.

- `app/controllers/admin/order_exports_controller.rb`
  - `new` form: date range or "since last export", recipient override
  - `create` action: creates OrderExport record, enqueues `Admin::SendOrderExportJob.perform_later(scheduled_for, recipient:, manual:true)` and redirects with notice.

- Scheduler:
  - Use `sidekiq-scheduler` or `whenever` to schedule `Admin::SendOrderExportJob.perform_later(scheduled_for)` on Mon/Wed/Fri 07:00 EST converted to UTC.
  - Implementation detail: compute the next run times in scheduler config or let an orchestrator enqueue the job at the correct UTC time.

---

## Scheduling & Timezone handling (detailed)

- Internal times stored in UTC in DB. The job receives `scheduled_for_utc`.
- A reliable scheduler should convert 07:00 America/New_York (EST/EDT as appropriate) to UTC at scheduling time. Use `tzinfo`/Rails `Time.zone` config:
  - Example Cron: `tz: 'America/New_York'` if your scheduler supports timezone. For Sidekiq-scheduler you can schedule at 07:00 in America/New_York.
- When the job runs:
  - It uses the canonical `scheduled_for_utc` argument the scheduler passed, not `Time.current`—this ensures the window is deterministic.
  - It computes the `ends_at = scheduled_for_utc`.
  - `starts_at` is read from the most recent successful export's `ends_at`. If none exist, `starts_at` is nil (export all).
- Missed runs: If a scheduled run is missed (system down), next run computes `starts_at` from the last successful export, so no orders are lost.
- Edge-case microsecond orders: using DB datetime precision (sub-second if supported) and exclusive lower bound `>` ensures no overlapping inclusion. If an order has `created_at == starts_at` that implies it was included in previous export (or is exactly the same instant) — this behavior is the intended and deterministic tie-breaker.

---

## Security & Authorization

- Only authenticated admin users may view or trigger exports. Controller inherits `Admin::BaseController` which enforces `require_admin`.
- The scheduled job runs using background worker credentials (no UI auth needed).
- Exported file may contain PII (emails, phones). Ensure:
  - Delivery target(s) are secure emails and limited in access.
  - SMTP transport uses TLS.
  - Consider encrypting attachments if required by policy (not in MVP).

---

## Error handling & observability

- Persist `error_message` on `OrderExport` on failure.
- The job should set `status` transitions: `pending` → `running` → `succeeded`/`failed`.
- Add logging lines at critical points: reservation count, builder time, mail deliver success.
- Add alerts (optional): if export job fails 3 times in a row, send an admin alert email to a secondary address.

---

## Migration plan (DB)

1. Create `order_exports` migration:
   - fields per Data Model above.
2. Create `exported_orders` migration:
   - fields per Data Model above.
   - add unique index on `[order_id]`? No — one order can appear in only one export; to enforce uniqueness across exported_orders, add unique index on `order_id` to prevent accidental double-exporting. However, that prevents re-exporting an order in the unlikely event you want to re-send; if you want ability to re-export, instead make unique index on `[order_export_id, order_id]` and enforce reservation logic via transaction. For strict "exactly once" semantics we will add unique index on `order_id` to ensure DB-level guard; manual re-exports require deleting/exported_order adjustments.
   - Rationale: Unique `order_id` in exported_orders provides strong guarantee that an order cannot appear in more than one export. If you prefer to allow re-sends, remove that unique constraint and rely on reservation logic.
   - Recommended: Add unique index on `order_id` to align with acceptance criteria.

Migration note: initialize `order_exports` with a row if you want a seed `last_export` or leave empty. Our migration/seed might set `order_export` initial row with `ends_at = Time.at(0)` if desired.

---

## Tests (detailed)

1. Service tests (`spec/services/order_export/builder_spec.rb`)
   - Give a small set of orders, call `builder.build_to_tempfile(orders:)`, open xlsx (using `caxlsx` or parse binary) and assert:
     - header columns match orders table columns
     - number of rows matches orders
     - certain cell values match expected formatted values (order confirmation padded 6-digits, created_at in UTC).

2. Model tests (`spec/models/order_export_spec.rb`)
   - `reserve_orders!`:
     - Set up orders with created_at values; create a previous successful export and call reserve for new ends_at; assert exported_orders created and that order_ids do not overlap with prior exports.
     - Test transactionality: simulate concurrency by calling reserve twice in threads (or stub locking) and assert uniqueness enforced by DB.

3. Job tests (`spec/jobs/send_order_export_job_spec.rb`)
   - Test that job instantiates an OrderExport, reserves orders, calls builder and mailer. Use mocks for builder and mailer to ensure method calls made.
   - Test failure path: builder raises => OrderExport.status set to 'failed', error logged.

4. Mailer tests (`spec/mailers/admin/order_export_mailer_spec.rb`)
   - Mail contains attachment with expected filename and content-type `application/vnd.openxmlformats-officedocument.spreadsheetml.sheet`.

5. Request tests (`spec/requests/admin_order_exports_spec.rb`)
   - Ensure unauthenticated redirects to admin login.
   - Authenticated admin can `GET new` and `POST create` which enqueues job and redirects with notice.

6. Integration/concurrency test (`spec/integration/order_export_integration_spec.rb`)
   - Simulate multiple scheduled runs/enqueues and ensure no order duplication. This test should not run in transactional fixtures; use truncation or tag it and configure RSpec to run it in non-transactional mode.

7. Scheduler test (if using sidekiq-scheduler)
   - Confirm scheduling configuration triggers the job at configured times (stub scheduler or verify next run schedule).

---

## Tasks (concrete, ordered)

1. Add gem to `Gemfile`:
   - `gem 'caxlsx'`
   - `bundle install`

2. Migrations:
   - Create `order_exports` migration
   - Create `exported_orders` migration with unique index on `order_id`

3. Models:
   - `app/models/order_export.rb`
   - `app/models/exported_order.rb`

4. Service:
   - `app/services/order_export/builder.rb` — .xlsx builder, writes to Tempfile

5. Mailer:
   - `app/mailers/admin/order_export_mailer.rb`
   - Views: `app/views/admin/order_export_mailer/export_email.{text,html}.erb`

6. Job:
   - `app/jobs/admin/send_order_export_job.rb`

7. Admin UI:
   - Routes:
     - `resource :order_export, only: [:new, :create], controller: 'admin/order_exports'`
   - Controller: `Admin::OrderExportsController`
   - View: `app/views/admin/order_exports/new.html.erb`
   - Link on admin dashboard (already added earlier)

8. Scheduler:
   - Configure sidekiq-scheduler / cron to run Mon/Wed/Fri at 07:00 America/New_York and call `Admin::SendOrderExportJob.perform_later(scheduled_for_utc)`

9. Tests:
   - Add the specs described above. Tag integration/concurrency tests appropriately.

10. Documentation:
    - Add README section describing how exports, recipients, and scheduling work.

---

## Implementation details & pseudo-code

Reserve & export flow (pseudo-code):

```ruby
# in Admin::SendOrderExportJob
def perform(scheduled_for_utc = Time.current.utc, recipient: DEFAULT_RECIPIENT)
  ends_at = scheduled_for_utc
  last_success = OrderExport.where(status: 'succeeded').order(ends_at: :desc).first
  starts_at = last_success&.ends_at

  export = OrderExport.create!(status: 'pending', scheduled_for: scheduled_for_utc, ends_at: ends_at, recipient: recipient)

  # reserve orders atomically
  reserved_orders = []
  OrderExport.transaction do
    # Find candidate orders
    scope = Order.all
    scope = scope.where('created_at > ?', starts_at) if starts_at.present?
    scope = scope.where('created_at <= ?', ends_at)
    order_ids = scope.pluck(:id)

    # Create ExportedOrder rows; unique index on order_id prevents duplicates
    order_ids.each_slice(500) do |batch|
      batch.each do |oid|
        ExportedOrder.create!(order_export: export, order_id: oid)
      end
    end
    reserved_orders = Order.where(id: order_ids).order(:created_at)
    export.update!(status: 'running', started_at: Time.current.utc)
  end

  # Build and send
  temp = OrderExport::Builder.build_to_tempfile(orders: reserved_orders)
  filename = "orders_export_#{scheduled_for_utc.strftime('%Y%m%d_%H%M%S')}_UTC.xlsx"
  Admin::OrderExportMailer.with(export_id: export.id).export_email(recipient: recipient, file: temp.path, filename: filename).deliver_now

  export.update!(status: 'succeeded', filename: filename)
rescue => e
  export.update!(status: 'failed', error_message: e.message)
  raise
end
```

Notes:
- Use batched inserts for performance on large exports.
- Use transaction with attempted creation of ExportedOrder rows to ensure unique order-level guarantee. If a `ExportedOrder` unique constraint violation occurs, treat as concurrent reservation and handle gracefully by reloading chosen order IDs.
- Use `Tempfile` for file creation to avoid memory overhead. Ensure to `close/unlink` the tempfile post-deliver (mailer attach reads file contents).

---

## TODOs & follow-ups I can implement for you
If you want I will:
1. Add the migration files, models, builder, mailer, job, admin controller and views.
2. Add the `caxlsx` gem line to the `Gemfile`.
3. Implement the RSpec tests described (unit, job, mailer, request, integration).
4. Configure sample scheduler config (sidekiq-scheduler cron snippet) for Mon/Wed/Fri 07:00 America/New_York -> corresponding UTC times.
5. Wire admin setting (single constant in `config/initializers/order_exports.rb` or a small `Setting` model) for the default recipient.

Please confirm:
- Use of `caxlsx` is acceptable (I will add the gem).
- You want the DB-level uniqueness guard on exported orders (unique index on `order_id`) — confirm yes/no. (Default: **yes** to enforce exactly-once.)
- I should implement scheduled job via `sidekiq-scheduler` or using system cron/`whenever`? (Default: I'll provide sidekiq-scheduler snippet, but job uses ActiveJob so you can adopt any scheduler.)

Once you confirm these three items I will proceed to create the code artifacts and tests (model migrations + services + tests) following this spec.