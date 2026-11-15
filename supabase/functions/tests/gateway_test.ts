import { RestBackend } from "../skcpl-management-control/gateway.ts";
import { ControlError } from "../skcpl-management-control/control.ts";
import { equal } from "./test_support.ts";
Deno.test("Gateway verifies caller with public key; Auth admin calls use server secret only", async () => {
  const calls: Request[] = [];
  const backend = new RestBackend(
    "https://fixture.invalid",
    "server-only-secret",
    "public-key",
    (input, init) => {
      const request = new Request(input, init);
      calls.push(request);
      return Promise.resolve(
        new Response(
          JSON.stringify(
            request.url.endsWith("/user")
              ? { id: "verified" }
              : { user: { id: "existing", email: "new@fixture.test", app_metadata: {} } },
          ),
          { status: 200 },
        ),
      );
    },
  );
  await backend.verify("caller-jwt");
  await backend.user("existing");
  await backend.updateUser("existing", { email: "new@fixture.test", password: " New secret " });
  equal(calls[0].headers.get("apikey"), "public-key");
  equal(calls[0].headers.get("Authorization"), "Bearer caller-jwt");
  equal(calls[1].headers.get("apikey"), "server-only-secret");
  equal(calls[1].headers.get("Authorization"), "Bearer server-only-secret");
  equal(calls[2].method, "PUT");
  equal(JSON.parse(await calls[2].text()).password, " New secret ");
});
for (
  const [code, status] of [["40001", 409], ["55P03", 409], ["23505", 409], ["22023", 400], [
    "weak_password",
    400,
  ]]
) {
  Deno.test("Gateway sanitizes backend error " + code, async () => {
    const backend = new RestBackend(
      "https://fixture.invalid",
      "server-secret",
      "public",
      () =>
        Promise.resolve(
          new Response(JSON.stringify({ code, message: "internal sensitive detail" }), {
            status: 400,
          }),
        ),
    );
    try {
      await backend.rpc("fixture");
      throw new Error("Expected failure");
    } catch (error) {
      if (!(error instanceof ControlError)) throw error;
      equal(error.status, status);
      equal(error.message.includes("sensitive"), false);
    }
  });
}
Deno.test("Gateway request fingerprint is stable, keyed and does not contain password", async () => {
  const a = new RestBackend("https://fixture.invalid", "secret-a", "public");
  const b = new RestBackend("https://fixture.invalid", "secret-b", "public");
  const hash = await a.digest("New password");
  equal(hash, await a.digest("New password"));
  equal(hash.length, 64);
  equal(hash === await b.digest("New password"), false);
  equal(hash.includes("password"), false);
});
