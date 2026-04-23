# Build stage
FROM node:24-slim AS builder
# Pin version for reproducible builds; update intentionally
RUN npm install -g @anthropic-ai/claude-code@latest

# Runtime stage
FROM node:24-slim

LABEL org.opencontainers.image.title="isolated-claude" \
      org.opencontainers.image.description="Isolated Claude Code session with mounted working directory"

# Install common tooling for development sessions
RUN apt-get update && apt-get install -y --no-install-recommends \
      git \
      python3 \
      python3-pip \
      ca-certificates \
      curl \
    && rm -rf /var/lib/apt/lists/*

COPY --from=builder /usr/local/lib/node_modules /usr/local/lib/node_modules
COPY --from=builder /usr/local/bin/claude /usr/local/bin/claude

RUN useradd -m -u 1001 -s /bin/bash claude \
      && mkdir -p /home/claude/.claude /home/claude/.local/bin \
      && ln -sf /usr/local/bin/claude /home/claude/.local/bin/claude \
      && ln -sf /home/claude/.claude/.claude.json /home/claude/.claude.json \
      && chown -R 1001:1001 /home/claude

ENV HOME=/home/claude
ENV PATH=/home/claude/.local/bin:${PATH}

USER claude
WORKDIR /workspace

# --dangerously-skip-permissions is appropriate here because the container
# is the isolation boundary — Claude shouldn't need to prompt for every file op.
ENTRYPOINT ["claude"]
CMD ["--dangerously-skip-permissions"]