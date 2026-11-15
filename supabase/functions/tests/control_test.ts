import {
  Backend,
  ControlError,
  createControlHandler,
  Role,
  roles,
  Snapshot,
} from "../skcpl-management-control/control.ts";
import { database, equal, ids } from "./test_support.ts";
type Database = Awaited<ReturnType<typeof database>>;
class PgBackend implements Backend {
  actor = ids.admin;
  validToken = true;
  failRole: Role | undefined;
  lostReply: Role | undefined;
  failCommit = false;
  authCalls: string[] = [];
  passwords = new Map([[ids.accounts, "old-account-pass"], [ids.head, "old-head-pass"]]);
  gate: Promise<void> | undefined;
  entered: (() => void) | undefined;
  constructor(public db: Database) {}
  verify(_jwt: string) {
    if (!this.validToken) throw new Error("Invalid JWT");
    return Promise.resolve({ id: this.actor });
  }
  async profile(id: string) {
    return (await this.db.query<{ role: string; is_active: boolean }>(
      "select role,is_active from public.users where id=$1",
      [id],
    )).rows[0];
  }
  async rpc<T>(name: string, args: Record<string, unknown> = {}): Promise<T> {
    if (name === "skcpl_management_finish" && this.failCommit) {
      this.failCommit = false;
      throw new Error("simulated transport loss");
    }
    const keys = Object.keys(args);
    const values = Object.values(args).map((v) =>
      v && typeof v === "object" ? JSON.stringify(v) : v
    );
    try {
      const result = await this.db.query<{ result: T }>(
        `select public.${name}(${keys.map((k, i) => `${k}=>$${i + 1}`).join(",")}) result`,
        values,
      );
      return result.rows[0].result;
    } catch (error) {
      const pg = error as { code?: string; message?: string };
      if (["40001", "55P03", "23505"].includes(pg.code ?? "")) {
        throw new ControlError(409, pg.message ?? "Conflict");
      }
      if (pg.code === "42501") throw new ControlError(403, "Not authorized");
      if (pg.code === "22023") throw new ControlError(400, "Invalid save request");
      throw error;
    }
  }
  async user(id: string) {
    return (await this.db.query<
      { id: string; email: string; app_metadata: Record<string, unknown> }
    >("select * from auth.users where id=$1", [id])).rows[0];
  }
  async updateUser(id: string, fields: Record<string, unknown>) {
    this.authCalls.push(id);
    this.entered?.();
    if (this.gate) await this.gate;
    const role = id === ids.accounts ? "accounts" : "project_head";
    if (this.failRole === role) throw new ControlError(400, "Simulated password-policy rejection");
    await this.db.query("update auth.users set email=$1,app_metadata=$2 where id=$3", [
      fields.email,
      JSON.stringify(fields.app_metadata),
      id,
    ]);
    if (typeof fields.password === "string") this.passwords.set(id, fields.password);
    if (this.lostReply === role) {
      this.lostReply = undefined;
      throw new Error("Response lost after Auth saved");
    }
  }
  async digest(text: string) {
    const bytes = await crypto.subtle.digest(
      "SHA-256",
      new TextEncoder().encode("fixture-secret:" + text),
    );
    return [...new Uint8Array(bytes)].map((v) => v.toString(16).padStart(2, "0")).join("");
  }
  async login(email: string, password: string) {
    const user = (await this.db.query<{ id: string }>(
      "select id from auth.users where lower(email)=lower($1)",
      [email],
    )).rows[0];
    return user && this.passwords.get(user.id) === password ? user.id : null;
  }
}
async function request(backend: PgBackend, body: unknown, token = "fixture-valid-admin") {
  const response = await createControlHandler(backend)(
    new Request("https://fixture.invalid/management", {
      method: "POST",
      headers: { Authorization: "Bearer " + token },
      body: JSON.stringify(body),
    }),
  );
  return { status: response.status, body: await response.json() };
}
async function saveBody(backend: PgBackend, passwords = true) {
  const snapshot = await backend.rpc<Snapshot>("skcpl_management_snapshot");
  const cards = Object.fromEntries(
    roles.map(
      (role) => [role, {
        ...snapshot.roles[role],
        credential_revision: undefined,
        login_id: role === "accounts" ? "finance.team" : "site.operations",
        email: role === "accounts" ? "finance@skcpl.com" : "operations@skcpl.com",
        ...(passwords
          ? { new_password: role === "accounts" ? " New account password " : "New head password" }
          : {}),
      }],
    ),
  );
  return {
    action: "save",
    operation_id: crypto.randomUUID(),
    expected_revision: snapshot.policy.revision,
    roles: cards,
    permissions: Object.fromEntries(
      Object.entries(snapshot.policy).filter(([key]) => key.includes("_can_approve_")),
    ),
  };
}
async function withBackend(test: (backend: PgBackend) => Promise<void>) {
  const db = await database();
  try {
    await test(new PgBackend(db));
  } finally {
    await db.close();
  }
}
async function history(db: Database) {
  return JSON.stringify({
    cash: (await db.query("select * from public.cash_transactions")).rows,
    stock: (await db.query("select * from public.stock_transactions")).rows,
  });
}

