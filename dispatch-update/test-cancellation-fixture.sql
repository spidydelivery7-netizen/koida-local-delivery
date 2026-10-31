set local check_function_bodies=false;
create schema hunkart_cancel;
CREATE OR REPLACE FUNCTION hunkart_cancel.admin_required()
RETURNS void
LANGUAGE plpgsql
SET search_path TO ''
AS $function$
BEGIN
IF auth.uid() IS NULL
OR NOT coalesce(public.is_app_admin(), false)
THEN
RAISE EXCEPTION 'Admin access required.'
USING ERRCODE = '42501';
END IF;
END;
$function$;
CREATE OR REPLACE FUNCTION hunkart_cancel.held(p_order_id uuid)
RETURNS boolean
LANGUAGE sql
SET search_path TO ''
AS $function$
SELECT EXISTS (
SELECT 1 FROM hunkart_cancel.cases c
WHERE c.order_id = p_order_id
AND c.request_type = 'cancel'
AND c.status = 'pending'
);
$function$;
CREATE OR REPLACE FUNCTION hunkart_cancel.order_kind(p_order_id uuid)
RETURNS text
LANGUAGE sql
SET search_path TO ''
AS $function$
SELECT CASE
WHEN count(*) = 0 THEN 'manual'
WHEN bool_or(r.kind IS NULL OR r.kind = 'manual')
THEN 'manual'
WHEN bool_or(r.kind = 'food') THEN 'food'
ELSE 'grocery'
END
FROM public.order_items i
LEFT JOIN hunkart_cancel.item_rules r
ON r.order_item_id = i.id AND r.order_id = i.order_id
WHERE i.order_id = p_order_id;
$function$;
CREATE OR REPLACE FUNCTION hunkart_cancel.note_progress(p_order_id uuid, p_prepared boolean, p_dispatched boolean)
RETURNS void
LANGUAGE plpgsql
SET search_path TO ''
AS $function$
BEGIN
IF NOT (coalesce(p_prepared, false) OR coalesce(p_dispatched, false))
THEN RETURN; END IF;

INSERT INTO hunkart_cancel.lifecycle AS l (
order_id, preparation_started, dispatch_started,
prepared_at, dispatched_at
) VALUES (
p_order_id, coalesce(p_prepared, false), coalesce(p_dispatched, false),
CASE WHEN p_prepared THEN now() END,
CASE WHEN p_dispatched THEN now() END
)
ON CONFLICT (order_id) DO UPDATE SET
preparation_started = l.preparation_started OR EXCLUDED.preparation_started,
dispatch_started = l.dispatch_started OR EXCLUDED.dispatch_started,
prepared_at = CASE WHEN l.preparation_started
THEN l.prepared_at ELSE EXCLUDED.prepared_at END,
dispatched_at = CASE WHEN l.dispatch_started
THEN l.dispatched_at ELSE EXCLUDED.dispatched_at END;
END;
$function$;
CREATE OR REPLACE FUNCTION hunkart_cancel.valid_explanation(p_text text)
RETURNS boolean
LANGUAGE sql
IMMUTABLE
SET search_path TO ''
AS $function$
SELECT coalesce(
char_length(p_text) BETWEEN 1 AND 1000
AND p_text ~ '[^[:space:]]',
false
);
$function$;
CREATE OR REPLACE FUNCTION hunkart_cancel.validate_reason(p_request_type text, p_reason text, p_explanation text)
RETURNS void
LANGUAGE plpgsql
SET search_path TO ''
AS $function$
BEGIN
IF NOT EXISTS (
SELECT 1
FROM hunkart_cancel.reasons AS r
WHERE r.request_type = p_request_type
AND r.reason = p_reason
) THEN
RAISE EXCEPTION 'Please select a valid reason.'
USING ERRCODE = '22023';
END IF;

