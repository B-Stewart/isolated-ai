# Hooks

Harness settings snippets — primarily Claude Code's hook system. Hooks are JSON entries inside `settings.json`, not standalone files. The examples here are **fragments to merge into your settings**, not files to copy verbatim.

## What's a hook?

A shell command Claude Code runs automatically in response to an event (tool call, session start, prompt submit, etc.). Output flows back into the model's context — non-zero exit codes surface as messages.

The most useful event for validation is **`PostToolUse`**: fires after every tool call (Edit, Write, Bash, etc.), with access to the tool's input + output.

## Example: typecheck after every TypeScript edit

See `claude.settings.example.json`. The hook:

1. Matches `Edit | Write | MultiEdit` tool calls.
2. Reads the edited file path from the JSON payload via `jq`.
3. If the path ends in `.ts`, `.tsx`, `.mts`, or `.cts`, runs `npm run typecheck`.
4. If typecheck fails, the error output is surfaced back to Claude on the next turn, prompting it to fix.

### Why filter by extension?

`PostToolUse` fires on every Edit — including markdown, JSON, config, etc. Running typecheck on a README change is wasted CPU. The `jq | grep` filter scopes it to TypeScript-only edits.

### Why use `jq` for the path?

Claude Code feeds hooks a JSON payload on **stdin** containing `tool_name`, `tool_input`, and `tool_response`. The edited file is at `.tool_input.file_path`. `jq -r` extracts it.

## Installing the hook

Pick one scope:

**User-wide** (applies to every project the user opens in Claude Code):
```bash
# Merge into ~/.claude/settings.json
```

**Project-only** (applies only when working inside this repo):
```bash
mkdir -p .claude
# Copy/merge into .claude/settings.json
```

Both files use the same schema. Project settings take precedence on overlap.

## Adapting to other stacks

| Stack | Replace `npm run typecheck` with | File extensions |
|---|---|---|
| TypeScript | `npm run typecheck` or `pnpm tsc --noEmit` | `.ts`, `.tsx` |
| Python (mypy) | `mypy <changed-file>` | `.py` |
| Python (pyright) | `pyright <changed-file>` | `.py` |
| Rust | `cargo check --quiet` | `.rs` |
| Go | `go vet ./...` | `.go` |

For per-file linting (lint only the changed file rather than the whole project), substitute the file path: `npm run lint -- "$FILE"`.

## Caveats

- **Latency**: every TS edit blocks until typecheck completes. Fast in small projects, painful in large monorepos. Consider `tsc --incremental` or a filtered `tsc --noEmit -p <subpath>` if your project is big.
- **Noise**: if your project has many pre-existing type errors, every edit will surface them. Fix the baseline first, or scope the hook tighter.
- **One `PostToolUse` array**: multiple hook entries are allowed inside the array — add lint, format, test runs as separate entries with their own matchers.

## See also

- Claude Code hooks reference: https://code.claude.com/docs/en/hooks
- Hook payload schema (stdin JSON): https://code.claude.com/docs/en/hooks-reference
