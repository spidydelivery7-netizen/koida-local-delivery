begin;set local check_function_bodies=false;set local statement_timeout='15s';
CREATE OR REPLACE FUNCTION hunkart_cancel.admin_required()
RETURNS void
LANGUAGE plpgsql
SET search_path TO ''
AS $function$
BEGIN
IF auth.uid() IS NULL
OR NOT coalesce(public.is_app_admin(), false)
THEN
RAISE EXCEPTION 'Admin access required.'
USING ERRCODE = '42501';
END IF;
END;
$function$;
CREATE OR REPLACE FUNCTION hunkart_cancel.held(p_order_id uuid)
RETURNS boolean
LANGUAGE sql
SET search_path TO ''
AS $function$
SELECT EXISTS (
SELECT 1 FROM hunkart_cancel.cases c
WHERE c.order_id = p_order_id
AND c.request_type = 'cancel'
AND c.status = 'pending'
);
$function$;
CREATE OR REPLACE FUNCTION hunkart_cancel.order_kind(p_order_id uuid)
RETURNS text
LANGUAGE sql
SET search_path TO ''
AS $function$
SELECT CASE
WHEN count(*) = 0 THEN 'manual'
WHEN bool_or(r.kind IS NULL OR r.kind = 'manual')
THEN 'manual'
WHEN bool_or(r.kind = 'food') THEN 'food'
ELSE 'grocery'
END
FROM public.order_items i
LEFT JOIN hunkart_cancel.item_rules r
ON r.order_item_id = i.id AND r.order_id = i.order_id
WHERE i.order_id = p_order_id;
$function$;
CREATE OR REPLACE FUNCTION hunkart_cancel.note_progress(p_order_id uuid, p_prepared boolean, p_dispatched boolean)
RETURNS void
LANGUAGE plpgsql
SET search_path TO ''
AS $function$
BEGIN
IF NOT (coalesce(p_prepared, false) OR coalesce(p_dispatched, false))
THEN RETURN; END IF;

INSERT INTO hunkart_cancel.lifecycle AS l (
order_id, preparation_started, dispatch_started,
prepared_at, dispatched_at
) VALUES (
p_order_id, coalesce(p_prepared, false), coalesce(p_dispatched, false),
CASE WHEN p_prepared THEN now() END,
CASE WHEN p_dispatched THEN now() END
)
ON CONFLICT (order_id) DO UPDATE SET
preparation_started = l.preparation_started OR EXCLUDED.preparation_started,
dispatch_started = l.dispatch_started OR EXCLUDED.dispatch_started,
prepared_at = CASE WHEN l.preparation_started
THEN l.prepared_at ELSE EXCLUDED.prepared_at END,
dispatched_at = CASE WHEN l.dispatch_started
THEN l.dispatched_at ELSE EXCLUDED.dispatched_at END;
END;
$function$;
CREATE OR REPLACE FUNCTION hunkart_cancel.valid_explanation(p_text text)
RETURNS boolean
LANGUAGE sql
IMMUTABLE
SET search_path TO ''
AS $function$
SELECT coalesce(
char_length(p_text) BETWEEN 1 AND 1000
AND p_text ~ '[^[:space:]]',
false
);
$function$;
CREATE OR REPLACE FUNCTION hunkart_cancel.validate_reason(p_request_type text, p_reason text, p_explanation text)
RETURNS void
LANGUAGE plpgsql
SET search_path TO ''
AS $function$
BEGIN
IF NOT EXISTS (
SELECT 1
FROM hunkart_cancel.reasons AS r
WHERE r.request_type = p_request_type
AND r.reason = p_reason
) THEN
RAISE EXCEPTION 'Please select a valid reason.'
USING ERRCODE = '22023';
END IF;

