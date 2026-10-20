#!/usr/bin/env bash
set -euo pipefail

# Keep browser/cache files under agent's home for the Dockerfile's ownership pass.
HOME=/home/agent XDG_CACHE_HOME=/home/agent/.cache agent-browser install --with-deps
