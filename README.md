# isolated-ai

A repo to hold my current agentic developer workflow revolving around Docker isolation. Included is a base image hosting 2 coding agents (maybe more to come if I start using them) — Claude Code, OpenCode — for use as a Dev Container base or as a standalone host with optional hardening flags.

Image tag: `braydens/agentic-base:latest`

The image ships:

| Tool | Binary | Kind | Purpose |
|---|---|---|---|
| Claude Code | `claude` | Coding agent | Anthropic's CLI |
| OpenCode | `opencode` | Coding agent | OpenCode's CLI |
| context7 | `context7-mcp` | MCP | Up-to-date library docs (Upstash) |
| Figma (Framelink) | `figma-developer-mcp` | MCP | Public Figma REST API; requires a personal access token |
| Playwright | `playwright-cli` | CLI + skills | Browser automation via [Playwright CLI](https://github.com/microsoft/playwright-cli) |
| uv | `uv` | Python tool manager | Standalone Rust binary, fetches its own Python on demand |

Skip to:

- [Usage](#usage) — first-run setup, Dev Container and standalone invocations
- [Contributing](#contributing) — build and push the base image
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
mkdir -p ~/.claude ~/.config/opencode ~/.local/share/opencode
touch ~/.claude.json
```

**3. Install the Playwright skills.** Runs inside a throwaway container so you don't need Node + npm on the host; the skills land in your bind-mounted `~/.claude/skills/` (and `~/.config/opencode/` if the installer targets it):

```bash
docker run --rm \
  -v "$HOME/.claude:/home/agent/.claude" \
  -v "$HOME/.config/opencode:/home/agent/.config/opencode" \
  braydens/agentic-base:latest \
  playwright-cli install --skills
```

Re-run the same command later to update skills.

**4. Register the MCP servers.** Once is enough — registrations persist in your host `~/.claude.json` and every container plus your native `claude` will see them:

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

**5. Playwright browsers — usually handled for you.** The shipped `devcontainer.json` includes a `postCreateCommand` that installs the project's pinned Chromium revision automatically whenever the workspace's `package.json` references Playwright. Browsers land in `~/.cache/ms-playwright/`, backed by the `isolated-pw-browsers` named volume so they persist across rebuilds without polluting your host home. See [Playwright browsers — cache volume + auto-install](#playwright-browsers--cache-volume--auto-install) for the rationale.

For standalone `docker run` invocations (or to manually add Firefox/WebKit), do it from inside a running container:

```bash
npx playwright install chromium    # or firefox / webkit
```

Do **not** pass `--with-deps` — that half needs sudo, which the hardened defaults (`--security-opt=no-new-privileges:true`) block. The system libs are already baked into the image.

### Use as a Dev Container base

Drop a `.devcontainer/devcontainer.json` in your project pointing at this image — or copy [`.devcontainer/devcontainer.json`](.devcontainer/devcontainer.json) as a starting point. If you need extra layers, create `.devcontainer/Dockerfile`:

```dockerfile
FROM braydens/agentic-base:latest
# project-specific layers (Bun, env vars, etc.)
```

and update your `devcontainer.json` to build from it.

**Auth forwarding (Dev Containers extension).** When you "Reopen in Container," VS Code handles git auth automatically — no devcontainer.json changes needed:

- **SSH** — your host's SSH agent socket is forwarded in via `SSH_AUTH_SOCK`. Keys stay on the host.
- **HTTPS** — an in-container credential helper proxies to your host credential manager (Windows Credential Manager, macOS Keychain, libsecret on Linux).
- **Identity** — host `user.name`/`user.email` get injected so commits carry the right author.

**Firewall variant.** For egress allowlisting, use [`devcontainer.firewall.jsonc`](.devcontainer/devcontainer.firewall.jsonc) instead of the default. See [Firewall allowlist](#firewall-allowlist) for what's allowed and how to add hosts.

### Use as a standalone container

The image has no `ENTRYPOINT` or `CMD` — invoke the agent you want explicitly. Mount paths below match the Dev Container's bind-mount strategy (see [Mount strategy](#mount-strategy)).

**Workspace run — hardened, firewall off:**

```bash
docker run -it --rm \
  --cap-drop ALL \
  --security-opt no-new-privileges:true \
  --pids-limit 4096 \
  --tmpfs /tmp:rw,noexec,nosuid,size=512m \
  -v "$HOME/.claude:/home/agent/.claude" \
  -v "$HOME/.claude.json:/home/agent/.claude.json" \
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
  -v "$PWD:/workspace" \
  braydens/agentic-base:latest \
  sh -c 'sudo /usr/local/bin/init-firewall.sh && exec claude --dangerously-skip-permissions'
```

**Git auth without VS Code:**

- **Forward an SSH agent socket** — add `-v "${SSH_AUTH_SOCK}:/ssh-agent" -e SSH_AUTH_SOCK=/ssh-agent`. Keys stay on the host.
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

### Build the image

Rebuild whenever you want fresher agent versions — everything is pinned to `@latest`:

```bash
docker build -f agentic-base.dockerfile -t braydens/agentic-base:latest .
```

### Push to Docker Hub

```bash
docker push braydens/agentic-base:latest
```

### Repo layout

| Path | What it is |
|---|---|
| `agentic-base.dockerfile` | The base image definition. Add/remove agents and MCP servers here. |
| `init-firewall.sh` | Egress allowlist enforced via iptables/ipset. Edit the default host list near the top. |
| `.devcontainer/devcontainer.json` | Default Dev Container config (firewall off). |
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

The Playwright browser cache (`~/.cache/ms-playwright/`) stays on a named volume (`isolated-pw-browsers`) — browsers are bulky binaries, not user-edited config, and you don't want them living in your host home.

**Why bind mounts instead of named volumes.** One source of truth between containerized agents and native Claude/OpenCode running directly on the WSL host. A skill installed once on the host is visible in every container; an MCP server registered in any container is visible to the host CLI. Curated parts of `~/.claude/` (`settings.json`, `skills/`, `commands/`) can be checked into a dotfiles repo.

**Trade-off being made.** All containers + native usage share one global state — there's no per-project isolation of `~/.claude.json`. That's the intent, not a bug. If you want per-project isolation, swap the bind mounts for named volumes.

**Why `~/.claude.json` is a separate mount.** It's a single-file database Claude maintains alongside the `~/.claude/` directory: OAuth account binding, recently-opened-projects index, per-project trust answers, per-project permission rules, auto-updater state, and user-scope MCP server lists. Without bind-mounting it, every container rebuild starts with no login session, no project trust answers, no recent-projects list — you'd re-authenticate every time. The split (which state lives where) is historical and has drifted across Claude Code versions; treat both as "persist together."

**UID alignment.** The container's `agent` user is UID/GID 1000. On WSL the default user is also 1000, so the bind mount needs no `chown` dance. If your WSL user is on a different UID, `id -u` will tell you — align the host user to 1000 or open an issue to add a `--build-arg`.

**What's gitignore-able.** Treat the host paths as part of your dotfiles. `~/.claude/settings.json`, `~/.claude/skills/`, `~/.claude/commands/` are good candidates for versioning. `~/.claude.json` and anything that holds OAuth tokens or `FIGMA_API_KEY` values should stay out of git.

### Playwright — CLI + skills, not MCP

The image used to ship `@playwright/mcp`. Upstream now points coding agents at [Playwright CLI](https://github.com/microsoft/playwright-cli) with **skills** instead. From the playwright-cli README:

> Modern coding agents increasingly favor CLI–based workflows exposed as SKILLs over MCP because CLI invocations are more token-efficient: they avoid loading large tool schemas and verbose accessibility trees into the model context.

[Playwright MCP](https://github.com/microsoft/playwright-mcp) is still alive for long-running-state use cases (exploratory automation, self-healing tests). For day-to-day "drive a browser from inside an agent," CLI + skills wins on token economy, which is why this image now installs `@playwright/cli` and ships skills.

**Skills install via the image, not the host.** Step 3 of [First-run setup](#first-run-setup) runs `playwright-cli install --skills` inside a throwaway container, writing into the host-mounted `~/.claude/` (and `~/.config/opencode/`). This avoids forcing Node + npm onto the host just to bootstrap. Re-run the same command to pull skill updates after a base-image rebuild.

### Playwright browsers — cache volume + auto-install

Browser binaries (Chromium, Firefox, WebKit) are **not** baked into the image — only the system libs they need are. Browsers live in `~/.cache/ms-playwright/`, backed by the `isolated-pw-browsers` named volume so they survive container rebuilds.

**Why not bake them in.** Playwright pins browser binaries to a *specific revision per Playwright version* (e.g. Playwright 1.49 wants `chromium-1140`, 1.51 wants `chromium-1155`). Baking one revision into the image would help only when a project happens to use that exact Playwright version; every other project would re-download regardless. The size cost (~300MB–1GB compressed for all three engines) buys very little practical win. The cache volume covers the actually-useful case: "don't re-download what's already on disk across rebuilds."

**The post-create auto-install.** The shipped `devcontainer.json` includes a `postCreateCommand` that runs:

```bash
if [ -f package.json ] && grep -q '"playwright"' package.json; then
  npx --yes playwright install chromium
fi
```

This fires once on container create, only if the workspace's `package.json` references Playwright. It downloads the project's pinned Chromium revision into the cache (no-op if it's already there). After the first attach you never see the "browser not found" prompt — projects on the same Playwright version reuse the cache, new versions add another revision next to the existing ones. Standalone `docker run` invocations don't get this — for them it's still a one-time `npx playwright install` after attaching.

**Firewall caveat.** `cdn.playwright.dev` (the browser download CDN) is not in the default firewall allowlist. With the firewall enabled, either add `-e FIREWALL_EXTRA_HOSTS=cdn.playwright.dev` or install browsers once with the firewall off, then enable it.

**Cache cleanup.** Over time the volume accumulates revisions from every Playwright version you've touched. If it gets uncomfortable, `npx playwright uninstall --all` inside a container clears it, then re-run install for the versions you currently care about.

### Workspace path and Docker-out-of-Docker

The default `devcontainer.json` mounts the workspace at the **same path inside the container as it has on the host** (`workspaceFolder` and `workspaceMount` both use `${localWorkspaceFolder}`) rather than the conventional `/workspace`. This matters as soon as you do Docker-out-of-Docker — running `docker` or `docker compose` from inside the container against the host's daemon via the mounted `/var/run/docker.sock`.

Bind mounts in a `docker-compose.yml` are resolved by the daemon that runs them, which here is the **host** daemon. A relative mount like `./data:/data` expands to `$PWD/data` inside the container, and the host daemon then looks for that exact path on the host filesystem. If the container's `$PWD` were `/workspace`, the host would look for `/workspace/data` and find nothing. Mounting at the original host path keeps `$PWD` valid on both sides and lets compose stacks defined inside the container "just work" against the host daemon.

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