IF NOT hunkart_cancel.valid_explanation(p_explanation) THEN
RAISE EXCEPTION
'Please write an explanation of 1 to 1000 characters.'
USING ERRCODE = '22023';
END IF;
END;
$function$;
CREATE OR REPLACE FUNCTION hunkart_cancel.rule_allows(p_kind text, p_status text, p_preparation_started boolean, p_dispatch_started boolean, p_paid boolean)
RETURNS boolean
LANGUAGE sql
STABLE
SET search_path TO ''
AS $function$
SELECT coalesce(
(
SELECT
p_paid IS TRUE
AND p_dispatch_started IS FALSE
AND p_status = ANY (r.cancel_statuses)
AND (
NOT r.stop_at_preparation
OR p_preparation_started IS FALSE
)
FROM hunkart_cancel.policy_rules AS r
WHERE r.kind = p_kind
),
false
);
$function$;
CREATE OR REPLACE FUNCTION hunkart_cancel.capture_item_rule()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO ''
AS $function$
DECLARE
v_kind text := 'manual';
v_version text := 'legacy-unclassified';
BEGIN
IF EXISTS (
SELECT 1
FROM hunkart_cancel.settings s
WHERE s.id = true
AND s.enabled = true
AND s.full_refund_policy_accepted = true
) THEN
SELECT
coalesce(pr.kind, sr.kind, 'manual'),
s.policy_version
INTO v_kind, v_version
FROM hunkart_cancel.settings s
LEFT JOIN public.products p
ON p.id = NEW.product_id
LEFT JOIN hunkart_cancel.product_rules pr
ON pr.product_id = p.id
LEFT JOIN hunkart_cancel.shop_rules sr
ON sr.shop_id = p.shop_id
WHERE s.id = true;
END IF;

INSERT INTO hunkart_cancel.item_rules (
order_item_id,
order_id,
kind,
policy_version
)
VALUES (
NEW.id,
NEW.order_id,
coalesce(v_kind, 'manual'),
coalesce(v_version, 'legacy-unclassified')
)
ON CONFLICT (order_item_id) DO NOTHING;

RETURN NEW;
END;
$function$;
CREATE OR REPLACE FUNCTION hunkart_cancel.guard_fulfilment()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO ''
AS $function$
DECLARE
v_order_status text;
v_changed boolean;
BEGIN
IF TG_OP = 'UPDATE'
AND NEW.order_id IS DISTINCT FROM OLD.order_id
THEN
RAISE EXCEPTION 'Order reference cannot be changed.';
END IF;

v_changed := CASE
WHEN TG_OP = 'INSERT' THEN NEW.status <> 'new'
ELSE NEW.status IS DISTINCT FROM OLD.status
END;

SELECT o.status
INTO v_order_status
FROM public.orders o
WHERE o.id = NEW.order_id
FOR UPDATE;

IF NOT FOUND THEN
RAISE EXCEPTION 'Order not found.';
END IF;

IF v_changed AND v_order_status = 'cancelled' THEN
RAISE EXCEPTION 'Order is cancelled.';
END IF;

IF v_changed
AND hunkart_cancel.held(NEW.order_id)
THEN
RAISE EXCEPTION
'Cancellation request is pending. Order fulfilment is on hold.';
END IF;

IF v_changed AND TG_TABLE_NAME = 'shop_order_status' THEN
PERFORM hunkart_cancel.note_progress(
NEW.order_id,
NEW.status IN ('preparing', 'packed'),
false
);
END IF;

IF v_changed AND TG_TABLE_NAME = 'delivery_tracking' THEN
PERFORM hunkart_cancel.note_progress(
NEW.order_id,
false,
NEW.status IN ('picked_up', 'out_for_delivery', 'delivered')
);
END IF;

RETURN NEW;
END;
$function$;
CREATE OR REPLACE FUNCTION hunkart_cancel.guard_order()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO ''
AS $function$
DECLARE
v_active boolean;
v_has_case boolean;
v_refunded_paise bigint;
BEGIN
SELECT EXISTS (
SELECT 1
FROM hunkart_cancel.cases c
WHERE c.order_id = OLD.id
)
INTO v_has_case;

SELECT (s.enabled OR v_has_case)
INTO v_active
FROM hunkart_cancel.settings s
WHERE s.id = true;

IF NEW.status IS DISTINCT FROM OLD.status THEN
IF v_active AND OLD.status = 'cancelled' THEN
RAISE EXCEPTION 'Cancelled order cannot be restarted.';
END IF;

