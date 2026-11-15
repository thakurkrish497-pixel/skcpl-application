-- LOCAL REVIEW ONLY. Apply after review and a coordinated native-app rollout.
-- Additive account control; never recreates users or changes operational record IDs.
begin;
create table if not exists public.skcpl_management_state (
  singleton boolean primary key default true check (singleton),
  revision bigint not null default 0,
  accounts_user_id uuid references public.users(id) on delete restrict,
  project_head_user_id uuid references public.users(id) on delete restrict,
  settings jsonb not null,
  lock_id uuid, lock_owner uuid, lock_until timestamptz,
  updated_at timestamptz not null default now()
);
create table if not exists public.skcpl_management_operations (
  id uuid primary key, actor_id uuid not null references public.users(id),
  request_hash text not null, plan jsonb not null, auth_applied jsonb not null default '[]',
  status text not null default 'saving' check(status in ('saving','partial','complete')),
  result jsonb, created_at timestamptz not null default now(), updated_at timestamptz not null default now()
);
alter table public.skcpl_management_state enable row level security;
alter table public.skcpl_management_operations enable row level security;
revoke all on public.skcpl_management_state, public.skcpl_management_operations from anon, authenticated;
grant select on public.skcpl_management_state to authenticated;
grant all on public.skcpl_management_state, public.skcpl_management_operations to service_role;
create policy "Authenticated clients observe nonsecret management state" on public.skcpl_management_state for select to authenticated using (true);

-- Link an existing official Project Head Auth identity when its ERP profile is missing.
-- Never recreate Auth users, replace UUIDs, or alter a pre-existing profile/history.
do $profile$
begin
 if exists(select 1 from auth.users a where lower(a.email)='projecthead@skcpl.com'
   and not exists(select 1 from public.users u where u.id=a.id)) then
   if exists(select 1 from public.users where lower(email)='projecthead@skcpl.com') then
     raise exception 'Project Head email belongs to another ERP profile. Resolve the binding without replacing its ID.' using errcode='22023';
   end if;
   insert into public.users(id,email,role,is_active)
   select id,email,'project_head',true from auth.users where lower(email)='projecthead@skcpl.com';
 end if;
end $profile$;

do $seed$
declare legacy jsonb := '{}'; aid uuid; pid uuid; settings jsonb;
begin
  begin
    select description::jsonb into legacy from public.tasks where title='CONFIG:ROLE_PERMISSIONS' order by updated_at desc limit 1;
  exception when others then legacy := '{}'; end;
  legacy := coalesce(legacy, '{}');
  settings := jsonb_build_object(
    'accounts_email',coalesce(legacy->>'accounts_email','accounts@skcpl.com'),
    'project_head_email',coalesce(legacy->>'project_head_email','projecthead@skcpl.com'),
    'accounts_login_id','accounts','project_head_login_id','project',
    'accounts_credential_revision',0,'project_head_credential_revision',0,
    'accounts_can_approve_cash',coalesce((legacy->>'accounts_can_approve_cash')::boolean,true),
    'accounts_can_approve_stock',coalesce((legacy->>'accounts_can_approve_stock')::boolean,true),
    'accounts_can_approve_attendance',coalesce((legacy->>'accounts_can_approve_attendance')::boolean,false),
    'accounts_can_approve_dsr',coalesce((legacy->>'accounts_can_approve_dsr')::boolean,false),
    'project_head_can_approve_cash',coalesce((legacy->>'project_head_can_approve_cash')::boolean,true),
    'project_head_can_approve_stock',coalesce((legacy->>'project_head_can_approve_stock')::boolean,true),
    'project_head_can_approve_attendance',coalesce((legacy->>'project_head_can_approve_attendance')::boolean,true),
    'project_head_can_approve_dsr',coalesce((legacy->>'project_head_can_approve_dsr')::boolean,true));
  select id into aid from public.users where role='accounts' and is_active=true and lower(email)=lower(settings->>'accounts_email');
  if aid is null and (select count(*) from public.users where role='accounts' and is_active=true)=1 then
    select id into aid from public.users where role='accounts' and is_active=true;
  end if;
  select id into pid from public.users where role='project_head' and is_active=true and lower(email)=lower(settings->>'project_head_email');
  if pid is null and (select count(*) from public.users where role='project_head' and is_active=true)=1 then
    select id into pid from public.users where role='project_head' and is_active=true;
  end if;
  insert into public.skcpl_management_state(accounts_user_id,project_head_user_id,settings)
    values(aid,pid,settings) on conflict(singleton) do nothing;
