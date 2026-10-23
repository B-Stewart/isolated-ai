#!/bin/bash
set -euo pipefail
root=/opt/isoai/mixins/omo
mkdir -p "$root/vendor"
/opt/isoai/bin/tooling-npm install --prefix "$root/vendor" --no-audit --no-fund oh-my-opencode-slim@3.0.5
