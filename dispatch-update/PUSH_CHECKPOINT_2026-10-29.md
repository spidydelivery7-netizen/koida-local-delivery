# Staging push checkpoint — 29 October 2026
User screenshot Screenshot 2026-10-28 235825.png shows actual Microsoft Edge receipt and a visible Windows notification for the isolated staging-device-push-test. This confirms browser push transport with the staging VAPID pair, not staff/order notification integration.

## Completed
- Staging VAPID public/private pair verified server-side. Private key never copied into source or chat.
- Installed staging_staff_push_subscription_api. Active staff may save only their own subscription; role spoofing and cross-account endpoint takeover are denied.
- Draft staff-push.js selects the new key and hd_save_staff_push_subscription only for the exact staging Supabase URL. Production key and RPC remain unchanged.
- 68 rollback-only workflow assertions passed, including 10 staff subscription checks.
- 9 mocked JS assertions passed for staging/live routing and nonstaff exclusion.
- Test harness now creates its required cancellation-policy settings inside the rollback transaction. The initial rerun failed because the staging settings table was empty; no production policy was changed.
- Post-test staging state: 0 orders, 0 synthetic subscriptions, dispatch disabled, cancellation settings still empty.
- No main merge, live backend mutation, or Play Console change.

## Still required before release
- Current dispatch notification outbox/worker only handles CUSTOMER order_confirmed and shop_rejected. Do not describe it as a completed shopkeeper/rider push pipeline.
- Shopkeeper new-order and rider-offer durable enqueue, transport invocation/retry scheduling and expiry handling need implementation/verification.
- Register real test staff browsers using the matching staging key; exercise actual order/offer event notification end to end.
- Customer OTP display, concurrency tests, and coordinated production migration/rollback remain open.
- Temporary isolated device test endpoint expires 30 October 2026 at 23:41 IST. It has capability-token authorization and a fixed test message; no business-data writes.
