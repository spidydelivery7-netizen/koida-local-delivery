-- Staging-only registration bridge for shopkeeper Auth signups.
-- Keep customer Auth trigger unchanged. A new shop stays pending and closed
-- until an admin explicitly approves it.
CREATE OR REPLACE FUNCTION public.handle_new_shopkeeper_staging()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path TO ''
AS $$
DECLARE v_shop_id uuid;
BEGIN
  IF NEW.raw_user_meta_data->>'account_type' <> 'shopkeeper' THEN
    RETURN NEW;
  END IF;
  IF EXISTS (SELECT 1 FROM public.shopkeepers WHERE user_id=NEW.id) THEN
    RETURN NEW;
  END IF;
  INSERT INTO public.shops(name,active,approval_status,shop_section,is_open)
  VALUES (
    coalesce(nullif(trim(NEW.raw_user_meta_data->>'business_name'),''),'New shop'),
    false,'pending',
    coalesce(nullif(NEW.raw_user_meta_data->>'requested_category',''),'food'),
    false
  ) RETURNING id INTO v_shop_id;
  INSERT INTO public.shopkeepers(user_id,shop_id,active,full_name,phone,business_name,requested_category)
  VALUES (
    NEW.id,v_shop_id,true,
    NEW.raw_user_meta_data->>'full_name',NEW.raw_user_meta_data->>'phone',
    NEW.raw_user_meta_data->>'business_name',
    NEW.raw_user_meta_data->>'requested_category'
  );
  RETURN NEW;
END $$;
CREATE TRIGGER on_auth_shopkeeper_created_staging
AFTER INSERT ON auth.users FOR EACH ROW
EXECUTE FUNCTION public.handle_new_shopkeeper_staging();

-- Backfill only shopkeeper Auth users lacking an assignment.
DO $$
DECLARE u record; sid uuid;
BEGIN
  FOR u IN
    SELECT id, raw_user_meta_data m FROM auth.users
    WHERE raw_user_meta_data->>'account_type'='shopkeeper'
      AND NOT EXISTS (
        SELECT 1 FROM public.shopkeepers k WHERE k.user_id=auth.users.id
      )
  LOOP
    INSERT INTO public.shops(name,active,approval_status,shop_section,is_open)
    VALUES (
      coalesce(nullif(trim(u.m->>'business_name'),''),'New shop'),
      false,'pending',
      coalesce(nullif(u.m->>'requested_category',''),'food'),
      false
    ) RETURNING id INTO sid;
    INSERT INTO public.shopkeepers(user_id,shop_id,active,full_name,phone,business_name,requested_category)
    VALUES (
      u.id,sid,true,u.m->>'full_name',u.m->>'phone',
      u.m->>'business_name',u.m->>'requested_category'
    );
  END LOOP;
END $$;
