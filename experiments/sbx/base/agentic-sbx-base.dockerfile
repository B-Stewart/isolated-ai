FROM debian:bookworm-slim

ARG BUN_VERSION=1.4.3
ARG BUN_SHA256=3e730528d89775f03f87f05c06787c4df4099d0a37f3f252e7b829cb23816e18
ARG MISE_VERSION=2026.10.17
ARG MISE_SHA256=17565e268c5542d8ce944321e17af81e0b741b65af4aa7e8e010ee77376a4aa3
ARG NODE_VERSION=24.22.1

ENV DEBIAN_FRONTEND=noninteractive \
    MISE_DATA_DIR=/opt/isoai/mise \
    MISE_CONFIG_DIR=/etc/isoai/mise \
    MISE_STATE_DIR=/var/lib/isoai/mise \
    PATH=/opt/isoai/mise/shims:/opt/isoai/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin

COPY base/install-base.sh /opt/isoai/install-base.sh
RUN /bin/bash /opt/isoai/install-base.sh "$BUN_VERSION" "$BUN_SHA256" "$MISE_VERSION" "$MISE_SHA256" "$NODE_VERSION" \
    && rm /opt/isoai/install-base.sh

COPY runtime/ /opt/isoai/runtime/
COPY base/bash-env /etc/isoai/bash_env
RUN chmod 0755 /opt/isoai/runtime/launch-opencode /opt/isoai/runtime/assemble-opencode.mjs \
    && useradd --uid 1000 --create-home --shell /bin/bash agent \
    && mkdir -p /home/agent/.config/opencode /opt/isoai/opencode/fragments.d /opt/isoai/opencode/bin \
    && printf '%s\n' 'Defaults env_keep += "http_proxy https_proxy ftp_proxy all_proxy no_proxy HTTP_PROXY HTTPS_PROXY FTP_PROXY ALL_PROXY NO_PROXY"' > /etc/sudoers.d/isoai-proxy \
    && printf '%s\n' 'agent ALL=(ALL) NOPASSWD:ALL' > /etc/sudoers.d/agent \
    && chmod 0440 /etc/sudoers.d/isoai-proxy /etc/sudoers.d/agent \
    && chown -R agent:agent /home/agent /opt/isoai/mise /etc/isoai/mise /var/lib/isoai/mise

COPY runtime/opencode-base.json /opt/isoai/opencode/base.json
ENV HOME=/home/agent \
    BASH_ENV=/etc/isoai/bash_env
USER agent
RUN test -w "$MISE_DATA_DIR" \
    && test -w "$MISE_CONFIG_DIR" \
    && test -w "$MISE_STATE_DIR" \
    && test "$(node --version)" = "v${NODE_VERSION}" \
    && tooling-node --version \
    && tooling-npm --version \
    && test "$(mise where node)" = "$MISE_DATA_DIR/installs/node/${NODE_VERSION}"
WORKDIR /workspace
ENTRYPOINT ["/usr/bin/tini", "--"]
CMD ["bash"]
