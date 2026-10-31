BEGIN;
DO $$ DECLARE fresh text:='retention-fresh-'||gen_random_uuid(); recent text:='retention-recent-'||gen_random_uuid(); before_count integer; removed integer;
BEGIN
insert into hunkart_dispatch.staff_worker_invocations(token_hash,expires_at)
select 'retention-old-'||gen_random_uuid(),clock_timestamp()-interval '2 hours' from generate_series(1,1005);
insert into hunkart_dispatch.staff_worker_invocations(token_hash,expires_at) values(fresh,clock_timestamp()+interval '1 minute'),(recent,clock_timestamp()-interval '1 minute');
select count(*) into before_count from hunkart_dispatch.staff_worker_invocations where expires_at<clock_timestamp()-interval '1 hour';
removed:=hunkart_dispatch.prune_staff_invocations();
if removed<>1000 then raise exception 'Batch bound failed';end if;
if (select count(*) from hunkart_dispatch.staff_worker_invocations where expires_at<clock_timestamp()-interval '1 hour')<>before_count-1000 then raise exception 'Retention count failed';end if;
if (select count(*) from hunkart_dispatch.staff_worker_invocations where token_hash in(fresh,recent))<>2 then raise exception 'Recent tokens deleted';end if;
if has_function_privilege('anon','hunkart_dispatch.prune_staff_invocations()','execute') or has_function_privilege('authenticated','hunkart_dispatch.prune_staff_invocations()','execute') then raise exception 'Client permission exposed';end if;
END $$;
SELECT 'PASS: bounded cleanup, remaining backlog, recent token preservation, client access denied' AS result;
ROLLBACK;