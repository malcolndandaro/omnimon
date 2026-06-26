# Omnimon runner (Omnigent Host) — executes agent sessions.
#
# Ships the native-harness toolchain Omnigent requires on a Linux host:
# Node 22 (Claude Code / agent CLIs), tmux (native wrappers), bubblewrap
# (mandatory agent sandbox), and the `omnigent` CLI.
#
# Tools are installed OUTSIDE $HOME on purpose: $HOME is a persisted volume
# (it holds the one-time login tokens), so a fresh volume must not hide the
# installed binaries.
FROM node:22-bookworm

# OS dependencies for the native harness.
RUN apt-get update && apt-get install -y --no-install-recommends \
        bubblewrap \
        tmux \
        git \
        curl \
        ca-certificates \
    && rm -rf /var/lib/apt/lists/*

# GitHub CLI — lets agents use `gh` and authenticates plain `git` (via
# `gh auth setup-git`) when GH_TOKEN is provided.
RUN curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg \
        -o /usr/share/keyrings/githubcli-archive-keyring.gpg \
    && chmod go+r /usr/share/keyrings/githubcli-archive-keyring.gpg \
    && echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" \
        > /etc/apt/sources.list.d/github-cli.list \
    && apt-get update && apt-get install -y --no-install-recommends gh \
    && rm -rf /var/lib/apt/lists/*

# The harness: Claude Code (installed globally, lives under /usr/local).
RUN npm install -g @anthropic-ai/claude-code

# uv + the omnigent CLI. Everything goes to system paths (/usr/local, /opt)
# so the persisted $HOME volume can't shadow it. uv brings its own Python 3.12.
ENV UV_INSTALL_DIR=/usr/local/bin \
    UV_TOOL_DIR=/opt/uv/tools \
    UV_TOOL_BIN_DIR=/usr/local/bin \
    UV_PYTHON_INSTALL_DIR=/opt/uv/python \
    INSTALLER_NO_MODIFY_PATH=1
RUN curl -LsSf https://astral.sh/uv/install.sh | sh \
    && uv tool install --python 3.12 omnigent

# Unprivileged in-container user (bubblewrap runs fine unprivileged; Claude
# Code dislikes running as root). $HOME is mounted as a named volume at runtime.
# UID is pinned to 1001 (NOT 1000 — the node base image already owns 1000 as
# the `node` user). Host bind mounts for this user (./workspace, ./claude) must
# therefore be group-owned by gid 1001, not 1000 — see the CLAUDE.md gotcha.
RUN useradd --create-home --home-dir /home/omni --shell /bin/bash --uid 1001 omni

COPY entrypoint.sh /usr/local/bin/omnimon-runner-entrypoint.sh
RUN chmod +x /usr/local/bin/omnimon-runner-entrypoint.sh

USER omni
ENV HOME=/home/omni
WORKDIR /home/omni

ENTRYPOINT ["/usr/local/bin/omnimon-runner-entrypoint.sh"]
