# syntax=docker/dockerfile:1.7
# Builder stage — agents installed here, copied to runtime stage
FROM node:24-slim AS builder

# Each agent installs in its own RUN line so a single failure doesn't cascade.
RUN --mount=type=cache,target=/root/.npm \
    npm install -g @anthropic-ai/claude-code@2.1.126

# TODO: revisit OpenCode install. The bin shim at /usr/local/bin/opencode is
# a symlink in the builder; Docker's COPY --from dereferences it and writes a
# regular file in the runtime stage. The shim then uses fs.realpathSync(__filename)
# to walk up from its own directory looking for node_modules, but the resolved
# path is /usr/local/bin (no node_modules there) instead of inside
# /usr/local/lib/node_modules/opencode-ai/bin, so it can't locate the platform
# binary (opencode-linux-x64) and fails with "your package manager failed to
# install the right version". Fix: replace the COPY of /usr/local/bin/opencode
# with `RUN ln -sf ../lib/node_modules/opencode-ai/bin/opencode /usr/local/bin/opencode`.
# RUN --mount=type=cache,target=/root/.npm \
#     npm install -g opencode-ai@1.14.33

# TODO: revisit Codex install. Same root cause as OpenCode: the bin shim at
# /usr/local/bin/codex is a symlink in the builder; Docker's COPY --from
# dereferences it so the runtime gets a regular file. The shim then can't
# resolve its sibling node_modules to find @openai/codex-linux-x64 and
# fails with "Missing optional dependency". Fix: replace the COPY of
# /usr/local/bin/codex with `RUN ln -sf ../lib/node_modules/@openai/codex/bin/codex.js /usr/local/bin/codex`.
# RUN --mount=type=cache,target=/root/.npm \
#     npm install -g @openai/codex@0.128.0

# Runtime stage
FROM node:24-slim

LABEL org.opencontainers.image.title="agentic-base" \
      org.opencontainers.image.description="Local-only base image hosting Claude Code, OpenCode, Codex, and Gemini CLI for use as a devcontainer base or standalone agent host." \
      org.opencontainers.image.source="https://github.com/local/isolated-ai"

# System deps. Cache mounts on apt to keep rebuilds fast.
RUN --mount=type=cache,target=/var/cache/apt,sharing=locked \
    --mount=type=cache,target=/var/lib/apt,sharing=locked \
    rm -f /etc/apt/apt.conf.d/docker-clean \
    && apt-get update \
    && apt-get install -y --no-install-recommends \
        git \
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
    && rm -rf /var/lib/apt/lists/*

# Non-root user
RUN groupadd --gid 1001 agent \
    && useradd --uid 1001 --gid 1001 --create-home --shell /bin/bash agent \
    && mkdir -p /home/agent/.local/bin \
    && chown -R 1001:1001 /home/agent

ENV HOME=/home/agent
ENV PATH=/home/agent/.local/bin:${PATH}

# Copy global node_modules and bin shims from the builder
COPY --from=builder /usr/local/lib/node_modules /usr/local/lib/node_modules
COPY --from=builder /usr/local/bin/claude /usr/local/bin/claude
# COPY --from=builder /usr/local/bin/opencode /usr/local/bin/opencode
# COPY --from=builder /usr/local/bin/codex /usr/local/bin/codex

# Symlink agent bins into the user's local bin
RUN ln -sf /usr/local/bin/claude /home/agent/.local/bin/claude \
    && chown -h 1001:1001 /home/agent/.local/bin/claude
#    && ln -sf /usr/local/bin/opencode /home/agent/.local/bin/opencode \
#    && ln -sf /usr/local/bin/codex /home/agent/.local/bin/codex \
#    && chown -h 1001:1001 \
#       /home/agent/.local/bin/claude \
#       /home/agent/.local/bin/codex

USER agent
WORKDIR /workspace
