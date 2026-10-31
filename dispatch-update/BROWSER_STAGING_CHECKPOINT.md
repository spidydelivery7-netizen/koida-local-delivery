# Actual browser staging checkpoint — 28 October 2026

Local source pages loaded with bundled real @supabase/supabase-js 2.57.4, real staging Auth/REST/cron, headless Chromium at 390px and simulated browser geolocation. No SDK/RPC mocking. SDK locally bundled for deterministic import; proxy configured for environment. Service workers blocked; actual device push not tested.

Observed through buttons: keeper password login and own order visible, Accept, real automatic rider offer and rider acceptance, Preparing/Ready/Packed and pickup (database out_for_delivery). Resumed browser sessions for final steps; Reached and correct-OTP Mark Delivered resulted in database status delivered, reached_at set, OTP verified_at set. This was a staged multi-session test, not one uninterrupted automated test. OTP was generated/read through privileged staging fixture tooling for handoff; customer OTP display was not tested. Final exact-text UI selector did not match and was interrupted; do not claim the whole script passed.

Found refresh rendering issue: existing GPS was applied while replacement card not yet inserted; refreshed Reached button could stay disabled despite nearby GPS. Apply latest known position after renderDeliveries completes. Final resumed Reached/OTP completion verified against staging database after this fix. Eight preservation checks and git diff whitespace passed.

Authenticated notification worker returned 503: notification service not configured, intent remains queued. VAPID configuration is a real remaining blocker; no actual customer messages sent. Requires dedicated test-device subscription and authorized recipient before delivery verification. Do not invent success.

Synthetic order/tracking/OTP/outbox/offers/jobs/acceptance/shop/products/staff/auth users and sessions removed; dispatch flag false. No live/main/Play change. Remaining: notification configuration/delivery, customer OTP display, concurrency stress and guarded coordinated deployment/rollback.
