# Staging verification — 28 October 2026 (latest checkpoint)

Production, GitHub main and Play AAB unchanged. All new APIs and notification worker are installed only on HUNKART-STAGING jjitqihblpubqwbggjpv. Feature remains disabled outside rolled-back tests.

## Tests that passed
- 42 SQL workflow checks through the actual new staff APIs: own-shop paid orders, three-minute cancellation window, active ownership, acceptance/idempotence, preparing/ready/packed, assigned-rider read isolation and pickup; decline, expiry, busy exclusion and Admin deadline escalation; cancellation/refund queue; notification authorization, lease/retry/token protections; direct table and anon denial.
- 2 explicit anon-role SQL denial checks.
- 10 Chromium UI checks with MOCKED SDK/HTTP transport at 390px and 1280px. This is not an authenticated browser-to-staging test.
- 8 UI/unit checks and 7 notification-worker unit checks with mocked send transport.
- Changed inline script syntax and git diff whitespace checks pass.
- Deployed staging notification endpoint: unauthenticated POST 401, GET 405, OPTIONS 204.

The missing legacy staging staff APIs are no longer blockers: pages now use self-contained hd_my_shop_orders, hd_set_shop_stage, hd_my_deliveries and hd_start_delivery. Production legacy function source was not fetched after the approval rejection. Existing production delivery OTP/tracking endpoints remain untouched; end-of-delivery regression remains to be tested.

## Safe final database state
Feature enabled=false. Zero test orders, refund rows and notification-outbox rows remained after rollback. No real payments, refunds or notifications were sent.

## Still required before release
- Authenticated browser-to-staging integration and simultaneous transaction stress tests.
- Actual notification VAPID configuration/delivery compatibility; no real message delivery has been verified. Foreground send/Admin retry is implemented; independent notification retry scheduling is not implemented.
- Tracking/reached/OTP completion regression.
- Production metadata/ACL backup, idempotent guarded installation and rollback plan; coordinated frontend/cache deploy and monitoring.
- Permanent dispatch tick schedule. Automatic approval review rejected enabling pg_cron and a recurring 10-second job as ongoing activity beyond current testing scope. No scheduler was installed; manual tick execution is verified. Do not retry or bypass that rejection without further authorization or a safer approved plan.

Current code and tests are on PR #1: https://github.com/spidydelivery7-netizen/koida-local-delivery/pull/1 . Do not merge based solely on these passing checks.
