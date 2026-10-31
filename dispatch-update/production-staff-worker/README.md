# Production staff worker candidate — disabled, not deployed

This separate entrypoint removes the staging-only restriction without changing the tested staging worker. Source is reviewable only; do not deploy or enable from this checkpoint.

## Configuration contract

- Runtime URL must be exactly the production Supabase URL encoded in config.mjs.
- `HUNKART_STAFF_WORKER_ENABLED` defaults OFF; only the literal `true` allows a request to continue. Database dispatch and staff notification flags must also be enabled separately after release review.
- `HUNKART_FCM_PROJECT_ID` must equal the actual Firebase project used to build both production staff APKs. That value is not inferred or filled in by this draft. The APK google-services JSON is not a Firebase server service-account credential.
- `FCM_SERVICE_ACCOUNT_JSON` is server-only and must belong to that same production Firebase project. Do not copy staging credentials, commit secrets, or print them.
- `VAPID_PUBLIC_KEY` and `VAPID_PRIVATE_KEY` must form a matching pair. Existing subscriptions require their original pair. This draft never generates or replaces keys and never touches Razorpay secrets.
- Supabase supplies `SUPABASE_URL` and the existing server role credential used by the reviewed SQL RPC role checks. Key migration is outside this change.

## Authentication and deployment packaging

The future function slug is `dispatch-staff-worker`, matching the disabled SQL installer. Its platform JWT check must be off for this function only because the scheduler sends a short-lived one-use hex capability, not a user JWT. The handler strictly validates and hashes the bearer capability and consumes it atomically through `hd_consume_staff_worker_token` before claiming any jobs or contacting providers. Do not disable JWT verification on unrelated functions.

Bundle index.ts, handler.mjs, config.mjs and the imported staff-worker/core.mjs and native-fcm/{oauth,send,core}.mjs preserving relative paths. This entrypoint is not a self-contained single-file deployment. Provider calls have bounded timeouts.

31 October follow-up: Deno 2.9.6 type-check passed for the actual entrypoint and test-entrypoint.ts. Four entrypoint/import response checks passed with no network permission and no listener; 36 configuration/auth tests also passed under Deno. Dependency loading used an isolated npm node_modules directory because direct Deno registry fetching stalled. This confirms local Deno import/runtime behavior, not Supabase-hosted deployment packaging or enabled provider delivery.

Reproduce in an isolated test workspace with the same relative source tree and pinned @supabase/supabase-js 2.57.4, web-push 3.6.7 and @types/node 22.10.2 installed: run Deno from that workspace (its cwd must contain package.json/node_modules), `deno check --no-remote --node-modules-dir=manual dispatch-update/production-staff-worker/index.ts dispatch-update/production-staff-worker/test-entrypoint.ts`, then `deno run --no-remote --node-modules-dir=manual dispatch-update/production-staff-worker/test-entrypoint.ts`. No allow-net/env permissions are used by the smoke test. This procedure does not deploy a function.

## Firebase Android/server identity comparison

`check-firebase-identity.mjs` accepts two local private input paths: production Android google-services JSON, then production Firebase server service-account JSON. Run only in a trusted private workspace, never commit inputs, and never paste credentials in chat. Success reports only project ID and match flags; failures suppress file paths, raw errors and contents. Eleven generated-fixture tests cover wrong project/packages/account/key and pass. Actual production server account has not been supplied or verified here. Existing APK build run 41085568765 and its non-expired HUNKART_Staff_Production_APKs artifact were rechecked successfully on 31 October; that build does not prove server-side credential readiness.

## Remaining gates

Full backup and restore evidence; reviewed installer and grants/trigger comparison; exact Firebase APK/server project match; server credential provisioning; Supabase deployment bundle verification; deployed disabled-function smoke test; enabled staging-equivalent provider test; cancellation/refund/order E2E; controlled activation authorization. None of these is implied by local tests. No schedules are added by this draft.

Emergency stop first disables both database flags and sets `HUNKART_STAFF_WORKER_ENABLED=false`; in-flight sends may already have been accepted by providers. Preserve queues and all order/payment/refund records. Restore prior pages separately. Do not claim this flag-only stop restores old database definitions.

Tests: `node dispatch-update/production-staff-worker/test.mjs`.

Documentation checked 31 October 2026: Supabase Edge Function secrets and authorization headers. Changelog index retrieved; TLS cipher deprecation and Postgres release notes require review for the actual deployment runtime before activation. No platform change is applied here.
