# WSL2 agent sandboxing with existing Linux toolchains

Reviewed: 2026-10-23. Desk research from primary sources; not a runtime test,
penetration test, or security audit. WSL2 kernel/distro prerequisites and
behavior have not been validated on the target machine.

## Scope and question

This note compares in-place Linux/WSL2 process sandboxing—Claude Code's native
Bash sandbox, Anthropic's standalone Sandbox Runtime (`srt`), Bubblewrap, and
Codex CLI's current Linux sandbox—with using a separate VM boundary such as
Docker Sandboxes (`sbx`). The aim is to reuse installed Linux toolchains, not to
claim process sandboxes provide VM-equivalent isolation.

## Decision summary

| Option | Tool reuse | Adoption | Boundary scope | Main caveat |
| --- | --- | --- | --- | --- |
| Claude native sandbox | Reuses existing WSL Linux tools and installs | Easiest for Claude Bash; needs `bubblewrap` and `socat` | Bash/PowerShell/Monitor commands and child processes; not Claude file tools, MCP, hooks, or helpers | Broad reads by default; optional seccomp matters for Unix-socket/WSL interop blocking; fail-closed startup does not prove that optional filter is installed |
| `srt` whole-agent wrapper | Reuses WSL Linux tools if present in that distro | More launcher and policy setup; research-preview | Can wrap agent and selected child processes/MCP servers | Same kernel; credentials, descriptors, sockets, agent/tool routes must be managed explicitly |
| `nono` | Reuses WSL Linux tools under a process-tree policy | Packaged CLI and agent profiles; check kernel features first | Landlock filesystem policy plus feature-dependent seccomp/network controls | On its documented Microsoft WSL2 kernel 6.6/ABI V3 setup, enforced domain-proxy mode is refused; insecure opt-in permits direct egress bypass |
| Codex CLI Linux sandbox | Reuses existing WSL Linux tools and installs | Built into Codex; Bubblewrap prerequisites still apply | Codex command execution and descendants; not a generic boundary for external MCP/host components | Codex-specific; WSL interop and credentials still need review |
| DIY Bubblewrap | Reuses tools visible in WSL | Highest policy/launcher effort | Only processes actually launched inside configured namespaces/mount view | Primitive, not turnkey policy or credential/network broker; errors in mounts or IPC policy are operator responsibility |
| Docker Sandboxes (`sbx`) | Does not automatically reuse WSL distro installs; provision guest toolchain | Separate setup; native Windows 11 x64 uses WHP | Per-sandbox microVM/kernel and private Docker daemon; inspect host-side MCP gateway/stdio tools | Strongest boundary here, but guest provisioning/resources; mounted workspace is still readable and direct mode permits host writes |
| MXC | Backend- and image-dependent; not automatic host-tool reuse | Embed SDK and select/configure backend | Depends on selected backend (Linux default Bubblewrap; Windows ProcessContainer) | “MXC” is not one fixed boundary; policy/backend-specific behavior |
| WSL distro / rootless container | Distro can reuse its own installed tools; container requires packaged/exposed tools | Distro separation is easy; container setup varies | Not equivalent to a separate independent VM; container scope depends on mounts and configuration | Host binaries bind-mounted into a container can have ABI/library/runtime dependencies; rootless does not mean host toolchain is automatically available |
| Greywall | Reuses locally installed WSL Linux agent and tools | Prefix command; install Greywall/Greyproxy and meet Linux prerequisites | Wraps local command/process tree; Linux documents Bubblewrap/namespaces, Landlock, seccomp, TUN network capture | If TUN unavailable, proxy-env fallback may be bypassed by clients that ignore proxy variables; not hardened against actively malicious code |
| Agent Safehouse | WSL Linux unsupported; macOS tool reuse only | Simple wrapper/profile model on macOS | macOS `sandbox-exec` around launched command and descendants | macOS-only; not a WSL2 candidate |

The practical host-native options sandbox **existing WSL Linux installations and
tools**, not Windows-native tools. Native Windows executables launched through
WSL run as the active Windows user, so do not assume Linux process controls
confine them. A same-kernel process sandbox is still meaningful enforcement
against a compromised child process: it can deny filesystem writes, isolate
network routes, and restrict syscalls/IPC when correctly configured. It is not
merely protection against accidental mistakes, but it is not a guest-kernel
boundary either.

## Findings

### Claude Code native Bash sandbox

