# Skills

> **Attribution.** The four skills in this directory are vendored verbatim from [obra/superpowers](https://github.com/obra/superpowers) — MIT licensed, copyright © 2025 Jesse Vincent. Full license text in [`LICENSE.superpowers`](LICENSE.superpowers). We cherry-picked just these four (workflow discipline) and skipped the dispatch/worktree skills that conflict with our standing subagent roster.

Workflow-discipline skills that complement the subagent roster in `../agents/`. Where agents are *specialists you delegate to*, skills are *rules you follow yourself*.

## What's here

| Skill | Source | Purpose |
|---|---|---|
| `writing-plans/` | obra/superpowers (MIT) | Produce a structured implementation plan before coding |
| `executing-plans/` | obra/superpowers (MIT) | Work through a plan task-by-task with review checkpoints |
| `test-driven-development/` | obra/superpowers (MIT) | Red-Green-Refactor discipline; "no production code without a failing test first" |
| `systematic-debugging/` | obra/superpowers (MIT) | Four-phase root-cause method; "no fixes without root-cause investigation first" |

License text for the vendored skills lives in `LICENSE.superpowers`.

## Why these four

Compared to the agent roster, these fill **workflow gaps** that aren't a specialist problem:

- The agents handle review / test-writing / debugging / docs *after* you've started.
- The skills give you **discipline before you start**: spec the work, write the failing test, debug systematically.

Cherry-picked from a larger superpowers framework so we don't pull in subagent-dispatch and worktree skills that conflict with our standing roster.

## Install scope

**Claude Code:** `sync-agents` (in `../agents/`) writes these into `~/.claude/skills/` on every container start. They're invoked automatically when their description matches the situation, or manually via `/<skill-name>` if that's how your harness routes.

**opencode:** opencode now installs superpowers via its **plugin manager**, not a filesystem skills directory. If you want these skills in opencode, add this to `opencode.json` instead of relying on the sync script:

```json
{ "plugin": ["superpowers@git+https://github.com/obra/superpowers.git"] }
```

That pulls all 14 superpowers skills, not just our four. Different scope — that's an opencode quirk, not a bug in our setup.

## Updating

The vendored copies are pinned to whatever `main` was when fetched. To refresh:

```bash
# from repo root
for skill in writing-plans executing-plans test-driven-development systematic-debugging; do
  for f in skills/$skill/*.md; do
    name=$(basename "$f")
    curl -fsSL "https://raw.githubusercontent.com/obra/superpowers/main/skills/$skill/$name" -o "$f"
  done
done
```

Then commit the updated files. Skim the diffs — Jesse occasionally tightens the prompts.

## Adding your own skills

A skill is a directory with at minimum a `SKILL.md` that opens with YAML frontmatter:

```markdown
---
name: my-skill
description: Use when X. Describes when the model should auto-load it.
---

# My Skill

<skill instructions>
```

Drop it in `skills/<name>/SKILL.md`, run `sync-agents`, done. Supporting files in the same directory (`@filename.md` references, scripts, examples) are copied along with `SKILL.md`.
