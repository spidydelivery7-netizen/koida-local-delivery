-- REVIEW DRAFT: DO NOT EXECUTE UNTIL TRIGGERS, GRANTS, WORKER, BACKUP AND ROLLBACK ARE APPROVED.
-- Generated from isolated HUNKART staff branch. No test fixtures, secrets or cron activation.
BEGIN;
DO $guard$ BEGIN
 IF to_regnamespace('hunkart_dispatch') IS NOT NULL THEN
  RAISE EXCEPTION 'Expected a fresh hunkart_dispatch schema; stop and review existing install';
 END IF;
 IF to_regclass('public.orders') IS NULL OR to_regclass('public.shop_order_status') IS NULL
    OR to_regclass('public.delivery_tracking') IS NULL THEN
  RAISE EXCEPTION 'Required live order tables are missing';
 END IF;
END $guard$;

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

-- The existing live actor constraint permits customer and admin only.
-- Extend it for shopkeeper rejection while retaining both existing actors.
DO $actor$ BEGIN
 IF (SELECT pg_get_constraintdef(oid) FROM pg_constraint
      WHERE conrelid='hunkart_cancel.cases'::regclass AND conname='cases_actor_check')
    IS DISTINCT FROM 'CHECK ((actor = ANY (ARRAY[''customer''::text, ''admin''::text])))' THEN
  RAISE EXCEPTION 'Live cancellation actor constraint changed; review manually';
 END IF;
END $actor$;
ALTER TABLE hunkart_cancel.cases DROP CONSTRAINT cases_actor_check;
ALTER TABLE hunkart_cancel.cases ADD CONSTRAINT cases_actor_check CHECK (actor IN ('customer','admin','shopkeeper'));

-- BEGIN candidate.sql
-- Candidate only. Deploy disabled, then enable after role/race/refund tests.
-- All authenticated API functions authorize against server-owned staff tables.
create schema if not exists hunkart_dispatch;
revoke all on schema hunkart_dispatch from public,anon,authenticated;
create table if not exists hunkart_dispatch.settings(singleton boolean primary key default true check(singleton),enabled boolean not null default false);
insert into hunkart_dispatch.settings values(true,false) on conflict do nothing;
create table if not exists hunkart_dispatch.shop_acceptance(order_id uuid primary key references public.orders(id),shop_id uuid not null references public.shops(id),accepted_by uuid not null,accepted_at timestamptz not null default now());
create table if not exists hunkart_dispatch.presence(rider_id uuid primary key references public.delivery_boys(id),online boolean not null default false,lat double precision check(lat between -90 and 90),lng double precision check(lng between -180 and 180),seen_at timestamptz not null default now());
create table if not exists hunkart_dispatch.jobs(order_id uuid primary key references public.orders(id),created_at timestamptz not null default now(),state text not null default 'searching' check(state in ('searching','offered','assigned','attention','closed')),note text);
create table if not exists hunkart_dispatch.offers(id uuid primary key default gen_random_uuid(),order_id uuid not null references public.orders(id),rider_id uuid not null references public.delivery_boys(id),created_at timestamptz not null default now(),expires_at timestamptz not null,status text not null default 'pending' check(status in ('pending','accepted','declined','expired','cancelled')),unique(order_id,rider_id));
create unique index if not exists hd_one_pending_order on hunkart_dispatch.offers(order_id) where status='pending';
create unique index if not exists hd_one_pending_rider on hunkart_dispatch.offers(rider_id) where status='pending';
create index if not exists hd_search_jobs on hunkart_dispatch.jobs(created_at) where state in ('searching','offered');
alter table hunkart_dispatch.settings enable row level security;
alter table hunkart_dispatch.shop_acceptance enable row level security;
alter table hunkart_dispatch.presence enable row level security;
alter table hunkart_dispatch.jobs enable row level security;
alter table hunkart_dispatch.offers enable row level security;
revoke all on all tables in schema hunkart_dispatch from public,anon,authenticated;

create or replace function hunkart_dispatch.require_enabled() returns void language plpgsql set search_path='' as $$
begin if not exists(select 1 from hunkart_dispatch.settings where enabled) then raise exception 'Dispatch rollout is not enabled';end if;end $$;
create or replace function hunkart_dispatch.keeper(p_order uuid) returns uuid language plpgsql set search_path='' as $$
declare sid uuid;n integer;expected uuid;
begin
 if auth.uid() is null then raise exception 'Login required' using errcode='42501';end if;
 select shop_id into sid from public.orders where id=p_order;
 if not exists(select 1 from public.shopkeepers where user_id=auth.uid() and active and shop_id=sid) then raise exception 'Only the active assigned shopkeeper can act' using errcode='42501';end if;
 select count(distinct p.shop_id),(array_agg(distinct p.shop_id))[1] into n,expected from public.order_items i left join public.products p on p.id=i.product_id where i.order_id=p_order;
 if n<>1 or expected is distinct from sid or exists(select 1 from public.order_items i left join public.products p on p.id=i.product_id where i.order_id=p_order and (p.id is null or p.shop_id is distinct from sid)) then raise exception 'Shop ownership needs Admin review';end if;
 return sid;
end $$;
create or replace function hunkart_dispatch.rider() returns uuid language plpgsql set search_path='' as $$
declare rid uuid;begin
 if auth.uid() is null then raise exception 'Login required' using errcode='42501';end if;
 select id into rid from public.delivery_boys where user_id=auth.uid() and is_active;
 if rid is null then raise exception 'Active delivery partner required' using errcode='42501';end if;return rid;end $$;

create or replace function hunkart_dispatch.accept_shop_order(p_order_id uuid) returns jsonb language plpgsql security definer set search_path='' as $$
declare o public.orders%rowtype;sid uuid;
begin
 perform hunkart_dispatch.require_enabled();
 select * into o from public.orders where id=p_order_id for update;
 sid:=hunkart_dispatch.keeper(p_order_id);
 if o.payment_status is distinct from 'paid' or coalesce(o.payment_id,'')!~'^pay_[A-Za-z0-9]+$' then raise exception 'Verified paid order required';end if;
 if o.customer_cancel_until is null or clock_timestamp()<o.customer_cancel_until then raise exception 'Customer cancellation window is still open';end if;
 if exists(select 1 from hunkart_dispatch.shop_acceptance where order_id=o.id) and o.status in ('confirmed','preparing','packed','out_for_delivery','delivered') then return jsonb_build_object('ok',true,'already_accepted',true);end if;
 if o.status is distinct from 'new' then raise exception 'Order no longer awaiting acceptance';end if;
 if hunkart_cancel.held(o.id) then raise exception 'Cancellation review pending';end if;
 insert into public.shop_order_status(order_id,shop_id,status) values(o.id,sid,'confirmed') on conflict(order_id,shop_id) do update set status='confirmed',updated_at=now() where public.shop_order_status.status='new';
 if not found then raise exception 'Shop stage changed; refresh order';end if;
 update public.orders set status='confirmed',updated_at=now() where id=o.id;
 insert into hunkart_dispatch.shop_acceptance(order_id,shop_id,accepted_by) values(o.id,sid,auth.uid());
 insert into hunkart_dispatch.jobs(order_id) values(o.id);
 return jsonb_build_object('ok',true,'shop_status','confirmed');
end $$;

create or replace function hunkart_dispatch.reject_shop_order(p_order_id uuid,p_reason text) returns jsonb language plpgsql security definer set search_path='' as $$
declare o public.orders%rowtype;sid uuid;cid uuid;remaining bigint;
begin
 perform hunkart_dispatch.require_enabled();
 select * into o from public.orders where id=p_order_id for update;
 sid:=hunkart_dispatch.keeper(p_order_id);
 if p_reason is null or p_reason not in ('Item unavailable','Shop cannot fulfil order') then raise exception 'Choose a valid rejection reason';end if;
 if o.status is distinct from 'new' or o.payment_status is distinct from 'paid' then raise exception 'Only unaccepted paid orders can be rejected';end if;
 if o.customer_cancel_until is null or clock_timestamp()<o.customer_cancel_until then raise exception 'Customer cancellation window is still open';end if;
 if o.customer_id is null or coalesce(o.payment_id,'')!~'^pay_[A-Za-z0-9]+$' or o.total<1 then raise exception 'Refund details need Admin review';end if;
 if not exists(select 1 from hunkart_cancel.settings where enabled and full_refund_policy_accepted) or hunkart_cancel.held(o.id) then raise exception 'Cancellation/refund needs Admin review';end if;
 select round(o.total*100)::bigint-coalesce(sum(amount_paise),0) into remaining from hunkart_cancel.refunds where order_id=o.id;
 if remaining<100 then raise exception 'Refund already exists or no refundable balance';end if;
 insert into hunkart_cancel.cases(order_id,customer_id,opened_by,actor,request_type,reason,details,policy_kind,policy_version,status,admin_note,cancel_order,decided_by,decided_at)
 values(o.id,o.customer_id,auth.uid(),'shopkeeper','cancel',p_reason,'Shopkeeper rejected before acceptance: '||p_reason,hunkart_cancel.order_kind(o.id),'shop-rejection-v1','approved','Shop rejection; remaining paid amount queued for refund.',true,auth.uid(),now()) returning id into cid;
 insert into hunkart_cancel.refunds(case_id,order_id,payment_id,amount_paise,status) values(cid,o.id,o.payment_id,remaining,'queued');
 update public.orders set status='cancelled',updated_at=now() where id=o.id;
 return jsonb_build_object('ok',true,'refund_status','queued');
