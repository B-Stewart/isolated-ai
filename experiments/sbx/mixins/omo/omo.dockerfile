ARG BASE_IMAGE=local/isoai-sbx-base:scaffold
FROM ${BASE_IMAGE} AS install
USER root
COPY install.sh /tmp/install.sh
RUN /bin/bash /tmp/install.sh && rm /tmp/install.sh
FROM scratch
COPY --from=install /opt/isoai/mixins/omo/ /opt/isoai/mixins/omo/
COPY files/fragments/40-omo.json /opt/isoai/opencode/fragments.d/40-omo.json
COPY files/oh-my-opencode-slim.json /opt/isoai/mixins/omo/oh-my-opencode-slim.json
