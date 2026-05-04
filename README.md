# isolated-ai

Local-only Docker base image hosting four coding agents — Claude Code, OpenCode, Codex CLI, Gemini CLI — for use as a Dev Container base or as a standalone hardened agent host.

Image tag: `local/agentic-base:1` (no registry; lives in your local Docker daemon).

## Build

```powershell
docker build -f agentic-base.dockerfile -t local/agentic-base:1 .
```

Rebuild whenever you want fresher agent versions; bump the pinned versions in `agentic-base.dockerfile` first.

## Use as a Dev Container base

In a consumer repo's `.devcontainer/Dockerfile`:

```dockerfile
FROM local/agentic-base:1
# project-specific layers (Bun, env vars, etc.)
```

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

### Figma desktop alternative

If you'd rather use Figma's desktop app's local MCP server (more capable — supports write operations, Code Connect, FigJam) instead of Framelink's REST-based one, point Claude at the desktop's SSE endpoint via Docker's host-gateway DNS:

```bash
claude mcp add -s user -t sse figma-desktop http://host.docker.internal:3845
```

The Figma desktop app must be running on your host. Note: when the egress firewall is enabled it does NOT allowlist `host.docker.internal` by default — extend the allowlist via `FIREWALL_EXTRA_HOSTS` if you turn the firewall on while using the desktop server.

### Notes

- **Playwright browsers** aren't baked into the image (the apt block has only the runtime libs). Run `npx playwright install chromium` once after registering the MCP; the binaries land at `~/.cache/ms-playwright`, which is pre-created with `agent` ownership in the image. Mount a named volume there in your consumer if you want them to persist across rebuilds.
- **Serena** may write per-user config to `~/.serena/`. That directory is *not* in the pre-create list and *not* on a named volume, so it gets reset on container rebuild. If you want it to persist, mount a `serena-config` volume at `/home/agent/.serena` in your consumer.
- **Figma personal access token** lives in your Claude config (`~/.claude/settings.json`) via `claude mcp add -e`. Treat that volume as a credential store accordingly.

## Standalone hardened use

The image is neutral — no `ENTRYPOINT`, no `CMD`. Invoke the agent you want explicitly.

### One-time auth setup (per agent)

Each agent gets its own named Docker volume so auth state survives container restarts.

```powershell
# Create one volume per agent you intend to use
docker volume create claude-auth
docker volume create opencode-auth
docker volume create codex-auth
docker volume create gemini-auth
```

First-run login (Claude shown; same pattern for the others, with the agent's config dir):

```powershell
$dockerArgs = @(
  '-it', '--rm',
  '-v', 'claude-auth:/home/agent/.claude',
  '-v', "${PWD}:/workspace",
  'local/agentic-base:1',
  'claude', 'login'
)
docker run @dockerArgs
```

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
