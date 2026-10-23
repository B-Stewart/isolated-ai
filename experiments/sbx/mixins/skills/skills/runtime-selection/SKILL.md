---
name: runtime-selection
description: Keep agent tooling on its pinned runtime while selecting project runtimes deliberately.
---

# Runtime selection

Use the project runtime manager for project commands when the repository pins a
runtime. Keep globally installed agent tools on their explicitly pinned tooling
runtime; do not assume a project runtime switch also configures agent executables.
When a tool needs a different runtime, state that requirement and invoke it
explicitly rather than silently changing the project's runtime.
