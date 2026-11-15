export const roles = ["accounts", "project_head"] as const;
export type Role = typeof roles[number];
export const powerKeys = roles.flatMap((r) =>
  ["cash", "stock", "attendance", "dsr"].map((m) => `${r}_can_approve_${m}`)
);
export type Card = {
  user_id: string;
  login_id: string;
  email: string;
  credential_revision: number;
};
export type Snapshot = {
  policy: Record<string, unknown> & { revision: number };
  roles: Record<Role, Card>;
};
export type AuthUser = { id: string; email: string; app_metadata: Record<string, unknown> };
export interface Backend {
  verify(jwt: string): Promise<{ id: string }>;
  profile(id: string): Promise<{ role: string; is_active: boolean }>;
  rpc<T>(name: string, args?: Record<string, unknown>): Promise<T>;
  user(id: string): Promise<AuthUser>;
  updateUser(id: string, fields: Record<string, unknown>): Promise<void>;
  digest(value: string): Promise<string>;
}
export class ControlError extends Error {
  constructor(public status: number, message: string) {
    super(message);
  }
}
const uuid = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
function object(value: unknown, fields: string[], context: string): Record<string, unknown> {
  if (
    !value || typeof value !== "object" || Array.isArray(value) ||
    Object.keys(value).some((k) => !fields.includes(k))
  ) {
    throw new ControlError(400, `Invalid ${context}.`);
  }
  return value as Record<string, unknown>;
}
export function validateSave(raw: unknown, snapshot: Snapshot) {
  const body = object(
    raw,
    ["action", "operation_id", "expected_revision", "roles", "permissions"],
    "save request",
  );
  if (
    !uuid.test(String(body.operation_id)) || !Number.isSafeInteger(body.expected_revision) ||
    Number(body.expected_revision) < 0
  ) throw new ControlError(400, "Invalid save revision or request token.");
  const cards = object(body.roles, [...roles], "role accounts");
  const permissions = object(body.permissions, powerKeys, "approval permissions");
  if (powerKeys.some((k) => typeof permissions[k] !== "boolean")) {
    throw new ControlError(400, "All eight approval powers must be specified.");
  }
  const normalized = {} as Record<
    Role,
    Card & { new_password?: string; credentials_changed: boolean }
  >;
  for (const role of roles) {
    const card = object(cards[role], ["user_id", "login_id", "email", "new_password"], role);
    const current = snapshot.roles[role];
    if (card.user_id !== current.user_id) {
      throw new ControlError(
        403,
        "Existing role account identity cannot be changed. Reload settings.",
      );
    }
    const login = String(card.login_id ?? "").trim().toLowerCase();
    const email = String(card.email ?? "").trim().toLowerCase();
    if (!/^[a-z0-9][a-z0-9._-]{2,63}$/.test(login) || ["admin", "administrator"].includes(login)) {
      throw new ControlError(
        400,
        "Use a unique Login ID of 3–64 letters, numbers, dots, dashes or underscores. Admin IDs are reserved.",
      );
    }
    if (email.length > 254 || !/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(email)) {
      throw new ControlError(400, "Enter a valid email address.");
    }
    const password = card.new_password;
    if (
      password !== undefined &&
      (typeof password !== "string" || !password.trim() || [...password].length < 8 ||
        new TextEncoder().encode(password).length > 72)
    ) {
      throw new ControlError(
        400,
        "New passwords require at least 8 characters and at most 72 UTF-8 bytes. Leave blank to keep the current password.",
      );
    }
    normalized[role] = {
      user_id: current.user_id,
      login_id: login,
      email,
      credential_revision: current.credential_revision,
      ...(password === undefined ? {} : { new_password: password as string }),
      credentials_changed: password !== undefined || login !== current.login_id ||
        email !== String(snapshot.policy[role + "_email"] ?? current.email).toLowerCase(),
    };
  }
  if (
    normalized.accounts.login_id === normalized.project_head.login_id ||
    normalized.accounts.email === normalized.project_head.email
  ) throw new ControlError(400, "Accounts and Project Head need different Login IDs and emails.");
  return {
    operation: String(body.operation_id),
    revision: Number(body.expected_revision),
    cards: normalized,
    permissions,
  };
}

