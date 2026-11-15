import { PGlite } from "@electric-sql/pglite";
export const ids = {
  admin: "00000000-0000-4000-8000-000000000001",
  accounts: "00000000-0000-4000-8000-000000000002",
  head: "00000000-0000-4000-8000-000000000003",
  site: "00000000-0000-4000-8000-000000000004",
};
export async function database() {
  const db = new PGlite();
  await db.exec(`create role anon;create role authenticated;create role service_role bypassrls;
 create schema auth;
 create table auth.users(id uuid primary key,email text unique,app_metadata jsonb default '{}');
 create function auth.uid() returns uuid language sql stable as $$select nullif(current_setting('request.jwt.claim.sub',true),'')::uuid$$;
 create function auth.jwt() returns jsonb language sql stable as $$select coalesce(nullif(current_setting('request.jwt.claims',true),'')::jsonb,'{}'::jsonb)$$;
 create function auth.role() returns text language sql stable as $$select current_setting('request.jwt.claim.role',true)$$;
 grant usage on schema public,auth to anon,authenticated,service_role;
 create type public.user_role as enum ('admin','accounts','project_head','worker');
 create type public.transaction_status as enum ('pending_accounts','pending_admin','approved','rejected');
 create table public.users(id uuid primary key,email text unique,role public.user_role,is_active boolean default true);
 create table public.sites(id uuid primary key);
 create table public.tasks(id uuid primary key default gen_random_uuid(),site_id uuid references public.sites,created_by uuid references public.users,title text,description text,status text,priority text,updated_at timestamptz default now());
 create table public.cash_transactions(id uuid primary key,submitted_by uuid,approved_by uuid,status public.transaction_status,expense_amount numeric,site_id uuid default gen_random_uuid(),remarks text,rejection_note text,reviewed_by uuid,approved_at timestamptz,reviewed_at timestamptz);
 create table public.stock_transactions(id uuid primary key,submitted_by uuid,approved_by uuid,status public.transaction_status,quantity numeric,site_id uuid default gen_random_uuid(),remarks text,rejection_note text,reviewed_by uuid,approved_at timestamptz,reviewed_at timestamptz);
 create table public.attendance(id uuid primary key,site_id uuid,status text,admin_decision_note text,reviewed_by uuid,staff_name text,date date,updated_at timestamptz default now());
 create table public.daily_site_reports(id uuid primary key,site_id uuid,remarks text,notes text,date date,updated_at timestamptz default now());
 grant select on public.users to authenticated;
 insert into public.users values('${ids.admin}','admin@skcpl.com','admin',true),('${ids.accounts}','accounts@skcpl.com','accounts',true),('${ids.head}','projecthead@skcpl.com','project_head',true);
 insert into auth.users(id,email) select id,email from public.users;
 insert into public.sites values('${ids.site}');
 insert into public.cash_transactions(id,submitted_by,approved_by,status,expense_amount) values(gen_random_uuid(),'${ids.accounts}','${ids.admin}','approved',150);
 insert into public.stock_transactions(id,submitted_by,approved_by,status,quantity) values(gen_random_uuid(),'${ids.head}','${ids.admin}','approved',30);`);
  const migrations = new URL("../../migrations/", import.meta.url);
  await db.exec(await Deno.readTextFile(new URL("202611150001_admin_management.sql", migrations)));
  await db.exec(
    await Deno.readTextFile(new URL("202611150002_management_reviews.sql", migrations)),
  );
  await db.exec(
    await Deno.readTextFile(new URL("202611150003_financial_power_guards.sql", migrations)),
  );
  return db;
}
export function equal(actual: unknown, expected: unknown) {
  if (JSON.stringify(actual) !== JSON.stringify(expected)) {
    throw new Error(`Expected ${JSON.stringify(expected)}; received ${JSON.stringify(actual)}`);
  }
}