IF v_active AND hunkart_cancel.held(OLD.id) THEN
RAISE EXCEPTION
'Cancellation request is pending. Order fulfilment is on hold.';
END IF;

IF v_active
AND NEW.status = 'cancelled'
AND NOT EXISTS (
SELECT 1
FROM hunkart_cancel.cases c
WHERE c.order_id = OLD.id
AND c.status = 'approved'
AND c.cancel_order = true
)
THEN
RAISE EXCEPTION
'Use Cancellation and Refunds to cancel with a recorded reason.';
END IF;

PERFORM hunkart_cancel.note_progress(
OLD.id,
NEW.status IN (
'preparing', 'packed',
'out_for_delivery', 'delivered'
),
NEW.status IN ('out_for_delivery', 'delivered')
);
END IF;

IF v_has_case
AND (
NEW.total,
NEW.subtotal,
NEW.delivery_charge,
NEW.platform_fee,
NEW.payment_id,
NEW.customer_id
) IS DISTINCT FROM (
OLD.total,
OLD.subtotal,
OLD.delivery_charge,
OLD.platform_fee,
OLD.payment_id,
OLD.customer_id
)
THEN
RAISE EXCEPTION
'Financial details are locked while a cancellation or refund case exists.';
END IF;

IF v_active
AND NEW.payment_status IS DISTINCT FROM OLD.payment_status
AND (
NEW.payment_status = 'refunded'
OR OLD.payment_status = 'refunded'
)
THEN
SELECT coalesce(sum(r.amount_paise), 0)
INTO v_refunded_paise
FROM hunkart_cancel.refunds r
WHERE r.order_id = OLD.id
AND r.status = 'processed';

IF NEW.payment_status <> 'refunded'
OR v_refunded_paise < round(OLD.total * 100)::bigint
THEN
RAISE EXCEPTION
'Refunded status requires verified Razorpay refund confirmation.';
END IF;
END IF;

RETURN NEW;
END;
$function$;
CREATE OR REPLACE FUNCTION hunkart_cancel.guard_items()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO ''
AS $function$
DECLARE
v_order_id uuid;
BEGIN
v_order_id := CASE
WHEN TG_OP = 'DELETE' THEN OLD.order_id
ELSE NEW.order_id
END;

PERFORM 1
FROM public.orders o
WHERE o.id = v_order_id
FOR UPDATE;

IF NOT FOUND THEN
RAISE EXCEPTION 'Order not found.';
END IF;

IF TG_OP = 'UPDATE'
AND NEW.order_id IS DISTINCT FROM OLD.order_id
THEN
RAISE EXCEPTION 'Order item cannot be moved to another order.';
END IF;

IF EXISTS (
SELECT 1
FROM hunkart_cancel.cases c
WHERE c.order_id = v_order_id
) THEN
RAISE EXCEPTION
'Order items are locked while a cancellation or refund case exists.';
END IF;

IF TG_OP = 'DELETE' THEN
RETURN OLD;
END IF;

RETURN NEW;
END;
$function$;
CREATE OR REPLACE FUNCTION hunkart_cancel.set_customer_cancel_until()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO ''
AS $function$
BEGIN
NEW.customer_cancel_until :=
coalesce(NEW.created_at, now()) + interval '3 minutes';

RETURN NEW;
END;
$function$;
CREATE OR REPLACE FUNCTION hunkart_cancel.eligible(p_order_id uuid)
RETURNS boolean
LANGUAGE plpgsql
SET search_path TO ''
AS $function$
DECLARE
o public.orders%ROWTYPE;
BEGIN
SELECT *
INTO o
FROM public.orders
WHERE id = p_order_id;

IF NOT FOUND THEN
RETURN false;
END IF;