end $$;
-- Required in production installer after verifying exact previous constraint:
-- alter table hunkart_cancel.cases drop constraint cases_actor_check;
-- alter table hunkart_cancel.cases add constraint cases_actor_check check(actor in ('customer','admin','shopkeeper'));

create or replace function hunkart_dispatch.heartbeat(p_online boolean,p_lat double precision,p_lng double precision) returns jsonb language plpgsql security definer set search_path='' as $$
declare rid uuid;
begin
 perform hunkart_dispatch.require_enabled();rid:=hunkart_dispatch.rider();
 if p_online is null then raise exception 'Online state required';end if;
 if p_online and (p_lat is null or p_lng is null or not(p_lat between -90 and 90) or not(p_lng between -180 and 180)) then raise exception 'Valid current GPS required';end if;
 insert into hunkart_dispatch.presence(rider_id,online,lat,lng,seen_at) values(rid,p_online,p_lat,p_lng,clock_timestamp()) on conflict(rider_id) do update set online=excluded.online,lat=excluded.lat,lng=excluded.lng,seen_at=excluded.seen_at;
 -- Expiry worker handles outstanding offers; accept independently checks current presence.
 return jsonb_build_object('ok',true,'online',p_online);
end $$;

-- Worker runs every 10 seconds; no browser must remain open to expire requests.
create or replace function hunkart_dispatch.tick() returns void language plpgsql security definer set search_path='' as $$
declare j record;o public.orders%rowtype;rid uuid;s public.shops%rowtype;
begin
 if not exists(select 1 from hunkart_dispatch.settings where enabled) then return;end if;
 -- Serialize workers only, not customer cancellation transactions.
 if not pg_try_advisory_xact_lock(721184) then return;end if;
 for j in select * from hunkart_dispatch.jobs where state in ('searching','offered') order by created_at limit 50 loop
  select * into o from public.orders where id=j.order_id for update skip locked;
  if not found then continue;end if;
  if o.status not in ('confirmed','preparing','packed') or o.payment_status<>'paid' or exists(select 1 from public.delivery_tracking where order_id=o.id) then
   update hunkart_dispatch.offers set status='cancelled' where order_id=o.id and status='pending';
   update hunkart_dispatch.jobs set state=case when exists(select 1 from public.delivery_tracking where order_id=o.id) then 'assigned' else 'closed' end where order_id=o.id;continue;
  end if;
  if hunkart_cancel.held(o.id) then continue;end if;
  update hunkart_dispatch.offers f set status='expired' where f.order_id=o.id and f.status='pending' and (f.expires_at<=clock_timestamp() or not exists(select 1 from hunkart_dispatch.presence p join public.delivery_boys b on b.id=p.rider_id where p.rider_id=f.rider_id and p.online and b.is_active and p.seen_at>clock_timestamp()-interval '5 minutes'));
  if exists(select 1 from hunkart_dispatch.offers where order_id=o.id and status='pending') then continue;end if;
  if clock_timestamp()>j.created_at+interval '5 minutes' then update hunkart_dispatch.jobs set state='attention',note='No partner accepted within five minutes. Contact a partner or reassign.' where order_id=o.id;continue;end if;
  select * into s from public.shops where id=o.shop_id;
  if s.location_lat is null or s.location_lng is null then update hunkart_dispatch.jobs set state='attention',note='Shop GPS missing' where order_id=o.id;continue;end if;
  select p.rider_id into rid from hunkart_dispatch.presence p join public.delivery_boys b on b.id=p.rider_id
  where p.online and b.is_active and p.seen_at>clock_timestamp()-interval '5 minutes' and p.lat is not null and p.lng is not null
  and not exists(select 1 from hunkart_dispatch.offers f where f.rider_id=p.rider_id and (f.order_id=o.id or f.status='pending'))
  and not exists(select 1 from public.delivery_tracking t join public.orders x on x.id=t.order_id where t.delivery_boy_id=p.rider_id and t.status not in ('delivered','cancelled') and x.status not in ('delivered','cancelled'))
  order by (p.lat-s.location_lat)^2+(cos(radians(s.location_lat))*(p.lng-s.location_lng))^2,p.rider_id for update of p skip locked limit 1;
  if rid is null then update hunkart_dispatch.jobs set state='searching',note='Waiting for an online available partner' where order_id=o.id;continue;end if;
  insert into hunkart_dispatch.offers(order_id,rider_id,expires_at) values(o.id,rid,clock_timestamp()+interval '120 seconds');
  update hunkart_dispatch.jobs set state='offered',note=null where order_id=o.id;
 end loop;
end $$;

create or replace function hunkart_dispatch.my_offers() returns jsonb language plpgsql security definer set search_path='' as $$
declare rid uuid;
begin
 perform hunkart_dispatch.require_enabled();rid:=hunkart_dispatch.rider();
 return coalesce((select jsonb_agg(jsonb_build_object('id',f.id,'order_id',o.id,'order_number',o.order_number,'shop_name',s.name,'shop_lat',s.location_lat,'shop_lng',s.location_lng,'distance_km',o.distance_km,'expires_at',f.expires_at,'server_now',clock_timestamp())) from hunkart_dispatch.offers f join public.orders o on o.id=f.order_id join public.shops s on s.id=o.shop_id where f.rider_id=rid and f.status='pending' and f.expires_at>clock_timestamp() and o.status in ('confirmed','preparing','packed') and o.payment_status='paid' and not hunkart_cancel.held(o.id)), '[]'::jsonb);
end $$;

create or replace function hunkart_dispatch.respond(p_offer_id uuid,p_accept boolean) returns jsonb language plpgsql security definer set search_path='' as $$
declare rid uuid;oid uuid;f hunkart_dispatch.offers%rowtype;o public.orders%rowtype;p hunkart_dispatch.presence%rowtype;
begin
 perform hunkart_dispatch.require_enabled();rid:=hunkart_dispatch.rider();
 if p_accept is null then raise exception 'Accept or decline required';end if;
 select order_id into oid from hunkart_dispatch.offers where id=p_offer_id and rider_id=rid;
 if not found then raise exception 'Request access denied' using errcode='42501';end if;
 select * into o from public.orders where id=oid for update;
 select * into p from hunkart_dispatch.presence where rider_id=rid for update;
 select * into f from hunkart_dispatch.offers where id=p_offer_id for update;
 if f.status='accepted' and exists(select 1 from public.delivery_tracking where order_id=oid and delivery_boy_id=rid) then return jsonb_build_object('ok',true,'already_accepted',true);end if;
 if f.status<>'pending' or f.expires_at<=clock_timestamp() then raise exception 'Request expired or already answered';end if;
 if o.status not in ('confirmed','preparing','packed') or o.payment_status<>'paid' or hunkart_cancel.held(o.id) or exists(select 1 from public.delivery_tracking where order_id=oid) then raise exception 'Order no longer available';end if;
 if not p_accept then
  update hunkart_dispatch.offers set status='declined' where id=f.id;
  update hunkart_dispatch.jobs set state='searching' where order_id=oid;
  return jsonb_build_object('ok',true,'accepted',false);
 end if;
 if p.rider_id is null or not p.online or p.seen_at<=clock_timestamp()-interval '5 minutes' then raise exception 'Go online with current GPS first';end if;
 if exists(select 1 from public.delivery_tracking t join public.orders x on x.id=t.order_id where t.delivery_boy_id=rid and t.status not in ('delivered','cancelled') and x.status not in ('delivered','cancelled')) then raise exception 'Finish current delivery first';end if;
 insert into public.delivery_tracking(order_id,delivery_boy_id,status) values(oid,rid,'assigned');
 update hunkart_dispatch.offers set status='accepted' where id=f.id;
 update hunkart_dispatch.jobs set state='assigned',note=null where order_id=oid;
 return jsonb_build_object('ok',true,'accepted',true);
