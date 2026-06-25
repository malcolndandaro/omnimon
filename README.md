# Omnimon

A small, opinionated **deployment wrapper** that stands up the upstream
[Omnigent](https://github.com/omnigent-ai/omnigent) agent-orchestration
framework — server, web UI, and a runner — behind Google sign-in, with one
env-driven Docker stack that runs the same on a VPS or on `localhost`.

Omnimon **wraps** Omnigent (a pinned published image); it never forks or
modifies it. See [`docs/adr/`](docs/adr/) for the load-bearing decisions and
[`CONTEXT.md`](CONTEXT.md) for the vocabulary.

> **Status:** Phase 1 (single Contabo/VPS deployment). The home-GPU runner and
> Ollama local models are Phase 2 and not built yet.

## Architecture

```
            ┌─────────── your VM (owns :80/:443) ───────────┐
 Browser ──▶│  caddy  ──▶  omnigent-server :8000  ──▶ postgres │
 (Google    │   (TLS)        (UI / API)                        │
  login)    │                    ▲                             │
            │            omnigent-runner ── bwrap ── agents     │
            └──────────────────────────────────────────────────┘
```

- **caddy** — TLS front door on 80/443, automatic Let's Encrypt, proxies the
  server and the runner's WebSocket tunnel. (ADR-0002)
- **omnigent-server** — the upstream control plane (UI/API) on port 8000.
- **postgres** — `postgres:16-alpine`, data on a named volume.
- **omnigent-runner** — a privileged, network-isolated sibling container with
  Claude Code + bubblewrap that actually executes agent sessions. (ADR-0003)

## Quick start

```bash
git clone <this-repo> omnimon && cd omnimon
./setup.sh            # installs Docker if needed; mints secrets into .env
# edit .env: set OMNIMON_DOMAIN, OMNIGENT_OIDC_CLIENT_ID/SECRET, OMNIMON_ALLOWED_EMAILS
docker compose up -d
```

`setup.sh` is idempotent — it creates `.env` from `.env.example` on first run,
mints strong unique values for `POSTGRES_PASSWORD` and
`OMNIGENT_ACCOUNTS_COOKIE_SECRET`, and never overwrites values you've set. The
only things you supply by hand are the domain, the Google OAuth credentials,
and the email allowlist.

Set `OMNIMON_DOMAIN=localhost` to run locally, or a real FQDN on a server.

## Deploying to a server

1. **Use a dedicated VM.** Omnimon's Caddy binds ports **80 and 443**. Put it
   on its **own** host — do not co-locate it with another stack that already
   owns 80/443 (e.g. an existing nginx deployment), or they will conflict.
2. **DNS.** Point an **A record** for your `OMNIMON_DOMAIN` at the VM's public
   IP before first boot, so Caddy can complete the Let's Encrypt challenge.
3. **Google OAuth.** Create the OAuth client and add your callback +
   test users (see below).
4. `./setup.sh`, fill `.env`, `docker compose up -d`, then complete the
   runner's one-time login.

Any Ubuntu VPS works; nothing here is Contabo-specific.

## Google sign-in setup

Omnimon authenticates with **Google OIDC** and is locked to an email
allowlist. Because Omnigent's OIDC access control is *domain-level*, the
**per-email** gate is enforced at Google itself:

1. In **Google Cloud Console → APIs & Services → Credentials**, create an
   **OAuth 2.0 Client ID** of type **Web application**.
2. Add an **Authorized redirect URI** of exactly:
   `https://<OMNIMON_DOMAIN>/auth/callback`
   (e.g. `https://agents.example.com/auth/callback`, or
   `https://localhost/auth/callback` for local dev).
3. On the **OAuth consent screen**, keep the publishing status as
   **"Testing"** and add each allowed address (e.g. your Gmail) as a
   **Test user**. Google will refuse to issue a token to anyone not on that
   list — this is what actually enforces single-user access.
4. Put the client id/secret in `.env` as `OMNIGENT_OIDC_CLIENT_ID` /
   `OMNIGENT_OIDC_CLIENT_SECRET`, and list the same addresses in
   `OMNIMON_ALLOWED_EMAILS` (they are also made Omnigent admins).

> **Important:** the single-email guarantee depends on the OAuth app staying
> in **Testing** status. If you ever "Publish" the app to Production, any
> Google account could authenticate — at that point you must switch to a
> domain allowlist or front the stack with a forward-auth proxy. Open
> multi-user Google signup is **out of scope** for Phase 1.

## The runner (one-time login)

The `omnigent-runner` container is the **Host** that executes agent sessions.
Upstream Omnigent has no headless host token — `omnigent host` reuses the
token from an interactive `omnigent login` — so there is a **one-time** login
per fresh runner volume. The tokens persist on the `runner-home` volume, so
the runner reconnects automatically on every restart afterward.

After `docker compose up -d`, do this once:

```bash
# 1) Register the runner as a Host (prints a Google sign-in URL; open it,
#    approve, and it stores the host token on the persisted volume)
docker compose exec omnigent-runner omnigent login https://<OMNIMON_DOMAIN>

# 2) Get a long-lived Claude Code subscription token (prints a URL; open it,
#    approve, paste the code back), then put the printed token in .env as
#    CLAUDE_CODE_OAUTH_TOKEN and re-up so the runner picks it up.
docker compose exec omnigent-runner claude setup-token
```

The runner then shows up as an available Host in the Omnigent UI and stays
connected across restarts.

> **Privileged container:** the runner runs with `privileged: true` because
> bubblewrap (Omnigent's mandatory Linux agent sandbox) needs it inside a
> container. The runner is kept on its **own** Docker network and reaches the
> server only through the public front door, so an agent that escaped bubblewrap
> is still confined to the runner container and cannot reach Postgres or the
> control plane. This is accepted for a single-tenant box you control. (ADR-0003)

### Local dev caveat

For `OMNIMON_DOMAIN=localhost`, Google will redirect to
`https://localhost/auth/callback`, which uses Caddy's internal certificate.
Trust it once so the browser accepts the redirect (e.g. install Caddy's local
CA), or run a throwaway domain. Auth stays **on** locally so local mirrors
production.

## Teardown & redeploy

```bash
docker compose down              # stop, keep data (Postgres, certs, runner login)
docker compose down -v           # stop and DELETE all data/volumes (full reset)
docker compose pull && docker compose up -d   # apply an OMNIGENT_IMAGE_TAG bump
```

After a `down -v` (or on a new box) you redeploy from scratch: `./setup.sh` →
fill `.env` → `docker compose up -d` → redo the runner's one-time login. Because
all state lives in named volumes and `.env`, the box is fully reproducible.

## Tests

```bash
bash tests/run.sh
```

- **Seam 2 (config)** — fast, no containers; verifies the `OMNIMON_DOMAIN`
  wiring, the pinned image, the database contract, and the auth/allowlist
  rendering. Runs anywhere.
- **Seam 1 (smoke)** — boots the stack on `localhost` and checks HTTPS, the
  auth redirect, and (Slice 03) the runner registration. Requires Docker;
  skips cleanly where Docker is absent.
