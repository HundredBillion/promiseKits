promisekits/specs/005-order-export/tasks.md#L1-300
# Tasks: Feature 005 — Order Export & Email (.xlsx)

Meta
- Feature: Order Export & Email (.xlsx)
- Spec: `specs/005-order-export/spec.md`
- Plan: `specs/005-order-export/plan.md`
- Owner: (assign an engineer)
- Branch: `005-orders-export`
- Goal: Implement scheduled (Mon/Wed/Fri 07:00 America/New_York) and ad-hoc admin-triggered exports that produce an `.xlsx` attachment emailed to a configured recipient, guaranteeing each Order is exported exactly once.

How to use this file
- Tasks are ordered top-to-bottom. Each task lists:
  - ID, title
  - Description / acceptance
  - Files to change/create (exact paths)
  - Dependencies (task IDs)
  - [P] marks tasks safe to run in parallel
  - Estimated time (rough)
- After completing a task, update status in a tracking board and run the associated tests.

Prerequisites
- You are on feature branch `005-orders-export` (already created).
- Run `bundle install` after Gem changes.
- Database migrations will be applied before running integration tests.

Phases
- Phase 0: Infra & deps
- Phase 1: Schema & models
- Phase 2: Builder, job, mailer
- Phase 3: Admin UI & routes
- Phase 4: Scheduler & ops
- Phase 5: Tests, docs & cleanup
- Phase 6: Release checklist

-----------------------
PHASE 0 — INFRA & DEPENDENCIES
-----------------------

T0.01 — Add spreadsheet gem to Gemfile
- Description: Add `caxlsx` (or chosen version) to the Gemfile and run `bundle install`.
- Files:
  - `Gemfile`
  - `Gemfile.lock` (after bundling)
- Acceptance:
  - `bundle install` completes; `caxlsx` available.
- Dependencies: none
- Est: 10–30m

T0.02 — Add scheduler config example (if missing)
- Description: Add or ensure `config/sidekiq_scheduler.yml` has the Mon/Wed/Fri entry (tz aware).
- Files:
  - `config/sidekiq_scheduler.yml`
- Acceptance:
  - Contains cron entry for `Admin::SendOrderExportJob` with `tz: 'America/New_York'`.
- Dependencies:
  - T0.01 (optional)
- Est: 10m

-----------------------
PHASE 1 — SCHEMA & MODELS
-----------------------

T1.01 — Create migration: `order_exports`
- ID: T1.01
- Title: Add `order_exports` table
- Description:
  - Create migration with columns: `status`, `scheduled_for`, `started_at`, `ends_at`, `recipient`, `filename`, `error_message`, `created_at`, `updated_at`.
  - Add indexes on `scheduled_for` and `status`.
- Files:
  - `db/migrate/XXXX_create_order_exports.rb`
- Acceptance:
  - Migration exists and schema.rb contains `order_exports` with correct columns and indexes.
- Dependencies: T0.01
- Est: 30–60m

T1.02 — Create migration: `exported_orders`
- ID: T1.02
- Title: Add `exported_orders` table
- Description:
  - Create migration with `order_export_id` (FK), `order_id` (FK), `created_at`.
  - Add index on `order_export_id` and unique index on `order_id`.
  - Add foreign keys with `ON DELETE RESTRICT`.
- Files:
  - `db/migrate/XXXX_create_exported_orders.rb`
- Acceptance:
  - Migration exists and schema.rb reflects unique index on `order_id`.
- Dependencies: T1.01
- Est: 30–60m

T1.03 — Add models: `OrderExport` & `ExportedOrder`
- ID: T1.03
- Title: Implement ActiveRecord models and basic methods
- Description:
  - Implement `app/models/order_export.rb` if missing or update existing to include: associations, enum `status`, validations, `.last_successful`, `mark_succeeded!`, `mark_failed!`.
  - Implement `app/models/exported_order.rb` with validations: presence + `validates :order_id, uniqueness: true`.
  - Ensure `exported_orders` association present on `OrderExport`.
- Files:
  - `app/models/order_export.rb`
  - `app/models/exported_order.rb` (or same file)
- Acceptance:
  - Models load; unit tests should be scaffolded.
- Dependencies: T1.01, T1.02
- Est: 60–90m

T1.04 — Implement `reserve_orders!` on `OrderExport`
- ID: T1.04
- Title: Reservation transactional logic
- Description:
  - Implement algorithm (see plan & data-model):
    - Determine `starts_at` from `.last_successful`
    - Select candidate order IDs (created_at > starts_at and <= ends_at)
    - In transaction, update `OrderExport` status to `running`, set `started_at`, `ends_at`
    - Insert `ExportedOrder` rows; batch insertion and handle uniqueness conflicts gracefully (skip conflicts)
    - Return ActiveRecord::Relation of reserved `Order` records ordered by created_at
  - Use bulk `INSERT ... ON CONFLICT DO NOTHING` for Postgres; fallback to per-row create/rescue for SQLite.
