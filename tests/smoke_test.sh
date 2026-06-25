#!/usr/bin/env bash
# Seam 1 — end-to-end smoke test. Boots the real stack with
# OMNIMON_DOMAIN=localhost and asserts external behavior through Caddy.
# Requires Docker; SKIPs cleanly (exit 0) where Docker is unavailable so it
# is safe to invoke from a dev laptop, and runs for real in CI / on the VM.
#
# Slices extend this file:
#   01  HTTPS terminates and the server answers through Caddy
#   02  unauthenticated -> redirected into Google OIDC; non-allowlisted rejected
#   03  the runner registers and shows as an available Host
set -uo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

if ! command -v docker >/dev/null 2>&1; then
	echo "SKIP: docker not found — Seam 1 runs in CI / on the VM."
	exit 0
fi
if ! docker compose version >/dev/null 2>&1; then
	echo "SKIP: 'docker compose' plugin not found — Seam 1 runs in CI / on the VM."
	exit 0
fi

fail=0
ok()   { printf '  \033[32mok\033[0m  %s\n' "$1"; }
bad()  { printf '  \033[31mFAIL\033[0m %s\n' "$1"; fail=1; }

# Throwaway env for an isolated test stack.
ENV_FILE="$(mktemp)"
cat >"$ENV_FILE" <<EOF
OMNIMON_DOMAIN=localhost
OMNIGENT_IMAGE=ghcr.io/omnigent-ai/omnigent-server
OMNIGENT_IMAGE_TAG=v0.1.0
POSTGRES_USER=omnigent
POSTGRES_DB=omnigent
POSTGRES_PASSWORD=$(openssl rand -hex 16)
# Auth on (mirrors prod). Dummy OIDC creds are enough for the server to
# build the Google authorize redirect; real validation happens at Google.
OMNIGENT_AUTH_ENABLED=1
OMNIGENT_OIDC_CLIENT_ID=smoke-test-client-id
OMNIGENT_OIDC_CLIENT_SECRET=smoke-test-client-secret
OMNIGENT_OIDC_COOKIE_SECRET=$(openssl rand -hex 32)
OMNIMON_ALLOWED_EMAILS=smoke@example.com
OMNIGENT_OIDC_ALLOW_INVITES=0
EOF

compose() { docker compose --project-name omnimon-smoke --env-file "$ENV_FILE" -f "$ROOT/docker-compose.yml" "$@"; }

cleanup() { compose down -v >/dev/null 2>&1 || true; rm -f "$ENV_FILE"; }
trap cleanup EXIT

echo "Seam 1 — smoke (localhost)"
echo "  bringing up the stack…"
if ! compose up -d >/dev/null 2>&1; then
	bad "stack failed to start"
	compose logs --no-color | tail -n 50
	exit 1
fi

# Wait for the server to answer through Caddy over HTTPS (-k: trust Caddy's
# local CA). Success = any HTTP status < 500 (200 or an auth redirect both
# prove TLS + proxy + server are working).
code=""
for _ in $(seq 1 60); do
	code="$(curl -ksS -o /dev/null -w '%{http_code}' https://localhost/ 2>/dev/null || true)"
	if [ -n "$code" ] && [ "$code" != "000" ] && [ "$code" -lt 500 ]; then break; fi
	sleep 2
done

if [ -n "$code" ] && [ "$code" != "000" ] && [ "$code" -lt 500 ]; then
	ok "HTTPS terminates and the server responds through Caddy (HTTP $code)"
else
	bad "no healthy HTTPS response through Caddy (last code: ${code:-none})"
	compose logs --no-color | tail -n 50
fi

# TLS actually negotiated (not a plaintext fallback).
if curl -ksS -o /dev/null https://localhost/ 2>/dev/null; then
	ok "TLS handshake with Caddy succeeds"
else
	bad "TLS handshake with Caddy failed"
fi

# ── Slice 02: auth gate ───────────────────────────────────────────────
# The UI is a SPA: "/" serves a 200 HTML shell, and the gate is enforced on
# the API — an unauthenticated /v1/me must be rejected (401/403). (Confirmed
# against the live server.)
me_status="$(curl -ksS -o /dev/null -w '%{http_code}' https://localhost/v1/me 2>/dev/null || true)"
case "$me_status" in
	401|403) ok "unauthenticated API call is rejected (/v1/me -> $me_status)" ;;
	*)       bad "unauthenticated /v1/me was not rejected (got ${me_status:-none})" ;;
esac
# Actually rejecting a non-allowlisted *identity* needs a real Google login, so
# it stays a documented manual check — Google Testing-mode test users enforce it.

# Note: actually rejecting a non-allowlisted *identity* requires completing
# a real Google login, so it is a documented manual check (see README), not
# automated here — Google's Testing-mode test-user list is the enforcement point.

# ── Slice 03: runner ──────────────────────────────────────────────────
# The runner image builds and its CLI is present. Actual Host registration
# needs the one-time interactive login, so it's a documented manual check.
if compose ps --status running --format '{{.Service}}' 2>/dev/null | grep -q '^omnigent-runner$'; then
	ok "runner container is running"
else
	bad "runner container is not running"
	compose logs --no-color omnigent-runner | tail -n 30
fi
if compose exec -T omnigent-runner omnigent --version >/dev/null 2>&1; then
	ok "omnigent CLI is installed in the runner"
else
	bad "omnigent CLI not available in the runner"
fi
if compose exec -T omnigent-runner sh -c 'command -v bwrap && command -v claude' >/dev/null 2>&1; then
	ok "runner has bubblewrap and Claude Code"
else
	bad "runner is missing bubblewrap or Claude Code"
fi
echo "  note: Host registration requires the one-time 'omnigent login' + 'claude' login (see README); not automated here."

echo
if [ "$fail" -eq 0 ]; then echo "Seam 1 passed."; else echo "Seam 1 failed."; fi
exit "$fail"
