# syntax=docker/dockerfile:1.7
# Builder stage — agents installed here, copied to runtime stage
FROM node:24-slim AS builder

# Each install stays a separate command in the build-only installer script.
RUN --mount=type=bind,source=scripts/image/base/install-npm-tools.sh,target=/tmp/install-npm-tools.sh,ro \
    --mount=type=cache,target=/root/.npm \
    bash /tmp/install-npm-tools.sh

# Runtime stage
FROM node:24-slim

LABEL org.opencontainers.image.title="agentic-base" \
      org.opencontainers.image.description="Local-only base image hosting Claude Code and OpenCode for use as a devcontainer base or standalone agent host." \
      org.opencontainers.image.source="https://github.com/local/isolated-ai"

# System deps. Cache mounts on apt to keep rebuilds fast.
RUN --mount=type=bind,source=scripts/image/base/install-system-deps.sh,target=/tmp/install-system-deps.sh,ro \
    --mount=type=cache,target=/var/cache/apt,sharing=locked \
    --mount=type=cache,target=/var/lib/apt,sharing=locked \
    bash /tmp/install-system-deps.sh

# Playwright browser system deps (chromium + firefox + webkit). Baked at build
# time because runtime `playwright install --with-deps` needs sudo, which the
# hardened devcontainer (no-new-privileges) deliberately blocks.
RUN --mount=type=bind,source=scripts/image/base/install-playwright-deps.sh,target=/tmp/install-playwright-deps.sh,ro \
    --mount=type=cache,target=/var/cache/apt,sharing=locked \
    --mount=type=cache,target=/var/lib/apt,sharing=locked \
    bash /tmp/install-playwright-deps.sh

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
# Disable Claude Code's auto-updater — agent selectors are in the build-only
# npm installer script; rebuild the image to pick up updates.
ENV DISABLE_AUTOUPDATER=1
# Disable Claude Code's auto-memory feature, because we're containerized but sharing the mounted claude settings
# our project might overlap memory with another if we don't turn this off.
ENV CLAUDE_CODE_DISABLE_AUTO_MEMORY=1

# Disable opencode's auto updates
ENV OPENCODE_DISABLE_AUTOUPDATE=1

# Environment variables for opencode slim
ENV OPENCODE_EXPERIMENTAL_BACKGROUND_SUBAGENTS=true 
ENV OPENCODE_ENABLE_EXA=1

# Disable astro telemetry because it tries to write to a config it doesn't have access to 
ENV ASTRO_TELEMETRY_DISABLED=1

# Keep codegraph local/non-daemonized by default inside short-lived containers.
ENV CODEGRAPH_TELEMETRY=0
ENV DO_NOT_TRACK=1
ENV CODEGRAPH_NO_DAEMON=1

# Copy global node_modules from the builder
COPY --from=builder /usr/local/lib/node_modules /usr/local/lib/node_modules

RUN --mount=type=bind,source=scripts/image/base/link-agent-tools.sh,target=/tmp/link-agent-tools.sh,ro \
    bash /tmp/link-agent-tools.sh

# Installer version arguments are passed explicitly to the build-only scripts.
ARG UV_VERSION=0.13.3
ARG DOTNET_VERSION=10.0
ARG BUN_VERSION=1.4.3
ARG RTK_VERSION=v1.0.1
ARG SPEC_KIT_TAG=v0.10.2
# Match this group id to the mounted Docker socket on native Linux hosts.
ARG DOCKER_GID=999

# Corepack, uv, .NET SDK, and Bun. Project packageManager choices remain
# project-controlled; standalone installer versions come from these build args.
RUN --mount=type=bind,source=scripts/image/base/install-runtimes.sh,target=/tmp/install-runtimes.sh,ro \
    --mount=type=cache,target=/var/cache/apt,sharing=locked \
    --mount=type=cache,target=/var/lib/apt,sharing=locked \
    bash /tmp/install-runtimes.sh "${UV_VERSION}" "${DOTNET_VERSION}" "${BUN_VERSION}"

