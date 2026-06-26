# omnimon

A small, opinionated **deployment wrapper** that self-hosts the upstream
[Omnigent](https://github.com/omnigent-ai/omnigent) agent-orchestration
framework (server + web UI + a runner) behind Google sign-in, as one
env-driven Docker stack that runs identically on a VPS or on `localhost`.

Omnimon **wraps** Omnigent (a pinned published image) and never forks or
modifies it. Read [CONTEXT.md](CONTEXT.md) for the vocabulary and
[docs/adr/](docs/adr/) for the load-bearing decisions before changing things.

## Architecture

Four sibling containers in one `docker-compose.yml` (no Docker-in-Docker):

- **caddy** — TLS on 80/443, automatic Let's Encrypt, reverse-proxies the
  server + the runner's WebSocket tunnel. (ADR-0002 — Caddy, not nginx+certbot)
- **omnigent-server** — upstream image `ghcr.io/omnigent-ai/omnigent-server`
  (pinned, ADR-0001), control plane / UI / API on **port 8000**.
- **postgres** — `postgres:16-alpine`, named volume.
- **omnigent-runner** — privileged, network-isolated sibling (Node 22 + tmux +
  Claude Code + bubblewrap) that runs `omnigent host`. (ADR-0003)

One variable, `OMNIMON_DOMAIN`, drives everything (Caddy site, server domain,
OAuth callback). Set it to `localhost` for local, or an FQDN on a server.

## Key commands

```bash
./setup.sh                 # install Docker if needed; mint secrets into .env
docker compose up -d       # bring up the stack
bash tests/run.sh          # Seam 2 (config, no Docker) + Seam 1 (smoke, needs Docker)
bash tests/config_test.sh  # fast config checks only — run after editing compose/env
```

After `up`, two one-time logins on the runner (tokens persist on a volume):

```bash
docker compose exec omnigent-runner omnigent login https://<OMNIMON_DOMAIN>
docker compose exec omnigent-runner claude setup-token   # -> put token in .env as CLAUDE_CODE_OAUTH_TOKEN
```

## Gotchas (verified against the live deploy)

- Server listens on **8000** (not the 6767 CLI default).
- `DATABASE_URL` must use the `postgresql+psycopg://` driver.
- OIDC mode requires **`OMNIGENT_OIDC_COOKIE_SECRET`** (the *accounts*-mode
  cookie var is different and not used here).
- Omnigent's OIDC allowlist is **domain-level only**; single-user access is
  enforced by keeping the Google OAuth app in **Testing** mode with the allowed
  email as the sole test user. `OMNIMON_ALLOWED_EMAILS` also renders an
  `admins:` list into `/data/config.yaml`.
- Agents run inside **bubblewrap**, which strips the host env (only
  `PATH/HOME/USER/LC_*` pass by default). To give agents a credential like
  `GH_TOKEN`, name it in **`OMNIGENT_RUNNER_ENV_PASSTHROUGH`** on the runner —
  setting it in the container env alone is not enough. `CLAUDE_CODE_OAUTH_TOKEN`
  and the other standard harness creds are forwarded automatically. Only **new**
  sessions pick up a passthrough change.
- Claude Code auth is headless via `CLAUDE_CODE_OAUTH_TOKEN`; capture the token
  from `claude setup-token` with tmux `capture-pane` (raw TUI logs corrupt it),
  and submit input with a carriage return.
- **Runner tunnel 403 after server restart:** the runner's `omnigent login` token
  is validated by the server on every tunnel connection. If the server container
  restarts (or `OMNIGENT_OIDC_COOKIE_SECRET` is rotated), it rejects the stored
  token with HTTP 403 and all job executions fail. Fix: re-run
  `docker compose exec omnigent-runner omnigent login https://<OMNIMON_DOMAIN>`.
  The entrypoint logs this as `ALERT:` and keeps retrying automatically. **Never
  rotate `OMNIGENT_OIDC_COOKIE_SECRET` without immediately re-running
  `omnigent login`.**
- Edits made on Windows: shell scripts must stay **LF**; strip CRLF before
  piping any git-checked-out script to a Linux host.

## Tests / seams

- **Seam 2** (`tests/config_test.sh`) — fast, container-free config-wiring guard;
  runs anywhere. Add an assertion here whenever you change the compose/env contract.
- **Seam 1** (`tests/smoke_test.sh`) — boots the stack on localhost and checks
  HTTPS, the auth gate, and the runner; needs Docker, skips cleanly without it.

## Status

Phase 1 (single VPS) is deployed and live. Phase 2 (a home GPU box as a second
Host + Ollama local models) is not started.

## Agent skills

### Issue tracker

Issues are tracked as local markdown files under `.scratch/<feature>/`. See `docs/agents/issue-tracker.md`.

### Triage labels

Five canonical triage roles using the default strings: `needs-triage`, `needs-info`, `ready-for-agent`, `ready-for-human`, `wontfix`. See `docs/agents/triage-labels.md`.

### Domain docs

Single-context: one `CONTEXT.md` + `docs/adr/` at the repo root. See `docs/agents/domain.md`.
