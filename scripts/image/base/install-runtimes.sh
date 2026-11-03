#!/usr/bin/env bash
set -euo pipefail

# Resolve the newest stable release within each supported major/minor channel.
# Bounded tag globs avoid GitHub API pagination and never drift to another major.
uv_version=$(
    git ls-remote --tags --refs https://github.com/astral-sh/uv.git 'refs/tags/0.*' \
        | cut -f2 | sed 's#refs/tags/##' | grep -E '^0\.[0-9]+\.[0-9]+$' | sort -V | tail -n1
)
bun_version=$(
    git ls-remote --tags --refs https://github.com/oven-sh/bun.git 'refs/tags/bun-v1.*' \
        | cut -f2 | sed 's#refs/tags/##' | grep -E '^bun-v1\.[0-9]+\.[0-9]+$' | sort -V | tail -n1
)

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
apt-get install -y --no-install-recommends dotnet-sdk-10.0
rm -rf /var/lib/apt/lists/*

# Bun is required by oh-my-opencode-slim's CLI and is installed in PATH.
curl -fsSL https://bun.sh/install \
    | env BUN_INSTALL=/usr/local bash -s -- "${bun_version}"
