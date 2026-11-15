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

Deno.test("Production preflight adds missing Project Head enum/profile using the existing Auth UUID", async () => {
  const db = await database(true);
  try {
    const profile = (await db.query<{ id: string; role: string; is_active: boolean }>(
      "select id,role,is_active from public.users where email='projecthead@skcpl.com'",
    )).rows[0];
    equal(profile.id, ids.head);
    equal(profile.role, "project_head");
    equal(profile.is_active, true);
    const auth = (await db.query<{ count: number }>(
      "select count(*)::int as count from auth.users where id=$1",
      [ids.head],
    )).rows[0];
    equal(auth.count, 1);
  } finally {
    await db.close();
  }
});