Deno.test("Protected save changes real Auth identity fields but preserves UUID, role and all history", () =>
  withBackend(async (b) => {
    const before = await history(b.db);
    const body = await saveBody(b);
    body.permissions.accounts_can_approve_attendance = true;
    body.permissions.project_head_can_approve_stock = false;
    const response = await request(b, body);
    equal(response.status, 200);
    equal(response.body.state, "saved");
    equal(await b.login("finance@skcpl.com", " New account password "), ids.accounts);
    equal(await b.login("accounts@skcpl.com", "old-account-pass"), null);
    equal(
      await b.rpc("skcpl_resolve_management_login", { p_login: "finance.team" }),
      "finance@skcpl.com",
    );
    equal(await b.rpc("skcpl_resolve_management_login", { p_login: "accounts" }), null);
    equal((await b.profile(ids.accounts)).role, "accounts");
    equal((await b.profile(ids.head)).role, "project_head");
    equal(await history(b.db), before);
    const policy = await b.rpc<Record<string, unknown>>("skcpl_management_policy");
    equal(policy.accounts_can_approve_attendance, true);
    equal(policy.project_head_can_approve_stock, false);
    const rows =
      (await b.db.query<{ description: string }>("select description from public.tasks")).rows;
    equal(rows.some((r) => r.description.includes("New account password")), false);
    const ops = await b.db.query("select plan,result from public.skcpl_management_operations");
    equal(JSON.stringify(ops.rows).includes("New account password"), false);
  }));
Deno.test("Same Save token replay does not reset passwords twice or increment revision again", () =>
  withBackend(async (b) => {
    const body = await saveBody(b);
    equal((await request(b, body)).status, 200);
    equal((await request(b, body)).status, 200);
    equal(b.authCalls.length, 2);
    const cfg = await b.rpc<Snapshot>("skcpl_management_snapshot");
    equal(cfg.policy.revision, 1);
  }));
Deno.test("Partial Auth failure is explicit and same request resumes only the remaining role", () =>
  withBackend(async (b) => {
    const body = await saveBody(b);
    b.failRole = "project_head";
    let response = await request(b, body);
    equal(response.status, 207);
    equal(response.body.state, "partial");
    equal(response.body.credentials_updated, ["accounts"]);
    equal((await b.rpc<Snapshot>("skcpl_management_snapshot")).policy.revision, 0);
    equal(
      await b.rpc("skcpl_resolve_management_login", { p_login: "accounts" }),
      "finance@skcpl.com",
    );
    b.failRole = undefined;
    response = await request(b, body);
    equal(response.status, 200);
    equal(b.authCalls.filter((id) => id === ids.accounts).length, 1);
  }));
Deno.test("Lost Auth reply for email-only edit reconciles server metadata without a second update", () =>
  withBackend(async (b) => {
    const body = await saveBody(b, false);
    b.lostReply = "accounts";
    let response = await request(b, body);
    equal(response.status, 207);
    equal(response.body.credentials_update_uncertain, "accounts");
    response = await request(b, body);
    equal(response.status, 200);
    equal(b.authCalls.filter((id) => id === ids.accounts).length, 1);
    equal(await b.login("finance@skcpl.com", "old-account-pass"), ids.accounts);
  }));
