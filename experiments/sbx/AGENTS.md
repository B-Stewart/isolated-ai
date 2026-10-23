# SBX experiments

Read [README.md](README.md) before changing workloads, mixins, profiles, or
installers. These experiments are independent of the root images and `isoai`.

## Architecture

- Keep the shared image agent-neutral. Workloads select and launch one coding
  agent; mixins add optional tools, MCPs, skills, or agent-specific behavior.
- Keep OpenCode usable without OMO-slim. Profiles select the desired workload
  and mixins; changing that selection requires a new or recreated sandbox.
- Prefer maintained native release binaries when available. Pin releases and
  verify downloads against upstream checksums. Use Bun/Node packages when no
  suitable release binary exists; validate their actual installation and runtime
  requirements instead of assuming Bun installation removes a Node dependency.
- Keep agent-tool runtimes stable and independent of project mise selections.
  Install the default tooling Node during image builds; let mise select project
  runtimes inside the guest.
- Keep MCP configuration, plugins, skills, and agent state sandbox-local. Bundle
  selected skills with kits and disable SBX's shared skills store. Use guest
  agent configuration rather than SBX host-global MCP registrations.
- Give configuration assembly one owner. Mixins contribute uniquely named
  fragments; required assembly finishes before the agent launches.

## Verification

- Build from the repository root. Installer scripts run inside image builds,
  not on the host. Keep experiment installers under this directory.
- Validate plain and OMO compositions, including the absence of OMO from the
  plain profile. Keep source mounts explicit and credentials out of committed
  files; preserve ordinary agent approval behavior.
- Distinguish offline structure checks, image builds, and actual SBX smoke
  tests. Record unavailable checks and scaffold limitations in the guide.
- Version `provides` entries and validate kits through their YAML frontend;
  Dockerfile-only checks do not validate the v3 descriptor schema.
