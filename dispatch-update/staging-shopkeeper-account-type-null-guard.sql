-- Staging-only migration, applied and verified on 2026-10-30.
-- Prior predicate used <> and SQL NULL let unspecified account types through.
create or replace function public.handle_new_shopkeeper_staging() returns trigger
language plpgsql security definer set search_path='' as $fn$
declare v_shop_id uuid;
begin
 if NEW.raw_user_meta_data->>'account_type' is distinct from 'shopkeeper' then return NEW; end if;
 if exists(select 1 from public.shopkeepers where user_id=NEW.id) then return NEW; end if;
 insert into public.shops(name,active,approval_status,shop_section,is_open)
 values(coalesce(nullif(trim(NEW.raw_user_meta_data->>'business_name'),''),'New shop'),false,'pending',coalesce(nullif(NEW.raw_user_meta_data->>'requested_category',''),'food'),false)
 returning id into v_shop_id;
 insert into public.shopkeepers(user_id,shop_id,active,full_name,phone,business_name,requested_category)
 values(NEW.id,v_shop_id,true,NEW.raw_user_meta_data->>'full_name',NEW.raw_user_meta_data->>'phone',NEW.raw_user_meta_data->>'business_name',NEW.raw_user_meta_data->>'requested_category');
 return NEW;
end $fn$;