- **Adoption and support:** Claude Code documents its Bash sandbox as supported
  on Linux and WSL2, but not native Windows. On Linux/WSL2 it requires
  Bubblewrap (`bubblewrap`) and `socat`; an optional seccomp filter adds Unix
  domain socket blocking and is installed with `@anthropic-ai/sandbox-runtime`.
  Ubuntu 24.04+ may require an AppArmor allowance for `/usr/bin/bwrap` to create
  user namespaces. Check `sysctl kernel.apparmor_restrict_unprivileged_userns`;
  Anthropic documents the narrowly scoped profile if the value is `1`.
- **Actual boundary:** It wraps Bash, PowerShell, and Monitor commands and their
  child processes. Claude's Read/Edit/Web tools, MCP servers, hooks, LSP servers,
  and helper commands run outside the sandbox with the agent user's access. To
  constrain those, the docs recommend running the Claude process itself in a
  container, VM, or sandbox runtime.
- **Confidentiality vs integrity:** By default commands can read most of the
  machine, including `~/.ssh` and AWS credentials, although writes are limited
  to the working directory, temp space, and explicitly added paths. Configure
  read-deny/credential rules to protect secrets; a read-only project mount alone
  would not stop source disclosure if the process can reach a network path.
- **Network and fallback:** Linux/WSL2 commands have no direct route out; proxy-
  aware traffic goes through a host proxy checking allowed domains. Plain SSH,
  many database clients, UDP/QUIC, and other proxy-ignoring traffic do not use
  that route. If sandbox prerequisites/platform support are unavailable,
  commands run unsandboxed by default; set `sandbox.failIfUnavailable=true` to
  fail instead. Unsandboxed retry is also an escape hatch by default; disable it
  with `allowUnsandboxedCommands=false` for strict mode.
- **WSL IPC:** WSL may launch Windows binaries through a Unix socket. Anthropic
  notes the optional seccomp filter is needed to block that socket; allowing all
  Unix sockets allows all such sockets, not just Windows interop.

