# AGENTS.md

This repository provides containerized AI-assisted development with persistent
host-mounted agent configuration and project workspaces.

## Structure

- Keep two image entrypoints: `agentic-base.dockerfile` and the derived
  `agentic-gamedev.dockerfile` at the repository root.
- `scripts/image/base/` and `scripts/image/gamedev/` contain build-only installers.
  Dockerfiles own orchestration, cache mounts, build arguments, environment, and
  user/runtime setup; scripts own package selectors and installation details.
- `scripts/isoai` and `scripts/isoai-ssh-agent.py` run on the host to manage
  persistent project containers and SSH forwarding. `.devcontainer/` provides
  the alternative Dev Containers entrypoints.

## Rules

- For installer or Dockerfile changes, follow [Image build structure](README.md#image-build-structure)
  and [Verification](README.md#verification). Build from the repository root;
  installers execute inside image builds, not directly on the host.
- Preserve bounded package selectors, checksum verification, and existing public
  build-argument overrides when moving or changing installation steps.
- Keep tool summaries and maintenance explanations in `README.md` synchronized
  with the installers. Update isoai and devcontainer settings when runtime
  behavior, image selection, or mounts change.
- Keep devcontainer files compact and portable; `README.md` owns explanations.
