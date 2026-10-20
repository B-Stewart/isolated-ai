#!/usr/bin/env bash
set -euo pipefail

# Recreate npm's global bin links after copying the package tree from the builder.
# claude.exe is the Linux launcher shipped by @anthropic-ai/claude-code.
ln -sf ../lib/node_modules/@anthropic-ai/claude-code/bin/claude.exe /usr/local/bin/claude
ln -sf ../lib/node_modules/@opencode/cli/bin/opencode.exe /usr/local/bin/opencode
ln -sf ../lib/node_modules/oh-my-opencode-slim/dist/cli/index.js /usr/local/bin/oh-my-opencode-slim
ln -sf ../lib/node_modules/@upstash/context7-mcp/dist/index.js /usr/local/bin/context7-mcp
ln -sf ../lib/node_modules/@playwright/cli/playwright-cli.js /usr/local/bin/playwright-cli
ln -sf ../lib/node_modules/agent-browser/bin/agent-browser.js /usr/local/bin/agent-browser
ln -sf ../lib/node_modules/figma-developer-mcp/dist/bin.js /usr/local/bin/figma-developer-mcp
ln -sf ../lib/node_modules/firebase-tools/lib/bin/firebase.js /usr/local/bin/firebase
ln -sf ../lib/node_modules/@colbymchenry/codegraph/npm-shim.js /usr/local/bin/codegraph

ln -sf /usr/local/bin/claude /home/agent/.local/bin/claude
ln -sf /usr/local/bin/opencode /home/agent/.local/bin/opencode
ln -sf /usr/local/bin/oh-my-opencode-slim /home/agent/.local/bin/oh-my-opencode-slim
ln -sf /usr/local/bin/context7-mcp /home/agent/.local/bin/context7-mcp
ln -sf /usr/local/bin/playwright-cli /home/agent/.local/bin/playwright-cli
ln -sf /usr/local/bin/agent-browser /home/agent/.local/bin/agent-browser
ln -sf /usr/local/bin/figma-developer-mcp /home/agent/.local/bin/figma-developer-mcp
ln -sf /usr/local/bin/firebase /home/agent/.local/bin/firebase
ln -sf /usr/local/bin/codegraph /home/agent/.local/bin/codegraph
chown -h 1000:1000 \
    /home/agent/.local/bin/claude \
    /home/agent/.local/bin/opencode \
    /home/agent/.local/bin/oh-my-opencode-slim \
    /home/agent/.local/bin/context7-mcp \
    /home/agent/.local/bin/playwright-cli \
    /home/agent/.local/bin/agent-browser \
    /home/agent/.local/bin/figma-developer-mcp \
    /home/agent/.local/bin/firebase \
    /home/agent/.local/bin/codegraph
