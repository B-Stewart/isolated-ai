# Docker Sandboxes OpenCode image evidence

Inspection date: 2026-10-23. Read-only OCI Registry v2 inspection; no image pull, build, or sandbox execution. Context7 was unavailable, so official Docker documentation and registry metadata were used directly.

## Findings / recommendation

**Given the specific goal—small common foundation, project runtimes managed by mise, and the repository's OpenCode v2 + OMO-slim combination—a custom small v3 workload is justified if lean/composable is the priority.** Keep the Docker OpenCode template as a convenient upstream-maintained option and a reference for the SBX workload contract, rather than recreating its broad toolchain. Split shared agent-support requirements from project tools: put the desired OpenCode/OMO support runtime in the workload; add mise/project tools selectively. A custom workload may be smaller, but no such image has been built or measured, so assert no size reduction or performance gain.

**Important correction to earlier reasoning:** the published v3 kit `docker/sbx-kit-opencode:1.18.31` is not equivalent to the template image and should not be treated as the lean official alternative. Its registry metadata records a `shell-docker` base and an added Docker Engine/containerd layer, in addition to a broad dev-tool set. It is an OpenCode workload that explicitly enables a private Docker service, not the small OpenCode-only layer one might infer from its name.

## Registry evidence (linux/amd64)

Queried Docker Hub anonymously using the Registry v2 bearer-token flow. Image index digests (immutable index references):

| Reference | Index digest | amd64 manifest digest | Sum of compressed layer sizes |
|---|---|---|---:|
| `docker.io/docker/sandbox-templates:opencode` | `sha256:b3b69aa5148a20d1c0e3ec4d5db2975b8b9d6830d46d50a93fd766aec7d6668b` | `sha256:d270f816edc1c42fbef9eaa049464eff31b08db1d25b97f38b515789820db877` | 1,055,483,906 bytes (~1.06 GB decimal) |
| `docker.io/docker/sbx-kit-opencode:1.18.31` | `sha256:dd7e2f0b77c653af9b8611da7c5ffeaba2e82606703dc655d528540c8288e004` | `sha256:cd9bdd9397748670a94d867ac08b21ddcdf54c4c2c1bb638b4afc765b087b860` | 851,268,312 bytes (~851 MB decimal) |

These are registry-reported **compressed layer transfer sizes** for the amd64 manifests, not unpacked rootfs size, installed-package disk use, or per-sandbox disk use. The v3 kit and template share the same first 13 layer digests; their final layers differ. That shared registry content may be relevant to transfer/cache reuse, but it is **not evidence of shared sandbox storage**. Docker's [architecture docs](https://docs.docker.com/ai/sandboxes/architecture/) say each sandbox maintains its own Docker daemon state, image cache, and package installations; multiple sandboxes do not share images or layers. Therefore don't estimate long-lived sandbox disk by assuming OCI-layer deduplication between sandboxes. Docker says VM images, Docker images/layers, and volumes consume disk, but the docs give no exact per-template/per-sandbox physical accounting. Registry history/config metadata was fetched; layer blobs were not downloaded. Thus package inventory below is corroborated by Docker's documented template inventory plus image build-history command records, not by querying `dpkg` inside a running image.

### Main layer size comparison (compressed registry blobs)

| Layer/history purpose | Template | v3 workload | Evidence/interpretation |
|---|---:|---:|---|
| Shared general CLI apt install | 99,673,627 B (~99.7 MB) | 99,673,627 B (~99.7 MB) | Same layer digest; includes Git, OpenSSH client, Docker CLI/Compose, utilities. |
| Shared apt development runtimes (`default-jdk-headless`, `golang`, `nodejs`, `npm`, `python3`, `python3-pip`, `bc`, `man-db`) | 324,988,895 B (~325 MB) | 324,988,895 B (~325 MB) | Same layer digest. These are broad baseline runtimes despite the composable goal. |
| Final OpenCode npm install | 524,158,986 B (~524 MB) | 252,099,097 B (~252 MB) | Different layers/build history; not a controlled package-size comparison. |
| Docker Engine + containerd install | — | 67,828,898 B (~67.8 MB) | V3 workload only; its config marks `start-docker=true`. |

Template history records `npm install -g opencode-ai --include=optional` and `opencode --version`, with no recorded npm-cache cleanup. The v3 workload history records the pinned `opencode-ai@1.18.31` install followed by `npm cache clean --force` and removal of `$HOME/.npm`. That is a potential build-hygiene difference, **not proof** that retained npm cache explains the entire final-layer size gap; these are registry compressed sizes, not inspected filesystem contents or package-level measurements.

