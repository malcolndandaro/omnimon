# One-command operator deploy + full replication docs

Status: ready-for-agent

## Parent

[PRD: Omnimon — Phase 1 Contabo Deployment](../PRD.md)

## What to build

Make the whole stack replicable by anyone on a fresh VM (or localhost) with a single script and a complete README — turning the repo into the generic, public, easy-to-replicate artifact that is Omnimon's whole point. The documented path must be the same one the operator actually runs.

Scope:
- A portable `setup.sh` that: installs Docker and the compose plugin if missing, clones the repo, and **mints strong, unique secrets** into `.env` (Postgres password, `OMNIGENT_ACCOUNTS_COOKIE_SECRET`, and any token keys) — never shipping or reusing defaults. After it runs, the operator sets `OMNIMON_DOMAIN` and runs `docker compose up -d`.
- A README covering: DNS guidance (an A record for `OMNIMON_DOMAIN` → the VM), the Google OAuth client setup (cross-link issue 02), the one-time Claude Code login (cross-link issue 03), the **privileged-runner tradeoff** stated loudly (what `--privileged` enables and why it's accepted for single-tenant), the new-VM / ports-80-443 guidance (Omnimon assumes a fresh VM that owns 80/443; it must not collide with an existing deployment such as midas), and a teardown/redeploy procedure.
- Targets any Ubuntu VPS or localhost; no terraform in the core repo.

## Acceptance criteria

- [ ] On a fresh Ubuntu VM, running `setup.sh` then setting `OMNIMON_DOMAIN` and `docker compose up -d` yields a working HTTPS deployment with Google login and a registered runner — no manual steps beyond editing `.env`.
- [ ] `setup.sh` installs Docker + compose if absent and is idempotent (safe to re-run).
- [ ] `setup.sh` mints **non-empty, unique** secrets into `.env` (no placeholder/default secret survives).
- [ ] README documents DNS, Google OAuth client, one-time Claude login, the privileged-runner tradeoff, the new-VM/80-443 constraint, and teardown/redeploy.
- [ ] A teardown/redeploy procedure rebuilds the box from scratch to the same result.
- [ ] **Seam 2 (config render):** the fast test asserts `setup.sh` produces non-empty, unique secret values.

## Blocked by

- [03 — The runner Host executes](./03-runner-host-executes.md)
