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
