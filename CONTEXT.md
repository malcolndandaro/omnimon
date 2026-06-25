# Omnimon

Omnimon is a deployment wrapper that makes the upstream **Omnigent** agent-orchestration framework easy to self-host on any machine (a Contabo VPS first, other VPS or localhost later). It owns no application logic — its value is *deployability*.

## Language

**Omnigent**:
The upstream open-source multi-agent orchestration framework we deploy. Consists of a central Server (web UI on port 6767) plus Hosts that execute agent sessions. We consume it as published artifacts; we never fork or modify its code.
_Avoid_: "the app", "the backend" (those are ambiguous between Omnigent and Omnimon's own wrapper concerns)

**Omnimon**:
This repo. A thin, opinionated production wrapper around upstream Omnigent — TLS reverse proxy, OAuth/domain wiring, one-command bootstrap, persistence, and runner-onboarding — that stays generic and portable across VMs and localhost.
_Avoid_: "the fork", "the server" (Omnimon is not a fork and is not the Omnigent server)

**Server**:
The single central Omnigent process serving the web UI and API (port 6767), which Omnimon hosts behind its reverse proxy. There is exactly one per deployment.
_Avoid_: "backend", "API host"

**Host** (a.k.a. **Runner**):
A registered execution endpoint that runs `omnigent host`, executes agent sessions, and dials back over a WebSocket tunnel. In Omnimon the first Host is a **dedicated, privileged, network-isolated runner container** (Node + tmux + Claude Code + bwrap) that sits beside the control plane in the same compose — agents are sandboxed with bwrap *inside* this container, not via Docker-in-Docker. A home GPU machine may join later as an additional Host.
_Avoid_: "worker", "node", "agent" (an "agent" is the AI agent being run, not the machine running it)

**Harness**:
The agent runtime a Host executes — for Omnimon, the `claude` CLI (Claude Code) and the Claude Agent SDK, authenticated with a Claude Code subscription rather than an API key. A "native" harness runs directly on a Host and, on Linux, inside a bubblewrap sandbox.
_Avoid_: "the agent", "the model" (the harness runs an agent which calls a model; they are three different things)

**Model provider**:
Where a harness's tokens come from. Omnimon uses the Claude Code subscription for Claude models and a self-hosted **Ollama** gateway (on the GPU Host) for local LLMs.
_Avoid_: "the LLM", "the API"

**Reverse proxy**:
The TLS-terminating front door (Caddy, with automatic Let's Encrypt certificates) Omnimon places ahead of the Omnigent Server. Required because Omnigent's session cookie uses the `__Host-` prefix and therefore mandates HTTPS; also proxies the runner's WebSocket tunnel.
_Avoid_: "gateway", "ingress", "nginx" (Omnimon uses Caddy, not the nginx+certbot stack midas uses)
