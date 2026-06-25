#!/usr/bin/env bash
# Seam 2 — fast config-rendering guard. No containers, no Docker required.
# Asserts that the single OMNIMON_DOMAIN value is wired through every place
# it has to reach, that the upstream image is pinned, and that the database
# contract matches upstream. This is the wiring most likely to harbor a real
# bug (a wrong callback path or an unpinned image), so it runs everywhere.
set -uo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

echo "Seam 2 — config rendering"

# ── Files exist ───────────────────────────────────────────────────────
assert_file ".env.example"           ".env.example present"
assert_file "docker-compose.yml"     "docker-compose.yml present"
assert_file "Caddyfile"              "Caddyfile present"

# ── .env.example documents the inputs ─────────────────────────────────
assert_grep ".env.example" "OMNIMON_DOMAIN="    ".env.example documents OMNIMON_DOMAIN"
assert_grep ".env.example" "OMNIGENT_IMAGE_TAG=" ".env.example documents the image tag"
assert_grep ".env.example" "POSTGRES_PASSWORD="  ".env.example documents POSTGRES_PASSWORD"

# ── Upstream image pinned, not 'latest' (ADR-0001) ────────────────────
assert_grep "docker-compose.yml" "OMNIGENT_IMAGE_TAG:-v0.1.0" "server image defaults to pinned v0.1.0"
assert_grep ".env.example"       "OMNIGENT_IMAGE_TAG=v0.1.0"  ".env.example pins v0.1.0"
refute_grep ".env.example"       "OMNIGENT_IMAGE_TAG=latest"  ".env.example does not pin 'latest'"

# ── Domain is the single source of truth, wired everywhere ────────────
assert_grep "Caddyfile"          '{$OMNIMON_DOMAIN}'                    "Caddy site address comes from OMNIMON_DOMAIN"
assert_grep "Caddyfile"          "reverse_proxy omnigent-server:8000"   "Caddy proxies the server on port 8000"
assert_grep "docker-compose.yml" 'OMNIGENT_DOMAIN: ${OMNIMON_DOMAIN}'   "OMNIGENT_DOMAIN derives from OMNIMON_DOMAIN"
assert_grep "docker-compose.yml" 'OMNIGENT_ACCOUNTS_BASE_URL: https://${OMNIMON_DOMAIN}' "accounts base URL derives from OMNIMON_DOMAIN over https"

# ── Database contract matches upstream ────────────────────────────────
assert_grep "docker-compose.yml" "postgresql+psycopg://" "DATABASE_URL uses the psycopg driver"
assert_grep "docker-compose.yml" "@postgres:5432/"       "DATABASE_URL targets the postgres service"
assert_grep "docker-compose.yml" "postgres:16-alpine"    "postgres pinned to 16-alpine (upstream parity)"
assert_grep "docker-compose.yml" "pg_isready"            "postgres has a readiness healthcheck"
assert_grep "docker-compose.yml" "condition: service_healthy" "server waits for a healthy database"

# ── Server listen contract ────────────────────────────────────────────
assert_grep "docker-compose.yml" 'PORT: "8000"' "server listens on 8000"
assert_grep "docker-compose.yml" 'HOST: "0.0.0.0"' "server binds all interfaces"

# ── Slice 02: Google OIDC + email allowlist ───────────────────────────
echo
echo "Seam 2 — auth wiring"
assert_grep ".env.example" "OMNIGENT_OIDC_CLIENT_ID="        ".env.example documents the OIDC client id"
assert_grep ".env.example" "OMNIGENT_OIDC_CLIENT_SECRET="    ".env.example documents the OIDC client secret"
assert_grep ".env.example" "OMNIGENT_OIDC_COOKIE_SECRET=" ".env.example documents the OIDC cookie secret"
assert_grep ".env.example" "OMNIMON_ALLOWED_EMAILS="         ".env.example documents the email allowlist"
assert_grep ".env.example" "OMNIGENT_AUTH_ENABLED=1"         ".env.example enables auth"

assert_grep "docker-compose.yml" "OMNIGENT_AUTH_ENABLED:-1"          "auth enabled by default (on everywhere)"
assert_grep "docker-compose.yml" "OMNIGENT_AUTH_PROVIDER: oidc"      "auth provider pinned to oidc"
assert_grep "docker-compose.yml" "https://accounts.google.com"       "OIDC issuer is Google"
assert_grep "docker-compose.yml" "OMNIGENT_OIDC_CLIENT_ID"           "server reads the OIDC client id"
assert_grep "docker-compose.yml" "OMNIGENT_OIDC_CLIENT_SECRET"       "server reads the OIDC client secret"
assert_grep "docker-compose.yml" "OMNIGENT_OIDC_ALLOW_INVITES:-0"    "open signup forbidden by default"

