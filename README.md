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
