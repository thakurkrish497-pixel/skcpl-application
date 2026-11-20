-- PREPARED ONLY. Separate explicit approval required before enabling this option.
-- Existing Site-PIN clients share anonymous access and can read legacy staff PINs.
-- This opt-in therefore trusts site users/application-key holders at that boundary;
-- it is not cryptographically bound per-worker authentication. Prefer individual
-- authenticated staff identities if strict adversarial ownership is required.
-- Only rejected entries can be hidden; source audit rows/photos are retained.
-- Normal submissions, queues, approvals, login sessions and approved rows are untouched.
begin;
update public.skcpl_rejected_action_config set worker_actions_enabled=true,legacy_worker_actions_enabled=true where singleton;
commit;
-- To disable all future worker cleanup, set worker_actions_enabled=false. Do not delete audit rows.
