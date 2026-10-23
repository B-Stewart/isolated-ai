# Composable Docker Sandboxes experiment

This v3 scaffold replaces the unused v2 adapters over `agentic-base`. It does
not change the root images, `isoai`, or Dev Containers. It targets Linux amd64
guests; SBX execution and agent/plugin compatibility still require validation.

## Pattern and ownership

```text
agent-neutral base image
  Linux essentials, Git/SSH, GitHub CLI, Bun, mise, default tooling Node
  |
  +-- OpenCode workload: installs and launches OpenCode
        +-- Context7 MCP mixin
        +-- CodeGraph MCP mixin
        +-- selected skills mixin
        +-- agent-browser mixin
        +-- optional OMO-slim mixin
```

The shared image contains no coding agent. A workload supplies one agent and
its launch command. Mixins contribute optional files/tools/configuration; a
profile is an SBX environment file selecting that composition and its workspace.
Future agents should get thin workloads over the same base, not be added to the
shared image. A published kit set is optional, not required for this layout.

`profiles/opencode.yaml` selects the common tools without OMO;
`profiles/opencode-omo.yaml` adds OMO. Both disable the shared SBX skills store.
The research behind the custom-base decision is in
[the image analysis](opencode-image-analysis.md).

### Installation policy

Prefer maintained native release binaries with pinned versions and upstream
checksum verification. JavaScript packages are appropriate where no suitable
release binary exists. Installing a package with Bun does not prove it executes
without Node; test installation scripts and actual commands independently.
The authoritative contribution rules are in [AGENTS.md](AGENTS.md).

The base installs a pinned default Node through mise during the image build.
`tooling-node` and `tooling-npm` use that fixed installation, regardless of a
project's selected Node version. Bun and mise are available independently.
Mise data/config/state are writable by the guest user so project versions can
be installed later. Project configuration must be reviewed/trusted deliberately;
the scaffold does not globally trust every checkout or automatically run project
tasks. Additional runtime downloads require appropriate sandbox network access.

### Guest-local configuration

Each mixin owns uniquely named files under `/opt/isoai/`; selected OpenCode
fragments live in `/opt/isoai/opencode/fragments.d/`. Before OpenCode starts,
the workload launcher synchronously assembles those fragments with the base
configuration into `$HOME/.config/opencode/opencode.json`. This generated file
is scaffold-owned: change its source fragments, not the generated result.
Conflicting definitions fail rather than silently replacing another kit's MCPs.
When selected, OMO's kit-owned sidecar settings are copied into the guest home
by the launcher, rather than overlaying root-owned files onto that home.

OpenCode launches local MCP commands inside the guest, using native v2
`mcp.servers` configuration. Skills are kit-owned guest files selected through
OpenCode configuration. Neither uses SBX's host-global MCP registration or
shared host skills installation. OpenCode's user-global configuration here is
global only within that guest. Project configuration can still override agent
behavior; review projects before sharing them.

The base contains configuration-assembly helpers but no OpenCode executable or
OMO plugin. Only the OpenCode workload uses those helpers; future workloads can
supply their own launch/configuration logic. Browser provisioning and OMO
compatibility are separate checks, not properties guaranteed by a valid YAML file.
The skills kit currently contains two small starter skills, not an import of
your host's skill collection. Choose and version the desired collection here.
The browser kit installs the CLI only: see its [provisioning note](mixins/browser/README.md)
before attempting browser automation. Network rules are a starter allowlist;
project registries, websites under test, and system-package mirrors may require
additional explicitly approved destinations.

## Layout

- `base/`: agent-neutral Dockerfile and build-only installation script.
- `runtime/`: synchronous OpenCode configuration assembly and focused tests.
- `workloads/opencode/`: v3 descriptor, companion Dockerfile, agent installation.
- `mixins/`: independent v3 kits for MCPs, skills, browser tooling, and OMO.
- `profiles/`: plain and OMO environment files.

Run commands from the repository root. Experiment image builds use dedicated
contexts rather than the root `.dockerignore`, which excludes Markdown skills.
Installers execute inside image builds, never as host bootstrap scripts.

## Build and distribution

Build the shared image first:

```bash
docker build -f experiments/sbx/base/agentic-sbx-base.dockerfile \
  -t local/isoai-sbx-base:scaffold experiments/sbx
docker run --rm local/isoai-sbx-base:scaffold bash -c \
  'id; git --version; ssh -V; gh --version; bun --version; mise --version; node --version; tooling-node --version'
```

Pins and checksum overrides are Dockerfile build arguments. When overriding a
native archive version, update its checksum too. Do not run an x64 build on
another architecture without adding that platform's verified artifacts.

For a local Docker build check, build each v3 descriptor with its kit directory
as context. For example:

```bash
docker buildx build --load -t local/isoai-sbx-opencode:scaffold \
  -f experiments/sbx/workloads/opencode/opencode.yaml \
  experiments/sbx/workloads/opencode
```

