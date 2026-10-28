# Staff profile checkpoint — 28 October 2026

Staging profile reads were blocked by missing own-staff SELECT policies. Added hd_staff_profile(kind), an authenticated invoker wrapper over a private definer with empty search_path, enabled-feature/auth checks and server-owned active keeper/rider mapping. Returns explicit own-profile/shop/product fields only; no broad table grants. Updated both identical keeper pages and rider page to use this API.

Installed on staging only. 47 real SQL workflow assertions passed (five new profile checks); anonymous, unassigned keeper/rider checks passed; eight UI/unit preservation checks passed. Tests rolled back: enabled=false, orders=0, offers=0. This is not an authenticated browser-to-staging test. Final tracking/reached/delivery OTP, browser integration and actual push delivery remain release blockers. No production/main/AAB change.

Include staff-profile.sql in the guarded production installer before enabling the coordinated frontend. Keep all unrelated customer drafts separate.
