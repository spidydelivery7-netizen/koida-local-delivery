# HUNKART staff notifications checkpoint — 29 October 2026

## Scope and authorization
Draft branch: work/shop-acceptance-rider-dispatch.
Staging: jjitqihblpubqwbggjpv. No live Supabase, main, Play Console or Razorpay changes in this work.
Do not enable or deploy to production based on these results alone.

## Implemented
- Staging-only staff notification outbox, eligibility checks, leases and bounded retries.
- Shop alerts after cancellation window; rider alerts bound to individual offer expiry.
- One-time 30-second scheduler capability, stored as SHA-256, atomic consumption; no permanent worker credential sent through pg_net.
- dispatch-staff-worker v2 deployed in staging.
- Both staff service workers suppress expired or malformed-expiry notifications, preserving legacy notifications without expiresAt.
- SQL, edge worker and tests saved together in this branch.

## Evidence
- test-staff-workflow.sql: 86 assertions passed in a transaction that rolled back.
- staff-worker/test.mjs: 35 worker/service-worker assertions passed against committed draft files.
- Earlier nonce test: first-use success, replay denial, expired denial, client-role EXECUTE denial passed.
- Real pg_net request ID 1 reached staging edge worker: HTTP 200, no timeout, counters all zero. This tests connection/authentication with notifications disabled, NOT real order delivery.
- Last baseline verification: dispatch enabled=false, staff notifications enabled=false; orders=0, staff subscriptions=0, staff outbox=0.
- Earlier separate browser transport test displayed a Windows notification. It did not register a staff device or validate order-triggered staff delivery.

## Remaining before release
1. Register actual staging keeper and rider devices, run controlled order-to-device test and confirm sound/vibration foreground/background. Browser/OS support must be observed, not assumed.
2. Exercise enabled scheduler with real controlled staging fixtures and provider subscriptions; zero-queue smoke test is not full scheduler proof.
3. Add bounded retention for expired one-time invocation rows before sustained enablement.
4. Review customer notification retry scheduling separately; current staff scheduler does not prove customer retries.
5. Recheck advisory findings before production. Current security advisor includes existing rls_auto_enable executable grants, leaked-password protection disabled, and authenticated delivery SECURITY DEFINER functions. Private queue tables intentionally have no client policies and revoked client grants; do not blindly add permissive policies.
6. pg_net queue ownership/grants remain platform-managed; attempted prior REVOKE did not change them. Do not claim otherwise. Raw invocation capability is short-lived/single-use but can temporarily appear there; no long-lived credentials.
7. Old hd_staff_worker_token / hd_staff_worker_url Vault entries may remain unused. Do not print them; cleanup is separate from VAPID.
8. All live release gates remain closed.

## Reproduce
- Staging SQL Editor: run dispatch-update/test-staff-workflow.sql (includes BEGIN and ROLLBACK).
- Node: node dispatch-update/staff-worker/test.mjs
- Never replace staging URL with production to run synthetic tests.
