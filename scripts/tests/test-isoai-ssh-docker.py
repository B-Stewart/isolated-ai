#!/usr/bin/env python3
"""Real Docker regression for the stable SSH relay directory mount."""

import json
import os
from pathlib import Path
import signal
import socket
import stat
import subprocess
import sys
import tempfile
import threading
import time
import uuid
import unittest

ROOT = Path(__file__).resolve().parents[2]
HELPER = (ROOT / "scripts" / "isoai-ssh-agent.py").resolve()
IMAGE_REF = os.environ.get("ISOAI_SSH_TEST_IMAGE", "braydens/agentic-gamedev:latest")
CONTAINER_SOCK = "/run/isoai/ssh/agent.sock"
PAYLOAD = b"\x00\xffisoai-fixture-token\x80\x01"


class TokenAgent(threading.Thread):
    def __init__(self, path, token):
        super().__init__(daemon=True)
        self.path = str(path)
        self.token = token
        self.listener = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
        self.listener.bind(self.path)
        self.listener.listen()
        self.listener.settimeout(0.1)
        self.stopping = threading.Event()
        self.start()

    def run(self):
        while not self.stopping.is_set():
            try:
                client, _ = self.listener.accept()
            except TimeoutError:
                continue
            except OSError:
                break
            with client:
                try:
                    client.settimeout(2)
                    payload = b""
                    while len(payload) < len(PAYLOAD):
                        part = client.recv(4096)
                        if not part:
                            break
                        payload += part
                    if payload:
                        client.sendall(self.token + payload)
                except OSError:
                    pass

    def close(self):
        self.stopping.set()
        self.join(timeout=1)
        self.listener.close()


def helper_processes(directory):
    """Return only processes with this helper's exact serve identity and path."""
    matches = []
    for entry in Path("/proc").iterdir():
        if not entry.name.isdigit():
            continue
        try:
            argv = (entry / "cmdline").read_bytes().decode(errors="replace").split("\0")
        except (FileNotFoundError, PermissionError, ProcessLookupError):
            continue
        if str(HELPER) in argv and "serve" in argv and str(directory) in argv:
            matches.append(int(entry.name))
    return matches


def terminate_helpers(directory):
    pids = helper_processes(directory)
    for pid in pids:
        try:
            os.kill(pid, signal.SIGTERM)
        except ProcessLookupError:
            pass
    deadline = time.monotonic() + 4
    while pids and time.monotonic() < deadline:
        pids = [pid for pid in pids if helper_is_running(pid)]
        time.sleep(0.05)
    for pid in pids:
        try:
            os.kill(pid, signal.SIGKILL)
        except ProcessLookupError:
            pass
    deadline = time.monotonic() + 2
    while pids and time.monotonic() < deadline:
        pids = [pid for pid in pids if helper_is_running(pid)]
        time.sleep(0.05)
    if pids:
        raise RuntimeError(f"test relay processes did not exit: {pids}")


def helper_is_running(pid):
    try:
        status = Path(f"/proc/{pid}/status").read_text()
    except FileNotFoundError:
        return False
    state = next(line for line in status.splitlines() if line.startswith("State:")).split()[1]
    return state != "Z"


def command(*args, timeout=30):
    return subprocess.run(args, text=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=timeout)


