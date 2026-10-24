# Order and export reliability Technical Spec

> **For agentic workers:** REQUIRED SUB-SKILL: Use dmi-superpowers:executing-plans to implement this TSP task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Fix the findings in issue #28 and open a verified PR.

**Architecture:** Preserve the Rails interfaces where possible. Put data invariants in the database, put public and admin detail access at distinct controller seams, persist export identity across retries, and use Solid Queue for recurring and ad hoc work.

**Tech Stack:** Rails 8.1.1, Ruby 3.4, SQLite test, PostgreSQL production, Active Job, Solid Queue 1.3.1, Minitest.

## Global Constraints

- Preserve existing customer orders and coupons; fail a migration with a clear duplicate report if manual reconciliation is required.
- No automatic email resend after an SMTP delivery exception.
- Keep public order confirmation usable without private details.
- Compose and Kamal must each have a Solid Queue worker, with only one production schedule per task.

---

### Task 1: Restore a test runner with nonzero tests

**Blocked by:** None

**Files:** Modify `Gemfile`, `Gemfile.lock`; verify `test/test_helper.rb` and a focused existing test.

**Interfaces:** Produces a working `RBENV_VERSION=3.4.5 bin/rails test test/models/order_test.rb` command.

- [ ] Pin `minitest` to `~> 5.25` because `test/test_helper.rb` requires `minitest/mock`, missing in locked 6.0.1. Run `RBENV_VERSION=3.4.5 bundle install`.
- [ ] Run the focused test command. Confirm more than zero tests execute; distinguish baseline failures from new failures.
- [ ] Commit the dependency correction.

### Task 2: Protect order details and admin expiry

**Blocked by:** Task 1

**Files:** Modify `app/views/orders/show.html.erb`, `app/controllers/admin/base_controller.rb`, `app/views/admin/coupon_codes/index.html.erb`, `config/routes.rb`; create `app/controllers/admin/orders_controller.rb`, `app/views/admin/orders/show.html.erb`; test `test/controllers/orders_controller_test.rb`, `test/controllers/admin/base_controller_test.rb`, `test/controllers/admin/sessions_controller_test.rb`.

**Interfaces:** Public `order_path(order)` shows number and kit only. Authenticated `admin_order_path(order)` shows full order. `Admin::BaseController#current_admin` returns nil and clears an expired session.

- [ ] Add an HTTP regression: anonymous order detail contains no private name/address/email/phone/notes, while authenticated admin detail contains them. Run it red.
- [ ] Make the public view limited, add protected admin route/view, and repoint the coupon list link. Run it green.
- [ ] Add a session time-travel regression, run red, implement expiry in `current_admin`, run green.
- [ ] Run affected controller tests and commit.

### Task 3: Enforce single-use coupon redemption

**Blocked by:** Task 1

**Files:** Modify `app/models/order.rb`, `app/controllers/orders_controller.rb`, `db/schema.rb`; create `db/migrate/*_enforce_one_order_per_coupon.rb`; test `test/models/order_test.rb`, `test/controllers/orders_controller_test.rb`.

**Interfaces:** `Order#save` with a stale coupon cannot create a second order; `OrdersController#create` renders an actionable coupon error for a conflict.

- [ ] Add a stale-coupon regression using two separately loaded `CouponCode` objects. Run red; confirm two orders are possible before the fix.
- [ ] Add a migration that reports duplicate coupon IDs and creates a unique index on `orders.coupon_code_id`. Apply to a fresh test database. Verify the stale-coupon test turns green at the database invariant, then map conflict to a user-facing error.
- [ ] Add an HTTP regression for already redeemed coupon, run focused tests, and commit.

### Task 4: Make export retry and attachment failure safe

**Blocked by:** Task 1

**Files:** Modify `app/models/order_export.rb`, `app/jobs/admin/send_order_export_job.rb`, `app/mailers/admin/order_export_mailer.rb`, `db/schema.rb`; create migration for stable job identity and review-required status if needed; test `test/jobs/send_order_export_job_test.rb`, `test/models/order_export_test.rb`, `test/mailers/admin_order_export_mailer_test.rb`.

**Interfaces:** A retried `Admin::SendOrderExportJob` reuses the same `OrderExport`, its reserved orders, and its `job_id`; mailer raises for missing files. SMTP delivery exceptions set review-required state without automatic retry.

- [ ] Add a build-failure-then-retry regression on one job instance: same export ID and order IDs, eventual success. Run red.
- [ ] Persist job identity and return already reserved orders from that run. Run green.
- [ ] Add missing-file mailer regression, run red, require a readable file, run green.
- [ ] Add delivery-exception regression: review-required state, no retry enqueue. Run red then green.
- [ ] Run affected model, job, and mailer tests; commit.

### Task 5: Consolidate queue and Florida report paths

**Blocked by:** Tasks 1 and 4

**Files:** Modify `docker-compose.production.yml`, `config/recurring.yml`, `config/initializers/order_export.rb`, `app/controllers/admin/order_exports_controller.rb`, tests for schedule and Florida report; remove duplicate `app/jobs/admin_reports/florida_orders_export_job.rb` and `app/mailers/admin_reports/florida_orders_export_mailer.rb`; retire `config/sidekiq_scheduler.yml` and Sidekiq Compose path after schedule parity.

**Interfaces:** Compose executes `bin/jobs`; `config/recurring.yml` schedules `Admin::SendOrderExportJob` and `Admin::FloridaOrdersExportJob` in America/New_York. The report's single job and mailer are used by schedule and tests.

- [ ] Add a config regression that parses recurring YAML and verifies task names, classes, cron times, and timezone. Run red.
- [ ] Configure Solid Queue worker in Compose and both recurring tasks. Remove the competing Sidekiq schedule and duplicate Florida code. Run green.
- [ ] Make schedule settings authoritative by deriving cron and subject labels from one source or removing settings that do not drive execution. Verify manual form parsing remains correct.
- [ ] Validate Compose config, Rails boot, focused schedule and Florida report tests; commit.

### Task 6: Whole branch verification and PR

**Blocked by:** Tasks 2, 3, 4, 5

**Files:** All changed code and tests; PR body.

**Interfaces:** Verified branch review package and PR linked to issue #28.

- [ ] Run full test suite and artifact-specific checks, including schema load, route checks, and Compose config. Confirm nonzero tests and inspect full output.
- [ ] Review every diff and run an independent code review; fix substantive findings and reverify.
- [ ] Push branch and create a PR with plain-language summary, developer details, and before/after evidence. Link issue #28.