Deno.test("Database finish failure never reports success and can resume without repeating Auth updates", () =>
  withBackend(async (b) => {
    b.failCommit = true;
    const body = await saveBody(b);
    equal((await request(b, body)).status, 207);
    equal((await b.rpc<Snapshot>("skcpl_management_snapshot")).policy.revision, 0);
    equal((await request(b, body)).status, 200);
    equal(b.authCalls.length, 2);
  }));
Deno.test("Concurrent Admin save is rejected while the first request holds its lease", () =>
  withBackend(async (b) => {
    let release!: () => void;
    let entered!: () => void;
    const reached = new Promise<void>((r) => entered = r);
    b.gate = new Promise<void>((r) => release = r);
    b.entered = entered;
    const first = await saveBody(b);
    const second = await saveBody(b);
    const pending = request(b, first);
    await reached;
    const other = await request(b, second);
    equal(other.status, 409);
    release();
    equal((await pending).status, 200);
  }));
Deno.test("A stale expected revision cannot overwrite a later Admin save", () =>
  withBackend(async (b) => {
    const first = await saveBody(b);
    const stale = await saveBody(b);
    equal((await request(b, first)).status, 200);
    equal((await request(b, stale)).status, 409);
    equal(b.authCalls.length, 2);
  }));
Deno.test("Powers-only save keeps passwords and credential revisions unchanged", () =>
  withBackend(async (b) => {
    const snap = await b.rpc<Snapshot>("skcpl_management_snapshot");
    const body = await saveBody(b, false);
    for (const role of roles) {
      body.roles[role].email = snap.roles[role].email;
      body.roles[role].login_id = snap.roles[role].login_id;
    }
    body.permissions.accounts_can_approve_dsr = true;
    equal((await request(b, body)).status, 200);
    equal(b.authCalls.length, 0);
    const policy = await b.rpc<Snapshot>("skcpl_management_snapshot");
    equal(policy.roles.accounts.credential_revision, 0);
    equal(await b.login("accounts@skcpl.com", "old-account-pass"), ids.accounts);
  }));
for (
  const attack of [
    "non-admin",
    "inactive-admin",
    "bad-jwt",
    "target-swap",
    "role-escalation",
    "duplicate-email",
    "duplicate-login",
    "reserved-id",
    "weak-password",
    "reused-token",
  ]
) {
  Deno.test("Reject management attack: " + attack, () =>
    withBackend(async (b) => {
      const body = await saveBody(b);
      let expected = 400;
      switch (attack) {
        case "non-admin":
          b.actor = ids.accounts;
          expected = 403;
          break;
        case "inactive-admin":
          await b.db.query("update public.users set is_active=false where id=$1", [ids.admin]);
          expected = 403;
          break;
        case "bad-jwt":
          b.validToken = false;
          expected = 401;
          break;
        case "target-swap":
          body.roles.accounts.user_id = ids.admin;
          expected = 403;
          break;
        case "role-escalation":
          (body.roles.accounts as unknown as Record<string, unknown>).role = "admin";
          break;
        case "duplicate-email":
          body.roles.accounts.email = "admin@skcpl.com";
          expected = 409;
          break;
        case "duplicate-login":
          body.roles.project_head.login_id = body.roles.accounts.login_id;
          break;
        case "reserved-id":
          body.roles.accounts.login_id = "ADMIN";
          break;
        case "weak-password":
          body.roles.accounts.new_password = "123456";
          break;
        case "reused-token": {
          const done = await saveBody(b);
          await request(b, done);
          body.operation_id = done.operation_id;
          body.roles.accounts.new_password = "Different secret value";
          expected = 400;
          break;
        }
      }
      const before = b.authCalls.length;
      const result = await request(b, body);
      equal(result.status, expected);
      equal(b.authCalls.length, before);
    }));
}
