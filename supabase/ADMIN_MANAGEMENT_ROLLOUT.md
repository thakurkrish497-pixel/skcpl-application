# Admin login and approval controls — local rollout notes

Implementation is local. No production migration, credential update, deployment, Git commit/push or release publication was performed for this feature.

## App behavior

Admin → Role & Access Management now edits Accounts and Project Head independently: Login ID, Auth email, optional new password, and Cash/Stock/Attendance/DSR approval powers. A blank password keeps the existing password. New passwords require at least eight Unicode characters and no more than 72 UTF-8 bytes. Existing six-character passwords remain usable until changed.

Save disables editing and navigation while the protected server acknowledges the request. A confirmed save shows a success message. A partial credential save is explicitly reported and can be retried with the same operation token. Concurrent or stale Admin saves are rejected rather than overwriting each other.

Accounts and Project Head retain their existing Supabase Auth/public.users UUIDs and roles. Login changes never rewrite submitted_by, reviewed_by, approved_by or operational history. Passwords are not returned to the app, stored in settings/cache/audit tables, or logged. The privileged Auth key is read only from the Edge Function environment.

Cash/Stock use enabled Project Head → Accounts → Admin checkpoints. Switching Accounts OFF makes eligible existing pending_accounts vouchers available to Admin without migrating their IDs/statuses. Attendance/DSR use a server-verified review ledger; only final Admin approval finalizes an attendance regularization. Rejections require a reason. Accounts Attendance/DSR defaults OFF to preserve the existing workflow. Previously finalized records remain finalized when powers change.

Policy changes are enforced by server checks on new review writes. Connected updated apps refresh using Postgres events, reconnect refresh and a 30-second fallback poll. Offline devices cannot receive changes until they reconnect. Updated Accounts/Project Head clients ask for sign-in again after a credential revision changes, preserving offline queues and drafts. This is an application reauthentication mechanism, not a claim that every historical Supabase refresh token has been globally revoked.

## Controlled deployment still required

1. Validate the additive migrations in a staging copy of the actual deployed schema and RLS policies. Local tests cover PostgreSQL enums, new tables, functions, triggers, permission checks, ordinary site writes, primary and tasks-backed records. They do not reproduce every pre-existing production policy or custom trigger.
2. Apply only `202611150001_admin_management.sql`, `202611150002_management_reviews.sql`, and `202611150003_financial_power_guards.sql` in order. They add central state, an operation journal/review ledger and review guards; they do not drop or truncate operational tables. Existing accounts are bound by configured email or a single active role identity; ambiguous/missing bindings fail clearly and must be resolved before use.
3. Deploy `skcpl-management-control`. Its `verify_jwt=false` setting is intentional: the handler verifies the caller using Supabase Auth and then independently checks an active Admin profile before any snapshot/save. Ensure `SUPABASE_URL`, `SUPABASE_ANON_KEY` and `SUPABASE_SERVICE_ROLE_KEY` are available only in the function environment. Do not put the service key in Flutter build flags or website files.
4. Install updated Android, Windows and macOS builds on management devices in coordination with backend activation. Old apps have hardcoded Login ID aliases and legacy review actions. Custom IDs require the updated app; old review actions are intentionally refused by the new guards. Confirm the existing mobile signing identities are retained for installable updates.
5. On staging, test both roles on separate devices: change IDs/emails/passwords, sign in again, toggle every power, verify old credential rejection, interrupt a save and retry, and confirm a pre-existing offline queue/draft still submits under its unchanged account ID. Only then perform a scheduled production rollout.

Until deployment, the new Admin form reports that the secure backend is unavailable. It does not falsely save credentials into local settings. Ordinary legacy login/workflow behavior falls back only when the new RPC is absent, never for a permission rejection.

## Repeatable local verification

From the app root:

```sh
flutter analyze
flutter test --reporter expanded
python3 -m unittest discover -s scripts -p 'test_release*.py'
deno task --config supabase/functions/deno.json check
deno task --config supabase/functions/deno.json lint
deno task --config supabase/functions/deno.json test
```

Backend tests use an in-memory PostgreSQL engine (PGlite 0.5.16) and mocked Supabase Auth/HTTP; no production URL or credentials are used. The test task grants local file/environment access for the engine but no network access. Dependencies must already be cached or fetched during setup. `deno.lock` pins the test dependency. A full macOS/Windows native smoke test remains part of staging rollout; unit/widget tests do not establish device-level behavior.
