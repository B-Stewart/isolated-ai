# syntax=docker/dockerfile:1.7
# Builder stage — agents installed here, copied to runtime stage
FROM node:24-slim AS builder

# Each agent installs in its own RUN line so a single failure doesn't cascade.
RUN --mount=type=cache,target=/root/.npm \
    npm install -g @anthropic-ai/claude-code@latest

RUN --mount=type=cache,target=/root/.npm \
    npm install -g opencode-ai@latest

RUN --mount=type=cache,target=/root/.npm \
    npm install -g oh-my-opencode-slim@latest

RUN --mount=type=cache,target=/root/.npm \
    npm install -g @upstash/context7-mcp@latest

RUN --mount=type=cache,target=/root/.npm \
    npm install -g @playwright/cli@latest

RUN --mount=type=cache,target=/root/.npm \
    npm install -g figma-developer-mcp@latest

# Runtime stage
FROM node:24-slim

LABEL org.opencontainers.image.title="agentic-base" \
      org.opencontainers.image.description="Local-only base image hosting Claude Code and OpenCode for use as a devcontainer base or standalone agent host." \
      org.opencontainers.image.source="https://github.com/local/isolated-ai"

# System deps. Cache mounts on apt to keep rebuilds fast.
RUN --mount=type=cache,target=/var/cache/apt,sharing=locked \
    --mount=type=cache,target=/var/lib/apt,sharing=locked \
    rm -f /etc/apt/apt.conf.d/docker-clean \
    && apt-get update \
    && apt-get install -y --no-install-recommends \
        git \
        git-lfs \
        openssh-client \
        curl \
        ca-certificates \
        dnsutils \
        sudo \
        iptables \
        ipset \
        libasound2 \
        libatk-bridge2.0-0 \
        libatk1.0-0 \
        libcups2 \
        libdbus-1-3 \
        libdrm2 \
        libgbm1 \
        libglib2.0-0 \
        libgtk-3-0 \
        libnspr4 \
        libnss3 \
        libpango-1.0-0 \
        libx11-6 \
        libx11-xcb1 \
        libxcb1 \
        libxcomposite1 \
        libxdamage1 \
        libxext6 \
        libxfixes3 \
        libxkbcommon0 \
        libxrandr2 \
        libxrender1 \
        libxshmfence1 \
        libxss1 \
        libxtst6 \
        fonts-liberation \
        xdg-utils \
        python3 \
        python-is-python3 \
    && git lfs install --system \
    && rm -rf /var/lib/apt/lists/*

# Playwright browser system deps (chromium + firefox + webkit). Baked at build
# time because runtime `playwright install --with-deps` needs sudo, which the
# hardened devcontainer (no-new-privileges) deliberately blocks.
RUN --mount=type=cache,target=/var/cache/apt,sharing=locked \
    --mount=type=cache,target=/var/lib/apt,sharing=locked \
    apt-get update \
    && npx --yes playwright@latest install-deps \
    && rm -rf /var/lib/apt/lists/*

# Non-root user
# node:24-slim ships with a `node` user at UID/GID 1000 — remove it so we can
# reclaim 1000 for `agent` (matching the default Linux/WSL user UID).
RUN userdel -r node 2>/dev/null || true \
    && groupdel node 2>/dev/null || true \
    && groupadd --gid 1000 agent \
    && useradd --uid 1000 --gid 1000 --create-home --shell /bin/bash agent \
    && mkdir -p /home/agent/.local/bin \
    && chown -R 1000:1000 /home/agent

ENV HOME=/home/agent
ENV PATH=/home/agent/.local/bin:${PATH}
# Disable Claude Code's auto-updater — agent versions are pinned in this dockerfile;
# rebuild the image to pick up newer versions, don't let Claude self-update in place.
ENV DISABLE_AUTOUPDATER=1
# Disable Claude Code's auto-memory feature, because we're containerized but sharing the mounted claude settings
# our project might overlap memory with another if we don't turn this off.
ENV CLAUDE_CODE_DISABLE_AUTO_MEMORY=1

# Copy global node_modules from the builder
COPY --from=builder /usr/local/lib/node_modules /usr/local/lib/node_modules

# Agent + MCP bin shims — recreate the symlinks npm installs (COPY would dereference them and break node_modules resolution).
# claude.exe is the real Linux launcher shipped by @anthropic-ai/claude-code, not a Windows artifact.
RUN ln -sf ../lib/node_modules/@anthropic-ai/claude-code/bin/claude.exe /usr/local/bin/claude \
    && ln -sf ../lib/node_modules/opencode-ai/bin/opencode /usr/local/bin/opencode \
    && ln -sf ../lib/node_modules/oh-my-opencode-slim/dist/cli/index.js /usr/local/bin/oh-my-opencode-slim \
    && ln -sf ../lib/node_modules/@upstash/context7-mcp/dist/index.js /usr/local/bin/context7-mcp \
    && ln -sf ../lib/node_modules/@playwright/cli/playwright-cli.js /usr/local/bin/playwright-cli \
    && ln -sf ../lib/node_modules/figma-developer-mcp/dist/bin.js /usr/local/bin/figma-developer-mcp

# Symlink agent bins into the user's local bin
RUN ln -sf /usr/local/bin/claude /home/agent/.local/bin/claude \
    && ln -sf /usr/local/bin/opencode /home/agent/.local/bin/opencode \
    && ln -sf /usr/local/bin/oh-my-opencode-slim /home/agent/.local/bin/oh-my-opencode-slim \
    && ln -sf /usr/local/bin/context7-mcp /home/agent/.local/bin/context7-mcp \
    && ln -sf /usr/local/bin/playwright-cli /home/agent/.local/bin/playwright-cli \
    && ln -sf /usr/local/bin/figma-developer-mcp /home/agent/.local/bin/figma-developer-mcp \
    && chown -h 1000:1000 \
       /home/agent/.local/bin/claude \
       /home/agent/.local/bin/opencode \
       /home/agent/.local/bin/oh-my-opencode-slim \
       /home/agent/.local/bin/context7-mcp \
       /home/agent/.local/bin/playwright-cli \
       /home/agent/.local/bin/figma-developer-mcp

# Enable Corepack so `yarn` and `pnpm` shims exist on PATH. Done as root so the
# shims land in /usr/local/bin (the agent user can't write there at runtime).
# Actual package-manager binaries are fetched on demand into ~/.cache/node/corepack,
# which is user-writable, so each container can pull whatever version a project's
# `packageManager` field pins without rebuilding the image.
RUN corepack enable

# Install uv (Python tool manager). Standalone Rust binary; fetches its own
# Python on demand when projects request a specific interpreter.
RUN curl -LsSf https://astral.sh/uv/install.sh \
    | env UV_INSTALL_DIR=/usr/local/bin INSTALLER_NO_MODIFY_PATH=1 sh

# Install RTK (token-optimizing CLI proxy). Standalone Rust binary; intercepts
# bash command output, filters/dedups it before it reaches the LLM context.
# Wired into Claude via a PreToolUse hook written by `rtk init -g` (host-side
# bootstrap step in the README — the hook persists in the bind-mounted
# ~/.claude/settings.json so every container plus native Claude pick it up).
RUN curl -fsSL https://raw.githubusercontent.com/rtk-ai/rtk/refs/heads/master/install.sh \
    | env RTK_INSTALL_DIR=/usr/local/bin sh

# Python tools installed via `uv tool install` into a shared, image-baked
# location. Venvs live at /opt/uv-tools (root-owned, world-readable); shims
# land in /usr/local/bin so every user has them on PATH without modifying the
# bind-mounted home dirs. Tools are installed but NOT globally activated — the
# consumer enables them per-project (see tools table in README). Upgrade by
# rebuilding the image.
ENV UV_TOOL_DIR=/opt/uv-tools
ENV UV_TOOL_BIN_DIR=/usr/local/bin

# Graphify (PyPI: `graphifyy`, CLI: `graphify`) + spec-kit (CLI: `specify`).
# spec-kit isn't published to PyPI by the upstream maintainer (the `specify-cli`
# name on PyPI is owned by an unrelated third party), so install from git. To
# avoid pulling unstable `.devN` builds from HEAD, the latest published release
# tag is resolved from the GitHub API at build time — matches the @latest
# pattern used by the npm/uv installs above; rebuild to pick up new releases.
#
# `build-essential` + `python3-dev` are installed transiently for this RUN
# only and purged at the end — graphifyy pulls `tree-sitter-dm`, which ships
# no Linux wheels and must compile its C extension against Python.h at install
# time. The compiled .so lives inside the venv, so neither the C toolchain
# nor the dev headers are needed at runtime; system `python3` (already
# installed above) remains for the venvs to link against.
RUN --mount=type=cache,target=/var/cache/apt,sharing=locked \
    --mount=type=cache,target=/var/lib/apt,sharing=locked \
    --mount=type=cache,target=/root/.cache/uv \
    apt-get update \
    && apt-get install -y --no-install-recommends build-essential python3-dev \
    && uv tool install graphifyy \
    && SPEC_KIT_TAG=$(curl -fsSL https://api.github.com/repos/github/spec-kit/releases/latest \
        | grep -m1 '"tag_name"' | cut -d'"' -f4) \
    && [ -n "$SPEC_KIT_TAG" ] \
    && uv tool install specify-cli \
        --from "git+https://github.com/github/spec-kit.git@${SPEC_KIT_TAG}" \
    && apt-get purge -y --auto-remove build-essential python3-dev \
    && rm -rf /var/lib/apt/lists/*

# Pre-create the Playwright browser cache dir. Kept as a named volume in the
# consumer devcontainer (browsers are bulky and not user-edited), so image-side
# ownership/perms must exist as 1000:1000 for Docker's volume init to honor them.
# Agent config dirs (~/.claude, ~/.config/opencode, ~/.local/share/opencode) are
# intentionally NOT pre-created here — they're bind-mounted from the host so
# config and auth state live alongside the user's native CLI installs.
RUN mkdir -p /home/agent/.cache/ms-playwright \
    && chown -R 1000:1000 /home/agent/.cache

# Firewall script — root-owned, executable, dormant unless invoked
COPY init-firewall.sh /usr/local/bin/init-firewall.sh
RUN chown root:root /usr/local/bin/init-firewall.sh \
    && chmod 0755 /usr/local/bin/init-firewall.sh

# Allow agent to run only the firewall script via sudo without password
RUN echo 'agent ALL=(root) NOPASSWD: /usr/local/bin/init-firewall.sh' \
    > /etc/sudoers.d/agent-firewall \
    && chmod 0440 /etc/sudoers.d/agent-firewall

# Docker CLI + Compose v2 plugin for docker-outside-of-docker (DooD). No daemon
# runs in this image — the container talks to the host daemon via a mounted
# /var/run/docker.sock (see the devcontainer.json that consumes this image).
#
# DOCKER_GID controls the gid of the in-image `docker` group. It must match the
# gid that owns the socket as it appears INSIDE the container. On Docker Desktop
# (Windows/Mac) that's typically 0 (root) — Desktop relaxes the socket perms so
# membership often isn't even required — but on a Linux host with native Docker
# it's whatever the host's docker group gid is (commonly 999 or 998). Override
# at build time if your host disagrees: `docker build --build-arg DOCKER_GID=998 …`.
ARG DOCKER_GID=999
RUN --mount=type=cache,target=/var/cache/apt,sharing=locked \
    --mount=type=cache,target=/var/lib/apt,sharing=locked \
    install -m 0755 -d /etc/apt/keyrings \
    && curl -fsSL https://download.docker.com/linux/debian/gpg \
        -o /etc/apt/keyrings/docker.asc \
    && chmod a+r /etc/apt/keyrings/docker.asc \
    && echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/debian $(. /etc/os-release && echo $VERSION_CODENAME) stable" \
        > /etc/apt/sources.list.d/docker.list \
    && apt-get update \
    && apt-get install -y --no-install-recommends \
        docker-ce-cli \
        docker-compose-plugin \
        docker-buildx-plugin \
    && rm -rf /var/lib/apt/lists/* \
    && ( groupadd --gid ${DOCKER_GID} docker 2>/dev/null \
         || groupadd docker ) \
    && usermod -aG docker agent

USER agent
WORKDIR /workspace