end $seed$;

create or replace function public.skcpl_management_policy() returns jsonb
language sql stable security definer set search_path='' as $$
 select settings || jsonb_build_object('revision',revision) from public.skcpl_management_state where singleton;
$$;
revoke all on function public.skcpl_management_policy() from public;
grant execute on function public.skcpl_management_policy() to anon,authenticated,service_role;

create or replace function public.skcpl_resolve_management_login(p_login text) returns text
language sql stable security definer set search_path='' as $$
 select a.email from public.skcpl_management_state s
 join auth.users a on a.id=case when lower(s.settings->>'accounts_login_id')=lower(trim(p_login)) then s.accounts_user_id
                              when lower(s.settings->>'project_head_login_id')=lower(trim(p_login)) then s.project_head_user_id end
 join public.users u on u.id=a.id and u.is_active=true
 where s.singleton and length(p_login) between 1 and 64 and u.role in ('accounts','project_head');
$$;
revoke all on function public.skcpl_resolve_management_login(text) from public;
grant execute on function public.skcpl_resolve_management_login(text) to anon,authenticated,service_role;

create or replace function public.skcpl_require_management_session() returns void
language plpgsql stable security definer set search_path='' as $$
declare r text; cfg jsonb; required_revision bigint; token_revision bigint;
begin
 select role::text into r from public.users where id=auth.uid() and is_active=true;
 if r is null or r not in ('admin','accounts','project_head') then raise exception 'Active management sign-in required' using errcode='42501'; end if;
 if r='admin' then return; end if;
 select settings into strict cfg from public.skcpl_management_state where singleton;
 required_revision:=coalesce((cfg->>(r||'_credential_revision'))::bigint,0);
 token_revision:=coalesce((auth.jwt()->'app_metadata'->>'skcpl_credential_revision')::bigint,0);
 if token_revision<required_revision then raise exception 'Login details changed. Sign in again; saved entries remain on your device.' using errcode='42501'; end if;
end $$;
revoke all on function public.skcpl_require_management_session() from public;

create or replace function public.skcpl_management_snapshot() returns jsonb
language plpgsql stable security definer set search_path='' as $$
declare s public.skcpl_management_state; result jsonb; r text; uid uuid; email text;
begin
 select * into strict s from public.skcpl_management_state where singleton;
 result:=jsonb_build_object('policy',s.settings||jsonb_build_object('revision',s.revision),'roles','{}'::jsonb);
 foreach r in array array['accounts','project_head'] loop
   uid:=case when r='accounts' then s.accounts_user_id else s.project_head_user_id end;
   select a.email into email from auth.users a join public.users u on u.id=a.id where a.id=uid and u.role::text=r and u.is_active=true;
   if email is null then raise exception 'Role account % must be linked to one active existing Auth user before editing.',r using errcode='22023'; end if;
   result:=jsonb_set(result,array['roles',r],jsonb_build_object('user_id',uid,'email',email,
       'login_id',s.settings->>(r||'_login_id'),'credential_revision',s.settings->(r||'_credential_revision')));
 end loop;
 return result;
end $$;

