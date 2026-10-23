ARG BASE_IMAGE=local/isoai-sbx-base:scaffold
FROM ${BASE_IMAGE} AS install
USER root
COPY install.sh /tmp/install.sh
RUN /bin/bash /tmp/install.sh && rm /tmp/install.sh
FROM scratch
COPY --from=install /opt/isoai/mixins/context7/ /opt/isoai/mixins/context7/
COPY files/fragments/20-context7.json /opt/isoai/opencode/fragments.d/20-context7.json
