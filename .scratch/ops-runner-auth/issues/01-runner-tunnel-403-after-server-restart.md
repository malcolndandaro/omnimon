# Runner tunnel returns HTTP 403; runner_failed_to_start after server restart

Status: needs-triage

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
- [ ] **Improve the entrypoint's error handling:** The current `entrypoint.sh` treats
  any non-zero exit from `omnigent host` the same way (prints "likely not logged in
  yet"). A 403 should print a more actionable message: "token rejected by server —
  re-run `omnigent login`". This avoids confusion with the first-boot "never logged in"
  case.
- [ ] **Document re-auth runbook:** The `README` / `CONTEXT.md` should call out that
  a server restart invalidates the runner's session and that `omnigent login` must be
  re-run. Currently the one-time login procedure is documented but the re-auth case
  (after a server restart) is not.
- [ ] **Consider a health-check or auto-detect loop:** After N consecutive 403s the
  entrypoint could print a clearer alert (e.g., to stderr or a log file) so an operator
  watching logs can act immediately rather than diagnosing from a failed job.
- [ ] **Evaluate upstream:** Upstream Omnigent (`v0.1.0`) has no headless host token;
  the runner reuses a user OIDC session. If a future upstream version introduces a
  dedicated, long-lived runner registration credential, adopt it (within ADR-0001's
  pin policy).

## Related

- `runner/entrypoint.sh` — current reconnect loop (exits non-zero → 15 s retry, no
  distinction between "never logged in" and "token rejected")
- `CLAUDE.md` gotchas — "Auth is one-time/interactive; the token persists on a named
  volume and the runner auto-reconnects on every restart thereafter." This is only true
  when the *server* has not restarted.
- ADR-0003 — runner architecture (privileged sibling, runner-net only, dials back via
  host-gateway through Caddy)
