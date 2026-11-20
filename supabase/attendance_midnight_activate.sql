-- DEPLOY ONLY WITH THE APPROVED COMBINED RELEASE.
-- Records an activation boundary; no historical attendance row is edited.
create extension if not exists pg_cron with schema pg_catalog;
begin;
update public.skcpl_attendance_reset_config set enabled=true,activated_at=coalesce(activated_at,now()) where singleton;
select public.skcpl_close_expired_attendance();
select cron.schedule('skcpl-attendance-session-expiry','* * * * *','select public.skcpl_close_expired_attendance();');
commit;
-- To pause: cron.unschedule('skcpl-attendance-session-expiry'); then set enabled=false.
-- Do not delete the audit tables or any source attendance records.
