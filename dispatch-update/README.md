# Shopkeeper acceptance + delivery partner requests

Status: implementation candidate; NOT released. Main and production database untouched.
Branch: work/shop-acceptance-rider-dispatch
User authorized a tested live rollout for this feature only. All unrelated accumulated customer/native/auth/design drafts remain separate and must not be accidentally released.

## Behavior implemented in candidate
- Shopkeeper Accept/Reject replaces routine Admin Confirm. Paid-state, active keeper, item/shop ownership and the existing 3-minute customer cancellation window are enforced server-side.
- Rejection records a shopkeeper cancellation case and queues the remaining paid amount through the existing refund table; never marks refunded without provider confirmation. Installer must extend cases_actor_check to include shopkeeper.
- Preparing -> Ready -> Packed is enforced. Delivery pickup requires Packed.
- Explicit rider Go Online / Offline, foreground GPS heartbeat, 90-second freshness, 30-second recipient-bound offer, acceptance/decline, idempotent acceptance and per-order row locking.
- Worker reserves one pending request per rider/order and excludes busy/inactive/stale riders; chooses by approximate geographic proximity, NOT a road ETA or Zomato's proprietary algorithm. It retries available riders for up to five minutes, then exposes an Admin attention case. Worker needs a 10-second pg_cron schedule at release.
- Existing manual Admin assignment is retained as fallback and passes the same capacity/online checks via a tracking guard.
- Existing tracking and delivery OTP routines preserved; new read wrapper adds order stage/shop data and filters cancelled orders. No Android permission or AAB changes.
- No payout amount invented; business payout policy still needs its separate finalization.
- Background request alerts are NOT guaranteed by this WebView. Rider screen explicitly asks users to keep it open. No new push-notification delivery guarantee is claimed.

## Files
candidate.sql: SQL installer candidate. Settings default false. Not a generated Supabase migration and not production-ready until missing tests complete.
test-workflow.sql: synthetic database assertions; run only in a staging transaction which is rolled back.
test-existing-staging.sql: schema compatibility harness; NOT a production installer. Uses baseline cancellation functions/guards, with no network refund worker.
test-ui.cjs: 8 executable unit/preservation checks; passed.
rider-controls.js: source embedded in the existing module; keep synchronized when changing controls.
patch-ui.py / patch-rider.py: recorded transformation scripts; NOT idempotent; do not rerun on modified pages.

## Validation actually completed
- All modified HTML inline scripts pass Node syntax checks.
- 8 UI/unit checks pass: acceptance/rejection RPC payloads, error recovery, refund-pending messaging, offline-vs-inflight-GPS race, absence of routine Admin Confirm, matching shopkeeper entrypoints and Packed-only start control.
- git diff --check passes.
- Candidate SQL DDL compiled inside a staging transaction and rolled back, with check_function_bodies=false. This DOES NOT validate runtime PL/pgSQL logic.
- Staging retains original disabled acceptance foundation from earlier work; settings.enabled=false. Verified 0 orders, 0 cancellation cases and 0 refunds after attempted tests.
- Full database workflow, concurrent accept/manual assignment, refund worker/provider handling and browser/device E2E have NOT passed. Large test requests repeatedly returned Invalid or expired requestState. Do not present this as a successful workflow test.

## Release block: automatic approval review
A persistent staging cancellation-module compatibility setup was rejected by automatic approval review. The latest stated reason: persistent function definitions and permission revocations exceed draft/rollback-only authorization. This conflicts with the user's later explicit instruction authorizing tested live rollout, but the action was not bypassed.
To proceed, obtain explicit approval for the concrete staging compatibility change: HUNKART-STAGING (jjitqihblpubqwbggjpv), restore missing private cancellation function definitions/guards from the live schema, no real customer/payment data, no outbound worker, no production changes. Preserve disabled rollout/settings. Then execute and verify synthetic rollback tests. Do not merge this PR while those tests are pending.

## Remaining release work
1. Complete compatible staging setup, database role/race/refund tests and device/browser checks. Review code after actual runtime tests.
2. Add durable customer-confirmed notification/outbox support or explicitly agree on a status-refresh-only first release; old Admin confirmation previously sent a customer push. Current candidate does not replace that notification operation.
3. Review operational worker budget and load. Schedule tick every 10s only after cron support is verified.
4. Fresh production schema/function/ACL backup; exact guarded installer, cases_actor_check extension, feature-flag rollout and rollback plan. Source code changes alone must not be promoted before compatible backend install.
5. Coordinate entrypoint deployment and cache revisions, then enable flag only after smoke checks; preserve in-flight/legacy orders. Monitor rejection/refund and attention cases. Feature rollback sets settings.enabled=false and restores frontend; never delete recorded cases/refunds.

Repository URL: https://github.com/spidydelivery7-netizen/koida-local-delivery
Live URL: https://hunkart.com/delivery-app/
Production project: amnqqxgmqciipcortpmi (read-only during this work)
Staging project: jjitqihblpubqwbggjpv
