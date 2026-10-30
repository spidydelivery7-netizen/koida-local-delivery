# HUNKART staff order flow — staging checkpoint

Status: tested on HUNKART-STAGING; **not released to production**. This draft PR is isolated from the customer Play AAB and customer feature draft. Do not merge into `main` as a deployment shortcut.

## Behavior

The assigned shopkeeper accepts a paid order after the three-minute cancellation window, then marks Preparing → Ready → Packed. An online, recently located and available delivery partner gets an expiring offer. The first acceptance assigns the delivery; the rider starts delivery and completes it with the customer's delivery OTP. Shop and rider ownership checks and the existing refund hold rules remain in force. Admin can monitor exceptions; manual assignment remains guarded. Native staging staff APKs register Firebase tokens for background order alerts. The Android alert channel uses an alarm sound and vibration, subject to phone notification settings.

## Verified on staging

- Shopkeeper and delivery partner signed into their separate staging APKs. Shopkeeper location saved, paid synthetic orders accepted and packed, rider offer accepted, delivery started, customer reached, OTP entered on the phone, and delivered orders moved to History. The database showed `delivered` in both orders and tracking and recorded OTP verification.
- Staging staff notification outbox sent shopkeeper and rider events; the rider received a native notification. An offer that expired before opening correctly disappeared from the active list. The new Android alert's sound and vibration were not separately confirmed on a phone.
- Dispatch cron every 10 seconds and staff notification cron every 5 seconds are active on staging. Source uses 120-second rider offers and five-minute GPS freshness. Some synthetic test orders remain in staging; they are not real payments.
- Native FCM tests, notification worker tests, staff worker tests, push routing tests and the eight UI/unit checks pass. Browser checks in the earlier checkpoint used mocked transport; authenticated phone testing above is the stronger evidence for the core order flow.
- The staging staff APK build for commit `9e15c007` succeeded and produced both APKs. They target an isolated Cloudflare preview and staging Firebase packages. Debug signing may require uninstalling an earlier staging build before installing a new one.

## Release boundaries and remaining work

Production backend, live website, GitHub `main`, Razorpay and Play Console have not been changed for this feature. This branch contains staging-only configuration and Android package IDs; these must never be copied verbatim into production. A production rollout requires a separate, reviewed installer with current schema/ACL backup, rollback plan, production frontend configuration, stable APK signing and deployment sequence. Verify a real paid order and refund/cancellation paths in a controlled production release. The optional long alert sound/vibration check remains deferred at the user's request.

Candidate SQL and related source files in this directory are draft installers, not production migrations. Avoid replaying test fixtures or the staging cron setup on live data.
