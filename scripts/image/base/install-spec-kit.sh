#!/usr/bin/env bash
set -euo pipefail

# Interface: SPEC_KIT_TAG (passed by the Dockerfile).
spec_kit_tag=$1
uv tool install specify-cli \
    --from "git+https://github.com/github/spec-kit.git@${spec_kit_tag}"
