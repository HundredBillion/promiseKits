# Implementation Plan: Orders Export & Email (.xlsx)

**Branch**: `005-orders-export` | **Date**: 2026-02-15 | **Spec**: specs/005-order-export/spec.md  
**Input**: Feature specification from `/specs/005-order-export/spec.md`

**Note**: This plan implements the Order Export feature described in the spec: scheduled and ad-hoc exports of orders to an Excel (.xlsx) file, emailed to a configured recipient, with an auditable and atomic reservation mechanism that guarantees each order is exported exactly once.

## Summary

Implement a robust background export system that:
- Produces an Excel (.xlsx) spreadsheet that contains one row per order with columns corresponding to the `orders` table and selected related fields.
- Sends the spreadsheet as an email attachment to a configured recipient on a schedule (Mon/Wed/Fri at 07:00 America/New_York) and supports admin-triggered ad-hoc exports via the admin UI.
- Guarantees each Order is included in exactly one export using a reservation mechanism (new `order_exports` and `exported_orders` tables) with DB-level uniqueness and transactional reservation to avoid duplicates across concurrent jobs.
- Uses the `caxlsx` gem to build .xlsx files into a Tempfile, ActiveJob (Sidekiq optional) to run background jobs, and an `Admin::SendOrderExportJob` that orchestrates reservation → build → email → status transitions.
- Persists audit information in `order_exports` and `exported_orders` so administrators can review exported runs, counts, recipients, filenames, and error messages.

This plan covers technical choices, data model changes, migrations, services (builder), job orchestration, mailer integration, admin UI endpoints, scheduler configuration, and tests (unit, job, mailer, request, and concurrency/integration tests).

## Technical Context

Language/Version:
- Ruby (Rails application). Use the application's current Rails version (the repository is a Rails app). Code should remain idiomatic to Rails 7.x+ conventions.

Primary Dependencies:
- `caxlsx` gem for .xlsx generation (Axlsx-compatible API).
- Active Job with the existing adapter (Sidekiq recommended in production; code uses ActiveJob APIs so it is adapter agnostic).
- Action Mailer for email delivery.
- Standard Rails stack for models/controllers/views.
- Optional: `sidekiq-scheduler` (or equivalent scheduler) for cron-like scheduling in production.

Storage:
- Relational DB used by the app (the code supports SQLite and Postgres). Times are stored in UTC. The plan adds two tables:
  - `order_exports` (records of each export run).
  - `exported_orders` (join rows linking orders to a specific export).
- Database-level unique index on `exported_orders.order_id` is recommended to enforce "exactly once" semantics.

Testing:
- RSpec for unit and integration tests (existing project test conventions apply).
- Tests to add:
  - Service spec for the builder (verify header columns, row contents, formatting).
  - Model spec for `OrderExport#reserve_orders!` (transactionality and uniqueness conflict handling).
  - Job spec for `Admin::SendOrderExportJob` (reservation, builder invocation, mailer call).
  - Mailer spec for attachment presence and filename format.
  - Request/auth spec for admin UI protection.
  - Integration/concurrency spec to simulate parallel reservations and ensure no duplicates (non-transactional/truncation DB or dedicated environment).

Target Platform:
- Backend Rails application running in the environment currently used by the repo. Scheduler must be able to run jobs in the application's timezone conversion (America/New_York for schedule conversion).

Project Type:
- Web application (Rails backend with admin UI). All new files are placed under `app/models`, `app/services`, `app/jobs`, `app/mailers`, `app/controllers/admin`, and `spec/*`.

Performance Goals:
- Typical export frequency is low (three times per week); performance focus is correctness and atomic reservation. Builder should support batching/incremental insertion of ExportedOrder rows for large exports to avoid DB timeouts.
- Memory: builder uses Tempfile, not holding entire file in memory when attaching.

Constraints:
- Exports must be deterministic with respect to scheduling: job must accept a canonical `scheduled_for_utc` so export windows are deterministic regardless of job run time.
- Use created_at timestamp windows for selection (exclusive lower bound, inclusive upper bound) to avoid duplication across consecutive runs.
- Admin re-sequencing of `order_confirmation` must not affect selection logic — use timestamps and exported_records instead.

