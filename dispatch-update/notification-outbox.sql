-- Durable notification intent. Delivery worker is a separate release requirement.
create table if not exists hunkart_dispatch.notification_outbox(
 id uuid primary key default gen_random_uuid(),order_id uuid not null references public.orders(id) on delete cascade,
 customer_id uuid not null,event_name text not null check(event_name in ('order_confirmed','shop_rejected')),
 payload jsonb not null,status text not null default 'pending' check(status in ('pending','sending','sent','failed')),
 attempts integer not null default 0,lease_until timestamptz,last_error text,created_at timestamptz not null default now(),sent_at timestamptz,
 unique(order_id,event_name)
);
alter table hunkart_dispatch.notification_outbox enable row level security;
revoke all on hunkart_dispatch.notification_outbox from public,anon,authenticated;
create index if not exists hd_notification_pending on hunkart_dispatch.notification_outbox(created_at) where status in ('pending','sending');
create or replace function hunkart_dispatch.queue_customer_notification() returns trigger language plpgsql security definer set search_path='' as $$
begin
 if not exists(select 1 from hunkart_dispatch.settings where enabled) or new.customer_id is null then return new;end if;
 if old.status='new' and new.status='confirmed' then
  insert into hunkart_dispatch.notification_outbox(order_id,customer_id,event_name,payload) values(new.id,new.customer_id,'order_confirmed',jsonb_build_object('title','HUNKART Order Confirmed','body','Order '||new.order_number||': shop accepted your order.','url','/')) on conflict(order_id,event_name) do nothing;
 elsif old.status='new' and new.status='cancelled' and exists(select 1 from hunkart_cancel.cases where order_id=new.id and actor='shopkeeper' and status='approved') then
  insert into hunkart_dispatch.notification_outbox(order_id,customer_id,event_name,payload) values(new.id,new.customer_id,'shop_rejected',jsonb_build_object('title','HUNKART order update','body','Shop could not fulfil order '||new.order_number||'. Refund is queued; bank confirmation is pending.','url','/')) on conflict(order_id,event_name) do nothing;
 end if;return new;
end $$;
revoke all on function hunkart_dispatch.queue_customer_notification() from public,anon,authenticated;
create trigger hd_queue_customer_notification after update on public.orders for each row execute function hunkart_dispatch.queue_customer_notification();
