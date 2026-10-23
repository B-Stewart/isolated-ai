FROM scratch
COPY skills/ /opt/isoai/mixins/skills/
COPY files/fragments/50-skills.json /opt/isoai/opencode/fragments.d/50-skills.json
