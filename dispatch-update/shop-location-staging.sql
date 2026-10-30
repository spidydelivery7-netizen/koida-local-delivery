-- HUNKART staging shopkeeper GPS RPC. Keep separate from live installer until reviewed.
create or replace function public.save_my_shop_location(p_lat double precision,p_lng double precision)
returns table(shop_id uuid,location_lat double precision,location_lng double precision,location_updated_at timestamptz)
language plpgsql security definer set search_path=''
as $$
declare v_shop_id uuid;
begin
 if auth.uid() is null then raise exception 'You must be signed in.' using errcode='42501'; end if;
 if p_lat is null or p_lng is null or p_lat in ('NaN'::double precision,'Infinity'::double precision,'-Infinity'::double precision)
    or p_lng in ('NaN'::double precision,'Infinity'::double precision,'-Infinity'::double precision)
    or p_lat < -90 or p_lat > 90 or p_lng < -180 or p_lng > 180
 then raise exception 'Invalid shop location.'; end if;
 select sk.shop_id into v_shop_id from public.shopkeepers sk
 where sk.user_id=auth.uid() and sk.active and sk.shop_id is not null
 order by sk.created_at limit 1;
 if v_shop_id is null then raise exception 'This active account is not assigned to a shop.' using errcode='42501'; end if;
 update public.shops s set location_lat=p_lat,location_lng=p_lng,location_updated_at=clock_timestamp()
 where s.id=v_shop_id;
 if not found then raise exception 'Assigned shop could not be found.'; end if;
 return query select s.id,s.location_lat,s.location_lng,s.location_updated_at from public.shops s where s.id=v_shop_id;
end $$;
revoke all on function public.save_my_shop_location(double precision,double precision) from public,anon;
grant execute on function public.save_my_shop_location(double precision,double precision) to authenticated;
