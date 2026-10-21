ARG BASE_IMAGE=braydens/agentic-base:latest
FROM ${BASE_IMAGE}

USER root

# Sandbox commands may need passwordless sudo for ordinary guest-local setup.
RUN printf '%s\n' 'agent ALL=(ALL) NOPASSWD: ALL' > /etc/sudoers.d/agent-sandbox \
    && chmod 0440 /etc/sudoers.d/agent-sandbox \
    && printf '%s\n' 'Defaults:agent env_keep += "HTTP_PROXY HTTPS_PROXY NO_PROXY http_proxy https_proxy no_proxy"' \
       > /etc/sudoers.d/agent-proxy-env \
    && chmod 0440 /etc/sudoers.d/agent-proxy-env \
    && touch /etc/sandbox-persistent.sh \
    && chown root:root /etc/sandbox-persistent.sh \
    && chmod 0644 /etc/sandbox-persistent.sh \
    && chown -R 1000:1000 /home/agent

ENV BASH_ENV=/etc/sandbox-persistent.sh
USER agent
WORKDIR /workspace
