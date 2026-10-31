-- Staging-only staff subscription API; does not replace the production RPC.
create or replace function hunkart_dispatch.save_staff_subscription(p_role text,p_endpoint text,p_p256dh text,p_auth text,p_user_agent text default null)
returns boolean language plpgsql security definer set search_path='' as $$
declare uid uuid:=auth.uid(); changed integer;
begin
 if uid is null then raise exception 'Please log in' using errcode='42501';end if;
 if p_role is null or not (
 (p_role='shopkeeper' and exists(select 1 from public.shopkeepers where user_id=uid and active))
 or (p_role='delivery_boy' and exists(select 1 from public.delivery_boys where user_id=uid and is_active))
 or (p_role='admin' and hunkart_dispatch.is_admin())
 ) then raise exception 'Active staff role required' using errcode='42501';end if;
 if p_endpoint is null or length(p_endpoint)>2048 or p_endpoint !~ '^https://(fcm[.]googleapis[.]com|updates[.]push[.]services[.]mozilla[.]com|web[.]push[.]apple[.]com|[a-zA-Z0-9-]+([.][a-zA-Z0-9-]+)*[.]notify[.]windows[.]com)/[^[:space:]]+$'
 or p_p256dh is null or p_p256dh !~ '^[A-Za-z0-9_-]{87}=?$'
 or p_auth is null or p_auth !~ '^[A-Za-z0-9_-]{22}(==)?$' then raise exception 'Invalid push subscription';end if;
 insert into public.staff_push_subscriptions(user_id,role,endpoint,p256dh,auth_key,user_agent)
 values(uid,p_role,p_endpoint,p_p256dh,p_auth,left(p_user_agent,500))
 on conflict(endpoint) do update set role=excluded.role,p256dh=excluded.p256dh,auth_key=excluded.auth_key,user_agent=excluded.user_agent,updated_at=now()
 where public.staff_push_subscriptions.user_id=uid;
 get diagnostics changed=row_count;
 if changed<>1 then raise exception 'Browser subscription belongs to another account' using errcode='42501';end if;
 return true;
end $$;
create or replace function public.hd_save_staff_push_subscription(p_role text,p_endpoint text,p_p256dh text,p_auth text,p_user_agent text default null)
returns boolean language sql security invoker set search_path='' as $$
 select hunkart_dispatch.save_staff_subscription(p_role,p_endpoint,p_p256dh,p_auth,p_user_agent)
$$;
revoke all on function hunkart_dispatch.save_staff_subscription(text,text,text,text,text),public.hd_save_staff_push_subscription(text,text,text,text,text) from public,anon;
grant execute on function hunkart_dispatch.save_staff_subscription(text,text,text,text,text),public.hd_save_staff_push_subscription(text,text,text,text,text) to authenticated;