Scale/Scope:
- Designed for weekly to near-real-time ad-hoc exports; should handle thousands of orders per run with batched DB operations.

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

[Gates determined based on constitution file]

## Project Structure

### Documentation (this feature)

```text
specs/[###-feature]/
├── plan.md              # This file (/speckit.plan command output)
├── research.md          # Phase 0 output (/speckit.plan command)
├── data-model.md        # Phase 1 output (/speckit.plan command)
├── quickstart.md        # Phase 1 output (/speckit.plan command)
├── contracts/           # Phase 1 output (/speckit.plan command)
└── tasks.md             # Phase 2 output (/speckit.tasks command - NOT created by /speckit.plan)
```

### Source Code (repository root)
<!--
  ACTION REQUIRED: Replace the placeholder tree below with the concrete layout
  for this feature. Delete unused options and expand the chosen structure with
  real paths (e.g., apps/admin, packages/something). The delivered plan must
  not include Option labels.
-->

```text
# [REMOVE IF UNUSED] Option 1: Single project (DEFAULT)
src/
├── models/
├── services/
├── cli/
└── lib/

tests/
├── contract/
├── integration/
└── unit/

# [REMOVE IF UNUSED] Option 2: Web application (when "frontend" + "backend" detected)
backend/
├── src/
│   ├── models/
│   ├── services/
│   └── api/
└── tests/

frontend/
├── src/
│   ├── components/
│   ├── pages/
│   └── services/
└── tests/

# [REMOVE IF UNUSED] Option 3: Mobile + API (when "iOS/Android" detected)
api/
└── [same as backend above]

ios/ or android/
└── [platform-specific structure: feature modules, UI flows, platform tests]
```

**Structure Decision**: Use the existing Rails application layout. Add files under these paths:

- Models and DB:
  - `db/migrate/XXXX_create_order_exports.rb`
  - `db/migrate/XXXX_create_exported_orders.rb`
  - `app/models/order_export.rb`
  - `app/models/exported_order.rb` (can be defined in the same file as `OrderExport` or separate)

- Services:
  - `app/services/order_export/builder.rb` (xlsx builder using `caxlsx`)

- Jobs:
  - `app/jobs/admin/send_order_export_job.rb` (or update existing job)

- Mailers & Views:
  - `app/mailers/admin/order_export_mailer.rb`
  - `app/views/admin/order_export_mailer/export_email.html.erb`
  - `app/views/admin/order_export_mailer/export_email.text.erb`

- Admin UI:
  - `app/controllers/admin/order_exports_controller.rb`
  - `app/views/admin/order_exports/new.html.erb` (ad-hoc export form)
  - Add admin route: `resource :order_exports, only: [:new, :create], controller: 'admin/order_exports'` in `config/routes.rb`

- Scheduler config:
  - `config/sidekiq_scheduler.yml` (or equivalent cron config) to schedule `Admin::SendOrderExportJob` on Mon/Wed/Fri 07:00 America/New_York

- Specs:
  - `spec/services/order_export/builder_spec.rb`
  - `spec/models/order_export_spec.rb`
  - `spec/jobs/send_order_export_job_spec.rb`
  - `spec/mailers/admin/order_export_mailer_spec.rb`
  - `spec/requests/admin_order_exports_spec.rb`
  - `spec/integration/order_export_integration_spec.rb` (concurrency)

These paths map directly to the project’s existing Rails layout and adhere to the spec’s auditability and atomic reservation requirements.

## Complexity Tracking

> **Fill ONLY if Constitution Check has violations that must be justified**

| Violation | Why Needed | Simpler Alternative Rejected Because |
|-----------|------------|-------------------------------------|
| [e.g., 4th project] | [current need] | [why 3 projects insufficient] |
| [e.g., Repository pattern] | [specific problem] | [why direct DB access insufficient] |
