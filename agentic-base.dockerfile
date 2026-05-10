# syntax=docker/dockerfile:1.7
# Builder stage — agents installed here, copied to runtime stage
FROM node:24-slim AS builder

# Each agent installs in its own RUN line so a single failure doesn't cascade.
RUN --mount=type=cache,target=/root/.npm \
    npm install -g @anthropic-ai/claude-code@latest

RUN --mount=type=cache,target=/root/.npm \
    npm install -g opencode-ai@latest

RUN --mount=type=cache,target=/root/.npm \
    npm install -g @openai/codex@latest

RUN --mount=type=cache,target=/root/.npm \
    npm install -g @google/gemini-cli@latest

RUN --mount=type=cache,target=/root/.npm \
    npm install -g @upstash/context7-mcp@latest

RUN --mount=type=cache,target=/root/.npm \
    npm install -g @playwright/mcp@latest

RUN --mount=type=cache,target=/root/.npm \
    npm install -g figma-developer-mcp@latest

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
        git-lfs \
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

# Non-root user
RUN groupadd --gid 1001 agent \
    && useradd --uid 1001 --gid 1001 --create-home --shell /bin/bash agent \
    && mkdir -p /home/agent/.local/bin \
    && chown -R 1001:1001 /home/agent

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
    && ln -sf ../lib/node_modules/@openai/codex/bin/codex.js /usr/local/bin/codex \
    && ln -sf ../lib/node_modules/@google/gemini-cli/bundle/gemini.js /usr/local/bin/gemini \
    && ln -sf ../lib/node_modules/@upstash/context7-mcp/dist/index.js /usr/local/bin/context7-mcp \
    && ln -sf ../lib/node_modules/@playwright/mcp/cli.js /usr/local/bin/playwright-mcp \
    && ln -sf ../lib/node_modules/figma-developer-mcp/dist/bin.js /usr/local/bin/figma-developer-mcp

# Symlink agent bins into the user's local bin
RUN ln -sf /usr/local/bin/claude /home/agent/.local/bin/claude \
    && ln -sf /usr/local/bin/opencode /home/agent/.local/bin/opencode \
    && ln -sf /usr/local/bin/codex /home/agent/.local/bin/codex \
    && ln -sf /usr/local/bin/gemini /home/agent/.local/bin/gemini \
    && ln -sf /usr/local/bin/context7-mcp /home/agent/.local/bin/context7-mcp \
    && ln -sf /usr/local/bin/playwright-mcp /home/agent/.local/bin/playwright-mcp \
    && ln -sf /usr/local/bin/figma-developer-mcp /home/agent/.local/bin/figma-developer-mcp \
    && ln -sf /usr/local/bin/serena /home/agent/.local/bin/serena \
    && chown -h 1001:1001 \
       /home/agent/.local/bin/claude \
       /home/agent/.local/bin/opencode \
       /home/agent/.local/bin/codex \
       /home/agent/.local/bin/gemini \
       /home/agent/.local/bin/context7-mcp \
       /home/agent/.local/bin/playwright-mcp \
       /home/agent/.local/bin/figma-developer-mcp \
       /home/agent/.local/bin/serena

# Install uv (Python tool manager) and serena (uv-installed MCP server). uv is a
# standalone Rust binary so we don't need a Python interpreter at this layer; uv
# fetches its own Python when serena's tool install asks for 3.13.
RUN curl -LsSf https://astral.sh/uv/install.sh \
    | env UV_INSTALL_DIR=/usr/local/bin INSTALLER_NO_MODIFY_PATH=1 sh \
    && UV_TOOL_BIN_DIR=/usr/local/bin UV_TOOL_DIR=/usr/local/uv-tools \
       uv tool install -p 3.13 serena-agent@1.2.0 --prerelease=allow

# Pre-create config dirs for the agents and Playwright. Docker's named-volume init
# copies image-side ownership/perms into a fresh volume on first mount, so these
# dirs must exist as 1001:1001 in the image — otherwise the volumes would be
# created root-owned and the agent user couldn't write to them.
RUN mkdir -p \
        /home/agent/.claude \
        /home/agent/.config/opencode \
        /home/agent/.local/share/opencode \
        /home/agent/.codex \
        /home/agent/.gemini \
        /home/agent/.cache/ms-playwright \
    && chown -R 1001:1001 /home/agent/.claude /home/agent/.config /home/agent/.local /home/agent/.codex /home/agent/.gemini /home/agent/.cache

# ~/.claude.json (project manifest, MCP servers, recent projects) lives at home root,
# NOT inside ~/.claude/. Symlinking it into the .claude dir makes writes land in the
# claude-auth volume so MCP registrations and project state persist across rebuilds.
# Claude resolves the symlink at runtime; the target lives inside the mounted volume.
RUN ln -sf /home/agent/.claude/.claude.json /home/agent/.claude.json \
    && chown -h 1001:1001 /home/agent/.claude.json

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
