-- PREPARED ONLY. A separate telemetry table keeps GPS off the operational task lane.
-- Existing tables/policies are not replaced if already present.
begin;
set local lock_timeout='2s';
do $create$
begin
 if to_regclass('public.staff_live_locations') is null then
  create table public.staff_live_locations(
   staff_id text primary key check(length(staff_id)>0),staff_name text not null,staff_role text not null,
   site_id text not null,site_name text not null,
   latitude double precision not null check(latitude between -90 and 90),
   longitude double precision not null check(longitude between -180 and 180),
   accuracy_meters double precision not null check(accuracy_meters between 0 and 100),
   is_within_site boolean not null default false,
   distance_meters double precision not null check(distance_meters>=0 and distance_meters<'Infinity'::float8),
   timestamp timestamptz not null check(timestamp between now()-interval '2 minutes' and now()+interval '30 seconds'),address text
  );
  alter table public.staff_live_locations enable row level security;
  revoke all on public.staff_live_locations from public,anon,authenticated;
  -- Matches the existing shared Site-ID/PIN trust model; no financial permissions.
  grant select,insert,update on public.staff_live_locations to anon,authenticated;
  create policy "Read last staff fixes" on public.staff_live_locations for select to anon,authenticated using(true);
  create policy "Publish fresh staff fixes" on public.staff_live_locations for insert to anon,authenticated with check(true);
  create policy "Advance latest staff fix" on public.staff_live_locations for update to anon,authenticated using(true) with check(true);
 end if;
end;$create$;
create or replace function public.skcpl_location_timestamp_guard() returns trigger
language plpgsql set search_path='' as $$begin if new.timestamp<=old.timestamp then return null;end if;return new;end;$$;
revoke all on function public.skcpl_location_timestamp_guard() from public,anon,authenticated;
do $guard$
begin
 if not exists(select 1 from pg_trigger where tgrelid='public.staff_live_locations'::regclass and tgname='skcpl_location_timestamp_guard') then
  create trigger skcpl_location_timestamp_guard before update on public.staff_live_locations for each row execute function public.skcpl_location_timestamp_guard();
 end if;
end;$guard$;
-- Realtime metadata changes refresh only attendance/location displays.
do $publication$
declare relation text;
begin
 if exists(select 1 from pg_publication where pubname='supabase_realtime' and not puballtables) then
  foreach relation in array array['staff_live_locations','skcpl_attendance_sessions','skcpl_attendance_closures'] loop
   if not exists(select 1 from pg_publication_tables where pubname='supabase_realtime' and schemaname='public' and tablename=relation) then execute format('alter publication supabase_realtime add table public.%I',relation);end if;
  end loop;
 end if;
end;$publication$;
commit;
