# HUNKART staff flow: release readiness

## 31 October 2026 — draft-only continuation

Current user instruction supersedes earlier release authorization: continue preparation in draft only. No live SQL, secrets, Edge deployment, cron, main merge, APK distribution or Play change is authorized by this continuation.

Added `production-staff-worker/` as a separate disabled candidate. It validates the exact Supabase URL, an explicitly configured production Firebase project and matching server account, a matching existing VAPID pair, and an explicit OFF-by-default worker flag. Single-use scheduler capability is consumed before job claims/provider calls. The tested staging entrypoint is unchanged. Production server credentials were not read, created or modified.

Offline checks on 31 October: 36 production configuration/authorization assertions; 41 existing worker/service-worker assertions; 11 FCM helper checks; FCM send and OAuth suites passed. No actual push sent; Deno deployment/bundling, real server Firebase identity, phone install and production E2E remain unverified.

Read-only live recheck: dispatch schema remains absent; cancellation actor constraint remains customer/admin only; delivery tracking still has both cancellation fulfilment guard and order-status sync triggers. Edge Function inventory has no dispatch-staff-worker. This is a compatibility inventory, NOT a schema/data backup or restore verification.

Next checkpoint: complete reviewed backup/restore artifacts and installer dependency/grant comparison, verify production Firebase APK/server identity, then validate Deno bundle in isolation. Preserve the earlier automatic-review rejection: do not execute the broad production installer or split it to bypass that rejection. Release activation remains blocked and outside this draft-only instruction.

The user authorized a live staff release on 30 October 2026. This document records release blockers and test evidence; the customer AAB and Play Console are explicitly out of scope. Do not claim live deployment until checks pass.

## Evidence and boundaries

- The seven shared public tables used by the flow have matching columns and types on staging and live as of 30 October 2026. Live lacks the entire `hunkart_dispatch` schema and the `hd_*` API functions.
- Live already has `public.save_my_shop_location`, with different validation and search path. Review its behavior before applying any staging definition; do not blindly overwrite it.
- Staging shopkeeper/rider APKs use `.staging` Android application IDs, staging Firebase, and a fixed Cloudflare preview origin. They are **not** installable production updates to the existing staff packages.
- Existing production APK workflows generate versionCode 1 debug packages. A production in-place update needs the exact existing package ID and matching signing certificate plus an increased versionCode. If that identity cannot be verified, use an explicit migration/install plan rather than promising a seamless update. Do not reuse the customer Play signing key by assumption.
- The existing admin APK opens `https://hunkart.com/admin.html`; the role change is a site/backend update and does not itself require reinstalling that APK. The PR has no change to customer `index.html`.
- Staging synthetic `paid` orders are not real Razorpay transactions; none of their data, Firebase registrations or cron state should be copied to live.
- Inspected archive APK certificate fingerprints (SHA-256): old Shopkeeper `1e660122037500fcaf10853c8525762b113f1d371881cdebd2f563924aeb93b0`; old Delivery Partner `50cfa125b04204899959dec0dec30993276a79fbd3e0afbaf4af5965a31c6d24`; staging Shopkeeper `d67ea85b2fd497b72b507ab358351ff88038e44eb261e80f3f168d3666747436`; staging Rider `9a6a404f0a6fa6a155d9c245dd065a5f2dd891f00a9f56440e6cd4d6fd4314ef`. The only stored signing secret named `HUNKART_KEYSTORE_BASE64` is for the customer Play AAB; its certificate fingerprint is `6915d90f544de69d6c3b052da099994bff7158f10719175b01f902b5ff6ce3ea`, which matches neither legacy staff app. Certificates identify identity, not possession of private signing keys. Do not repackage the staging APK as an in-place staff update.
- The production Firebase Android JSON for both staff package IDs and the permanent staff signing key were validated by the isolated GitHub Actions build. Server-side Firebase service-account and notification worker readiness are still separate release gates. Do not point production staff apps at the staging Firebase project.
- Live has `sync_order_status_from_delivery_trigger` after insert/update of tracking; the isolated staging suite did not include it. A staging signup trigger had a null-account-type bug; this was fixed in staging with `IS DISTINCT FROM 'shopkeeper'`. With the live status-sync trigger reproduced inside a rollback-only staging transaction, the full suite passed 86 assertions, including refund queue and OTP delivery. No fixture users persisted.

## Controlled rollout sequence to prepare, then review

1. Capture a current read-only inventory and backup of live schema, functions, grants, triggers, cron jobs, Edge Functions and staff frontend version. Check cancellation/refund dependencies and existing notification behavior.
2. Assemble an idempotent production installer from the reviewed candidate SQL, separating schema/functions, private grants, triggers and scheduling. Keep the dispatch and notification flags disabled during installation. Include a revert plan that disables new paths before touching any existing objects.
3. Build production staff APK candidates against the actual HUNKART domain and production Firebase project only after verifying package/signature continuity. Keep customer AAB out of this build. Test install/update on spare phones without exposing staging credentials.
4. Stage frontend and server notification components in a controlled release. Verify old staff apps and the current admin/customer/payment flows before enabling new routing.
5. Enable for a limited shop and rider cohort, run a real paid order through cancellation window → shop acceptance → packing → rider offer → OTP delivery, and inspect refunds, alerts and audit logs. Expand only after monitoring shows no regressions.
6. Rollback order: disable dispatch/notification flags, restore the previous frontend and staff APK distribution, then review queued jobs before removing any newly added database object. Preserve real order and payment records.

## Production staff APK source

The branch now contains `.github/workflows/staff-production-apk.yml` and a separate `android-production` source tree. They use `https://hunkart.com`, the existing `com.hunkart.shopkeeper` and `com.hunkart.deliverypartner` IDs, and versionCode 100. The workflow fails closed unless the production Firebase JSON contains both package IDs and its project is not `hunkart-staging`; it also requires a persistent staff keystore and verifies signed APK identity. The isolated branch build passed Firebase/signing validation, release assembly, APK signature and package/version checks; run 41085568765 uploaded `HUNKART_Staff_Production_APKs`. These are release candidates, not a deployed live service. Since the legacy signing private keys are unavailable, the resulting APKs will require a one-time uninstall/reinstall after backend activation; do not uninstall old apps early.

## Current status

Staging flow and phone OTP tests passed. Automated JavaScript tests and the staging staff APK build pass. Native long sound/vibration was deferred at the user's request. A non-destructive flag-only rollback is in `PRODUCTION_EMERGENCY_STOP.sql`. A disabled production SQL assembly is available, but its live execution was rejected by automatic approval review as too broad while backup, worker, signing and rollback gates remain unresolved. Do not split it into smaller live calls to bypass that rejection. Read-only verification confirmed the production `hunkart_dispatch` schema is still absent. The staging suite passed 86 assertions with the live tracking trigger reproduced. Production Firebase Android registration and staff signing secrets are configured and CI verified. A complete production backup, server-side notification configuration, approved backend installation, and controlled live verification remain unresolved. Do not merge the draft PR yet.