IF NOT hunkart_cancel.valid_explanation(p_explanation) THEN
RAISE EXCEPTION
'Please write an explanation of 1 to 1000 characters.'
USING ERRCODE = '22023';
END IF;
END;
$function$;
CREATE OR REPLACE FUNCTION hunkart_cancel.rule_allows(p_kind text, p_status text, p_preparation_started boolean, p_dispatch_started boolean, p_paid boolean)
RETURNS boolean
LANGUAGE sql
STABLE
SET search_path TO ''
AS $function$
SELECT coalesce(
(
SELECT
p_paid IS TRUE
AND p_dispatch_started IS FALSE
AND p_status = ANY (r.cancel_statuses)
AND (
NOT r.stop_at_preparation
OR p_preparation_started IS FALSE
)
FROM hunkart_cancel.policy_rules AS r
WHERE r.kind = p_kind
),
false
);
$function$;
CREATE OR REPLACE FUNCTION hunkart_cancel.capture_item_rule()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO ''
AS $function$
DECLARE
v_kind text := 'manual';
v_version text := 'legacy-unclassified';
BEGIN
IF EXISTS (
SELECT 1
FROM hunkart_cancel.settings s
WHERE s.id = true
AND s.enabled = true
AND s.full_refund_policy_accepted = true
) THEN
SELECT
coalesce(pr.kind, sr.kind, 'manual'),
s.policy_version
INTO v_kind, v_version
FROM hunkart_cancel.settings s
LEFT JOIN public.products p
ON p.id = NEW.product_id
LEFT JOIN hunkart_cancel.product_rules pr
ON pr.product_id = p.id
LEFT JOIN hunkart_cancel.shop_rules sr
ON sr.shop_id = p.shop_id
WHERE s.id = true;
END IF;

INSERT INTO hunkart_cancel.item_rules (
order_item_id,
order_id,
kind,
policy_version
)
VALUES (
NEW.id,
NEW.order_id,
coalesce(v_kind, 'manual'),
coalesce(v_version, 'legacy-unclassified')
)
ON CONFLICT (order_item_id) DO NOTHING;

RETURN NEW;
END;
$function$;
CREATE OR REPLACE FUNCTION hunkart_cancel.guard_fulfilment()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO ''
AS $function$
DECLARE
v_order_status text;
v_changed boolean;
BEGIN
IF TG_OP = 'UPDATE'
AND NEW.order_id IS DISTINCT FROM OLD.order_id
THEN
RAISE EXCEPTION 'Order reference cannot be changed.';
END IF;

v_changed := CASE
WHEN TG_OP = 'INSERT' THEN NEW.status <> 'new'
ELSE NEW.status IS DISTINCT FROM OLD.status
END;

SELECT o.status
INTO v_order_status
FROM public.orders o
WHERE o.id = NEW.order_id
FOR UPDATE;

IF NOT FOUND THEN
RAISE EXCEPTION 'Order not found.';
END IF;

IF v_changed AND v_order_status = 'cancelled' THEN
RAISE EXCEPTION 'Order is cancelled.';
END IF;

IF v_changed
AND hunkart_cancel.held(NEW.order_id)
THEN
RAISE EXCEPTION
'Cancellation request is pending. Order fulfilment is on hold.';
END IF;

IF v_changed AND TG_TABLE_NAME = 'shop_order_status' THEN
PERFORM hunkart_cancel.note_progress(
NEW.order_id,
NEW.status IN ('preparing', 'packed'),
false
);
END IF;

IF v_changed AND TG_TABLE_NAME = 'delivery_tracking' THEN
PERFORM hunkart_cancel.note_progress(
NEW.order_id,
false,
NEW.status IN ('picked_up', 'out_for_delivery', 'delivered')
);
END IF;

RETURN NEW;
END;
$function$;
CREATE OR REPLACE FUNCTION hunkart_cancel.guard_order()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO ''
AS $function$
DECLARE
v_active boolean;
v_has_case boolean;
v_refunded_paise bigint;
BEGIN
SELECT EXISTS (
SELECT 1
FROM hunkart_cancel.cases c
WHERE c.order_id = OLD.id
)
INTO v_has_case;

