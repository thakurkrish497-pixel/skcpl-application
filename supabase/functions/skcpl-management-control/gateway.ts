import { AuthUser, Backend, ControlError } from "./control.ts";
export class RestBackend implements Backend {
  constructor(
    private url: string,
    private key: string,
    private anon: string,
    private transport: typeof fetch = fetch,
  ) {}
  async request(path: string, init: RequestInit = {}, privileged = true) {
    const response = await this.transport(this.url + path, {
      ...init,
      signal: AbortSignal.timeout(12_000),
      headers: {
        apikey: privileged ? this.key : this.anon,
        Authorization: `Bearer ${this.key}`,
        "Content-Type": "application/json",
        ...init.headers,
      },
    });
    const text = await response.text();
    let body;
    try {
      body = text ? JSON.parse(text) : null;
    } catch {
      throw new ControlError(503, "The management server returned an invalid response.");
    }
    if (!response.ok) {
      const code = body?.code;
      if (code === "40001") {
        throw new ControlError(409, "Settings changed on another device. Reload before saving.");
      }
      if (code === "55P03") {
        throw new ControlError(409, "Another save is still running. Please wait and retry.");
      }
      if (code === "23505") {
        throw new ControlError(409, "The selected email or Login ID is already in use.");
      }
      if (response.status === 422 || code === "weak_password") {
        throw new ControlError(
          400,
          "The new password does not meet the company password requirements.",
        );
      }
      if (code === "22023") {
        throw new ControlError(400, "Check the existing role accounts and the supplied settings.");
      }
      throw new ControlError(
        response.status === 401 ? 401 : 503,
        "The server refused the update. Check account configuration or retry.",
      );
    }
    return body;
  }
  verify(jwt: string) {
    return this.request("/auth/v1/user", { headers: { Authorization: `Bearer ${jwt}` } }, false);
  }
  async profile(id: string) {
    const rows = await this.request(
      `/rest/v1/users?id=eq.${encodeURIComponent(id)}&select=role,is_active`,
    );
    if (!Array.isArray(rows) || rows.length !== 1) {
      throw new ControlError(403, "Company profile not found.");
    }
    return rows[0];
  }
  rpc<T>(name: string, args: Record<string, unknown> = {}): Promise<T> {
    return this.request("/rest/v1/rpc/" + name, { method: "POST", body: JSON.stringify(args) });
  }
  async user(id: string): Promise<AuthUser> {
    const data = await this.request("/auth/v1/admin/users/" + encodeURIComponent(id));
    return data.user ?? data;
  }
  async updateUser(id: string, fields: Record<string, unknown>) {
    await this.request("/auth/v1/admin/users/" + encodeURIComponent(id), {
      method: "PUT",
      body: JSON.stringify(fields),
    });
  }
  async digest(value: string) {
    const key = await crypto.subtle.importKey(
      "raw",
      new TextEncoder().encode(this.key),
      { name: "HMAC", hash: "SHA-256" },
      false,
      ["sign"],
    );
    const data = await crypto.subtle.sign("HMAC", key, new TextEncoder().encode(value));
    return [...new Uint8Array(data)].map((v) => v.toString(16).padStart(2, "0")).join("");
  }
}
