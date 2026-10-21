# Replacing isoai: sandbox comparison

Reviewed: 2026-10-21. Documentation research, not a runtime/security audit.
Names assumed: Microsoft eXecution Container (MXC) and
Matt Pocock's `@ai-hero/sandcastle`. Confirm these are the intended projects.

Experimental implementation: see [SBX profiles and usage](experiments/sbx/README.md).
Those starter profiles deliberately use supported custom V2 kits and thin
adapters over this repository's existing images, not Docker's built-in agent
kits or published V3 workloads. They preserve existing agent binaries and do
not add a guest Docker Engine; the inherited Docker CLI alone cannot run
Docker/Compose workloads. Host-socket access is not an alternative. The broader
Docker capabilities discussed below require a suitably equipped guest image.

## Recommendation

Trial **Docker Sandboxes (`sbx`) with one named sandbox per parallel task**.
User clarified the security goal: protect unrelated host resources, not prevent
writes to explicitly shared development resources. Direct-mounted development
workspaces and dedicated agent-state directories are acceptable; clone mode is
optional. Separate working copies remain useful for parallel-edit isolation.
Explicitly shared Mongo access is acceptable too, subject to database integrity
and credentials. A host Docker socket remains qualitatively different: its
authority can extend to unrelated host paths, not just the intended dev assets.
Dedicated writable state mounts could replace some exports where supported by
the chosen runtime and application; this research has not validated the exact
sbx path mapping. Keep independent live databases separate regardless.
It most directly combines a stronger isolation boundary, private Docker access,
persistent environments, supported coding agents, and reusable configuration.
User confirmed Windows 11 with WSL2 and centrally managed configuration updates,
not two-way writable sharing. Virtualization availability still needs checking.

For the first trial, prefer native Windows `sbx` using Windows Hypervisor
Platform rather than assuming nested KVM works inside WSL. Docker documents
clone-mode access to WSL repositories via `\\wsl.localhost\...`; Windows Git
may reject ownership across that boundary. If this occurs, follow Docker's
repository-specific `safe.directory` guidance, not a blanket `*` exemption.
Validate path handling and performance before migrating projects. See
[WSL troubleshooting][wsl]. Keep the trusted config source outside sandbox
writable mounts; use controlled skill imports and kits for updates.

Use a common, trusted configuration source, not a common writable agent home:

- Shared: curated skills, agent definitions/settings, toolchain recipes.
- Private per sandbox: sessions, databases, caches that require isolation,
  generated configuration, build output, and the working clone.
- Broker credentials separately; don't share the host's entire auth directory.
- Return changes through explicit Git fetch/review rather than live writes to
  the original checkout.

This is a proposed configuration pattern, not a claim that all existing
isoai settings import automatically.

## Current isoai boundary

Source: [`scripts/isoai`](scripts/isoai), especially lines 100–133 and 172–209;
[`README.md`](README.md), sections “Mount strategy” and
“Workspace path and Docker-out-of-Docker”.

- Container identity is derived from the working directory; repeated runs reuse
  it. Base and gamedev profiles can share the same host working files.
- Workspace files and numerous agent/tool configuration, auth, and data paths
  are bind-mounted read-write. This shares more than configuration.
- `/var/run/docker.sock` is mounted. If usable, it lets the guest ask the host
  daemon to create containers with other host mounts. Capability dropping does
  not remove that API authority. Actual scope depends on the daemon and its
  privileges; this is not a runtime exploit test.
- SSH forwarding grants signing authority, even though key files stay outside.
- The user confirmed Windows 11 with WSL2 as the intended host setup.

## Comparison

| Candidate | What it provides | Fit and caveats |
| --- | --- | --- |
| Docker Sandboxes | Managed microVMs, private Docker daemon, persistent state, clone or direct workspace modes, shared skills, kits and environment files | Best first trial for the stated isolation goal. Must explicitly choose clone/mountless mode; direct mode writes the host checkout. No automatic import of all user-level agent config. |
| Microsoft MXC | Cross-platform SDK with filesystem/network policies and backend-dependent containment | Useful when embedding policy-driven execution. Not a turnkey replacement for the developer workflow; choosing policies, workspace management, and integration still leaves custom work. Not every backend is a VM. |
| Sandcastle | TypeScript orchestration with Docker, Podman, Vercel, reusable sandboxes, interactive sessions and Git branch strategies | Stronger fit for scripted parallel-agent workflows. Its default local Docker path is ordinary container isolation and writes a host-mounted workspace. Parallel branch selection is explicit. |

Sources: [Docker architecture][architecture], [Docker security][security],
[MXC README][mxc], [Sandcastle README][sandcastle].

### Docker Sandboxes details

