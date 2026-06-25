# Control plane runs over Caddy, env-driven, with both test seams

Status: ready-for-agent

## Parent

[PRD: Omnimon — Phase 1 Contabo Deployment](../PRD.md)

## What to build

The thin tracer bullet through the whole stack: a single env-driven `docker-compose.yml` that brings up Caddy in front of the upstream Omnigent **Server** and a **Postgres** database, reachable over HTTPS. One variable, `OMNIMON_DOMAIN`, drives the Caddy site address (and is the single source the later auth wiring will reuse). Setting it to `localhost` yields a working local deployment via Caddy's internal CA; setting it to a real domain yields automatic Let's Encrypt certificates.

Scope:
- Compose with three sibling services: `caddy` (TLS on 80/443, reverse-proxies the Server on its internal port **8000**), `omnigent-server` from the pinned image `ghcr.io/omnigent-ai/omnigent-server:v0.1.0`, and `postgres:16-alpine` (upstream parity — upstream's own compose uses 16) with data on a named volume and a healthcheck gating the Server.
- A `Caddyfile` whose site address comes from `OMNIMON_DOMAIN`.
- A committed `.env.example` documenting every variable introduced so far, including `OMNIMON_DOMAIN` and the Postgres/database settings.
- `restart: unless-stopped` on long-running services; named volumes for Postgres and Caddy state (certs).
- Both test seams in their initial form (see Acceptance criteria).

This is a wrapper: do not fork, patch, or build Omnigent from source — consume the pinned image only (ADR-0001). Use Caddy, not nginx+certbot (ADR-0002). Use the [CONTEXT.md](../../../CONTEXT.md) vocabulary (Server, Reverse proxy, Host) in any docs/comments.

## Acceptance criteria

- [ ] `docker compose up -d` with `OMNIMON_DOMAIN=localhost` brings up Caddy, the Server, and Postgres; the Server starts only after Postgres is healthy.
- [ ] The Server's UI/health endpoint is reachable over **HTTPS** through Caddy on localhost (Caddy's internal/trusted local cert), not plain HTTP.
- [ ] Postgres data survives `docker compose down && up` (named volume), and Caddy's issued cert/state likewise persists.
- [ ] The Omnigent image is pinned to `v0.1.0` (not `latest`); changing the pin is the only way the Server version changes.
- [ ] `.env.example` exists and documents every variable, with safe placeholder values.
- [ ] **Seam 2 (config render):** a fast test, with no containers, asserts that a given `OMNIMON_DOMAIN` propagates into the rendered Caddy site address.
- [ ] **Seam 1 (smoke):** an on-demand test boots the stack with `OMNIMON_DOMAIN=localhost`, waits for health, and asserts the health/UI endpoint responds over HTTPS.

## Blocked by

- None — can start immediately
