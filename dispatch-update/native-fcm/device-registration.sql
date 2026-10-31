create table if not exists hunkart_dispatch.native_devices (
 id bigint generated always as identity primary key,
 user_id uuid not null references auth.users(id) on delete cascade,
 role text not null check (role in ('shopkeeper','delivery_boy')),
 token text not null unique check (length(token) between 20 and 4096 and token !~ '[[:space:]]'),
 updated_at timestamptz not null default now()
);
alter table hunkart_dispatch.native_devices enable row level security;
revoke all on hunkart_dispatch.native_devices from public, anon, authenticated;

create or replace function hunkart_dispatch.save_native_device(p_role text,p_token text)
returns boolean language plpgsql security definer set search_path='' as $$
declare uid uuid:=auth.uid(); changed integer;
begin
 if uid is null then raise exception 'Please log in' using errcode='42501'; end if;
 if p_role is null or not (
  (p_role='shopkeeper' and exists(select 1 from public.shopkeepers where user_id=uid and active))
  or (p_role='delivery_boy' and exists(select 1 from public.delivery_boys where user_id=uid and is_active))
 ) then raise exception 'Active staff role required' using errcode='42501'; end if;
 if p_token is null or length(p_token) not between 20 and 4096 or p_token ~ '[[:space:]]' then
  raise exception 'Invalid device token' using errcode='22023'; end if;
 insert into hunkart_dispatch.native_devices(user_id,role,token)
 values(uid,p_role,p_token)
 on conflict(token) do update set role=excluded.role,updated_at=now()
 where hunkart_dispatch.native_devices.user_id=uid;
 get diagnostics changed=row_count;
 if changed<>1 then raise exception 'Device belongs to another account' using errcode='42501'; end if;
 return true;
end $$;
create or replace function hunkart_dispatch.remove_native_device(p_token text)
returns boolean language plpgsql security definer set search_path='' as $$
begin
 if auth.uid() is null then raise exception 'Please log in' using errcode='42501'; end if;
 delete from hunkart_dispatch.native_devices where user_id=auth.uid() and token=p_token;
 return found;
end $$;
create or replace function public.hd_save_native_device(p_role text,p_token text)
returns boolean language sql security invoker set search_path='' as $$
 select hunkart_dispatch.save_native_device(p_role,p_token)
$$;
create or replace function public.hd_remove_native_device(p_token text)
returns boolean language sql security invoker set search_path='' as $$
 select hunkart_dispatch.remove_native_device(p_token)
$$;
revoke all on function hunkart_dispatch.save_native_device(text,text),hunkart_dispatch.remove_native_device(text),public.hd_save_native_device(text,text),public.hd_remove_native_device(text) from public,anon;
grant usage on schema hunkart_dispatch to authenticated;
grant execute on function hunkart_dispatch.save_native_device(text,text),hunkart_dispatch.remove_native_device(text),public.hd_save_native_device(text,text),public.hd_remove_native_device(text) to authenticated;
