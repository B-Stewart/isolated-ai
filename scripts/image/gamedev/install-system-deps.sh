#!/usr/bin/env bash
set -euo pipefail

# Pass the configured .NET runtime version as the first argument.
dotnet_runtime_version="${1:?usage: install-system-deps.sh DOTNET_RUNTIME_VERSION}"

apt-get update \
    && apt-get install -y --no-install-recommends \
        xz-utils \
        "dotnet-runtime-${dotnet_runtime_version}" \
        libfontconfig1 \
        libfreetype6 \
        libgl1 \
        libice6 \
        libsm6 \
        libxinerama1 \
        libxcursor1 \
        libxi6 \
        libxfixes3 \
        libxrender1 \
        libxrandr2 \
        libxkbcommon0 \
        libwayland-client0 \
        libwayland-cursor0 \
        libwayland-egl1 \
    && rm -rf /var/lib/apt/lists/*
