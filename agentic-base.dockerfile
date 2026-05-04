# syntax=docker/dockerfile:1.7
# Builder stage — agents installed here, copied to runtime stage
FROM node:24-slim AS builder

# Cache mounts make repeat builds fast
RUN --mount=type=cache,target=/root/.npm \
    npm config set update-notifier false

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

USER agent
WORKDIR /workspace
