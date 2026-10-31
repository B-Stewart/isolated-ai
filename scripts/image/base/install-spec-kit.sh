#!/usr/bin/env bash
set -euo pipefail

# Follow https://github.com/github/spec-kit/blob/main/docs/install/pypi.md.
# Bound the major version to avoid unreviewed breaking upgrades.
uv tool install 'specify-cli>=1,<2'
