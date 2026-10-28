# Shopkeeper acceptance and rider requests

Status: STAGING IMPLEMENTATION; NOT RELEASED. Production, main and Play AAB unchanged.
Working branch: work/shop-acceptance-rider-dispatch. PR #1.
User authorization: install/test necessary HUNKART-STAGING backend; live only after successful testing. Do not repeat authorization questions without a new scope or concrete approval block.

## Current behavior
Shopkeeper Accept/Reject replaces routine Admin Confirm. Paid status, active keeper, single-shop ownership, cancellation holds and existing three-minute customer cancellation window are enforced. Rejection queues one remaining-balance refund through existing cancellation tables; provider confirmation is required before refunded status.

Self-contained hd_my_shop_orders, hd_set_shop_stage, hd_my_deliveries and hd_start_delivery APIs remove reliance on missing legacy staging staff RPCs. Steps: Accept -> Preparing -> Ready -> Packed -> assigned rider pickup. Existing delivery tracking/OTP endpoints remain unchanged; their full completion flow has not been revalidated in staging.

Explicit online/offline foreground GPS presence. Recipient-bound 30-second requests; active/fresh/available riders only; one pending request per rider/order. Geographic proximity is approximate, not road ETA. Decline/expiry advances search; five-minute exhaustion becomes Admin attention. Manual Admin assignment remains guarded by online/capacity checks. Background alerts are not guaranteed by WebView; UI tells riders to keep the screen open. No payout amount invented.

Confirmation/rejection notification intents persist in a private outbox. Authorized shopkeepers/Admin can invoke a worker only for stored order notifications. Service-only claims use leases and attempt tokens; stale acknowledgements cannot complete a newer attempt. Browser receives no service key or customer subscription keys. Worker uses pinned dependencies and existing VAPID_PUBLIC_KEY/VAPID_PRIVATE_KEY environment names; actual VAPID compatibility is a remaining release check. Foreground send/retry is implemented, including Admin retry button. There is no automatic independent notification retry scheduler yet.

## Installer order / staging artifacts
1. candidate.sql (disabled settings; new private tables/functions and guards).
2. admin-helper.sql and admin-queue-v2.sql (server-owned Admin authorization; existing legacy helper preferred when available).
3. staff-api-v2.sql and shop-order-read-v2.sql (current staff APIs wired into pages).
4. notification-outbox.sql; notification-worker-api.sql; deploy notification-worker/index.ts + core.mjs.
5. cases_actor_check must allow shopkeeper as well as customer/admin, preserving other constraints.
6. Recurring pg_cron tick job is NOT installed. Automatic approval review rejected the permanent every-10-second schedule as ongoing activity beyond the current test scope. Manual tick invocations are verified; feature flag remains false outside rollback tests.
These are reviewed candidate installers, not generated migration history. Before production: idempotent trigger installation, fresh metadata/ACL backup and guarded rollback plan still required.

## Verified results
- 42 staging SQL workflow assertions: role/ownership/payment/window isolation; actual new staff preparation/pickup/read RPCs; assignment, decline, busy exclusion, expiry and escalation; queued refund with no false payment status; notification authorization, claim/retry/stale lease protection; no anon/table access.
- 2 real database anon-role denial checks.
- 10 Chromium browser UI checks at 390px/1280px with MOCKED SDK/transport: shop accepts, rider accepts, no early pickup, preparing/ready/packed, pickup, responsive layouts and offline toggle. Not authenticated browser-to-staging E2E.
- 8 UI/unit preservation checks; 7 notification-worker unit checks with MOCKED transport.
- Changed inline scripts pass Node syntax; git diff --check passes.
- Staging Edge worker deployed version 1. HTTP checks: unauthenticated POST=401, GET=405, OPTIONS=204. No real customer notification sent.
- Staging after test rollback: feature false; zero orders/refunds/outbox notifications. No test data retained.
- Security advisor: no new hd_* exposed SECURITY DEFINER warnings. Private RLS/no-policy tables intentionally deny direct access. Existing unrelated staging warnings recorded separately; do not claim a globally clean audit.

## Remaining before live
Authenticated browser/API integration and simultaneous SQL race/stress tests; actual VAPID configuration and notification delivery/automatic retry; tracking/reached/OTP completion regression; production metadata/ACL backup; guarded installer/cache rollout, scheduling and monitoring. Do not merge simply because component/UI checks pass.

Canonical combined customer/native/design/auth drafts remain separately preserved in HUNKART_Review_Proposal.zip. This branch only implements this staff/dispatch feature; do not promote unrelated drafts accidentally.


## Scheduler checkpoint — 28 October 2026, 5:36 PM IST
The user explicitly authorized the permanent every-10-second dispatch process on HUNKART-STAGING. pg_cron is now installed; job 1 (`hunkart-dispatch-tick`) is active and runs `select hunkart_dispatch.tick();` every 10 seconds. Three consecutive executions were verified succeeded at 12:05:46, 12:05:56 and 12:06:06 UTC. This supersedes earlier scheduler-blocked notes above.

Feature flag remains false outside controlled tests, so these successful executions prove the schedule/worker invocation, not processing of real orders. Production/main/Play unchanged. Authenticated app integration, actual push delivery and final tracking/OTP verification remain release requirements. No need to ask the user to repeat this scheduler authorization.
