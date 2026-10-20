#!/usr/bin/env bash
set -euo pipefail

# Bake browser system libraries because runtime --with-deps needs sudo, which
# the hardened devcontainer deliberately blocks.
apt-get update
npx --yes playwright@1 install-deps
rm -rf /var/lib/apt/lists/*