end $$;

create or replace function hunkart_dispatch.admin_queue() returns jsonb language plpgsql security definer set search_path='' as $$
begin
 if auth.uid() is null or not hunkart_dispatch.is_admin() then raise exception 'Admin required' using errcode='42501';end if;
 return coalesce((select jsonb_agg(jsonb_build_object('order_id',o.id,'order_number',o.order_number,'state',coalesce(j.state,'awaiting_shop'),'note',coalesce(j.note,'Shop has not accepted yet'))) from public.orders o left join hunkart_dispatch.jobs j on j.order_id=o.id where o.payment_status='paid' and o.status in ('new','confirmed','preparing','packed') and (j.state in ('attention','searching') or (o.status='new' and clock_timestamp()>o.customer_cancel_until+interval '2 minutes'))),'[]'::jsonb);
end $$;

-- Thin invoker wrappers; only authenticated users may execute privileged private functions.
-- Private schema is not exposed through PostgREST. Explicit function and schema grants
-- are needed for SECURITY INVOKER wrappers; implementations perform actor checks.
create or replace function public.hd_accept_shop_order(p_order_id uuid) returns jsonb language sql security invoker set search_path='' as $$select hunkart_dispatch.accept_shop_order(p_order_id)$$;
create or replace function public.hd_reject_shop_order(p_order_id uuid,p_reason text) returns jsonb language sql security invoker set search_path='' as $$select hunkart_dispatch.reject_shop_order(p_order_id,p_reason)$$;
create or replace function public.hd_heartbeat(p_online boolean,p_lat double precision,p_lng double precision) returns jsonb language sql security invoker set search_path='' as $$select hunkart_dispatch.heartbeat(p_online,p_lat,p_lng)$$;
create or replace function public.hd_my_offers() returns jsonb language sql security invoker set search_path='' as $$select hunkart_dispatch.my_offers()$$;
create or replace function public.hd_respond_offer(p_offer_id uuid,p_accept boolean) returns jsonb language sql security invoker set search_path='' as $$select hunkart_dispatch.respond(p_offer_id,p_accept)$$;
create or replace function public.hd_admin_queue() returns jsonb language sql security invoker set search_path='' as $$select hunkart_dispatch.admin_queue()$$;
revoke all on all functions in schema hunkart_dispatch from public,anon,authenticated;
grant usage on schema hunkart_dispatch to authenticated;
grant execute on function hunkart_dispatch.accept_shop_order(uuid),hunkart_dispatch.reject_shop_order(uuid,text),hunkart_dispatch.heartbeat(boolean,double precision,double precision),hunkart_dispatch.my_offers(),hunkart_dispatch.respond(uuid,boolean),hunkart_dispatch.admin_queue() to authenticated;
revoke all on function public.hd_accept_shop_order(uuid),public.hd_reject_shop_order(uuid,text),public.hd_heartbeat(boolean,double precision,double precision),public.hd_my_offers(),public.hd_respond_offer(uuid,boolean),public.hd_admin_queue() from public,anon;
grant execute on function public.hd_accept_shop_order(uuid),public.hd_reject_shop_order(uuid,text),public.hd_heartbeat(boolean,double precision,double precision),public.hd_my_offers(),public.hd_respond_offer(uuid,boolean),public.hd_admin_queue() to authenticated;

create or replace function hunkart_dispatch.guard_tracking() returns trigger language plpgsql security definer set search_path='' as $$
declare o public.orders%rowtype;
begin
 if not exists(select 1 from hunkart_dispatch.settings where enabled) then return new;end if;
 if tg_op='UPDATE' and new.delivery_boy_id=old.delivery_boy_id and new.status=old.status then return new;end if;
 if new.status not in ('assigned','out_for_delivery') then return new;end if;
 select * into o from public.orders where id=new.order_id for update;
 if o.payment_status<>'paid' or o.status not in ('confirmed','preparing','packed','out_for_delivery') or hunkart_cancel.held(o.id) then raise exception 'Order not eligible for delivery assignment';end if;
 if new.status='out_for_delivery' then
  if o.status not in ('packed','out_for_delivery') then raise exception 'Shop must mark Packed before pickup';end if;
  return new;
 end if;
 if tg_op='UPDATE' and old.status in ('out_for_delivery','delivered') then raise exception 'Delivery has already started';end if;
 perform 1 from hunkart_dispatch.presence p join public.delivery_boys b on b.id=p.rider_id where p.rider_id=new.delivery_boy_id and b.is_active and p.online and p.seen_at>clock_timestamp()-interval '5 minutes' for update of p;
 if not found then raise exception 'Partner must be online with recent GPS';end if;
 if exists(select 1 from public.delivery_tracking t join public.orders x on x.id=t.order_id where t.delivery_boy_id=new.delivery_boy_id and t.order_id<>new.order_id and t.status not in ('delivered','cancelled') and x.status not in ('delivered','cancelled'))
 or exists(select 1 from hunkart_dispatch.offers where rider_id=new.delivery_boy_id and order_id<>new.order_id and status='pending' and expires_at>clock_timestamp()) then raise exception 'Partner already busy or reserved';end if;
 update hunkart_dispatch.offers set status='cancelled' where order_id=new.order_id and status='pending';
 update hunkart_dispatch.jobs set state='assigned',note='Assignment recorded' where order_id=new.order_id;
 return new;
end $$;
create or replace function hunkart_dispatch.guard_shop() returns trigger language plpgsql security definer set search_path='' as $$
declare o public.orders%rowtype;previous text;
begin
 if not exists(select 1 from hunkart_dispatch.settings where enabled) then return new;end if;
 if tg_op='UPDATE' and new.status=old.status then return new;end if;
 if new.status='new' then return new;end if;
 select * into o from public.orders where id=new.order_id for update;
 if not exists(select 1 from public.shopkeepers where user_id=auth.uid() and active and shop_id=new.shop_id and shop_id=o.shop_id) then raise exception 'Active assigned shopkeeper required' using errcode='42501';end if;
 if o.payment_status<>'paid' or o.status not in ('new','confirmed','preparing') or clock_timestamp()<o.customer_cancel_until then raise exception 'Order cannot be prepared';end if;
 previous:=case when tg_op='INSERT' then 'new' else old.status end;
 if not ((previous='new' and new.status='confirmed') or (previous in ('confirmed','new') and new.status='preparing' and o.status in ('confirmed','preparing')) or (previous='preparing' and new.status='ready') or (previous='ready' and new.status='packed')) then raise exception 'Follow Accept, Preparing, Ready, Packed in order';end if;
 return new;
end $$;
create or replace function hunkart_dispatch.guard_confirmation() returns trigger language plpgsql security definer set search_path='' as $$
begin
 if old.status='new' and new.status='confirmed' and exists(select 1 from hunkart_dispatch.settings where enabled) then
  perform hunkart_dispatch.keeper(old.id);
  if old.payment_status<>'paid' or old.customer_cancel_until is null or clock_timestamp()<old.customer_cancel_until then raise exception 'Paid order after cancellation window required';end if;
 end if;return new;
end $$;
drop trigger if exists hd_guard_tracking on public.delivery_tracking;
create trigger hd_guard_tracking before insert or update on public.delivery_tracking for each row execute function hunkart_dispatch.guard_tracking();
drop trigger if exists hd_guard_shop on public.shop_order_status;
create trigger hd_guard_shop before insert or update on public.shop_order_status for each row execute function hunkart_dispatch.guard_shop();
drop trigger if exists hd_guard_confirmation on public.orders;
create trigger hd_guard_confirmation before update on public.orders for each row execute function hunkart_dispatch.guard_confirmation();
revoke all on function hunkart_dispatch.guard_tracking(),hunkart_dispatch.guard_shop(),hunkart_dispatch.guard_confirmation() from public,anon,authenticated;
create or replace function hunkart_dispatch.my_deliveries() returns jsonb language plpgsql security definer set search_path='' as $$
begin
 perform hunkart_dispatch.rider();
 return coalesce((select jsonb_agg(to_jsonb(d)||jsonb_build_object('order_status',o.status,'shop_lat',s.location_lat,'shop_lng',s.location_lng,'shop_name',s.name)) from public.get_my_deliveries_v2() d join public.orders o on o.id=d.order_id left join public.shops s on s.id=o.shop_id where o.status<>'cancelled'),'[]'::jsonb);
end $$;
create or replace function public.hd_my_deliveries() returns jsonb language sql security invoker set search_path='' as $$select hunkart_dispatch.my_deliveries()$$;
revoke all on function hunkart_dispatch.my_deliveries(),public.hd_my_deliveries() from public,anon;
grant execute on function hunkart_dispatch.my_deliveries(),public.hd_my_deliveries() to authenticated;
-- END candidate.sql


