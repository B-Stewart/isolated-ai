#!/usr/bin/env bash
set -euo pipefail

# Interface: UV_VERSION DOTNET_VERSION BUN_VERSION (passed by the Dockerfile).
uv_version=$1
dotnet_version=$2
bun_version=$3

# Enable Corepack shims in /usr/local/bin; project versions remain controlled
# by each packageManager field and are fetched into the user's writable cache.
corepack enable

curl -LsSf "https://astral.sh/uv/${uv_version}/install.sh" \
    | env UV_INSTALL_DIR=/usr/local/bin INSTALLER_NO_MODIFY_PATH=1 sh

# Install .NET SDK from Microsoft's repository for the base image's Debian.
. /etc/os-release
case "${ID}:${VERSION_ID}" in
    debian:12|debian:13) ;;
    *) echo "ERROR: .NET SDK installation requires Debian 12 or 13 (found ${ID} ${VERSION_ID})" >&2; exit 1 ;;
esac
curl -fsSL "https://packages.microsoft.com/config/debian/${VERSION_ID}/packages-microsoft-prod.deb" \
    -o /tmp/packages-microsoft-prod.deb
dpkg -i /tmp/packages-microsoft-prod.deb
rm -f /tmp/packages-microsoft-prod.deb
apt-get update
apt-get install -y --no-install-recommends "dotnet-sdk-${dotnet_version}"
rm -rf /var/lib/apt/lists/*

# Bun is required by oh-my-opencode-slim's CLI and is installed in PATH.
curl -fsSL https://bun.sh/install \
    | env BUN_INSTALL=/usr/local bash -s -- "bun-v${bun_version}"
