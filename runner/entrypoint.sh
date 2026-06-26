#!/usr/bin/env bash
# Registers this container as an Omnigent Host and keeps it connected.
#
# Authentication is one-time and interactive — upstream Omnigent has no
# headless host token; `omnigent host` reuses the token from `omnigent login`.
# The token (and Claude Code's credentials) persist in $HOME, which is a named
# volume, so you only log in once:
#
#   docker compose exec omnigent-runner omnigent login "$OMNIGENT_SERVER_URL"
#
# HTTP 403 after a server restart is normal — the server dropped its in-memory
# session table. The runner auto-retries and reconnects once the server is ready;
# no human action is needed for that case.
#
# If 403s persist across 5+ retries (~2.5 min) the token is likely genuinely
# invalid (OMNIGENT_OIDC_COOKIE_SECRET was rotated). Re-run `omnigent login`.
# OMNIGENT_ALERT_WEBHOOK_URL, if set, receives a POST at that point.
#
# Claude Code auth is headless via the CLAUDE_CODE_OAUTH_TOKEN env var; get it
# once with `docker compose exec omnigent-runner claude setup-token` and store
# in .env. After omnigent login, the host reconnects automatically on every
# restart without further intervention.
set -u
: "${OMNIGENT_SERVER_URL:?set OMNIGENT_SERVER_URL}"

log()   { printf '[omnimon-runner] %s\n' "$*"; }

# Print to stderr (always visible in `docker compose logs`) and optionally POST
# to a webhook so an operator is notified without watching logs.
alert() {
    printf '[omnimon-runner] ALERT: %s\n' "$*" >&2
    if [ -n "${OMNIGENT_ALERT_WEBHOOK_URL:-}" ]; then
        curl -s -X POST "${OMNIGENT_ALERT_WEBHOOK_URL}" \
            --max-time 10 \
            -d "omnimon-runner: $*" \
            >/dev/null 2>&1 || true
    fi
}

# Configure GitHub access for agents when a token is provided. `gh` reads
# GH_TOKEN directly; `gh auth setup-git` points git's credential helper at it.
if [ -n "${GH_TOKEN:-}" ]; then
    if gh auth setup-git >/dev/null 2>&1; then
        log "GitHub: git + gh authenticated via GH_TOKEN"
    else
        log "GitHub: 'gh auth setup-git' failed (is gh installed in the image?)"
    fi
    [ -n "${GIT_USER_NAME:-}" ]  && git config --global user.name  "${GIT_USER_NAME}"
    [ -n "${GIT_USER_EMAIL:-}" ] && git config --global user.email "${GIT_USER_EMAIL}"
fi

# How many consecutive 403s before we stop silently retrying and alert.
# 5 attempts × 30 s ≈ 2.5 min — enough time for the server to fully initialize
# after a restart while not masking a genuinely broken token for too long.
ALERT_403_THRESHOLD=5
consecutive_403s=0

while true; do
    log "connecting host to ${OMNIGENT_SERVER_URL}"
    tmplog=$(mktemp)

    # Tee so output appears in `docker compose logs` AND can be inspected for
    # the 403 message after the process exits.
    omnigent host "${OMNIGENT_SERVER_URL}" 2>&1 | tee "$tmplog"
    omnigent_exit=${PIPESTATUS[0]}

    if [ "$omnigent_exit" -eq 0 ]; then
        consecutive_403s=0
        log "host exited cleanly; reconnecting in 5s"
        rm -f "$tmplog"
        sleep 5
        continue
    fi

    if grep -q "HTTP 403" "$tmplog" 2>/dev/null; then
        consecutive_403s=$((consecutive_403s + 1))
        rm -f "$tmplog"

        if [ "$consecutive_403s" -lt "$ALERT_403_THRESHOLD" ]; then
            # Likely Mode 1: server just restarted, session table cleared.
            # Auto-retry; the server will accept a fresh handshake once ready.
            log "tunnel rejected (HTTP 403, attempt ${consecutive_403s}/${ALERT_403_THRESHOLD}); server may still be initializing — retrying in 30s…"
            sleep 30
        else
            # Persistent 403 → likely Mode 2: OMNIGENT_OIDC_COOKIE_SECRET was
            # rotated and the stored token is no longer verifiable. Needs human.
            alert "runner tunnel rejected (HTTP 403) for ${consecutive_403s} consecutive attempts — token may be invalid. Re-authenticate: docker compose exec omnigent-runner omnigent login ${OMNIGENT_SERVER_URL}"
            sleep 120  # keep retrying in case the operator re-logins; loop picks it up
        fi
        continue
    fi

    consecutive_403s=0
    rm -f "$tmplog"

    log "host exited (likely not logged in yet). Complete the one-time login:"
    log "  docker compose exec omnigent-runner omnigent login ${OMNIGENT_SERVER_URL}"
    log "  (and set CLAUDE_CODE_OAUTH_TOKEN in .env via 'claude setup-token')"
    log "then this container will connect automatically. Retrying in 15s…"
    sleep 15
done