- Files:
  - `app/models/order_export.rb` (method implementation)
- Acceptance:
  - Called from job yields consistent reserved set; unit tested.
- Dependencies: T1.03
- Est: 2–4h

T1.05 — Add DB constraint tests (schema spec)
- ID: T1.05
- Title: Validate unique constraint and indexes exist
- Description:
  - Add spec that checks migration created expected indexes/uniqueness constraint (schema spec).
- Files:
  - `spec/models/order_export_spec.rb`
  - `spec/db/schema_spec.rb` or similar
- Acceptance:
  - Tests verify presence of unique index on `exported_orders.order_id`.
- Dependencies: T1.01, T1.02
- Est: 30–60m

-----------------------
PHASE 2 — BUILDER, JOB, MAILER
-----------------------

T2.01 — Verify/Adjust `OrderExport::Builder`
- ID: T2.01
- Title: Builder correctness & robustness
- Description:
  - Ensure `app/services/order_export/builder.rb` builds expected header and row formatting per spec:
    - Columns: `id`, `order_confirmation` (zero-padded 6-digit), `created_at_utc` (ISO8601 UTC), `first_name`, `last_name`, `email`, `phone`, `address1`, `address2`, `city`, `state`, `zip`, `promise_fitness_kit`, `coupon_code`, `description`
  - Ensure Tempfile use, `tmp.binmode`, `package.serialize(tmp.path)` and cleanup advice.
  - Add guard for nil associations.
- Files:
  - `app/services/order_export/builder.rb`
- Acceptance:
  - Unit tests verify header and simple sample rows.
- Dependencies: T1.04
- Est: 1–2h

T2.02 — Mailer: `Admin::OrderExportMailer`
- ID: T2.02
- Title: Implement mailer that attaches .xlsx
- Description:
  - Ensure `app/mailers/admin/order_export_mailer.rb` has `export_email` method that:
    - Attaches file from filepath
    - Uses filename format `orders_export_YYYYMMDD_HHMMSS_UTC.xlsx`
    - Uses proper MIME type
    - Includes summary in body (export_id, scheduled_for, exported_count)
  - Add mailer views for text and HTML.
- Files:
  - `app/mailers/admin/order_export_mailer.rb`
  - `app/views/admin/order_export_mailer/export_email.html.erb`
  - `app/views/admin/order_export_mailer/export_email.text.erb`
- Acceptance:
  - Mailer spec validates attachment presence and filename format.
- Dependencies: T2.01
- Est: 1–2h

T2.03 — Job: `Admin::SendOrderExportJob` orchestration
- ID: T2.03
- Title: Implement/verify Admin job to run a single export
- Description:
  - Confirm job implementation handles:
    - `scheduled_for_utc` parsing
    - create `OrderExport` record status `pending`
    - call `reserve_orders!` with `ends_at`
    - log reserved count
    - call builder to get Tempfile
    - call mailer to deliver synchronously
    - mark succeeded/failed and persist filename/error_message
    - ensure tempfile cleanup in `ensure`
    - retry_on configured (exponential backoff)
  - Add or update job spec for normal and failure flows.
- Files:
  - `app/jobs/admin/send_order_export_job.rb`
  - `spec/jobs/send_order_export_job_spec.rb`
- Acceptance:
  - Job spec ensures builder + mailer are invoked and `order_exports` transitions to succeeded/failed appropriately.
- Dependencies: T2.01, T2.02, T1.04
- Est: 1.5–3h

T2.04 — Mail delivery / SMTP environment doc
- ID: T2.04
- Title: Document SMTP and recipient config
- Description:
  - Update README or `specs/005-order-export/quickstart.md` to show required ENV vars:
    - `ORDER_EXPORT_RECIPIENT` or application config
    - `DEFAULT_FROM_EMAIL`
  - Provide sample config snippet in `config/initializers/order_export.rb` if not present
- Files:
  - `specs/005-order-export/quickstart.md` (placeholder and will be expanded Phase 5)
  - `config/initializers/order_export.rb` (verify existing)
- Acceptance:
  - Admins/devs can set recipient via env or `OrderExport::Config`.
- Dependencies: none
- Est: 30–60m

-----------------------
PHASE 3 — ADMIN UI & ROUTES
-----------------------

