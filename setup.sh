#!/usr/bin/env bash
# Omnimon one-shot setup. Safe to re-run (idempotent):
#   • ensures Docker + the Compose plugin are present
#   • creates .env from .env.example on first run
#   • mints strong, unique secrets for any secret left blank
#   • reminds you which values you still have to fill in by hand
#
# After it finishes: review .env, then `docker compose up -d`.
#
# Test/CI hooks (not for normal use):
#   OMNIMON_NO_DOCKER_INSTALL=1  skip the Docker auto-install (still warns)
#   OMNIMON_DIR=/path            operate on a different dir (default: script dir)
set -euo pipefail

DIR="${OMNIMON_DIR:-$(cd "$(dirname "$0")" && pwd)}"
cd "$DIR"

log() { printf '\033[36m[setup]\033[0m %s\n' "$*"; }
warn() { printf '\033[33m[setup] ! %s\033[0m\n' "$*"; }

# ── 1. Docker + Compose ───────────────────────────────────────────────
if ! command -v docker >/dev/null 2>&1; then
	if [ "${OMNIMON_NO_DOCKER_INSTALL:-0}" = "1" ]; then
		warn "Docker not found (auto-install skipped). Install Docker before 'docker compose up'."
	else
		log "Docker not found — installing via get.docker.com…"
		curl -fsSL https://get.docker.com | sh
	fi
fi
if command -v docker >/dev/null 2>&1 && ! docker compose version >/dev/null 2>&1; then
	warn "The Docker Compose plugin is missing — install 'docker-compose-plugin'."
fi

# ── 2. .env ───────────────────────────────────────────────────────────
if [ ! -f .env ]; then
	cp .env.example .env
	log "created .env from .env.example"
else
	log ".env already exists — leaving your values untouched"
fi

# ── 3. Mint any blank secret ──────────────────────────────────────────
# Fills KEY only when it is present but empty; never overwrites a real value.
ensure_secret() {
	local key="$1" bytes="$2" line cur val
	line="$(grep -nE "^${key}=" .env | head -1 || true)"
	if [ -z "$line" ]; then
		val="$(openssl rand -hex "$bytes")"
		printf '%s=%s\n' "$key" "$val" >> .env
		log "minted $key (added)"
		return
	fi
	cur="${line#*:}"; cur="${cur#*=}"
	if [ -z "$cur" ]; then
		val="$(openssl rand -hex "$bytes")"
		# Use a non-/ delimiter; hex secrets never contain '|'.
		sed -i.bak "s|^${key}=.*|${key}=${val}|" .env && rm -f .env.bak
		log "minted $key"
	fi
}
ensure_secret POSTGRES_PASSWORD 24
ensure_secret OMNIGENT_OIDC_COOKIE_SECRET 32

# ── 4. Nudge the operator about values only they can supply ────────────
needs=0
check_required() {
	local key="$1" cur
	cur="$(grep -E "^${key}=" .env | head -1 | cut -d= -f2- || true)"
	if [ -z "$cur" ] || [ "$cur" = "you@example.com" ]; then
		warn "set $key in .env (currently: ${cur:-empty})"
		needs=1
	fi
}
check_required OMNIGENT_OIDC_CLIENT_ID
check_required OMNIGENT_OIDC_CLIENT_SECRET
check_required OMNIMON_ALLOWED_EMAILS

dom="$(grep -E '^OMNIMON_DOMAIN=' .env | head -1 | cut -d= -f2- || true)"
if [ "$dom" = "localhost" ] || [ -z "$dom" ]; then
	warn "OMNIMON_DOMAIN is '${dom:-empty}' — set it to your FQDN for a server deploy (and add a DNS A record)."
fi

echo
if [ "$needs" = 1 ]; then
	log "Secrets are set. Fill the values flagged above in .env, then: docker compose up -d"
else
	log "Ready. Review .env, then: docker compose up -d"
fi