SELECT (s.enabled OR v_has_case)
INTO v_active
FROM hunkart_cancel.settings s
WHERE s.id = true;

IF NEW.status IS DISTINCT FROM OLD.status THEN
IF v_active AND OLD.status = 'cancelled' THEN
RAISE EXCEPTION 'Cancelled order cannot be restarted.';
END IF;

IF v_active AND hunkart_cancel.held(OLD.id) THEN
RAISE EXCEPTION
'Cancellation request is pending. Order fulfilment is on hold.';
END IF;

IF v_active
AND NEW.status = 'cancelled'
AND NOT EXISTS (
SELECT 1
FROM hunkart_cancel.cases c
WHERE c.order_id = OLD.id
AND c.status = 'approved'
AND c.cancel_order = true
)
THEN
RAISE EXCEPTION
'Use Cancellation and Refunds to cancel with a recorded reason.';
END IF;

PERFORM hunkart_cancel.note_progress(
OLD.id,
NEW.status IN (
'preparing', 'packed',
'out_for_delivery', 'delivered'
),
NEW.status IN ('out_for_delivery', 'delivered')
);
END IF;

IF v_has_case
AND (
NEW.total,
NEW.subtotal,
NEW.delivery_charge,
NEW.platform_fee,
NEW.payment_id,
NEW.customer_id
) IS DISTINCT FROM (
OLD.total,
OLD.subtotal,
OLD.delivery_charge,
OLD.platform_fee,
OLD.payment_id,
OLD.customer_id
)
THEN
RAISE EXCEPTION
'Financial details are locked while a cancellation or refund case exists.';
END IF;

IF v_active
AND NEW.payment_status IS DISTINCT FROM OLD.payment_status
AND (
NEW.payment_status = 'refunded'
OR OLD.payment_status = 'refunded'
)
THEN
SELECT coalesce(sum(r.amount_paise), 0)
INTO v_refunded_paise
FROM hunkart_cancel.refunds r
WHERE r.order_id = OLD.id
AND r.status = 'processed';

IF NEW.payment_status <> 'refunded'
OR v_refunded_paise < round(OLD.total * 100)::bigint
THEN
RAISE EXCEPTION
'Refunded status requires verified Razorpay refund confirmation.';
END IF;
END IF;

RETURN NEW;
END;
$function$;
CREATE OR REPLACE FUNCTION hunkart_cancel.guard_items()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO ''
AS $function$
DECLARE
v_order_id uuid;
BEGIN
v_order_id := CASE
WHEN TG_OP = 'DELETE' THEN OLD.order_id
ELSE NEW.order_id
END;

PERFORM 1
FROM public.orders o
WHERE o.id = v_order_id
FOR UPDATE;

IF NOT FOUND THEN
RAISE EXCEPTION 'Order not found.';
END IF;

IF TG_OP = 'UPDATE'
AND NEW.order_id IS DISTINCT FROM OLD.order_id
THEN
RAISE EXCEPTION 'Order item cannot be moved to another order.';
END IF;

IF EXISTS (
SELECT 1
FROM hunkart_cancel.cases c
WHERE c.order_id = v_order_id
) THEN
RAISE EXCEPTION
'Order items are locked while a cancellation or refund case exists.';
END IF;

IF TG_OP = 'DELETE' THEN
RETURN OLD;
END IF;

RETURN NEW;
END;
$function$;
CREATE OR REPLACE FUNCTION hunkart_cancel.set_customer_cancel_until()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO ''
AS $function$
BEGIN
NEW.customer_cancel_until :=
coalesce(NEW.created_at, now()) + interval '3 minutes';

RETURN NEW;
END;
$function$;
CREATE OR REPLACE FUNCTION hunkart_cancel.eligible(p_order_id uuid)
RETURNS boolean
LANGUAGE plpgsql
SET search_path TO ''
AS $function$
DECLARE
o public.orders%ROWTYPE;
BEGIN
SELECT *
INTO o
FROM public.orders
WHERE id = p_order_id;

