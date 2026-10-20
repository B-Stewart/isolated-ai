# Godot and Blender agent skills: comparison and first setup

**Reviewed:** 2026-10-01. This is a source-based comparison and a proposed small first install, not a claim that every published skill was reviewed or that any candidate was runtime-validated. No skills, packages, plugins, or MCP servers were installed during this review.

## Recommendation: start with three project skills

Use the skills CLI to add only these three skills to a project:

```bash
npx skills add gamedev-skills/awesome-gamedev-agent-skills --skill godot-csharp --skill godot-nodes-scenes -a opencode -a claude-code
npx skills add jord-jd/jord-skills --skill blender-workflow -a opencode -a claude-code
```

They provide a compact starting point for this image's Godot 4.7.2 .NET and Blender 5.2.2 LTS command-line workflow: C#-oriented Godot guidance, a scene/node design reference, and reproducible Blender scripting guidance. They are plain project-scoped skills, not engine plugins, test frameworks, or MCP integrations. They do not install .NET SDKs, Godot export templates, Blender add-ons, or other project dependencies.

Run the commands from the project root. The skills CLI defaults to project installation; do not add `-g` for this setup. You can run them on the host or inside the game-development image, for example:

```bash
isoai --image=gd -- npx skills add gamedev-skills/awesome-gamedev-agent-skills --skill godot-csharp --skill godot-nodes-scenes -a opencode -a claude-code
```

