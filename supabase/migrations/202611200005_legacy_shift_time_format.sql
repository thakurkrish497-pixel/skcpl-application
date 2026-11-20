-- Read legacy Admin HH.mm shifts as HH:mm; source policies/punches are not changed.
begin;
set local lock_timeout='2s';
create or replace function public.skcpl_capture_attendance_session(doc jsonb) returns void
language plpgsql security definer set search_path='' as $$
declare activated timestamptz; entered timestamptz; work_day date; cutoff timestamptz; settings jsonb; start_time time; end_time time; india timestamp;
begin
 select activated_at into activated from public.skcpl_attendance_reset_config where singleton and enabled;
 if activated is null or nullif(doc->>'punch_in_time','') is null or nullif(doc->>'punch_out_time','') is not null then return;end if;
 entered:=public.skcpl_attendance_instant(doc->>'punch_in_time');
 india:=entered at time zone 'Asia/Kolkata';work_day:=india::date;
 settings:=public.skcpl_attendance_shift(doc->>'site_id');
 start_time:=replace(settings->>'shift_start_time','.',':')::time;end_time:=replace(settings->>'shift_end_time','.',':')::time;
 if start_time is null or end_time is null or start_time=end_time then raise exception 'Invalid assigned-location shift';end if;
 if end_time<start_time and india::time<end_time then work_day:=work_day-1;end if;
 cutoff:=case when end_time<start_time then ((work_day+1)+end_time) at time zone 'Asia/Kolkata' else (work_day+1)::timestamp at time zone 'Asia/Kolkata' end;
 -- Existing historical/expired shifts are excluded. Active overnight shifts survive rollout.
 if cutoff<=activated or cutoff<=entered then return;end if;
 insert into public.skcpl_attendance_sessions(attendance_id,staff_id,site_id,punch_in_time,work_day,expires_at,shift_policy)
 values(doc->>'id',doc->>'staff_id',doc->>'site_id',entered,work_day,cutoff,settings) on conflict do nothing;
end;$$;
commit;
