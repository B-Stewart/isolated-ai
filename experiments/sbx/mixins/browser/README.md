# Browser mixin scaffold

Installs the pinned `agent-browser` CLI and exposes it at
`/opt/isoai/mixins/browser/bin/agent-browser`. Browser provisioning is explicit:
run `/opt/isoai/mixins/browser/install-browser` in the guest when network access
and the platform's browser dependencies are available. This mixin does not
silently download a browser at build or sandbox startup and does not claim that
the guest has all distro libraries required to launch one.
