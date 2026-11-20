-- PREPARED ONLY. Additive metadata; no UPDATE/DELETE on attendance or source tasks.
-- Automatic processing stays disabled until attendance_midnight_activate.sql is approved.
begin;
set local lock_timeout='2s';
create table if not exists public.skcpl_attendance_reset_config (
 singleton boolean primary key default true check(singleton),
 enabled boolean not null default false, activated_at timestamptz
);
insert into public.skcpl_attendance_reset_config(singleton) values(true) on conflict do nothing;
create table if not exists public.skcpl_attendance_sessions (
 attendance_id text primary key, staff_id text not null, site_id text not null,
 punch_in_time timestamptz not null, work_day date not null, expires_at timestamptz not null,
 shift_policy jsonb not null, captured_at timestamptz not null default now(),
 check(expires_at>punch_in_time)
);
create table if not exists public.skcpl_attendance_closures (
 attendance_id text primary key references public.skcpl_attendance_sessions(attendance_id),
 punch_in_time timestamptz not null, cutoff_at timestamptz not null,
 recorded_at timestamptz not null default now(), estimated boolean not null default true check(estimated),
 reason text not null default 'missing_punch_out_requires_review'
);
create table if not exists public.skcpl_attendance_reset_errors (
 attendance_id text primary key, error text not null, checked_at timestamptz not null default now()
);
alter table public.skcpl_attendance_reset_config enable row level security;
alter table public.skcpl_attendance_sessions enable row level security;
alter table public.skcpl_attendance_closures enable row level security;
alter table public.skcpl_attendance_reset_errors enable row level security;
revoke all on public.skcpl_attendance_reset_config,public.skcpl_attendance_sessions,public.skcpl_attendance_closures,public.skcpl_attendance_reset_errors from public,anon,authenticated;
-- Existing Site ID/PIN sessions use anon and already read their attendance source.
-- Only metadata reads are exposed. No client role may create or edit a closure.
grant select on public.skcpl_attendance_sessions,public.skcpl_attendance_closures to anon,authenticated;
create policy "Read attendance session metadata" on public.skcpl_attendance_sessions for select to anon,authenticated using(true);
create policy "Read estimated attendance closures" on public.skcpl_attendance_closures for select to anon,authenticated using(true);

create or replace function public.skcpl_attendance_safe_json(value text) returns jsonb
language plpgsql immutable set search_path='' as $$begin return value::jsonb;exception when others then return null;end;$$;