- Current docs use standalone `sbx`, not just older `docker sandbox` examples.
  Docker Desktop and host Docker Engine are not installation requirements.
  Local compute and the CLI are free, including commercial use; cloud/model
  charges and optional paid governance are separate. Docker sign-in is required.
  [Overview][docker], [installation][install].
- Supported installation platforms: Ubuntu 24.04+ (x64/Arm64), Windows 11
  (Intel/AMD x64), and Apple-silicon macOS 14+. Local Linux requires KVM and
  access to it; running inside a VM requires nested virtualization. These facts
  do not establish that this user's particular WSL setup works. [Installation][install].
- Each local sandbox has a separate kernel and Docker daemon. Installed packages,
  in-VM files, agent state, and Docker state survive stop/start until removal.
  Per-sandbox Docker state increases disk/resource costs. [Architecture][architecture].
- `sbx run` defaults to directly mounting the current directory read-write.
  `--clone` instead creates a private in-VM clone and exposes the source
  repository read-only at `/run/sandbox/source`. A mountless `sbx create`
  exposes no host workspace. Clone mode protects source writes, not the
  confidentiality of files in that read-only source mount. [Usage][usage].
- Clone mode is fixed at creation, requires a Git repo, and cannot be created
  from a linked host worktree. Use the main checkout. Distinct named sandboxes
  give distinct clones; multiple sessions in one sandbox do not by themselves
  isolate parallel tasks. Fetch results via the sandbox Git remote before
  deleting the sandbox. [Git workflows][git], [usage][usage].
- Shared skills are experimental, live in a dedicated persistent host-side
  store, and default to read-only for newly created supported-agent sandboxes.
  Host import is a copy, not continuous synchronization. A sandbox granted
  read-write access can poison skills used by others, even read-only consumers.
  [Skills][skills].
- Kits package toolchains and configuration; `sbxenv.yaml` and user defaults can
  share environment setup. The environment-file interface is experimental.
  These are routes for migrating existing recipes, not proof that either
  existing image is immediately compatible. V2/v3 kit compatibility matters.
  [Kits][kits], [environment files][env].
- Claude Code and OpenCode are supported agents. Host user-level agent config
  is not automatically inherited; migrate curated settings/plugins deliberately.
  Verify the required OpenCode version, plugin, and provider/auth workflow in a
  trial rather than assuming parity with the current image. [Agents][agents],
  [OpenCode integration][oc].
- Proxy-managed credentials can stay outside the VM; supported requests receive
  injected headers. This does not remove the agent's authority to use the
  authenticated service. Credentials copied into files/env or OAuth passthrough
  have different exposure. SSH forwarding is enabled by default when available;
  review/disable it if unnecessary. [Credentials][credentials].
- Gateway-managed local stdio MCP servers run on the host, outside the microVM.
  Filesystem/command tools exposed there can bypass the intended workflow
  boundary. Audit them. Keep environment files and host-executed helpers outside
  writable sandbox mounts. Review network allowlists and imported code before
  running it on the host. [Security][security], [environment files][env].

### Microsoft MXC details

The current README explicitly describes an SDK dependency embedded in an app,
with Rust, .NET, and Node SDKs. It also exposes persistent lifecycle operations;
it is not merely a one-shot process wrapper. Linux defaults to Bubblewrap,
macOS to Seatbelt, and Windows to ProcessContainer. Other backends include LXC
and VM options with platform-specific/experimental qualifications. Thus “using
MXC” alone does not specify a VM-grade boundary or an independent checkout.
Source: [MXC README][mxc].

Assessment: choose it if retaining a custom launcher and precise policy control
is desirable, not primarily to eliminate launcher maintenance. Exact backend
policy semantics and compatibility with this toolchain were not runtime-tested.

### Sandcastle details

The current README documents Docker/Podman as bind-mount providers and Vercel as
an isolated cloud provider. Local Docker defaults to `branchStrategy: head`,
which edits the host working directory. Named `branch` strategies create
worktrees for parallel tasks; `merge-to-head` merges automatically and is not
appropriate for uncontrolled concurrent merging into the same HEAD.

Custom images and optional read-only configuration mounts are supported.
`createSandbox()` keeps a sandbox warm for multiple runs; `interactive()` offers
interactive sessions, so it is not exclusively a batch tool. Its isolation
depends on the selected provider and mounts, not the orchestration API.
Source: [Sandcastle README][sandcastle].

Assessment: attractive for parallel implementation/review automation, but do not
treat a Git worktree as a security boundary. Exact shared Git-metadata exposure
and native Windows support were not audited here.

## Follow-up: shared MongoDB and workflow profiles

### Share the Mongo service, not its raw data volume

Keep the current Mongo container and its data volume owned by the current
Docker daemon. Connect sandboxed clients to that one service over TCP. A named
volume in the host Docker daemon is not the same object as a volume in a
sandbox's private Docker daemon. Do not start another `mongod` against the same
database files.

