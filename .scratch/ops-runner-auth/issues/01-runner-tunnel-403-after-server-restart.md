# Runner tunnel returns HTTP 403; runner_failed_to_start after server restart

Status: ready-for-human

## Incident

**Observed:** 2026-06-26 ~03:34 UTC  
**Symptom:** Every new agent execution fails with `Error · execution · runner_failed_to_start`. The runner process exits with code 1; the last line of the log is:

```
error: runner tunnel rejected by server (HTTP 403); check remote server authentication
```

**Prior state:** Stack was healthy and running jobs earlier the same day.

## Root cause (most likely)

The runner authenticates to the server using the token from a one-time interactive
`omnigent login`. This token is stored on the `runner-home` named Docker volume and
reused every time `omnigent host` connects. The server returns a 403 — not a network
error — meaning it actively rejected the runner's credentials.

The 403 (not a "token file missing" error) rules out a lost volume. It points to
**server-side session invalidation**, with the following candidates in priority order:

1. **Server container was restarted** (OOM kill, `docker compose restart`, host reboot,
   or `restart: unless-stopped` cycling). Omnigent likely holds active runner sessions
   in memory; a restart clears them. The stored token is cryptographically intact but
   the server no longer recognises the session → 403.

2. **`OMNIGENT_OIDC_COOKIE_SECRET` was rotated or changed.** If `setup.sh` was re-run
   or `.env` was manually edited the server can no longer verify tokens signed with the
   old secret. The cookie secret is what the server uses to sign/verify session cookies;
   changing it invalidates all existing sessions immediately.

3. **Token TTL expired.** The `omnigent login` session token may carry a finite lifetime
   (e.g., 24 h). If it was minted early enough it would have expired by the time the
   runner reconnected after a server restart.

4. **Underlying Google OIDC token expiry.** Less likely for an intraday failure, but the
   Google access/refresh token behind the omnigent session could have expired and the
   server rejected the stale session on its next tunnel validation.

## Immediate workaround

Re-authenticate the runner. This takes roughly 30 seconds and does not require a
container restart:

```bash
docker compose exec omnigent-runner omnigent login https://<OMNIMON_DOMAIN>
```

Follow the browser prompt, then wait up to 15 s for the runner's reconnect loop to
pick up the new token and establish the tunnel. Verify in `docker compose logs -f
omnigent-runner` that the `connecting host to …` line is followed by normal operation
rather than another 403.

## What to investigate / fix

- [ ] **Confirm cause:** Check `docker compose ps` and `docker compose logs
  omnigent-server` for restart timestamps that precede the 03:34 UTC failure. If the
  server restarted, cause 1 is confirmed.
- [x] **Improve the entrypoint's error handling:** `entrypoint.sh` now captures
  `omnigent host` output, detects the "HTTP 403" message, and branches:
  - 403 → prints `ALERT:` to stderr and POSTs to `OMNIGENT_ALERT_WEBHOOK_URL` if set;
    backs off 30 s (manual action needed).
  - Other failure → original "likely not logged in yet" message + 15 s retry.
- [x] **Document re-auth runbook:** Added a gotcha to `CLAUDE.md` covering the 403
  trigger, the one-liner fix, and the invariant (never rotate the cookie secret without
  re-running `omnigent login`).
- [x] **Operator alerting:** `OMNIGENT_ALERT_WEBHOOK_URL` (optional, ntfy/Zapier/Make
  compatible) wired through `docker-compose.yml` and `.env.example`.
- [ ] **Evaluate upstream:** Upstream Omnigent (`v0.1.0`) has no headless host token;
  the runner reuses a user OIDC session. If a future upstream version introduces a
  dedicated, long-lived runner registration credential, adopt it (within ADR-0001's
  pin policy). Consider opening an upstream issue.

## Related

- `runner/entrypoint.sh` — current reconnect loop (exits non-zero → 15 s retry, no
  distinction between "never logged in" and "token rejected")
- `CLAUDE.md` gotchas — "Auth is one-time/interactive; the token persists on a named
  volume and the runner auto-reconnects on every restart thereafter." This is only true
  when the *server* has not restarted.
- ADR-0003 — runner architecture (privileged sibling, runner-net only, dials back via
  host-gateway through Caddy)
