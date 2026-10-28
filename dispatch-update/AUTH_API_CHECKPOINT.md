# Staging authenticated HTTP checkpoint — 28 October 2026

Real password-grant HTTP login verified for synthetic keeper and rider: each /auth/v1/token returned 200. Each authenticated hd_staff_profile request returned 200 with own role data and null for the other role. Both /auth/v1/logout returned 204. No mocked SDK/transport used for these checks. This is HTTP API verification, not full browser/page/order E2E.

Initial synthetic fixtures failed login because auth.users.created_at was missing; auth logs confirmed this fixture issue. Recreated with created_at/updated_at; tests passed. No live auth settings/users changed. Synthetic users/shop/keeper/rider/customer records and sessions removed; dispatch feature restored false. No orders/payments/notifications sent.

Remaining: actual browser order flow and customer OTP display, push delivery/config compatibility, concurrent transactions and guarded deployment/rollback. Do not merge/release solely based on these checks. Production function source remains outside this public repository.
