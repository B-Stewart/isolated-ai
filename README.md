# isolated-ai

Local-only Docker base image hosting four coding agents — Claude Code, OpenCode, Codex CLI, Gemini CLI — for use as a Dev Container base or as a standalone hardened agent host.

Image tag: `braydens/agentic-base:latest`

## Build

```
docker build -f agentic-base.dockerfile -t braydens/agentic-base:latest .
```

Rebuild whenever you want fresher agent versions as everything is pinned to @latest.

## Push

If you want to push the new version to docker hub

```
docker push braydens/agentic-base:latest
```

## Use as a Dev Container base

You can use this project's [devcontainer.json](.devcontainer/devcontainer.json) as a starting point for your workspace.

If you need extras in your project's specific docker file you can create a custom docker file that extends it in `.devcontainer/Dockerfile`:

```dockerfile
FROM braydens/agentic-base:latest
# project-specific layers (Bun, env vars, etc.)
```

And update your devcontainer configuration to point to it.

## Agents, skills, and hooks in this repo

This repo doubles as a working example of a cost-tiered SDLC agent setup for both Claude Code and OpenCode. The image itself ships none of this — you opt in by using this devcontainer as your starting point, or by mounting these directories into a downstream image.

- **[`agents/`](agents/README.md)** — 8 custom subagents with per-agent model selection (Sonnet 4.6 for review/test/debug, Haiku 4.5 for security/docs/deps/PR/librarian). All written from scratch in this repo.
- **[`skills/`](skills/README.md)** — 4 workflow-discipline skills **vendored verbatim from [obra/superpowers](https://github.com/obra/superpowers)** under the MIT license: `writing-plans`, `executing-plans`, `test-driven-development`, `systematic-debugging`. Copyright © 2025 Jesse Vincent. Full license text in [`skills/LICENSE.superpowers`](skills/LICENSE.superpowers). Only these four were cherry-picked; the dispatch/worktree skills from upstream are intentionally omitted.
- **[`hooks/`](hooks/README.md)** — example PostToolUse hook (TypeScript typecheck after edits). Settings snippet to merge into `~/.claude/settings.json`, not a deployable file.

### How the sync works

[`agents/sync-agents`](agents/sync-agents) is a small Python script wired into [`.devcontainer/devcontainer.json`](.devcontainer/devcontainer.json) as a `postStartCommand`. On every container start it:

1. Copies each `agents/*.md` to `~/.claude/agents/` verbatim.
2. Transforms each into opencode format and writes to `~/.config/opencode/agents/` — drops `name:` (opencode derives identity from filename), remaps `model: sonnet` → `anthropic/claude-sonnet-4-6`, converts CC's `tools:` array to opencode's `permission:` object, adds `mode: subagent`.
3. Recursively copies each `skills/*/` directory to `~/.claude/skills/`.

Skills are **Claude Code only** — opencode installs skills via its own plugin manager (a `plugin` array entry in `opencode.json`), not a filesystem dir. If you want the vendored skills in opencode too, add `superpowers@git+https://github.com/obra/superpowers.git` to your `opencode.json` — note that pulls all 14 superpowers skills, not just our four.

### Bring your own agents

To use this image with your own canonical agent directory living on the host (instead of, or alongside, this repo's `agents/`), see the commented `BYO AGENTS:` block in [`.devcontainer/devcontainer.json`](.devcontainer/devcontainer.json) and the matching section in [`agents/README.md`](agents/README.md). The sync script picks up whatever lives at `/workspace/agents` — bind-mount your own dir there and it just works.

## Windows host caveats

When the consumer's workspace is bind-mounted from a Windows path (the default for VS Code "Reopen in Container" on Windows + Docker Desktop), a few rough edges show up:

- **File watchers don't fire across the bind mount.** Linux's `inotify` doesn't propagate from Windows-side file changes. Tools running inside the container — Vite's HMR watcher, Nx's project-graph file watcher, etc. — won't notice when you save files in the editor. The fix is to put each tool in polling mode (e.g., `server.watch.usePolling = true` in `vite.config.*`). VS Code's own editor-to-container file sync uses a separate mechanism and works fine.
- **`node_modules` reads are slower than they need to be** because every `require()` resolves through the WSL2 file translation layer.

The fully-correct fix is **WSL2-native**: clone the consumer repo into your WSL2 distro (e.g., `~/dev/...` inside Ubuntu/Debian) and reopen the devcontainer from there. The bind mount becomes Linux-on-Linux — inotify works, mtimes are stable, file I/O is fast. This is the recommended setup for daily development on Windows hosts; the Windows-side bind mount works for casual or one-off use but expect the caveats above. VS Code handles most of this natively by using the "Clone Repository in Container Volume" command.

## Git and Git LFS

`git` and `git-lfs` are baked into the image, with LFS filters registered system-wide (`git lfs install --system`). Any repo with LFS-tracked files works in `/workspace` without per-user setup — `git clone`, `git pull`, and `git push` handle large files transparently.

LFS blobs land under `.git/lfs/objects`. On Windows bind-mounted workspaces they pay the same WSL2 translation cost flagged above, so LFS-heavy repos are a good candidate for VS Code's **Clone Repository in (Named) Container Volume** flow — the `.git` tree lives entirely in a Docker volume on the Linux side and LFS smudge/clean operations run at native speed.

### Auth from inside the container (VS Code path)

When you "Reopen in Container" from VS Code, the Dev Containers extension forwards your host's git credentials automatically — no devcontainer.json changes needed:

- **SSH** — your host's running SSH agent socket is mounted in and `SSH_AUTH_SOCK` is set. Keys never enter the container; signing happens on the host.
- **HTTPS** — a credential helper inside the container proxies back to your host's credential manager (Windows Credential Manager, macOS Keychain, libsecret on Linux). Tokens stored by `gh auth` on the host, GitLab/Bitbucket creds, etc. are all reachable.
- **Identity** — `user.name` and `user.email` from your host git config are injected so commits carry the correct author.

The hardening flags (`--cap-drop=ALL`, `no-new-privileges`) don't interfere — credential forwarding rides on a socket mount, not a Linux capability.

### Auth outside VS Code (standalone runs)

When you launch the container directly via `docker run` (see "Standalone hardened use" below), VS Code's forwarding isn't in play. Options, easiest first:

- **Forward an SSH agent socket manually** — `-v "${SSH_AUTH_SOCK}:/ssh-agent" -e SSH_AUTH_SOCK=/ssh-agent` (Linux/macOS host). Keys stay on the host.
- **Mount `~/.ssh` read-only** — simplest, but exposes the key files to the container; only acceptable for trusted workloads.
- **Add the `gh` CLI to your downstream image** — not pre-installed (keeps the base lean). Mount a persistent auth volume, run `gh auth login` once, then `gh auth setup-git` configures git's HTTPS credential helper inside the container. `.devcontainer/devcontainer.json` has a commented-out example mount (`gh-auth` → `/home/agent/.config/gh`) showing the pattern.

## Pre-installed MCP servers

Four MCP servers ship on PATH inside the image. Versions are pinned in `agentic-base.dockerfile`; rebuild the base to update them.

| Server | Binary | Purpose |
|---|---|---|
| context7 | `context7-mcp` | Up-to-date library docs (Upstash) |
| Playwright | `playwright-mcp` | Browser automation; needs `npx playwright install chromium` once per `pw-browsers` cache |
| Figma (Framelink) | `figma-developer-mcp` | Public Figma REST API; requires a personal access token |
| Serena | `serena start-mcp-server` | Code-symbolic agent toolkit (uv-installed) |

### Registering them with Claude Code

MCP configs live in `~/.claude/settings.json`, which is mounted via the `claude-auth` named volume — register once and they persist across container restarts and rebuilds. Run inside any container that uses this base:

```bash
# context7 — no args
claude mcp add -s user context7 -- context7-mcp

# Playwright (Chromium binaries fetched on first use; mount pw-browsers in your consumer to persist)
claude mcp add -s user playwright -- playwright-mcp

# Figma (Framelink) — supply your token via env var; --stdio puts the server in MCP transport mode
claude mcp add -s user -e FIGMA_API_KEY=<your-figma-pat> figma -- figma-developer-mcp --stdio

# Serena
claude mcp add -s user serena -- serena start-mcp-server
```

Inspect or remove with `claude mcp list` and `claude mcp remove <name>`.

### Registering them with OpenCode

OpenCode has no `opencode mcp add` CLI — MCP servers are declared in `opencode.json` directly. Two places work:

- **Global** — `~/.config/opencode/opencode.json` inside the container. Backed by the `opencode-config` named volume in the default `devcontainer.json`, so MCP registrations persist across rebuilds (parallel to how `claude-auth` persists Claude's `~/.claude.json`). Auth lives in a separate `opencode-auth` volume; OpenCode splits config and data across two XDG dirs, hence two volumes.
- **Project-level** — `opencode.json` at the repo root. Version-controlled and scoped to the project; useful when MCP setup is part of the repo's contract rather than a per-user choice.

Either way, drop the servers under the top-level `mcp` key:

```jsonc
{
  "$schema": "https://opencode.ai/config.json",
  "mcp": {
    "context7": {
      "type": "local",
      "command": ["context7-mcp"],
      "enabled": true
    },
    "playwright": {
      "type": "local",
      "command": ["playwright-mcp"],
      "enabled": true
    },
    "figma": {
      "type": "local",
      "command": ["figma-developer-mcp", "--stdio"],
      "environment": { "FIGMA_API_KEY": "<your-figma-pat>" },
      "enabled": true
    },
    "serena": {
      "type": "local",
      "command": ["serena", "start-mcp-server"],
      "enabled": true
    }
  }
}
```

Inspect connection state and auth with `opencode mcp list`; troubleshoot a misbehaving server with `opencode mcp debug <name>`.

### Notes

- **Playwright browsers** aren't baked into the image (the apt block has only the runtime libs). Run `npx playwright install chromium` once after registering the MCP; the binaries land at `~/.cache/ms-playwright`, which is pre-created with `agent` ownership in the image. Mount a named volume there in your consumer if you want them to persist across rebuilds.
- **Serena** may write per-user config to `~/.serena/`. That directory is *not* in the pre-create list and *not* on a named volume, so it gets reset on container rebuild. If you want it to persist, mount a `serena-config` volume at `/home/agent/.serena` in your consumer.
- **Figma personal access token** lives in your Claude config (`~/.claude/settings.json`) via `claude mcp add -e`. Treat that volume as a credential store accordingly.

## Standalone hardened use

The image is neutral — no `ENTRYPOINT`, no `CMD`. Invoke the agent you want explicitly.

### Workspace run (hardened, firewall off)

```powershell
$dockerArgs = @(
  '-it', '--rm',
  '--cap-drop', 'ALL',
  '--security-opt', 'no-new-privileges:true',
  '--pids-limit', '4096',
  '--tmpfs', '/tmp:rw,noexec,nosuid,size=512m',
  '-v', 'claude-auth:/home/agent/.claude',
  '-v', "${PWD}:/workspace",
  'local/agentic-base:1',
  'claude', '--dangerously-skip-permissions'
)
docker run @dockerArgs
```

### Workspace run (hardened, firewall on)

Firewall needs `NET_ADMIN`, so `--cap-drop ALL` is replaced by targeted drops. Mount the script invocation as the entrypoint via a wrapper.

```powershell
$dockerArgs = @(
  '-it', '--rm',
  '--cap-drop', 'NET_RAW',
  '--cap-drop', 'SYS_PTRACE',
  '--cap-add', 'NET_ADMIN',
  '--security-opt', 'no-new-privileges:true',
  '--pids-limit', '4096',
  '--tmpfs', '/tmp:rw,noexec,nosuid,size=512m',
  '-v', 'claude-auth:/home/agent/.claude',
  '-v', "${PWD}:/workspace",
  'local/agentic-base:1',
  'sh', '-c', 'sudo /usr/local/bin/init-firewall.sh && exec claude --dangerously-skip-permissions'
)
docker run @dockerArgs
```

## Run modes

| Mode | cap-drop ALL | cap-add NET_ADMIN | Firewall | Use case |
|---|---|---|---|---|
| Devcontainer (default) | yes | no | off | VS Code attached, dev workflow |
| Devcontainer + firewall | partial | yes | on | development with egress allowlist |
| Standalone hardened | yes | no | off | one-shot agent run, max isolation |
| Standalone + firewall | partial | yes | on | one-shot, egress-controlled |

## Firewall allowlist

`init-firewall.sh` allowlists egress to:

- `registry.npmjs.org`
- `api.anthropic.com`, `console.anthropic.com`
- `github.com`, `api.github.com`, `objects.githubusercontent.com`, `raw.githubusercontent.com`, `codeload.github.com`

Add hosts via `FIREWALL_EXTRA_HOSTS` (comma-separated):

```
-e FIREWALL_EXTRA_HOSTS=registry.opencodeai.com,gemini.google.com
```

DNS (UDP/53) is allowed unconditionally so resolution works after rules are applied.

CDN-backed targets (npm, GitHub objects) rotate IPs over hours/days. If a long-lived container starts seeing previously-working hosts blocked, re-run the script to re-resolve.

## Hardening flag reference

- `--cap-drop=ALL` — drops all Linux capabilities. Casualties: `ping`, `traceroute`, cross-process ptrace.
- `--security-opt=no-new-privileges:true` — blocks setuid/setgid escalation.
- `--pids-limit=4096` — fork-bomb mitigation, sized for parallel builds.
- `--tmpfs=/tmp:rw,noexec,nosuid,size=512m` — ephemeral `/tmp`, no executing dropped binaries, capped size.
- `--cap-add=NET_ADMIN` — required only when running `init-firewall.sh`. Mutually exclusive with `--cap-drop=ALL`.
