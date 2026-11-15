import { database, equal, ids } from "./test_support.ts";
type DB = Awaited<ReturnType<typeof database>>;
async function actor(db: DB, id: string, version = 0) {
  await db.query(
    "select set_config('request.jwt.claim.sub',$1,false),set_config('request.jwt.claim.role','authenticated',false),set_config('request.jwt.claims',$2,false)",
    [id, JSON.stringify({ app_metadata: { skcpl_credential_revision: version } })],
  );
}
async function setting(db: DB, key: string, value: unknown) {
  await db.query(
    "update public.skcpl_management_state set settings=jsonb_set(settings,array[$1],$2::jsonb)",
    [key, JSON.stringify(value)],
  );
}
async function insert(db: DB, module: string) {
  const id = crypto.randomUUID();
  if (module === "attendance") {
    await db.query(
      "insert into attendance(id,site_id,status,staff_name,date)values($1,$2,'regularizationPending','Fixture employee',current_date)",
      [id, ids.site],
    );
  } else {await db.query(
      "insert into daily_site_reports(id,site_id,notes,date)values($1,$2,'Work completed',current_date)",
      [id, ids.site],
    );}
  return id;
}
async function queue(db: DB, module: string) {
  return (await db.query<
    {
      entry_id: string;
      data: Record<string, unknown>;
      review_revision: number;
      source_version: string;
    }
  >("select * from public.skcpl_review_queue($1,$2)", [module, "all"])).rows;
}
async function review(db: DB, module: string, id: string, approve = true, note = "Checked") {
  const entry = (await queue(db, module)).find((r) => r.entry_id === id);
  if (!entry) throw new Error("No eligible review");
  return (await db.query<{ result: Record<string, unknown> }>(
    "select public.skcpl_review_entry($1,$2,$3,$4,false,$5,$6) result",
    [module, id, approve, note, entry.review_revision, entry.source_version],
  )).rows[0].result;
}
async function rejects(fn: () => Promise<unknown>, code: string) {
  try {
    await fn();
  } catch (error) {
    equal((error as { code: string }).code, code);
    return;
  }
  throw new Error("Expected rejection " + code);
}
async function withDb(test: (db: DB) => Promise<void>) {
  const db = await database();
  try {
    await test(db);
  } finally {
    await db.close();
  }
}
for (const module of ["attendance", "dsr"]) {
  Deno.test(`${module}: Worker → Project Head → Accounts → Admin; only Admin finalizes`, () =>
    withDb(async (db) => {
      await setting(db, "accounts_can_approve_" + module, true);
      const id = await insert(db, module);
      await actor(db, ids.accounts);
      equal((await queue(db, module)).length, 0);
      await actor(db, ids.admin);
      equal((await queue(db, module)).length, 0);
      await actor(db, ids.head);
      await review(db, module, id);
      if (module === "attendance") {
        equal(
          (await db.query<{ status: string }>("select status from attendance where id=$1", [id]))
            .rows[0].status,
          "regularizationPending",
        );
      }
      await actor(db, ids.accounts);
      await review(db, module, id);
      if (module === "attendance") {
        equal(
          (await db.query<{ status: string }>("select status from attendance where id=$1", [id]))
            .rows[0].status,
          "regularizationPending",
        );
      }
      await actor(db, ids.admin);
      await review(db, module, id);
      const ledger =
        (await db.query<{ state: { final: { reviewed_by: string; decision: string } } }>(
          "select state from skcpl_entry_reviews where module=$1 and entry_id=$2",
          [module, id],
        )).rows[0];
      equal(ledger.state.final.reviewed_by, ids.admin);
      equal(ledger.state.final.decision, "approved");
      equal((await queue(db, module)).length, 0);
      await setting(db, "accounts_can_approve_" + module, false);
      equal((await queue(db, module)).length, 0);
    }));
  Deno.test(`${module}: disabled checkpoints immediately bypass to Admin without rewriting data`, () =>
    withDb(async (db) => {
      const id = await insert(db, module);
      await setting(db, "project_head_can_approve_" + module, false);
      await setting(db, "accounts_can_approve_" + module, false);
      await actor(db, ids.head);
      equal((await queue(db, module)).length, 0);
      await actor(db, ids.accounts);
      equal((await queue(db, module)).length, 0);
      await actor(db, ids.admin);
      equal((await queue(db, module))[0].entry_id, id);
      await review(db, module, id);
    }));
  Deno.test(`${module}: rejection needs a reason and records the actual reviewer`, () =>
    withDb(async (db) => {
      const id = await insert(db, module);
      await actor(db, ids.head);
      const entry = (await queue(db, module))[0];
      await rejects(
        () =>
          db.query("select public.skcpl_review_entry($1,$2,false,'',false,$3,$4)", [
            module,
            id,
            entry.review_revision,
            entry.source_version,
          ]),
        "22023",
      );
      await review(db, module, id, false, "Missing details");
      const result = (await db.query<{ state: { final: { reviewed_by: string; note: string } } }>(
        "select state from skcpl_entry_reviews where module=$1 and entry_id=$2",
        [module, id],
      )).rows[0];
      equal(result.state.final.reviewed_by, ids.head);
      equal(result.state.final.note, "Missing details");
      await actor(db, ids.admin);
      equal((await queue(db, module)).length, 0);
    }));
  Deno.test(`${module}: stale source and double review cannot approve changed entries`, () =>
    withDb(async (db) => {
      const id = await insert(db, module);
      await actor(db, ids.head);
      const entry = (await queue(db, module))[0];
      const table = module === "attendance" ? "attendance" : "daily_site_reports";
      await db.query(`update ${table} set updated_at=now()+interval '1 second' where id=$1`, [id]);
      await rejects(
        () =>
          db.query("select public.skcpl_review_entry($1,$2,true,'Checked',false,$3,$4)", [
            module,
            id,
            entry.review_revision,
            entry.source_version,
          ]),
        "40001",
      );
      await review(db, module, id);
      await rejects(
        () =>
          db.query("select public.skcpl_review_entry($1,$2,true,'Checked',false,$3,$4)", [
            module,
            id,
            entry.review_revision,
            entry.source_version,
          ]),
        "40001",
      );
    }));
}
Deno.test("Server rejects a stale credential-version token after Admin changes login", () =>
  withDb(async (db) => {
    await setting(db, "project_head_credential_revision", 1);
    await actor(db, ids.head, 0);
    await rejects(() => queue(db, "dsr"), "42501");
    await actor(db, ids.head, 1);
    equal((await queue(db, "dsr")).length, 0);
  }));
