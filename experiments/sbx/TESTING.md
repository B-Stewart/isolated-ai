# Deferred SBX acceptance tests

Status: **not run in SBX**. Local Docker builds and offline checks are recorded
in [README.md](README.md#verification); they do not establish sandbox behavior.
Native WSL2 testing is deferred until a Windows update restores working nested
virtualization on the affected AMD host. See [WSL #41917](https://github.com/microsoft/WSL/issues/41917).
Do not disable security features or roll back Windows updates merely to complete
this checklist.

Record the date, Windows build, WSL/kernel version, SBX version, image digests,
and result for each gate. Keep credentials, transcripts, and diagnostic logs
private. Leave unchecked items pending rather than treating builds as substitutes.

## 1. Host readiness

- [ ] After installing the Windows fix and rebooting, record `wsl --version`
  and `wsl -l -v` from PowerShell.
- [ ] In Ubuntu, `sudo kvm-ok` reports usable acceleration. `/dev/kvm` exists
  and is readable/writable by the account running SBX. On this AMD machine,
  confirm `grep -m1 -w svm /proc/cpuinfo` returns the virtualization flag.
- [ ] Install/check Linux `sbx` using Docker's current installation guide;
  record `sbx version`. Docker Desktop working is not a replacement for KVM.
- [ ] Publish the shared base to a registry reachable by the SBX builder and
  record its immutable digest. Local Docker tags and `sbx template load` are
  not the v3 kit distribution path. No images have been published by this scaffold.

Stop here if KVM is still unavailable. The remaining gates are intentionally
deferred; a Windows-native SBX test would be a separate environment result.

## 2. Plans, creation, and isolation

Use disposable project clones outside this trusted configuration checkout.
Follow the [launch commands](README.md#launch-and-lifecycle), supplying both
`workspace` and the registry-accessible `base_image`. Use different sandbox names
and separate clones for the plain and OMO profiles.

- [ ] `sbx env plan` accepts each profile and resolves the intended workload,
  mixins, base image, workspace, and resource limits. Review the plan before
  approving creation.
- [ ] Create both sandboxes. Confirm the guest user is UID 1000 and the selected
  project is writable. No unrelated host directories or Docker socket are mounted.
- [ ] Confirm SBX's shared skills store is disabled, no host-global MCP
  registrations were added, and no host OpenCode configuration/state was imported.
- [ ] In the plain guest, inspect the generated OpenCode config: Context7 and
  CodeGraph are present under `mcp.servers`, skills point to kit-owned guest
  paths, and there is no OMO plugin or OMO sidecar configuration.
- [ ] In the OMO guest, confirm those same integrations remain present and only
  this composition includes OMO's plugin, package, and sidecar configuration.
- [ ] Re-launching the agent produces the same generated configuration without
  permission errors. Changing compositions uses a new/recreated sandbox, not a
  claim that reattaching hot-swaps installed kits.

## 3. Tools, project runtimes, and integrations

- [ ] Verify `opencode`, `bun`, `mise`, `gh`, `tooling-node`, and `tooling-npm`
  versions in the guest. Verify `agent-browser` and `codegraph` are on PATH.
- [ ] In a disposable project, declare and deliberately trust/install a different
  supported Node version through mise. Project commands resolve that version in
  interactive and non-interactive shells; tooling wrappers retain the image's
  pinned Node/npm. Record any missing download destinations and allow only those
  required for the test.
- [ ] OpenCode reports Context7 connected; make one known library-documentation
  query. Confirm the local stdio server can reach its API without registering it
  through SBX's host MCP gateway.
- [ ] Initialize/index the disposable project with CodeGraph, then connect its
  MCP server and perform one code exploration query. A started process alone is
  not a successful tool-call test.
- [ ] Both starter skills are discovered and can be loaded. Replace/extend the
  starter collection deliberately; none of the host's skills should appear merely
  because they exist on the host.
- [ ] If GitHub integration is wanted, authenticate inside the guest through an
  approved mechanism and perform a read-only `gh` query. No host credentials are
  assumed to have been copied.
- [ ] Provision the browser and Linux libraries explicitly using the
  [browser note](mixins/browser/README.md). Permit only needed download/test
  destinations. Open a known test page headlessly, inspect its content, and save
  a screenshot. CLI installation alone does not satisfy this gate.

## 4. Credentials and optional paid agent tests

- [ ] Select intended provider/model settings and approve the kit's credential
  request. Verify proxy-managed authentication without printing keys or copying
  them into configuration/source files.
- [ ] **Only after opting into provider charges**, perform one small plain-agent
  request and confirm ordinary approval behavior is retained.
- [ ] Check OMO's compatibility with the pinned OpenCode version and inspect its
  effective presets/models. Do not assume specialists inherit the workload's
  Anthropic model or that all required provider credentials already exist.
- [ ] **Only after opting into additional charges**, perform one bounded OMO
  delegation and verify the intended specialist, provider/model, MCPs, and skills.

## 5. Persistence and removal

- [ ] Stop and restart each sandbox. Installed project runtimes, guest config,
  and intended agent state persist; MCPs/skills still work after reconnecting.
- [ ] Preserve any desired private files before removing the test environments
  with the matching profile, arguments, and names. Direct-mounted project files
  remain intact; guest-only state is removed. Do not use global `sbx reset` for
  this test.

Acceptance requires the applicable gates above plus a recorded explanation for
any deliberate skips. Browser and paid-agent gates can remain explicitly pending
if those features are not yet being adopted.
