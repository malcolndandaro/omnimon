# Wrap upstream Omnigent via a pinned published image

Omnimon's job is *deployability*, not application logic, so it consumes upstream Omnigent as the pinned published image `ghcr.io/omnigent-ai/omnigent-server:v0.1.0` rather than forking the code or vendoring it as a git submodule and building from source. We pin a release tag (not `latest`) so a deploy is reproducible and an upstream change can't silently break a running box.

## Considered Options

- **Pinned published image (chosen)** — `cp .env.example .env && docker compose up -d`; most portable and the easiest thing for a public replicator to run. Confirmed available on GHCR (`v0.1.0`, plus `latest` and `sha-*` tags).
- **Git submodule + build from source** — always reproducible even without a published image and lets you pin an exact commit, but `git clone --recurse-submodules` + a source build is heavier and slower to replicate, which fights the "anyone can replicate easily" goal.

## Consequences

- Omnimon's compose is a thin overlay that sets env and adds the reverse proxy + runner; it never patches Omnigent. If we ever genuinely need to modify upstream behavior, this ADR must be revisited (the wrapper-only constraint is load-bearing).
- Upgrades are an explicit, reviewable bump of the pinned tag.
