#!/usr/bin/env bash
set -euo pipefail

# Interface: DOCKER_GID (passed by the Dockerfile).
docker_gid=$1

# Resolve the newest stable v1 release. The bounded tag glob avoids GitHub API
# pagination and prevents selecting a release outside the supported major.
rtk_version=$(
    git ls-remote --tags --refs https://github.com/rtk-ai/rtk.git 'refs/tags/v1.*' \
        | cut -f2 | sed 's#refs/tags/##' | grep -E '^v1\.[0-9]+\.[0-9]+$' | sort -V | tail -n1
)

# RTK's installer is served from master; RTK_VERSION selects its release.
curl -fsSL https://raw.githubusercontent.com/rtk-ai/rtk/refs/heads/master/install.sh \
    | env RTK_INSTALL_DIR=/usr/local/bin RTK_VERSION="${rtk_version}" sh

# Trivy from Aqua Security's official APT repository.
install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://aquasecurity.github.io/trivy-repo/deb/public.key \
    -o /etc/apt/keyrings/trivy.asc
chmod a+r /etc/apt/keyrings/trivy.asc
echo "deb [signed-by=/etc/apt/keyrings/trivy.asc] https://aquasecurity.github.io/trivy-repo/deb generic main" \
    > /etc/apt/sources.list.d/trivy.list
apt-get update
apt-get install -y --no-install-recommends 'trivy=0.*'
rm -rf /var/lib/apt/lists/*

# GitHub CLI. Auth/config live in the bind-mounted ~/.config/gh.
install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg \
    -o /etc/apt/keyrings/githubcli-archive-keyring.gpg
chmod a+r /etc/apt/keyrings/githubcli-archive-keyring.gpg
echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" \
    > /etc/apt/sources.list.d/github-cli.list
apt-get update
apt-get install -y --no-install-recommends 'gh=2.*'
rm -rf /var/lib/apt/lists/*

# Docker CLI and Compose plugin for docker-outside-of-docker. No daemon runs
# in this image; the in-image group must match the mounted socket's gid.
install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/debian/gpg \
    -o /etc/apt/keyrings/docker.asc
chmod a+r /etc/apt/keyrings/docker.asc
echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/debian $(. /etc/os-release && echo $VERSION_CODENAME) stable" \
    > /etc/apt/sources.list.d/docker.list
apt-get update
apt-get install -y --no-install-recommends \
    'docker-ce-cli=5:29.*' \
    'docker-compose-plugin=5.*' \
    'docker-buildx-plugin=0.*'
rm -rf /var/lib/apt/lists/*
if ! groupadd --gid "${docker_gid}" docker 2>/dev/null; then
    groupadd docker
fi
usermod -aG docker agent
