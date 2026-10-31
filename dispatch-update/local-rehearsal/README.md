# Isolated schema-fixture installer rehearsal

Run `npm ci`, then `npm test -- /protected/catalog-fixture.json /protected/baseline-functions.json` in this directory. The two schema-only fixture inputs must be prepared and kept in a protected local location; they are NOT shipped or uploaded to GitHub. The dependency is pinned and locked. It uses an in-memory PGlite database only; the runner has no Supabase client, network connection string, production rows, secret reads, cron scheduler or real payment/push calls. Never run workflow.sql or these fixture adapters in any hosted database.

## Result — 31 October 2026

40 assertions passed on PostgreSQL 18.6 / PGlite 0.5.13. Read-only production metadata reported PostgreSQL 17.6. This is an additional local rehearsal, not a production-version restore drill or a replacement for the earlier authenticated staging/phone tests.

Coverage: a forced late installation error rolls back schema, public APIs and cancellation constraint changes; valid installation leaves both flags OFF; repeat installation refuses; legacy tracking triggers and sync function survive; private tables retain RLS; anonymous and authenticated worker API access is refused; actual authenticated rider profile call succeeds; private offers cannot be selected directly; service-role claim is empty while notification gate is OFF. Synthetic order coverage includes cancellation-window/payment/ownership denials, keeper acceptance, preparation ordering, rider offer/accept/idempotence, start delivery and existing status-sync trigger, shop rejection and refund queue. Emergency stop preserves orders and refund rows.

## Exact fixture limitations

- The private catalog input used locally contained column types/defaults/nullability and table constraints from 14 scoped relations plus the existing tracking sync function, captured by read-only queries. It contained no table rows or customer identities and was not a full schema/ACL/trigger backup. Its expected fields are tables (nspname, relname, columns with name/type/default/not_null), constraints (schema/table/name/definition) and tracking_sync. Do not commit its contents.
- The private function input is an array of proname/definition records for valid_explanation, held and guard_fulfilment. It is not included in this repository. Fixture auth users/customers and JWT helpers are minimal local adapters. The order_kind helper returns food; note_progress is a no-op. Real category/lifecycle behavior is not validated here.
- Both existing delivery_tracking triggers are reproduced. Other production triggers, signup, cancellation/order guards, default privileges, RLS policies and external integrations are not fully reproduced.
- PGlite cannot load pg_net: the harness strictly replaces the single extension prerequisite check and the single CREATE EXTENSION declaration IN MEMORY. The checked-in production installer remains unchanged. net.http_post is a local function that always raises; no network is sent. pg_net scheduling/delivery is NOT tested.
- The test intentionally fails an install near its final COMMIT and verifies rollback before running a valid install. It changes only this disposable in-memory database.
- OTP issuance/delivery completion uses existing production/staging APIs outside this installer and is not recreated. No live payment/refund execution, provider delivery, phone UI, APK installation, background siren or hosted Edge bundling is proved by this fixture.
- Single-process execution does not prove multi-session race/deadlock behavior, production load or timing under real cron. Keep those release gates pending.

The broad production SQL activation previously rejected by automatic approval review is not attempted or split by this harness. All draft-only boundaries remain in force.
