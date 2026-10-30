import {readFileSync, writeFileSync} from 'node:fs';
import {fileURLToPath} from 'node:url';
import {dirname, join} from 'node:path';

// Offline assembler only. It neither connects to a database nor enables the feature.
const root=dirname(fileURLToPath(import.meta.url));
const ref=process.argv[2];
if (!ref || !/^[a-z0-9]{20}$/.test(ref)) throw new Error('Pass the reviewed 20-character production Supabase project ref');
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
const output=header+cancellationConstraint+sections.join('\n')+tail;
if(/cron\.schedule\s*\(/i.test(output)||output.includes(stagingRef)||/UPDATE hunkart_dispatch\.settings SET enabled=true/i.test(output))
 throw new Error('Production draft boundary check failed');
const path=join(root,'PRODUCTION_INSTALL_REVIEW_ONLY.sql');
writeFileSync(path,output);
console.log('Wrote review-only disabled installer: '+output.length+' bytes, '+files.length+' source fragments');