create or replace function public.skcpl_management_begin(p_operation uuid,p_owner uuid,p_actor uuid,p_hash text,p_revision bigint,p_plan jsonb) returns jsonb
language plpgsql security definer set search_path='' as $$
declare s public.skcpl_management_state; op public.skcpl_management_operations; r text; card jsonb; uid uuid;
begin
 if not exists(select 1 from public.users where id=p_actor and role='admin' and is_active=true) then raise exception 'Active Admin required' using errcode='42501'; end if;
 select * into strict s from public.skcpl_management_state where singleton for update;
 select * into op from public.skcpl_management_operations where id=p_operation;
 if found then
   if op.actor_id<>p_actor or op.request_hash<>p_hash then raise exception 'Save token does not match this request' using errcode='22023'; end if;
   if op.status='complete' then return jsonb_build_object('complete',true,'result',public.skcpl_management_snapshot()); end if;
 end if;
 if s.lock_until>now() then raise exception 'A settings save is already running. Please wait and retry.' using errcode='55P03'; end if;
 if s.revision<>p_revision then raise exception 'Settings changed on another device. Reload before saving.' using errcode='40001'; end if;
 foreach r in array array['accounts','project_head'] loop
   card:=p_plan->'roles'->r;
   uid:=case when r='accounts' then s.accounts_user_id else s.project_head_user_id end;
   if uid is null or (card->>'user_id')::uuid is distinct from uid or not exists(select 1 from public.users where id=uid and role::text=r and is_active=true) then
     raise exception 'Target role identity changed. Reload settings.' using errcode='42501';
   end if;
   if exists(select 1 from auth.users where lower(email)=lower(card->>'email') and id<>uid) then
     raise exception 'That email is already used by another account.' using errcode='23505';
   end if;
 end loop;
 if lower(p_plan->'roles'->'accounts'->>'email')=lower(p_plan->'roles'->'project_head'->>'email') then raise exception 'Each role needs a different email.' using errcode='23505'; end if;
 insert into public.skcpl_management_operations(id,actor_id,request_hash,plan) values(p_operation,p_actor,p_hash,p_plan)
 on conflict(id) do update set status='saving',updated_at=now();
 update public.skcpl_management_state set lock_id=p_operation,lock_owner=p_owner,lock_until=now()+interval '5 minutes' where singleton;
 return jsonb_build_object('complete',false,'auth_applied',coalesce(op.auth_applied,'[]'::jsonb));
end $$;

create or replace function public.skcpl_management_progress(p_operation uuid,p_owner uuid,p_role text) returns void
language plpgsql security definer set search_path='' as $$
begin
 if not exists(select 1 from public.skcpl_management_state where singleton and lock_id=p_operation and lock_owner=p_owner and lock_until>now()) then raise exception 'Save lease expired' using errcode='40001'; end if;
 update public.skcpl_management_operations set auth_applied=case when auth_applied ? p_role then auth_applied else auth_applied||jsonb_build_array(p_role) end,updated_at=now() where id=p_operation;
end $$;

