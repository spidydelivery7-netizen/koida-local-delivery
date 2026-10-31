-- Synthetic fixture ONLY. No production OTP/payment/provider calls.
CREATE TABLE rehearsal_results(name text PRIMARY KEY);
CREATE FUNCTION pg_temp.ok(v boolean,label text) RETURNS void LANGUAGE plpgsql AS $$BEGIN IF v IS DISTINCT FROM true THEN RAISE EXCEPTION 'FAILED: %',label;END IF;INSERT INTO rehearsal_results VALUES(label);END$$;
CREATE FUNCTION pg_temp.denied(q text,label text) RETURNS void LANGUAGE plpgsql AS $$DECLARE failed boolean:=false;BEGIN BEGIN EXECUTE q;EXCEPTION WHEN OTHERS THEN failed:=true;END;IF NOT failed THEN RAISE EXCEPTION 'Expected denial: %',label;END IF;INSERT INTO rehearsal_results VALUES(label);END$$;
DO $$
<<fixture>>
DECLARE keeper uuid:=gen_random_uuid();rider uuid:=gen_random_uuid();other_user uuid:=gen_random_uuid();customer uuid:=gen_random_uuid();shop uuid:=gen_random_uuid();product uuid:=gen_random_uuid();rider_id uuid:=gen_random_uuid();ord uuid:=gen_random_uuid();rejected uuid:=gen_random_uuid();offer uuid;r jsonb;
BEGIN
 INSERT INTO auth.users(id,email,email_confirmed_at) SELECT u,'fixture-'||u||'@example.invalid',now() FROM unnest(ARRAY[keeper,rider,other_user,customer])u;
 INSERT INTO public.customers(id,full_name) VALUES(customer,'Synthetic customer');
 INSERT INTO public.shops(id,name,location_lat,location_lng) VALUES(shop,'Synthetic fixture shop',21.91,85.23);
 INSERT INTO public.shopkeepers(user_id,shop_id,active) VALUES(keeper,shop,true);
 INSERT INTO public.products(id,name,shop_id) VALUES(product,'Synthetic product',shop);
 INSERT INTO public.delivery_boys(id,user_id,full_name,is_active) VALUES(rider_id,rider,'Synthetic rider',true);
 INSERT INTO public.orders(id,order_number,customer_id,shop_id,customer_name,phone,address,area,status,payment_status,payment_id,total,customer_cancel_until)
 VALUES(ord,'SYNTHETIC-1',customer,shop,'Synthetic customer','0000000000','Fixture address','Fixture area','new','paid','pay_Synthetic1',100,now()+interval '3 minutes'),
 (rejected,'SYNTHETIC-2',customer,shop,'Synthetic customer','0000000000','Fixture address','Fixture area','new','paid','pay_Synthetic2',100,now()-interval '1 minute');
 INSERT INTO public.order_items(order_id,product_id,product_name,variant,variant_label,qty,unit_price,line_total)
 VALUES(ord,product,'Synthetic product','full','Full',1,100,100),(rejected,product,'Synthetic product','full','Full',1,100,100);
 PERFORM set_config('request.jwt.claim.sub',keeper::text,false);
 PERFORM pg_temp.denied(format('SELECT public.hd_accept_shop_order(%L)',ord),'disabled feature refuses acceptance');
 UPDATE hunkart_dispatch.settings SET enabled=true;
 PERFORM pg_temp.denied(format('SELECT public.hd_accept_shop_order(%L)',ord),'cancellation window protected');
 UPDATE public.orders SET customer_cancel_until=now()-interval '1 minute' WHERE id=ord;
 PERFORM set_config('request.jwt.claim.sub',other_user::text,false);
 PERFORM pg_temp.denied(format('SELECT public.hd_accept_shop_order(%L)',ord),'unassigned staff denied');
 PERFORM set_config('request.jwt.claim.sub',keeper::text,false);
 UPDATE public.orders SET payment_status='pending' WHERE id=ord;
 PERFORM pg_temp.denied(format('SELECT public.hd_accept_shop_order(%L)',ord),'unpaid order denied');
 UPDATE public.orders SET payment_status='paid' WHERE id=ord;
 r:=public.hd_accept_shop_order(ord);PERFORM pg_temp.ok(r->>'ok'='true','keeper accepts paid order');
 r:=public.hd_accept_shop_order(ord);PERFORM pg_temp.ok(r->>'already_accepted'='true','acceptance idempotent');
 PERFORM pg_temp.denied(format('SELECT public.hd_set_shop_stage(%L,%L)',ord,'packed'),'cannot skip preparation stages');
 PERFORM public.hd_set_shop_stage(ord,'preparing');PERFORM public.hd_set_shop_stage(ord,'ready');PERFORM public.hd_set_shop_stage(ord,'packed');
 PERFORM pg_temp.ok((SELECT status='packed' FROM public.orders WHERE id=ord),'preparation completes packed');
 PERFORM set_config('request.jwt.claim.sub',rider::text,false);
 PERFORM public.hd_heartbeat(true,21.91,85.23);
 PERFORM hunkart_dispatch.tick();
 SELECT f.id INTO offer FROM hunkart_dispatch.offers f WHERE f.order_id=ord AND f.rider_id=fixture.rider_id;
 PERFORM pg_temp.ok(offer IS NOT NULL,'online rider receives offer');
 r:=public.hd_respond_offer(offer,true);PERFORM pg_temp.ok(r->>'ok'='true','rider accepts offer');
 PERFORM pg_temp.ok((SELECT count(*)=1 FROM public.delivery_tracking WHERE order_id=ord),'one delivery assignment');
 r:=public.hd_respond_offer(offer,true);PERFORM pg_temp.ok(r->>'already_accepted'='true','rider acceptance idempotent');
 PERFORM public.hd_start_delivery(ord,21.91,85.23,10);
 PERFORM pg_temp.ok((SELECT status='out_for_delivery' FROM public.orders WHERE id=ord),'legacy sync preserves out-for-delivery');
 PERFORM set_config('request.jwt.claim.sub',keeper::text,false);
 INSERT INTO hunkart_cancel.settings(id,enabled,full_refund_policy_accepted) VALUES(true,true,true);
 r:=public.hd_reject_shop_order(rejected,'Item unavailable');
 PERFORM pg_temp.ok(r->>'refund_status'='queued','shop rejection queues refund');
 PERFORM pg_temp.ok((SELECT status='cancelled' FROM public.orders WHERE id=rejected),'rejected order cancelled');
 PERFORM pg_temp.ok((SELECT amount_paise=10000 AND status='queued' FROM hunkart_cancel.refunds WHERE order_id=rejected),'refund amount matches synthetic total');
 PERFORM pg_temp.denied(format('SELECT public.hd_reject_shop_order(%L,%L)',rejected,'Item unavailable'),'duplicate rejection denied');
 PERFORM pg_temp.ok((SELECT count(*)=1 FROM hunkart_cancel.refunds WHERE order_id=rejected),'no duplicate refund');
END $$;
