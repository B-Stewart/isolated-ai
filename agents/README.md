# Agents

Canonical subagent definitions for both [Claude Code](https://code.claude.com) and [opencode](https://opencode.ai). One source of truth here; `sync-agents` writes per-harness variants into each harness's config dir.

## The team

| Agent | Model | Role |
|---|---|---|
| `code-reviewer` | Sonnet 4.6 | Reviews diffs for correctness, security, perf, maintainability. Reports only. |
| `test-author` | Sonnet 4.6 | Writes focused tests for new behavior. Matches project test framework. |
| `debugger` | Sonnet 4.6 | Hunts root cause with fresh context. Reports findings, doesn't apply fixes. |
| `security-auditor` | Haiku 4.5 | Pattern-matches common vulns. Complements SAST tooling. |
| `tech-writer` | Haiku 4.5 | Writes/updates docs to match project style. |
| `dependency-auditor` | Haiku 4.5 | Vets new third-party deps for maintenance, CVEs, license, alternatives. |
| `commit-and-pr-drafter` | Haiku 4.5 | Drafts commit/PR messages from diffs. User runs the actual command. |
| `librarian` | Haiku 4.5 | Fetches authoritative docs for unfamiliar libraries/APIs via context7 MCP + WebFetch. |

Main session (Opus) orchestrates and implements. Subagents handle isolated specialist work.

Codebase search is handled by Claude Code's built-in `Explore` agent (Haiku) — no custom subagent needed.

See `../skills/` for workflow-discipline skills (plan-first, TDD, systematic debugging) — **vendored from [obra/superpowers](https://github.com/obra/superpowers) under MIT**, not authored here.

## How `sync-agents` works

`sync-agents` handles both `/workspace/agents/` (this directory) and `/workspace/skills/`. Agents go to both Claude Code and opencode; skills go to Claude Code only (opencode uses its own plugin manager for skills).

Canonical agent files in this directory use **Claude Code frontmatter**:

```yaml
---
name: code-reviewer
description: Use proactively after writing or modifying code...
model: sonnet
tools: Read, Grep, Glob, Bash
---
```

`sync-agents` reads each `.md` here and emits:

- **`~/.claude/agents/<file>.md`** — copied verbatim
- **`~/.config/opencode/agents/<file>.md`** — transformed:
  - `name:` dropped (opencode uses filename)
  - `model: sonnet` → `model: anthropic/claude-sonnet-4-6` (full provider/model ID)
  - `tools: Read, Edit, Bash` → `permission: { edit: allow, bash: allow, webfetch: deny }`
  - `mode: subagent` added

Both targets sit inside named volumes (`claude-auth`, `opencode-config`), so they persist across container rebuilds.

## When does it run?

The devcontainer's `postStartCommand` runs `sync-agents` on every container start, always overwriting. This means:

- The canonical files here are the source of truth.
- Local edits to `~/.claude/agents/foo.md` or `~/.config/opencode/agents/foo.md` will be clobbered on next container start.
- To change an agent permanently: edit the file here, then rebuild or run `sync-agents` manually.

## Run manually

```bash
python /workspace/agents/sync-agents
# or, if executable bit is set:
/workspace/agents/sync-agents
```

## Adding a new agent

1. Create `<name>.md` here with Claude Code frontmatter (`name`, `description`, `model`, optional `tools`).
2. Write a focused `description` — start with "Use proactively when…" so the main agent auto-delegates. The description is the routing signal.
3. Run `sync-agents` (or restart the container).

## Bring your own agents (without forking)

If you want to use this image/devcontainer with your own canonical agent directory living on your host (not this repo's `agents/`):

1. Put your canonical Claude Code-format `.md` files somewhere on your host, e.g. `~/.agentic/agents/`.
2. In `.devcontainer/devcontainer.json`, find the `BYO AGENTS:` block in the `mounts` array and uncomment the line below it. That bind-mounts your host dir over `/workspace/agents`, replacing this repo's example agents.
3. Rebuild / restart the container. `sync-agents` reads from `/workspace/agents` either way, so your files now feed both `~/.claude/agents/` and `~/.config/opencode/agents/`.

The mount is `readonly` by default — runaway agents can't accidentally modify your source. Drop `,readonly` if you want to edit canonical files from inside the container.

If you want to keep this repo's example agents around as a reference while still BYO-ing your own, mount to a different path (e.g. `target=/home/agent/.agents-source`) and edit `sync-agents` to read from there — or run two separate sync passes.

## Switching opencode to a non-Anthropic model

opencode is provider-agnostic. To swap a subagent to OpenAI / Gemini / a local model: edit the corresponding file in `~/.config/opencode/agents/` directly (note: `sync-agents` will overwrite it on next container start), or extend `MODEL_MAP_OPENCODE` in `sync-agents` to add a new mapping.

## Model rationale (TL;DR)

- **Sonnet** for review/test/debug — needs reasoning depth, runs at moderate frequency.
- **Haiku** for security-scan/docs/deps/commits — pattern-matching or mechanical, runs often, cost matters.
- **Opus** stays as the main session — orchestration + implementation.

See the discussion thread in the repo's commit history for the full reasoning.
