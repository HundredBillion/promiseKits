# Quickstart — Order Export & Email (.xlsx)

This quickstart helps you run and test the Order Export feature locally and in staging. It assumes you're working on the `005-orders-export` feature branch and have applied the migrations that add `order_exports` and `exported_orders`.

Contents
- Prerequisites
- Configuration (env / initializer)
- Migrate database
- Run a manual export (dev)
- Trigger an ad-hoc export from the Admin UI
- Test the builder and mailer
- Verify DB records and audit trail
- Scheduler (production/staging)
- Troubleshooting & tips

---

## 1) Prerequisites

- Ruby / Rails (match repository versions)
- Bundler installed
- Local database configured (SQLite for dev/test or PostgreSQL for staging)
- Mailer configuration (SMTP) for dev or a mail catcher (letter_opener / MailHog)

Recommended local gems (already added by the feature):
- `caxlsx` — .xlsx generation
- `sidekiq` + `sidekiq-scheduler` (for scheduled runs, optional in dev)

---

## 2) Configuration

Main settings are read from `config/initializers/order_export.rb` and environment variables.

Important environment variables:
- `ORDER_EXPORT_RECIPIENT` — default recipient email used by scheduled exports (recommended)
- `DEFAULT_FROM_EMAIL` — default From address for emails

Check `OrderExport::Config` (initializer) for:
- `recipient_email`
- `timezone` (should be `America/New_York` by default)
- `schedule_hour`, `schedule_minute` (if relevant)

If you need to override the default recipient in an ad-hoc request, use the admin UI form or pass `recipient:` to the job.

---

## 3) Migrate the database

After pulling the branch, run:

```bash
bundle install
bin/rails db:migrate
```

Notes:
- The migrations create `order_exports` and `exported_orders`.
- The `exported_orders.order_id` unique index enforces exactly-once semantics. If your DB already has conflicting indexes from earlier runs, tidy them up before re-running migrations.

---

## 4) Run a manual export (development)

There are two common ways to run a manual export locally:

A) Synchronous run in a console (recommended for local dev)

```bash
# Open a Rails console
bin/rails console

# Inside console, run:
scheduled_for = Time.current.utc
recipient = ENV['ORDER_EXPORT_RECIPIENT'] || 'you@example.com'
Admin::SendOrderExportJob.perform_now(scheduled_for, recipient: recipient, manual: true)
```

This will:
- create an `OrderExport` record (status `pending` -> `running`)
- reserve orders with created_at in the computed window
- build an .xlsx into a Tempfile
- send the mail synchronously
- mark the `OrderExport` as `succeeded` or `failed`

B) Background worker style (if you run Sidekiq locally)

```bash
# start a Sidekiq worker
bundle exec sidekiq

# enqueue the job (from rails console or HTTP controller action):
Admin::SendOrderExportJob.perform_later(Time.current.utc, recipient: 'you@example.com', manual: true)
```

If you run Sidekiq in dev, you can use `deliver_now` inside the job (the job calls mailer synchronously) so you get immediate send behavior.

---

## 5) Trigger ad-hoc export from the Admin UI

Open the admin UI (e.g., `http://localhost:3000/admin`) and navigate:
- Admin → Order Exports → New

Form options:
- Ends at: local datetime in `America/New_York`. By default the form shows current local time.
- Recipient: optional override; if blank, the system default is used.
- You can select "Since last export" by leaving `ends_at` at default or using the provided button.

Submitting the form will enqueue the job and redirect you with a notice.

---

## 6) Test builder and mailer (unit tests)

Builder tests (example):
- File: `spec/services/order_export/builder_spec.rb`
- Create a few small Order-like structs or factory records; call:

```ruby
tmp = OrderExport::Builder.build_to_tempfile(orders: orders)
expect(tmp).to be_a(Tempfile)
expect(File.size(tmp.path)).to be > 0
# Optionally: open the xlsx using an XML parser / caxlsx reader to inspect header row
```

Mailer tests (example):
- File: `spec/mailers/admin/order_export_mailer_spec.rb`

