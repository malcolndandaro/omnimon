# PRD: Omnimon — Phase 1 Contabo Deployment

Status: ready-for-agent

> Self-hostable deployment wrapper that stands up upstream Omnigent (server + UI + a runner) behind Google login on a fresh VM, with one env-driven Docker stack that also runs identically on localhost.

## Problem Statement

I want to run Omnigent — an agent-orchestration server with a web UI — somewhere I can reach from any device, so I can dispatch and supervise agent work from anywhere. Upstream Omnigent ships a bare `docker compose` + Postgres, but it leaves the production essentials to me: it mandates HTTPS (its session cookie uses the `__Host-` prefix) yet ships no reverse proxy; it needs a separately-registered Host to actually execute anything; and "just run it" exposes an internet-facing box that can run code and spend my Claude subscription to anyone who completes a Google login. I don't want to hand-assemble TLS, OAuth wiring, a runner, secrets, and an authorization gate every time — and I want the result to be a generic, public repo that anyone (including me, on another VM or localhost) can replicate with one command.

## Solution

Omnimon is a thin, opinionated **deployment wrapper** around upstream Omnigent. It owns *deployability*, not application logic, and never forks or modifies Omnigent (see ADR-0001). From the operator's perspective: spin up a fresh Ubuntu VM, run `setup.sh` (installs Docker, clones the repo, mints secrets into `.env`), set one domain value, and `docker compose up -d`. That brings up a single env-driven stack — a Caddy TLS front door, the Omnigent **Server**, Postgres, and a dedicated **runner** container with Claude Code inside it — reachable over HTTPS at the operator's domain, gated by Google login restricted to an email allowlist. The same compose file runs on Contabo, any other VPS, or localhost, with only the domain value changing.

## User Stories