Deno.test("Attendance cannot be finalized by a stale legacy client before required reviews", () =>
  withDb(async (db) => {
    const id = await insert(db, "attendance");
    await actor(db, ids.head);
    await rejects(
      () => db.query("update attendance set status='regularizedPresent' where id=$1", [id]),
      "42501",
    );
  }));
for (const module of ["cash", "stock"]) {
  Deno.test(`${module}: revoked Accounts power is enforced on the server; pending voucher can bypass safely`, () =>
    withDb(async (db) => {
      const table = module === "cash" ? "cash_transactions" : "stock_transactions";
      const amount = module === "cash" ? "expense_amount" : "quantity";
      const id = crypto.randomUUID();
      await db.query(
        `insert into ${table}(id,submitted_by,status,${amount},site_id)values($1,$2,'pending_accounts',100,$3)`,
        [id, ids.head, ids.site],
      );
      await setting(db, "project_head_can_approve_" + module, false);
      await setting(db, "accounts_can_approve_" + module, false);
      await actor(db, ids.accounts);
      await rejects(
        () => db.query(`update ${table} set status='pending_admin' where id=$1`, [id]),
        "42501",
      );
      await actor(db, ids.admin);
      await db.query(`update ${table} set status='approved',approved_by=$2 where id=$1`, [
        id,
        ids.head,
      ]);
      equal(
        (await db.query<{ approved_by: string }>(`select approved_by from ${table} where id=$1`, [
          id,
        ])).rows[0].approved_by,
        ids.admin,
      );
      await rejects(() => db.query(`update ${table} set ${amount}=999 where id=$1`, [id]), "42501");
      await rejects(() => db.query(`delete from ${table} where id=$1`, [id]), "42501");
    }));
}
Deno.test("Employees cannot directly read the operation journal or write the central policy", () =>
  withDb(async (db) => {
    await db.exec("set role authenticated");
    try {
      await rejects(() => db.query("select * from public.skcpl_management_operations"), "42501");
      await rejects(
        () => db.query("update public.skcpl_management_state set settings='{}'"),
        "42501",
      );
      await rejects(() => db.query("select public.skcpl_management_snapshot()"), "42501");
    } finally {
      await db.exec("reset role");
    }
  }));