create or replace function public.skcpl_attendance_shift(p_site text) returns jsonb
language plpgsql stable security definer set search_path='' as $$
declare ids text[]; source text; result jsonb; first_stamp timestamptz;
begin
 ids:=case when p_site in ('office','89e1477d-7f66-4b6d-99ca-6270183143e0','bdb1478e-4fa9-4873-9804-864b0952fa4d')
 then array['89e1477d-7f66-4b6d-99ca-6270183143e0','office','bdb1478e-4fa9-4873-9804-864b0952fa4d','global'] else array[p_site,'global'] end;
 source:='select split_part(t.title,'':'',2) scope,public.skcpl_attendance_safe_json(t.description) doc,t.updated_at stamp,1 priority from public.tasks t where t.title like ''SHIFT_POLICY:%''';
 if to_regclass('public.site_shift_policies') is not null then
  source:='select p.site_id::text scope,to_jsonb(p) doc,nullif(to_jsonb(p)->>''updated_at'','''')::timestamptz stamp,0 priority from public.site_shift_policies p union all '||source;
 end if;
 execute format($q$
  with per_scope as (select distinct on(scope) scope,doc,stamp from (%s) s where scope=any($1) and jsonb_typeof(doc)='object' order by scope,priority,stamp desc nulls last),
  chosen_scope as (select * from per_scope where scope<>'global' or not exists(select 1 from per_scope where scope<>'global')),
  ordered as (select *,first_value(stamp) over(order by array_position($1,scope)) first_stamp from chosen_scope)
  select doc from ordered order by case when first_stamp is null then array_position($1,scope) else 0 end,stamp desc nulls last limit 1
 $q$,source) into result using ids;
 -- This is the same explicit default used by AttendanceService when no location was configured.
 return '{"shift_start_time":"09:00","shift_end_time":"18:00","grace_minutes":15}'::jsonb || jsonb_strip_nulls(coalesce(result,'{}'::jsonb));
end;$$;

create or replace function public.skcpl_attendance_open_sources() returns setof jsonb
language plpgsql stable security definer set search_path='' as $$
declare source text; floor_time timestamptz;
begin
 select (((activated_at at time zone 'Asia/Kolkata')::date-1)::timestamp at time zone 'Asia/Kolkata') into floor_time from public.skcpl_attendance_reset_config where singleton and enabled;
 if floor_time is null then return;end if;
 source:='select public.skcpl_attendance_safe_json(t.description) doc,1 priority from public.tasks t where t.title like ''ATTENDANCE:%'' and t.created_at >= $1';
 if to_regclass('public.attendance') is not null then
  source:='select to_jsonb(a) doc,0 priority from public.attendance a where a.date >= ($1 at time zone ''Asia/Kolkata'')::date union all '||source;
 end if;
 return query execute format($q$
  with dedup as (select distinct on(doc->>'id') doc from (%s) src where jsonb_typeof(doc)='object' and nullif(doc->>'id','') is not null order by doc->>'id',priority)
  select doc from dedup where nullif(doc->>'punch_in_time','') is not null and nullif(doc->>'punch_out_time','') is null
  and not exists(select 1 from public.skcpl_attendance_closures c where c.attendance_id=doc->>'id')
 $q$,source) using floor_time;
end;$$;

create or replace function public.skcpl_capture_attendance_session(doc jsonb) returns void
language plpgsql security definer set search_path='' as $$
declare activated timestamptz; entered timestamptz; work_day date; cutoff timestamptz; settings jsonb; start_time time; end_time time; india timestamp;
begin
 select activated_at into activated from public.skcpl_attendance_reset_config where singleton and enabled;
 if activated is null or nullif(doc->>'punch_in_time','') is null or nullif(doc->>'punch_out_time','') is not null then return;end if;
 entered:=(doc->>'punch_in_time')::timestamptz;
 india:=entered at time zone 'Asia/Kolkata';work_day:=india::date;
 settings:=public.skcpl_attendance_shift(doc->>'site_id');
 start_time:=(settings->>'shift_start_time')::time;end_time:=(settings->>'shift_end_time')::time;
 if start_time is null or end_time is null or start_time=end_time then raise exception 'Invalid assigned-location shift';end if;
 if end_time<start_time and india::time<end_time then work_day:=work_day-1;end if;
 cutoff:=case when end_time<start_time then ((work_day+1)+end_time) at time zone 'Asia/Kolkata' else (work_day+1)::timestamp at time zone 'Asia/Kolkata' end;
 -- Existing historical/expired shifts are excluded. Active overnight shifts survive rollout.
 if cutoff<=activated or cutoff<=entered then return;end if;
 insert into public.skcpl_attendance_sessions(attendance_id,staff_id,site_id,punch_in_time,work_day,expires_at,shift_policy)
 values(doc->>'id',doc->>'staff_id',doc->>'site_id',entered,work_day,cutoff,settings) on conflict do nothing;
end;$$;

create or replace function public.skcpl_attendance_session_insert() returns trigger
language plpgsql security definer set search_path='' as $$
declare doc jsonb;
begin
 if tg_table_name='tasks' then
  if new.title not like 'ATTENDANCE:%' then return new;end if;
  doc:=public.skcpl_attendance_safe_json(new.description);
 else doc:=to_jsonb(new);end if;
 begin
  perform public.skcpl_capture_attendance_session(doc);
 exception when others then
  insert into public.skcpl_attendance_reset_errors(attendance_id,error) values(coalesce(doc->>'id','unknown'),left(sqlstate||': '||sqlerrm,300)) on conflict(attendance_id) do update set error=excluded.error,checked_at=now();
 end;
 return new;
end;$$;
create trigger skcpl_attendance_capture_after_insert after insert on public.tasks for each row execute function public.skcpl_attendance_session_insert();
do $$begin
 if to_regclass('public.attendance') is not null then execute 'create trigger skcpl_attendance_capture_after_insert after insert on public.attendance for each row execute function public.skcpl_attendance_session_insert()';end if;
end;$$;

create or replace function public.skcpl_close_expired_attendance(p_now timestamptz default now()) returns jsonb
language plpgsql security definer set search_path='' as $$
declare doc jsonb; captured public.skcpl_attendance_sessions; closed_count integer:=0; skipped_count integer:=0; affected integer;
begin
 if not exists(select 1 from public.skcpl_attendance_reset_config where singleton and enabled) then return '{"enabled":false,"closed":0,"errors":0}'::jsonb;end if;
 for doc in select * from public.skcpl_attendance_open_sources() loop
  begin
   perform public.skcpl_capture_attendance_session(doc);
   select * into captured from public.skcpl_attendance_sessions where attendance_id=doc->>'id' and punch_in_time=(doc->>'punch_in_time')::timestamptz;
   if found and captured.expires_at<=p_now then
    insert into public.skcpl_attendance_closures(attendance_id,punch_in_time,cutoff_at,recorded_at) values(captured.attendance_id,captured.punch_in_time,captured.expires_at,p_now) on conflict do nothing;
    get diagnostics affected=row_count;closed_count:=closed_count+affected;
   end if;
  exception when others then
   skipped_count:=skipped_count+1;
   insert into public.skcpl_attendance_reset_errors(attendance_id,error) values(coalesce(doc->>'id','unknown'),left(sqlstate||': '||sqlerrm,300)) on conflict(attendance_id) do update set error=excluded.error,checked_at=p_now;
  end;
 end loop;
 return jsonb_build_object('enabled',true,'closed',closed_count,'errors',skipped_count);
end;$$;
revoke all on function public.skcpl_attendance_safe_json(text),public.skcpl_attendance_shift(text),public.skcpl_attendance_open_sources(),public.skcpl_capture_attendance_session(jsonb),public.skcpl_attendance_session_insert(),public.skcpl_close_expired_attendance(timestamptz) from public,anon,authenticated;
grant execute on function public.skcpl_close_expired_attendance(timestamptz) to service_role;
commit;
