import {PGlite} from '@electric-sql/pglite';
import {pgcrypto} from '@electric-sql/pglite/contrib/pgcrypto';
import {readFileSync} from 'node:fs';
const read=p=>readFileSync(new URL(p,import.meta.url),'utf8');
// Private schema exports are external inputs, never repository fixtures.
const [catalogPath,functionsPath]=process.argv.slice(2);
if(!catalogPath||!functionsPath)throw Error('Provide two protected local schema-fixture paths; do not commit private inputs');
const catalog=JSON.parse(readFileSync(catalogPath,'utf8'));
const functions=JSON.parse(readFileSync(functionsPath,'utf8'));
const db=new PGlite({extensions:{pgcrypto}});
const quote=s=>'"'+s.replaceAll('"','""')+'"';
let checks=0;
async function check(sql,label){const r=await db.query(sql);if(r.rows[0]?.ok!==true)throw Error('FAILED: '+label);checks++;}
async function denied(sql,label){await db.exec('SAVEPOINT denied');let failed=false;try{await db.exec(sql);}catch{failed=true;}await db.exec('ROLLBACK TO SAVEPOINT denied;RELEASE SAVEPOINT denied');if(!failed)throw Error('Expected denial: '+label);checks++;}
try{
 await db.exec(`
 CREATE ROLE anon;CREATE ROLE authenticated;CREATE ROLE service_role;
 CREATE SCHEMA auth;CREATE SCHEMA extensions;CREATE SCHEMA hunkart_cancel;CREATE SCHEMA net;
 CREATE EXTENSION pgcrypto WITH SCHEMA extensions;
 CREATE TABLE auth.users(id uuid PRIMARY KEY,email text,email_confirmed_at timestamptz);
 CREATE TABLE public.customers(id uuid PRIMARY KEY,full_name text);
 CREATE FUNCTION auth.uid() RETURNS uuid LANGUAGE sql AS $$SELECT nullif(current_setting('request.jwt.claim.sub',true),'')::uuid$$;
 CREATE FUNCTION auth.jwt() RETURNS jsonb LANGUAGE sql AS $$SELECT coalesce(nullif(current_setting('request.jwt.claims',true),''),'{}')::jsonb$$;
 GRANT USAGE ON SCHEMA auth TO authenticated,service_role;
 GRANT EXECUTE ON FUNCTION auth.uid(),auth.jwt() TO authenticated,service_role;
 CREATE FUNCTION net.http_post(url text,headers jsonb,body jsonb,timeout_milliseconds integer) RETURNS bigint LANGUAGE plpgsql AS $$BEGIN RAISE EXCEPTION 'Network forbidden in local fixture';END$$;
 `);
 for(const t of catalog.tables){
  const cols=t.columns.map(c=>quote(c.name)+' '+c.type+(c.default?' DEFAULT '+c.default:'')+(c.not_null?' NOT NULL':''));
  await db.exec(`CREATE TABLE ${quote(t.nspname)}.${quote(t.relname)}(${cols.join(',')});`);
 }
 await db.exec(functions.find(f=>f.proname==='valid_explanation').definition);
 for(const c of catalog.constraints.filter(c=>!c.definition.startsWith('FOREIGN KEY'))){await db.exec(`ALTER TABLE ${quote(c.schema)}.${quote(c.table)} ADD CONSTRAINT ${quote(c.name)} ${c.definition};`);}
 for(const c of catalog.constraints.filter(c=>c.definition.startsWith('FOREIGN KEY'))){await db.exec(`ALTER TABLE ${quote(c.schema)}.${quote(c.table)} ADD CONSTRAINT ${quote(c.name)} ${c.definition};`);}
 await db.exec(functions.find(f=>f.proname==='held').definition);
 // Explicit fixture adapters, not recovered production functions.
 await db.exec(`
 CREATE FUNCTION hunkart_cancel.order_kind(uuid) RETURNS text LANGUAGE sql AS $$SELECT 'food'::text$$;
 CREATE FUNCTION hunkart_cancel.note_progress(uuid,boolean,boolean) RETURNS void LANGUAGE plpgsql AS $$BEGIN RETURN;END$$;
 CREATE FUNCTION public.is_app_admin() RETURNS boolean LANGUAGE sql SECURITY DEFINER SET search_path='' AS $$SELECT EXISTS(SELECT 1 FROM auth.users u JOIN public.app_admins a ON lower(a.email)=lower(u.email) WHERE u.id=auth.uid() AND u.email_confirmed_at IS NOT NULL)$$;
 `);
 await db.exec(functions.find(f=>f.proname==='guard_fulfilment').definition);
 await db.exec(catalog.tracking_sync);
 await db.exec(`CREATE TRIGGER hc_guard_delivery_fulfilment BEFORE INSERT OR UPDATE ON public.delivery_tracking FOR EACH ROW EXECUTE FUNCTION hunkart_cancel.guard_fulfilment();
 CREATE TRIGGER sync_order_status_from_delivery_trigger AFTER INSERT OR UPDATE OF status ON public.delivery_tracking FOR EACH ROW EXECUTE FUNCTION public.sync_order_status_from_delivery();`);
 const before=(await db.query("SELECT pg_get_functiondef('public.sync_order_status_from_delivery()'::regprocedure) AS body")).rows[0].body;
 let installer=read('../PRODUCTION_INSTALL_REVIEW_ONLY.sql');
 const guard="IF NOT EXISTS(SELECT 1 FROM pg_extension WHERE extname='pg_net') THEN";
 if(installer.split(guard).length!==2)throw Error('Expected one pg_net extension guard');
 // PGlite cannot load pg_net. Adapt that prerequisite and its CREATE EXTENSION
 // only; the no-network fixture function always raises. Disk SQL stays intact.
 installer=installer.replace(guard,"IF to_regnamespace('net') IS NULL THEN");
 const extension='create extension if not exists pg_net with schema extensions;';
 if(installer.split(extension).length!==2)throw Error('Expected one pg_net declaration');
 installer=installer.replace(extension,'-- pg_net unavailable: local no-network fixture only');
 // Force a late error to verify the transaction cannot leave half an install.
 if(!installer.endsWith('COMMIT;\n'))throw Error('Unexpected installer transaction tail');
 let lateFailure=false;
 try{await db.exec(installer.slice(0,-8)+"DO $$ BEGIN RAISE EXCEPTION 'Synthetic late install failure'; END $$;\nCOMMIT;\n");}catch{lateFailure=true;}
 await db.exec('ROLLBACK');
 if(!lateFailure)throw Error('Expected synthetic install failure');checks++;
 await check("SELECT to_regnamespace('hunkart_dispatch') IS NULL AS ok",'failed installation leaves no schema');
 await check("SELECT pg_get_constraintdef(oid) NOT LIKE '%shopkeeper%' AS ok FROM pg_constraint WHERE conrelid='hunkart_cancel.cases'::regclass AND conname='cases_actor_check'",'failed installation restores cancellation constraint');
 await check("SELECT NOT EXISTS(SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace WHERE n.nspname='public' AND left(p.proname,3)='hd_') AS ok",'failed installation leaves no public API');
 await db.exec(installer);
 await check("SELECT NOT enabled AS ok FROM hunkart_dispatch.settings",'dispatch stays disabled');
 await check("SELECT NOT enabled AS ok FROM hunkart_dispatch.staff_notification_settings",'notifications stay disabled');
 await check("SELECT count(*)=2 AS ok FROM pg_trigger WHERE tgrelid='public.delivery_tracking'::regclass AND tgname IN ('hc_guard_delivery_fulfilment','sync_order_status_from_delivery_trigger')",'legacy tracking triggers survive');
 if((await db.query("SELECT pg_get_functiondef('public.sync_order_status_from_delivery()'::regprocedure) AS body")).rows[0].body!==before)throw Error('Legacy function changed');checks++;
 await check("SELECT bool_and(relrowsecurity) AS ok FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace WHERE n.nspname='hunkart_dispatch' AND c.relkind='r'",'private tables RLS');
 await check("SELECT NOT EXISTS(SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace WHERE n.nspname='public' AND left(p.proname,3)='hd_' AND has_function_privilege('anon',p.oid,'execute')) AS ok",'anonymous API denied');
 await check("SELECT NOT has_function_privilege('authenticated','public.hd_claim_staff_notifications()','execute') AND has_function_privilege('service_role','public.hd_claim_staff_notifications()','execute') AS ok",'worker API service-only');
 await check("SELECT NOT has_table_privilege('authenticated','hunkart_dispatch.offers','select,insert,update,delete') AS ok",'private offer table inaccessible');
 await db.exec('BEGIN');
 await denied(installer,'second install rejected');
 await db.exec('ROLLBACK');
 await db.exec(read('./workflow.sql'));
 checks+=Number((await db.query('SELECT count(*) AS n FROM rehearsal_results')).rows[0].n);
 const rider=(await db.query('SELECT user_id FROM public.delivery_boys LIMIT 1')).rows[0].user_id;
 await db.exec('BEGIN');
 await db.query("SELECT set_config('request.jwt.claim.sub',$1,true)",[rider]);
 await db.exec('SET LOCAL ROLE authenticated');
 await check("SELECT public.hd_staff_profile('rider')->>'id' IS NOT NULL AS ok",'authenticated role can call authorized rider profile');
 await denied('SELECT * FROM hunkart_dispatch.offers','authenticated cannot bypass API for private offers');
 await denied('SELECT public.hd_claim_staff_notifications()','authenticated cannot claim worker jobs');
 await db.exec('RESET ROLE;SET LOCAL ROLE anon');
 await denied("SELECT public.hd_staff_profile('rider')",'anonymous role cannot execute staff profile');
 await db.exec('RESET ROLE');
 await db.query("SELECT set_config('request.jwt.claims',$1,true)",['{"role":"service_role"}']);
 await db.exec('SET LOCAL ROLE service_role');
 await check("SELECT public.hd_claim_staff_notifications()='[]'::jsonb AS ok",'worker role cannot claim while notification gate off');
 await db.exec('ROLLBACK');
 await db.exec(read('../PRODUCTION_EMERGENCY_STOP.sql'));
 await check("SELECT NOT enabled AS ok FROM hunkart_dispatch.settings",'emergency dispatch stop');
 await check("SELECT NOT enabled AS ok FROM hunkart_dispatch.staff_notification_settings",'emergency notification stop');
 await check("SELECT count(*)=2 AS ok FROM public.orders",'stop preserves synthetic orders');
 await check("SELECT count(*)=1 AS ok FROM hunkart_cancel.refunds",'stop preserves synthetic refund');
 const version=(await db.query('SELECT version() AS version')).rows[0].version;
 console.log(JSON.stringify({passed:checks,engine:version,scope:'schema-derived synthetic fixture; pg_net guard adapted; no real data/network/backup restore'},null,2));
}catch(error){console.error('LOCAL REHEARSAL FAILED:',error.message);process.exitCode=1;}
finally{await db.close();}