Primary source: [Claude Code sandboxing](https://code.claude.com/docs/en/sandboxing).

### Anthropic Sandbox Runtime (`srt`)

- **Purpose and adoption:** Anthropic describes `srt` as a research-preview,
  standalone wrapper/library for arbitrary processes, including agents, local
  MCP servers, shell commands, and other processes. Linux uses Bubblewrap and a
  network namespace. It can therefore wrap more than Claude's built-in Bash
  tool, provided the launcher places the relevant agent/MCP subprocesses under
  the wrapper.
- **Filesystem policy:** Defaults allow reads broadly, restrict writes, and
  deny network absent configured allowances. `denyRead` is required to protect
  confidential files; permitted project reads remain exfiltratable whenever an
  allowed network route exists. Linux write rules bind concrete paths; the
  repository documents limitations around glob expansion and paths that do not
  exist at sandbox construction.
- **Network and sockets:** Linux removes the sandbox process's network
  namespace and routes traffic through host proxies over mounted Unix sockets.
  HTTP/HTTPS and other TCP traffic can be mediated by proxy policy. Linux blocks
  Unix sockets by default using seccomp where supported; if seccomp is
  unavailable, Unix sockets are unrestricted and a warning is shown. Private
  network ranges are not categorically denied by default; policy and resolved
  address checks matter. A parent proxy owns its own destination-resolution
  policy.
- **Credential/process caveat:** A wrapped process still receives whatever
  environment, descriptors, files, and sockets its launcher exposes. Environment
  secrets are not protected merely by filesystem isolation. Configure credential
  masking/denial or avoid passing credentials. This is a same-kernel process
  boundary, not a separate VM.
- **Configuration behavior:** With no settings file, built-in defaults apply;
  an explicit unreadable/invalid settings file is an error rather than a silent
  fallback. Preserve trusted settings/launcher configuration outside agent-
  writable paths.

Primary source: [Anthropic `sandbox-runtime` repository and current README](https://github.com/anthropics/sandbox-runtime).

### nono: promising, but check the WSL2 networking gap

[`nono`](https://github.com/nolabs-ai/nono) is an agent-oriented CLI wrapper with
profiles and Landlock filesystem enforcement over the launched process tree;
it can reuse installed Linux tools without an image. Its WSL2 docs describe
Microsoft kernel 6.6/Landlock ABI V3: filesystem restrictions and `--block-net`
work, but per-port filtering needs ABI V4. WSL's seccomp-notification listener
conflicts with nono's pre-V4 proxy enforcement, so domain allowlists, network
profiles, and credential-proxy mode are refused by default in that setup.
The `insecure_proxy` opt-in runs the proxy but allows direct outbound bypass;
do not count it as enforced egress confinement. Check the actual machine with
`nono setup --check-only`; do not infer its kernel/ABI from the distro version.
Worth a filesystem-first trial, but not the first choice for enforced online
agent egress on the documented WSL configuration. This limitation concerns
nono's enforcement design, not all uses of seccomp or all WSL sandboxes.
Sources: [WSL2 support](https://nono.sh/docs/cli/internals/wsl2),
[feature matrix](https://nono.sh/docs/cli/internals/wsl2-feature-matrix).

### Bubblewrap as a primitive

Bubblewrap constructs mount and namespace isolation for an unprivileged
process; it is a primitive, not by itself an agent policy, credential broker,
or network allowlist. The caller must define visible/readable paths, writable
binds, namespace choices, and networking. A ro-mounted workspace protects
integrity, not confidentiality. Successful operation depends on user namespace
and mount namespace permissions and distro security policy; package presence
alone does not prove those prerequisites work.

Primary source: [Bubblewrap project](https://github.com/containers/bubblewrap).
Anthropic's [WSL2 setup and Ubuntu/AppArmor notes](https://code.claude.com/docs/en/sandboxing)
provide a concrete example of distro policy blocking user namespaces.

### Codex CLI Linux sandbox: current architecture

Current upstream Linux sandbox documentation describes Bubblewrap as the
default filesystem sandbox, with seccomp filtering; Landlock remains legacy or
backup code, not the current general filesystem path. Codex prefers system
Bubblewrap when available and otherwise can use its bundled helper. The project
explicitly says WSL2 follows its normal Linux Bubblewrap path and WSL1 is not
supported for that sandbox. Current source describes a read-only root with
explicit writable roots, user namespace isolation, normally PID namespace
isolation, and network namespace isolation when network restrictions require
it. Seccomp also addresses restricted networking and WSL-related vsock paths.

Do not summarize the current Codex Linux model as “Landlock-only.” The Linux
source retains Landlock helpers as legacy/backup; Codex's documented current
filesystem backend is Bubblewrap. Kernel Landlock remains relevant to other
implementations: the kernel requires a runtime ABI query, and supported rights
vary by ABI (TCP network rules begin at ABI 4; UDP network rules at ABI 10).
WSL2 status alone does not establish a particular Landlock ABI.

Primary sources: [Codex Linux sandbox README](https://github.com/openai/codex/blob/main/codex-rs/linux-sandbox/README.md),
[Codex Linux sandbox implementation](https://github.com/openai/codex/tree/main/codex-rs/linux-sandbox),
[Linux kernel Landlock documentation](https://docs.kernel.org/userspace-api/landlock.html).

## WSL2 Linux toolchains vs Windows-native tools

WSL2 supports running Linux tools in a Linux distribution and launching Windows
executables from that distribution. These are not the same execution/security
domain: Microsoft documents that a Windows executable launched from WSL runs as
the active Windows user and has that user's Windows permissions. WSL's default
`/mnt/c` DrvFs mount exposes Windows files to Linux processes; Microsoft
recommends storing Linux-command-line projects in the WSL filesystem for
performance. Thus Linux process sandboxing may constrain Linux child processes
but should not be assumed to confine Windows executables reached through WSL
interop or to hide files already visible through mounted paths. Conversely,
Windows-native toolchains and Windows paths are not simply the existing Linux
WSL toolchain; choose the agent/runtime execution side deliberately.

Primary sources: [Microsoft WSL file systems and interop](https://learn.microsoft.com/en-us/windows/wsl/filesystems),
[Microsoft WSL configuration (DrvFs mounts)](https://learn.microsoft.com/en-us/windows/wsl/wsl-config).

## Alternatives and stronger-boundary baseline

### Greywall and Agent Safehouse

The names resolve to different projects. **Greywall** is GreyhavenHQ's
open-source Linux/macOS process sandbox (`greywall`, with `greywatch` for
observe/allow mode), not a Windows-native sandbox. Its docs list Linux
Bubblewrap/namespaces, Landlock, seccomp, and TUN/tun2socks network capture; it
provides agent profiles including OpenCode and accepts arbitrary commands. The
deny-by-default profile restricts filesystem access, while its external
Greyproxy performs domain filtering. TUN-based capture is the stronger
network-enforcement mode; Greywall documents fallback to proxy environment
variables when TUN is unavailable, where programs ignoring those variables may
bypass the proxy. Its own security model describes defense-in-depth, not a
hardened boundary against actively malicious code; allowed domains can still
carry exfiltrated data. Adoption requires installing Greywall and proxy
dependencies, verifying WSL kernel/distro and TUN prerequisites, and reviewing
the selected profile.

**Agent Safehouse** (`eugene1g/agent-safehouse`) is macOS-only, built on Apple's
`sandbox-exec`/Seatbelt. Its maintainer explicitly says it does not work on
Linux or Windows. It is not an option for OpenCode running in WSL2; do not
confuse it with Greywall or other similarly named Linux projects.

Sources: [Greywall repository](https://github.com/GreyhavenHQ/greywall),
[Greywall agent profiles](https://github.com/GreyhavenHQ/greywall/blob/main/docs/agents.md),
[Greywall security model](https://github.com/GreyhavenHQ/greywall/blob/main/docs/security-model.md),
[Agent Safehouse repository](https://github.com/eugene1g/agent-safehouse).

### OpenCode V2 client/server execution boundary

OpenCode V2 is client/server: the shared background service owns sessions,
plugins, permissions, integrations, and tool execution. Clients normally
discover or start that service; `--standalone` selects a private server and
`--server` connects to a specified URL. Therefore, wrapping only the TUI/client
does **not** establish that the server or tool executor is sandboxed. The
wrapped TUI may connect to an already-running shared service outside the
sandbox, and tools then execute in that service's context. To claim whole-agent
containment, launch the relevant OpenCode server inside the sandbox (for
example a suitably configured standalone instance) and verify that shell, file,
plugin, and MCP execution occurs there. Separately inspect MCP servers launched
externally or remote endpoints. This is a consequence of the V2 client/server
design, not something established by wrapping the terminal UI.

Sources: [OpenCode V2 CLI—background service, `--standalone`, and `--server`](https://opencode.ai/v2/docs/cli),
[OpenCode V2 troubleshooting—service ownership](https://opencode.ai/v2/docs/troubleshooting).

### Docker Sandboxes (`sbx`)

Docker documents local `sbx` support on Windows 11 x64 using Windows Hypervisor
Platform (WHP); Linux local sandboxes use KVM, and running inside a VM requires
nested virtualization. On Windows 11, that makes native Windows `sbx` a
separate-VM option without relying on nested KVM inside WSL2. Docker describes
each local sandbox as a microVM with a separate kernel and private Docker
daemon. All outbound TCP traffic routes through a host-side proxy and policy
path. This is the strongest boundary in this comparison for keeping an
autonomous agent from unrelated host processes/resources, not the lightest path
for reusing an existing WSL installation.

By default `sbx run` can mount the workspace directly, so project writes remain
visible on the host; that is compatible with an explicit development-write
requirement, but not host-workspace integrity. Clone mode is an alternative,
not a prerequisite. A read-only workspace still reveals its contents to the
agent, so read-only must not be mistaken for confidentiality. Docker's docs also
describe a host-side MCP gateway and local stdio MCP servers that may execute
outside the VM; audit those integrations rather than assuming every tool is
inside the guest. Docker's proxy-mediated credential injection can keep a real
credential outside the VM, but direct credentials passed into files/environment
remain a separate exposure decision.

Primary sources: [Docker Sandboxes installation and platform requirements](https://docs.docker.com/ai/sandboxes/install/),
[local sandbox architecture](https://docs.docker.com/ai/sandboxes/architecture/),
[isolation model](https://docs.docker.com/ai/sandboxes/architecture/security/isolation/).

### SBX adoption and small-team fit

Public-attention snapshot, independently checked through the GitHub repository
API on 2026-10-23 (stars, not installations or market share):

| Repository | Stars |
| --- | ---: |
| [Bubblewrap](https://api.github.com/repos/containers/bubblewrap) | 9,168 |
| [Firejail](https://api.github.com/repos/netblue30/firejail) | 7,709 |
| [`srt`](https://api.github.com/repos/anthropics/sandbox-runtime) | 5,654 |
| [nono](https://api.github.com/repos/nolabs-ai/nono) | 4,643 |
| [SBX releases](https://api.github.com/repos/docker/sbx-releases) | 469 |
| [Greywall](https://api.github.com/repos/GreyhavenHQ/greywall) | 311 |

These repositories differ in age and purpose, especially SBX's release-only
repository. Counts cannot establish relative deployment or security quality.
The cited Claude documentation establishes integration of `srt`; Bubblewrap's
README identifies Flatpak as a user, and Codex's Linux sandbox README documents
its Bubblewrap backend. Those integrations are stronger evidence of deployed
technology than stars, but do not count standalone agent-wrapper installations.

Docker's overall popularity is not evidence of standalone SBX adoption. At
review time its [release repository API](https://api.github.com/repos/docker/sbx-releases)
reported 469 stars and repository creation on 2026-03-03. These are limited
public signals, not measurements of active teams or deployment maturity; this
research does not establish that SBX is an industry standard or widely deployed.
Docker explicitly documents [OpenCode support](https://docs.docker.com/ai/sandboxes/agents/opencode/),
but that alone does not validate the bundled version against this team's V2
plugins/configuration. Its [FAQ](https://docs.docker.com/ai/sandboxes/faq/)
states local CLI/compute are free for commercial work, sign-in is required,
and central organization governance/audit features require a separate paid
subscription. SBX is a credible small-team pilot when a VM boundary is worth
guest-toolchain maintenance; popularity alone is not a reason to select it.

### Microsoft eXecution Container (MXC)

MXC is an SDK embedded in a calling application, not a ready-made general
developer container workflow. Its upstream README lists Linux Bubblewrap and
Windows ProcessContainer as platform defaults, with other backends (including
LXC and VM-style options) having backend-specific support/qualifications.
Therefore “MXC” alone does not name one isolation boundary: select and assess
the backend and policy semantics. It may be useful when a custom launcher and
policy-driven execution API are acceptable, but is less direct than enabling
Claude's existing sandbox for a WSL workflow.

Primary source: [Microsoft MXC repository](https://github.com/microsoft/mxc).

### WSL distro isolation and rootless containers

A separate WSL distribution/root filesystem can help organize dependencies,
but Microsoft describes WSL distributions as environments managed by WSL, not
as mutually isolated independent VMs. Do not treat distro separation alone as
an equivalent to `sbx`'s separate guest kernel. Likewise, a rootless container
is a useful packaging/process boundary, but does **not** automatically reuse
host-installed tools. The image must include the toolchain, or the operator must
deliberately expose it. Bind-mounting arbitrary host binaries is not a general
solution: they may rely on host libraries, interpreters, loader paths, devices,
configuration, or ABI details that are absent/incompatible in the container.
That last compatibility point is a general technical caveat, not a claim of a
specific tool having been tested here.

Microsoft's WSL configuration describes per-distro configuration and DrvFs
mounts; Docker's architecture comparison distinguishes containers from its
microVM isolation. Sources: [Microsoft WSL configuration](https://learn.microsoft.com/en-us/windows/wsl/wsl-config),
[Microsoft WSL file systems](https://learn.microsoft.com/en-us/windows/wsl/filesystems),
[Docker Sandboxes architecture](https://docs.docker.com/ai/sandboxes/architecture/).

## WSL2 prerequisites: documented support vs checks still needed

- Anthropic and Codex document WSL2 support for their Linux sandbox paths. That
  is product support, not evidence that a particular distro/kernel configuration
  has working unprivileged user namespaces, seccomp, Bubblewrap, or a required
  Landlock ABI.
- Anthropic specifically documents installing Bubblewrap and `socat`, and the
  Ubuntu 24.04+ AppArmor user-namespace restriction. Codex notes that
  Bubblewrap's user namespaces must be creatable and calls out WSL1 as
  unsupported.
- Linux kernel documentation says Landlock availability and ABI are queried at
  runtime (`landlock_create_ruleset` with `LANDLOCK_CREATE_RULESET_VERSION`);
  it may be unsupported or disabled. Do not infer availability from the WSL2
  label or distro release.
- Microsoft documents WSL2's kernel/configuration as VM-backed and configurable,
  but its general WSL configuration documentation does not promise that every
  kernel feature or distro policy required by these sandboxes is enabled.

Primary sources: [Microsoft WSL configuration](https://learn.microsoft.com/en-us/windows/wsl/wsl-config),
[Anthropic WSL2 setup](https://code.claude.com/docs/en/sandboxing),
[Codex Linux sandbox README](https://github.com/openai/codex/blob/main/codex-rs/linux-sandbox/README.md),
[Landlock ABI query](https://docs.kernel.org/userspace-api/landlock.html#landlock-abi-versions).

## Tradeoffs against a separate VM (`sbx`)

In-place process sandboxes reuse the WSL distro, installed toolchains, and
existing Linux workflows with comparatively little setup. They can enforce
useful filesystem, namespace, and syscall boundaries, but share the WSL Linux
kernel and depend on correctly configured launchers, policies, credential
handling, and IPC exposure. They do not automatically sandbox an agent's
non-shell tools or MCP servers, and exposed processes, sockets, descriptors,
environment credentials, or host interop can provide routes outside the
intended boundary.

A separate VM sandbox such as native Windows `sbx` is the stronger fit when the
goal is to isolate the agent from unrelated host resources or obtain a distinct
guest kernel. It costs more in provisioning, resources, and toolchain setup;
project mounts and explicitly shared services still determine what data the
agent can read or change. Windows `sbx`'s documented WHP support avoids needing
to assume nested KVM within WSL2; whether the target machine meets the WHP
prerequisites remains to be verified.

**Recommendation:** For OpenCode on WSL2 while retaining the existing Linux
toolchain, start with an `srt` trial: its underlying implementation is used by
Claude Code, whose Linux/WSL2 path is explicitly documented. That does not prove
the standalone OpenCode deployment works without policy/launcher configuration.
Greywall is a second candidate with useful packaged OpenCode profiles, not a
demonstrated winner over `srt`. Validate its TUN capture and egress enforcement;
proxy-environment fallback is not equivalent when clients can ignore it. With
either wrapper, launch OpenCode V2's server inside the boundary, not just the
TUI, and verify MCP/tool execution placement. This host-native route is a
practical tool-reuse choice, not
merely protection against mistakes: a configured same-kernel sandbox can
meaningfully constrain compromised children. Choose native Windows `sbx` when
the separate guest-kernel boundary is the priority; use MXC when an embedded,
backend-selectable containment SDK is acceptable. Keep Linux WSL tools and
Windows-native tools distinct. None of these options hides readable source or
secrets unless read access and outbound channels are separately controlled.

## Proposed real-host validation checklist (not executed)

Run only with a disposable project and a harmless planted dummy secret. Confirm
the effective policy on the target WSL2 distro rather than inferring it from
documentation or dependency presence:

1. From a sandboxed command, attempt an out-of-workspace write; verify it is
   denied. Attempt a write inside the project; verify it succeeds as intended.
2. Plant a dummy secret outside allowed read paths; attempt to read it from a
   sandboxed command; verify denial. Do not test with real credentials.
3. Attempt network egress to a domain not on the allowlist; verify denial, then
   verify an explicitly allowed development endpoint works if required.
4. Attempt to launch a harmless Windows executable (for example `cmd.exe`) and
   access a harmless host/interop socket from inside the sandbox; verify the
   intended block. Check that the optional seccomp filter is actually present:
   `failIfUnavailable` covers required sandbox availability, but does not by
   itself establish that this optional filter is installed or blocking WSL
   interop.
5. For OpenCode V2, verify the private server/tool executor is inside the
   sandbox rather than connected to an outside shared service. Inventory file
   tools, plugins, MCP servers, and helpers (and Claude hooks if evaluating it);
   verify which execute inside versus outside the sandbox and confirm that
   outside components cannot access data or services beyond the intended scope.
   For `srt`, verify the agent and intended MCP child processes are launched
   beneath the wrapper, not merely shell commands.
6. Exercise the real Linux toolchain and expected cache/output paths. `.NET`,
   `mise`, and `npm` may need explicit `filesystem.allowWrite` paths for their
   caches or installed tool locations. If blocking reads across home, remember
   that this also hides locations such as `~/.local` or `mise` installs unless
   selectively re-exposed; add only the needed paths and retest the secret
   denial.

These are proposed acceptance checks, not performed validation. Passing them
would test the configured deployment's behavior, not establish a comprehensive
security audit.

## Validation status

No WSL kernel, distro, Bubblewrap installation, sandbox runtime, agent, or MCP
configuration was tested. This is desk research based on the cited upstream
documentation/source, not runtime validation or a security audit.
