-- PREPARED ONLY: explicit rejected-entry cleanup. No historical backfill/deletion.
begin;
set local lock_timeout='2s';
-- Site-PIN profiles currently expose PINs to legacy clients. Do not silently grant
-- the public application key a new cleanup capability during a migration rollout.
-- This release is Admin-only. Worker actions also require a separate future opt-in.
create table public.skcpl_rejected_action_config(
 singleton boolean primary key default true check(singleton),
 worker_actions_enabled boolean not null default false,
 legacy_worker_actions_enabled boolean not null default false
);
insert into public.skcpl_rejected_action_config(singleton) values(true);
alter table public.skcpl_rejected_action_config enable row level security;
revoke all on public.skcpl_rejected_action_config from public,anon,authenticated;
create table public.skcpl_rejected_actions(
 module text not null check(module in ('cash','stock')),
 source_id uuid not null, action text not null check(action in ('dismiss','resubmit')),
 replacement_id uuid, actor_user_id uuid,actor_staff_id text,
 request jsonb,acted_at timestamptz not null default now(),
 primary key(module,source_id),unique(module,replacement_id),
 check((action='dismiss' and replacement_id is null) or(action='resubmit' and replacement_id is not null and replacement_id<>source_id))
);
alter table public.skcpl_rejected_actions enable row level security;
revoke all on public.skcpl_rejected_actions from public,anon,authenticated;
-- Private request/audit metadata is separate from the public identifier-only event feed.
create table public.skcpl_rejected_events(
 module text not null,source_id uuid not null,action text not null,replacement_id uuid,
 actor_staff_id text,acted_at timestamptz not null default now(),primary key(module,source_id),
 foreign key(module,source_id) references public.skcpl_rejected_actions(module,source_id)
);
alter table public.skcpl_rejected_events enable row level security;
revoke all on public.skcpl_rejected_events from public,anon,authenticated;
grant select on public.skcpl_rejected_events to anon,authenticated;
create policy "Read rejected action identifiers" on public.skcpl_rejected_events for select to anon,authenticated using(true);
create function public.skcpl_rejected_visible(p_module text,p_id uuid) returns boolean
language sql stable security definer set search_path='' as $$
 select not exists(select 1 from public.skcpl_rejected_actions where module=p_module and source_id=p_id);
$$;
revoke all on function public.skcpl_rejected_visible(text,uuid) from public;
grant execute on function public.skcpl_rejected_visible(text,uuid) to anon,authenticated;
-- RESTRICTIVE policies intersect every existing permissive read/edit policy.
create policy "Hide explicitly removed cash" on public.cash_transactions as restrictive for select to anon,authenticated using(public.skcpl_rejected_visible('cash',id));
create policy "Hide explicitly removed stock" on public.stock_transactions as restrictive for select to anon,authenticated using(public.skcpl_rejected_visible('stock',id));
create policy "Lock removed cash" on public.cash_transactions as restrictive for update to anon,authenticated using(public.skcpl_rejected_visible('cash',id)) with check(public.skcpl_rejected_visible('cash',id));
create policy "Lock removed stock" on public.stock_transactions as restrictive for update to anon,authenticated using(public.skcpl_rejected_visible('stock',id)) with check(public.skcpl_rejected_visible('stock',id));
create policy "Rejected cash requires fresh submission" on public.cash_transactions as restrictive for update to anon,authenticated using(status::text<>'rejected') with check(true);
create policy "Rejected stock requires fresh submission" on public.stock_transactions as restrictive for update to anon,authenticated using(status::text<>'rejected') with check(true);
-- Even Admin uses the checked action for rejected entries. No new raw DELETE right.
create policy "Reject direct rejected cash deletion" on public.cash_transactions as restrictive for delete to anon,authenticated using(status::text<>'rejected');
create policy "Reject direct rejected stock deletion" on public.stock_transactions as restrictive for delete to anon,authenticated using(status::text<>'rejected');

create function public.skcpl_rejected_staff(p_site uuid) returns setof jsonb
language plpgsql stable security definer set search_path='' as $$
begin
 if to_regclass('public.site_staff') is not null then
  return query execute 'select to_jsonb(s) from public.site_staff s where s.site_id::text=$1' using p_site::text;
 else
  return query select public.skcpl_attendance_safe_json(t.description) from public.tasks t where t.title like 'STAFF:%' and public.skcpl_attendance_safe_json(t.description)->>'site_id'=p_site::text;
 end if;
end;$$;
revoke all on function public.skcpl_rejected_staff(uuid) from public,anon,authenticated;

