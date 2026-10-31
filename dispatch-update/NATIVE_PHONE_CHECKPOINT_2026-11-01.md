# Staff phone checkpoint — 2026-11-01

Draft only. Main, production backend, Razorpay and Play Console remain unchanged.

## Verified evidence
- Shopkeeper production candidate installed and login succeeded on user's phone.
- Foreground Order Alerts On and Android notification permission were observed. Background FCM delivery remains unverified; rider installation remains unverified.
- Local production Firebase service account successfully authenticated with Google OAuth. No notification was sent; access token was not displayed. FCM send permission and delivery are not implied.
- Isolated full restore and draft workflow/registration tests passed. Authenticated registration, duplicate prevention and removal passed; invalid staff role and missing login were rejected. Test transactions rolled back.
- Original 26 trigger statements and 255 ownership statements compared unchanged. Explicit ACL comparison for 111 pre-existing app objects found zero removed/changed or added statements.
- A separate schema-only baseline without the draft restored successfully in a separate network-none container, with cron disabled. All 52 original ACL statements missing from the draft restore were also missing in that baseline. Zero were present before but absent after draft. This attributes the 52 text differences to the restore baseline, not the draft; it is not a complete effective-privilege/default-ACL/RLS audit.

## Android layout change
Commit 61c9758 adds a native FrameLayout around the production staff WebView and applies system bar, display cutout and keyboard insets on API 30+. This avoids relying on HTML padding for fixed page headers. Android 24–29 retain their existing platform layout handling. Both production staff flavors share this activity. Source was read back after commit; Android build and phone visual validation are pending. Existing installed APKs do not contain this change.

## Registration finding
The existing native-fcm/staff-registration.js explicitly allows only the staging Supabase URL. Production APKs load hunkart.com staff pages. Production native_devices and hd_save_native_device(text,text) were absent in the user's read-only production SQL result. Do not widen this staging module's allowlist and assume production is complete: prepare a separate explicit production page integration, account/token refresh and logout handling, with origin/role validation and tests before release. No production bridge was enabled in this checkpoint.

## Remaining release gates
- Complete and test production frontend native-token integration; examine token/account switching and logout failures.
- Build layout candidate and validate portrait/landscape, keyboard, gesture navigation and three-button navigation on phone.
- Actual configured VAPID pair verification remains pending.
- Production install/deployment requires separate concrete release authorization; keep worker/dispatch flags off until controlled hosted tests succeed.
- Targeted Shopkeeper and Delivery Partner background notification and order E2E tests remain pending. Long siren/vibration is not certified.
