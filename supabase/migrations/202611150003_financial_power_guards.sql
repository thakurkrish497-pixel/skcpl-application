-- New writes must obey the current server policy, even from a stale/malicious client.
begin;
create or replace function public.skcpl_pending_head(p_remarks text) returns boolean language sql immutable set search_path='' as $$
 select coalesce(p_remarks,'') ~ '\[(PENDING SUPERVISOR REVIEW|Project Head Review: Pending|Project Head: Review Pending|Supervisor Review: Pending|Supervisor: Review Pending)\]';
$$;
revoke all on function public.skcpl_pending_head(text) from public;
create or replace function public.skcpl_financial_review_guard() returns trigger language plpgsql security definer set search_path='' as $$
declare actor uuid:=auth.uid(); actor_role text; cfg jsonb; module text; ph boolean; acc boolean; pending_head boolean;
begin
 if coalesce(auth.role(),'')='service_role' then
   if tg_op='DELETE' then return old; end if; return new;
 end if;
 if old.status::text='approved' then raise exception 'Approved vouchers are permanently locked.' using errcode='42501'; end if;
 if tg_op='DELETE' then return old; end if;
 if new.id is distinct from old.id or new.site_id is distinct from old.site_id or new.submitted_by is distinct from old.submitted_by then raise exception 'Voucher ownership cannot be changed.' using errcode='42501'; end if;
 module:=case when tg_table_name='cash_transactions' then 'cash' else 'stock' end;
 select settings into strict cfg from public.skcpl_management_state where singleton for share;
 ph:=coalesce((cfg->>('project_head_can_approve_'||module))::boolean,true);
 acc:=coalesce((cfg->>('accounts_can_approve_'||module))::boolean,true);
 pending_head:=public.skcpl_pending_head(old.remarks);
 select role::text into actor_role from public.users where id=actor and is_active=true;
 if actor is not null and actor_role is null then raise exception 'An active profile is required' using errcode='42501'; end if;
 if actor_role in ('accounts','project_head') then perform public.skcpl_require_management_session(); end if;
 if new.status::text='approved' then
   if actor_role is distinct from 'admin' or not(old.status::text='pending_admin' or (old.status::text='pending_accounts' and not acc and (not ph or not pending_head))) then
     raise exception 'Required review checkpoints have not completed.' using errcode='42501'; end if;
   new.approved_by:=actor;new.approved_at:=now();
 elsif new.status::text='pending_admin' and old.status::text='pending_accounts' then
   if not((actor_role='accounts' and acc and (not ph or not pending_head)) or (actor_role='project_head' and ph and not acc)) then
     raise exception 'This review checkpoint is disabled or an earlier review is pending.' using errcode='42501'; end if;
   if actor_role is null then raise exception 'Verified reviewer required' using errcode='42501'; end if;
   new.reviewed_by:=actor;new.reviewed_at:=now();
 elsif new.status::text='rejected' and old.status::text<>'rejected' then
   if length(trim(coalesce(new.rejection_note,'')))=0 then raise exception 'A rejection reason is required' using errcode='22023'; end if;
   if actor_role is null or not(actor_role='admin' or (actor_role='project_head' and ph and old.status::text='pending_accounts') or (actor_role='accounts' and acc and old.status::text='pending_accounts' and (not ph or not pending_head))) then
     raise exception 'Rejection is not permitted at this checkpoint.' using errcode='42501'; end if;
   new.reviewed_by:=actor;new.reviewed_at:=now();
 elsif new.status::text<>old.status::text and not(old.status::text='rejected' and new.status::text='pending_accounts') then
   raise exception 'Invalid voucher status transition.' using errcode='42501';
 else
   if actor_role='project_head' and (not ph or old.status::text<>'pending_accounts') then raise exception 'Project Head review is disabled at this checkpoint.' using errcode='42501'; end if;
   if actor_role='accounts' and (not acc or old.status::text<>'pending_accounts' or (ph and pending_head)) then raise exception 'Accounts review is disabled at this checkpoint.' using errcode='42501'; end if;
   if actor_role is null or actor_role not in ('admin','accounts','project_head') then
     if old.status::text not in ('pending_accounts','rejected') or new.reviewed_by is distinct from old.reviewed_by or new.approved_by is distinct from old.approved_by or
        coalesce(new.remarks,'') ~ '\[(Project Head|Supervisor): (Approved|Edited & Approved|Rejected)' and coalesce(old.remarks,'') !~ '\[(Project Head|Supervisor): (Approved|Edited & Approved|Rejected)' then
       raise exception 'Management review fields cannot be changed by a site submission.' using errcode='42501'; end if;
   end if;
 end if;
 return new;
end $$;
do $$ begin
 if to_regclass('public.cash_transactions') is not null then
   create trigger skcpl_cash_review_guard before update or delete on public.cash_transactions for each row execute function public.skcpl_financial_review_guard();
 end if;
 if to_regclass('public.stock_transactions') is not null then
   create trigger skcpl_stock_review_guard before update or delete on public.stock_transactions for each row execute function public.skcpl_financial_review_guard();
 end if;
end $$;
commit;
