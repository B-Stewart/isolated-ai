# Browser mixin provisioning

Installs the pinned `agent-browser` CLI and exposes it at
`/opt/isoai/mixins/browser/bin/agent-browser`, also exposed on PATH.
Provisioning remains an explicit guest operation; image builds and sandbox
startup install neither the browser nor its Linux libraries.

## Provision as the guest user

Open a guest shell using the [experiment guide](../../README.md#guest-shell-and-diagnostics),
then run as `agent` (UID 1000):

```bash
/opt/isoai/mixins/browser/install-browser
```

The helper runs the pinned CLI's `install --with-deps`: it installs Debian
libraries through sudo and downloads Chrome for Testing into the guest user's
cache. Do not prefix the helper with sudo, which would put browser state under
root's home. Package-manager or download failures propagate as a nonzero exit.
The helper can be rerun after interrupted provisioning or when checking an
existing guest. It installs dependencies again as needed; it does not remove
browser state. Browser selection follows the pinned CLI's installer, not a
separately pinned Chrome version, so record the downloaded version per run.

The mixin allows `deb.debian.org:80` for the shared base's Debian bookworm apt
sources, plus the declared browser-download hosts over HTTPS. The base preserves
SBX proxy variables through sudo. If you override apt sources or a download
redirect needs another destination, inspect the blocked request and permit the
specific destination before retrying. Websites under test need their own rules.

## Headless smoke test

Use an inline page first so no additional website allowlist entry is needed:

```bash
export AGENT_BROWSER_SESSION=sbx-browser-smoke
agent-browser --version
agent-browser open 'data:text/html,<title>SBX browser smoke</title><h1>Browser ready</h1>'
agent-browser get title
agent-browser snapshot
agent-browser eval navigator.userAgent
agent-browser screenshot /tmp/sbx-browser-smoke.png
agent-browser close
```

Expect the title `SBX browser smoke`, a heading containing `Browser ready`, and
a nonempty PNG. Run provisioning a second time and repeat the smoke test.
Then test a real project page under the intended SBX network policy. Copy any
wanted screenshots out before removing the sandbox. CLI version output alone
does not verify browser installation or launch.