RETURN (
o.payment_status = 'paid'
AND o.status IN ('new', 'confirmed')
AND now() < o.customer_cancel_until
);
END;
$function$;
CREATE TRIGGER hc_capture_item_rule AFTER INSERT ON public.order_items FOR EACH ROW EXECUTE FUNCTION hunkart_cancel.capture_item_rule();
CREATE TRIGGER hc_guard_order BEFORE UPDATE ON public.orders FOR EACH ROW EXECUTE FUNCTION hunkart_cancel.guard_order();
CREATE TRIGGER hc_guard_shop_fulfilment BEFORE INSERT OR UPDATE ON public.shop_order_status FOR EACH ROW EXECUTE FUNCTION hunkart_cancel.guard_fulfilment();
CREATE TRIGGER hc_guard_delivery_fulfilment BEFORE INSERT OR UPDATE ON public.delivery_tracking FOR EACH ROW EXECUTE FUNCTION hunkart_cancel.guard_fulfilment();
CREATE TRIGGER hc_guard_items BEFORE INSERT OR DELETE OR UPDATE ON public.order_items FOR EACH ROW EXECUTE FUNCTION hunkart_cancel.guard_items();
CREATE TRIGGER hc_set_customer_cancel_until BEFORE INSERT ON public.orders FOR EACH ROW EXECUTE FUNCTION hunkart_cancel.set_customer_cancel_until();
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
update hunkart_dispatch.offers f set status='expired' where f.order_id=o.id and f.status='pending' and (f.expires_at<=clock_timestamp() or not exists(select 1 from hunkart_dispatch.presence p join public.delivery_boys b on b.id=p.rider_id where p.rider_id=f.rider_id and p.online and b.is_active and p.seen_at>clock_timestamp()-interval '90 seconds'));
if exists(select 1 from hunkart_dispatch.offers where order_id=o.id and status='pending') then continue;end if;
if clock_timestamp()>j.created_at+interval '5 minutes' then update hunkart_dispatch.jobs set state='attention',note='No partner accepted within five minutes. Contact a partner or reassign.' where order_id=o.id;continue;end if;
select * into s from public.shops where id=o.shop_id;
if s.location_lat is null or s.location_lng is null then update hunkart_dispatch.jobs set state='attention',note='Shop GPS missing' where order_id=o.id;continue;end if;
select p.rider_id into rid from hunkart_dispatch.presence p join public.delivery_boys b on b.id=p.rider_id
where p.online and b.is_active and p.seen_at>clock_timestamp()-interval '90 seconds' and p.lat is not null and p.lng is not null
and not exists(select 1 from hunkart_dispatch.offers f where f.rider_id=p.rider_id and (f.order_id=o.id or f.status='pending'))
and not exists(select 1 from public.delivery_tracking t join public.orders x on x.id=t.order_id where t.delivery_boy_id=p.rider_id and t.status not in ('delivered','cancelled') and x.status not in ('delivered','cancelled'))
order by (p.lat-s.location_lat)^2+(cos(radians(s.location_lat))*(p.lng-s.location_lng))^2,p.rider_id for update of p skip locked limit 1;
if rid is null then update hunkart_dispatch.jobs set state='searching',note='Waiting for an online available partner' where order_id=o.id;continue;end if;
insert into hunkart_dispatch.offers(order_id,rider_id,expires_at) values(o.id,rid,clock_timestamp()+interval '30 seconds');
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
if p.rider_id is null or not p.online or p.seen_at<=clock_timestamp()-interval '90 seconds' then raise exception 'Go online with current GPS first';end if;
if exists(select 1 from public.delivery_tracking t join public.orders x on x.id=t.order_id where t.delivery_boy_id=rid and t.status not in ('delivered','cancelled') and x.status not in ('delivered','cancelled')) then raise exception 'Finish current delivery first';end if;
insert into public.delivery_tracking(order_id,delivery_boy_id,status) values(oid,rid,'assigned');
update hunkart_dispatch.offers set status='accepted' where id=f.id;
update hunkart_dispatch.jobs set state='assigned',note=null where order_id=oid;
return jsonb_build_object('ok',true,'accepted',true);
end $$;

create or replace function hunkart_dispatch.admin_queue() returns jsonb language plpgsql security definer set search_path='' as $$
begin
if auth.uid() is null or not coalesce(public.is_app_admin(),false) then raise exception 'Admin required' using errcode='42501';end if;
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
perform 1 from hunkart_dispatch.presence p join public.delivery_boys b on b.id=p.rider_id where p.rider_id=new.delivery_boy_id and b.is_active and p.online and p.seen_at>clock_timestamp()-interval '90 seconds' for update of p;
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

