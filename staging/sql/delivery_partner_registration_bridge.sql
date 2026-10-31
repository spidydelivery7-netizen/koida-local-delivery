-- Staging-only delivery-partner Auth signup bridge.
-- New delivery-partner accounts are linked to delivery_boys; no live data is modified.
CREATE OR REPLACE FUNCTION public.handle_new_delivery_partner_staging()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path TO ''
AS $$
BEGIN
  IF NEW.raw_user_meta_data->>'account_type' = 'delivery_boy' THEN
    INSERT INTO public.delivery_boys(user_id,full_name,phone,is_active)
    VALUES (
      NEW.id,
      coalesce(nullif(trim(NEW.raw_user_meta_data->>'full_name'),''),'Delivery partner'),
      NEW.raw_user_meta_data->>'phone',
      true
    )
    ON CONFLICT (user_id) DO NOTHING;
  END IF;
  RETURN NEW;
END $$;
CREATE TRIGGER on_auth_delivery_partner_created_staging
AFTER INSERT ON auth.users FOR EACH ROW
EXECUTE FUNCTION public.handle_new_delivery_partner_staging();