# RTK, Trivy, GitHub CLI, and Docker CLI/Compose tools.
RUN --mount=type=bind,source=scripts/image/base/install-cli-tools.sh,target=/tmp/install-cli-tools.sh,ro \
    --mount=type=cache,target=/var/cache/apt,sharing=locked \
    --mount=type=cache,target=/var/lib/apt,sharing=locked \
    bash /tmp/install-cli-tools.sh "${RTK_VERSION}" "${DOCKER_GID}"

# Python tools installed via `uv tool install` into a shared, image-baked
# location. Venvs live at /opt/uv-tools (root-owned, world-readable); shims
# land in /usr/local/bin so every user has them on PATH without modifying the
# bind-mounted home dirs. Tools are installed but NOT globally activated — the
# consumer enables them per-project (see tools table in README). Upgrade by
# rebuilding the image.
ENV UV_TOOL_DIR=/opt/uv-tools
ENV UV_TOOL_BIN_DIR=/usr/local/bin

# spec-kit (CLI: `specify`).
# spec-kit isn't published to PyPI by the upstream maintainer (the `specify-cli`
# name on PyPI is owned by an unrelated third party), so install from git at a
# pinned tag. Previously this resolved the latest tag dynamically via the GitHub
# API, but `api.github.com` rate-limits/blocks anonymous build-time calls,
# bricking the build. Bump SPEC_KIT_TAG manually when a new release is wanted —
# see https://github.com/github/spec-kit/releases.
RUN --mount=type=bind,source=scripts/image/base/install-spec-kit.sh,target=/tmp/install-spec-kit.sh,ro \
    --mount=type=cache,target=/root/.cache/uv \
    bash /tmp/install-spec-kit.sh "${SPEC_KIT_TAG}"

# Bake agent-browser's Chrome for Testing download and Linux dependencies into
# the image. HOME/XDG_CACHE_HOME keep its browser and runtime state under the
# non-root user's home; the final ownership pass below makes the files writable.
RUN --mount=type=bind,source=scripts/image/base/install-agent-browser.sh,target=/tmp/install-agent-browser.sh,ro \
    --mount=type=cache,target=/var/cache/apt,sharing=locked \
    --mount=type=cache,target=/var/lib/apt,sharing=locked \
    bash /tmp/install-agent-browser.sh

# Pre-create the Playwright browser cache dir. Kept as a named volume in the
# consumer devcontainer (browsers are bulky and not user-edited), so image-side
# ownership/perms must exist as 1000:1000 for Docker's volume init to honor them.
# Agent config dirs (~/.claude, ~/.config/opencode, ~/.local/share/opencode) are
# intentionally NOT pre-created here — they're bind-mounted from the host so
# config and auth state live alongside the user's native CLI installs.
RUN mkdir -p /home/agent/.cache/ms-playwright \
    && chown -R 1000:1000 /home/agent/.cache

# Disable Playwright's stale-browser garbage collection. By default `playwright
# install` deletes browser revisions not referenced by the *current* package
# version — which silently wipes other projects' browsers out of the shared
# `isolated-pw-browsers` cache volume whenever a project on a newer Playwright
# version installs. With GC off, installs only add revisions; cleanup is manual
# (`npx playwright uninstall --all` from inside a container) when desired.
ENV PLAYWRIGHT_SKIP_BROWSER_GC=1

# Firewall script — root-owned, executable, dormant unless invoked
COPY init-firewall.sh /usr/local/bin/init-firewall.sh
RUN chown root:root /usr/local/bin/init-firewall.sh \
    && chmod 0755 /usr/local/bin/init-firewall.sh

# Allow agent to run only the firewall script via sudo without password
RUN echo 'agent ALL=(root) NOPASSWD: /usr/local/bin/init-firewall.sh' \
    > /etc/sudoers.d/agent-firewall \
    && chmod 0440 /etc/sudoers.d/agent-firewall

# Some root-run installers write into $HOME; hand ownership back before dropping
# privileges so standalone runs can create config/state under /home/agent.
RUN chown -R 1000:1000 /home/agent

USER agent
WORKDIR /workspace
