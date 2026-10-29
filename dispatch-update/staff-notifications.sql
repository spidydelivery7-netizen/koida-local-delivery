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
    and b.user_id=n.recipient_id and b.is_active and pr.online and pr.seen_at>clock_timestamp()-interval '90 seconds'))
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
 where f.status='pending' and f.expires_at>clock_timestamp() and pr.seen_at>clock_timestamp()-interval '90 seconds'
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

create or replace function hunkart_dispatch.staff_notification_tick()
returns void language plpgsql security definer set search_path='' as $$
declare token text;target text;request_id bigint;
begin
 if not exists(select 1 from hunkart_dispatch.settings where enabled)
 or not exists(select 1 from hunkart_dispatch.staff_notification_settings where enabled) then return;end if;
 if not pg_try_advisory_xact_lock(hashtext('hunkart_dispatch.staff_notification_tick')) then return;end if;
 perform hunkart_dispatch.enqueue_staff_notifications();
 update hunkart_dispatch.staff_notification_outbox n set status='cancelled',lease_until=null where status in ('pending','sending') and not hunkart_dispatch.staff_notice_eligible(n.id);
 if not exists(select 1 from hunkart_dispatch.staff_notification_outbox where next_attempt_at<=clock_timestamp() and (status='pending' or (status='sending' and lease_until<clock_timestamp()))) then return;end if;
 select decrypted_secret into token from vault.decrypted_secrets where name='hd_staff_worker_token';
 select decrypted_secret into target from vault.decrypted_secrets where name='hd_staff_worker_url';
 if token is null or target is null then
  update hunkart_dispatch.staff_notification_settings set last_error='Worker configuration missing';return;
 end if;
 if target<>'https://jjitqihblpubqwbggjpv.supabase.co/functions/v1/dispatch-staff-worker' then
  update hunkart_dispatch.staff_notification_settings set last_error='Staging worker URL mismatch';return;
 end if;
 begin
  select net.http_post(url:=target,headers:=jsonb_build_object('Content-Type','application/json','Authorization','Bearer '||token),body:='{}'::jsonb,timeout_milliseconds:=15000) into request_id;
  update hunkart_dispatch.staff_notification_settings set last_request_id=request_id,last_requested_at=clock_timestamp(),last_error=null;
 exception when others then
  update hunkart_dispatch.staff_notification_settings set last_error='Worker invocation failed';
 end;
end $$;
revoke all on function hunkart_dispatch.staff_notification_tick() from public,anon,authenticated,service_role;
-- Separate from dispatch cron: notification errors cannot roll back rider assignment.
select cron.schedule('hunkart-staff-notifications','5 seconds','select hunkart_dispatch.staff_notification_tick();');
