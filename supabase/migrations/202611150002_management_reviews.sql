-- Optional Accounts Attendance/DSR checkpoint with verified server-side decisions.
begin;
create table if not exists public.skcpl_entry_reviews(
 module text not null check(module in ('attendance','dsr')), entry_id uuid not null,
 state jsonb not null default '{}', revision bigint not null default 0,
 updated_at timestamptz not null default now(), primary key(module,entry_id)
);
alter table public.skcpl_entry_reviews enable row level security;
revoke all on public.skcpl_entry_reviews from anon,authenticated;
grant select on public.skcpl_entry_reviews to authenticated;
grant all on public.skcpl_entry_reviews to service_role;
create policy "Management observes review decisions" on public.skcpl_entry_reviews for select to authenticated using(
 exists(select 1 from public.users where id=auth.uid() and is_active=true and role in ('admin','project_head','accounts')));

create or replace function public.skcpl_try_json(value text) returns jsonb language plpgsql immutable set search_path='' as $$
begin return value::jsonb; exception when others then return null; end $$;
revoke all on function public.skcpl_try_json(text) from public;

create or replace function public.skcpl_next_review(p_module text,p_data jsonb,p_review jsonb,p_policy jsonb) returns text
language plpgsql immutable set search_path='' as $$
declare remarks text:=coalesce(p_data->>'remarks',''); head_done boolean;
begin
 if p_review ? 'final' then return null; end if;
 if p_module='attendance' and coalesce(p_data->>'status','') not in ('regularizationPending','regularization_pending') then return null; end if;
 if p_module='dsr' and (remarks like '%[Admin: Approved%' or remarks like '%[Admin: Rejected%' or remarks like '%[Project Head: Rejected%' or remarks like '%[Supervisor: Rejected%' or remarks like '%[Accounts: Rejected%') then return null; end if;
 head_done:=p_review->'project_head'->>'decision'='approved' or (p_module='dsr' and (remarks like '%[Project Head: Approved%' or remarks like '%[Supervisor: Approved%'));
 if coalesce((p_policy->>('project_head_can_approve_'||p_module))::boolean,true) and not coalesce(head_done,false) then return 'project_head'; end if;
 if coalesce((p_policy->>('accounts_can_approve_'||p_module))::boolean,false) and coalesce(p_review->'accounts'->>'decision','')<>'approved' then return 'accounts'; end if;
 return 'admin';
end $$;
revoke all on function public.skcpl_next_review(text,jsonb,jsonb,jsonb) from public;

create or replace function public.skcpl_review_queue(p_module text,p_site text default 'all')
returns table(entry_id uuid,data jsonb,review_state jsonb,review_revision bigint,source_version text)
language plpgsql stable security definer set search_path='' as $$
declare actor text; policy jsonb; source text; primary_name text; tag text;
begin
 perform public.skcpl_require_management_session();
 if p_module not in ('attendance','dsr') then raise exception 'Invalid review module' using errcode='22023'; end if;
 select role::text into actor from public.users where id=auth.uid() and is_active=true;
 if actor is null or actor not in ('admin','accounts','project_head') then raise exception 'Management sign-in required' using errcode='42501'; end if;
 select settings into strict policy from public.skcpl_management_state where singleton;
 primary_name:=case when p_module='attendance' then 'attendance' else 'daily_site_reports' end;
 tag:=case when p_module='attendance' then 'ATTENDANCE:%' else 'DSR:%' end;
 source:=format('select public.skcpl_try_json(description) doc,1 priority from public.tasks where title like %L',tag);
 if to_regclass('public.'||primary_name) is not null then
   source:=format('select to_jsonb(t) doc,0 priority from public.%I t union all ',primary_name)||source;
 end if;
 return query execute format($query$
   with src as materialized (select distinct on (doc->>'id') doc from (%s) sources
     where doc->>'id' ~ '^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$' order by doc->>'id',priority)
   select (src.doc->>'id')::uuid,src.doc,coalesce(r.state,'{}'::jsonb),coalesce(r.revision,0),md5(src.doc::text)
   from src left join public.skcpl_entry_reviews r on r.module=$1 and r.entry_id=(src.doc->>'id')::uuid
   where ($2='all' or src.doc->>'site_id'=$2) and public.skcpl_next_review($1,src.doc,coalesce(r.state,'{}'::jsonb),$3)=$4
   order by src.doc->>'date' desc,src.doc->>'id'
 $query$,source) using p_module,p_site,policy,actor;
