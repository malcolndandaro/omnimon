# Execution runs in a privileged sibling runner container

Omnigent's control plane (server + UI) cannot execute agent sessions by itself; it needs a registered Host running `omnigent host`, and on Linux every agent terminal is sandboxed with bubblewrap (`bwrap`), which upstream treats as mandatory. Omnimon runs that Host as a **dedicated, privileged, network-isolated sibling container** in the same compose (Node 22 + tmux + Claude Code + bwrap) — not Docker-in-Docker, and not a native systemd host. Agents are sandboxed with bwrap *inside* this one container.

## Considered Options

- **Privileged sibling runner container (chosen)** — keeps everything in Docker and portable, matches the "containerize the services" preference, and gives a clean blast-radius boundary (its own container, its own network, away from other workloads). bwrap needs elevated privileges (user namespaces / `CAP_SYS_ADMIN`, realistically `--privileged`) to run inside a container, so the container is privileged by necessity.
- **Native host on the VM (systemd)** — bwrap gets real kernel namespaces with no privileged container, the cleanest isolation, but mixes Docker + native and diverges from the all-Docker goal.
- **Managed cloud sandboxes (Modal/E2B/Daytona/…)** — no local host and no bwrap headaches, but adds a third-party provider plus per-run cost and isn't self-contained on your own VM.

## Consequences

- The runner container is privileged: an agent that escapes bwrap is then inside a near-root container. This is accepted for a **single-tenant** box the operator controls; it is documented loudly in the public repo so replicators understand what `--privileged` enables. Isolation is bounded by running the runner on its own Docker network, separate from any other workload.
- bwrap stays enabled (we do **not** disable it and treat the container as the sandbox), because disabling it would mean deviating from / patching upstream, violating the wrapper-only constraint (see ADR-0001).
- Authorization must be gated (single-user email allowlist) precisely because this privileged runner is reachable behind an internet-facing login.