class DesktopRelayMountTest(unittest.TestCase):
    def test_live_relay_directory_survives_upstream_and_socket_turnover(self):
        image = command("docker", "image", "inspect", "--format", "{{.Id}}", IMAGE_REF)
        self.assertEqual(
            image.returncode, 0,
            f"required local image {IMAGE_REF!r} unavailable (no pull attempted): {image.stderr}",
        )
        image_id = image.stdout.strip()
        self.assertTrue(image_id.startswith("sha256:") and len(image_id) == 71,
                        f"Docker returned an invalid immutable image ID: {image_id!r}")

        # Keep the bind source below the shared workspace and the AF_UNIX path short.
        test_root = Path(tempfile.mkdtemp(prefix="isoai-ssh-", dir=ROOT)).resolve()
        relay_dir = test_root / "r"
        container_name = "isoai-ssh-regression-" + uuid.uuid4().hex
        container_attempted = False
        agents = []
        try:
            agent_a = TokenAgent(test_root / "a", b"A:")
            agent_b = TokenAgent(test_root / "b", b"B:")
            agents.extend((agent_a, agent_b))
            # An unavailable upstream may make ensure fail, but must not block
            # mounting the stable directory or starting its disposable container.
            relay_dir.mkdir(mode=0o700)
            directory_inode = relay_dir.stat().st_ino
            self.assertLess(len(os.fsencode(relay_dir / "agent.sock")), 104)
            unavailable = command(
                sys.executable, str(HELPER), "ensure", str(relay_dir), str(test_root / "missing"), timeout=10
            )
            self.assertIn("warning", (unavailable.stdout + unavailable.stderr).lower())
            self.assertEqual(stat.S_IMODE(relay_dir.stat().st_mode), 0o700)
            self.assertEqual(relay_dir.stat().st_ino, directory_inode)

            container_attempted = True
            create = command(
                "docker", "run", "-d", "--name", container_name,
                "--user", "1000:1000",
                "--mount", f"type=bind,src={relay_dir},dst=/run/isoai/ssh,readonly",
                "--env", f"SSH_AUTH_SOCK={CONTAINER_SOCK}",
                "--entrypoint", "python3", image_id,
                "-c", "import time; time.sleep(3600)",
                timeout=90,
            )
            self.assertEqual(create.returncode, 0, f"disposable container create failed: {create.stderr}")
            self.assertTrue(create.stdout.strip(), "Docker did not return the test container ID")
            self.assert_mount_contract(container_name, relay_dir)
            self.ensure(relay_dir, agent_a.path)
            self.assertEqual(relay_dir.stat().st_ino, directory_inode)
            self.assertTrue(stat.S_ISSOCK((relay_dir / "agent.sock").stat().st_mode))
            self.assertEqual(stat.S_IMODE((relay_dir / "agent.sock").stat().st_mode), 0o600)
            self.assert_exchange(container_name, b"A:")

            # Refresh only the upstream endpoint while the first container remains running.
            self.ensure(relay_dir, agent_b.path)
            self.assertEqual(relay_dir.stat().st_ino, directory_inode)
            self.assert_exchange(container_name, b"B:")

            stopped = command("docker", "stop", "--time", "1", container_name, timeout=30)
            self.assertEqual(stopped.returncode, 0, f"test container stop failed: {stopped.stderr}")
            pids = helper_processes(relay_dir)
            self.assertEqual(len(pids), 1, f"expected one owned relay process, found {pids}")
            os.kill(pids[0], signal.SIGTERM)
            self.wait_for_helper_exit(pids[0])
            self.assertEqual(relay_dir.stat().st_ino, directory_inode)

            # The stale socket is replaced inside the same directory before restart.
            self.ensure(relay_dir, agent_b.path)
            self.assertEqual(relay_dir.stat().st_ino, directory_inode)
            started = command("docker", "start", container_name, timeout=60)
            self.assertEqual(started.returncode, 0, f"container restart/mount failed: {started.stderr}")
            self.assert_mount_contract(container_name, relay_dir)
            self.assert_exchange(container_name, b"B:")
        finally:
            try:
                if container_attempted:
                    existing = command("docker", "container", "inspect", container_name)
                    if existing.returncode == 0:
                        removed = command("docker", "rm", "-f", container_name, timeout=30)
                        if removed.returncode != 0:
                            raise RuntimeError(f"could not remove disposable container: {removed.stderr}")
            finally:
                try:
                    terminate_helpers(relay_dir)
                except Exception:
                    for agent in agents:
                        agent.close()
                    raise
                else:
                    for agent in agents:
                        agent.close()
                    import shutil
                    shutil.rmtree(test_root)

    def ensure(self, directory, upstream):
        result = command(sys.executable, str(HELPER), "ensure", str(directory), str(upstream), timeout=10)
        self.assertEqual(result.returncode, 0, f"helper ensure failed: {result.stderr}")
        return result

    def assert_mount_contract(self, name, directory):
        template = (
            '{{.Config.User}}{{"\\n"}}'
            '{{range .Config.Env}}{{if eq . "SSH_AUTH_SOCK=/run/isoai/ssh/agent.sock"}}{{.}}{{end}}{{end}}'
            '{{"\\n"}}{{json .Mounts}}'
        )
        result = command("docker", "inspect", "--format", template, name)
        self.assertEqual(result.returncode, 0, f"test container inspect failed: {result.stderr}")
        user, sock_env, mounts_json = result.stdout.splitlines()
        self.assertEqual(user, "1000:1000")
        self.assertEqual(sock_env, f"SSH_AUTH_SOCK={CONTAINER_SOCK}")
        mounts = json.loads(mounts_json)
        self.assertEqual(len(mounts), 1, f"unexpected test container mounts: {mounts}")
        self.assertEqual(mounts[0]["Source"], str(directory))
        self.assertEqual(mounts[0]["Destination"], "/run/isoai/ssh")
        self.assertFalse(mounts[0]["RW"], "relay directory mount must be read-only")

    def assert_exchange(self, name, prefix):
        script = (
            "import os, socket, sys\n"
            "p = bytes.fromhex(sys.argv[1])\n"
            "want = bytes.fromhex(sys.argv[2]) + p\n"
            "assert os.getuid() == 1000\n"
            "s = socket.socket(socket.AF_UNIX)\n"
            "s.settimeout(5)\n"
            f"s.connect({CONTAINER_SOCK!r})\n"
            "s.sendall(p)\n"
             "got = b''\n"
             "while len(got) < len(want):\n"
             "    part = s.recv(4096)\n"
             "    assert part, 'premature EOF from relay'\n"
             "    got += part\n"
            "assert got == want, (got, want)\n"
        )
        result = command(
            "docker", "exec", "--user", "1000:1000", name,
            "python3", "-c", script, PAYLOAD.hex(), prefix.hex(), timeout=20,
        )
        self.assertEqual(result.returncode, 0, f"container relay exchange failed: {result.stderr}")

    def wait_for_helper_exit(self, pid):
        deadline = time.monotonic() + 5
        while helper_is_running(pid) and time.monotonic() < deadline:
            time.sleep(0.05)
        self.assertFalse(helper_is_running(pid), f"owned relay process {pid} did not exit")


if __name__ == "__main__":
    unittest.main(verbosity=2)
