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

## Registration implementation and limits
The staging-only registration module remains unchanged and both pages retain its integration. A separate production-registration.mjs module is now connected in both draft staff pages. It requires the exact production Supabase URL, HTTPS hunkart.com origin, matching staff page path and Android token bridge. The database still authorizes the caller's staff identity; no user ID or service credential is supplied by the frontend.

Registration operations are serialized. Repeated token/auth events deduplicate confirmed registrations; token rotation saves the replacement and removes the previously registered token. Failed old-token cleanup remains queued for retry. Logout waits for an in-flight registration and removes known tokens before calling auth signout. Failed removal keeps the auth session available for retry and reports a user-facing error; it never silently reports successful cleanup. Auth callbacks schedule work outside the callback. Native registration failures show an unavailable message instead of claiming working background alerts.

Mocked lifecycle tests passed locally for registration, deduplication, token rotation, signed-out/login behavior, logout failure/retry, invalid token, cleanup, origin/project/role gates, an in-flight save/logout race and failed rotation cleanup retry. Both changed page modules passed syntax checks before the later staging-preservation import addition. CI also passed the initial lifecycle suite. These mocks do not prove hosted RPC behavior or real device FCM delivery. Direct account switching without a successful prior logout is not certified: the server intentionally rejects another user's token ownership. Do not weaken that restriction.

Production native_devices and hd_save_native_device(text,text) were absent in the last read-only production SQL result. The new module and staff pages exist only in the unmerged draft; the installed APK loads the old live pages. Backend installation and frontend release remain necessary before production registration can work.

Staff candidate version is now 1.1.1 (101), signed by the existing staff signing configuration. Build run 41237905844 is in progress; a later test-only commit triggers another build. Do not replace or distribute the candidate as verified until build/package/signature checks complete. Phone layout validation remains pending.

## Remaining release gates
- Hosted production frontend/RPC integration and token/account transition tests after separate release authorization. Local mocked lifecycle checks are complete.
- Build layout candidate and validate portrait/landscape, keyboard, gesture navigation and three-button navigation on phone.
- Actual configured VAPID pair verification remains pending.
- Production install/deployment requires separate concrete release authorization; keep worker/dispatch flags off until controlled hosted tests succeed.
- Targeted Shopkeeper and Delivery Partner background notification and order E2E tests remain pending. Long siren/vibration is not certified.
