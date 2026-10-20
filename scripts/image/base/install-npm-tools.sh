#!/usr/bin/env bash
set -euo pipefail

# Keep installs separate so a package failure is isolated to its own command.
npm install -g @anthropic-ai/claude-code@2
npm install -g @opencode/cli@2
npm install -g oh-my-opencode-slim@3
npm install -g @upstash/context7-mcp@4
npm install -g @playwright/cli@0
npm install -g agent-browser@0
npm install -g figma-developer-mcp@0
npm install -g firebase-tools@15
npm install -g @colbymchenry/codegraph@1
