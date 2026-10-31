# Staff dispatch backup and restore preparation — 31 October 2026

Status: DRAFT. No backup export, restore, migration or production activation was performed in this checkpoint. Catalog compatibility reads are not a recoverable backup. A complete rollback must not be marked ready from these reads alone.

## Evidence to collect before installation

Use a protected location outside the repository and browser assets. Keep database credentials, customer data, push subscriptions, OTPs and private function definitions out of GitHub/Cloudflare/CI logs. Record only a manifest of timestamps, tool/database versions, file sizes, SHA-256 hashes and restore outcomes in the release evidence. A hash alone does not prove a usable backup.

1. Capture a consistent recoverable database backup including application data, required custom schemas (notably hunkart_cancel), definitions, constraints, indexes, policies, ACLs, ownership and triggers. Record its consistency point and the handling of writes after that point. Do not export only public while omitting cancellation/refund state. Confirm Supabase platform backup/PITR availability and retention separately.
2. Export the current schema/roles with a current Supabase CLI after inspecting its `db dump --help`. Use supported filtering for platform-managed objects; a generic raw pg_dump restore can fail on managed schemas and reserved roles. Validate the exact custom schema list and inclusion of auth-linked identities needed by the restore target. No dump command is run by this document.
3. Separately preserve existing Edge Function source/version/configuration, cron definitions and enabled states, frontend main SHA, current staff APKs and certificates, and private secret recovery arrangements. SQL dumps do not back up deployed Edge Functions, actual Storage object bytes or secret provisioning. Cron definitions can contain credentials: do not paste them into reports.
4. Restore into a NEW isolated compatible test destination, not production or the existing active staging project. Keep outbound networking, refund workers, cron, webhooks, email/SMS/push and payment calls disabled before importing operational state. Never replay refund queues or real payments during the drill.
5. Verify constraints, grants, RLS, ownership, existing fulfilment/order-sync triggers, cancellation/refund relationships and row counts at the captured consistency point. Run synthetic role/OTP/workflow regression checks without contacting production services.
6. Rehearse the candidate installer on that isolated copy, both disabled and with synthetic fixtures. Confirm the two existing delivery_tracking triggers survive, unrelated functions remain identical and no client gains direct private-table access. Verify the proposed flag-only emergency stop, including in-flight requests and queued work.

## Restore versus emergency stop

The existing PRODUCTION_EMERGENCY_STOP.sql stops new dispatch/notification paths by flags and preserves records; it is not a full database restore. The production worker environment gate is a separate stop. Restore the preceding staff/admin frontend separately. Do not drop the dispatch schema or narrow cancellation actors if real shopkeeper cases exist.

A point-in-time database rollback after release can discard newer orders/payments/refund decisions. It needs a reconciliation plan and explicit release/incident authorization; do not automatically restore a stale snapshot over current production. Prefer stopping new paths and preserving queued records for review.

## Current blockers and next action

No database connection credential or protected backup/restore destination was available in this workspace. No attempt was made to retrieve secrets through SQL. Local psql, postgres, Docker and Supabase CLI were absent at this check. Connected SQL access supports metadata inspection, but does not by itself prove consistent full backup/PITR/restore capabilities. Next: establish a protected export/isolated restore route, record evidence, and keep release blocked until that drill succeeds. Do not request or paste database passwords in chat.

References checked: https://supabase.com/docs/guides/platform/backups and https://supabase.com/docs/guides/self-hosting/restore-from-platform . Recheck commands and platform restore behavior at execution time.
