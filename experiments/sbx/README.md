# Composable Docker Sandboxes experiment

This v3 scaffold replaces the unused v2 adapters over `agentic-base`. It does
not change the root images, `isoai`, or Dev Containers. It targets Linux amd64
guests; SBX execution and agent/plugin compatibility still require validation.

For a first run on patched WSL2, follow [host setup](#wsl2-host-setup),
[build and distribution](#build-and-distribution), then
[launch and lifecycle](#launch-and-lifecycle). Record results in the
[field-test checklist](TESTING.md).

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
Login, interactive, and non-interactive Bash shells load the same mise/shim
setup. The workload exposes `opencode` on PATH as well as through its launcher.
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

Build all six v3 descriptors with their own kit directories as contexts. These
tags are also the inputs to the image smoke tests below:

```bash
(
  set -e
  for kit in experiments/sbx/workloads/* experiments/sbx/mixins/*; do
    name="${kit##*/}"
    docker buildx build --load -t "local/isoai-sbx-$name:scaffold" \
      -f "$kit/$name.yaml" "$kit"
  done
)
python3 scripts/tests/test-sbx-images.py
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

Publish the shared base explicitly to your Docker Hub namespace:

```bash
base_repository='docker.io/YOUR_NAMESPACE/isoai-sbx-base'
base_tag="$base_repository:fieldtest-$(date +%Y%m%d)"
docker login
docker tag local/isoai-sbx-base:scaffold "$base_tag"
docker push "$base_tag"
docker buildx imagetools inspect "$base_tag"
```

Copy the top-level `Digest` from that inspection into the variable below. Use
the digest, not the mutable tag, for both profiles and keep it with your test
record:

```bash
base_image="$base_repository@sha256:REPLACE_WITH_PUSHED_DIGEST"
```

The SBX builder must be able to pull this reference. Sign into the same Docker
Hub account with `sbx login`; for other registries, configure SBX registry
credentials using Docker's [credential guide](https://docs.docker.com/ai/sandboxes/configuration/credentials/).
Host `docker login` alone is not proof that SBX can pull it.

## WSL2 host setup

Run SBX on the WSL host, not inside the `isoai` development container. The
Windows KVM fix has been reported installed on the test host; verify that
host's actual readiness rather than treating the patch as a passed runtime test.
The previous AMD/WSL blocker is tracked in
[WSL #41917](https://github.com/microsoft/WSL/issues/41917).

In PowerShell, record the Windows build and WSL versions:

```powershell
Get-ComputerInfo | Select-Object WindowsVersion, OsBuildNumber
wsl --version
wsl -l -v
```

In WSL Ubuntu 24.04 or later, check CPU architecture and KVM access:

```bash
uname -m
uname -r
sudo apt-get update
sudo apt-get install -y cpu-checker
sudo kvm-ok
ls -l /dev/kvm
test -r /dev/kvm && test -w /dev/kvm
```

This kit set requires `x86_64`. If `/dev/kvm` exists but your user lacks access,
add yourself to its `kvm` group and start a new login session before repeating
the checks:

```bash
sudo usermod -aG kvm "$USER"
```

Install Linux SBX separately from Docker Desktop. Docker's
[current Ubuntu installation guide](https://docs.docker.com/ai/sandboxes/install/)
provides this SBX-only route when Docker's apt repository is not configured:

```bash
curl -fsSL https://get.docker.com | sudo REPO_ONLY=1 sh
sudo apt-get update
sudo apt-get install -y docker-sbx
sbx version
sbx env --help
sbx login
```

Record the installed version and confirm its help includes v3-kit environment
operations. SBX's environment interface is experimental; the commands below
follow Docker's documentation reviewed on 2026-11-14. Docker Desktop working
does not establish KVM readiness. Stop here if the KVM checks fail.

## Launch and lifecycle

Keep this trusted configuration checkout outside every writable project mount.
Run these Bash commands from the repository root after setting `base_image`
above. Use a disposable clone on WSL's Linux filesystem for the plain profile:

```bash
mkdir -p "$HOME/sbx-fieldtests"
workspace="$HOME/sbx-fieldtests/project-plain"
git clone --no-hardlinks /absolute/path/to/source-project "$workspace"
profile="$PWD/experiments/sbx/profiles/opencode.yaml"
sandbox_name=project-plain
env_options=("$profile" --env-arg "workspace=$workspace" \
  --env-arg "base_image=$base_image" --name "$sandbox_name")

sbx secret set anthropic
sbx env plan "${env_options[@]}"
sbx env create "${env_options[@]}"
sbx env exec "${env_options[@]}" -- /opt/isoai/runtime/launch-opencode debug config
sbx env run "${env_options[@]}"
```

`secret set` prompts for your Anthropic API key. `create` provisions without
attaching; the `debug config` invocation assembles and parses the guest config
without requesting inference. Check that CodeGraph's parsed `command` ends in
`"serve", "--mcp"` and the plain profile has no OMO plugin. `run` attaches to
OpenCode. Follow [TESTING.md](TESTING.md) before making a model request.

For OMO, repeat with a separate clone, `profiles/opencode-omo.yaml`, and
`sandbox_name=project-omo`; rebuild `env_options` with those values. These are
Linux-host paths; Windows-native SBX is a separate test environment and needs
Windows-visible paths.

The workload and all OMO built-in agent model defaults explicitly select
`anthropic/claude-sonnet-4-6`, matching the workload's credential and network
configuration. Settings live in `workloads/opencode/files/fragments/10-opencode.json`
and `mixins/omo/files/oh-my-opencode-slim.json`. Change them together before
building if you want a different model. Other providers also need matching
credential/network declarations. These defaults do not add council members or
enable optional agents. Verify the plugin's effective models and any project
overrides before delegation; each model request incurs its provider's charges.

### Guest shell and diagnostics

In the same host Bash session, use the saved profile, arguments, and name:

```bash
sbx env exec -it "${env_options[@]}" -- bash -l
```

Inside the guest:

```bash
id
command -v opencode node tooling-node tooling-npm codegraph agent-browser
opencode --version
opencode debug config
opencode mcp list
```

Check MCP connections in the running agent too; a generated JSON file or a
version command alone does not establish a working connection. For browser
setup and a headless smoke test, follow the [browser note](mixins/browser/README.md).

### Stop, restart, and remove

Exit the guest shell/agent first. From the host, stop by name and restart using
the same environment invocation:

```bash
sbx ls
sbx stop "$sandbox_name"
sbx env run "${env_options[@]}"
```

Keep the profile path, workspace, base digest, and name in your test record;
recreate `env_options` from those values if you open a new host terminal.

Source is mounted read-write. Agent state, installed project runtimes, and
private files persist with the sandbox, not after its removal. Different names
mounting the same project do not isolate concurrent edits; use separate clones
for independent work. There are no host HOME, agent-state, SSH-directory, or
Docker-socket mounts in these profiles, and no agent permission-bypass flags.

Changing kit selection requires a new or recreated sandbox, not merely
reattaching. Preserve private work before removal. Prefer a new name when testing
changed kits; do not use a global `sbx reset` as routine experiment cleanup.

After preserving desired guest-only state, remove this environment explicitly:

```bash
sbx env rm "${env_options[@]}"
```

Review its destroy plan. The direct-mounted disposable clone remains on the
host; this command removes the sandbox's guest-only state. Use a new sandbox
name for rebuilt kits, or deliberately remove and recreate the old environment.

## Verification

Offline structure checks use the existing PyYAML dependency. In an isolated
temporary environment, for example:

```bash
uv run --no-project --with 'pyyaml>=6,<7' python scripts/tests/test-sbx-configs.py
node --test experiments/sbx/runtime/tests/assemble-opencode.test.mjs
```

These check composition and guest-local config assembly, not Docker's v3 schema
or runtime behavior. Also run the root README's offline verification checks.
After building the base and all six YAML kits as shown above, run:

```bash
python3 scripts/tests/test-sbx-images.py
```

This network-disabled test copies kit files into temporary Docker compositions,
then checks all four Bash modes, project/tooling Node separation, OpenCode's
actual parsing of MCP arguments, and OMO package/config presence versus absence.
It removes its temporary images afterward. It requires Docker and the six local
kit tags; it neither downloads missing images nor proves SBX composition,
network policy, MCP connectivity, or plugin loading.

Build the affected images/kits, then validate actual SBX plans and launches on a
supported host. Check tool versions, MCP connections, skill discovery, browser
launch, and OMO loading; confirm the plain profile has no OMO plugin loaded.
Inspect the generated config inside each guest. Do not infer compatibility from
package installation alone, or infer startup/RAM performance from image size.

Verification snapshot (2026-11-14): seven offline SBX checks, three Node
assembly tests, eight root image-installer checks, five SSH-helper checks, and
the launcher regression suite passed. The base image and all six workload/mixin
images rebuilt through their documented entrypoints, including the actual v3
YAML frontend. Builds used an isolated Docker client configuration because the
development container's mounted credential helper was unavailable.

All three image smoke tests passed: OpenCode v2.1.3 retains the complete MCP
commands when parsing the assembled config; plain and OMO compositions have the
expected package/sidecar/plugin differences; all four Bash modes discover the
tools; and a fake project-selected Node does not replace tooling Node/npm or
break the agent/tool wrappers. These were ordinary Docker containers, running
as UID 1000 with networking disabled. No images were pushed and no inference
requests were made.

Browser provisioning also passed twice as UID 1000 in a disposable Docker
container with network access. Each pass launched Chrome headlessly, checked
the inline page's title/heading, and produced a nonempty screenshot; the browser
reported `HeadlessChrome/157.0.0.0`. This validates the helper and Debian libraries,
not SBX's proxy or allowlist behavior.

Not yet verified: actual SBX plans/creation, credential injection, MCP
connections, skill discovery in a running agent, browser provisioning/launch under SBX,
or OMO loading and inference. No SBX runtime result is claimed while its CLI/KVM
is unavailable. Follow the [field-test checklist](TESTING.md) on the patched
WSL2 host; it separates host readiness, composition,
integration, optional paid inference, and lifecycle checks.

## References

- [V3 workloads and mixins](https://docs.docker.com/ai/sandboxes/customize/)
- [Build and distribute kits](https://docs.docker.com/ai/sandboxes/customize/author/distribute/)
- [Environment files](https://docs.docker.com/ai/sandboxes/configuration/environment-files/)
- [OpenCode v2 configuration](https://opencode.ai/v2/docs/config)
- [OpenCode v2 MCP servers](https://opencode.ai/v2/docs/mcp-servers)