1. As an operator, I want to stand up the whole stack on a fresh Ubuntu VM with a single `setup.sh` run, so that I don't hand-install Docker, clone, and configure step by step.
2. As an operator, I want `setup.sh` to install Docker and the compose plugin if missing, so that a bare VM is sufficient to start.
3. As an operator, I want `setup.sh` to mint strong, unique secrets into `.env` (Postgres password, Omnigent accounts cookie secret, any token keys), so that I never ship or reuse default credentials.
4. As an operator, I want a committed `.env.example` documenting every variable, so that I know exactly what to set and what each value means.
5. As an operator, I want to set a single `OMNIMON_DOMAIN` value that drives the Caddy site address, `OMNIGENT_DOMAIN`, `OMNIGENT_ACCOUNTS_BASE_URL`, and the OAuth callback URL, so that I configure the deployment in one place.
6. As an operator, I want `docker compose up -d` to bring up Caddy, the Server, Postgres, and the runner together, so that one command yields a working system.
7. As an operator, I want Caddy to obtain and auto-renew a real Let's Encrypt certificate for my domain, so that I never manually manage or rotate certificates.
8. As an operator, I want the exact same compose file to run on localhost with `OMNIMON_DOMAIN=localhost` (Caddy serving a trusted local certificate), so that I can validate changes locally before deploying.
9. As an operator, I want the UI reachable over HTTPS at my domain, so that Omnigent's `__Host-` session cookie works and the app is secure in transit.
10. As an operator, I want Caddy to proxy the runner's WebSocket tunnel, so that the runner can dial back to the Server through the same front door.
11. As an operator, I want Postgres to persist its data on a named Docker volume, so that the database survives container restarts and is portable across hosts (not tied to a specific mounted disk).
12. As an operator, I want a dedicated, network-isolated runner container with Node 22, tmux, Claude Code, and bubblewrap that runs `omnigent host`, so that agent sessions can actually execute (the Server alone cannot run them).
13. As an operator, I want the runner registered to the Server automatically on startup so it appears as an available Host, so that I can launch sessions without manual registration each boot.
14. As an operator, I want to authenticate Claude Code inside the runner once and have those credentials persist on a named volume, so that the runner stays logged in across restarts and rebuilds without re-authenticating.
15. As an operator, I want agent terminals sandboxed with bubblewrap inside the runner container, so that isolation matches upstream's mandatory Linux behavior without resorting to Docker-in-Docker.
16. As an operator, I want the runner on its own Docker network, separate from the control plane, so that the privileged container's blast radius is bounded.
17. As a user, I want to sign in with my Google account, so that I can access the UI from any device without managing a separate password.
18. As an operator, I want only email addresses on an allowlist (`OMNIMON_ALLOWED_EMAILS`, defaulting to my address) to be authorized after Google login, so that authenticating with Google is not by itself enough for a stranger to get in.
19. As an operator, I want a non-allowlisted Google identity to be rejected rather than served the app, so that the internet-facing box stays single-tenant.
20. As an operator, I want auth enabled in every environment including localhost (localhost mirrors prod), so that I never accidentally test against a weaker security posture than I deploy.
21. As an operator, I want to widen access later by adding emails to `OMNIMON_ALLOWED_EMAILS`, so that onboarding a teammate is a one-line change, not a re-architecture.
22. As an operator, I want Omnimon to consume Omnigent as the pinned image `ghcr.io/omnigent-ai/omnigent-server:v0.1.0`, so that deploys are reproducible and an upstream change can't silently break my box.
23. As an operator, I want to upgrade Omnigent by bumping a single pinned tag, so that upgrades are explicit and reviewable.
24. As a replicator (someone who isn't me), I want the public repo to run on my own VM or laptop with no edits beyond `.env`, so that the documented path is the same one the author actually runs.
25. As a replicator, I want the README to clearly state that the runner container is privileged and what that enables, so that I understand the security tradeoff before I run it.
26. As an operator, I want clear documentation of the Google Cloud OAuth client setup (issuer, client id/secret, the `https://<domain>/auth/callback` redirect URI), so that I can wire Google login correctly the first time.
27. As an operator, I want documented DNS guidance (an A record for `OMNIMON_DOMAIN` pointing at the VM), so that certificate issuance and the callback work on first boot.
28. As an operator, I want services to restart automatically unless explicitly stopped, so that the deployment survives reboots.
29. As an operator deploying to Contabo, I want Omnimon to assume a fresh VM that owns ports 80/443, so that it does not collide with my existing midas deployment (which already binds 80/443 on its own VM).
30. As an operator, I want a documented teardown/redeploy path, so that I can rebuild the box from scratch and trust I'll get the same result.
31. As a maintainer, I want an end-to-end smoke test I can run on demand that boots the stack and asserts its external behavior, so that I can trust a change before deploying.
32. As a maintainer, I want a fast config-rendering test that doesn't boot containers, so that I get quick feedback on the wiring that's easiest to get subtly wrong.

## Implementation Decisions

- **Wrapper, not a fork.** Omnimon consumes upstream Omnigent only as the pinned published image `ghcr.io/omnigent-ai/omnigent-server:v0.1.0`. No submodule, no source build, no edits to Omnigent. (ADR-0001.)
- **One env-driven `docker-compose.yml`** with four sibling services (no Docker-in-Docker):
  - `caddy` — TLS termination on 80/443, automatic Let's Encrypt, reverse-proxies the Server and its WebSocket tunnel.
  - `omnigent-server` — the upstream image, the control plane / web UI / API on 6767.
  - `postgres` — `postgres:17-alpine`, data on a named volume, healthcheck gating dependents.
  - `omnigent-runner` — a Host built by Omnimon: Node 22 + tmux + Claude Code + bubblewrap, runs `omnigent host`, on its own Docker network, privileged as required for bubblewrap.
- **Single source of truth for the domain.** `OMNIMON_DOMAIN` drives the Caddy site address, `OMNIGENT_DOMAIN`, `OMNIGENT_ACCOUNTS_BASE_URL`, and the OAuth callback (`https://<domain>/auth/callback`). Setting it to `localhost` yields a working local deployment via Caddy's internal CA.
- **Authentication contract.** Google OIDC: `OMNIGENT_OIDC_ISSUER=https://accounts.google.com`, `OMNIGENT_OIDC_CLIENT_ID`, `OMNIGENT_OIDC_CLIENT_SECRET`, `OMNIGENT_AUTH_ENABLED=1`, plus `OMNIGENT_ACCOUNTS_COOKIE_SECRET` and `OMNIGENT_ACCOUNTS_BASE_URL`. Auth is on in every environment.
- **Authorization gate.** `OMNIMON_ALLOWED_EMAILS` (default: the operator's address) restricts who is admitted after a successful Google login. This is wired through to wherever Omnigent enforces its identity allowlist; authentication at Google is never sufficient on its own. (Required by the privileged runner — ADR-0003.)
- **Reverse proxy is Caddy**, deliberately diverging from midas's nginx+certbot, for one small env-driven config that works identically on a public VM and localhost. (ADR-0002.)
- **Runner execution model.** The runner container is privileged and isolated on its own network; bubblewrap stays enabled and runs *inside* the container (not DinD, not disabled). Claude Code is authenticated once and its credentials persist on a named volume. (ADR-0003.)
- **Harness / models.** The harness is the `claude` CLI + Claude Agent SDK on a Claude Code subscription (not an API key). Ollama and any local-LLM gateway are out of scope (Phase 2).
- **Provisioning.** Canonical path is a portable `setup.sh` (install Docker, clone, mint secrets) plus docs. No terraform in the core repo. Works on any Ubuntu VPS or localhost.
- **Persistence.** Postgres on a named volume; Caddy's cert/state on a named volume; the runner's Claude Code credentials on a named volume. No host-path coupling.
- **Restart policy.** Long-running services use `restart: unless-stopped`.
- **Repo artifacts produced by this PRD:** `docker-compose.yml`, a `Caddyfile`, the runner `Dockerfile`, `.env.example`, `setup.sh`, and a README covering DNS, Google OAuth client setup, the privileged-runner tradeoff, one-time Claude Code login, and teardown/redeploy.

## Testing Decisions

A good test here asserts **external, observable behavior of the deployment** — what an operator or user would see — never Omnigent's internals (that's upstream's responsibility) and never implementation details of our compose. Two seams, agreed with the operator:

- **Seam 1 — the running stack over HTTP(S) (primary, end-to-end black box).** Boot the stack with `OMNIMON_DOMAIN=localhost` via `docker compose up -d`, wait for health, then assert through Caddy:
  - HTTPS terminates and the UI/health endpoint responds;
  - an unauthenticated request is redirected into the Google OIDC flow rather than served the app;
  - the `omnigent-runner` registers and appears as an available Host;
  - (negative) a non-allowlisted identity is rejected.
  This needs Docker and the pulled image, so it runs in CI / on demand, not on every change.
- **Seam 2 — config rendering (fast guard, no containers).** Given an `.env`, assert the rendered config is correct: `OMNIMON_DOMAIN` propagates into the Caddy site address, `OMNIGENT_ACCOUNTS_BASE_URL`, and the OAuth callback URL; `OMNIMON_ALLOWED_EMAILS` lands where Omnigent reads it; `setup.sh` mints non-empty, unique secrets. A pure function of inputs → rendered files, so it gives fast feedback on the wiring most likely to harbor a real bug (a wrong callback URL or an empty allowlist).

Prior art: the sibling **midas** repo demonstrates the same overall shape (env-driven `docker-compose.prod.yml`, reverse proxy, Postgres, Google OAuth env contract) and is a reference for service wiring and the `.env` pattern — though Omnimon deliberately uses Caddy rather than midas's nginx+certbot (ADR-0002). No automated tests for the deployment exist yet; these two seams are the starting point.

## Out of Scope

- **The 5090 home Host and Ollama / local-LLM gateway (Phase 2).** Documented as a future second Host but not built. (Note for later: that box needs Linux/WSL for proper bubblewrap; native Windows sandboxing is degraded.)
- **Sharing the existing midas Contabo VM.** Omnimon targets a *new* VM that owns 80/443; co-hosting behind midas's nginx or a shared front proxy is explicitly rejected for Phase 1.
- **Terraform / IaC provisioning** in the core repo.
- **Managed cloud sandbox execution** (Modal/E2B/Daytona/etc.) — rejected in favor of the local privileged runner.
- **Multi-tenant / open signup.** Phase 1 is single-user via an email allowlist.
- **API-key-based model billing.** The subscription harness is the chosen path.
- **Modifying or contributing upstream to Omnigent.**
- **Hardening the runner below full privilege** (minimum-cap set, dropping `--privileged`). Noted as a possible later tightening, not done now.

## Further Notes

- This is the foundational deployment; subsequent PRDs (e.g. the 5090 Host, Ollama gateway, runner hardening) build on the stack it establishes.
- The exact published image digest, the final Caddy/privileged-runner flags, the concrete `OMNIMON_DOMAIN` value, and the DNS A record are settled at build/deploy time and are not design blockers.
- Relevant context lives in [CONTEXT.md](../../CONTEXT.md) (glossary) and the ADRs under [docs/adr/](../../docs/adr/): 0001 (pinned image), 0002 (Caddy), 0003 (privileged runner).
