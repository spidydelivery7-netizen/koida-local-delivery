# Production staff worker candidate — disabled, not deployed

This separate entrypoint removes the staging-only restriction without changing the tested staging worker. Source is reviewable only; do not deploy or enable from this checkpoint.

## Configuration contract

- Runtime URL must be exactly the production Supabase URL encoded in config.mjs.
- `HUNKART_STAFF_WORKER_ENABLED` defaults OFF; only the literal `true` allows a request to continue. Database dispatch and staff notification flags must also be enabled separately after release review.
- `FCM_PROJECT_ID` is the existing project secret name confirmed in the earlier chat. Reuse it; do not ask the user to recreate it under a new name. It must match the production APK Firebase project (`hunkart-production`) and server account. The APK google-services JSON is not a Firebase server service-account credential.
- `FCM_SERVICE_ACCOUNT_JSON` is server-only and must belong to that same production Firebase project. Do not copy staging credentials, commit secrets, or print them.
- `VAPID_PUBLIC_KEY` and `VAPID_PRIVATE_KEY` must form a matching pair. Existing subscriptions require their original pair. This draft never generates or replaces keys and never touches Razorpay secrets.
- Supabase supplies `SUPABASE_URL` and the existing server role credential used by the reviewed SQL RPC role checks. Key migration is outside this change.

## Authentication and deployment packaging

The future function slug is `dispatch-staff-worker`, matching the disabled SQL installer. Its platform JWT check must be off for this function only because the scheduler sends a short-lived one-use hex capability, not a user JWT. The handler strictly validates and hashes the bearer capability and consumes it atomically through `hd_consume_staff_worker_token` before claiming any jobs or contacting providers. Do not disable JWT verification on unrelated functions.

Bundle index.ts, handler.mjs, config.mjs and the imported staff-worker/core.mjs and native-fcm/{oauth,send,core}.mjs preserving relative paths. This entrypoint is not a self-contained single-file deployment. Provider calls have bounded timeouts.

31 October follow-up: Deno 2.9.6 type-check passed for the actual entrypoint and test-entrypoint.ts. Four entrypoint/import response checks passed with no network permission and no listener. Current configuration/auth suite has 38 assertions after compatibility correction. Dependency loading used an isolated npm node_modules directory because direct Deno registry fetching stalled. This confirms local Deno import/runtime behavior, not enabled hosted provider delivery.

Reproduce in an isolated test workspace with the same relative source tree and pinned @supabase/supabase-js 2.57.4, web-push 3.6.7 and @types/node 22.10.2 installed: run Deno from that workspace (its cwd must contain package.json/node_modules), `deno check --no-remote --node-modules-dir=manual dispatch-update/production-staff-worker/index.ts dispatch-update/production-staff-worker/test-entrypoint.ts`, then `deno run --no-remote --node-modules-dir=manual dispatch-update/production-staff-worker/test-entrypoint.ts`. No allow-net/env permissions are used by the smoke test. This procedure does not deploy a function.

## Firebase Android/server identity comparison

`check-firebase-identity.mjs` accepts two local private input paths: production Android google-services JSON, then production Firebase server service-account JSON. Run only in a trusted private workspace, never commit inputs, and never paste credentials in chat. Success reports only project ID and match flags; failures suppress file paths, raw errors and contents. Eleven generated-fixture tests cover wrong project/packages/account/key and pass. Actual production server account has not been supplied or verified here. Existing APK build run 41085568765 and its non-expired HUNKART_Staff_Production_APKs artifact were rechecked successfully on 31 October; that build does not prove server-side credential readiness.

Earlier-chat reconciliation: the user already confirmed downloading the server-account JSON and saving `FCM_SERVICE_ACCOUNT_JSON` plus `FCM_PROJECT_ID`. Do not repeat creation/provisioning or ask them to upload that JSON. Only the actual runtime identity/match remains unverified from this workspace. Production Android config was read and both package IDs matched `hunkart-production`. The candidate now uses the already-saved `FCM_PROJECT_ID` name and rejects every other project, including unrelated production projects. The newly introduced `HUNKART_FCM_PROJECT_ID` name is not required or used.

## Self-contained deployment source package

`deploymentPackage()` in package.mjs returns the future deployment fields (name, entrypoint_path, verify_jwt and files) without deploying anything or reading environment secrets. It includes exactly seven allowlisted source files, flattens imports deterministically, and rejects changed/missing/escaping local imports. Add the reviewed project_id only at a separately authorized future deployment; never invoke deployment from a test. No test fixture, SQL, APK config, account JSON or keystore is included.

`test-package.mjs` passes 38 checks. The flattened package was actually type-checked in Deno 2.9.6 and passed the four disabled entrypoint tests without network permission. Source manifest SHA-256 values are available through packageManifest(). Hosted gateway configuration and an actual deployed-disabled smoke test remain pending. The package's verify_jwt=false is scoped to this worker because its handler checks a one-time capability; it does not alter any existing function setting.

Enabled-path follow-up: test-enabled-entrypoint.ts passed Deno type-check and 19 integration assertions against the actual flattened worker entrypoint and Supabase/OAuth/FCM modules. All transport is intercepted and credentials are generated fixtures. It verifies capability consumption before claims/sends, native payload/priority, correct lease acknowledgement, replay denial, transient provider failure/retry and disabled gating. Run without network/environment permissions; no hosted service or real notification is contacted. This is transport-mocked integration, not a live E2E or service-account validation.

## Remaining gates

Full backup and restore evidence; reviewed installer and grants/trigger comparison; exact Firebase APK/server project match; server credential provisioning; Supabase deployment bundle verification; deployed disabled-function smoke test; enabled staging-equivalent provider test; cancellation/refund/order E2E; controlled activation authorization. None of these is implied by local tests. No schedules are added by this draft.

Emergency stop first disables both database flags and sets `HUNKART_STAFF_WORKER_ENABLED=false`; in-flight sends may already have been accepted by providers. Preserve queues and all order/payment/refund records. Restore prior pages separately. Do not claim this flag-only stop restores old database definitions.

Tests: `node dispatch-update/production-staff-worker/test.mjs`.

Documentation checked 31 October 2026: Supabase Edge Function secrets and authorization headers. Changelog index retrieved; TLS cipher deprecation and Postgres release notes require review for the actual deployment runtime before activation. No platform change is applied here.
