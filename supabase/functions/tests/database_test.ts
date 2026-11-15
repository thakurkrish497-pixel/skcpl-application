import { database, equal, ids } from "./test_support.ts";
Deno.test("Local migration creates nonsecret management state and preserves existing records", async () => {
  const db = await database();
  try {
    const result = await db.query<{ policy: Record<string, unknown> }>(
      "select public.skcpl_management_policy() policy",
    );
    equal(result.rows[0].policy.accounts_can_approve_attendance, false);
    equal(result.rows[0].policy.project_head_can_approve_dsr, true);
    equal((await db.query("select * from cash_transactions")).rows.length, 1);
    equal((await db.query("select * from stock_transactions")).rows.length, 1);
    const snapshot = await db.query<{ value: Record<string, unknown> }>(
      "select public.skcpl_management_snapshot() value",
    );
    equal(
      (snapshot.rows[0].value.roles as Record<string, { user_id: string }>).accounts.user_id,
      ids.accounts,
    );
  } finally {
    await db.close();
  }
});
