# isolated-ai

A repo to hold my current agentic developer workflow revolving around Docker isolation. Included is a base image hosting 2 coding agents (maybe more to come if I start using them) — Claude Code, OpenCode — for use as a Dev Container base or as a standalone host with optional hardening flags.

Image tag: `braydens/agentic-base:latest`

The image ships:

| Tool | Binary | Kind | Purpose |
|---|---|---|---|
| Claude Code | `claude` | Coding agent | Anthropic's CLI |
| OpenCode v2 | `opencode` | Coding agent | Installed from `@opencode/cli@2` (the older `opencode-ai` package installs v1) |
| oh-my-opencode-slim | `oh-my-opencode-slim` | OpenCode plugin + agents | Slimmed agent-orchestration plugin for OpenCode (Orchestrator, Explorer, Oracle, Librarian, Designer, Fixer subagents) ([alvinunreal/oh-my-opencode-slim](https://github.com/alvinunreal/oh-my-opencode-slim)). Baked in but **not auto-enabled** — install presets per host with `oh-my-opencode-slim install`. |
| OpenCode Quota | `opencode-quota` | OpenCode plugin + CLI | Provider quota, token usage, and cost reporting ([slkiser/opencode-quota](https://github.com/slkiser/opencode-quota)). Baked in but **not auto-enabled** — enable once per host as described below. |
| context7 | `context7-mcp` | MCP | Up-to-date library docs (Upstash) |
| Figma (Framelink) | `figma-developer-mcp` | MCP | Public Figma REST API; requires a personal access token |
| Firebase | `firebase` | CLI | Firebase CLI (`firebase-tools`) for project deploys, auth, and emulator workflows |
| GitHub CLI | `gh` | CLI | GitHub issues, PRs, checks, releases, and auth-aware repo workflows |
| .NET SDK | `dotnet` | SDK | .NET development |
| agent-browser | `agent-browser` | CLI | Browser automation CLI; Chrome for Testing and Linux dependencies are preinstalled |
| uv | `uv` | Python tool manager | Standalone Rust binary, fetches its own Python on demand |
| Bun | `bun` | JavaScript runtime | Required by oh-my-opencode-slim (its CLI uses a `#!/usr/bin/env bun` shebang); also available on PATH for general use |
| RTK | `rtk` | CLI token optimizer | Filters/dedups command output before it reaches the LLM context ([rtk-ai/rtk](https://github.com/rtk-ai/rtk)) |
| Trivy | `trivy` | Security scanner | Vulnerability, misconfiguration, and secret scanning CLI ([aquasecurity/trivy](https://github.com/aquasecurity/trivy)) |
| CodeGraph | `codegraph` | Codebase knowledge graph | Local code graph/index CLI ([colbymchenry/codegraph](https://github.com/colbymchenry/codegraph)). Baked in but **not auto-enabled** — initialize per project with `codegraph init`. |
| spec-kit | `specify` | Spec-Driven Development | Generates implementations from specs ([github/spec-kit](https://github.com/github/spec-kit)). Baked in but **not auto-enabled** — initialize per project with `specify init .`. |

Skip to:

- [Usage](#usage) — first-run setup, Dev Container and standalone invocations
- [Contributing](#contributing) — image structure, maintenance, checks, and builds
- [Methodology](#methodology) — why the image is shaped this way

---

## Usage

### First-run setup

Do these once on the WSL host before launching anything. Everything below assumes you've completed this block.

**1. Pull the image.**

```bash
docker pull braydens/agentic-base:latest
```

**2. Create the host config paths.** Docker would otherwise auto-create them root-owned, and would auto-create `~/.claude.json` as a *directory* (it can't tell file vs dir intent), which breaks both agents in surprising ways:

```bash
mkdir -p ~/.agents ~/.claude ~/.config/opencode ~/.local/share/opencode ~/.config/rtk ~/.local/share/rtk ~/.config/configstore ~/.cache/firebase ~/.config/gh ~/.codegraph
touch ~/.claude.json
```

**3. Register the MCP servers.** Once is enough — registrations persist in your host `~/.claude.json` and every container plus your native `claude` will see them:

```bash
# context7 — no args
claude mcp add -s user context7 -- context7-mcp

# Figma (Framelink) — supply your token; --stdio puts the server in MCP transport mode
claude mcp add -s user -e FIGMA_API_KEY=<your-figma-pat> figma -- figma-developer-mcp --stdio
```

Inspect or remove with `claude mcp list` / `claude mcp remove <name>`.

For OpenCode, edit `~/.config/opencode/opencode.json` directly — OpenCode has no `mcp add` CLI:

```jsonc
{
  "$schema": "https://opencode.ai/config.json",
  "mcp": {
    "context7": {
      "type": "local",
      "command": ["context7-mcp"],
      "enabled": true
    },
    "figma": {
      "type": "local",
      "command": ["figma-developer-mcp", "--stdio"],
      "environment": { "FIGMA_API_KEY": "<your-figma-pat>" },
      "enabled": true
    }
  }
}
```

Inspect connection state with `opencode mcp list`; troubleshoot a misbehaving server with `opencode mcp debug <name>`.

**4. Install oh-my-opencode-slim agents.** This OpenCode plugin adds a team of specialist subagents (Orchestrator, Explorer, Oracle, Librarian, Designer, Fixer) and writes config to `~/.config/opencode/oh-my-opencode-slim.json` plus skill assets under the bind-mounted opencode dirs. Run its `install` subcommand once in a throwaway container:

```bash
docker run -it --rm \
  -v "$HOME/.config/opencode:/home/agent/.config/opencode" \
  -v "$HOME/.local/share/opencode:/home/agent/.local/share/opencode" \
  braydens/agentic-base:latest \
  oh-my-opencode-slim install
```

`-it` because the installer prompts for model assignments per agent role. Re-run the same command later to change assignments or pick up new presets after a base-image rebuild.

**Enable OpenCode Quota.** After rebuilding the base image with Quota included, run this once to add the plugin to your shared OpenCode configuration, preserving existing plugins:

```bash
docker run --rm \
  -v "$HOME/.config/opencode:/home/agent/.config/opencode" \
  -v "$HOME/.local/share/opencode:/home/agent/.local/share/opencode" \
  braydens/agentic-base:latest \
  opencode plugin add @slkiser/opencode-quota@6
```

OpenCode installs its own plugin copy; the image also provides `opencode-quota` for standalone terminal reports. The major-bounded entry works in native OpenCode too, without a container-specific path. Image builds and normal container startup do not modify your mounted configuration. In OpenCode, use `/quota` for limits, `/quota_usage` for usage, and `/quota_status` to check provider setup; use `/reload` if an existing session has not picked up the plugin. It uses existing provider logins where supported; some providers need additional setup as described in the [provider guide](https://github.com/slkiser/opencode-quota/blob/main/docs/readme/providers.md).

**5. Install the RTK hook.** RTK's `init -g` writes a `PreToolUse` hook into `~/.claude/settings.json` so every bash invocation gets passed through the token-optimizing proxy. Run it in a throwaway container; it persists for every container plus your native `claude`:

```bash
docker run --rm \
  -v "$HOME/.claude:/home/agent/.claude" \
  -v "$HOME/.claude.json:/home/agent/.claude.json" \
  -v "$HOME/.config/rtk:/home/agent/.config/rtk" \
  -v "$HOME/.local/share/rtk:/home/agent/.local/share/rtk" \
  braydens/agentic-base:latest \
  rtk init -g --auto-patch --claude && rtk init -g --auto-patch --opencode
```

`--auto-patch` skips the interactive "Patch existing settings.json? [y/N]" prompt — without it, `rtk init` detects non-interactive stdin (which the throwaway container always is) and defaults to `N`, leaving the hook *not* installed.

The hook calls `rtk` on `PATH`. In the base image that's `/usr/local/bin/rtk`. **Caveat:** if you also run `claude` natively on the WSL host, the same hook fires there too — install RTK on the host (`curl -fsSL https://raw.githubusercontent.com/rtk-ai/rtk/refs/heads/master/install.sh | sh`) or the hook will error on every tool call. Undo at any time with `rtk init -g --uninstall` (same throwaway-container shape).

Inspect token savings with `rtk gain`.

**6. Authenticate GitHub CLI if needed.** `gh` stores auth/config in the bind-mounted `~/.config/gh`, so one login survives rebuilds and is shared with native WSL usage:

```bash
gh auth login
```

Inside a devcontainer, VS Code's git credential forwarding handles normal `git` auth, but `gh` still reads its own config directory for issue/PR/check/release workflows. For throwaway standalone containers, mount `~/.config/gh` the same way as the devcontainer.

**7. Initialize CodeGraph per project if needed.** The `codegraph` binary is available on PATH and defaults to local project state under `./.codegraph/` (for example `./.codegraph/codegraph.db`). Run it inside each workspace you want indexed:

```bash
codegraph init
```

The optional global home state at `~/.codegraph/` is bind-mounted from the host. The image also sets `CODEGRAPH_TELEMETRY=0`, `DO_NOT_TRACK=1`, and `CODEGRAPH_NO_DAEMON=1` for quieter, container-friendly runs.

Project-specific Playwright browsers are not provisioned automatically. Install them using the project's own instructions. The image's `agent-browser` command and its Chrome for Testing browser, including Linux dependencies, are preinstalled and ready to use.

### Use as a Dev Container base

Drop a `.devcontainer/devcontainer.json` in your project pointing at this image — or copy [`.devcontainer/devcontainer.json`](.devcontainer/devcontainer.json) as a starting point. If you need extra layers, create `.devcontainer/Dockerfile`:

```dockerfile
FROM braydens/agentic-base:latest
# project-specific packages or environment variables
```

and update your `devcontainer.json` to build from it.

For the game-development image, copy [`.devcontainer/devcontainer.gd.jsonc`](.devcontainer/devcontainer.gd.jsonc)
to your project as `.devcontainer/devcontainer.json` to use it instead of the
default config.

**Auth forwarding (Dev Containers extension).** When you "Reopen in Container," VS Code handles git auth automatically — no devcontainer.json changes needed:

- **SSH** — your host's SSH agent socket is forwarded in via `SSH_AUTH_SOCK`. Keys stay on the host.
- **HTTPS** — an in-container credential helper proxies to your host credential manager (Windows Credential Manager, macOS Keychain, libsecret on Linux).
- **Identity** — host `user.name`/`user.email` get injected so commits carry the right author.

**Firewall variant.** For egress allowlisting, use [`devcontainer.firewall.jsonc`](.devcontainer/devcontainer.firewall.jsonc) instead of the default. The variant ships with the firewall toggles **present but off** so it diffs cleanly against the default — flip them on with three edits:

1. Comment out `"--cap-drop=ALL"` in `runArgs` (incompatible with `NET_ADMIN`).
2. Uncomment the three `// FIREWALL:` lines in `runArgs` (`NET_RAW` + `SYS_PTRACE` drops + `NET_ADMIN` add).
3. Uncomment the `// FIREWALL:` line in `postCreateCommand` (runs `init-firewall.sh` via sudo on container create).

See [Firewall allowlist](#firewall-allowlist) for what's allowed and how to add hosts.

### Use as a standalone container

#### Recommended: persistent launcher

`scripts/isoai` can be run from any project directory:

```bash
isoai
```

The launcher defaults to `braydens/agentic-base:latest`. Use `--code` or
`-c` to open the matching persistent container directly in local VS Code
(replacing the old positional `code` mode), or use `--image=gd` / `-i=gd` or
`--image gd` / `-i gd` to select `braydens/agentic-gamedev:latest`:

```bash
isoai --code
isoai -c -- opencode
isoai --image=gd
isoai --image gd -- godot --headless --path "$PWD" --import
isoai -i=gd -- blender --background --python script.py
isoai --image=gd --code -- opencode
isoai -i=gd -c -- opencode
```

Host Docker socket access is off by default. Opt in per invocation with `--docker`
or `-d`; this works with base and `gd`, with commands, and with VS Code:

```bash
isoai -d
isoai --docker -- opencode
isoai -d --image gd -- godot --headless --path "$PWD" --import
isoai -c -d --image=gd
```

The socket grants the container control of the host Docker daemon and is a
powerful host privilege. The launcher checks an existing container's saved
Docker mount before reuse/start: its mode must match this invocation. Older
socket-enabled containers remain reusable by running `isoai -d`. A mismatch
is refused without starting, execing, deleting, or recreating the container;
mounts cannot be changed in place. The container name/identity is unchanged.
To change modes, first preserve any writable-layer state you need, then
explicitly remove/recreate the container in the intended mode. Omitting `-d`
creates a socket-free container by default. This controls only the standard
`/var/run/docker.sock` bind; it does not guarantee the container lacks every
possible alternate Docker endpoint.

The only supported image selector is `gd`. `isoai help`, `isoai --help`, and
`isoai -h` print the launcher's built-in reference without requiring Docker.
Launcher options can appear in any order before `--`; everything after `--`
is passed through as the in-container command. Omit `--` to start or reuse the
container without running a command. Keep the built-in help, launcher
regression tests, and these README examples in sync when changing the CLI.

The `gd` profile is for Godot 4.7.2 .NET project imports/tests and Blender
5.2.2 LTS background Python scripting. It does not configure a GUI, display,
GPU, or host bridge. Godot export templates are not included and must be
installed separately. The image inherits the base image's .NET 10 SDK and adds
.NET 8 runtime support for conventional `net8` project testing. Godot and
Blender versions are pinned in the derived Dockerfile's build arguments;
update those arguments explicitly to change either version.

The game-development image is Linux `amd64` only because the official Blender
Linux build is x64-only. ARM hosts need Docker's `linux/amd64` emulation and
platform selection; native ARM support is not provided. Build the image
locally before selecting this profile (build commands are below); do not
assume the tag is published.

Both profiles use the same deterministic workspace naming, with `-gd` appended
for the game-development container. Pulling or rebuilding an image does not
automatically recreate an existing container, and switching profiles leaves
the other profile's container in place. The profiles share workspace files
and host-mounted state, so avoid simultaneous modifications or imports that
could conflict.

To run a command inside the matching persistent workspace container, put `--`
before the command. Everything after `--` runs inside that container as the
`agent` user:

```bash
isoai -- opencode
isoai -- claude --dangerously-skip-permissions
```

To open the persistent container directly in local VS Code, use `--code` (or
`-c`):

```bash
isoai --code
isoai --code -- opencode
```

The `--` form opens the matching workspace container first, then runs the
rest of the command inside it as `agent`. This uses an undocumented VS Code
remote URI format and requires the Dev Containers extension plus the `code`
and `xxd` commands on the host. It may break when VS Code changes.

The launcher creates the required host mount sources before Docker starts, including `~/.gitconfig`, mounts the current working directory at the identical absolute path inside the container, and mirrors the default `.devcontainer/devcontainer.json` mounts and `runArgs`. It bind-mounts `~/.gitconfig` at `/home/agent/.gitconfig`; the host Docker socket is mounted only when `--docker`/`-d` is supplied. On Linux and WSL, when host Python 3 and a reachable `SSH_AUTH_SOCK` are available, it uses the adjacent `scripts/isoai-ssh-agent.py` helper to relay SSH-agent requests. The stable host directory `$HOME/.local/state/isoai/ssh/$container_name` is mounted read-only at `/run/isoai/ssh`, and the container uses `SSH_AUTH_SOCK=/run/isoai/ssh/agent.sock`. The relay reuses that directory and picks up the current upstream socket for new connections; its socket file may be replaced, but the directory must remain for the stopped container's lifetime. An unsafe or uncreatable relay directory prevents startup. If the host agent is unavailable, the helper disables forwarding and warns without blocking startup. If Python 3 or the helper is unavailable, startup continues with a warning, but an existing relay may still forward to its previous agent because it could not be refreshed. `~/.config/gh` remains bind-mounted for GitHub HTTPS credentials and `gh` workflows.

It starts a persistent, deterministically named container and prints its name. Running it again from the same directory and Docker-socket mode reuses that container. Docker cannot retrofit mounts onto an existing container, so a mode mismatch is refused rather than silently changing or deleting it. To recreate explicitly, use the known container name (or find it with `docker ps -a --filter 'name=isolated-ai-'`); do not derive it from `isoai` when the mode mismatch makes that invocation fail. If its writable layer matters, make and validate a private snapshot first:

```bash
container_name='your-container-name'
snapshot_tag='local/isoai-snapshot:temporary'
docker commit "$container_name" "$snapshot_tag"
```

The snapshot retains the writable layer, not bind-mounted workspace/config data; keep it private because it may contain secrets. Only remove the original once its state is preserved or discarding it is acceptable; the next invocation's `-d` choice determines the new standard socket mount. For legacy SSH-mount failures, follow the preservation-first migration instructions below instead.

```bash
container_name='your-container-name'
docker rm -f "$container_name"
isoai # socket-free by default; add -d only if host Docker access is intended
```

The relay forwards signing authority: read-only mounting its directory does not prevent the container from asking the host agent to sign. The container's `agent` user (UID 1000 in this image) must match the host socket relay's permissions; do not make the socket world-accessible. Mount only the dedicated relay directory, not all of `/tmp` or `~/.ssh`.

Containers created before this relay contract may have a saved single-file `/ssh-agent` bind mount. Updating the launcher/helper cannot retrofit that mount. Restart can fail if the saved source disappears or no longer has the expected socket type, even when the current host agent is healthy. If a legacy container fails to start, the launcher leaves it unchanged and prints snapshot guidance; do not remove it as an automatic repair. For a preservation-first migration, keep the container stopped and privately snapshot its writable layer:

```bash
container_name='your-container-name'
snapshot_tag='local/isoai-legacy-snapshot:temporary'
docker commit "$container_name" "$snapshot_tag"
```

The original container remains intact. The snapshot includes the writable layer, but not bind mounts or volumes; reconstruct their host sources and retain the original runtime configuration. A snapshot may contain secrets, so keep it private and do not publish it. Create a replacement under a temporary new name from the immutable snapshot, restoring the original configuration and reconstructed bind mounts (not Docker Desktop's internal mount paths). Validate its workspace contents and SSH forwarding before consenting to adoption, renaming, or deleting either container. Do not recreate from a mutable `latest` image in place of the snapshot, since that can discard state.

The script lives inside this repository. To install a copy on your PATH without adding anything to the repository:

```bash
mkdir -p ~/.local/bin
install -m 755 /absolute/path/to/isolated-ai/scripts/isoai ~/.local/bin/isoai
install -m 644 /absolute/path/to/isolated-ai/scripts/isoai-ssh-agent.py ~/.local/bin/isoai-ssh-agent.py
```

Alternatively, symlink it so updates in this repository take effect immediately:

```bash
mkdir -p ~/.local/bin
ln -sfn /absolute/path/to/isolated-ai/scripts/isoai ~/.local/bin/isoai
ln -sfn /absolute/path/to/isolated-ai/scripts/isoai-ssh-agent.py ~/.local/bin/isoai-ssh-agent.py
```

Keep the launcher and helper adjacent: the launcher locates the helper beside itself. Python 3 runs the helper, so it does not need an executable bit.

For **bash**, append the PATH export to `~/.bashrc`, then source it:

```bash
printf '%s\n' 'export PATH="$HOME/.local/bin:$PATH"' >> ~/.bashrc
source ~/.bashrc
```

For **zsh**, append it to `~/.zshrc`, then source it:

```bash
printf '%s\n' 'export PATH="$HOME/.local/bin:$PATH"' >> ~/.zshrc
source ~/.zshrc
```

As a fallback, attach manually with VS Code by installing the **Dev
Containers** extension, then use **F1** → **Dev Containers: Attach to Running
Container...** and select the printed container. Next choose **File** → **Open
Folder** and enter the current working directory's identical absolute path
inside the container. The same container is also available through VS Code's
**Remote Explorer**.

List launcher containers or stop and remove one with:

```bash
docker ps --filter 'name=isolated-ai-'
docker rm -f <container-name>
```

#### Advanced/manual one-shot alternatives

The image has no `ENTRYPOINT` or `CMD` — invoke the agent you want explicitly. These manual invocations are one-shot alternatives and do not provide the launcher's host initialization, persistent container, or automatic post-create check.

**Workspace run — hardened, firewall off:**

```bash
docker run -it --rm \
  --cap-drop ALL \
  --security-opt no-new-privileges:true \
  --pids-limit 4096 \
  --tmpfs /tmp:rw,noexec,nosuid,size=512m \
  -v "$HOME/.claude:/home/agent/.claude" \
  -v "$HOME/.claude.json:/home/agent/.claude.json" \
  -v "$HOME/.config/gh:/home/agent/.config/gh" \
  -v "$HOME/.codegraph:/home/agent/.codegraph" \
  -v "$PWD:/workspace" \
  braydens/agentic-base:latest \
  claude --dangerously-skip-permissions
```

**Workspace run — hardened, firewall on:**

Firewall needs `NET_ADMIN`, so `--cap-drop ALL` is replaced by targeted drops:

```bash
docker run -it --rm \
  --cap-drop NET_RAW \
  --cap-drop SYS_PTRACE \
  --cap-add NET_ADMIN \
  --security-opt no-new-privileges:true \
  --pids-limit 4096 \
  --tmpfs /tmp:rw,noexec,nosuid,size=512m \
  -v "$HOME/.claude:/home/agent/.claude" \
  -v "$HOME/.claude.json:/home/agent/.claude.json" \
  -v "$HOME/.config/gh:/home/agent/.config/gh" \
  -v "$HOME/.codegraph:/home/agent/.codegraph" \
  -v "$PWD:/workspace" \
  braydens/agentic-base:latest \
  sh -c 'sudo /usr/local/bin/init-firewall.sh && exec claude --dangerously-skip-permissions'
```

**Git auth without VS Code:**

- **Forward an SSH agent socket (one-shot only)** — add `-v "${SSH_AUTH_SOCK}:/ssh-agent" -e SSH_AUTH_SOCK=/ssh-agent`. Keys stay on the host, but the saved mount points at an ephemeral socket path and can fail when restarting a stopped container after that socket is replaced or disappears. Use the persistent launcher for restart-safe forwarding.
- **Mount `~/.ssh` read-only** — simplest, but exposes key files to the container; only acceptable for trusted workloads.

### Run modes at a glance

| Mode | cap-drop ALL | cap-add NET_ADMIN | Firewall | Use case |
|---|---|---|---|---|
| Devcontainer (default) | yes | no | off | VS Code attached, dev workflow |
| Devcontainer + firewall | partial | yes | on | development with egress allowlist |
| Standalone hardened | yes | no | off | one-shot agent run, max isolation |
| Standalone + firewall | partial | yes | on | one-shot, egress-controlled |

### Firewall allowlist

The default `init-firewall.sh` allowlists egress to:

- `registry.npmjs.org`
- `api.anthropic.com`, `console.anthropic.com`
- `github.com`, `api.github.com`, `objects.githubusercontent.com`, `raw.githubusercontent.com`, `codeload.github.com`

Add hosts via `FIREWALL_EXTRA_HOSTS` (comma-separated):

```
-e FIREWALL_EXTRA_HOSTS=registry.opencodeai.com
```

DNS (UDP/53) is allowed unconditionally so resolution works after rules apply.

CDN-backed targets (npm, GitHub objects) rotate IPs over hours/days. If a long-lived container starts seeing previously-working hosts blocked, re-run the script to re-resolve.

---

## Contributing

### Image build structure

There are two images: `agentic-base` and `agentic-gamedev`, which inherits from
the base. Their Dockerfiles stay at the repository root; installation details
live in build-only Bash scripts grouped by image:

```text
agentic-base.dockerfile
agentic-gamedev.dockerfile
scripts/
  image/
    base/       # shared agent/developer environment installers
    gamedev/    # additional game-development installers
  tests/        # offline regressions and in-image smoke checks
  isoai         # host-side runtime launcher, not an image installer
  isoai-ssh-agent.py
```

**Ownership:** Dockerfiles define build stages, installation order, cache mounts,
build arguments, image environment, users, and runtime setup. Installer scripts
define package selectors, repositories, downloads, and installation commands.
Base tool version bounds live in the installers, not Docker build arguments.
The remaining platform and gamedev version arguments stay in the Dockerfiles
and are passed explicitly to the relevant scripts.

| Installer under `scripts/image/` | Responsibility |
|---|---|
| `base/install-npm-tools.sh` | Agent, plugin, MCP, browser CLI, Firebase, and CodeGraph npm packages in the builder stage |
| `base/install-system-deps.sh` | Debian dependencies and system-wide Git LFS setup |
| `base/link-agent-tools.sh` | Global and agent-local executable links after copying the builder's npm packages |
| `base/install-runtimes.sh` | Corepack, uv, .NET SDK, and Bun |
| `base/install-cli-tools.sh` | RTK, Trivy, GitHub CLI, and Docker CLI/plugins/group setup |
| `base/install-spec-kit.sh` | Spec Kit from PyPI via uv, bounded to major version 1 |
| `base/install-agent-browser.sh` | Agent Browser's Chrome for Testing and Linux dependencies |
| `gamedev/install-system-deps.sh` | Game-development libraries and the additional .NET runtime |
| `gamedev/install-godot.sh` | Checksum-validated Godot .NET editor |
| `gamedev/install-blender.sh` | Checksum-validated Blender archive |

BuildKit mounts each installer read-only for its own `RUN` step; the scripts are
not copied into the finished image. A script edit invalidates its installation
step and subsequent dependent layers, not earlier unrelated steps. The npm tools
share one installer step and are reinstalled together when that script changes.
Build from the repository root with the full checkout as context (`.`), as shown
below; a Dockerfile copied on its own is no longer sufficient. These scripts run
as root inside image builds and are **not host bootstrap commands**.

To add, remove, or update a tool, edit its installer, update executable links if
needed, and update the tool/version summaries below. Change the Dockerfile only
when its orchestration or build-argument interface changes. Keep bounded version
selectors, download checksums, and explicit build-argument overrides intact.

### Build the images

#### Image tool version policy (reviewed 2026-10-20)

Image-owned npm tools use major-version selectors rather than `@latest`, so a
rebuild can receive updates within the selected major without silently moving
to a later major. Spec Kit follows the same policy with a Python package version
range. uv, Bun, and RTK resolve the newest stable Git tag within their selected
major before invoking the upstream installers; prereleases are excluded and no
GitHub API lookup is needed. .NET uses the signed APT repository's SDK channel.
The authoritative base-tool selectors live in `scripts/image/base/`. The
following release values are a review-date snapshot, not an additional version
configuration:

| Tool | Selector | Current stable | Source |
|---|---|---:|---|
| Claude Code | `@anthropic-ai/claude-code@2` | 2.1.304 | [npm registry](https://registry.npmjs.org/) |
| OpenCode CLI | `@opencode/cli@2` | 2.0.32 | [npm registry](https://registry.npmjs.org/) |
| oh-my-opencode-slim | `oh-my-opencode-slim@3` | 3.0.5 | [npm registry](https://registry.npmjs.org/) |
| OpenCode Quota | `@slkiser/opencode-quota@6` | 6.2.1 (reviewed 2026-11-04) | [npm registry](https://registry.npmjs.org/@slkiser%2fopencode-quota/latest) |
| Context7 MCP | `@upstash/context7-mcp@4` | 4.4.4 | [npm registry](https://registry.npmjs.org/) |
| agent-browser | `agent-browser@0` | 0.39.1 | [npm registry](https://registry.npmjs.org/) |
| Figma MCP | `figma-developer-mcp@0` | 0.13.2 | [npm registry](https://registry.npmjs.org/) |
| Firebase CLI | `firebase-tools@15` | 15.34.0 | [npm registry](https://registry.npmjs.org/) |
| CodeGraph | `@colbymchenry/codegraph@1` | 1.6.2 | [npm registry](https://registry.npmjs.org/) |
| Spec Kit | `specify-cli>=1,<2` | 1.2.5 (reviewed 2026-10-31) | [Official PyPI install guide](https://github.com/github/spec-kit/blob/main/docs/install/pypi.md) |
| uv | stable `0.*` Git tags | 0.13.6 (verified 2026-10-31) | [uv releases](https://github.com/astral-sh/uv/releases) |
| .NET SDK | `dotnet-sdk-10.0` | 10.0.403 (verified 2026-10-31) | [Microsoft Debian packages](https://learn.microsoft.com/en-us/dotnet/core/install/linux-debian) |
| RTK | stable `v1.*` Git tags | v1.1.0 (reviewed 2026-10-31) | [RTK releases](https://github.com/rtk-ai/rtk/releases) |
| Bun | stable `bun-v1.*` Git tags | 1.4.4 (verified 2026-10-31) | [Bun releases](https://github.com/oven-sh/bun/releases) |
| Trivy | `trivy=0.*` | 0.76.0 | [Trivy releases](https://github.com/aquasecurity/trivy/releases) |
| GitHub CLI | `gh=2.*` | 2.102.0 | [GitHub CLI releases](https://github.com/cli/cli/releases) |
| Docker CLI | `docker-ce-cli=5:29.*` | 29.9.1 | [Docker Debian repository](https://download.docker.com/linux/debian/) |
| Docker Compose plugin | `docker-compose-plugin=5.*` | 5.6.0 | [Docker Debian repository](https://download.docker.com/linux/debian/) |
| Docker Buildx plugin | `docker-buildx-plugin=0.*` | 0.38.0 | [Docker Debian repository](https://download.docker.com/linux/debian/) |

Major selectors are compatibility bounds, not exact locks: they do not pin
transitive dependencies, and `@0` / `0.*` (including uv) can still accept breaking
minor releases before 1.0. Debian system libraries remain distro-managed. Node 24
remains the chosen LTS line; Godot and Blender retain their existing
explicit version pins, and .NET retains its configured channels. Project
`packageManager` choices remain project-controlled.

External APT tools use quoted major-version globs; Docker CLI's `5:` is the
Debian package epoch, not its upstream major. If a repository stops publishing
a matching version, the build fails rather than falling back to a newer major.
The release column records upstream versions; APT repositories may lag, so builds
select matching versions advertised by their configured package indexes.
The Git-tag selectors likewise fail if no matching stable tag exists or its
release assets are unavailable; they never fall back to an unbounded latest.
RTK's upstream installer continues to verify release archive SHA-256 checksums.

Build the base image:

```bash
docker build -f agentic-base.dockerfile -t braydens/agentic-base:latest .
```

Rebuild with `--no-cache` to refresh tools within their configured bounds,
including uv, .NET, Bun, RTK, and Spec Kit. Edit the installer selectors when
intentionally moving to a newer major; there are no base-tool version ARGs:

```bash
docker build --no-cache -f agentic-base.dockerfile -t braydens/agentic-base:latest .
```

**OpenCode v2 migration:** Back up `~/.config/opencode` and
`~/.local/share/opencode` before the first v2 launch; these host directories are
shared by the project containers. Do not run v1 and v2 against the same live
database. V1 plugins do not run in v2, so verify compatibility of any enabled
plugins, including oh-my-opencode-slim, before using your normal configuration.
See the [official migration guide](https://opencode.ai/v2/docs/migrate-v1).
Rebuilding does not update existing containers; preserve any needed writable-layer
data before recreating them from the new image.

The game-development image is derived from the base image. Build the base
first, then build the derived image:

```bash
docker build -f agentic-base.dockerfile -t braydens/agentic-base:latest .
docker build --platform=linux/amd64 -f agentic-gamedev.dockerfile -t braydens/agentic-gamedev:latest .
```

The derived image adds Godot 4.7.2 .NET and Blender 5.2.2 LTS. When overriding
Blender, update `BLENDER_VERSION` and `BLENDER_SHA256` together; pin the SHA256
from that archive's official release manifest so builds do not need to fetch
the manifest. The Blender archive uses the [IU13 mirror listed by Blender](https://mirror.blender.org/release/Blender5.2/)
because the official origin rejects non-browser requests in this environment;
the pinned checksum remains from the official manifest. Once the image is built,
the game-development smoke check verifies its tools and a conventional `net8`
test project (NuGet network access is required; the check uses a scratch project):

```bash
docker run --rm -i braydens/agentic-gamedev:latest bash -s < scripts/tests/smoke-gamedev.sh
```

### Verification

Run these offline checks after changing installers, Dockerfile wiring, or the
launcher. The image-installer checks validate Bash syntax and build-script
wiring; they do not execute privileged installers or prove downloaded tools run:

```bash
python3 scripts/tests/test-image-installers.py
bash scripts/tests/test-isoai.sh
python3 scripts/tests/test-isoai-ssh-agent.py
```

Rebuild affected images to validate real package installation; after changing the
base, rebuild it before gamedev. Use the gamedev smoke command above for runtime
validation. A successful offline check is not a substitute for an image build.

SSH relay regression checks use Python 3 and synthetic agents, not your SSH
keys. The Docker check requires a local game-development image and a checkout
path visible to the daemon; it does not pull an image. Set
`ISOAI_SSH_TEST_IMAGE` to use another locally available image with Python 3
and UID 1000 support.

```bash
python3 scripts/tests/test-isoai-ssh-docker.py
```

### Push to Docker Hub

```bash
docker push braydens/agentic-base:latest
```

### Repo layout

| Path | What it is |
|---|---|
| `agentic-base.dockerfile` | Base-image orchestration, build arguments, environment, and runtime setup. |
| `agentic-gamedev.dockerfile` | Derived game-development image orchestration and version/checksum arguments. |
| `scripts/image/base/` | Base-image tool installers; edit package selectors and installation details here. |
| `scripts/image/gamedev/` | Game-development dependency, Godot, and Blender installers. |
| `scripts/tests/` | Offline installer/launcher/SSH regressions and image-dependent smoke checks; see [Verification](#verification). |
| `scripts/isoai`, `scripts/isoai-ssh-agent.py` | Host-side container launcher and SSH-agent relay. |
| `AGENTS.md` | Contributor/agent rules and pointers to the authoritative maintenance documentation. |
| `init-firewall.sh` | Egress allowlist enforced via iptables/ipset. Edit the default host list near the top. |
| `.devcontainer/devcontainer.json` | Default Dev Container config (firewall off). |
| `.devcontainer/devcontainer.gd.jsonc` | Game-development Dev Container config using the derived image. |
| `.devcontainer/devcontainer.firewall.jsonc` | Variant with firewall enabled and the matching cap-drop loosening. |

---

## Methodology

### Mount strategy

The image expects **agent config and auth to be bind-mounted from the host**, not held in Docker named volumes. The shipped `devcontainer.json` mounts:

| Host path | Container path | Holds |
|---|---|---|
| `~/.claude/` | `/home/agent/.claude/` | settings, skills, project memory, agents, commands |
| `~/.claude.json` | `/home/agent/.claude.json` | project history, MCP registrations, auth metadata |
| `~/.config/opencode/` | `/home/agent/.config/opencode/` | OpenCode config (`opencode.json`, MCP servers) |
| `~/.local/share/opencode/` | `/home/agent/.local/share/opencode/` | OpenCode auth tokens, data |
| `~/.config/rtk/` | `/home/agent/.config/rtk/` | RTK config (`config.toml`) |
| `~/.local/share/rtk/` | `/home/agent/.local/share/rtk/` | RTK runtime state — `tee/` logs of failed-command full output, `rtk gain` savings stats |
| `~/.config/configstore/` | `/home/agent/.config/configstore/` | Firebase CLI auth (`firebase-tools.json`) and update-check state (`update-notifier-firebase-tools.json`) |
| `~/.cache/firebase/` | `/home/agent/.cache/firebase/` | Firebase CLI cache, including emulator/tool downloads |
| `~/.config/gh/` | `/home/agent/.config/gh/` | GitHub CLI auth/config (`gh auth login`) |
| `~/.codegraph/` | `/home/agent/.codegraph/` | Optional CodeGraph global state/config; project indexes stay in each workspace's `./.codegraph/` |

**Why bind mounts instead of named volumes.** One source of truth between containerized agents and native Claude/OpenCode/Firebase/GitHub CLI/CodeGraph running directly on the WSL host. A skill installed once on the host is visible in every container; an MCP server registered in any container is visible to the host CLI; `firebase login`, `gh auth login`, and update-check metadata persist across rebuilds. Curated parts of `~/.claude/` (`settings.json`, `skills/`, `commands/`) can be checked into a dotfiles repo.

**Trade-off being made.** All containers + native usage share one global state — there's no per-project isolation of `~/.claude.json` or Firebase's configstore login. That's the intent, not a bug. If you want per-project isolation, swap the bind mounts for named volumes.

**Why `~/.claude.json` is a separate mount.** It's a single-file database Claude maintains alongside the `~/.claude/` directory: OAuth account binding, recently-opened-projects index, per-project trust answers, per-project permission rules, auto-updater state, and user-scope MCP server lists. Without bind-mounting it, every container rebuild starts with no login session, no project trust answers, no recent-projects list — you'd re-authenticate every time. The split (which state lives where) is historical and has drifted across Claude Code versions; treat both as "persist together."

**UID alignment.** The container's `agent` user is UID/GID 1000. On WSL the default user is also 1000, so the bind mount needs no `chown` dance. If your WSL user is on a different UID, `id -u` will tell you — align the host user to 1000 or open an issue to add a `--build-arg`.

**What's gitignore-able.** Treat the host paths as part of your dotfiles. `~/.claude/settings.json`, `~/.claude/skills/`, `~/.claude/commands/` are good candidates for versioning. `~/.claude.json`, `~/.config/configstore/firebase-tools.json`, `~/.config/gh/hosts.yml`, and anything that holds OAuth tokens or `FIGMA_API_KEY` values should stay out of git.

**Belt-and-suspenders for the bind-mount sources (`initializeCommand`).** When a bind-mount source path doesn't exist on the host, the Docker daemon auto-creates it — but as root, since dockerd runs as root, leaving the container's `agent` user unable to write into the supposed config dir. For the `~/.claude.json` file-bind specifically, Docker can't tell file-vs-dir intent and will create it as an empty *directory*, which silently breaks both agents. Both devcontainer variants set `initializeCommand` to `mkdir -p` the dirs and `touch ~/.claude.json` on the host *before* mounts resolve — this also keeps Firebase, GitHub CLI, and CodeGraph state writable. Even if you skipped first-run §step 2, the devcontainer attach won't leave you with root-owned auto-created paths. The standalone `docker run` invocations below have no such safety net, so for those the first-run mkdir is still required.

### Browser tooling

The image does not install the standalone Playwright CLI, provision project-specific Playwright browser binaries, create a Playwright browser cache volume, or run Playwright browser-install hooks when a workspace starts. The `agent-browser` npm CLI is included with its Chrome for Testing browser and required Linux dependencies already installed at build time by `agent-browser install --with-deps`. No manual `agent-browser install` is needed. Project-specific Playwright browser setup remains under each project's control; in hardened containers, installing additional OS packages may require a project-specific image or another privileged setup.

### Workspace path and Docker-out-of-Docker

The default `devcontainer.json` mounts the workspace at the **same path inside the container as it has on the host** (`workspaceFolder` and `workspaceMount` both use `${localWorkspaceFolder}`) rather than the conventional `/workspace`. The shipped Dev Container configs do not mount the host Docker socket. For explicit Docker-out-of-Docker opt-in, add `"source=/var/run/docker.sock,target=/var/run/docker.sock,type=bind"` to the config's `mounts` array and rebuild/reopen the Dev Container. Existing Dev Containers must be rebuilt to remove a socket mount inherited from an older config; editing the config does not retrofit an existing container.

When that socket is explicitly mounted, the container's Docker CLI can operate the **host** daemon. Bind mounts in a `docker-compose.yml` are then resolved by that daemon. A relative mount like `./data:/data` expands to `$PWD/data` inside the container, and the host daemon then looks for that exact path on the host filesystem. If the container's `$PWD` were `/workspace`, the host would look for `/workspace/data` and find nothing. Mounting at the original host path keeps `$PWD` valid on both sides and lets compose stacks defined inside the container work against the host daemon.

The same setup also sets `COMPOSE_PROJECT_NAME` to the workspace folder's basename, so containers, networks, and volumes created by compose stacks from different repos using this pattern don't collide on the shared host daemon.

### Git and Git LFS in the base image

`git` and `git-lfs` are baked in, with LFS filters registered system-wide (`git lfs install --system`). Any repo with LFS-tracked files works in `/workspace` without per-user setup — `git clone`, `git pull`, and `git push` handle large files transparently.

LFS blobs land under `.git/lfs/objects`. On Windows bind-mounted workspaces they pay the WSL2 translation cost flagged below, so LFS-heavy repos are a good candidate for VS Code's **Clone Repository in (Named) Container Volume** flow — the `.git` tree lives entirely in a Docker volume on the Linux side and LFS smudge/clean operations run at native speed.

### Windows host caveats and the WSL2 recommendation

When the consumer's workspace is bind-mounted from a Windows path (the default for VS Code "Reopen in Container" on Windows + Docker Desktop), a few rough edges show up:

- **File watchers don't fire across the bind mount.** Linux's `inotify` doesn't propagate from Windows-side file changes. Tools running inside the container — Vite's HMR watcher, Nx's project-graph file watcher, etc. — won't notice when you save files in the editor. The fix is to put each tool in polling mode (e.g., `server.watch.usePolling = true` in `vite.config.*`). VS Code's own editor-to-container file sync uses a separate mechanism and works fine.
- **`node_modules` reads are slower than they need to be** because every `require()` resolves through the WSL2 file translation layer.

The ideal solution is **WSL2-native**: clone the consumer repo into your WSL2 distro (e.g., `~/dev/...` inside Ubuntu/Debian) and reopen the devcontainer from there. The bind mount becomes Linux-on-Linux — inotify works, mtimes are stable, file I/O is fast. This is the recommended setup for daily development on Windows hosts.

You can also "Clone Repository in Container Volume" — VS Code handles most of this natively, but the files don't live outside the container, which can be hard to work with depending on your workflow.

### Hardening flag reference

- `--cap-drop=ALL` — drops all Linux capabilities. Casualties: `ping`, `traceroute`, cross-process ptrace.
- `--security-opt=no-new-privileges:true` — blocks setuid/setgid escalation.
- `--pids-limit=4096` — fork-bomb mitigation, sized for parallel builds.
- `--tmpfs=/tmp:rw,noexec,nosuid,size=512m` — ephemeral `/tmp`, no executing dropped binaries, capped size (optional; defaults to half RAM so might be unnecessary).
- `--cap-add=NET_ADMIN` — required only when running `init-firewall.sh`. Mutually exclusive with `--cap-drop=ALL`.