-- BEGIN admin-helper.sql
create or replace function hunkart_dispatch.is_admin() returns boolean language plpgsql security definer set search_path='' as $$
declare result boolean;
begin
 if auth.uid() is null then return false;end if;
 if to_regprocedure('public.is_app_admin()') is not null then
  execute 'select coalesce(public.is_app_admin(),false)' into result;return result;
 end if;
 -- Staging schema has no legacy helper: use the server-owned allowlist and
 -- confirmed auth.users record; never trust user-editable metadata.
 return exists(select 1 from auth.users u join public.app_admins a on lower(a.email)=lower(u.email) where u.id=auth.uid() and u.email_confirmed_at is not null);
end $$;
revoke all on function hunkart_dispatch.is_admin() from public,anon,authenticated;
-- END admin-helper.sql


-- BEGIN admin-queue-v2.sql
create or replace function hunkart_dispatch.admin_queue() returns jsonb language plpgsql security definer set search_path='' as $$
begin
 if auth.uid() is null or not hunkart_dispatch.is_admin() then raise exception 'Admin required' using errcode='42501';end if;
 return coalesce((select jsonb_agg(jsonb_build_object('order_id',o.id,'order_number',o.order_number,'state',coalesce(j.state,'awaiting_shop'),'note',coalesce(j.note,'Shop has not accepted yet'))) from public.orders o left join hunkart_dispatch.jobs j on j.order_id=o.id where o.payment_status='paid' and o.status in ('new','confirmed','preparing','packed') and (j.state in ('attention','searching') or (o.status='new' and clock_timestamp()>o.customer_cancel_until+interval '2 minutes'))),'[]'::jsonb);
end $$;
-- END admin-queue-v2.sql


-- BEGIN staff-api-v2.sql
-- Self-contained staff APIs. Legacy production function definitions are not required.
create or replace function hunkart_dispatch.set_shop_stage(p_order_id uuid,p_status text)
returns jsonb language plpgsql security definer set search_path='' as $$
declare o public.orders%rowtype;sid uuid;previous text;
begin
 perform hunkart_dispatch.require_enabled();
 select * into o from public.orders where id=p_order_id for update;
 sid:=hunkart_dispatch.keeper(p_order_id);
 if p_status is null or p_status not in ('preparing','ready','packed') then raise exception 'Invalid preparation stage';end if;
 if o.payment_status<>'paid' or o.status not in ('confirmed','preparing','packed') or hunkart_cancel.held(o.id) then raise exception 'Order cannot be prepared';end if;
 select status into previous from public.shop_order_status where order_id=o.id and shop_id=sid for update;
 if previous=p_status then return jsonb_build_object('ok',true,'shop_status',p_status,'already_saved',true,'all_shops_packed',p_status='packed');end if;
 if not ((p_status='preparing' and previous in ('new','confirmed') and o.status='confirmed') or (p_status='ready' and previous='preparing') or (p_status='packed' and previous='ready')) then raise exception 'Follow Accept, Preparing, Ready, Packed in order';end if;
 update public.shop_order_status set status=p_status,packed_at=case when p_status='packed' then now() else packed_at end,updated_at=now() where order_id=o.id and shop_id=sid;
 update public.orders set status=case when p_status='packed' then 'packed' else 'preparing' end,updated_at=now() where id=o.id;
 return jsonb_build_object('ok',true,'shop_status',p_status,'all_shops_packed',p_status='packed');
end $$;
create or replace function public.hd_set_shop_stage(p_order_id uuid,p_status text)
returns jsonb language sql security invoker set search_path='' as $$select hunkart_dispatch.set_shop_stage(p_order_id,p_status)$$;
revoke all on function hunkart_dispatch.set_shop_stage(uuid,text),public.hd_set_shop_stage(uuid,text) from public,anon;
grant execute on function hunkart_dispatch.set_shop_stage(uuid,text),public.hd_set_shop_stage(uuid,text) to authenticated;

create or replace function hunkart_dispatch.start_delivery(p_order_id uuid,p_lat double precision,p_lng double precision,p_accuracy double precision default null)
returns jsonb language plpgsql security definer set search_path='' as $$
declare rid uuid;o public.orders%rowtype;t public.delivery_tracking%rowtype;
begin
 perform hunkart_dispatch.require_enabled();rid:=hunkart_dispatch.rider();
 if p_lat is null or p_lng is null or not(p_lat between -90 and 90) or not(p_lng between -180 and 180) or (p_accuracy is not null and not(p_accuracy>=0 and p_accuracy<'Infinity'::double precision)) then raise exception 'Valid current GPS required';end if;
 select * into o from public.orders where id=p_order_id for update;
 select * into t from public.delivery_tracking where order_id=p_order_id and delivery_boy_id=rid for update;
 if t.id is null then raise exception 'Assigned delivery not found' using errcode='42501';end if;
 if o.payment_status<>'paid' or o.status not in ('packed','out_for_delivery') or t.status not in ('assigned','out_for_delivery') or hunkart_cancel.held(o.id) then raise exception 'Shop must mark Packed before pickup';end if;
 update public.delivery_tracking set status='out_for_delivery',current_lat=p_lat,current_lng=p_lng,location_accuracy=p_accuracy,location_updated_at=now(),started_at=coalesce(started_at,now()) where id=t.id;
 update public.orders set status='out_for_delivery',updated_at=now() where id=o.id;
 return jsonb_build_object('success',true,'status','out_for_delivery');
end $$;
create or replace function public.hd_start_delivery(p_order_id uuid,p_lat double precision,p_lng double precision,p_accuracy double precision default null)
returns jsonb language sql security invoker set search_path='' as $$select hunkart_dispatch.start_delivery(p_order_id,p_lat,p_lng,p_accuracy)$$;
revoke all on function hunkart_dispatch.start_delivery(uuid,double precision,double precision,double precision),public.hd_start_delivery(uuid,double precision,double precision,double precision) from public,anon;
grant execute on function hunkart_dispatch.start_delivery(uuid,double precision,double precision,double precision),public.hd_start_delivery(uuid,double precision,double precision,double precision) to authenticated;

create or replace function hunkart_dispatch.my_deliveries() returns jsonb language plpgsql security definer set search_path='' as $$
declare rid uuid;
begin
 rid:=hunkart_dispatch.rider();
 return coalesce((select jsonb_agg(to_jsonb(x) order by x.created_at desc) from (
 select t.id as tracking_id,o.id as order_id,o.order_number,t.status as delivery_status,
 o.status as order_status,o.created_at,o.customer_name,o.phone,o.address,o.landmark,o.area,o.delivery_note,
 o.distance_km,o.delivery_lat,o.delivery_lng,o.total,o.payment_status,
 coalesce((select jsonb_agg(jsonb_build_object('product_name',i.product_name,'variant_label',i.variant_label,'variant',i.variant,'qty',i.qty,'line_total',i.line_total)) from public.order_items i where i.order_id=o.id),'[]'::jsonb) as items,
 t.location_updated_at,t.started_at,t.delivered_at,t.reached_at,t.reached_distance_m,
 s.name as shop_name,s.location_lat as shop_lat,s.location_lng as shop_lng
 from public.delivery_tracking t join public.orders o on o.id=t.order_id left join public.shops s on s.id=o.shop_id
 where t.delivery_boy_id=rid and o.status<>'cancelled'
 )x),'[]'::jsonb);
end $$;
revoke all on function hunkart_dispatch.my_deliveries() from public,anon;
grant execute on function hunkart_dispatch.my_deliveries() to authenticated;
-- END staff-api-v2.sql


-- BEGIN shop-order-read-v2.sql
create or replace function hunkart_dispatch.my_shop_orders() returns jsonb language plpgsql security definer set search_path='' as $$
begin
 perform hunkart_dispatch.require_enabled();
 if auth.uid() is null or not exists(select 1 from public.shopkeepers where user_id=auth.uid() and active) then raise exception 'Active assigned shopkeeper required' using errcode='42501';end if;
 return coalesce((select jsonb_agg(to_jsonb(x) order by x.created_at desc) from (
 select o.id as order_id,o.order_number,o.created_at,o.customer_cancel_until,o.customer_name,o.phone,o.address,o.landmark,o.area,o.delivery_note,o.payment_status,o.status as order_status,coalesce(sos.status,'new') as shop_status,sos.packed_at,
 coalesce((select jsonb_agg(jsonb_build_object('order_item_id',i.id,'product_id',i.product_id,'product_name',i.product_name,'variant_label',i.variant_label,'qty',i.qty)) from public.order_items i where i.order_id=o.id),'[]'::jsonb) as items
 from public.orders o left join public.shop_order_status sos on sos.order_id=o.id and sos.shop_id=o.shop_id
 where exists(select 1 from public.shopkeepers sk where sk.user_id=auth.uid() and sk.active and sk.shop_id=o.shop_id)
 and o.payment_status='paid' and o.status<>'cancelled' and o.customer_cancel_until<=clock_timestamp()
 )x),'[]'::jsonb);