Deno.test("Compatibility config cannot be forged through the general tasks API", () =>
  withDb(async (db) => {
    await actor(db, ids.accounts);
    await rejects(
      () =>
        db.query(
          "insert into tasks(site_id,created_by,title,description,status,priority)values($1,$2,'CONFIG:ROLE_PERMISSIONS','{}','completed','high')",
          [ids.site, ids.accounts],
        ),
      "42501",
    );
  }));

Deno.test("DSR approval tags cannot be forged by direct updates or new submissions", () =>
  withDb(async (db) => {
    const id = await insert(db, "dsr");
    await actor(db, ids.accounts);
    await rejects(
      () =>
        db.query(
          "update daily_site_reports set remarks='[Admin: Approved by forged]' where id=$1",
          [id],
        ),
      "42501",
    );
    await rejects(
      () =>
        db.query(
          "insert into daily_site_reports(id,site_id,remarks)values($1,$2,'[Project Head: Approved by forged]')",
          [crypto.randomUUID(), ids.site],
        ),
      "42501",
    );
  }));
Deno.test("Fallback attendance and DSR records use protected review actions too", () =>
  withDb(async (db) => {
    for (const module of ["attendance", "dsr"]) {
      const id = crypto.randomUUID();
      const doc = {
        id,
        site_id: ids.site,
        status: "regularizationPending",
        remarks: "",
        date: "2026-11-15",
      };
      await db.query("insert into tasks(id,site_id,title,description)values($1,$2,$3,$4)", [
        id,
        ids.site,
        (module === "dsr" ? "DSR:" : "ATTENDANCE:") + id,
        JSON.stringify(doc),
      ]);
      await actor(db, ids.head);
      const forged = module === "dsr"
        ? { ...doc, remarks: "[Project Head: Approved by forged]" }
        : { ...doc, status: "regularizedPresent" };
      await rejects(
        () => db.query("update tasks set description=$1 where id=$2", [JSON.stringify(forged), id]),
        "42501",
      );
      await review(db, module, id);
      await actor(db, ids.admin);
      await review(db, module, id);
    }
  }));

Deno.test("Authenticated site submissions still write ordinary DSR and fallback attendance", () =>
  withDb(async (db) => {
    await db.exec(
      "grant insert,update,select on public.tasks,public.daily_site_reports to authenticated",
    );
    await actor(db, ids.head);
    await db.exec("set role authenticated");
    try {
      await db.query(
        "insert into daily_site_reports(id,site_id,notes)values($1,$2,'Concrete work')",
        [crypto.randomUUID(), ids.site],
      );
      for (const prefix of ["DSR:", "ATTENDANCE:"]) {
        const id = crypto.randomUUID();
        const doc = {
          id,
          site_id: ids.site,
          status: "regularizationPending",
          notes: "Ordinary submission",
        };
        await db.query("insert into tasks(id,site_id,title,description)values($1,$2,$3,$4)", [
          id,
          ids.site,
          prefix + id,
          JSON.stringify(doc),
        ]);
        await db.query("update tasks set description=$1 where id=$2", [
          JSON.stringify({ ...doc, notes: "Corrected note" }),
          id,
        ]);
      }
    } finally {
      await db.exec("reset role");
    }
  }));