The v3 kit's config labels say base `docker/sandbox-templates:shell-docker`, `start-docker=true`, and its history records apt installs including `docker-ce`, `containerd.io`, `docker-ce-cli`, and Docker Compose, then installs `opencode-ai@1.18.31`. That explains why it is a distinct, Docker-enabled workload; it is not merely a repackaged `sandbox-templates:opencode` image.

## What is verified about tools

Docker's [base-image docs](https://docs.docker.com/ai/sandboxes/customize/author/base-images) say template variants are Ubuntu-based, run as non-root `agent` with sudo, and **most** variants include Git, Docker CLI, and common tools including Node.js, Python, Go, and Java. The table lists `opencode` as an agent variant and `claude-code-minimal` as a distinct minimal-toolset variant. The docs' OpenCode-specific example explicitly says the `opencode` template supplies OpenCode, Python, `uv`, and `agent`.

The template's amd64 OCI config has labels `com.docker.sandboxes.base=ubuntu:questing` and `org.opencontainers.image.version=26.04`; those labels disagree in naming/version semantics, so actual `/etc/os-release` was not verified and the OS release should not be asserted from them alone. Its image history records installs for `git`, `gh`, `openssh-client`, `nodejs`, `npm`, `python3`, `python3-pip`, `golang`, `default-jdk-headless`, `make`, `ripgrep`, `jq`, `rsync`, etc.; it copies `uv` and installs `opencode-ai` with npm. So for this inspected image: Git and OpenSSH client are supported by build-history evidence. **Git LFS was not found in the recorded install commands** and is not promised by the docs. (Absence from install commands is not a proof it cannot be present transitively.) Docker's host SSH-agent forwarding is a separate mechanism and does not establish guest `ssh` availability.

The V3 kit's config source label points to `git@github.com:docker/sbx-kits-contrib.git`, revision `e3d41b741d24603fe43097bb66327d58abeec17b`, with entrypoint label `opencode/opencode.yaml`; this is a useful reproducibility/source lead. Its history installs a comparable broad dev-tool collection plus Docker Engine/containerd, and explicitly installs `opencode-ai@1.18.31`. Do not infer from its OCI tag that its upstream package is equivalent to this repository's `@opencode/cli@2`: the project documents that package/version distinction at [README.md:11-13](../../README.md#L11-L13). This does **not** establish incompatibility; verify the exact package/runtime and plugin behavior. Exact runtime/plugin compatibility with `oh-my-opencode-slim` was not established by registry metadata or Docker docs. OMO's Bun shebang requirement is documented in the repository README (line 22), but neither OpenCode workload's published metadata guarantees Bun.

## Practical implication

- Prefer a custom small v3 workload when minimizing common image contents and composing project tools are primary; retain Docker's template as a supported convenience/reference if broad baseline tools are worth their footprint. The actual size tradeoff awaits a built custom candidate.
- Before adopting either OpenCode base, check in-sandbox `opencode --version`, Bun availability, and OMO install/activation. If OMO requires Bun, add it deliberately; do not select the Docker-enabled v3 `sbx-kit-opencode` solely for its name.
- Treat project Node versions via mise as a separate choice: template Node is a baseline, not proof of per-project version management. Avoid redundant Node/runtime mixins if mise will own project versions.
- If Docker-in-sandbox is not wanted, avoid the v3 `docker/sbx-kit-opencode` workload: its metadata positively indicates Docker Engine and containerd. The template `sandbox-templates:opencode` docs do not say it has a guest Docker Engine; Docker CLI alone is not equivalent.
- No custom-image comparison, per-sandbox disk measurement, idle-RAM measurement, or startup benchmark was conducted. OCI compressed transfer size does not establish sandbox disk footprint, idle memory, or startup speed. The case for a custom workload here is control over bundled tools and the OpenCode/OMO combination, not a demonstrated speed or RAM improvement. Keep that workload narrow and use modular kits for optional project tools; its maintenance and SBX compatibility become our responsibility.

## Sources and limits

- [Docker base images for sandbox workloads](https://docs.docker.com/ai/sandboxes/customize/author/base-images) — official per-variant and OpenCode template statements.
- [Docker OpenCode agent docs](https://docs.docker.com/ai/sandboxes/agents/opencode/) — identifies legacy template reference `docker/sandbox-templates:opencode`; this is distinct from the v3 `docker/sbx-kit-opencode` OCI reference.
- Registry v2 manifest/config endpoints, public anonymous pulls, inspected as above; index supports both amd64 and arm64. Digests make this snapshot reproducible even if tags later move.
- Metadata confirms architecture, labels, env/entrypoint, compressed sizes, and build-history commands. It does not reveal complete runtime filesystem inventory or prove OMO behavior. No image blobs were downloaded, and no compatibility test was run.
- The official template source Dockerfile/package lock was not found in the examined public docs/repositories. Therefore layer histories are evidence of build commands, not a full exhaustive package bill of materials.
