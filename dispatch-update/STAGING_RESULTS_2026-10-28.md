# Staging checkpoint — 28 October 2026

HUNKART-STAGING jjitqihblpubqwbggjpv only. Production and main branch unchanged.

Explicit user authorization covers necessary permanent staging backend installation and testing; live deployment only after tests pass. The missing cancellation functions and dispatch candidate are now installed in staging. Feature remains disabled outside rolled-back test transactions.

25 database component assertions PASS in test-dispatch-core.sql: disabled flag, three-minute cancellation window, customer/inactive keeper/unpaid rejection, authorized acceptance/idempotence/status, preparation guard, worker request, recipient isolation/privacy, decline fallback, assigned rider/idempotence, pickup guard, valid preparation/pickup, rejection reason, refund intent, no false refunded status, one refund, duplicate rejection, anon execution denial and direct-table access denial.

Preparation/pickup transitions in this component suite use direct writes through the candidate guards, NOT legacy preparation/delivery RPCs. Staging does not currently contain set_my_shop_order_status, mark_my_shop_order_packed, delivery_start or get_my_deliveries_v2. Full integration suite therefore has NOT passed. Early broad exception tests could mistake missing legacy RPCs for a denied action; the component suite instead exercises real installed guards and is the authoritative result.

Final verification: dispatch settings.enabled=false; remaining orders=0, cases=0, refunds=0. Test fixtures and temporary activation rolled back. No network refund worker is installed or invoked in staging.

Approval popup root cause: test settings UPDATE statements omitted WHERE. They now target singleton=true and id=true. The user's repeated written authorization was not the missing piece; per-tool Allow once UI is distinct. Do not ask them to repeat authorization unnecessarily.

Still pending: real staff RPC compatibility, concurrent request acceptance/manual assignment, notification replacement, browser/device E2E, guarded production installer/rollback and monitoring. Production function-definition read was separately rejected by automatic approval review as outside staging scope; no alternate retrieval was attempted afterward. Do not merge or claim the feature live.
