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
docker run -it --rm `
  -v claude-auth:/home/claude/.claude `
  -v "${PWD}:/workspace" `
  isolated-claude `
  login
```

5. Edit .claude/settings.json to the below to disable memory since it is going to blend per project due to the workspace dir mount
```
{
  "autoMemoryEnabled": false
}
```

### In a workspace (hardened)
```
docker run -it --rm `
  --cap-drop ALL `
  --security-opt no-new-privileges:true `
  --pids-limit 256 `
  --tmpfs /tmp:rw,noexec,nosuid,size=256m `
  -v claude-auth:/home/claude/.claude `
  -v "${PWD}:/workspace" `
  isolated-claude
```

#### Hardened flag notes

- `--cap-drop ALL`: removes Linux capabilities from the container process, reducing kernel-level powers.
- `--security-opt no-new-privileges:true`: blocks privilege escalation (including setuid/setgid paths).
- `--pids-limit 256`: limits process count to reduce fork-bomb/resource exhaustion risk.
- `--tmpfs /tmp:rw,noexec,nosuid,size=256m`: makes `/tmp` ephemeral, disallows executing from `/tmp` (`noexec`), and disables setuid semantics (`nosuid`).

#### Trade-offs

- Some tooling may fail if it expects elevated capabilities.
- Workflows that execute binaries from `/tmp` can fail due to `noexec`.
- Very parallel workloads can hit the PID cap; raise `--pids-limit` if needed.