Docker documents `host.docker.internal` as the sandbox-to-host hostname. Its
proxy translates this to `localhost`, so the allow rule uses `localhost`:

```sh
sbx policy allow network --sandbox pstack-task-a localhost:27017
```

The corresponding client endpoint is
`mongodb://host.docker.internal:27017/<database>` with suitable credentials.
This assumes the existing Mongo instance is reachable from Windows localhost
on that port; Docker Desktop versus a daemon running inside WSL can affect that
prerequisite. Verify the actual published endpoint before changing networking.
Do not expose Mongo broadly on the LAN to solve routing.

Use database-scoped `read` credentials for the large reference dataset and,
where needed, a separate small per-task database with scoped write credentials.
This avoids copying the large dataset, but applications must support separating
reference reads from task writes. If tasks need to modify the same existing
records or run destructive migrations, network isolation cannot give them
independent data: use a disposable test dataset or intentionally accept shared
write conflicts. Mongo authentication must be enabled for role boundaries to
be meaningful. Mongo's binary protocol credentials are not automatically
protected by the sandbox's HTTP credential-header injection.

The example rule grants one sandbox access, not all projects. Check existing
global/kit rules too; an open policy already permits more than this rule.
Sources: [host service access][development], [local policy][local-policy],
[MongoDB roles][mongo-roles], [MongoDB storage configuration][mongo-config].

### Compose named workflow profiles

A profile should select three separate things:

1. Agent/workload: Claude Code versus a pinned OpenCode v2 installation.
2. Reusable toolchain/configuration kits: pstack, RTK, OMO-slim settings.
3. Runtime setup: private clone, resource limits, published ports, and narrowly
   scoped service access.

Use `sbx env run <profile-file> --name <task-name>` as the orchestration layer.
Two profiles can share a toolchain kit without maintaining a separate complete
Dockerfile for every combination. Heavy binaries belong in images/mixins;
model choices, prompts, settings and service endpoints belong in profiles or
kit configuration. Plain configuration changes do not intrinsically require
a different full image, although v3 kits themselves are packaged as OCI images.

Illustrative commands, after authoring the referenced profile files:

```powershell
sbx env run C:\agent-workflows\pstack-claude.yaml --name pstack-task-a
sbx env run C:\agent-workflows\pstack-opencode-omo.yaml --name pstack-task-b
```

Profile sources and host-executed helper scripts should live outside writable
sandbox mounts. Different names create independent environments; returning to
an existing name reuses its recorded setup, rather than upgrading its kits.
Preserve work and state before recreation. Keep kit generations compatible:
built-in agent shortcuts select v2 kits, while v3 workloads require v3 mixins.
Docker recommends v3 for new kit authoring. [Environment files][env],
[using kits][use-kits], [v2 reference][kits-v2].

Version check: Docker's documented published v3 OpenCode workload currently
lists `1.18.31`, while this repository installs OpenCode v2. Do not assume
that image matches this user's setup. Pin a tested OpenCode v2/OMO-slim pair.
Built-in OpenCode kits manage `~/.config/opencode/opencode.json`; do not let a
generic plugin installer overwrite the sandbox's generated credential/MCP
configuration. Integrate the plugin/settings explicitly through a compatible
config layer or custom workload. OpenCode v2's system configuration directory
(`/etc/opencode`) is one documented route for managed configuration, but has
the highest file-config precedence, so use it deliberately. [OpenCode v2
configuration][oc-v2-config], [OpenCode v2 plugins][oc-v2-plugins].

### Host-accessible statistics and session records

Local sandbox state already resides on the user's machine, inside the sandbox
storage, and persists across stop/start. It is not automatically present in
the user's normal host directories or host tools' global history, and sandbox
removal destroys private state. [Usage][usage].

Keep private live databases and collect records into a host archive partitioned
by sandbox identity. A host-side scheduled collector is more robust than only
exporting on clean agent exit. Collect again and verify archives before any
sandbox removal; abnormal termination can skip exit hooks. This collector is
proposed glue, not a built-in cross-sandbox analytics feature.

RTK documents `~/.local/share/rtk/history.db` inside Linux environments and the
`RTK_DB_PATH` override. It can report with:

```sh
rtk gain --all --format json
rtk gain --all --format csv
```

Run the command through `sbx exec` and redirect stdout to a host file, using a
separate destination for each sandbox. The docs describe 90-day history
retention. Preserve snapshots if longer retention matters. These exports are
reports, not a documented database merge/import format. To aggregate across
sandboxes, use the latest cumulative snapshot per sandbox (or compute deltas),
not the sum of every periodic cumulative snapshot. RTK's savings estimates
measure filtered output, not exact provider billing. [RTK analytics][rtk-gain].

