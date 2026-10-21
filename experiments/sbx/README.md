# Experimental Docker Sandboxes workflows

These examples leave `isoai`, the two existing images, and Dev Containers
unchanged. They explicitly share a development workspace, not your home
directory or host Docker socket. Use disposable development projects first.

## Which image runs?

**The existing images remain the toolchain source.** A thin, SBX-only adapter
derives from `braydens/agentic-base:latest` or
`braydens/agentic-gamedev:latest`. It supplies the passwordless guest sudo and
proxy environment handling documented for custom V2 kits. It does not reinstall
or replace Claude, OpenCode, OMO-slim, RTK, .NET, or the game tools.

Do not substitute this sudo-enabled adapter for your hardened `isoai` image.
The intended security boundary here is SBX's microVM plus explicitly shared
resources. Neither adapter adds a Docker Engine: the inherited Docker CLI is
present, but these experiments do **not** provide Docker/Compose execution
inside the guest. Do not work around that by mounting the host Docker socket.
The existing Mongo service can still be reached over an explicitly allowed
network connection.

| Profile | Toolchain | Agent |
| --- | --- | --- |
| `profiles/base-claude.yaml` | Existing base image | Claude Code |
| `profiles/base-opencode-omo.yaml` | Existing base image | OpenCode v2 with OMO-slim enabled |
| `profiles/gamedev-claude.yaml` | Existing gamedev image | Claude Code, with Godot/Blender available |

The base profiles are starting points for a pstack workflow, not a claim that
unknown pstack-specific dependencies are installed. Copy a profile and adapt
its toolchain as those requirements become clear. Gamedev remains Linux amd64
only, headless, without a GPU/display bridge or Godot export templates.

## 1. Prepare Windows

Run SBX natively on Windows 11 x64. These examples require a current `sbx`
release with `sbx env`, V2 kits, environment arguments, and local template
imports. The environment-file interface is experimental; keep your CLI version
with experiment notes.

In an **administrator PowerShell** terminal, enable Windows Hypervisor Platform
if it is not enabled (Windows may require a reboot):

```powershell
Enable-WindowsOptionalFeature -Online -FeatureName HypervisorPlatform -All
```

Then in a regular Windows PowerShell terminal:

```powershell
winget install -h Docker.sbx
sbx version
sbx login
sbx policy init balanced
```

If SBX is already installed, inspect your existing policy rather than resetting
it. The profiles do not change your global policy or enable SSH forwarding.
For an initial experiment, disable forwarding explicitly if you do not need it:

```powershell
sbx settings set ssh.agentForwardingEnabled false
sbx daemon restart
```

That setting is global; daemon restart can interrupt existing sandboxes. Do it
only when appropriate for your other SBX work. The profiles also turn shared
skills off initially: custom-kit skill mounting has not been verified here.
They do not import host agent settings, tokens, sessions, or Git configuration.

## 2. Build the adapter images in WSL

Run from this repository's root, using the Docker daemon holding your current
images. The parent images must exist locally. If needed, build them using the
root README's image-build instructions; the gamedev tag is not assumed published.

```bash
docker image inspect braydens/agentic-base:latest >/dev/null
docker build -f experiments/sbx/agentic-sbx.dockerfile \
  -t local/agentic-base-sbx:experiment .

mkdir -p _ignore/sbx
docker image save local/agentic-base-sbx:experiment \
  -o _ignore/sbx/agentic-base-sbx.tar
```

For the optional gamedev profile:

```bash
docker image inspect braydens/agentic-gamedev:latest >/dev/null
docker build --platform linux/amd64 \
  -f experiments/sbx/agentic-sbx.dockerfile \
  --build-arg BASE_IMAGE=braydens/agentic-gamedev:latest \
  -t local/agentic-gamedev-sbx:experiment .
docker image save local/agentic-gamedev-sbx:experiment \
  -o _ignore/sbx/agentic-gamedev-sbx.tar
```

`_ignore/` is already ignored by Git. These archives can be large; keep them
local. SBX has a separate image store: building an image in Docker Desktop/WSL
alone does not make it available to SBX.

## 3. Import images and configure credentials on Windows

In **Windows PowerShell**, replace the distribution name and paths below:

