ARG BASE_IMAGE=local/isoai-sbx-base:scaffold
FROM ${BASE_IMAGE}
USER root
COPY install.sh /tmp/install-opencode.sh
RUN HOME=/tmp/isoai-opencode-install /bin/bash /tmp/install-opencode.sh \
    && rm -rf /tmp/isoai-opencode-install /tmp/install-opencode.sh
COPY files/fragments/10-opencode.json /opt/isoai/opencode/fragments.d/10-opencode.json
USER agent
ENTRYPOINT ["/opt/isoai/runtime/launch-opencode"]
CMD []