Create a small Tempfile with binary content (or use builder), then:

```ruby
mail = Admin::OrderExportMailer.export_email(
  recipient: 'test@example.com',
  file_path: tmp.path,
  filename: 'orders_export_test.xlsx',
  exported_count: 2
)
expect(mail.attachments.count).to eq(1)
expect(mail.subject).to match(/\d+ Orders/)
```

Run the specs:

```bash
bundle exec rspec spec/services/order_export/builder_spec.rb
bundle exec rspec spec/mailers/admin/order_export_mailer_spec.rb
```

---

## 7) Verify DB records & audit trail

After a successful run, inspect the database:

- `order_exports` — each run has:
  - status (succeeded/failed)
  - scheduled_for (UTC)
  - started_at, ends_at
  - recipient, filename, error_message

- `exported_orders` — one row per order exported:
  - `order_id` and `order_export_id` link the order to the run

Queries:

```sql
SELECT id, status, scheduled_for, filename, error_message FROM order_exports ORDER BY created_at DESC LIMIT 10;
SELECT eo.order_id, eo.order_export_id FROM exported_orders eo ORDER BY eo.created_at DESC LIMIT 50;
```

In Rails console:

```ruby
OrderExport.order(created_at: :desc).limit(10).each { |e| puts "#{e.id} #{e.status} #{e.scheduled_for} #{e.reserved_count}" }
ExportedOrder.limit(50).map(&:to_s)
```

---

## 8) Scheduler (production / staging)

Schedule configuration is in `config/sidekiq_scheduler.yml`. Example entry:

```yaml
send_order_export_job:
  cron: "0 7 * * MON,WED,FRI"
  tz: "America/New_York"
  class: "Admin::SendOrderExportJob"
  queue: "default"
  description: "Scheduled export of orders and email (Mon/Wed/Fri at 07:00 America/New_York)"
  enabled: true
  args: []
```

Important:
- The scheduled job should pass a canonical `scheduled_for_utc` argument if your scheduler supports it; otherwise the job computes a deterministic `scheduled_for` using the scheduler time converted to UTC.
- Use `tz: "America/New_York"` (or your scheduler equivalent) to handle DST correctly.
- Ensure your Sidekiq/worker process has access to the same environment variables (recipient, mail settings).

---

## 9) Troubleshooting & tips

- Duplicate exported orders
  - The DB unique index on `exported_orders.order_id` enforces exactly-once semantics.
  - If you see unique index violations, ensure no prior manual changes were made to `exported_orders`.
  - For Postgres, the reservation method uses `INSERT ... ON CONFLICT DO NOTHING`. For SQLite the code falls back to per-row inserts with rescue.

- Missing attachments in email
  - Ensure builder returns a valid Tempfile and its path is passed correctly to mailer.
  - Check mailer logs for warnings about "Attachment not found".

- Large export sizes
  - If attachments exceed SMTP limits, consider uploading the file to a secured storage (S3) and emailing a pre-signed download link instead.

- Running migrations twice / index errors
  - If `rails db:migrate` raises an index-already-exists error (local dev), drop the dev DB and re-create it, or inspect your `db/migrate` history to avoid duplicate migration definitions. Example:

```bash
bin/rails db:drop db:create db:migrate
```

- Logs and observability
  - The job logs reserved counts, builder time, and mail deliver success/failure. Add metrics if you have a monitoring stack (counters for succeeded/failed exports).

---

## 10) Admin repair & re-export (operation)

The system enforces exactly-once exports by default. If you need to re-send a previously exported order:
- Manually delete the corresponding `exported_orders` rows for those `order_id`s (careful — this alters audit trail).
- OR add an admin-only re-export/repair task that can create a new `order_exports` run and re-attach orders explicitly.

Prefer an audit-backed repair flow to manual DB edits.

---

If you want, I can:
- Add RSpec examples for builder/mailer/job files,
- Implement the admin index/audit view to download past generated files (optionally store attachments),
- Add a rake task to backfill or archive old `order_exports`.

Which one should I do next?