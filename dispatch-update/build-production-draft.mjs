import {readFileSync, writeFileSync} from 'node:fs';
import {fileURLToPath} from 'node:url';
import {dirname, join} from 'node:path';

// Offline assembler only. It neither connects to a database nor enables the feature.
const root=dirname(fileURLToPath(import.meta.url));
const ref=process.argv[2];
if (ref!=='amnqqxgmqciipcortpmi') throw new Error('Only the reviewed HUNKART production project ref is accepted');
const files=[
 'candidate.sql','admin-helper.sql','admin-queue-v2.sql','staff-api-v2.sql',
 'shop-order-read-v2.sql','staff-profile.sql','staff-push-subscription.sql',
 'notification-outbox.sql','notification-worker-api.sql',
 'native-fcm/device-registration.sql','staff-notifications.sql',
 'native-fcm/worker-delivery.sql'
];
const stagingRef='jjitqihblpubqwbggjpv';
const sections=files.map(file=>{
 let sql=readFileSync(join(root,file),'utf8');
 if(file==='staff-notifications.sql'){
  const schedule=/^select cron\.schedule\('hunkart-staff-notifications'.*\);\s*$/m;
  if(!schedule.test(sql))throw new Error('Expected staging cron statement changed');
  sql=sql.replace(schedule,'-- Cron is deliberately not scheduled in this disabled draft.');
  if(!sql.includes(stagingRef))throw new Error('Expected staging worker URL changed');
  sql=sql.replaceAll(stagingRef,ref);
 }
 if(sql.includes(stagingRef))throw new Error('Staging project ref remains in '+file);
 return `\n-- BEGIN ${file}\n${sql.trim()}\n-- END ${file}\n`;
});
const header=`-- REVIEW DRAFT: DO NOT EXECUTE UNTIL TRIGGERS, GRANTS, WORKER, BACKUP AND ROLLBACK ARE APPROVED.\n-- Generated from isolated HUNKART staff branch. No test fixtures, secrets or cron activation.\nBEGIN;\nDO $guard$ BEGIN\n IF to_regnamespace('hunkart_dispatch') IS NOT NULL THEN\n  RAISE EXCEPTION 'Expected a fresh hunkart_dispatch schema; stop and review existing install';\n END IF;\n IF to_regclass('public.orders') IS NULL OR to_regclass('public.shop_order_status') IS NULL\n    OR to_regclass('public.delivery_tracking') IS NULL THEN\n  RAISE EXCEPTION 'Required live order tables are missing';\n END IF;\nEND $guard$;\n`;
const cancellationConstraint=`\n-- The existing live actor constraint permits customer and admin only.\n-- Extend it for shopkeeper rejection while retaining both existing actors.\nDO $actor$ BEGIN\n IF (SELECT pg_get_constraintdef(oid) FROM pg_constraint\n      WHERE conrelid='hunkart_cancel.cases'::regclass AND conname='cases_actor_check')\n    IS DISTINCT FROM 'CHECK ((actor = ANY (ARRAY[''customer''::text, ''admin''::text])))' THEN\n  RAISE EXCEPTION 'Live cancellation actor constraint changed; review manually';\n END IF;\nEND $actor$;\nALTER TABLE hunkart_cancel.cases DROP CONSTRAINT cases_actor_check;\nALTER TABLE hunkart_cancel.cases ADD CONSTRAINT cases_actor_check CHECK (actor IN ('customer','admin','shopkeeper'));\n`;
const tail=`\n-- Explicitly leave both feature flags OFF after installation. No cron is installed here.\nUPDATE hunkart_dispatch.settings SET enabled=false WHERE singleton=true;\nUPDATE hunkart_dispatch.staff_notification_settings SET enabled=false WHERE singleton=true;\nCOMMIT;\n`;
// Fail before creating/replacing public entrypoints or touching shared tables.
// This is not proof of a full backup or authority to install the candidate.
const dependencies=`
DO $dependencies$
DECLARE item text;
BEGIN
 FOREACH item IN ARRAY ARRAY[
 'public.orders','public.order_items','public.products','public.shops',
 'public.shopkeepers','public.delivery_boys','public.delivery_tracking',
 'public.shop_order_status','public.staff_push_subscriptions',
 'public.customer_push_subscriptions','public.app_admins',
 'hunkart_cancel.cases','hunkart_cancel.settings','hunkart_cancel.refunds'
 ] LOOP
  IF to_regclass(item) IS NULL THEN RAISE EXCEPTION 'Missing required relation: %',item; END IF;
 END LOOP;
 FOREACH item IN ARRAY ARRAY['auth.uid()','auth.jwt()',
 'hunkart_cancel.held(uuid)','hunkart_cancel.order_kind(uuid)',
 'extensions.gen_random_bytes(integer)','extensions.digest(text,text)'] LOOP
  IF to_regprocedure(item) IS NULL THEN RAISE EXCEPTION 'Missing required function: %',item; END IF;
 END LOOP;
 IF NOT EXISTS(SELECT 1 FROM pg_extension WHERE extname='pg_net') THEN
  RAISE EXCEPTION 'Required pg_net extension missing';
 END IF;
 IF EXISTS(SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
 WHERE n.nspname='public' AND left(p.proname,3)='hd_') THEN
  RAISE EXCEPTION 'Existing hd_ API names require manual collision review';
 END IF;
 IF EXISTS(SELECT 1 FROM pg_trigger WHERE NOT tgisinternal
 AND tgrelid IN ('public.orders'::regclass,'public.shop_order_status'::regclass,'public.delivery_tracking'::regclass)
 AND tgname IN ('hd_guard_tracking','hd_guard_shop','hd_guard_confirmation','hd_queue_customer_notification')) THEN
  RAISE EXCEPTION 'Existing dispatch trigger names require manual collision review';
 END IF;
 IF to_regclass('public.hd_paid_unaccepted_orders') IS NOT NULL THEN
  RAISE EXCEPTION 'Existing dispatch index requires manual collision review';
 END IF;
END $dependencies$;
`;
const output=header+dependencies+cancellationConstraint+sections.join('\n')+tail;
if(/cron\.schedule\s*\(/i.test(output)||output.includes(stagingRef)||/UPDATE hunkart_dispatch\.settings SET enabled=true/i.test(output))
 throw new Error('Production draft boundary check failed');
const path=join(root,'PRODUCTION_INSTALL_REVIEW_ONLY.sql');
writeFileSync(path,output);
console.log('Wrote review-only disabled installer: '+output.length+' bytes, '+files.length+' source fragments');

