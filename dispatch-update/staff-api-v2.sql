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