Before installing, inspect a repository's offered skill names and descriptions with `npx skills add <owner/repo> --list`. Use the frontmatter `name` shown there with `--skill`; it is not necessarily a search slug or directory name. Afterward, `npx skills list` shows installed skills and `npx skills remove <name>` removes one. For the first trial, avoid `--all` and `-y`: choose skills explicitly and review the installer's proposed changes. See the [skills CLI documentation](https://github.com/vercel-labs/skills) for current usage and agent flags. The commands above target OpenCode and Claude Code using `-a opencode -a claude-code`.

## Godot candidates

| Candidate | What the source offers | Recommendation and caveats |
|---|---|---|
| [`godot-csharp`](https://github.com/gamedev-skills/awesome-gamedev-agent-skills/blob/main/skills/godot/godot-csharp/SKILL.md) — `gamedev-skills/awesome-gamedev-agent-skills` | C#-focused Godot workflows; its guidance includes a Godot 4.7/.NET 8 target. | **Install first.** This is the closest match to the image's Godot 4.7.2 .NET setup. Use the already-present .NET 10 SDK for builds and .NET 8 runtime for conventional `net8` test projects; do not install a separate .NET 8 SDK just to match the skill example. Validate its commands against the actual project. |
| [`godot-nodes-scenes`](https://github.com/gamedev-skills/awesome-gamedev-agent-skills/blob/main/skills/godot/godot-nodes-scenes/SKILL.md) — same repository | Scene and node organization guidance; examples are GDScript-oriented. | **Install first** as a design reference. Translate code snippets to C# for this workflow rather than treating GDScript examples as C# implementation. |
| [`godot-3d-essentials`](https://github.com/gamedev-skills/awesome-gamedev-agent-skills/blob/main/skills/godot/godot-3d-essentials/SKILL.md) — same repository | Cameras, transforms, lights, materials, and related 3D concepts. | Optional if the project actually needs 3D. Blender use alone does not imply a 3D game. |
| [`godot-resources`](https://github.com/gamedev-skills/awesome-gamedev-agent-skills/blob/main/skills/godot/godot-resources/SKILL.md) — same repository | Data-driven resources and asset organization. | Defer until the project has a concrete data-driven asset need. |
| [`godot-gdscript`](https://github.com/gamedev-skills/awesome-gamedev-agent-skills/blob/main/skills/godot/godot-gdscript/SKILL.md) — same repository | GDScript language guidance. | Not needed for a C#-first project. |
| [`godot-gdscript-patterns`](https://github.com/wshobson/agents/tree/main/plugins/game-development/skills/godot-gdscript-patterns) — `wshobson/agents` | Patterns explicitly limited to GDScript. | A reasonable alternative if choosing a GDScript workflow; don't add it alongside overlapping guidance without a reason. |
| [`godot-master`](https://github.com/thedivergentai/gd-agentic-skills) — `thedivergentai/gd-agentic-skills` | A broad, prescriptive GDScript-oriented hub of domain skills. | Not the default for a C#-first workflow. |
| [`godot-best-practices`](https://github.com/jwynia/agent-skills/blob/main/skills/tech/game-development/godot/godot-best-practices/SKILL.md) — `jwynia/agent-skills` | Best-practices guide explicitly focused on GDScript. | Alternative reference for GDScript, not a C# replacement. |
| [`godot-development`](https://github.com/Zate/cc-godot/tree/main/plugins/gd/skills/godot-dev) — `Zate/cc-godot` | Godot development guidance with `mcp__godot__*` tool examples; its directory is named `godot-dev`. | Defer: it assumes a Godot MCP integration and includes older GDScript-oriented guidance. |
| [`godot-testing`](https://github.com/jame581/GodotPrompter/blob/master/skills/godot-testing/SKILL.md) — `jame581/GodotPrompter` | Testing guide covering C# and GDScript testing, including GUT and GdUnit4 references. | Optional guide only. It does not install GdUnit4Net, GdUnit4, or any add-on. Its stated engine scope is Godot 4.3+; validate the actual framework version and runner commands separately. |
| [`csharp-godot`](https://github.com/jame581/GodotPrompter/blob/master/skills/csharp-godot/SKILL.md) — same repository | General Godot C# guide. | Consider as an alternative, but compare it with the more version-specific `godot-csharp` before choosing; its SDK examples may be stale for this image. |

The selected Godot repository skills can be inspected at its [Godot skill source folder](https://github.com/gamedev-skills/awesome-gamedev-agent-skills/tree/main/skills/godot). A skills listing API sample captured at review time is available at [skills.sh Godot search](https://skills.sh/api/search?q=godot&limit=50). The sampled install-count figures were `godot-csharp` 3,122, `godot-nodes-scenes` 3,400, `godot-3d-essentials` 3,269, `godot-resources` 3,336, and `godot-gdscript` 3,415. Other sample counts: `godot-gdscript-patterns` 16,174, `godot-master` 4,069, `godot-best-practices` 2,045, `godot-development` 1,403, `godot-testing` 149, and `csharp-godot` 107. Counts are a point-in-time listing signal, not unique users, quality, safety, or compatibility evidence.

Optional user-run commands, only if the relevant need arises:

```bash
# Add Godot 3D guidance from the selected repository
npx skills add gamedev-skills/awesome-gamedev-agent-skills --skill godot-3d-essentials -a opencode -a claude-code

# Add the testing guide (guidance only; does not install a test framework)
npx skills add jame581/GodotPrompter --skill godot-testing -a opencode -a claude-code

# Alternative when using GDScript instead of the selected C#-first set
npx skills add wshobson/agents --skill godot-gdscript-patterns -a opencode -a claude-code
```

## Blender candidates

| Candidate | What the source offers | Recommendation and caveats |
|---|---|---|
| [`blender-workflow`](https://github.com/jord-jd/jord-skills/blob/main/skills/blender-workflow/SKILL.md) — `jord-jd/jord-skills` | Reproducible `bpy`/data API and BMesh guidance; background execution with `--python-exit-code 1`; preserve existing content and inspect rendered/exported output. | **Install first.** A useful general-purpose fit for headless scripting. It avoids baking in an engine/API assumption and encourages checking the installed version. Its request for two visual references on substantial art changes is useful for art direction, not necessary for mechanical exports. |
| [`blender-scripting`](https://github.com/terminalskills/skills/blob/main/skills/blender-scripting/SKILL.md) — `terminalskills/skills` | Apache-2.0 concrete `bpy`/BMesh recipes for headless mesh, modifier, and batch export work. | Optional if the project needs more implementation examples. Some operator and export examples are Blender 3.x-era; validate operator names, context, and export settings on Blender 5.2.2. |
| [`godot-export`](https://github.com/arjun988/blender-skills/blob/main/.claude/skills/godot-export/SKILL.md) — `arjun988/blender-skills` | Blender-to-Godot pipeline guidance for GLB, units/axes, PBR, transforms, animation, and collision handoff. | Optional pipeline guidance when asset interchange becomes a real task. It is not required for Godot/Blender CLI use; validate settings with the target Godot version. MIT metadata is present in the repository. |
| [`blender-motion-state-inspection`](https://github.com/affaan-m/ecc/blob/main/skills/blender-motion-state-inspection/SKILL.md) — `affaan-m/ecc` | Motion diagnostics for bones, bounds, sampled frames, and foot contact. | Useful later for animation validation, not general-purpose modeling. The source describes a diagnostic workflow and is a CLI-compatible fallback candidate. |
| [`Blender`](https://skills.sh/sfkislev/flue/blender) — `sfkislev/flue` | Bootstrap guidance for the Flue desktop bridge, working against an open Blender document. The actual skill name uses a capital B. | Defer for the headless workflow: it needs an additional desktop bridge, which adding the skill alone does not install. |
| [`blender-web-pipeline`](https://github.com/freshtechbro/claudedesignskills/blob/main/.claude/skills/blender-web-pipeline/SKILL.md) — `freshtechbro/claudedesignskills` | Headless GLB/web pipeline recipes for Three.js/Babylon and Draco. | Defer unless building for the web. API and export settings should be checked against Blender 5.2.2 and the target project. |
| [`blender-mcp`](https://github.com/vladmdgolam/agent-skills/blob/HEAD/skills/blender-mcp/SKILL.md) — `vladmdgolam/agent-skills` | Workflow around a running Blender MCP add-on/socket, with CLI export fallback. | Not the no-MCP baseline: it expects a live bridge. |
| `blender-modeling`, `blender-materials`, `blender-rendering`, `blender-export`, `blender-pro-workflow`, `blender-animation` — [`RobLe3/cc-blender-skill`](https://github.com/RobLe3/cc-blender-skill/tree/main/plugin/skills) | Focused art and production recipes, including Blender 5.x notes. | Potentially useful targeted references, but their actual permitted-tool examples use `mcp__blender__execute_blender_code`; the repository README describes a BlenderMCP port on 9876. That bridge prerequisite makes them a poor default for this headless CLI setup. FBX rig policy, transforms, and modifier advice also need to be judged per asset pipeline, not treated as universal Godot rules. |
| [`cli-anything-blender`](https://github.com/HKUDS/CLI-Anything/blob/main/skills/cli-anything-blender/SKILL.md) — `HKUDS/CLI-Anything` | Stateful JSON CLI wrapper for Blender. | Defer: requires installing the separate `cli-anything-blender` Python package, beyond a guidance-only setup. |
| [`blender-python-scripting`, `blender-modeling-modifiers`, `blender-scene-rendering`](https://github.com/ra100/blender-claude-plugin) — `ra100/blender-claude-plugin` | Describes Blender 5.0/5.1 documentation-oriented skills, MCP preference, and script fallbacks. | Reference candidate, not a blanket recommendation: suitability for 5.2.2 and live-file/tool coverage were not established. |
| [`blender-pipeline`](https://github.com/kjaylee/misskim-skills) — `kjaylee/misskim-skills` | Pipeline skills with Blender 4.4 downloads and script dependencies. | Defer pending review of those dependencies and version fit. |

The first optional concrete `bpy` recipe pack can be added separately:

```bash
npx skills add terminalskills/skills --skill blender-scripting -a opencode -a claude-code

# Optional Blender-to-Godot handoff reference; includes MCP terminology, not an MCP installer
npx skills add arjun988/blender-skills --skill godot-export -a opencode -a claude-code
```

The sampled [skills.sh Blender search](https://skills.sh/api/search?q=blender&limit=50) showed `blender-workflow` 41 installs, `blender-scripting` 22, `blender-motion-state-inspection` 5,596, Flue's `Blender` 2,735, `blender-web-pipeline` 2,834, `blender-mcp` 2,050, the RobLe3 skills in the approximate 715–1,218 range, and `cli-anything-blender` 845. These are counts in the search response sampled at review time, not unique users or evidence of quality, safety, Blender 5.2.2 compatibility, or actual use. The relatively low count for `blender-workflow` does not change its fit-based recommendation.

## Small validation plan

Add one skill pack at a time to a disposable or new project, and compare the same brief before and after installing it. Judge results by artifacts, not just successful process exit codes:

1. **Godot C# and scenes:** import the project headlessly, build a small C# node/component with a signal, run the project's chosen test or executable, and inspect the resulting scene/build output. Confirm the skill's SDK and command advice works with the installed .NET 10 SDK and Godot 4.7.2 .NET.
2. **Blender workflow:** use a short background Python script to create a primitive, set properties, save a `.blend`, render a CPU preview, and export a GLB. Inspect the saved file, preview, and export; repeat to check that rerunning the script does not corrupt or duplicate content.
3. **Godot asset import:** import that GLB in Godot, instantiate it, and check scale, orientation, materials, and repeatable headless import. Add a testing framework only if the project has selected and validated one.

These are proposed user-run checks, not completed tests. A nonzero Blender exit code is useful, but a zero exit alone does not prove the asset looks right or imports correctly. Godot export templates remain a separate installation for export targets; these initial checks do not require claiming templates are bundled.

## Scope and evidence limits

The image provides Godot 4.7.2 .NET and Blender 5.2.2 LTS in the Linux `amd64` workflow, with .NET 10 SDK plus .NET 8 runtime. The image's smoke test and existing local tool availability do not validate third-party skill instructions. Skills are text and may prescribe commands, dependencies, permissions, or MCP tools that need review. This was a review of selected raw skill text and repository documentation, not a whole-package or security audit; none of these recommendations have been installed or benchmarked here. Keep .NET SDK/runtime, Godot export templates, Blender add-ons, and project test frameworks as separate explicit choices.

## Short MCP appendix (no new install recommendation)

- **[Blender Lab MCP](https://www.blender.org/lab/mcp-server/)** is a credible first-party candidate. Its setup describes Blender 5.1+ and an add-on plus a separate MCP server. Project documentation advertises `execute_blender_code_for_cli`, but the add-on dependency remains relevant: an add-on-free, headless workflow and exact Blender 5.2.2 behavior were not verified. Revisit only if structured inspection or live-editor control solves a concrete gap.
- **`ahujasid/blender-mcp`** is a community MCP server/add-on with a localhost TCP bridge (default port 9876). Its [add-on source](https://github.com/ahujasid/blender-mcp/blob/main/addon.py) rejects background-mode startup because the command queue relies on the interactive event loop. Dockerizing the MCP process is not the same as running Blender headlessly.
- **Godot MCPs** also remain optional, unvalidated integrations. [Vollkorn-Games/godot-mcp](https://github.com/Vollkorn-Games/godot-mcp) describes headless scene operations and optional interactive inspection/input via an additional TCP/autoload bridge; its scripting tools are largely GDScript-oriented, so comprehensive 4.7.2 .NET support is unverified. [bradypp/godot-mcp](https://github.com/bradypp/godot-mcp) describes project/scene operations and debug output but is not C#-focused. No vendor-maintained Godot MCP was identified in this review. Do not install an MCP merely to expose commands already available through the image's CLI.
