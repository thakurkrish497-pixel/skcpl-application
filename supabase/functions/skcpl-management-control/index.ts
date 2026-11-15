import { createControlHandler } from "./control.ts";
import { RestBackend } from "./gateway.ts";
const url = Deno.env.get("SUPABASE_URL");
const key = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
const anon = Deno.env.get("SUPABASE_ANON_KEY");
if (!url || !key || !anon) throw new Error("Management function environment is incomplete.");
Deno.serve(createControlHandler(new RestBackend(url, key, anon)));
