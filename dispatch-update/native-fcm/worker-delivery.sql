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
