# Order and export reliability

## Outcome

Customers can place one order per coupon without exposing shipping or contact details to strangers. Admin exports deliver the reserved orders or retain an actionable failure state. Scheduled and manually queued jobs run under the same deployment adapter.

## Requirements

1. Public order confirmation shows its confirmation number and kit, but no name, address, email, phone, or notes. A protected admin order detail page serves the full record. Existing `/orders/:id` links remain valid as limited confirmations.
2. A coupon may belong to at most one order. Two submissions that loaded the same unused coupon may not both succeed. A conflict returns a form error. A database unique index is the final invariant. The migration must check for pre-existing duplicates and stop with an actionable error rather than delete orders.
3. Export retries retain their original `OrderExport` and `ExportedOrder` set. A file build failure may retry automatically. Delivery exceptions have an unknown external outcome and require manual review, with no automatic resend. An absent or unreadable attachment is a failure before delivery. A successful status requires a delivered email with its spreadsheet.
4. Production uses Solid Queue for manual enqueue, recurring schedule, and worker execution. Compose runs `bin/jobs` and Solid Queue recurring tasks; Kamal continues using its existing Puma worker. The Florida report has one job and one mailer implementation. Any migration away from Sidekiq leaves no duplicate recurring schedule active.
5. Admin access expires 12 hours after login. Missing or expired expiry data invalidates the session on the next admin request.
6. The export schedule has one source for weekdays, hour, and timezone. Its email label reflects that schedule; configuration that has no effect is removed. Manual export time parsing must remain supported.
7. The test runner executes nonzero tests. Add behavioral regression tests at the HTTP, model, job, mailer, and schedule seams. Do not use tests that merely mirror implementation.

## Design

- `OrdersController#show` is a deliberately limited public view. `Admin::OrdersController#show` inherits admin authentication. The admin coupon list links to the protected route.
- `Order` owns coupon redemption. Database uniqueness prevents stale reads from violating single use. The controller maps the conflict to the existing invalid coupon message.
- A stable Active Job `job_id` identifies an export run across retries. Reservation returns that run's order set on subsequent attempts. Delivery failure moves the run to a review-required state; only pre-delivery failures are retried. Operators can inspect the run instead of silently losing orders or sending uncertain duplicates.
- `config/recurring.yml` contains the two production schedules. Compose runs a Solid Queue supervisor. The old Sidekiq scheduler is retired after the new schedule is active; review deployment order before release.
- The existing `Admin::FloridaOrdersExportJob` and mailer become the sole Florida report implementation.

## Migration and deployment

- Measure duplicate `orders.coupon_code_id` groups before the unique-index migration. If any exist, stop and reconcile manually; deleting an order would lose customer data. The additive index is compatible with older readers, but older writers may receive uniqueness failures until the new order behavior is deployed. Roll out the application handling before or with the index and monitor order creation errors.
- Current production data and queue state are unavailable locally. Queue switchover must ensure only one recurring scheduler runs and that Solid Queue tables exist before stopping Sidekiq. After deployment, enqueue and observe one real job in Compose, then retire Sidekiq dependencies in a later cleanup if no consumer remains.

## Success checks

- Anonymous request cannot see private fields; authenticated admin can.
- Stale coupon and competing request tests produce one order; existing duplicate data blocks migration with a clear message.
- Failed build retries retain order IDs; missing attachment cannot succeed; delivery exception is review-required and does not auto-resend.
- Recurring config names the same job exercised by tests; Compose runs a Solid Queue worker.
- Expired admin session redirects to login.
- Relevant test command runs nonzero examples with zero failures; Ruby syntax and repository checks pass.

## Source-grounded decisions

Rails is declared `~> 8.1.1` and locked at 8.1.1; Solid Queue is locked at 1.3.1 in `Gemfile.lock`. The local runtime is Ruby 3.4.5 because `.ruby-version` requests unavailable 3.4.7. Solid Queue's version-matched README and installed `configuration.rb` support `config/recurring.yml`, `bin/jobs`, and Fugit cron with a timezone. The installed Minitest 6.0.1 lacks `minitest/mock`, while the test helper requires it; Rails 8.1.1 accepts Minitest `>= 5.1`, so pinning to Minitest 5 is compatible.
