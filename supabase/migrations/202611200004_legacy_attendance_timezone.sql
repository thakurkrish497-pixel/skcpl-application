-- Additive parser correction. No source attendance/task UPDATE or DELETE.
begin;
set local lock_timeout='2s';
create or replace function public.skcpl_attendance_instant(value text) returns timestamptz
language sql immutable set search_path='' as $$
 select case when value ~* '(Z|[+-][0-9]{2}:[0-9]{2}|[+-][0-9]{4})$'
 then value::timestamptz else value::timestamp at time zone 'Asia/Kolkata' end;
$$;
revoke all on function public.skcpl_attendance_instant(text) from public,anon,authenticated;
create or replace function public.skcpl_capture_attendance_session(doc jsonb) returns void
language plpgsql security definer set search_path='' as $$
declare activated timestamptz; entered timestamptz; work_day date; cutoff timestamptz; settings jsonb; start_time time; end_time time; india timestamp;
begin
 select activated_at into activated from public.skcpl_attendance_reset_config where singleton and enabled;
 if activated is null or nullif(doc->>'punch_in_time','') is null or nullif(doc->>'punch_out_time','') is not null then return;end if;
 entered:=public.skcpl_attendance_instant(doc->>'punch_in_time');
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
create or replace function public.skcpl_close_expired_attendance(p_now timestamptz default now()) returns jsonb
language plpgsql security definer set search_path='' as $$
declare doc jsonb; captured public.skcpl_attendance_sessions; closed_count integer:=0; skipped_count integer:=0; affected integer;
begin
 if not exists(select 1 from public.skcpl_attendance_reset_config where singleton and enabled) then return '{"enabled":false,"closed":0,"errors":0}'::jsonb;end if;
 for doc in select * from public.skcpl_attendance_open_sources() loop
  begin
   perform public.skcpl_capture_attendance_session(doc);
   select * into captured from public.skcpl_attendance_sessions where attendance_id=doc->>'id' and punch_in_time=public.skcpl_attendance_instant(doc->>'punch_in_time');
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
commit;