alter table hunkart_cancel.cases drop constraint cases_actor_check;alter table hunkart_cancel.cases add constraint cases_actor_check check(actor in ('customer','admin','shopkeeper'));update hunkart_cancel.settings set enabled=true,full_refund_policy_accepted=true;
-- Invoked inside a staging-only transaction which ALWAYS ROLLS BACK.
create temp table hd_test_results(name text,passed boolean);
create function pg_temp.check_ok(v boolean,n text) returns void language plpgsql as $$begin if v is distinct from true then raise exception 'FAILED: %',n;end if;insert into hd_test_results values(n,true);end $$;
create function pg_temp.denied(q text,n text) returns void language plpgsql as $$declare failed boolean:=false;begin begin execute q;exception when others then failed:=true;end;if not failed then raise exception 'FAILED: %',n;end if;insert into hd_test_results values(n,true);end $$;
do $$
declare k uuid:=gen_random_uuid();c uuid:=gen_random_uuid();a uuid:=gen_random_uuid();b uuid:=gen_random_uuid();rid uuid:=gen_random_uuid();rid2 uuid:=gen_random_uuid();sid uuid:=gen_random_uuid();pid uuid:=gen_random_uuid();oid uuid:=gen_random_uuid();oid2 uuid:=gen_random_uuid();f uuid;r jsonb;
begin
insert into auth.users(id,aud,role,email,raw_app_meta_data,raw_user_meta_data) select x,'authenticated','authenticated','hd-'||x||'@example.invalid','{}','{}' from unnest(array[k,c,a,b])x;
insert into public.customers(id,full_name) values(c,'Synthetic only') on conflict(id) do nothing;
insert into public.shops(id,name,location_lat,location_lng) values(sid,'Synthetic test shop',21.91,85.23);
insert into public.shopkeepers(user_id,shop_id,active) values(k,sid,true);
insert into public.products(id,name,shop_id) values(pid,'Synthetic item',sid);
insert into public.delivery_boys(id,user_id,full_name,is_active) values(rid,a,'Synthetic rider A',true),(rid2,b,'Synthetic rider B',true);
insert into public.orders(id,order_number,customer_id,status,payment_status,payment_id,subtotal,total,shop_id,customer_name,phone,address,area) values(oid,'HD-TEST-'||oid,c,'new','paid','pay_SyntheticA',100,100,sid,'Synthetic customer','0000000000','Synthetic address','Synthetic area'),(oid2,'HD-TEST-'||oid2,c,'new','paid','pay_SyntheticB',100,100,sid,'Synthetic customer','0000000000','Synthetic address','Synthetic area');
insert into public.order_items(order_id,product_id,product_name,variant,variant_label,qty,unit_price,line_total) values(oid,pid,'Synthetic item','full','Full',1,100,100),(oid2,pid,'Synthetic item','full','Full',1,100,100);
perform set_config('request.jwt.claim.sub',k::text,true);
perform pg_temp.denied(format('select public.hd_accept_shop_order(%L)',oid),'feature disabled');
update hunkart_dispatch.settings set enabled=true;
perform pg_temp.denied(format('select public.hd_accept_shop_order(%L)',oid),'three minute window preserved');
update public.orders set customer_cancel_until=now()-interval '1 second' where id in (oid,oid2);
perform set_config('request.jwt.claim.sub',c::text,true);
perform pg_temp.denied(format('select public.hd_accept_shop_order(%L)',oid),'customer cannot accept');
perform set_config('request.jwt.claim.sub',k::text,true);
update public.shopkeepers set active=false where user_id=k;
perform pg_temp.denied(format('select public.hd_accept_shop_order(%L)',oid),'inactive keeper denied');
update public.shopkeepers set active=true where user_id=k;
update public.orders set payment_status='pending' where id=oid;
perform pg_temp.denied(format('select public.hd_accept_shop_order(%L)',oid),'unpaid order denied');
update public.orders set payment_status='paid' where id=oid;
r:=public.hd_accept_shop_order(oid);perform pg_temp.check_ok(r->>'ok'='true','keeper acceptance');
r:=public.hd_accept_shop_order(oid);perform pg_temp.check_ok(r->>'already_accepted'='true','acceptance idempotence');
perform pg_temp.check_ok((select status='confirmed' from public.orders where id=oid),'customer order confirmed');
perform pg_temp.denied(format('select public.mark_my_shop_order_packed(%L)',oid),'packing cannot skip preparation');
perform set_config('request.jwt.claim.sub',a::text,true);
perform public.hd_heartbeat(true,21.9101,85.2301);
perform set_config('request.jwt.claim.sub',b::text,true);
perform public.hd_heartbeat(true,21.92,85.24);
perform hunkart_dispatch.tick();
select id into f from hunkart_dispatch.offers where order_id=oid and status='pending';
perform pg_temp.check_ok(f is not null,'worker created request');
perform pg_temp.denied(format('select public.hd_respond_offer(%L,true)',f),'wrong rider denied');
perform set_config('request.jwt.claim.sub',a::text,true);
r:=public.hd_my_offers();perform pg_temp.check_ok(jsonb_array_length(r)=1 and not (r->0?'phone') and not (r->0?'address'),'offer privacy');
perform public.hd_respond_offer(f,false);
perform hunkart_dispatch.tick();
select id into f from hunkart_dispatch.offers where order_id=oid and status='pending';
perform pg_temp.check_ok((select rider_id=rid2 from hunkart_dispatch.offers where id=f),'decline fallback to next rider');
perform set_config('request.jwt.claim.sub',b::text,true);
perform public.hd_respond_offer(f,true);
perform pg_temp.check_ok((select delivery_boy_id=rid2 from public.delivery_tracking where order_id=oid),'accepted assignment');
r:=public.hd_respond_offer(f,true);perform pg_temp.check_ok(r->>'already_accepted'='true','rider accept idempotence');
perform pg_temp.denied(format('select public.delivery_start(%L,21.91,85.23,10)',oid),'pickup blocked before packed');
perform set_config('request.jwt.claim.sub',k::text,true);
perform public.set_my_shop_order_status(oid,'preparing');perform public.set_my_shop_order_status(oid,'ready');perform public.mark_my_shop_order_packed(oid);
perform pg_temp.check_ok((select status='packed' from public.orders where id=oid),'preparation sequence completes');
perform set_config('request.jwt.claim.sub',b::text,true);
perform public.delivery_start(oid,21.91,85.23,10);
perform pg_temp.check_ok((select status='out_for_delivery' from public.delivery_tracking where order_id=oid),'packed pickup allowed');
perform set_config('request.jwt.claim.sub',k::text,true);
perform pg_temp.denied(format('select public.hd_reject_shop_order(%L,%L)',oid2,'Bad reason'),'invalid rejection reason blocked');
r:=public.hd_reject_shop_order(oid2,'Item unavailable');
perform pg_temp.check_ok(r->>'refund_status'='queued','rejection queues refund');
perform pg_temp.check_ok((select status='cancelled' and payment_status='paid' from public.orders where id=oid2),'cancelled not falsely refunded');
perform pg_temp.check_ok((select count(*)=1 from hunkart_cancel.refunds where order_id=oid2 and status='queued'),'one refund intent');
perform pg_temp.denied(format('select public.hd_reject_shop_order(%L,%L)',oid2,'Item unavailable'),'duplicate rejection blocked');
perform pg_temp.check_ok(not has_function_privilege('anon','public.hd_accept_shop_order(uuid)','execute') and not has_function_privilege('anon','public.hd_respond_offer(uuid,boolean)','execute'),'anonymous RPC access revoked');
perform pg_temp.check_ok(not has_table_privilege('authenticated','hunkart_dispatch.offers','select'),'direct offer table access denied');
end $$;
select count(*) as passed_assertions,jsonb_agg(name) as checks from hd_test_results;

rollback;