T3.01 — Add admin controller actions and form
- ID: T3.01
- Title: Implement Admin → Order Exports UI
- Description:
  - `GET /admin/order_exports/new` shows form with:
    - Option: "Since last export" (default) or explicit `ends_at` date/time (local tz)
    - Recipient override (optional)
  - `POST /admin/order_exports` enqueues `Admin::SendOrderExportJob.perform_later(scheduled_for_utc, recipient:, manual: true)` and redirects with notice.
  - Ensure controller enforces admin-only access (controller inherits `Admin::BaseController`).
- Files:
  - `app/controllers/admin/order_exports_controller.rb`
  - `app/views/admin/order_exports/new.html.erb`
  - `config/routes.rb` (add `resource :order_exports, only: [:new, :create], controller: 'admin/order_exports'`)
- Acceptance:
  - Request spec verifies only admin can access and job gets enqueued with right args.
- Dependencies: T2.03
- Est: 1–2h

T3.02 — Admin index/audit view (optional)
- ID: T3.02
- Title: Add admin listing of past `order_exports`
- Description:
  - Provide a page showing recent exports: timestamp, recipient, number of orders, status, filename, link to download (if you choose to store attachments temporarily).
  - This is optional for MVP, but required by spec's auditability acceptance.
- Files:
  - `app/controllers/admin/order_exports_controller.rb` (index)
  - `app/views/admin/order_exports/index.html.erb`
- Acceptance:
  - Admin can view last N exports.
- Dependencies: T3.01
- Est: 2–3h (optional)

-----------------------
PHASE 4 — SCHEDULER & OPS
-----------------------

T4.01 — Scheduler entry & documentation
- ID: T4.01
- Title: Add schedule for Mon/Wed/Fri 07:00 America/New_York
- Description:
  - Configure `config/sidekiq_scheduler.yml` with cron entry using `tz: 'America/New_York'` to enqueue `Admin::SendOrderExportJob`.
  - Ensure scheduler passes the canonical `scheduled_for_utc` as argument if supported; otherwise job should compute deterministic scheduled_for based on `Time.current.in_time_zone('America/New_York')`.
- Files:
  - `config/sidekiq_scheduler.yml`
  - deployment docs (README/ops)
- Acceptance:
  - Demonstrable cron entry; documented deployment steps to enable scheduler.
- Dependencies: T0.02
- Est: 30–60m

T4.02 — Monitoring & logging hooks
- ID: T4.02
- Title: Add logging and metrics
- Description:
  - Add logs at reservation start/end, builder duration, mail delivery success/failure.
  - Instrument counters: `order_exports.succeeded`, `order_exports.failed`, histogram of `exported_count`.
- Files:
  - `app/jobs/admin/send_order_export_job.rb` (log calls)
  - Monitoring config or initializers (optional)
- Acceptance:
  - Logs contain export ids and counts. Metrics incremented on success/failure (if metrics infra present).
- Dependencies: T2.03
- Est: 1–2h

-----------------------
PHASE 5 — TESTS, DOCS & CLEANUP
-----------------------

T5.01 — Builder unit tests
- ID: T5.01
- Title: Tests for `OrderExport::Builder`
- Description:
  - Test headers, row content, formatting for sample order structs.
  - Test Tempfile returned, file is readable and has expected extension.
- Files:
  - `spec/services/order_export/builder_spec.rb`
- Acceptance:
  - Tests pass on CI.
- Dependencies: T2.01
- Est: 1–2h

T5.02 — Model tests (reservation)
- ID: T5.02
- Title: Tests for `OrderExport#reserve_orders!`
- Description:
  - Test normal reservation scenario with previous successful export.
  - Test boundary conditions (orders exactly at `ends_at`, orders at previous `ends_at`).
  - Concurrency test: simulate two reservation attempts and confirm unique exported_orders constraint prevents duplicates.
- Files:
  - `spec/models/order_export_spec.rb`
- Acceptance:
  - Tests assert no duplicates and correct reserved sets.
- Dependencies: T1.04
- Est: 2–4h

T5.03 — Job & mailer specs
- ID: T5.03
- Title: Job and Mailer test coverage
- Description:
  - Mock builder and mailer calls to test success and failure transitions.
  - Mailer tests check attachments and filename format.
- Files:
  - `spec/jobs/send_order_export_job_spec.rb`
  - `spec/mailers/admin/order_export_mailer_spec.rb`
- Acceptance:
  - All tests pass; job marks succeeded/failed accordingly.
- Dependencies: T2.02, T2.03
- Est: 2–3h

T5.04 — Request/controller tests
- ID: T5.04
- Title: Admin request specs
- Description:
  - Test `new` and `create` controller actions:
    - Only admin allowed.
    - `POST create` enqueues job with proper `scheduled_for_utc` and `recipient`.
- Files:
  - `spec/requests/admin_order_exports_spec.rb`
- Acceptance:
  - Tests validate auth and job enqueue behavior.