**Docker's image store is not SBX's v3 kit store.** A successful `--load` is a
local build check, not an SBX deployment. `sbx template load` is not the v3 kit
distribution mechanism. Before SBX builds these local kit directories, publish
the shared base to a registry its builder can access and pass that reference as
the required profile argument `base_image`. Kit arguments forward it to the
Dockerfiles' `BASE_IMAGE` build argument. Alternatively, build
and publish the complete v3 kits, then select their registry references in the
profiles. No build in this scaffold automatically pushes images or credentials.

Keep the base reference consistent across the workload and feature build stages.
Local-only base visibility in an SBX builder is not assumed. The publishing
workflow and actual SBX composition remain deployment prerequisites, not a
claim that the default local tags work in SBX without preparation.

## Launch and lifecycle

Use a current `sbx` release supporting v3 kits and environment files. Install it
separately from Docker. Native Linux local sandboxes require working KVM;
Docker Desktop integration alone is not evidence that KVM works inside WSL.
Windows-native SBX is a separate alternative. The AMD/WSL failure investigated
in this session is tracked in [WSL #41917](https://github.com/microsoft/WSL/issues/41917).

Keep this trusted configuration checkout outside every writable project mount.
After preparing registry-accessible build inputs, review a plan before launching:

```bash
sbx login
sbx secret set anthropic
sbx env plan experiments/sbx/profiles/opencode.yaml \
  --env-arg "workspace=/absolute/path/to/project" \
  --env-arg "base_image=docker.io/YOUR_NAMESPACE/isoai-sbx-base:scaffold" \
  --name project-plain
sbx env run experiments/sbx/profiles/opencode.yaml \
  --env-arg "workspace=/absolute/path/to/project" \
  --env-arg "base_image=docker.io/YOUR_NAMESPACE/isoai-sbx-base:scaffold" \
  --name project-plain
```

For OMO, use `profiles/opencode-omo.yaml` and a different sandbox name. These
commands are illustrative Linux-host paths; Windows SBX needs Windows-visible
paths, including converted WSL paths where applicable. Credentials remain out
of committed files. Custom-kit credential use may require approval; model
requests incur provider charges. Choose providers/models intentionally before
running inference, especially delegated OMO requests.
The workload's starter model is not proof that OMO's default specialists use
that same provider/model; settle its presets and verify plugin compatibility
before making delegated requests.

Source is mounted read-write. Agent state, installed project runtimes, and
private files persist with the sandbox, not after its removal. Different names
mounting the same project do not isolate concurrent edits; use separate clones
for independent work. There are no host HOME, agent-state, SSH-directory, or
Docker-socket mounts in these profiles, and no agent permission-bypass flags.

Changing kit selection requires a new or recreated sandbox, not merely
reattaching. Preserve private work before removal. Prefer a new name when testing
changed kits; do not use a global `sbx reset` as routine experiment cleanup.

## Verification

Offline structure checks use the existing PyYAML dependency. In an isolated
temporary environment, for example:

```bash
uv run --no-project --with 'pyyaml>=6,<7' python scripts/tests/test-sbx-configs.py
node --test experiments/sbx/runtime/tests/assemble-opencode.test.mjs
```

These check composition and guest-local config assembly, not Docker's v3 schema
or runtime behavior. Also run the root README's offline verification checks.
Build the affected images/kits, then validate actual SBX plans and launches on a
supported host. Check tool versions, MCP connections, skill discovery, browser
launch, and OMO loading; confirm the plain profile has no OMO plugin loaded.
Inspect the generated config inside each guest. Do not infer compatibility from
package installation alone, or infer startup/RAM performance from image size.

Verification snapshot (2026-10-23): the five offline SBX checks and three Node
assembly tests passed. The root image-installer checks (three), SSH-helper
checks (five), and Docker SSH integration check (one, using an existing local
image) passed. The unchanged launcher test printed its passing assertion marker
but exited 143 during cleanup; no launcher fix is included here.

The base image built and passed network-disabled UID 1000 smoke checks, including
login/non-login shell discovery and isolation of tooling Node from a fake project
Node. The fixed `tooling-npm` wrapper also passed its version check. All six
workload/mixin images built through the actual v3 YAML frontend. The OpenCode
launcher returned `opencode v2.1.3` with its default guest HOME and networking
disabled; generated configuration contained no OMO plugin. No images were pushed
and no inference requests were made.

Not yet verified: actual SBX plans/creation, credential injection, MCP
connections, skill discovery in a running agent, browser provisioning/launch,
or OMO loading and inference. No SBX runtime result is claimed while its CLI/KVM
is unavailable. Follow the [deferred acceptance checklist](TESTING.md) after the
Windows fix restores KVM inside WSL2; it separates host readiness, composition,
integration, optional paid inference, and lifecycle checks.

## References

- [V3 workloads and mixins](https://docs.docker.com/ai/sandboxes/customize/)
- [Build and distribute kits](https://docs.docker.com/ai/sandboxes/customize/author/distribute/)
- [Environment files](https://docs.docker.com/ai/sandboxes/configuration/environment-files/)
- [OpenCode v2 configuration](https://opencode.ai/v2/docs/config)
- [OpenCode v2 MCP servers](https://opencode.ai/v2/docs/mcp-servers)
