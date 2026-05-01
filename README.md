# Isolated AI
Repoistory designed to illustrate how to run Claude Code and other agent harnesses within docker for isolation.

## Claude

### Build
docker build -f isolated-claude.dockerfile -t isolated-claude .

### First Time Auth

1. Rebuild image
```
docker build -f isolated-claude.dockerfile -t isolated-claude .
```

2. Reset old auth volume (only needed once if you used the older setup)
```
docker volume rm claude-auth
```

3. Create auth volume
```
docker volume create claude-auth
```

4. Login
```
$dockerArgs = @(
  '-it', '--rm',
  '-v', 'claude-auth:/home/claude/.claude',
  '-v', "${PWD}:/workspace",
  'isolated-claude',
  'login'
)
docker run $dockerArgs
```

5. Edit .claude/settings.json to the below to disable memory since it is going to blend per project due to the workspace dir mount
```
{
  "autoMemoryEnabled": false
}
```

### In a workspace (hardened)
--rm and --name is optional depending on how you want to manage your containers

```
$dockerArgs = @(
  '-it', 
  '--name', 'project-name-dev',
  '--cap-drop', 'ALL',
  '--security-opt', 'no-new-privileges:true',
  '--pids-limit', '2048',
  '--tmpfs', '/tmp:rw,noexec,nosuid,size=256m',
  '--tmpfs', '/workspace/node_modules:rw,exec,uid=1001,gid=1001,mode=0755',
  '-v', 'claude-auth:/home/claude/.claude',
  '-v', "${PWD}:/workspace",
  'isolated-claude'
)
docker run $dockerArgs
```

### Playwright in container

The image includes Chromium runtime libraries so Playwright e2e tests can run.

After entering the container, run this once per project (or when Playwright version changes):

```
npx playwright install chromium
```

If you want browser binaries to persist between runs, mount a cache volume:

```
-v pw-browsers:/home/claude/.cache/ms-playwright
```

#### Hardened flag notes

- `--cap-drop ALL`: removes Linux capabilities from the container process, reducing kernel-level powers.
- `--security-opt no-new-privileges:true`: blocks privilege escalation (including setuid/setgid paths).
- `--pids-limit 2048`: limits process count to reduce fork-bomb/resource exhaustion risk while allowing heavier dev/build workloads.
- `--tmpfs /tmp:rw,noexec,nosuid,size=256m`: makes `/tmp` ephemeral, disallows executing from `/tmp` (`noexec`), and disables setuid semantics (`nosuid`).
- `--tmpfs /workspace/node_modules:rw,exec,uid=1001,gid=1001,mode=0755`: keeps `node_modules` Linux-native, executable, and writable by the `claude` user without persisting across runs.

#### Trade-offs

- Some tooling may fail if it expects elevated capabilities.
- Workflows that execute binaries from `/tmp` can fail due to `noexec`.
- Very parallel workloads can hit the PID cap; raise `--pids-limit` if needed.