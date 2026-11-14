# Sync regression checks

Run only the isolated regression tests and the existing pure model workflow tests:

```sh
flutter test --no-pub test/sync_regression/sync_safety_test.dart test/test_project_head_workflow.dart
```

These use mock SharedPreferences and injected fake services/HTTP clients. They do not log into Supabase or access production data. Several other existing tests in this repository change hosted records; do not run the full suite against production as a smoke test.

## Behavior to verify manually after review

- Stage a cash expense with a photo, leave the form and reopen it. Verify its amount, date, receipt and UUID survive.
- Submit cash and stock offline. Confirm the result distinguishes local acceptance from cloud upload. Reconnect and retry; the voucher must appear once.
- Submit or edit during a retry; verify new rows and failed drafts remain.
- Reject from Project Head; status and review note must persist together.
- Open All History as Project Head, Accounts and Admin. Confirm review actions appear only for the permitted role/stage and current company policy.
- Refresh and check pending queues, histories and material/unit balances across two devices.
- Compare operational cash (includes pending/local entries) with approved cash. Stock quantities remain separated by material and unit.

## Deployment dependencies — not executed

The Flutter client no longer ships a service-role key or accepts hardcoded management passwords. Management users need real Supabase Auth accounts and active users profiles. Site ID/PIN authentication still does not create a Supabase Auth session; worker operations now rely on existing anonymous policies and may be rejected. Do not release this security change until worker identity/scoping and management role policies are implemented and validated in staging.

The server must enforce role, site membership, permission revocation and allowed approval transitions atomically. Local role checks and conditional updates are defense in depth, not a substitute for those policies. Hosted RLS/publication/Storage configuration has not been inspected or modified in this patch. Permission settings currently stored in tasks also require server-side protection. Password fields in the old permission-settings model do not provision Supabase Auth credentials.

Previously exposed service-role credentials remain valid until rotated server-side. Historical Git content and handover documents are not sanitized by removing the constant from client source. Rotation must be coordinated with replacing old clients and any dependent backend processes.

Legacy offline rows have no reliable acknowledgement identity. They remain preserved and held for reconciliation; this patch deliberately does not guess whether an older row was already uploaded. No queue is cleared automatically. New-format rows paused after a database error can resume after an explicit correction.

Staged drafts and pending attachment bytes are retained in device preferences. A failed storage write reports failure and keeps the form data. This is not a replacement for durable database-backed local storage at larger volumes; test realistic photo batches on target Android devices and browsers before release.
