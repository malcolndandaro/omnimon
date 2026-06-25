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
# Claude Code auth is headless via the CLAUDE_CODE_OAUTH_TOKEN env var; get it
# once with `docker compose exec omnigent-runner claude setup-token` and put it
# in .env. After the omnigent login, the host reconnects automatically.
set -u
: "${OMNIGENT_SERVER_URL:?set OMNIGENT_SERVER_URL}"

log() { printf '[omnimon-runner] %s\n' "$*"; }

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
	if omnigent host "${OMNIGENT_SERVER_URL}"; then
		log "host exited cleanly; reconnecting in 5s"
	else
		log "host exited (likely not logged in yet). Complete the one-time login:"
		log "  docker compose exec omnigent-runner omnigent login ${OMNIGENT_SERVER_URL}"
		log "  (and set CLAUDE_CODE_OAUTH_TOKEN in .env via 'claude setup-token')"
		log "then this container will connect automatically. Retrying in 15s…"
		sleep 10
	fi
	sleep 5
done
