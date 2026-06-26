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
# If the server rejects the runner's token with HTTP 403 (happens when the
# server container is restarted or OMNIGENT_OIDC_COOKIE_SECRET is rotated)
# re-run the login above to get a fresh token. OMNIGENT_ALERT_WEBHOOK_URL, if
# set, receives a plain-text POST the moment a 403 is detected so you know
# immediately rather than discovering it from a failed job.
#
# Claude Code auth is headless via the CLAUDE_CODE_OAUTH_TOKEN env var; get it
# once with `docker compose exec omnigent-runner claude setup-token` and put it
# in .env. After the omnigent login, the host reconnects automatically.
set -u
: "${OMNIGENT_SERVER_URL:?set OMNIGENT_SERVER_URL}"

log()   { printf '[omnimon-runner] %s\n' "$*"; }

# Print to stderr (always visible in `docker compose logs`) and fire an
# optional webhook so an operator is paged without watching logs.
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

while true; do
    log "connecting host to ${OMNIGENT_SERVER_URL}"
    tmplog=$(mktemp)

    # Tee output so it appears in `docker compose logs` AND can be inspected
    # for the 403 error message after the process exits.
    omnigent host "${OMNIGENT_SERVER_URL}" 2>&1 | tee "$tmplog"
    omnigent_exit=${PIPESTATUS[0]}

    if [ "$omnigent_exit" -eq 0 ]; then
        log "host exited cleanly; reconnecting in 5s"
    elif grep -q "HTTP 403" "$tmplog" 2>/dev/null; then
        alert "runner tunnel rejected (HTTP 403) — token invalidated by server restart or OMNIGENT_OIDC_COOKIE_SECRET rotation. Re-authenticate:"
        alert "  docker compose exec omnigent-runner omnigent login ${OMNIGENT_SERVER_URL}"
        sleep 25  # back off; manual action is required before a retry makes sense
    else
        log "host exited (likely not logged in yet). Complete the one-time login:"
        log "  docker compose exec omnigent-runner omnigent login ${OMNIGENT_SERVER_URL}"
        log "  (and set CLAUDE_CODE_OAUTH_TOKEN in .env via 'claude setup-token')"
        log "then this container will connect automatically. Retrying in 15s…"
        sleep 10
    fi

    rm -f "$tmplog"
    sleep 5
done
