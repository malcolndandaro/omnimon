# Google login + email allowlist (auth-on everywhere)

Status: ready-for-agent

## Parent

[PRD: Omnimon — Phase 1 Contabo Deployment](../PRD.md)

## What to build

Gate the deployment behind Google sign-in with an authorization allowlist, enabled in every environment (localhost mirrors prod). Authentication via Google OIDC is wired through, and — critically — an **authorization** gate restricts who is admitted after a successful Google login, because authenticating with Google is not by itself sufficient to enter an internet-facing runner.

Scope:
- Wire Omnigent's OIDC contract through compose/env: `OMNIGENT_OIDC_ISSUER=https://accounts.google.com`, `OMNIGENT_OIDC_CLIENT_ID`, `OMNIGENT_OIDC_CLIENT_SECRET`, `OMNIGENT_AUTH_ENABLED=1`, `OMNIGENT_ACCOUNTS_COOKIE_SECRET`, and `OMNIGENT_ACCOUNTS_BASE_URL`.
- Derive `OMNIGENT_DOMAIN`, `OMNIGENT_ACCOUNTS_BASE_URL`, and the OAuth callback (`https://<domain>/auth/callback`) from the single `OMNIMON_DOMAIN` value.
- Add the `OMNIMON_ALLOWED_EMAILS` authorization gate (default: the operator's address) and pass it through to wherever Omnigent enforces its identity allowlist, so non-allowlisted Google identities are rejected.
- Extend `.env.example` with all new variables.
- README section documenting Google Cloud OAuth client setup (issuer, client id/secret, the exact callback URL).

Auth stays on for `OMNIMON_DOMAIN=localhost` too. Single source of truth for the domain — do not introduce a second domain variable.

## Acceptance criteria

- [ ] With auth configured, an **unauthenticated** request to the app is redirected into the Google OIDC flow rather than served the app.
- [ ] The OAuth callback URL and `OMNIGENT_ACCOUNTS_BASE_URL` are derived from `OMNIMON_DOMAIN` (verified for both a real domain and `localhost`).
- [ ] An identity **on** `OMNIMON_ALLOWED_EMAILS` is admitted; an identity **not** on the list is rejected after completing Google login.
- [ ] `OMNIMON_ALLOWED_EMAILS` defaults to the operator's address and accepts additional addresses without other changes.
- [ ] Auth is enabled when `OMNIMON_DOMAIN=localhost` (localhost mirrors prod).
- [ ] **Seam 2 (config render):** the fast test additionally asserts that `OMNIMON_DOMAIN` produces the correct `OMNIGENT_ACCOUNTS_BASE_URL` and `auth/callback` URL, and that `OMNIMON_ALLOWED_EMAILS` lands where Omnigent reads it (non-empty).
- [ ] **Seam 1 (smoke):** the end-to-end test asserts the unauthenticated→OIDC redirect and that a non-allowlisted identity is rejected.
- [ ] README explains the Google Cloud OAuth client + callback setup.

## Blocked by

- [01 — Control plane runs over Caddy](./01-control-plane-over-caddy.md)