```powershell
$Repo = '\\wsl.localhost\Ubuntu\home\you\repos\isolated-ai'
$Workspace = '\\wsl.localhost\Ubuntu\home\you\repos\pstack'
$Examples = Join-Path $Repo 'experiments\sbx'

sbx template load "$Repo\_ignore\sbx\agentic-base-sbx.tar"
# Optional, after building the gamedev adapter:
# sbx template load "$Repo\_ignore\sbx\agentic-gamedev-sbx.tar"

sbx secret set anthropic
```

The starter kits use **an Anthropic API key**, not an automatically imported
Claude subscription or your host OpenCode credentials. Third-party kits can
prompt for approval to use that credential. The proxy supplies the key to the
declared API endpoint; do not put secrets in the YAML or source repository.
OpenCode/OMO-slim use a simple single-provider starter configuration, with
Claude Sonnet 4.6 for the orchestrator and specialists. Delegation makes
additional billed API requests. Adjust the kit's generated JSON and credential
declarations together to change models/providers. Agent binaries and the plugin
come from your parent image, not from
Docker's stock OpenCode image or a new `@latest` install.

The profiles use `pullPolicy: never` because their templates were imported
locally. A missing-image error means the corresponding import/tag needs fixing,
not that you should expose your Docker daemon to SBX.

## 4. Validate, preview, and launch

Validate the kit definitions first:

```powershell
sbx kit validate "$Examples\kits\isoai-claude"
sbx kit validate "$Examples\kits\isoai-opencode-omo"
```

Preview the environment plan before applying it:

```powershell
sbx env plan "$Examples\profiles\base-claude.yaml" --env-arg "workspace=$Workspace" --name pstack-claude-a
```

Then launch either workflow:

```powershell
sbx env run "$Examples\profiles\base-claude.yaml" --env-arg "workspace=$Workspace" --name pstack-claude-a
sbx env run "$Examples\profiles\base-opencode-omo.yaml" --env-arg "workspace=$Workspace" --name pstack-omo-a
```

For gamedev, set `$Workspace` to your game project and run:

```powershell
sbx env run "$Examples\profiles\gamedev-claude.yaml" --env-arg "workspace=$Workspace" --name game-claude-a
```

These commands mount source **read-write**. That matches the desired trust
boundary: the agent may change your selected development resources, not
unrelated host files. The kits retain normal agent approval behavior; they do
not force dangerous permission-bypass flags. Your own project configuration
can still change agent behavior, so review it.

Network declarations are a starter allowlist, not every service used by the
installed toolchain. If a restore or download is blocked, inspect
`sbx policy log` and allow only the needed destination for that sandbox. For
example, a .NET project may need:

```powershell
sbx policy allow network --sandbox game-claude-a api.nuget.org:443
```

Keep the profile/kit checkout outside the development directories you give the
agent write access to. In particular, do not direct-mount this same repository
while relying on its experiment definitions as trusted host configuration.

### Parallel tasks and reconnecting

Distinct sandbox names do not make two mounts of the same working directory
independent. Use separate development clones/working directories for concurrent
editing. A linked host Git worktree can expose source but leave Git metadata
outside the mount; separate clones are the simplest starting point.

Pass the second directory as `workspace` with another `--name`. For private
in-VM clones instead, copy a profile and change `workspace` to:

```yaml
workspace:
  path: ${{ env.args.workspace }}
  clone: true
```

