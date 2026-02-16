# Research — Order Export & Email (.xlsx)

This research document consolidates technical investigation and choices for implementing the Order Export feature described in `spec.md`. It covers choices for .xlsx generation, background job/scheduler architecture, database reservation patterns, concurrency-safe insertion strategies, timezones and scheduling, mail delivery considerations, tests and validation approaches, and operational/observability recommendations.

---

## Goals of research
- Choose a robust, maintained library for producing `.xlsx` files in Rails.
- Identify safe, scalable ways to reserve orders atomically and avoid duplicate exports.
- Decide scheduler patterns for Mon/Wed/Fri 07:00 America/New_York and deterministic windows.
- Explore mailer attachment handling and large-file considerations.
- Produce actionable recommendations (migration, DB indexes, code patterns, tests).

---

## .xlsx generation: library options and recommendation

Candidates:
- `caxlsx` (recommended): maintained fork/compat of `axlsx`. API: workbook/worksheet/rows, supports styles, serializes to file path. Common in Ruby/Rails ecosystems.
  - Pros: widely used, straightforward, familiar Axlsx API, supports writing to disk (Tempfile) and streaming patterns.
  - Cons: building very large sheets can use memory; must manage batching and Tempfile use.
- `write_xlsx` (C extension via JRuby/other): less common in Rails apps.
- CSV alternative: produce CSV if Excel features are unnecessary; smaller dependency but spec requires `.xlsx`.

Recommendation:
- Use `caxlsx`. Write to `Tempfile` and call `package.serialize(tmp.path)`. Rewind and attach. For large exports, ensure orders are fetched in batches and use the builder to append rows iteratively. Monitor memory use and prefer filesystem-backed Tempfile.

Version guidance:
- Pick the latest stable `caxlsx` compatible with the project's Ruby/Rails versions (verify Gemfile.lock compatibility). Add explicit version in Gemfile (e.g., `gem 'caxlsx', '~> X.Y'`) after checking current project constraints.

Builder design notes:
- Expose `OrderExport::Builder.build_to_tempfile(orders:, sheet_name: 'Orders')` where `orders` is an Enumerable or ActiveRecord::Relation.
- Ensure builder does minimal per-row allocations and converts values to strings consistently:
  - `order_confirmation` -> `sprintf('%06d', value.to_i)` or nil
  - `created_at` -> `created_at.utc.iso8601`
- Create header row explicitly.
- Use `tmp.binmode` and `tmp.rewind` before returning.

---

## Background job and scheduling

Job orchestration:
- Use an `Admin::SendOrderExportJob < ApplicationJob` to orchestrate:
  1. Compute `ends_at = scheduled_for_utc` (job receives canonical scheduled time).
  2. `reserve_orders!(ends_at:)` on `OrderExport` to atomically claim orders.
  3. Use builder to create Tempfile `.xlsx`.
  4. Use `Admin::OrderExportMailer` to deliver attachment (synchronous `deliver_now` inside job).
  5. Mark export succeeded/failed and store metadata.

Retry behavior:
- Use `retry_on` on job or rely on adapter defaults. Persist failure messages in `OrderExport` and re-raise after marking failed to let ActiveJob/Sidekiq retry.

Scheduler:
- Use `sidekiq-scheduler` (recommended when Sidekiq is in use) with timezone support:
  - Example (sidekiq-scheduler):
    ```
    Admin::SendOrderExportJob:
      cron: "0 7 * * MON,WED,FRI"
      class: Admin::SendOrderExportJob
      tz: "America/New_York"
    ```
- Important: scheduler must pass the canonical `scheduled_for_utc` argument. If `sidekiq-scheduler` cannot pass arg, compute `scheduled_for` inside job from `Time.current.in_time_zone('America/New_York')` and convert to UTC deterministically — but preferred approach is scheduler passing the intended scheduled time (prevents drift and missed-run ambiguities).

Manual exports:
- Admin UI enqueues the job with `scheduled_for_utc = Time.current.utc` (or parsed ends_at converted from configured tz).

---

## Time ranges and timezone handling