end $$;
create or replace function public.hd_my_shop_orders() returns jsonb language sql security invoker set search_path='' as $$select hunkart_dispatch.my_shop_orders()$$;
revoke all on function hunkart_dispatch.my_shop_orders(),public.hd_my_shop_orders() from public,anon;
grant execute on function hunkart_dispatch.my_shop_orders(),public.hd_my_shop_orders() to authenticated;
-- END shop-order-read-v2.sql


-- BEGIN staff-profile.sql
create or replace function hunkart_dispatch.staff_profile(p_kind text) returns jsonb language plpgsql security definer set search_path='' as $$
declare sid uuid;r jsonb;
begin
 perform hunkart_dispatch.require_enabled();
 if auth.uid() is null then raise exception 'Please log in' using errcode='42501';end if;
 if p_kind='rider' then
 select jsonb_build_object('id',id,'full_name',full_name,'phone',phone,'is_active',is_active) into r from public.delivery_boys where user_id=auth.uid() and is_active=true;
 return r;
 elsif p_kind='keeper' then
 select shop_id into sid from public.shopkeepers where user_id=auth.uid() and active=true;
 if sid is null then return null;end if;
 select jsonb_build_object('shop',jsonb_build_object('id',s.id,'name',s.name,'active',s.active,'is_open',s.is_open,'reopens_at',s.reopens_at,'location_lat',s.location_lat,'location_lng',s.location_lng,'location_updated_at',s.location_updated_at),'products',coalesce((select jsonb_agg(jsonb_build_object('id',p.id,'shop_id',p.shop_id,'name',p.name,'category',p.category,'available',p.available,'is_available',p.is_available) order by p.category,p.name) from public.products p where p.shop_id=s.id),'[]'::jsonb)) into r from public.shops s where s.id=sid;
 return r;
 else raise exception 'Invalid staff profile';end if;
end $$;
create or replace function public.hd_staff_profile(p_kind text) returns jsonb language sql security invoker set search_path='' as $$select hunkart_dispatch.staff_profile(p_kind)$$;
revoke all on function hunkart_dispatch.staff_profile(text),public.hd_staff_profile(text) from public,anon;
grant execute on function hunkart_dispatch.staff_profile(text),public.hd_staff_profile(text) to authenticated;
-- END staff-profile.sql


-- BEGIN staff-push-subscription.sql
-- Staging-only staff subscription API; does not replace the production RPC.
create or replace function hunkart_dispatch.save_staff_subscription(p_role text,p_endpoint text,p_p256dh text,p_auth text,p_user_agent text default null)
returns boolean language plpgsql security definer set search_path='' as $$
declare uid uuid:=auth.uid(); changed integer;
begin
 if uid is null then raise exception 'Please log in' using errcode='42501';end if;
 if p_role is null or not (
 (p_role='shopkeeper' and exists(select 1 from public.shopkeepers where user_id=uid and active))
 or (p_role='delivery_boy' and exists(select 1 from public.delivery_boys where user_id=uid and is_active))
 or (p_role='admin' and hunkart_dispatch.is_admin())
 ) then raise exception 'Active staff role required' using errcode='42501';end if;
 if p_endpoint is null or length(p_endpoint)>2048 or p_endpoint !~ '^https://(fcm[.]googleapis[.]com|updates[.]push[.]services[.]mozilla[.]com|web[.]push[.]apple[.]com|[a-zA-Z0-9-]+([.][a-zA-Z0-9-]+)*[.]notify[.]windows[.]com)/[^[:space:]]+$'
 or p_p256dh is null or p_p256dh !~ '^[A-Za-z0-9_-]{87}=?$'
 or p_auth is null or p_auth !~ '^[A-Za-z0-9_-]{22}(==)?$' then raise exception 'Invalid push subscription';end if;
 insert into public.staff_push_subscriptions(user_id,role,endpoint,p256dh,auth_key,user_agent)
 values(uid,p_role,p_endpoint,p_p256dh,p_auth,left(p_user_agent,500))
 on conflict(endpoint) do update set role=excluded.role,p256dh=excluded.p256dh,auth_key=excluded.auth_key,user_agent=excluded.user_agent,updated_at=now()
 where public.staff_push_subscriptions.user_id=uid;
 get diagnostics changed=row_count;
 if changed<>1 then raise exception 'Browser subscription belongs to another account' using errcode='42501';end if;
 return true;
end $$;
create or replace function public.hd_save_staff_push_subscription(p_role text,p_endpoint text,p_p256dh text,p_auth text,p_user_agent text default null)
returns boolean language sql security invoker set search_path='' as $$
 select hunkart_dispatch.save_staff_subscription(p_role,p_endpoint,p_p256dh,p_auth,p_user_agent)
$$;
revoke all on function hunkart_dispatch.save_staff_subscription(text,text,text,text,text),public.hd_save_staff_push_subscription(text,text,text,text,text) from public,anon;
grant execute on function hunkart_dispatch.save_staff_subscription(text,text,text,text,text),public.hd_save_staff_push_subscription(text,text,text,text,text) to authenticated;
-- END staff-push-subscription.sql


-- BEGIN notification-outbox.sql
-- Durable notification intent. Delivery worker is a separate release requirement.
create table if not exists hunkart_dispatch.notification_outbox(
 id uuid primary key default gen_random_uuid(),order_id uuid not null references public.orders(id) on delete cascade,
 customer_id uuid not null,event_name text not null check(event_name in ('order_confirmed','shop_rejected')),
 payload jsonb not null,status text not null default 'pending' check(status in ('pending','sending','sent','failed')),
 attempts integer not null default 0,lease_until timestamptz,last_error text,created_at timestamptz not null default now(),sent_at timestamptz,
 unique(order_id,event_name)
);
alter table hunkart_dispatch.notification_outbox enable row level security;
revoke all on hunkart_dispatch.notification_outbox from public,anon,authenticated;
create index if not exists hd_notification_pending on hunkart_dispatch.notification_outbox(created_at) where status in ('pending','sending');
create or replace function hunkart_dispatch.queue_customer_notification() returns trigger language plpgsql security definer set search_path='' as $$
begin
 if not exists(select 1 from hunkart_dispatch.settings where enabled) or new.customer_id is null then return new;end if;
 if old.status='new' and new.status='confirmed' then
  insert into hunkart_dispatch.notification_outbox(order_id,customer_id,event_name,payload) values(new.id,new.customer_id,'order_confirmed',jsonb_build_object('title','HUNKART Order Confirmed','body','Order '||new.order_number||': shop accepted your order.','url','/')) on conflict(order_id,event_name) do nothing;
 elsif old.status='new' and new.status='cancelled' and exists(select 1 from hunkart_cancel.cases where order_id=new.id and actor='shopkeeper' and status='approved') then
  insert into hunkart_dispatch.notification_outbox(order_id,customer_id,event_name,payload) values(new.id,new.customer_id,'shop_rejected',jsonb_build_object('title','HUNKART order update','body','Shop could not fulfil order '||new.order_number||'. Refund is queued; bank confirmation is pending.','url','/')) on conflict(order_id,event_name) do nothing;
 end if;return new;
end $$;
revoke all on function hunkart_dispatch.queue_customer_notification() from public,anon,authenticated;
create trigger hd_queue_customer_notification after update on public.orders for each row execute function hunkart_dispatch.queue_customer_notification();
-- END notification-outbox.sql


-- BEGIN notification-worker-api.sql
alter table hunkart_dispatch.notification_outbox add column if not exists lease_token uuid;
create or replace function hunkart_dispatch.can_notify(p_order_id uuid) returns boolean language sql security definer set search_path='' as $$
 select auth.uid() is not null and exists(select 1 from public.orders o where o.id=p_order_id and (hunkart_dispatch.is_admin() or exists(select 1 from public.shopkeepers sk where sk.user_id=auth.uid() and sk.active and sk.shop_id=o.shop_id)));
