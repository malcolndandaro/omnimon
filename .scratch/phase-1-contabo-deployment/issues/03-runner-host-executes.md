# The runner Host executes (privileged container + Claude Code)

Status: ready-for-agent

## Parent

[PRD: Omnimon — Phase 1 Contabo Deployment](../PRD.md)

## What to build

Add the **Host** that actually executes agent sessions — the Server alone cannot. A dedicated `omnigent-runner` container runs `omnigent host`, registers with the Server, and dials back over the WebSocket tunnel that Caddy proxies. The runner ships the harness (the `claude` CLI / Claude Code) and is sandboxed with bubblewrap *inside* the container — not Docker-in-Docker.

Scope:
- A runner `Dockerfile`: Node 22, tmux, Claude Code, and bubblewrap.
- The runner runs `omnigent host` against the Server. NOTE (confirmed against upstream): Omnigent has **no headless host token** — `omnigent host` reuses the token from an interactive `omnigent login`. So registration is a **one-time interactive login** per fresh runner volume; the token persists on a named volume and the runner **auto-reconnects** on every restart thereafter. The entrypoint loops and prints the one-time-login instructions until authenticated.
- The runner is **privileged** (as bubblewrap requires inside a container) and runs on its **own Docker network**, separate from the control plane, to bound its blast radius (ADR-0003).
- bubblewrap stays **enabled** and sandboxes each agent terminal inside the runner container; do not disable it or treat the container as the only sandbox (that would mean deviating from upstream — ADR-0001/0003).
- Claude Code authenticates **once** (documented one-time `claude login`) and its credentials persist on a named volume, surviving restarts and rebuilds without re-auth.
- Ensure Caddy proxies the runner's WebSocket tunnel.

The harness uses a Claude Code **subscription**, not an API key. Ollama / local-LLM gateways are out of scope (Phase 2).

## Acceptance criteria

- [ ] The `omnigent-runner` container starts and runs `omnigent host`; after the one-time `omnigent login`, it registers and shows as an **available Host** and reconnects automatically across restarts.
- [ ] The runner's WebSocket tunnel reaches the Server **through Caddy** (proxied correctly).
- [ ] Agent terminals on the runner are sandboxed with bubblewrap (bwrap active inside the container).
- [ ] The runner is privileged and attached to its own Docker network, isolated from the control-plane services.
- [ ] Claude Code credentials persist on a named volume: after `docker compose down && up` (and after a runner image rebuild), the runner is still authenticated with no re-login.
- [ ] A one-time Claude Code login procedure is documented.
- [ ] **Seam 1 (smoke):** the end-to-end test asserts the runner registers and appears as an available Host after the stack boots.

## Blocked by

- [02 — Google login + email allowlist](./02-google-login-and-allowlist.md)