# Allowlist is rendered into /data/config.yaml from OMNIMON_ALLOWED_EMAILS.
assert_grep "docker-compose.yml" "config-init"                       "config.yaml renderer service present"
assert_grep "docker-compose.yml" "/data/config.yaml"                 "renderer writes /data/config.yaml"
assert_grep "docker-compose.yml" "admins: ["                         "renderer emits an admins allowlist"
assert_grep "docker-compose.yml" "service_completed_successfully"    "server waits for the allowlist to render"

# ── Slice 03: the runner Host ─────────────────────────────────────────
echo
echo "Seam 2 — runner wiring"
assert_file "runner/Dockerfile"  "runner Dockerfile present"
assert_file "runner/entrypoint.sh" "runner entrypoint present"
assert_grep "runner/Dockerfile" "bubblewrap"        "runner installs bubblewrap (mandatory sandbox)"
assert_grep "runner/Dockerfile" "tmux"              "runner installs tmux"
assert_grep "runner/Dockerfile" "@anthropic-ai/claude-code" "runner installs Claude Code"
assert_grep "runner/Dockerfile" "uv tool install"  "runner installs the omnigent CLI"
assert_grep "runner/entrypoint.sh" "omnigent host" "runner runs 'omnigent host'"
assert_grep "docker-compose.yml" "CLAUDE_CODE_OAUTH_TOKEN" "runner receives the Claude Code token"
assert_grep ".env.example" "CLAUDE_CODE_OAUTH_TOKEN=" ".env.example documents the Claude Code token"
assert_grep "docker-compose.yml" "GH_TOKEN" "runner receives the GitHub token"
assert_grep "runner/Dockerfile" "githubcli" "runner installs the GitHub CLI"
assert_grep "runner/entrypoint.sh" "gh auth setup-git" "runner wires git to GH_TOKEN"

assert_grep "docker-compose.yml" "omnigent-runner"      "runner service present"
assert_grep "docker-compose.yml" "privileged: true"     "runner is privileged (for bubblewrap)"
assert_grep "docker-compose.yml" "runner-net"           "runner has its own network"
refute_grep "runner/Dockerfile"  "USER root"            "runner does not end as root"
assert_grep "docker-compose.yml" "runner-home:/home/omni" "runner persists login/creds on a volume"
assert_grep "docker-compose.yml" ":host-gateway"        "runner reaches the server via the public front door"
assert_grep "docker-compose.yml" 'https://${OMNIMON_DOMAIN}' "runner targets the OMNIMON_DOMAIN server URL"

# Blast-radius: the runner service block must NOT join control-plane.
# Extract just the omnigent-runner service block (from its header until the
# next 2-space-indented key or a column-0 key), then check its networks.
runner_block="$(awk '
	/^  omnigent-runner:/ { f=1; print; next }
	f && /^[^[:space:]]/  { f=0 }                       # column-0 key ends it
	f && /^  [^[:space:]]/ { f=0 }                       # next service ends it
	f { print }
' "$ROOT/docker-compose.yml")"
if printf '%s\n' "$runner_block" | grep -q 'control-plane'; then
	fail "runner must not be on the control-plane network (blast radius)"
else
	pass "runner is isolated from the control-plane network"
fi

# ── Slice 04: setup.sh secret minting ─────────────────────────────────
echo
echo "Seam 2 — setup.sh"
assert_file "setup.sh" "setup.sh present"
tmp="$(mktemp -d)"
cp "$ROOT/.env.example" "$tmp/.env.example"
if OMNIMON_NO_DOCKER_INSTALL=1 OMNIMON_DIR="$tmp" bash "$ROOT/setup.sh" >/dev/null 2>&1; then
	pass "setup.sh runs without Docker present"
else
	fail "setup.sh failed to run"
fi
_get() { grep -E "^$1=" "$tmp/.env" 2>/dev/null | head -1 | cut -d= -f2- || true; }
pw1="$(_get POSTGRES_PASSWORD)"
ck1="$(_get OMNIGENT_OIDC_COOKIE_SECRET)"
if [ -n "$pw1" ]; then pass "POSTGRES_PASSWORD minted (non-empty)"; else fail "POSTGRES_PASSWORD not minted"; fi
if [ -n "$ck1" ]; then pass "cookie secret minted (non-empty)"; else fail "cookie secret not minted"; fi
if [ -n "$pw1" ] && [ "$pw1" != "$ck1" ]; then pass "minted secrets are unique"; else fail "minted secrets are not unique"; fi
# Idempotency: a second run must not change an already-set secret.
OMNIMON_NO_DOCKER_INSTALL=1 OMNIMON_DIR="$tmp" bash "$ROOT/setup.sh" >/dev/null 2>&1 || true
pw2="$(_get POSTGRES_PASSWORD)"
if [ "$pw1" = "$pw2" ]; then pass "re-running setup.sh preserves secrets (idempotent)"; else fail "setup.sh changed an existing secret"; fi
rm -rf "$tmp"

summary