create or replace function public.skcpl_management_finish(p_operation uuid,p_owner uuid) returns jsonb
language plpgsql security definer set search_path='' as $$
declare s public.skcpl_management_state; op public.skcpl_management_operations; cfg jsonb; r text; card jsonb; tid uuid; sid uuid; saved_result jsonb;
begin
 select * into strict s from public.skcpl_management_state where singleton for update;
 select * into strict op from public.skcpl_management_operations where id=p_operation for update;
 if op.status='complete' then return public.skcpl_management_snapshot(); end if;
 if s.lock_id is distinct from p_operation or s.lock_owner is distinct from p_owner or s.lock_until<=now() then raise exception 'Save lease expired' using errcode='40001'; end if;
 cfg:=s.settings || (op.plan->'permissions');
 foreach r in array array['accounts','project_head'] loop
   card:=op.plan->'roles'->r;
   if (card->>'credentials_changed')::boolean and not op.auth_applied ? r then raise exception 'Credentials not yet acknowledged for %',r using errcode='40001'; end if;
   cfg:=cfg || jsonb_build_object(r||'_login_id',card->>'login_id',r||'_email',card->>'email',
         r||'_credential_revision',coalesce((s.settings->>(r||'_credential_revision'))::bigint,0)+case when (card->>'credentials_changed')::boolean then 1 else 0 end);
   update public.users set email=card->>'email' where id=(card->>'user_id')::uuid;
 end loop;
 -- Mirror only nonsecret settings for older clients. No transaction/history updates.
 perform set_config('skcpl.management_write','allowed',true);
 select id into tid from public.tasks where title='CONFIG:ROLE_PERMISSIONS' order by updated_at desc limit 1;
 if tid is not null then
   update public.tasks set description=cfg::text,updated_at=now() where id=tid;
 else
   select id into sid from public.sites order by id limit 1;
   if sid is null then raise exception 'Create a company site before saving permissions.'; end if;
   insert into public.tasks(site_id,created_by,title,description,status,priority)
     values(sid,op.actor_id,'CONFIG:ROLE_PERMISSIONS',cfg::text,'completed','high');
 end if;
 update public.skcpl_management_state set settings=cfg,revision=s.revision+1,lock_id=null,lock_owner=null,lock_until=null,updated_at=now() where singleton;
 saved_result:=public.skcpl_management_snapshot();
 update public.skcpl_management_operations set status='complete',result=saved_result,updated_at=now() where id=p_operation;
 return saved_result;
end $$;

create or replace function public.skcpl_management_abort(p_operation uuid,p_owner uuid) returns void
language plpgsql security definer set search_path='' as $$
begin
 update public.skcpl_management_state set lock_id=null,lock_owner=null,lock_until=null where singleton and lock_id=p_operation and lock_owner=p_owner;
 update public.skcpl_management_operations set status='partial',updated_at=now() where id=p_operation and status<>'complete';
end $$;

create or replace function public.skcpl_protect_management_task() returns trigger
language plpgsql set search_path='' as $$
begin
 if (case when tg_op='DELETE' then old.title='CONFIG:ROLE_PERMISSIONS' else new.title='CONFIG:ROLE_PERMISSIONS' or (tg_op='UPDATE' and old.title='CONFIG:ROLE_PERMISSIONS') end)
 and coalesce(current_setting('skcpl.management_write',true),'')<>'allowed'
 and coalesce(auth.role(),'')<>'service_role' then
   raise exception 'Use the protected Admin control to change role permissions.' using errcode='42501';
 end if;
 if tg_op='DELETE' then return old; end if; return new;
end $$;
create trigger skcpl_protect_management_task before insert or update or delete on public.tasks for each row execute function public.skcpl_protect_management_task();

-- Privileged coordination is never callable directly by an employee/anonymous client.
revoke all on function public.skcpl_management_snapshot() from public;
revoke all on function public.skcpl_management_begin(uuid,uuid,uuid,text,bigint,jsonb) from public;
revoke all on function public.skcpl_management_progress(uuid,uuid,text) from public;
revoke all on function public.skcpl_management_finish(uuid,uuid) from public;
revoke all on function public.skcpl_management_abort(uuid,uuid) from public;
grant execute on function public.skcpl_management_snapshot() to service_role;
grant execute on function public.skcpl_management_begin(uuid,uuid,uuid,text,bigint,jsonb) to service_role;
grant execute on function public.skcpl_management_progress(uuid,uuid,text) to service_role;
grant execute on function public.skcpl_management_finish(uuid,uuid) to service_role;
grant execute on function public.skcpl_management_abort(uuid,uuid) to service_role;
do $$ begin
 if exists(select 1 from pg_publication where pubname='supabase_realtime') and not exists(select 1 from pg_publication_tables where pubname='supabase_realtime' and schemaname='public' and tablename='skcpl_management_state') then
   alter publication supabase_realtime add table public.skcpl_management_state;
 end if;
end $$;
commit;
