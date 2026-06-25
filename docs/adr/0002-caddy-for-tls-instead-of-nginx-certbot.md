# Caddy for TLS instead of nginx + certbot

Omnimon terminates TLS with Caddy (automatic Let's Encrypt) rather than the nginx + certbot stack used by the sibling midas project. Omnigent mandates HTTPS (its session cookie uses the `__Host-` prefix) and the runner uses a WebSocket tunnel, so the proxy must do TLS + WebSockets; Caddy does both with a ~4-line `Caddyfile`, auto-provisions and auto-renews certificates, and serves a trusted local cert for `localhost` — the same config works on a public VM and on a laptop.

## Considered Options

- **Caddy (chosen)** — collapses the TLS story to one small, env-driven file; no certbot sidecar, no renewal cron, no cert-volume juggling. Directly serves the "easy to replicate / portable to any VM or localhost" goal. Free and open source (Apache 2.0), Let's Encrypt-backed like certbot.
- **nginx + certbot** — the proven midas pattern with existing operational muscle memory, but more moving parts (nginx.conf + certbot container + cert volumes + renewal) — the more complex option chosen *despite* the simplicity goal, mainly for familiarity.

## Consequences

- Omnimon deliberately diverges from midas's proxy stack; the two projects are not meant to share proxy config. A future reader comparing them should not "align" Omnimon onto nginx.
