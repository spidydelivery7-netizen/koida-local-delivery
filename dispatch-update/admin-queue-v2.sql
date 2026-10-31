create or replace function hunkart_dispatch.admin_queue() returns jsonb language plpgsql security definer set search_path='' as $$
begin
 if auth.uid() is null or not hunkart_dispatch.is_admin() then raise exception 'Admin required' using errcode='42501';end if;
 return coalesce((select jsonb_agg(jsonb_build_object('order_id',o.id,'order_number',o.order_number,'state',coalesce(j.state,'awaiting_shop'),'note',coalesce(j.note,'Shop has not accepted yet'))) from public.orders o left join hunkart_dispatch.jobs j on j.order_id=o.id where o.payment_status='paid' and o.status in ('new','confirmed','preparing','packed') and (j.state in ('attention','searching') or (o.status='new' and clock_timestamp()>o.customer_cancel_until+interval '2 minutes'))),'[]'::jsonb);
end $$;