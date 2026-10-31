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
