#!/usr/bin/env bash
set -euo pipefail

# System dependencies for agents and browser tooling.
rm -f /etc/apt/apt.conf.d/docker-clean
apt-get update
apt-get install -y --no-install-recommends \
    git \
    git-lfs \
    openssh-client \
    curl \
    ca-certificates \
    unzip \
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
    python-is-python3
git lfs install --system
rm -rf /var/lib/apt/lists/*