$$;
create or replace function public.hd_can_notify(p_order_id uuid) returns boolean language sql security invoker set search_path='' as $$select hunkart_dispatch.can_notify(p_order_id)$$;
revoke all on function hunkart_dispatch.can_notify(uuid),public.hd_can_notify(uuid) from public,anon;
grant execute on function hunkart_dispatch.can_notify(uuid),public.hd_can_notify(uuid) to authenticated;
create or replace function hunkart_dispatch.claim_notifications(p_order_id uuid) returns jsonb language plpgsql security definer set search_path='' as $$
declare result jsonb;
begin
 if (auth.jwt()->>'role') is distinct from 'service_role' then raise exception 'Service worker required' using errcode='42501';end if;
 with claimed as (update hunkart_dispatch.notification_outbox n set status='sending',attempts=n.attempts+1,lease_token=gen_random_uuid(),lease_until=clock_timestamp()+interval '2 minutes' where n.order_id=p_order_id and n.attempts<10 and (n.status='pending' or (n.status='sending' and n.lease_until<clock_timestamp())) returning n.id,n.customer_id,n.payload,n.lease_token)
 select jsonb_agg(to_jsonb(c)) into result from claimed c;
 return coalesce(result,'[]'::jsonb);
end $$;
create or replace function public.hd_claim_notifications(p_order_id uuid) returns jsonb language sql security invoker set search_path='' as $$select hunkart_dispatch.claim_notifications(p_order_id)$$;
create or replace function hunkart_dispatch.ack_notification(p_id uuid,p_token uuid,p_status text,p_error text default null) returns void language plpgsql security definer set search_path='' as $$
begin
 if (auth.jwt()->>'role') is distinct from 'service_role' then raise exception 'Service worker required' using errcode='42501';end if;
 if p_status is null or p_status not in ('sent','retry','failed') then raise exception 'Invalid acknowledgement';end if;
 update hunkart_dispatch.notification_outbox set status=case when p_status='retry' and attempts<10 then 'pending' when p_status='sent' then 'sent' else 'failed' end,lease_until=null,last_error=left(p_error,300),sent_at=case when p_status='sent' then clock_timestamp() else null end where id=p_id and lease_token=p_token and status='sending';
end $$;
create or replace function public.hd_ack_notification(p_id uuid,p_token uuid,p_status text,p_error text default null) returns void language sql security invoker set search_path='' as $$select hunkart_dispatch.ack_notification(p_id,p_token,p_status,p_error)$$;
revoke all on function hunkart_dispatch.claim_notifications(uuid),public.hd_claim_notifications(uuid),hunkart_dispatch.ack_notification(uuid,uuid,text,text),public.hd_ack_notification(uuid,uuid,text,text) from public,anon,authenticated;
grant usage on schema hunkart_dispatch to service_role;
grant execute on function hunkart_dispatch.claim_notifications(uuid),public.hd_claim_notifications(uuid),hunkart_dispatch.ack_notification(uuid,uuid,text,text),public.hd_ack_notification(uuid,uuid,text,text) to service_role;
-- END notification-worker-api.sql


-- BEGIN native-fcm/device-registration.sql
create table if not exists hunkart_dispatch.native_devices (
 id bigint generated always as identity primary key,
 user_id uuid not null references auth.users(id) on delete cascade,
 role text not null check (role in ('shopkeeper','delivery_boy')),
 token text not null unique check (length(token) between 20 and 4096 and token !~ '[[:space:]]'),
 updated_at timestamptz not null default now()
);
alter table hunkart_dispatch.native_devices enable row level security;
revoke all on hunkart_dispatch.native_devices from public, anon, authenticated;

create or replace function hunkart_dispatch.save_native_device(p_role text,p_token text)
returns boolean language plpgsql security definer set search_path='' as $$
declare uid uuid:=auth.uid(); changed integer;
begin
 if uid is null then raise exception 'Please log in' using errcode='42501'; end if;
 if p_role is null or not (
  (p_role='shopkeeper' and exists(select 1 from public.shopkeepers where user_id=uid and active))
  or (p_role='delivery_boy' and exists(select 1 from public.delivery_boys where user_id=uid and is_active))
 ) then raise exception 'Active staff role required' using errcode='42501'; end if;
 if p_token is null or length(p_token) not between 20 and 4096 or p_token ~ '[[:space:]]' then
  raise exception 'Invalid device token' using errcode='22023'; end if;
 insert into hunkart_dispatch.native_devices(user_id,role,token)
 values(uid,p_role,p_token)
 on conflict(token) do update set role=excluded.role,updated_at=now()
 where hunkart_dispatch.native_devices.user_id=uid;
 get diagnostics changed=row_count;
 if changed<>1 then raise exception 'Device belongs to another account' using errcode='42501'; end if;
 return true;
end $$;
create or replace function hunkart_dispatch.remove_native_device(p_token text)
returns boolean language plpgsql security definer set search_path='' as $$
begin
 if auth.uid() is null then raise exception 'Please log in' using errcode='42501'; end if;
 delete from hunkart_dispatch.native_devices where user_id=auth.uid() and token=p_token;
 return found;
end $$;
create or replace function public.hd_save_native_device(p_role text,p_token text)
returns boolean language sql security invoker set search_path='' as $$
 select hunkart_dispatch.save_native_device(p_role,p_token)
$$;
create or replace function public.hd_remove_native_device(p_token text)
returns boolean language sql security invoker set search_path='' as $$
 select hunkart_dispatch.remove_native_device(p_token)
$$;
revoke all on function hunkart_dispatch.save_native_device(text,text),hunkart_dispatch.remove_native_device(text),public.hd_save_native_device(text,text),public.hd_remove_native_device(text) from public,anon;
grant usage on schema hunkart_dispatch to authenticated;
grant execute on function hunkart_dispatch.save_native_device(text,text),hunkart_dispatch.remove_native_device(text),public.hd_save_native_device(text,text),public.hd_remove_native_device(text) to authenticated;
-- END native-fcm/device-registration.sql


-- BEGIN staff-notifications.sql
-- Staging candidate. Both switches default OFF. No live installation authorized.
create extension if not exists pg_net with schema extensions;
create table if not exists hunkart_dispatch.staff_notification_settings(
 singleton boolean primary key default true check(singleton),
 enabled boolean not null default false,
 last_request_id bigint,last_requested_at timestamptz,last_error text
);
insert into hunkart_dispatch.staff_notification_settings(singleton) values(true) on conflict do nothing;
create table if not exists hunkart_dispatch.staff_notification_outbox(
 id uuid primary key default gen_random_uuid(),
 order_id uuid not null references public.orders(id) on delete cascade,
 offer_id uuid references hunkart_dispatch.offers(id) on delete cascade,
 recipient_id uuid not null references auth.users(id) on delete cascade,
 recipient_role text not null check(recipient_role in ('shopkeeper','delivery_boy')),
 event_name text not null check(event_name in ('shop_order_ready','rider_offer')),
 event_key text not null,
 expires_at timestamptz not null,
 status text not null default 'pending' check(status in ('pending','sending','sent','cancelled','failed')),
 attempts integer not null default 0,
 next_attempt_at timestamptz not null default now(),
 lease_token uuid,lease_until timestamptz,
 last_error text,created_at timestamptz not null default now(),sent_at timestamptz,
 unique(event_key,recipient_id),
 check((event_name='shop_order_ready' and recipient_role='shopkeeper' and offer_id is null) or
       (event_name='rider_offer' and recipient_role='delivery_boy' and offer_id is not null))
);
alter table hunkart_dispatch.staff_notification_settings enable row level security;
alter table hunkart_dispatch.staff_notification_outbox enable row level security;
revoke all on hunkart_dispatch.staff_notification_settings,hunkart_dispatch.staff_notification_outbox from public,anon,authenticated;
create index if not exists hd_staff_notice_pending on hunkart_dispatch.staff_notification_outbox(next_attempt_at,expires_at) where status in ('pending','sending');
create index if not exists hd_staff_notice_order on hunkart_dispatch.staff_notification_outbox(order_id);
create index if not exists hd_staff_notice_offer on hunkart_dispatch.staff_notification_outbox(offer_id);
create index if not exists hd_staff_notice_recipient on hunkart_dispatch.staff_notification_outbox(recipient_id);
create index if not exists hd_paid_unaccepted_orders on public.orders(customer_cancel_until,id) where status='new' and payment_status='paid';