end $$;
revoke all on function public.skcpl_review_queue(text,text) from public;
grant execute on function public.skcpl_review_queue(text,text) to authenticated;

create or replace function public.skcpl_review_entry(p_module text,p_entry uuid,p_approve boolean,p_note text,p_half_day boolean,p_review_revision bigint,p_source_version text)
returns jsonb language plpgsql security definer set search_path='' as $$
declare actor uuid:=auth.uid(); actor_role text; policy jsonb; primary_name text; doc jsonb; task_id uuid;
 rv public.skcpl_entry_reviews; next_role text; decision jsonb; tag text; status text; label text; is_primary boolean:=false;
begin
 perform public.skcpl_require_management_session();
 if p_module not in ('attendance','dsr') or p_approve is null then raise exception 'Invalid review action' using errcode='22023'; end if;
 if length(coalesce(p_note,''))>2000 or (not p_approve and length(trim(coalesce(p_note,'')))=0) then raise exception 'A rejection reason is required (up to 2000 characters).' using errcode='22023'; end if;
 select role::text into actor_role from public.users where id=actor and is_active=true;
 if actor_role is null or actor_role not in ('admin','accounts','project_head') then raise exception 'Management sign-in required' using errcode='42501'; end if;
 select settings into strict policy from public.skcpl_management_state where singleton for share;
 primary_name:=case when p_module='attendance' then 'attendance' else 'daily_site_reports' end;
 if to_regclass('public.'||primary_name) is not null then
   execute format('select to_jsonb(t) from public.%I t where id=$1 for update',primary_name) into doc using p_entry;
   is_primary:=doc is not null;
 end if;
 if doc is null then
   select id,public.skcpl_try_json(description) into task_id,doc from public.tasks
    where title like case when p_module='attendance' then 'ATTENDANCE:%' else 'DSR:%' end
    and public.skcpl_try_json(description)->>'id'=p_entry::text order by updated_at desc limit 1 for update;
 end if;
 if doc is null then raise exception 'The review entry no longer exists.' using errcode='P0002'; end if;
 insert into public.skcpl_entry_reviews(module,entry_id) values(p_module,p_entry) on conflict do nothing;
 select * into strict rv from public.skcpl_entry_reviews where module=p_module and entry_id=p_entry for update;
 if rv.revision<>p_review_revision or md5(doc::text)<>p_source_version then raise exception 'Entry changed or was reviewed elsewhere. Refresh it first.' using errcode='40001'; end if;
 next_role:=public.skcpl_next_review(p_module,doc,rv.state,policy);
 if next_role is null then raise exception 'This entry has already been finalized.' using errcode='40001'; end if;
 if next_role<>actor_role then raise exception 'This checkpoint is disabled or an earlier review is required.' using errcode='42501'; end if;
 decision:=jsonb_build_object('decision',case when p_approve then 'approved' else 'rejected' end,'reviewed_by',actor,'reviewed_at',now(),'note',coalesce(p_note,''),'half_day',p_half_day);
 rv.state:=jsonb_set(rv.state,array[actor_role],decision);
 if not p_approve or actor_role='admin' then rv.state:=jsonb_set(rv.state,array['final'],decision); end if;
 perform set_config('skcpl.managed_review','allowed',true);
 if p_module='attendance' then
   if rv.state ? 'final' then
     status:=case when not p_approve then 'rejected' when p_half_day then 'regularizedHalfDay' else 'regularizedPresent' end;
     if is_primary then
       execute format('update public.%I set status=$1,admin_decision_note=$2,reviewed_by=$3,updated_at=now() where id=$4',primary_name)
         using status,coalesce(p_note,''),actor,p_entry;
     else
       doc:=doc||jsonb_build_object('status',status,'admin_decision_note',coalesce(p_note,''),'reviewed_by',actor,'updated_at',now());
     end if;
   end if;
 else
   label:=case actor_role when 'project_head' then 'Project Head' when 'accounts' then 'Accounts' else 'Admin' end;
   tag:=case when p_approve then format('[%s: Approved by %s]',label,actor) else format('[%s: Rejected - %s by %s]',label,replace(replace(p_note,'[','('),']',')'),actor) end;
   if is_primary then
     execute format('update public.%I set remarks=trim(coalesce(remarks,'''')||'' ''||$1),updated_at=now() where id=$2',primary_name) using tag,p_entry;
   else doc:=doc||jsonb_build_object('remarks',trim(coalesce(doc->>'remarks','')||' '||tag),'updated_at',now()); end if;
 end if;
 if not is_primary then
   update public.tasks set description=doc::text,updated_at=now() where id=task_id;
 else
   execute format('select to_jsonb(t) from public.%I t where id=$1',primary_name) into doc using p_entry;
 end if;
 update public.skcpl_entry_reviews set state=rv.state,revision=revision+1,updated_at=now() where module=p_module and entry_id=p_entry;
 return jsonb_build_object('data',doc,'state',rv.state,'next_role',public.skcpl_next_review(p_module,doc,rv.state,policy));
end $$;
revoke all on function public.skcpl_review_entry(text,uuid,boolean,text,boolean,bigint,text) from public;
grant execute on function public.skcpl_review_entry(text,uuid,boolean,text,boolean,bigint,text) to authenticated;

-- A stale client cannot finalize an attendance request while required reviews remain.
create or replace function public.skcpl_guard_attendance_review() returns trigger language plpgsql set search_path='' as $$
begin
 if old.status::text in ('regularizationPending','regularization_pending') and new.status::text<>old.status::text
 and coalesce(current_setting('skcpl.managed_review',true),'')<>'allowed' and coalesce(auth.role(),'')<>'service_role' then
   raise exception 'Use the verified attendance review action.' using errcode='42501';
 end if;
 return new;
end $$;
do $$ begin
 if to_regclass('public.attendance') is not null then
   create trigger skcpl_guard_attendance_review before update on public.attendance for each row execute function public.skcpl_guard_attendance_review();
 end if;
 if exists(select 1 from pg_publication where pubname='supabase_realtime') and not exists(select 1 from pg_publication_tables where pubname='supabase_realtime' and schemaname='public' and tablename='skcpl_entry_reviews') then
   alter publication supabase_realtime add table public.skcpl_entry_reviews;
 end if;
end $$;
-- Review markers and fallback records must use the same protected decision RPC.
create or replace function public.skcpl_guard_nonfinancial_review() returns trigger
language plpgsql security definer set search_path='' as $$
declare before_doc jsonb; after_doc jsonb; old_marks text; new_marks text; relevant boolean;
begin
 if coalesce(auth.role(),'')='service_role' or coalesce(current_setting('skcpl.managed_review',true),'')='allowed' then return new; end if;
 if tg_table_name='tasks' then
   relevant:=new.title like 'DSR:%' or new.title like 'ATTENDANCE:%' or
     (tg_op='UPDATE' and (old.title like 'DSR:%' or old.title like 'ATTENDANCE:%'));
   if not coalesce(relevant,false) then return new; end if;
   after_doc:=public.skcpl_try_json(new.description);
   if tg_op='UPDATE' then before_doc:=public.skcpl_try_json(old.description); end if;
 else
   after_doc:=to_jsonb(new);
   if tg_op='UPDATE' then before_doc:=to_jsonb(old); end if;
 end if;
 select coalesce(string_agg(m[1],'|' order by m[1]),'') into old_marks from regexp_matches(coalesce(before_doc->>'remarks',''),'(\[(?:Project Head|Supervisor|Accounts|Admin): (?:Approved|Edited & Approved|Rejected)[^]]*\])','g') m;
 select coalesce(string_agg(m[1],'|' order by m[1]),'') into new_marks from regexp_matches(coalesce(after_doc->>'remarks',''),'(\[(?:Project Head|Supervisor|Accounts|Admin): (?:Approved|Edited & Approved|Rejected)[^]]*\])','g') m;
 if old_marks<>new_marks then raise exception 'Use the verified DSR review action.' using errcode='42501'; end if;
 if tg_table_name='tasks' then
  if new.title like 'ATTENDANCE:%' or (tg_op='UPDATE' and old.title like 'ATTENDANCE:%') then
   if (before_doc->>'status' in ('regularizationPending','regularization_pending') and after_doc->>'status' is distinct from before_doc->>'status') or
      after_doc->>'reviewed_by' is distinct from before_doc->>'reviewed_by' then
     raise exception 'Use the verified attendance review action.' using errcode='42501'; end if;
  end if;
 end if;
 return new;
end $$;
do $$ begin
 create trigger skcpl_guard_fallback_review before insert or update on public.tasks for each row execute function public.skcpl_guard_nonfinancial_review();
 if to_regclass('public.daily_site_reports') is not null then
   create trigger skcpl_guard_dsr_review before insert or update on public.daily_site_reports for each row execute function public.skcpl_guard_nonfinancial_review();
 end if;
end $$;
commit;