export function createControlHandler(backend: Backend) {
  const headers = {
    "Content-Type": "application/json",
    "Access-Control-Allow-Origin": "*",
    "Access-Control-Allow-Headers": "authorization,apikey,content-type,x-client-info",
    "Access-Control-Allow-Methods": "POST,OPTIONS",
    "Cache-Control": "no-store",
  };
  const reply = (body: unknown, status = 200) =>
    new Response(JSON.stringify(body), { status, headers });
  return async (request: Request): Promise<Response> => {
    if (request.method === "OPTIONS") return new Response(null, { status: 204, headers });
    if (request.method !== "POST") return reply({ error: "Use POST." }, 405);
    let operation: string | undefined;
    const owner = crypto.randomUUID();
    const applied: Role[] = [];
    let claimed = false;
    let uncertainRole: Role | undefined;
    try {
      const token = request.headers.get("Authorization")?.match(/^Bearer (.+)$/i)?.[1];
      if (!token) throw new ControlError(401, "Admin sign-in is required.");
      let actor: { id: string };
      try {
        actor = await backend.verify(token);
      } catch {
        throw new ControlError(401, "Your session expired. Sign in again.");
      }
      const profile = await backend.profile(actor.id);
      if (profile.role !== "admin" || !profile.is_active) {
        throw new ControlError(
          403,
          "Only active Admin accounts may manage role logins and powers.",
        );
      }
      const text = await request.text();
      if (new TextEncoder().encode(text).length > 16_384) {
        throw new ControlError(413, "Settings request is too large.");
      }
      let body: Record<string, unknown>;
      try {
        body = JSON.parse(text);
      } catch {
        throw new ControlError(400, "Invalid request body.");
      }
      const snapshot = await backend.rpc<Snapshot>("skcpl_management_snapshot");
      if (body.action === "snapshot") return reply({ state: "ready", snapshot });
      if (body.action !== "save") throw new ControlError(400, "Unknown management action.");
      // Existing completed requests are checked by the database before revision checks.
      const save = validateSave(body, snapshot);
      operation = save.operation;
      const plan = {
        roles: Object.fromEntries(roles.map((role) => {
          const { new_password: _password, ...card } = save.cards[role];
          return [role, card];
        })),
        permissions: save.permissions,
      };
      const hash = await backend.digest(JSON.stringify(body));
      const start = await backend.rpc<
        { complete: boolean; result?: Snapshot; auth_applied?: Role[] }
      >("skcpl_management_begin", {
        p_operation: operation,
        p_owner: owner,
        p_actor: actor.id,
        p_hash: hash,
        p_revision: save.revision,
        p_plan: plan,
      });
      if (start.complete) {
        return reply({ state: "saved", snapshot: start.result, operation_id: operation });
      }
      claimed = true;
      applied.push(...(start.auth_applied ?? []));
      for (const role of roles) {
        const card = save.cards[role];
        if (!card.credentials_changed || applied.includes(role)) continue;
        const current = await backend.user(card.user_id);
        if (current.id !== card.user_id) {
          throw new ControlError(409, "Role account identity changed. Reload settings.");
        }
        // Reconcile a lost response using server-controlled Auth metadata, not a second password reset.
        if (current.app_metadata?.skcpl_management_operation !== operation) {
          uncertainRole = role;
          await backend.updateUser(card.user_id, {
            email: card.email,
            email_confirm: true,
            ...(card.new_password === undefined ? {} : { password: card.new_password }),
            app_metadata: {
              ...current.app_metadata,
              skcpl_management_operation: operation,
              skcpl_credential_revision: card.credential_revision + 1,
            },
          });
        }
        applied.push(role);
        uncertainRole = undefined;
        await backend.rpc("skcpl_management_progress", {
          p_operation: operation,
          p_owner: owner,
          p_role: role,
        });
      }
      const committed = await backend.rpc<Snapshot>("skcpl_management_finish", {
        p_operation: operation,
        p_owner: owner,
      });
      return reply({ state: "saved", snapshot: committed, operation_id: operation });
    } catch (error) {
      if (claimed && operation) {
        try {
          await backend.rpc("skcpl_management_abort", { p_operation: operation, p_owner: owner });
        } catch { /* Lease expires; never report success. */ }
      }
      const message = error instanceof ControlError
        ? error.message
        : "The server could not complete this save. Retry with the same form; your existing accounts and entries are retained.";
      if (applied.length || uncertainRole) {
        return reply({
          state: "partial",
          operation_id: operation,
          credentials_updated: applied,
          ...(uncertainRole ? { credentials_update_uncertain: uncertainRole } : {}),
          error: `${applied.length ? "Credentials updated for " + applied.join(", ") + ". " : ""}${
            uncertainRole
              ? "A credential update may already have completed; retry the same Save to confirm it. "
              : ""
          }Approval settings are not confirmed saved. ${message}`,
        }, 207);
      }
      return reply(
        { state: "error", error: message },
        error instanceof ControlError ? error.status : 503,
      );
    }
  };
}