create or replace function hunkart_dispatch.staff_notice_eligible(p_id uuid)
returns boolean language sql security definer set search_path='' as $$
 select exists(
 select 1 from hunkart_dispatch.staff_notification_outbox n
 join public.orders o on o.id=n.order_id
 where n.id=p_id and n.expires_at>clock_timestamp()
 and exists(select 1 from hunkart_dispatch.settings where enabled)
 and exists(select 1 from hunkart_dispatch.staff_notification_settings where enabled)
 and o.payment_status='paid' and not hunkart_cancel.held(o.id)
 and (
  (n.event_name='shop_order_ready' and o.status='new' and o.customer_cancel_until<=clock_timestamp()
   and exists(select 1 from public.shopkeepers k where k.user_id=n.recipient_id and k.shop_id=o.shop_id and k.active)
   and exists(select 1 from public.order_items i where i.order_id=o.id)
   and not exists(select 1 from public.order_items i left join public.products p on p.id=i.product_id where i.order_id=o.id and (p.id is null or p.shop_id is distinct from o.shop_id)))
  or
  (n.event_name='rider_offer' and o.status in ('confirmed','preparing','packed')
   and exists(select 1 from hunkart_dispatch.offers f
    join public.delivery_boys b on b.id=f.rider_id
    join hunkart_dispatch.presence pr on pr.rider_id=b.id
    where f.id=n.offer_id and f.order_id=o.id and f.status='pending' and f.expires_at>clock_timestamp()
    and b.user_id=n.recipient_id and b.is_active and pr.online and pr.seen_at>clock_timestamp()-interval '5 minutes'))
  )
 );
$$;

create or replace function hunkart_dispatch.enqueue_staff_notifications()
returns integer language plpgsql security definer set search_path='' as $$
declare n integer;total integer:=0;
begin
 if not exists(select 1 from hunkart_dispatch.settings where enabled)
 or not exists(select 1 from hunkart_dispatch.staff_notification_settings where enabled) then return 0;end if;
 -- Payment may be verified after insert; scanning eligibility also covers that transition.
 insert into hunkart_dispatch.staff_notification_outbox(order_id,recipient_id,recipient_role,event_name,event_key,expires_at)
 select o.id,k.user_id,'shopkeeper','shop_order_ready','shop:'||o.id,o.customer_cancel_until+interval '1 hour'
 from public.orders o join public.shopkeepers k on k.shop_id=o.shop_id and k.active
 where o.status='new' and o.payment_status='paid' and o.customer_cancel_until<=clock_timestamp()
 and o.customer_cancel_until>clock_timestamp()-interval '1 hour' and not hunkart_cancel.held(o.id)
 and exists(select 1 from public.order_items i where i.order_id=o.id)
 and not exists(select 1 from public.order_items i left join public.products p on p.id=i.product_id where i.order_id=o.id and (p.id is null or p.shop_id is distinct from o.shop_id))
 and not exists(select 1 from hunkart_dispatch.staff_notification_outbox n where n.event_key='shop:'||o.id and n.recipient_id=k.user_id)
 order by o.customer_cancel_until,o.id limit 200
 on conflict(event_key,recipient_id) do nothing;
 get diagnostics n=row_count;total:=total+n;
 insert into hunkart_dispatch.staff_notification_outbox(order_id,offer_id,recipient_id,recipient_role,event_name,event_key,expires_at)
 select f.order_id,f.id,b.user_id,'delivery_boy','rider_offer','offer:'||f.id,f.expires_at
 from hunkart_dispatch.offers f join public.delivery_boys b on b.id=f.rider_id and b.is_active
 join hunkart_dispatch.presence pr on pr.rider_id=b.id and pr.online
 join public.orders o on o.id=f.order_id
 where f.status='pending' and f.expires_at>clock_timestamp() and pr.seen_at>clock_timestamp()-interval '5 minutes'
 and o.status in ('confirmed','preparing','packed') and o.payment_status='paid' and not hunkart_cancel.held(o.id)
 and not exists(select 1 from hunkart_dispatch.staff_notification_outbox n where n.event_key='offer:'||f.id and n.recipient_id=b.user_id)
 order by f.expires_at limit 200 on conflict(event_key,recipient_id) do nothing;
 get diagnostics n=row_count;return total+n;
end $$;

create or replace function hunkart_dispatch.claim_staff_notifications()
returns jsonb language plpgsql security definer set search_path='' as $$
declare result jsonb;
begin
 if (auth.jwt()->>'role') is distinct from 'service_role' then raise exception 'Service worker required' using errcode='42501';end if;
 if not exists(select 1 from hunkart_dispatch.settings where enabled)
 or not exists(select 1 from hunkart_dispatch.staff_notification_settings where enabled) then return '[]'::jsonb;end if;
 update hunkart_dispatch.staff_notification_outbox n set status='cancelled',lease_until=null
 where n.status in ('pending','sending') and not hunkart_dispatch.staff_notice_eligible(n.id);
 update hunkart_dispatch.staff_notification_outbox set status='failed',lease_until=null,last_error='Retry limit reached'
 where attempts>=6 and (status='pending' or (status='sending' and lease_until<clock_timestamp()));
 with candidates as (
 select n.id from hunkart_dispatch.staff_notification_outbox n
 where n.attempts<6 and n.next_attempt_at<=clock_timestamp()
 and (n.status='pending' or (n.status='sending' and n.lease_until<clock_timestamp()))
 and hunkart_dispatch.staff_notice_eligible(n.id)
 order by (n.event_name='rider_offer') desc,n.expires_at,n.id
 limit 10 for update skip locked
 ), claimed as (
 update hunkart_dispatch.staff_notification_outbox n set status='sending',attempts=attempts+1,lease_token=gen_random_uuid(),lease_until=clock_timestamp()+interval '45 seconds'
 from candidates c where n.id=c.id returning n.id,n.lease_token
 ) select coalesce(jsonb_agg(to_jsonb(c)),'[]'::jsonb) into result from claimed c;
 return result;
end $$;

create or replace function hunkart_dispatch.staff_notification_delivery(p_id uuid,p_token uuid)
returns jsonb language plpgsql security definer set search_path='' as $$
declare n hunkart_dispatch.staff_notification_outbox%rowtype;subs jsonb;payload jsonb;ttl integer;
begin
 if (auth.jwt()->>'role') is distinct from 'service_role' then raise exception 'Service worker required' using errcode='42501';end if;
 select * into n from hunkart_dispatch.staff_notification_outbox where id=p_id and lease_token=p_token and status='sending' and lease_until>clock_timestamp() for update;
 if not found then return null;end if;
 if not hunkart_dispatch.staff_notice_eligible(n.id) then
  update hunkart_dispatch.staff_notification_outbox set status='cancelled',lease_until=null where id=n.id;return null;
 end if;
 ttl:=least(300,greatest(0,floor(extract(epoch from n.expires_at-clock_timestamp()))::integer));
 if ttl<1 then return null;end if;
 select coalesce(jsonb_agg(jsonb_build_object('endpoint',s.endpoint,'keys',jsonb_build_object('p256dh',s.p256dh,'auth',s.auth_key))),'[]'::jsonb)
 into subs from public.staff_push_subscriptions s where s.user_id=n.recipient_id and s.role=n.recipient_role;
 payload:=jsonb_build_object(
 'title',case when n.event_name='rider_offer' then 'HUNKART • Delivery offer' else 'HUNKART • New order' end,
 'body',case when n.event_name='rider_offer' then 'A delivery offer is waiting. Open the app to review before it expires.' else 'A paid order is ready for your shop. Open the app to accept or reject.' end,
 'url',case when n.event_name='rider_offer' then '/delivery-app/' else '/shopkeeper-app/' end,
 'tag','hd-'||n.id,'event',n.event_name,'orderId',n.order_id,'offerId',n.offer_id,'expiresAt',n.expires_at);
 return jsonb_build_object('subscriptions',subs,'payload',payload,'ttl',ttl);
end $$;

create or replace function hunkart_dispatch.ack_staff_notification(p_id uuid,p_token uuid,p_status text)
returns void language plpgsql security definer set search_path='' as $$
begin
 if (auth.jwt()->>'role') is distinct from 'service_role' then raise exception 'Service worker required' using errcode='42501';end if;
 if p_status is null or p_status not in ('sent','retry','failed') then raise exception 'Invalid acknowledgement';end if;
 update hunkart_dispatch.staff_notification_outbox n set
 status=case when p_status='sent' then 'sent' when not hunkart_dispatch.staff_notice_eligible(n.id) then 'cancelled' when p_status='retry' and attempts<6 then 'pending' else 'failed' end,
 lease_until=null,
 next_attempt_at=clock_timestamp()+case when event_name='rider_offer' then interval '3 seconds' else least(60,power(2,attempts)::integer*5)*interval '1 second' end,
 last_error=case when p_status='sent' then null else 'Notification delivery not confirmed' end,
 sent_at=case when p_status='sent' then clock_timestamp() else null end
 where n.id=p_id and n.lease_token=p_token and n.status='sending' and n.lease_until>clock_timestamp();
end $$;

