# syntax=docker/dockerfile:1.7
# Builder stage — agents installed here, copied to runtime stage
FROM node:24-slim AS builder

# Each agent installs in its own RUN line so a single failure doesn't cascade.
RUN --mount=type=cache,target=/root/.npm \
    npm install -g @anthropic-ai/claude-code@2.1.126

RUN --mount=type=cache,target=/root/.npm \
    npm install -g opencode-ai@1.14.33

RUN --mount=type=cache,target=/root/.npm \
    npm install -g @openai/codex@0.128.0

RUN --mount=type=cache,target=/root/.npm \
    npm install -g @google/gemini-cli@0.40.1

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

# Copy global node_modules from the builder
COPY --from=builder /usr/local/lib/node_modules /usr/local/lib/node_modules

# Agent bin shims — recreate the symlinks npm installs (COPY would dereference them and break node_modules resolution).
# claude.exe is the real Linux launcher shipped by @anthropic-ai/claude-code, not a Windows artifact.
RUN ln -sf ../lib/node_modules/@anthropic-ai/claude-code/bin/claude.exe /usr/local/bin/claude \
    && ln -sf ../lib/node_modules/opencode-ai/bin/opencode /usr/local/bin/opencode \
    && ln -sf ../lib/node_modules/@openai/codex/bin/codex.js /usr/local/bin/codex \
    && ln -sf ../lib/node_modules/@google/gemini-cli/bundle/gemini.js /usr/local/bin/gemini

# Symlink agent bins into the user's local bin
RUN ln -sf /usr/local/bin/claude /home/agent/.local/bin/claude \
    && ln -sf /usr/local/bin/opencode /home/agent/.local/bin/opencode \
    && ln -sf /usr/local/bin/codex /home/agent/.local/bin/codex \
    && ln -sf /usr/local/bin/gemini /home/agent/.local/bin/gemini \
    && chown -h 1001:1001 \
       /home/agent/.local/bin/claude \
       /home/agent/.local/bin/opencode \
       /home/agent/.local/bin/codex \
       /home/agent/.local/bin/gemini

# Pre-create config dirs for the agents and Playwright. Docker's named-volume init
# copies image-side ownership/perms into a fresh volume on first mount, so these
# dirs must exist as 1001:1001 in the image — otherwise the volumes would be
# created root-owned and the agent user couldn't write to them.
RUN mkdir -p \
        /home/agent/.claude \
        /home/agent/.local/share/opencode \
        /home/agent/.codex \
        /home/agent/.gemini \
        /home/agent/.cache/ms-playwright \
    && chown -R 1001:1001 /home/agent/.claude /home/agent/.local /home/agent/.codex /home/agent/.gemini /home/agent/.cache

# Firewall script — root-owned, executable, dormant unless invoked
COPY init-firewall.sh /usr/local/bin/init-firewall.sh
RUN chown root:root /usr/local/bin/init-firewall.sh \
    && chmod 0755 /usr/local/bin/init-firewall.sh

# Allow agent to run only the firewall script via sudo without password
RUN echo 'agent ALL=(root) NOPASSWD: /usr/local/bin/init-firewall.sh' \
    > /etc/sudoers.d/agent-firewall \
    && chmod 0440 /etc/sudoers.d/agent-firewall

USER agent
WORKDIR /workspace