Create clone mode from the main Git checkout, not a linked worktree. Fetch or
push results before deleting the sandbox. Windows Git may need a
repository-specific `safe.directory` entry for a WSL source; follow Docker's
[WSL troubleshooting](https://docs.docker.com/ai/sandboxes/troubleshooting/#clone-mode-reports-not-in-a-git-repository-on-wsl),
not a blanket `safe.directory '*'` exemption.

Reconnect to an existing environment from any directory:

```powershell
sbx run --name pstack-omo-a
sbx ls
sbx stop pstack-omo-a
```

## 5. Optional access to your existing Mongo service

First verify that Windows can reach the existing development Mongo container
on localhost, for example on port 27017. Docker Desktop versus a daemon inside
WSL affects that prerequisite; do not expose Mongo to the LAN as a shortcut.

Grant access only to the chosen sandbox:

```powershell
sbx policy allow network --sandbox pstack-omo-a localhost:27017
```

Configure the application inside that sandbox to connect to
`mongodb://host.docker.internal:27017/<database>` with appropriate credentials.
The proxy translates the hostname to localhost for policy evaluation. Keep
one existing Mongo server and its current data volume; don't start two Mongo
servers on the same database files. Mongo authentication/roles, not SBX network
policy, determine read/write authority. Mongo credentials are not automatically
handled by the HTTP credential-header injection used for the agent API key.

## 6. Inspect tools and preserve records

Run harmless checks after creating a sandbox:

```powershell
sbx exec pstack-claude-a -- claude --version
sbx exec pstack-omo-a -- opencode --version
sbx exec pstack-omo-a -- oh-my-opencode-slim doctor
sbx exec game-claude-a -- godot --version
sbx exec game-claude-a -- blender --version
```

RTK is installed, but these starter profiles do not automatically configure
agent hooks. Use RTK commands explicitly or configure version-compatible hooks
inside the sandbox after verifying they preserve the OpenCode/OMO settings.

Private agent state persists across restarts, not sandbox removal. Export RTK
reports and copy diagnostic logs to a dedicated host directory, for example:

```powershell
$Records = Join-Path $env:USERPROFILE 'agent-records\pstack-omo-a'
New-Item -ItemType Directory -Force $Records | Out-Null
sbx exec pstack-omo-a -- rtk gain --all --format json > "$Records\rtk.json"
sbx cp 'pstack-omo-a:/home/agent/.local/share/opencode/log/opencode.log' "$Records\opencode.log"
```

The log must exist before copying it. Keep these records private. This is a
manual starting point, not an automatic collector or global-history merger.
For session transcripts, OpenCode V2 has experimental export/event-log APIs;
see the [research note](../../isoai-alternatives-research.md#host-accessible-statistics-and-session-records).
Don't share one live OpenCode/RTK SQLite database across independent sandboxes
or copy an active database as though that were a consistent backup.

## Updating and removing experiments

Rebuild and re-import the adapter after changing its parent image. This does
not update existing sandboxes. Profile kit/image changes apply when creating
a new sandbox, not simply reconnecting to an old name. Use a new name first,
verify the new environment, and preserve any needed old state before removal.

```powershell
sbx env rm "$Examples\profiles\base-opencode-omo.yaml" --env-arg "workspace=$Workspace" --name pstack-omo-a
```

Removal is destructive to the sandbox's private state. Direct-mounted source
and your separate Mongo container remain outside it. Do not use `sbx reset` as
routine cleanup: it affects other sandboxes and shared SBX state too.

## Verification status and references

From the repository root in WSL, run the focused offline structure checks using
the existing image's Python/uv. PyYAML is supplied in a temporary uv environment;
no dependency is added to the repository or image:

```bash
docker run --rm --mount "type=bind,src=$PWD,dst=/repo,readonly" -w /repo \
  braydens/agentic-base:latest \
  uv run --no-project --with 'pyyaml>=6,<7' python scripts/tests/test-sbx-configs.py
```

The first run needs package-download access. These checks validate the expected
document structure and safety constraints; they are not Docker's own schema
validator. The existing root README's offline launcher/image checks remain
applicable and unchanged.

These are experimental configuration scaffolds, not a tested Windows/WSL SBX
deployment. Local Docker adapter smoke checks and repository checks do not
prove SBX provisioning, credential injection, UNC mounts, or OMO inference.
Run the validation, plan, launch, and tool checks above on your Windows host
before adopting the profiles.

Implementation check snapshot (2026-10-21): both adapter images built, and
network-disabled guest checks passed for UID 1000, sudo/proxy preservation,
shell setup, and installed tool versions. The four focused configuration
tests, three image-installer tests, and five SSH-helper tests passed. The
unchanged launcher test printed its passing assertion marker but exited 143
during cleanup; the same behavior was reproduced from baseline `403afd4`. No
launcher fix is included in this experiment. SBX's own validator/runtime and
the final generated OpenCode/OMO configuration inside SBX remain unverified.

- [Custom V2 kits](https://docs.docker.com/ai/sandboxes/customize/kits-v2/)
- [Environment files](https://docs.docker.com/ai/sandboxes/configuration/environment-files/)
- [Local image imports](https://docs.docker.com/ai/sandboxes/usage/#load-a-template)
- [Host services](https://docs.docker.com/ai/sandboxes/workflows/development/#accessing-host-services-from-a-sandbox)
- [OpenCode V2 configuration](https://opencode.ai/v2/docs/config)
- [OMO-slim configuration](https://github.com/alvinunreal/oh-my-opencode-slim/blob/master/docs/configuration.md)