IF NOT FOUND THEN
RETURN false;
END IF;

RETURN (
o.payment_status = 'paid'
AND o.status IN ('new', 'confirmed')
AND now() < o.customer_cancel_until
);
END;
$function$;
create table hunkart_cancel.settings (id boolean default true not null, enabled boolean default false not null, policy_version text default 'food-grocery-v1'::text not null, activated_by uuid, activated_at timestamp with time zone, full_refund_policy_accepted boolean default false not null, request_layer_version text);
create table hunkart_cancel.policy_rules (kind text not null, policy_version text not null, cancel_statuses text[] not null, stop_at_preparation boolean not null, condition_en text not null);
create table hunkart_cancel.reasons (request_type text not null, reason text not null, requires_explanation boolean default true not null, requires_items boolean default false not null);
create table hunkart_cancel.shop_rules (shop_id uuid not null, kind text not null);
create table hunkart_cancel.product_rules (product_id uuid not null, kind text not null);
create table hunkart_cancel.lifecycle (order_id uuid not null, preparation_started boolean default false not null, dispatch_started boolean default false not null, prepared_at timestamp with time zone, dispatched_at timestamp with time zone);
create table hunkart_cancel.item_rules (order_item_id uuid not null, order_id uuid not null, kind text not null, policy_version text not null);
create table hunkart_cancel.cases (id uuid default gen_random_uuid() not null, order_id uuid not null, customer_id uuid not null, opened_by uuid not null, actor text not null, request_type text not null, reason text not null, details text not null, item_ids uuid[] default '{}'::uuid[] not null, policy_kind text not null, policy_version text not null, status text default 'pending'::text not null, admin_note text, cancel_order boolean default false not null, created_at timestamp with time zone default now() not null, decided_by uuid, decided_at timestamp with time zone);
create table hunkart_cancel.refunds (id uuid default gen_random_uuid() not null, case_id uuid not null, order_id uuid not null, payment_id text not null, amount_paise bigint not null, status text default 'queued'::text not null, provider_id text, bank_reference text, lease_until timestamp with time zone, last_error text, created_at timestamp with time zone default now() not null, updated_at timestamp with time zone default now() not null);
alter table hunkart_cancel.settings add constraint settings_id_check CHECK (id);
alter table hunkart_cancel.settings add constraint settings_pkey PRIMARY KEY (id);
alter table hunkart_cancel.policy_rules add constraint policy_rules_kind_check CHECK ((kind = ANY (ARRAY['food'::text, 'grocery'::text, 'manual'::text])));
alter table hunkart_cancel.policy_rules add constraint policy_rules_pkey PRIMARY KEY (kind);
alter table hunkart_cancel.reasons add constraint reasons_request_type_check CHECK ((request_type = ANY (ARRAY['cancel'::text, 'problem'::text])));
alter table hunkart_cancel.reasons add constraint reasons_requires_explanation_check CHECK (requires_explanation);
alter table hunkart_cancel.reasons add constraint reasons_pkey PRIMARY KEY (request_type, reason);
alter table hunkart_cancel.shop_rules add constraint shop_rules_kind_check CHECK ((kind = ANY (ARRAY['food'::text, 'grocery'::text, 'manual'::text])));
alter table hunkart_cancel.shop_rules add constraint shop_rules_pkey PRIMARY KEY (shop_id);
alter table hunkart_cancel.product_rules add constraint product_rules_kind_check CHECK ((kind = ANY (ARRAY['food'::text, 'grocery'::text, 'manual'::text])));
alter table hunkart_cancel.product_rules add constraint product_rules_pkey PRIMARY KEY (product_id);
alter table hunkart_cancel.lifecycle add constraint lifecycle_pkey PRIMARY KEY (order_id);
alter table hunkart_cancel.item_rules add constraint item_rules_kind_check CHECK ((kind = ANY (ARRAY['food'::text, 'grocery'::text, 'manual'::text])));
alter table hunkart_cancel.item_rules add constraint item_rules_pkey PRIMARY KEY (order_item_id);
alter table hunkart_cancel.cases add constraint cases_actor_check CHECK ((actor = ANY (ARRAY['customer'::text, 'admin'::text])));
alter table hunkart_cancel.cases add constraint cases_request_type_check CHECK ((request_type = ANY (ARRAY['cancel'::text, 'problem'::text])));
alter table hunkart_cancel.cases add constraint cases_reason_check CHECK (((char_length(reason) >= 1) AND (char_length(reason) <= 100)));
alter table hunkart_cancel.cases add constraint cases_details_check CHECK (hunkart_cancel.valid_explanation(details));
alter table hunkart_cancel.cases add constraint cases_policy_kind_check CHECK ((policy_kind = ANY (ARRAY['food'::text, 'grocery'::text, 'manual'::text])));
alter table hunkart_cancel.cases add constraint cases_status_check CHECK ((status = ANY (ARRAY['pending'::text, 'approved'::text, 'rejected'::text])));
alter table hunkart_cancel.cases add constraint cases_check CHECK (((status = 'pending'::text) OR (hunkart_cancel.valid_explanation(admin_note) AND (decided_by IS NOT NULL) AND (decided_at IS NOT NULL))));
alter table hunkart_cancel.cases add constraint cases_pkey PRIMARY KEY (id);
alter table hunkart_cancel.refunds add constraint refunds_payment_id_check CHECK ((payment_id ~ '^pay_[A-Za-z0-9]+$'::text));
alter table hunkart_cancel.refunds add constraint refunds_amount_paise_check CHECK ((amount_paise >= 100));
alter table hunkart_cancel.refunds add constraint refunds_status_check CHECK ((status = ANY (ARRAY['queued'::text, 'submitting'::text, 'uncertain'::text, 'pending'::text, 'processed'::text, 'failed'::text])));
alter table hunkart_cancel.refunds add constraint refunds_provider_id_check CHECK (((provider_id IS NULL) OR (provider_id ~ '^rfnd_[A-Za-z0-9]+$'::text)));
alter table hunkart_cancel.refunds add constraint refunds_pkey PRIMARY KEY (id);
alter table hunkart_cancel.refunds add constraint refunds_case_id_key UNIQUE (case_id);
alter table hunkart_cancel.refunds add constraint refunds_provider_id_key UNIQUE (provider_id);
alter table hunkart_cancel.shop_rules add constraint shop_rules_shop_id_fkey FOREIGN KEY (shop_id) REFERENCES shops(id) ON DELETE CASCADE;
alter table hunkart_cancel.product_rules add constraint product_rules_product_id_fkey FOREIGN KEY (product_id) REFERENCES products(id) ON DELETE CASCADE;
alter table hunkart_cancel.lifecycle add constraint lifecycle_order_id_fkey FOREIGN KEY (order_id) REFERENCES orders(id) ON DELETE CASCADE;
alter table hunkart_cancel.item_rules add constraint item_rules_order_item_id_fkey FOREIGN KEY (order_item_id) REFERENCES order_items(id) ON DELETE CASCADE;
alter table hunkart_cancel.item_rules add constraint item_rules_order_id_fkey FOREIGN KEY (order_id) REFERENCES orders(id) ON DELETE CASCADE;
alter table hunkart_cancel.cases add constraint cases_order_id_fkey FOREIGN KEY (order_id) REFERENCES orders(id) ON DELETE RESTRICT;
alter table hunkart_cancel.refunds add constraint refunds_case_id_fkey FOREIGN KEY (case_id) REFERENCES hunkart_cancel.cases(id) ON DELETE RESTRICT;
alter table hunkart_cancel.refunds add constraint refunds_order_id_fkey FOREIGN KEY (order_id) REFERENCES orders(id) ON DELETE RESTRICT;
insert into hunkart_cancel.reasons select * from jsonb_populate_recordset(null::hunkart_cancel.reasons, '[{"reason": "Ordered by mistake", "request_type": "cancel", "requires_items": false, "requires_explanation": true}, {"reason": "Duplicate order", "request_type": "cancel", "requires_items": false, "requires_explanation": true}, {"reason": "Wrong item or quantity", "request_type": "cancel", "requires_items": false, "requires_explanation": true}, {"reason": "Wrong delivery address", "request_type": "cancel", "requires_items": false, "requires_explanation": true}, {"reason": "Other", "request_type": "cancel", "requires_items": false, "requires_explanation": true}, {"reason": "Order not received", "request_type": "problem", "requires_items": false, "requires_explanation": true}, {"reason": "Delivery later than promised", "request_type": "problem", "requires_items": false, "requires_explanation": true}, {"reason": "Wrong item", "request_type": "problem", "requires_items": true, "requires_explanation": true}, {"reason": "Missing item", "request_type": "problem", "requires_items": true, "requires_explanation": true}, {"reason": "Damaged or leaking item", "request_type": "problem", "requires_items": true, "requires_explanation": true}, {"reason": "Expired or spoiled item", "request_type": "problem", "requires_items": true, "requires_explanation": true}, {"reason": "Food quality or safety", "request_type": "problem", "requires_items": true, "requires_explanation": true}, {"reason": "Other", "request_type": "problem", "requires_items": false, "requires_explanation": true}]'::jsonb);
insert into hunkart_cancel.settings select * from jsonb_populate_recordset(null::hunkart_cancel.settings, '[{"id": true, "enabled": true, "activated_at": "2026-09-16T16:08:55.644693+00:00", "activated_by": null, "policy_version": "food-grocery-v1", "request_layer_version": null, "full_refund_policy_accepted": true}]'::jsonb);
insert into hunkart_cancel.policy_rules select * from jsonb_populate_recordset(null::hunkart_cancel.policy_rules, '[{"kind": "food", "condition_en": "You may request cancellation before food preparation starts. A reason and explanation are required. Your request is subject to Admin review.", "policy_version": "food-grocery-v1", "cancel_statuses": ["new", "confirmed"], "stop_at_preparation": true}, {"kind": "grocery", "condition_en": "You may request cancellation before pickup or dispatch. A reason and explanation are required. Your request is subject to Admin review.", "policy_version": "food-grocery-v1", "cancel_statuses": ["new", "confirmed", "preparing", "packed"], "stop_at_preparation": false}, {"kind": "manual", "condition_en": "Please contact support for cancellation review. You may report a missing, wrong, damaged, expired or spoiled item even after delivery.", "policy_version": "food-grocery-v1", "cancel_statuses": [], "stop_at_preparation": true}]'::jsonb);
CREATE TRIGGER hc_capture_item_rule AFTER INSERT ON public.order_items FOR EACH ROW EXECUTE FUNCTION hunkart_cancel.capture_item_rule();
CREATE TRIGGER hc_guard_order BEFORE UPDATE ON public.orders FOR EACH ROW EXECUTE FUNCTION hunkart_cancel.guard_order();
CREATE TRIGGER hc_guard_shop_fulfilment BEFORE INSERT OR UPDATE ON public.shop_order_status FOR EACH ROW EXECUTE FUNCTION hunkart_cancel.guard_fulfilment();
CREATE TRIGGER hc_guard_delivery_fulfilment BEFORE INSERT OR UPDATE ON public.delivery_tracking FOR EACH ROW EXECUTE FUNCTION hunkart_cancel.guard_fulfilment();
CREATE TRIGGER hc_guard_items BEFORE INSERT OR DELETE OR UPDATE ON public.order_items FOR EACH ROW EXECUTE FUNCTION hunkart_cancel.guard_items();
CREATE TRIGGER hc_set_customer_cancel_until BEFORE INSERT ON public.orders FOR EACH ROW EXECUTE FUNCTION hunkart_cancel.set_customer_cancel_until();
alter table hunkart_cancel.cases drop constraint cases_actor_check;alter table hunkart_cancel.cases add constraint cases_actor_check check(actor in ('customer','admin','shopkeeper')); 