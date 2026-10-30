# HUNKART staff flow: release readiness

This is a review plan, not an authorization to change live. Only the isolated staging flow has passed phone testing. Customer app draft and Play Console AAB remain separate.

## Evidence and boundaries

- The seven shared public tables used by the flow have matching columns and types on staging and live as of 30 October 2026. Live lacks the entire `hunkart_dispatch` schema and the `hd_*` API functions.
- Live already has `public.save_my_shop_location`, with different validation and search path. Review its behavior before applying any staging definition; do not blindly overwrite it.
- Staging shopkeeper/rider APKs use `.staging` Android application IDs, staging Firebase, and a fixed Cloudflare preview origin. They are **not** installable production updates to the existing staff packages.
- Existing production APK workflows generate versionCode 1 debug packages. A production in-place update needs the exact existing package ID and matching signing certificate plus an increased versionCode. If that identity cannot be verified, use an explicit migration/install plan rather than promising a seamless update. Do not reuse the customer Play signing key by assumption.
- Staging synthetic `paid` orders are not real Razorpay transactions; none of their data, Firebase registrations or cron state should be copied to live.

## Controlled rollout sequence to prepare, then review

1. Capture a current read-only inventory and backup of live schema, functions, grants, triggers, cron jobs, Edge Functions and staff frontend version. Check cancellation/refund dependencies and existing notification behavior.
2. Assemble an idempotent production installer from the reviewed candidate SQL, separating schema/functions, private grants, triggers and scheduling. Keep the dispatch and notification flags disabled during installation. Include a revert plan that disables new paths before touching any existing objects.
3. Build production staff APK candidates against the actual HUNKART domain and production Firebase project only after verifying package/signature continuity. Keep customer AAB out of this build. Test install/update on spare phones without exposing staging credentials.
4. Stage frontend and server notification components in a controlled release. Verify old staff apps and the current admin/customer/payment flows before enabling new routing.
5. Enable for a limited shop and rider cohort, run a real paid order through cancellation window → shop acceptance → packing → rider offer → OTP delivery, and inspect refunds, alerts and audit logs. Expand only after monitoring shows no regressions.
6. Rollback order: disable dispatch/notification flags, restore the previous frontend and staff APK distribution, then review queued jobs before removing any newly added database object. Preserve real order and payment records.

## Current status

Staging flow and phone OTP tests passed. Automated JavaScript tests and the staging staff APK build pass. Native long sound/vibration was deferred at the user's request. Production installer, stable signing compatibility, backup/rollback artifacts, and controlled live verification are not complete; do not merge the draft PR yet.