For OpenCode v2, `opencode debug paths db` prints the actual DB path without
opening it; the default installed DB is
`~/.local/share/opencode/opencode.db`, with `OPENCODE_DB` as an override.
Diagnostic logs use `~/.local/share/opencode/log/opencode.log`.
OpenCode v2 documents experimental transcript export/import endpoints:

- `GET /api/experimental/session/{sessionID}/export`, optional `sanitize`.
- `POST /api/experimental/session/import`; import parents before children.
- `GET /api/experimental/session/{sessionID}/log`, optional exclusive `after`
  sequence and `follow=true` for live durable-event streaming.

A collector can execute authenticated `opencode api` requests inside the
sandbox and save output on the host, avoiding exposure of the server itself.
The exports are projected transcripts, not a complete backup of plugin state,
snapshots, configuration and all runtime data. Experimental API shape must be
validated against the pinned installed version. [OpenCode v2 CLI][oc-v2-cli],
[API][oc-v2-api], [troubleshooting][oc-v2-trouble].

Do not concurrently mount one active RTK/OpenCode SQLite DB across independent
VMs or synchronize live database files bidirectionally. For full recovery,
take an application-consistent backup (quiesce its writers or use a suitable
SQLite backup mechanism) and archive it separately per sandbox. A copy of only
the main DB file while a writer is active may miss WAL data. Archives and logs
can contain prompts, source code and secrets; keep them private and don't let
agents write executable host configuration through the archive path.

## Minimal trial and acceptance checks

Do not remove existing isoai containers or migrate the live global state yet.

1. Confirm host OS, `sbx` version, and virtualization access.
2. Use a disposable repository with no sensitive files. Create two distinct
   named clone-mode sandboxes, with shared skills read-only.
3. Confirm each can commit independently, while the original checkout and the
   other sandbox remain unchanged. Fetch/review each result explicitly.
4. Confirm the Docker daemon visible inside is private, not the host daemon.
5. Confirm no sensitive host paths, sockets, broad MCP filesystem/command
   services, or unnecessary credentials are exposed.
6. Migrate one curated configuration set and verify Claude/OpenCode, required
   plugins/providers, and MCP tools. Do not bind-mount the shared runtime DB.
7. Test stop/start persistence, then the required .NET/browser/game toolchain.
   Measure RAM/disk use with two active sandboxes before switching workflows.

These checks are proposed, not performed. No sandbox software was installed or
launched, and no existing launcher/runtime configuration was changed.

[docker]: https://docs.docker.com/ai/sandboxes/
[install]: https://docs.docker.com/ai/sandboxes/install/
[architecture]: https://docs.docker.com/ai/sandboxes/architecture/
[security]: https://docs.docker.com/ai/sandboxes/security/
[usage]: https://docs.docker.com/ai/sandboxes/usage/
[git]: https://docs.docker.com/ai/sandboxes/workflows/git/
[skills]: https://docs.docker.com/ai/sandboxes/workflows/agent-skills/
[kits]: https://docs.docker.com/ai/sandboxes/customize/
[env]: https://docs.docker.com/ai/sandboxes/configuration/environment-files/
[agents]: https://docs.docker.com/ai/sandboxes/agents/
[oc]: https://docs.docker.com/ai/sandboxes/agents/opencode/
[credentials]: https://docs.docker.com/ai/sandboxes/configuration/credentials/
[development]: https://docs.docker.com/ai/sandboxes/workflows/development/
[local-policy]: https://docs.docker.com/ai/sandboxes/governance/access-controls/local/
[mongo-roles]: https://www.mongodb.com/docs/manual/reference/built-in-roles/
[mongo-config]: https://www.mongodb.com/docs/manual/reference/configuration-options/#mongodb-setting-storage.dbPath
[use-kits]: https://docs.docker.com/ai/sandboxes/customize/use-kits/
[kits-v2]: https://docs.docker.com/ai/sandboxes/customize/kits-v2/
[oc-v2-config]: https://opencode.ai/v2/docs/config
[oc-v2-plugins]: https://opencode.ai/v2/docs/build/plugins
[rtk-gain]: https://www.rtk-ai.app/docs/analytics/gain/
[oc-v2-cli]: https://opencode.ai/v2/docs/cli
[oc-v2-api]: https://opencode.ai/v2/docs/api
[oc-v2-trouble]: https://opencode.ai/v2/docs/troubleshooting
[wsl]: https://docs.docker.com/ai/sandboxes/troubleshooting/#clone-mode-reports-not-in-a-git-repository-on-wsl
[mxc]: https://github.com/microsoft/mxc
[sandcastle]: https://github.com/mattpocock/sandcastle