create or replace function public.hd_claim_staff_notifications() returns jsonb language sql security invoker set search_path='' as $$select hunkart_dispatch.claim_staff_notifications()$$;
create or replace function public.hd_staff_notification_delivery(p_id uuid,p_token uuid) returns jsonb language sql security invoker set search_path='' as $$select hunkart_dispatch.staff_notification_delivery(p_id,p_token)$$;
create or replace function public.hd_ack_staff_notification(p_id uuid,p_token uuid,p_status text) returns void language sql security invoker set search_path='' as $$select hunkart_dispatch.ack_staff_notification(p_id,p_token,p_status)$$;
revoke all on function hunkart_dispatch.staff_notice_eligible(uuid),hunkart_dispatch.enqueue_staff_notifications() from public,anon,authenticated,service_role;
revoke all on function hunkart_dispatch.claim_staff_notifications(),hunkart_dispatch.staff_notification_delivery(uuid,uuid),hunkart_dispatch.ack_staff_notification(uuid,uuid,text),public.hd_claim_staff_notifications(),public.hd_staff_notification_delivery(uuid,uuid),public.hd_ack_staff_notification(uuid,uuid,text) from public,anon,authenticated;
grant execute on function hunkart_dispatch.claim_staff_notifications(),hunkart_dispatch.staff_notification_delivery(uuid,uuid),hunkart_dispatch.ack_staff_notification(uuid,uuid,text),public.hd_claim_staff_notifications(),public.hd_staff_notification_delivery(uuid,uuid),public.hd_ack_staff_notification(uuid,uuid,text) to service_role;

create table if not exists hunkart_dispatch.staff_worker_invocations(
 id uuid primary key default gen_random_uuid(),token_hash text not null unique,
 expires_at timestamptz not null,consumed_at timestamptz,created_at timestamptz not null default now()
);
alter table hunkart_dispatch.staff_worker_invocations enable row level security;
revoke all on hunkart_dispatch.staff_worker_invocations from public,anon,authenticated;
create index if not exists hd_staff_invocation_expiry on hunkart_dispatch.staff_worker_invocations(expires_at);
create or replace function hunkart_dispatch.consume_staff_worker_token(p_hash text)
returns boolean language plpgsql security definer set search_path='' as $$
declare n integer;
begin
 if (auth.jwt()->>'role') is distinct from 'service_role' then raise exception 'Service worker required' using errcode='42501';end if;
 update hunkart_dispatch.staff_worker_invocations set consumed_at=clock_timestamp()
 where token_hash=p_hash and consumed_at is null and expires_at>clock_timestamp();
 get diagnostics n=row_count;return n=1;
end $$;
create or replace function public.hd_consume_staff_worker_token(p_hash text)
returns boolean language sql security invoker set search_path='' as $$select hunkart_dispatch.consume_staff_worker_token(p_hash)$$;
revoke all on function hunkart_dispatch.consume_staff_worker_token(text),public.hd_consume_staff_worker_token(text) from public,anon,authenticated;
grant execute on function hunkart_dispatch.consume_staff_worker_token(text),public.hd_consume_staff_worker_token(text) to service_role;
create or replace function hunkart_dispatch.prune_staff_invocations()
returns integer language plpgsql security definer set search_path='' as $$
declare removed integer;
begin
 with expired as (
 select id from hunkart_dispatch.staff_worker_invocations
 where expires_at<clock_timestamp()-interval '1 hour'
 order by expires_at limit 1000 for update skip locked
 )
 delete from hunkart_dispatch.staff_worker_invocations t using expired e where t.id=e.id;
 get diagnostics removed=row_count;return removed;
end $$;
revoke all on function hunkart_dispatch.prune_staff_invocations() from public,anon,authenticated,service_role;
create or replace function hunkart_dispatch.staff_notification_tick()
returns void language plpgsql security definer set search_path='' as $$
declare token text;request_id bigint;
begin
 if not exists(select 1 from hunkart_dispatch.settings where enabled)
 or not exists(select 1 from hunkart_dispatch.staff_notification_settings where enabled) then return;end if;
 if not pg_try_advisory_xact_lock(hashtext('hunkart_dispatch.staff_notification_tick')) then return;end if;
 perform hunkart_dispatch.prune_staff_invocations();
 perform hunkart_dispatch.enqueue_staff_notifications();
 update hunkart_dispatch.staff_notification_outbox n set status='cancelled',lease_until=null where status in ('pending','sending') and not hunkart_dispatch.staff_notice_eligible(n.id);
 if not exists(select 1 from hunkart_dispatch.staff_notification_outbox where next_attempt_at<=clock_timestamp() and (status='pending' or (status='sending' and lease_until<clock_timestamp()))) then return;end if;
 begin
  token:=encode(extensions.gen_random_bytes(32),'hex');
  insert into hunkart_dispatch.staff_worker_invocations(token_hash,expires_at)
  values(encode(extensions.digest(token,'sha256'),'hex'),clock_timestamp()+interval '30 seconds');
  select net.http_post(url:='https://amnqqxgmqciipcortpmi.supabase.co/functions/v1/dispatch-staff-worker',
   headers:=jsonb_build_object('Content-Type','application/json','Authorization','Bearer '||token),
   body:='{}'::jsonb,timeout_milliseconds:=15000) into request_id;
  update hunkart_dispatch.staff_notification_settings set last_request_id=request_id,last_requested_at=clock_timestamp(),last_error=null where singleton=true;
 exception when others then
  update hunkart_dispatch.staff_notification_settings set last_error='Worker invocation failed' where singleton=true;
 end;
end $$;
revoke all on function hunkart_dispatch.staff_notification_tick() from public,anon,authenticated,service_role;

-- Separate from dispatch cron: notification errors cannot roll back rider assignment.
-- Cron is deliberately not scheduled in this disabled draft.
-- Invocation retention: delete at most 1000 records expired over one hour per enabled tick.
-- END staff-notifications.sql


-- BEGIN native-fcm/worker-delivery.sql
-- Staging-only replacement of the existing service-role delivery RPC.
-- The native list is bound to the recipient and role already checked by staff_notice_eligible.
create or replace function hunkart_dispatch.staff_notification_delivery(p_id uuid,p_token uuid)
returns jsonb language plpgsql security definer set search_path='' as $$
declare n hunkart_dispatch.staff_notification_outbox%rowtype;subs jsonb;devices jsonb;payload jsonb;ttl integer;
begin
 if (auth.jwt()->>'role') is distinct from 'service_role' then raise exception 'Service worker required' using errcode='42501';end if;
 select * into n from hunkart_dispatch.staff_notification_outbox where id=p_id and lease_token=p_token and status='sending' and lease_until>clock_timestamp() for update;
 if not found then return null;end if;
 if not hunkart_dispatch.staff_notice_eligible(n.id) then
  update hunkart_dispatch.staff_notification_outbox set status='cancelled',lease_until=null where id=n.id;return null;
 end if;
 ttl:=least(300,greatest(0,floor(extract(epoch from n.expires_at-clock_timestamp()))::integer));
 if ttl<1 then return null;end if;
 select coalesce(jsonb_agg(jsonb_build_object('endpoint',s.endpoint,'keys',jsonb_build_object('p256dh',s.p256dh,'auth',s.auth_key))),'[]'::jsonb)
 into subs from public.staff_push_subscriptions s where s.user_id=n.recipient_id and s.role=n.recipient_role;
 select coalesce(jsonb_agg(d.token),'[]'::jsonb) into devices
 from hunkart_dispatch.native_devices d where d.user_id=n.recipient_id and d.role=n.recipient_role;
 payload:=jsonb_build_object(
 'title',case when n.event_name='rider_offer' then 'HUNKART • Delivery offer' else 'HUNKART • New order' end,
 'body',case when n.event_name='rider_offer' then 'A delivery offer is waiting. Open the app to review before it expires.' else 'A paid order is ready for your shop. Open the app to accept or reject.' end,
 'url',case when n.event_name='rider_offer' then '/delivery-app/' else '/shopkeeper-app/' end,
 'tag','hd-'||n.id,'event',n.event_name,'orderId',n.order_id,'offerId',n.offer_id,'expiresAt',n.expires_at);
 return jsonb_build_object('subscriptions',subs,'nativeDevices',devices,'payload',payload,'ttl',ttl);
end $$;
-- END native-fcm/worker-delivery.sql

-- Explicitly leave both feature flags OFF after installation. No cron is installed here.
UPDATE hunkart_dispatch.settings SET enabled=false WHERE singleton=true;
UPDATE hunkart_dispatch.staff_notification_settings SET enabled=false WHERE singleton=true;
COMMIT;
