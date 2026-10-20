#!/usr/bin/env bash
set -Eeuo pipefail

script=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/isoai
tmp=$(mktemp -d)
fixture_pid=''
cleanup() {
  if [[ -n $fixture_pid ]]; then
    kill "$fixture_pid" 2>/dev/null || true
    wait "$fixture_pid" 2>/dev/null || true
  fi
  python3 - "$script-ssh-agent.py" "$HOME/.local/state/isoai/ssh" <<'PY'
import os
import signal
import sys
import time

helper, root = sys.argv[1], os.path.realpath(sys.argv[2])
owned = []
for entry in os.scandir('/proc'):
    if not entry.name.isdigit():
        continue
    try:
        args = open(f'{entry.path}/cmdline', 'rb').read().decode(errors='replace').split('\0')
    except (FileNotFoundError, PermissionError, ProcessLookupError):
        continue
    if helper in args and any(arg == root or arg.startswith(root + os.sep) for arg in args):
        owned.append(int(entry.name))
for pid in owned:
    try:
        os.kill(pid, signal.SIGTERM)
    except ProcessLookupError:
        pass
deadline = time.monotonic() + 2
while owned and time.monotonic() < deadline:
    owned = [pid for pid in owned if os.path.exists(f'/proc/{pid}')]
    time.sleep(0.02)
for pid in owned:
    try:
        os.kill(pid, signal.SIGKILL)
    except ProcessLookupError:
        pass
PY
  rm -rf "$tmp"
}
trap cleanup EXIT
mkdir -p "$tmp/bin" "$tmp/home" "$tmp/workspace"
export HOME="$tmp/home" WORKSPACE="$tmp/workspace" LOG="$tmp/log"
unset SSH_AUTH_SOCK

cat >"$tmp/bin/docker" <<'MOCK'
#!/usr/bin/env bash
printf 'docker' >>"$LOG"
printf '\t%s' "$@" >>"$LOG"
printf '\n' >>"$LOG"
case "$1" in
  info) exit 0 ;;
  container) exit "${CONTAINER_EXISTS:-1}" ;;
  inspect) printf '%s\n' "${CONTAINER_RUNNING:-false}" ;;
  start)
    if [[ -n ${START_ERROR:-} ]]; then
      printf '%s\n' "$START_ERROR" >&2
      exit "${START_STATUS:-1}"
    fi
    exit 0
    ;;
  run|exec|rm) exit 0 ;;
esac
MOCK
cat >"$tmp/bin/code" <<'MOCK'
#!/usr/bin/env bash
printf 'code' >>"$LOG"
printf '\t%s' "$@" >>"$LOG"
printf '\n' >>"$LOG"
MOCK
cat >"$tmp/bin/xxd" <<'MOCK'
#!/usr/bin/env bash
printf '7061796c6f6164\n'
MOCK
chmod +x "$tmp/bin/docker" "$tmp/bin/code" "$tmp/bin/xxd"
export PATH="$tmp/bin:$PATH"

