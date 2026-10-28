create or replace function hunkart_dispatch.is_admin() returns boolean language plpgsql security definer set search_path='' as $$
declare result boolean;
begin
 if auth.uid() is null then return false;end if;
 if to_regprocedure('public.is_app_admin()') is not null then
  execute 'select coalesce(public.is_app_admin(),false)' into result;return result;
 end if;
 -- Staging schema has no legacy helper: use the server-owned allowlist and
 -- confirmed auth.users record; never trust user-editable metadata.
 return exists(select 1 from auth.users u join public.app_admins a on lower(a.email)=lower(u.email) where u.id=auth.uid() and u.email_confirmed_at is not null);
end $$;
revoke all on function hunkart_dispatch.is_admin() from public,anon,authenticated;
