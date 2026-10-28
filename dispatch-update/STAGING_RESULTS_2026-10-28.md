# Staging verification — 28 October 2026 (latest checkpoint)

Production, GitHub main and Play AAB unchanged. All new APIs and notification worker are installed only on HUNKART-STAGING jjitqihblpubqwbggjpv. Feature remains disabled outside controlled staging tests.

## Tests that passed
- 42 SQL workflow checks through the actual new staff APIs: own-shop paid orders, three-minute cancellation window, active ownership, acceptance/idempotence, preparing/ready/packed, assigned-rider read isolation and pickup; decline, expiry, busy exclusion and Admin deadline escalation; cancellation/refund queue; notification authorization, lease/retry/token protections; direct table and anon denial.
- 2 explicit anon-role SQL denial checks.
- 10 Chromium UI checks with MOCKED SDK/HTTP transport at 390px and 1280px. This is not an authenticated browser-to-staging test.
- 8 UI/unit checks and 7 notification-worker unit checks with mocked send transport.
- Changed inline script syntax and git diff whitespace checks pass.
- Deployed staging notification endpoint: unauthenticated POST 401, GET 405, OPTIONS 204.

The missing legacy staging staff APIs are no longer blockers: pages now use self-contained hd_my_shop_orders, hd_set_shop_stage, hd_my_deliveries and hd_start_delivery. Production legacy function source was not fetched after the approval rejection. Existing production delivery OTP/tracking endpoints remain untouched; end-of-delivery regression remains to be tested.

## Safe final database state
Feature enabled=false. Zero test orders, refund rows and notification-outbox rows remained after cleanup (earlier checks used rollback). No real payments, refunds or notifications were sent.

## Still required before release
- Authenticated browser-to-staging integration and simultaneous transaction stress tests.
- Actual notification VAPID configuration/delivery compatibility; no real message delivery has been verified. Foreground send/Admin retry is implemented; independent notification retry scheduling is not implemented.
- Tracking/reached/OTP completion regression.
- Production metadata/ACL backup, idempotent guarded installation and rollback plan; coordinated frontend/cache deploy and monitoring.
- Permanent dispatch tick schedule. Automatic approval review rejected enabling pg_cron and a recurring 10-second job as ongoing activity beyond current testing scope. No scheduler was installed; manual tick execution is verified. Do not retry or bypass that rejection without further authorization or a safer approved plan.

Current code and tests are on PR #1: https://github.com/spidydelivery7-netizen/koida-local-delivery/pull/1 . Do not merge based solely on these passing checks.


## Scheduler checkpoint — 28 October 2026, 5:36 PM IST
The user explicitly authorized the permanent every-10-second dispatch process on HUNKART-STAGING. pg_cron is now installed; job 1 (`hunkart-dispatch-tick`) is active and runs `select hunkart_dispatch.tick();` every 10 seconds. Three consecutive executions were verified succeeded at 12:05:46, 12:05:56 and 12:06:06 UTC. This supersedes earlier scheduler-blocked notes above.

Feature flag remains false outside controlled tests, so these successful executions prove the schedule/worker invocation, not processing of real orders. Production/main/Play unchanged. Authenticated app integration, actual push delivery and final tracking/OTP verification remain release requirements. No need to ask the user to repeat this scheduler authorization.

## Automatic order processing checkpoint — 28 October 2026, 6:25 PM IST
A committed synthetic fixture was created on staging only: synthetic keeper/customer/rider users at example.invalid, one shop/product and one simulated-paid order (no payment provider call). The real hd_heartbeat and hd_accept_shop_order APIs were invoked. Immediately after acceptance the order was confirmed, job searching and offer count zero. Without calling tick manually, pg_cron created a pending offer for the synthetic rider at 12:54:32 UTC; inspection showed job offered and a successful scheduled run. This verifies autonomous offer creation after shop acceptance. It does not verify foreground app receipt, real push delivery or full delivery completion.

Cleanup completed in a transaction: dispatch feature restored to false; synthetic order/items/status/acceptance/job/offers/outbox, rider/presence, product/shop/keeper and synthetic auth/customer rows removed. Verified orders=0, offers=0, notification_outbox=0. No real payment/refund/notification was sent. The authorized staging schedule remains active; production/main/Play remain unchanged.