create function public.skcpl_rejected_entry_action(
 p_module text,p_source uuid,p_action text,p_new_id uuid default null,p_payload jsonb default null,
 p_staff_id text default null,p_staff_pin text default null,p_expected_updated timestamptz default null
) returns jsonb language plpgsql security definer set search_path='' as $$
declare tab text; original jsonb; result jsonb; staff jsonb; actor uuid:=auth.uid(); actor_role text;
 existing public.skcpl_rejected_actions; cfg jsonb; ph boolean; acc boolean; clean jsonb; nextrow jsonb;
 label text; original_label text; matches integer; field text; number numeric; allowed text[]; previous_staff text;
begin
 if p_module not in ('cash','stock') or p_action not in ('dismiss','resubmit') then raise exception 'Invalid rejected-entry action' using errcode='22023';end if;
  allowed:=case p_module when 'cash' then array['date','expense_type_id','expense_amount','amount_received','cash_in_hand','remarks','photo_urls'] else array['date','vendor_id','product_id','metric_unit_id','quantity','rate','sgst','igst','final_amount','remarks','unregistered_vendor','photo_urls'] end;
  select coalesce(jsonb_object_agg(key,value),'{}') into clean from jsonb_each(p_payload) where key=any(allowed);
 tab:=case p_module when 'cash' then 'cash_transactions' else 'stock_transactions' end;
 execute format('select to_jsonb(t) from public.%I t where id=$1 for update',tab) into original using p_source;
 if original is null or original->>'status'<>'rejected' then raise exception 'Only a currently rejected entry can be dismissed or resubmitted.' using errcode='42501';end if;
 select role::text into actor_role from public.users where id=actor and is_active=true;
 if actor_role is distinct from 'admin' and not exists(select 1 from public.skcpl_rejected_action_config where singleton and worker_actions_enabled) then raise exception 'Rejected-entry actions are Admin-only in this release. Your rejection feedback and correction remain preserved.' using errcode='42501';end if;
 if actor_role='admin' then
  perform public.skcpl_require_management_session();
 elsif actor_role='worker' and original->>'submitted_by'=actor::text then
  null; -- An authenticated worker may act on their own attributed voucher.
 elsif actor is null then
  if not exists(select 1 from public.skcpl_rejected_action_config where singleton and legacy_worker_actions_enabled) then raise exception 'Site-PIN cleanup is not activated yet. Admin can handle this entry; the original and your correction remain preserved.' using errcode='42501';end if;
  if length(coalesce(p_staff_id,''))=0 or length(coalesce(p_staff_pin,''))=0 then raise exception 'Select and verify the submitting staff member first.' using errcode='42501';end if;
  select d into staff from public.skcpl_rejected_staff((original->>'site_id')::uuid) d where d->>'id'=p_staff_id and coalesce((d->>'is_active')::boolean,true) and d->>'pin'=p_staff_pin;
  if staff is null then raise exception 'Staff identity could not be verified.' using errcode='42501';end if;
  if not exists(select 1 from jsonb_array_elements_text(coalesce(staff->'modules',jsonb_build_array(coalesce(staff->>'module','stock')))) v where (p_module='cash' and lower(trim(v)) in ('cashbook','cash','expense')) or (p_module='stock' and lower(trim(v))='stock')) then raise exception 'This module is not assigned to this staff member.' using errcode='42501';end if;
  if original->>'submitted_by' is not null then
   if actor is null or original->>'submitted_by'<>actor::text then raise exception 'Only the original submitter or Admin may act on this rejected entry.' using errcode='42501';end if;
  else
   select actor_staff_id into previous_staff from public.skcpl_rejected_actions where module=p_module and replacement_id=p_source;
   if previous_staff is not null then
    if previous_staff<>p_staff_id then raise exception 'This rejected entry belongs to another staff member.' using errcode='42501';end if;
   else
    original_label:=substring(coalesce(original->>'remarks','') from '\[By:\s*([^\]]+)\]');
    label:=(staff->>'name')||' ('||coalesce(staff->>'designation',case when staff->>'role'='supervisor' then 'Supervisor' else 'Worker' end)||')';
    select count(*) into matches from public.skcpl_rejected_staff((original->>'site_id')::uuid) d where coalesce((d->>'is_active')::boolean,true) and (d->>'name')||' ('||coalesce(d->>'designation',case when d->>'role'='supervisor' then 'Supervisor' else 'Worker' end)||')'=original_label;
    if original_label is distinct from label or matches<>1 then raise exception 'Original ownership is missing or ambiguous. Ask Admin to handle this rejected entry.' using errcode='42501';end if;
   end if;
  end if;
 else raise exception 'Only the original worker or Admin may remove rejected entries.' using errcode='42501';end if;
 select * into existing from public.skcpl_rejected_actions where module=p_module and source_id=p_source;
 if found then
  if existing.action<>p_action or (p_action='resubmit' and existing.replacement_id is distinct from p_new_id) then raise exception 'This rejected entry has already been handled. Refresh history.' using errcode='40001';end if;
  if p_action='resubmit' then
   if existing.request is distinct from clean then raise exception 'The earlier resubmission was already saved with different details. Refresh history before editing it.' using errcode='40001';end if;
   execute format('select to_jsonb(t) from public.%I t where id=$1',tab) into result using existing.replacement_id;
  end if;
  return jsonb_build_object('action',existing.action,'source_id',p_source,'replacement_id',existing.replacement_id,'entry',result,'already_saved',true);
 end if;
 if (original->>'updated_at')::timestamptz is distinct from p_expected_updated then raise exception 'This entry changed. Refresh it before continuing.' using errcode='40001';end if;
 if p_action='resubmit' then
  if p_new_id is null or p_new_id=p_source or jsonb_typeof(p_payload) is distinct from 'object' then raise exception 'A new submission identity and corrected entry are required.' using errcode='22023';end if;
  nextrow:=original||clean||jsonb_build_object('id',p_new_id,'created_at',now(),'updated_at',now(),'rejection_note',null,'reviewed_by',null,'reviewed_at',null,'approved_by',null,'approved_at',null);
  if nextrow->>'date' is null then raise exception 'An entry date is required.' using errcode='22023';end if;
  if (nextrow->>'date')::date>(now() at time zone 'Asia/Kolkata')::date then raise exception 'Future dates are not allowed.' using errcode='22023';end if;
  foreach field in array case p_module when 'cash' then array['expense_amount','amount_received','cash_in_hand'] else array['quantity','rate','sgst','igst','final_amount'] end loop
   number:=coalesce((nextrow->>field)::numeric,0);
   if number::text in ('NaN','Infinity','-Infinity') or (field<>'cash_in_hand' and number<0) then raise exception 'Entry amounts and quantities must be finite and valid.' using errcode='22023';end if;
  end loop;
  if p_module='cash' and ((coalesce((nextrow->>'expense_amount')::numeric,0)>0)=(coalesce((nextrow->>'amount_received')::numeric,0)>0)) then raise exception 'Enter an expense or cash received, not both.' using errcode='22023';end if;
  if p_module='stock' and coalesce((nextrow->>'quantity')::numeric,0)<=0 then raise exception 'Quantity must be positive.' using errcode='22023';end if;
  select settings into strict cfg from public.skcpl_management_state where singleton for share;
  ph:=coalesce((cfg->>('project_head_can_approve_'||p_module))::boolean,true);acc:=coalesce((cfg->>('accounts_can_approve_'||p_module))::boolean,true);
  label:=regexp_replace(coalesce(nextrow->>'remarks',''),'\[(PENDING SUPERVISOR REVIEW|Project Head[^\]]*|Supervisor[^\]]*)\]','','g');
  -- Attribution is retained from the verified original, never supplied by the editor.
  label:=regexp_replace(label,'\[By:[^\]]*\]','','g');
  original_label:=substring(coalesce(original->>'remarks','') from '\[By:\s*([^\]]+)\]');
  if original_label is not null then label:='[By: '||original_label||'] '||label;end if;
  label:=trim(label)||case when ph then ' [Project Head Review: Pending] [Supervisor Review: Pending]' else ' [Project Head Review: Bypassed by Admin Policy]' end;
  nextrow:=nextrow||jsonb_build_object('status',case when not ph and not acc then 'pending_admin' else 'pending_accounts' end,'remarks',trim(label));
  execute format('insert into public.%I select (jsonb_populate_record(null::public.%I,$1)).* returning to_jsonb(%I.*)',tab,tab,tab) into result using nextrow;
 end if;
 insert into public.skcpl_rejected_actions(module,source_id,action,replacement_id,actor_user_id,actor_staff_id,request)
 values(p_module,p_source,p_action,case when p_action='resubmit' then p_new_id end,actor,staff->>'id',clean);
 insert into public.skcpl_rejected_events(module,source_id,action,replacement_id,actor_staff_id) values(p_module,p_source,p_action,case when p_action='resubmit' then p_new_id end,staff->>'id');
 return jsonb_build_object('action',p_action,'source_id',p_source,'replacement_id',p_new_id,'entry',result,'already_saved',false);
end;$$;
revoke all on function public.skcpl_rejected_entry_action(text,uuid,text,uuid,jsonb,text,text,timestamptz) from public;
grant execute on function public.skcpl_rejected_entry_action(text,uuid,text,uuid,jsonb,text,text,timestamptz) to anon,authenticated;
do $$begin
 if exists(select 1 from pg_publication where pubname='supabase_realtime' and not puballtables) then alter publication supabase_realtime add table public.skcpl_rejected_events;end if;
end;$$;
commit;