- Dependencies: T3.01
- Est: 1–2h

T5.05 — Integration / concurrency test
- ID: T5.05
- Title: End-to-end concurrency/integration test
- Description:
  - Use a test environment that allows concurrent DB connections (non-transactional fixtures).
  - Simulate two jobs attempting to reserve overlapping windows and assert no order duplicated across `exported_orders`.
- Files:
  - `spec/integration/order_export_integration_spec.rb`
- Acceptance:
  - Test demonstrates exactly-once semantics under concurrent reservations.
- Dependencies: T1.04, T2.03, T5.02
- Est: 3–6h

T5.06 — Documentation: quickstart & data-model
- ID: T5.06
- Title: Create/complete `quickstart.md` and `data-model.md`
- Description:
  - Add quickstart instructions for local dev run, how to trigger manual exports, scheduler notes, ENV variables, and troubleshooting.
  - `data-model.md` should document migrations and field rationale (already created).
- Files:
  - `specs/005-order-export/quickstart.md`
  - `specs/005-order-export/data-model.md` (verify and expand)
- Acceptance:
  - README/quickstart contains operational steps for dev and prod.
- Dependencies: all prior tasks
- Est: 1–2h

T5.07 — Accessibility & security review
- ID: T5.07
- Title: Review PII exposure and admin access
- Description:
  - Confirm only admins can trigger/see exports.
  - Confirm recipients are configured securely and use TLS for SMTP.
- Files:
  - `app/controllers/admin/*` (audit)
  - `config/initializers/order_export.rb`
  - `docs/ops.md`
- Acceptance:
  - Security review checklist passed.
- Dependencies: T3.01, T4.01
- Est: 30–60m

-----------------------
PHASE 6 — RELEASE / OPERATIONS
-----------------------

T6.01 — Migration & deploy
- ID: T6.01
- Title: Deploy migrations and enable scheduler
- Description:
  - Run migrations on production/staging.
  - Enable sidekiq-scheduler / cron job and monitor first runs.
  - Ensure email provider settings are correct.
- Files:
  - Deployment/ops runbook
- Acceptance:
  - Scheduler enqueues job at the first scheduled time; exports run and mail arrives.
- Dependencies: All code tasks complete + CI green
- Est: Depends on org deploy cadence

T6.02 — Post-release verification
- ID: T6.02
- Title: Verify exports for a week and monitor alerts
- Description:
  - Confirm scheduled exports run on Mon/Wed/Fri.
  - Review `order_exports` rows and email receipts.
  - Address any failures.
- Acceptance:
  - No duplicates observed; logs and metrics normal.
- Dependencies: T6.01
- Est: 1 week of monitoring

-----------------------
PARALLEL TASKS (can be done concurrently)
- T0.01 [P] (gem add) — prerequisite for builder code run, but can be implemented while waiting for review.
- T1.01 & T1.02 [P] — migrations can be authored in parallel but apply in order.
- T2.01 [P] & T2.02 [P] — builder and mailer implementations can be worked on in parallel once migrations & models are sketched.
- T5.01, T5.02, T5.03 [P] — tests for different layers can be authored in parallel.

-----------------------
VALIDATION CHECKPOINTS
- After T1.02 (migrations): run `rails db:migrate:status` and `rails db:schema:dump` to confirm schema.
- After T1.04 (reserve implementation): run unit tests for model reservation and run a local job with a small dataset to confirm exported rows created.
- After T2.03 (job): simulate a job run locally in development and assert email delivered to dev mailbox with expected filename and content format.
- After T5.05 (integration): run concurrency test in a non-transactional CI job to verify correctness.

-----------------------
NOTES & IMPLEMENTATION TIPS
- Use `INSERT ... ON CONFLICT DO NOTHING` for Postgres bulk insertion; fall back to per-row `create!` with unique-rescue on SQLite.
- For mail attachments: prefer reading file bytes (`File.binread(tmp.path)`) when attaching to ActionMailer to avoid file descriptor issues.
- Ensure time conversions: admin UI inputs parsed in `OrderExport::Config.timezone` and converted to UTC for the job.
- Keep error messages succinct and actionable — persist full exception messages and shortened stack traces in logs.
- If exports risk exceeding attachment size limits, consider switching to S3 upload + email with signed URL (not in MVP).

-----------------------
TASK TRACKING TEMPLATE (copy to issue tracker)
- Title: [T1.04] Implement OrderExport#reserve_orders! (Reservation transaction)
- Description: (from tasks.md)
- Acceptance Criteria: (from task)
- Files: `app/models/order_export.rb`
- Estimate: 3h
- Assignee:
- Status: TODO / IN PROGRESS / REVIEW / DONE

-----------------------
End of tasks.md