fail() { printf 'FAIL: %s\n' "$*" >&2; exit 1; }
reset() { : >"$LOG"; }
run() { (cd "$WORKSPACE" && "$script" "$@"); }
assert_has() { [[ $1 == *"$2"* ]] || fail "expected output to contain: $2"; }
assert_rejected() {
  reset
  rm -rf "$HOME"
  mkdir -p "$HOME"
  local status=0
  run "$@" >"$tmp/out" 2>"$tmp/err" || status=$?
  [[ $status -eq 2 ]] || fail "expected exit 2 for: $* (got $status)"
  [[ ! -s $tmp/out && -s $tmp/err ]] || fail "expected usage error on stderr for: $*"
  [[ ! -s $LOG ]] || fail "host-side command ran for rejected args: $*"
  [[ ! -e "$HOME/.agents" ]] || fail "host directories created for rejected args: $*"
}
assert_image_and_name() {
  local image=$1 suffix=$2
  assert_has "$(<"$LOG")" "$image"
  local runline
  runline=$(while IFS= read -r line; do [[ $line == docker$'\t'run$'\t'* ]] && printf '%s\n' "$line"; done <"$LOG" || true)
  assert_has "$runline" "isolated-ai-workspace-"
  if [[ $suffix == gd ]]; then
    assert_has "$runline" '-gd'
  else
    [[ $runline != *'-gd'* ]] || fail 'standard container name has gd suffix'
  fi
}
run_name_from_log() {
  while IFS= read -r line; do
    if [[ $line == docker$'\t'run$'\t'* ]]; then
      IFS=$'\t' read -r -a fields <<<"$line"
      for ((i = 0; i < ${#fields[@]} - 1; i++)); do
        if [[ ${fields[i]} == --name ]]; then
          printf '%s\n' "${fields[i + 1]}"
          return 0
        fi
      done
    fi
  done <"$LOG"
  return 1
}
run_line_from_log() {
  while IFS= read -r line; do
    [[ $line == docker$'\t'run$'\t'* ]] && { printf '%s\n' "$line"; return 0; }
  done <"$LOG"
  return 1
}
assert_code_before_command() {
  local code_line=0 command_line=0 index=0 line
  while IFS= read -r line; do
    ((index += 1))
    [[ $line == code$'\t'* ]] && code_line=$index
    [[ $line == docker$'\t'exec$'\t'*-w$'\t'*$'\tprintf\t'* ]] && command_line=$index
  done <"$LOG"
  [[ $code_line -gt 0 && $command_line -gt $code_line ]] || fail 'VS Code did not launch before the optional command'
}

# Every help form is handled before Docker checks and host initialization.
for args in 'help' '--help' '-h'; do
  reset
  rm -rf "$HOME"
  mkdir -p "$HOME"
  run "$args" >"$tmp/out" || fail "help failed: $args"
  assert_has "$(<"$tmp/out")" 'isoai [help|--help|-h]'
  assert_has "$(<"$tmp/out")" '--image=gd|-i=gd'
  assert_has "$(<"$tmp/out")" '--code|-c'
  assert_has "$(<"$tmp/out")" 'braydens/agentic-base:latest'
  [[ ! -s $LOG && ! -e "$HOME/.agents" ]] || fail 'help caused side effects'
done

# Standard defaults, supported selector spellings, and mixed option order.
for args in '--image gd' '-i gd' '--image=gd' '-i=gd' '-c --image gd' '--image gd -c'; do
  reset
  # shellcheck disable=SC2086
  run $args >/dev/null || fail "valid options failed: $args"
  assert_image_and_name 'braydens/agentic-gamedev:latest' gd
done
reset
run >/dev/null || fail 'default invocation failed'
assert_image_and_name 'braydens/agentic-base:latest' standard
standard_name=$(run_name_from_log) || fail 'standard container name missing'

# Relay mounts must never use a symlink or an uncreatable path as source.
ssh_state="$HOME/.local/state/isoai/ssh/$standard_name"
mkdir -p "$(dirname "$ssh_state")" "$tmp/foreign-relay"
rm -rf "$ssh_state"
ln -s "$tmp/foreign-relay" "$ssh_state"
[[ -L "$ssh_state" ]] || fail "symlink fixture was not created: $ssh_state"
reset
unsafe_status=0
run >"$tmp/out" 2>"$tmp/err" || unsafe_status=$?
[[ $unsafe_status -ne 0 ]] || fail 'symlink relay directory did not block startup'
assert_has "$(<"$tmp/err")" 'private SSH relay directory'
[[ $(<"$LOG") != *$'docker\trun\t'* ]] || fail 'container created with symlink relay mount source'
[[ -d "$tmp/foreign-relay" && ! -S "$tmp/foreign-relay/agent.sock" ]] || fail 'symlink target was modified'
rm "$ssh_state"

mkdir "$ssh_state"
chmod 755 "$ssh_state"
reset
run >/dev/null || fail 'owned relay directory with unsafe mode blocked startup'
[[ $(stat -c '%a' "$ssh_state") == 700 ]] || fail 'owned relay directory was not made private'

no_python_bin="$tmp/no-python-bin"
mkdir "$no_python_bin"
for tool in env bash dirname id sha256sum cut mkdir chmod touch; do
  ln -s "$(command -v "$tool")" "$no_python_bin/$tool"
done
reset
PATH="$no_python_bin:$tmp/bin" run >"$tmp/out" 2>"$tmp/err" || fail 'missing Python prevented container startup'
assert_has "$(<"$tmp/err")" 'python3 is unavailable'
assert_has "$(<"$tmp/err")" 'an existing relay may remain active'
assert_has "$(<"$LOG")" $'docker\trun\t'

rm -rf "$HOME/.local/state"
touch "$HOME/.local/state"
reset
mkdir_status=0
run >"$tmp/out" 2>"$tmp/err" || mkdir_status=$?
[[ $mkdir_status -ne 0 ]] || fail 'relay directory creation failure did not block startup'
assert_has "$(<"$tmp/err")" 'could not create the private SSH relay directory'
[[ $(<"$LOG") != *$'docker\trun\t'* ]] || fail 'container created without a safe relay directory'
rm "$HOME/.local/state"

# A real host AF_UNIX socket fixture ensures SSH forwarding tests do not depend
# on, or modify, the user's SSH agent.
cat >"$tmp/ssh-agent-fixture.py" <<'PY'
import socket
import sys

path = sys.argv[1]
server = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
server.bind(path)
server.listen()
server.settimeout(0.2)
while True:
    try:
        connection, _ = server.accept()
    except TimeoutError:
        continue
    with connection:
        connection.sendall(b'fixture-token:' + connection.recv(1024))
PY
fixture_socket="$tmp/host-agent.sock"
python3 "$tmp/ssh-agent-fixture.py" "$fixture_socket" >"$tmp/fixture.out" 2>&1 &
fixture_pid=$!
for _ in {1..100}; do
  [[ -S $fixture_socket ]] && break
  sleep 0.01
done
[[ -S $fixture_socket ]] || fail 'AF_UNIX SSH fixture did not create its socket'
python3 - "$fixture_socket" <<'PY' || fail 'AF_UNIX SSH fixture did not echo its token'
import socket
import sys

client = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
client.connect(sys.argv[1])
client.sendall(b'probe')
assert client.recv(1024) == b'fixture-token:probe'
client.close()
PY

# New containers mount a stable per-container directory, never the host socket.
reset
SSH_AUTH_SOCK="$fixture_socket" run >/dev/null || fail 'invocation with host SSH fixture failed'
ssh_name=$(run_name_from_log) || fail 'SSH-enabled container name missing'
ssh_runline=$(run_line_from_log) || fail 'SSH-enabled container run missing'
assert_has "$ssh_runline" "type=bind,src=$HOME/.local/state/isoai/ssh/$ssh_name,dst=/run/isoai/ssh,readonly"
assert_has "$ssh_runline" 'SSH_AUTH_SOCK=/run/isoai/ssh/agent.sock'
[[ $ssh_runline != *"src=$fixture_socket"* && $ssh_runline != *'/ssh-agent'* ]] || fail 'host SSH socket was mounted directly'

# An unavailable host agent is advisory and must not prevent container startup.
reset
SSH_AUTH_SOCK="$tmp/missing-agent.sock" run >/dev/null || fail 'missing SSH agent prevented container startup'
assert_has "$(<"$LOG")" $'docker\trun\t'

# A saved legacy /ssh-agent mount cannot be repaired in place. Keep the old
# container intact, return Docker's original error, and give preservation-first
# migration guidance even when a live host agent now exists.
reset
legacy_error='Error response from daemon: failed to mount /ssh-agent: not a directory'
legacy_status=0
CONTAINER_EXISTS=0 CONTAINER_RUNNING=false START_ERROR="$legacy_error" START_STATUS=125 \
  SSH_AUTH_SOCK="$fixture_socket" run >"$tmp/out" 2>"$tmp/err" || legacy_status=$?
[[ $legacy_status -eq 125 ]] || fail "legacy mount failure returned $legacy_status instead of 125"
legacy_log=$(<"$LOG")
[[ $legacy_log != *$'docker\trm\t'* && $legacy_log != *$'docker\trun\t'* && \
   $legacy_log != *$'docker\texec\t'* ]] || fail 'legacy container was removed, recreated, or execed'
assert_has "$(<"$tmp/err")" 'snapshot'
assert_has "$(<"$tmp/err")" 'preserve'
assert_has "$(<"$tmp/err")" 'cannot be retrofitted'

# Unrelated docker-start errors remain unchanged and non-destructive.
reset
unrelated_status=0
CONTAINER_EXISTS=0 CONTAINER_RUNNING=false START_ERROR='daemon is unavailable' START_STATUS=42 \
  run >"$tmp/out" 2>"$tmp/err" || unrelated_status=$?
[[ $unrelated_status -eq 42 ]] || fail "unrelated start failure returned $unrelated_status instead of 42"
assert_has "$(<"$tmp/err")" 'daemon is unavailable'
assert_has "$(<"$tmp/err")" 'unrelated error'
unrelated_log=$(<"$LOG")
[[ $unrelated_log != *$'docker\trm\t'* && $unrelated_log != *$'docker\trun\t'* && \
   $unrelated_log != *$'docker\texec\t'* ]] || fail 'unrelated start failure changed the existing container'

reset
run --image gd >/dev/null || fail 'gd invocation failed'
gd_name=$(run_name_from_log) || fail 'gd container name missing'
[[ $gd_name == "$standard_name-gd" ]] || fail "expected distinct gd name $standard_name-gd, got $gd_name"

# Invalid CLI input must be rejected before Docker or host setup.
assert_rejected 'code'
assert_rejected '--image'
assert_rejected '-i'
assert_rejected '--image='
assert_rejected '-i='
assert_rejected '--image' ''
assert_rejected '-i' ''
assert_rejected '--image' 'other'
assert_rejected '-i=other'
assert_rejected '--image=other' '--image=gd'
assert_rejected '--unknown'
assert_rejected '--'

# -- forwards command and argument boundaries (including option-like values).
reset
run -- '--flag' 'two words' 'x=y' >/dev/null || fail 'command invocation failed'
assert_has "$(<"$LOG")" $'docker\texec\t-i\t-u\tagent'
assert_has "$(<"$LOG")" $'\t--flag\ttwo words\tx=y'

# VS Code runs before the optional container command in long and short forms.
reset
run --code --image=gd -- 'printf' 'hello world' >/dev/null || fail 'long VS Code/gd command failed'
assert_image_and_name 'braydens/agentic-gamedev:latest' gd
assert_has "$(<"$LOG")" $'\tprintf\thello world'
assert_code_before_command
reset
run -c -i=gd -- 'printf' 'hello world' >/dev/null || fail 'short VS Code/gd command failed'
assert_image_and_name 'braydens/agentic-gamedev:latest' gd
assert_has "$(<"$LOG")" $'\tprintf\thello world'
assert_code_before_command

# Existing gd container is inspected/reused under its suffixed name.
reset
CONTAINER_EXISTS=0 run --image gd >/dev/null || fail 'existing gd-container invocation failed'
[[ $(<"$LOG") != *$'docker\trun\t'* ]] || fail 'existing container was recreated'
assert_has "$(<"$LOG")" $'docker\tcontainer\tinspect\t'
assert_has "$(<"$LOG")" "$gd_name"

printf 'isoai launcher regression tests passed\n'
