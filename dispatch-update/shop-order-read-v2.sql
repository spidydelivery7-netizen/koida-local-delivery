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
