ARG BASE_IMAGE=local/isoai-sbx-base:scaffold
FROM ${BASE_IMAGE} AS install
USER root
COPY install.sh /tmp/install.sh
RUN /bin/bash /tmp/install.sh && rm /tmp/install.sh
FROM scratch
COPY --from=install /opt/isoai/mixins/codegraph/ /opt/isoai/mixins/codegraph/
COPY --from=install /opt/isoai/mixins/codegraph/codegraph /opt/isoai/bin/codegraph
COPY files/fragments/30-codegraph.json /opt/isoai/opencode/fragments.d/30-codegraph.json