Principles:
- Store times in UTC in DB.
- Compute windows using `created_at` in UTC:
  - Inclusive end: `created_at <= ends_at`
  - Exclusive lower bound: `created_at > starts_at` (where `starts_at` is last successful run's `ends_at`)
- This deterministic tie-breaker prevents overlap/duplicate inclusion.

Scheduler conversion:
- Use `tzinfo`/Rails `Time.zone` when parsing admin-provided local times.
- For scheduler cron entries that accept `tz`, use that facility. If not, compute UTC equivalents during schedule generation.

Edge cases:
- Missed runs: next run uses last_successful.ends_at as start, so orders are not lost.
- Sub-second precision: rely on DB precision; rails `created_at` usually supports microseconds in modern DBs. Lower-bound exclusive avoids boundary duplicates.

---

## Reservation strategy and DB-level enforcement

Approach:
- Create `order_exports` record (status `pending`), then `reserve_orders!(ends_at:)`.
- Reservation transaction:
  1. Determine `starts_at` from last successful export (`OrderExport.last_successful&.ends_at`).
  2. Query candidate order IDs ordered by `created_at`.
  3. Inside `OrderExport.transaction`:
     - Update this `OrderExport` to `running`, set `started_at`, `ends_at`.
     - Insert `ExportedOrder` rows for each candidate `order_id`.
     - Handle duplicates: if unique constraint triggers (concurrent insert), skip those IDs; record successfully inserted IDs.
- Return ActiveRecord::Relation of reserved Orders (ordered).

DB uniqueness enforcement:
- Add unique index on `exported_orders.order_id` to enforce exactly-once semantics.
- For bulk insertion, use `INSERT ... ON CONFLICT DO NOTHING` (Postgres) or batch `INSERT` with rescue per-row on SQLite.

Implementation notes:
- Prefer bulk `INSERT ... ON CONFLICT DO NOTHING` when using Postgres for performance:
  ```
  INSERT INTO exported_orders (order_export_id, order_id, created_at, updated_at)
  VALUES (1, 101, now(), now()), (1,102, now(), now()) 
  ON CONFLICT (order_id) DO NOTHING;
  ```
- After the insert, query which ids exist for this `order_export_id` to determine reserved set.

Concurrency considerations:
- Without DB-level unique index, two jobs could both add the same `order_id`. With the unique index, one insert will succeed and the other will be skipped/raise — handle gracefully.
- Use row-level transaction boundaries and small batch sizes to reduce lock contention.

---

## Mail delivery & large attachments

Delivery method:
- Use Action Mailer. Attach Tempfile contents as:
  ```
  attachments[filename] = File.read(tmp.path) # or use attachments.inline with file
  ```
- Prefer `deliver_now` inside the job to ensure retries on failure (or `deliver_later` and monitor delivery exceptions), but deliver_now inside background job is common.

Attachment size:
- For very large exports, be mindful of SMTP provider limits. Options:
  - Split into smaller attachments (not desired).
  - Upload file to secure storage (S3) and email a time-limited download link instead of attachment.
- For MVP, assume typical export sizes < provider limit (e.g., <25MB). Document and monitor.

PII and security:
- Exports contain PII (emails, phones, addresses). Ensure:
  - Recipient list is small and configured via secure env/config.
  - SMTP transport uses TLS.
  - Optionally encrypt attachments (PGP) if policy requires.
  - Log minimal PII; store only meta in `order_exports`.

---

## Testing & validation

Unit tests:
- Builder: test headers, record formatting, file exists and is valid `.xlsx` (optionally parse with `caxlsx` reader or open xml validations).
- OrderExport model: test `reserve_orders!` behavior with sample orders and prior successful exports.
- ExportedOrder uniqueness behavior: try concurrent inserts in tests (use DB-level tests or integration test pattern).

Job tests:
- `Admin::SendOrderExportJob`:
  - Mock `OrderExport::Builder` and `Admin::OrderExportMailer` to ensure they are called with expected arguments.
  - Test success and failure flows: `mark_succeeded!` and `mark_failed!`.

Integration tests:
- Simulate parallel reservation (use threads or two transactions with distinct connections) to verify no duplicates.
- End-to-end: create orders, run job, assert file attached to outgoing mail and `exported_orders` rows created.

Manual QA:
- Create dev/test exports and open `.xlsx` in Excel/LibreOffice for format verification.

---

## Operational considerations & runbook

Monitoring:
- Log exported counts and export duration.
- Track metrics:
  - exports.succeeded, exports.failed (counter)
  - exported_orders.count (histogram)
- Alert on repeated failures (e.g., 3 failed runs in a row).

Retention & cleanup:
- Keep `order_exports` and `exported_orders` for required audit window.
- Provide Rake tasks for archiving/cleanup.

Error recovery:
- If an export fails after reservation but before sending, reserved orders are still marked exported; decide whether to:
  - Rollback exported rows on certain failure types (dangerous for exactly-once requirement).
  - Leave rows reserved and re-run a repair process to re-create the file or push to admin retry action (preferred: keep reservation and provide an admin retry that re-builds and re-sends without re-reserving).

Troubleshooting:
- Common causes: SMTP issues, builder errors (unexpected nils), DB unique constraint violations due to manual exported_orders changes.
- Provide an admin page listing `order_exports` and their `error_message` to allow debugging.

---

## Alternatives and tradeoffs

Alternative: mark `orders` row with `exported_in_export_id` instead of a join table
- Pros: fewer joins, simpler lookup
- Cons: mutates core `orders` table (may violate design constraints), more intrusive schema change, backfill complexities.

Alternative: use event-sourcing / messaging to stream exported events
- Pros: eventual consistency, integrates with analytics
- Cons: more complexity; spec requires audit trail per export run and atomicity.

Alternative: no DB uniqueness, rely solely on reservation transaction
- Pros: simpler migration
- Cons: weaker guarantee; potential duplicates if bugs or manual changes occur.

Given acceptance criteria, join table + DB uniqueness chosen as the strongest, simplest-to-reason-about approach.

---

## Recommended next steps
1. Add `caxlsx` to `Gemfile` and run CI to verify compatibility.
2. Add migrations with unique index on `exported_orders.order_id`.
3. Harden `OrderExport#reserve_orders!` to use batched `INSERT ... ON CONFLICT DO NOTHING` for Postgres and robust per-row rescue for SQLite.
4. Implement builder tests and mailer tests.
5. Configure sidekiq-scheduler (or equivalent) to pass canonical `scheduled_for_utc`.
6. Implement monitoring instrumentation and admin UI to surface `order_exports` and their statuses.

---

## References & notes
- Postgres `INSERT ... ON CONFLICT DO NOTHING` pattern for bulk inserts.
- `caxlsx` usage pattern: `package = Axlsx::Package.new; package.workbook.add_worksheet { |s| s.add_row([...]) }; package.serialize(path)`.
- Time handling: prefer `scheduled_for_utc` argument and `Time.zone('America/New_York')` for conversions in UI parsing.
