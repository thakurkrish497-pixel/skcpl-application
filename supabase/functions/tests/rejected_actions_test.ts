import { database, equal, ids } from "./test_support.ts";

Deno.test("Rejected cleanup composes with the real financial guard and leaves ordinary approvals intact", async () => {
  const db = await database();
  const rejected = "10000000-0000-4000-8000-000000000001";
  const pending = "10000000-0000-4000-8000-000000000002";
  try {
    await db.exec(`
      alter table public.cash_transactions add column updated_at timestamptz default now();
      create function public.skcpl_attendance_safe_json(value text) returns jsonb
      language plpgsql immutable as $$begin return value::jsonb;exception when others then return null;end;$$;
      alter table public.cash_transactions enable row level security;
      alter table public.stock_transactions enable row level security;
      grant select,insert,update,delete on public.cash_transactions,public.stock_transactions to anon,authenticated;
      create policy fixture_access on public.cash_transactions for all to anon,authenticated using(true) with check(true);
      create policy fixture_access on public.stock_transactions for all to anon,authenticated using(true) with check(true);
      insert into public.cash_transactions(id,site_id,status,expense_amount,remarks,rejection_note)
      values('${rejected}','${ids.site}','rejected',100,'[By: Staff (Worker)]','Wrong bill'),
            ('${pending}','${ids.site}','pending_accounts',125,'[Project Head: Approved by Head]',null);
    `);
    await db.exec(
      await Deno.readTextFile(
        new URL("../../migrations/202611210001_rejected_entry_actions.sql", import.meta.url),
      ),
    );
    const before = (await db.query<{ row: unknown }>(
      "select to_jsonb(t) row from public.cash_transactions t where id=$1",
      [rejected],
    )).rows[0].row;
    const stamp = (await db.query<{ stamp: string }>(
      "select updated_at::text stamp from public.cash_transactions where id=$1",
      [rejected],
    )).rows[0].stamp;
    await db.query("select set_config('request.jwt.claim.sub',$1,false)", [ids.accounts]);
    await db.exec(
      "select set_config('request.jwt.claim.role','authenticated',false);set role authenticated;",
    );
    let denied = false;
    try {
      await db.query(
        "select public.skcpl_rejected_entry_action('cash',$1,'dismiss',p_expected_updated=>$2)",
        [rejected, stamp],
      );
    } catch {
      denied = true;
    }
    equal(denied, true);
    await db.query("update public.cash_transactions set status='pending_admin' where id=$1", [
      pending,
    ]);
    await db.exec("reset role;");
    await db.query("select set_config('request.jwt.claim.sub',$1,false)", [ids.admin]);
    await db.exec("set role authenticated;");
    await db.query(
      "select public.skcpl_rejected_entry_action('cash',$1,'dismiss',p_expected_updated=>$2)",
      [rejected, stamp],
    );
    equal(
      (await db.query("select id from public.cash_transactions where id=$1", [rejected])).rows
        .length,
      0,
    );
    await db.query("update public.cash_transactions set status='approved' where id=$1", [pending]);
    equal(
      (await db.query<{ status: string }>(
        "select status from public.cash_transactions where id=$1",
        [pending],
      )).rows[0].status,
      "approved",
    );
    await db.exec("reset role;");
    equal(
      (await db.query<{ row: unknown }>(
        "select to_jsonb(t) row from public.cash_transactions t where id=$1",
        [rejected],
      )).rows[0].row,
      before,
    );
  } finally {
    await db.close();
  }
});
