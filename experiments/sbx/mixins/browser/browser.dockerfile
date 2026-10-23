ARG BASE_IMAGE=local/isoai-sbx-base:scaffold
FROM ${BASE_IMAGE} AS install
USER root
COPY install.sh /tmp/install.sh
RUN /bin/bash /tmp/install.sh && rm /tmp/install.sh
FROM scratch
COPY --from=install /opt/isoai/mixins/browser/ /opt/isoai/mixins/browser/
COPY --from=install /opt/isoai/mixins/browser/bin/agent-browser /opt/isoai/bin/agent-browser
