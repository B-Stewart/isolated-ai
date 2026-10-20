#!/usr/bin/env python3
import concurrent.futures
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
import unittest

HELPER = (Path(__file__).resolve().parents[1] / "isoai-ssh-agent.py").resolve()


def stop_owned_helpers(root):
    root = str(Path(root).resolve())
    owned = []
    for entry in Path("/proc").iterdir():
        if not entry.name.isdigit():
            continue
        try:
            args = (entry / "cmdline").read_bytes().decode(errors="replace").split("\0")
        except (FileNotFoundError, PermissionError, ProcessLookupError):
            continue
        if str(HELPER) in args and any(arg == root or arg.startswith(root + os.sep) for arg in args):
            owned.append(int(entry.name))
    for pid in owned:
        try:
            os.kill(pid, signal.SIGTERM)
        except ProcessLookupError:
            pass
    deadline = time.monotonic() + 2
    while owned and time.monotonic() < deadline:
        owned = [pid for pid in owned if Path(f"/proc/{pid}").exists()]
        time.sleep(0.02)
    for pid in owned:
        try:
            os.kill(pid, signal.SIGKILL)
        except ProcessLookupError:
            pass


class EchoAgent(threading.Thread):
    def __init__(self, path, prefix, close_after_request=False):
        super().__init__(daemon=True)
        self.path = str(path)
        self.prefix = prefix
        self.close_after_request = close_after_request
        self.listener = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
        self.listener.bind(self.path)
        self.listener.listen()
        self.listener.settimeout(0.1)
        self.stopping = threading.Event()
        self.start()

    def run(self):
        while not self.stopping.is_set():
            try:
                connection, _ = self.listener.accept()
            except TimeoutError:
                continue
            with connection:
                connection.settimeout(2)
                payload = connection.recv(4096)
                if payload and not self.close_after_request:
                    connection.sendall(self.prefix + payload)

    def close(self):
        self.stopping.set()
        self.join(timeout=1)
        self.listener.close()


class RelayTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix="ia-")
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.directory = self.root / "relay"
        self.addCleanup(stop_owned_helpers, self.directory)

    def ensure(self, upstream, success=True):
        result = subprocess.run(
            [sys.executable, str(HELPER), "ensure", str(self.directory), str(upstream)],
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            timeout=5,
        )
        self.assertEqual(result.returncode == 0, success, result.stderr.decode(errors="replace"))
        return result

    def exchange(self, payload):
        with socket.socket(socket.AF_UNIX, socket.SOCK_STREAM) as client:
            client.settimeout(2)
            client.connect(str(self.directory / "agent.sock"))
            client.sendall(payload)
            response = b""
            while len(response) < len(payload) + 2:
                chunk = client.recv(4096)
                if not chunk:
                    raise AssertionError("relay closed before the full response arrived")
                response += chunk
            return response

    def helper_pid(self):
        target = str(HELPER)
        directory = str(self.directory.resolve())
        for entry in Path("/proc").iterdir():
            if not entry.name.isdigit():
                continue
            try:
                args = (entry / "cmdline").read_bytes().decode(errors="replace").split("\0")
            except (FileNotFoundError, PermissionError, ProcessLookupError):
                continue
            if len(args) >= 3 and args[0] == sys.executable and args[1] == target and \
                    args[2] == "serve" and args[3] == directory:
                return int(entry.name)
        self.fail("owned relay listener process was not found")

    def wait_for_helper_exit(self, pid):
        deadline = time.monotonic() + 2
        while time.monotonic() < deadline:
            try:
                state = Path(f"/proc/{pid}/stat").read_text().rsplit(")", 1)[1].split()[0]
            except FileNotFoundError:
                return True
            if state == "Z":
                return True
            time.sleep(0.02)
        return False

    def test_refreshes_upstream_and_reuses_private_endpoint(self):
        first = EchoAgent(self.root / "a", b"A:")
        second = EchoAgent(self.root / "b", b"B:")
        self.addCleanup(second.close)
        self.addCleanup(first.close)
        payload = b"\x00\xffagent-token\x80"

        self.ensure(first.path)
        inode = self.directory.stat().st_ino
        self.assertEqual(stat.S_IMODE(self.directory.stat().st_mode), 0o700)
        relay = self.directory / "agent.sock"
        self.assertTrue(stat.S_ISSOCK(relay.stat().st_mode))
        self.assertEqual(stat.S_IMODE(relay.stat().st_mode), 0o600)
        self.assertEqual(self.exchange(payload), b"A:" + payload)

        self.ensure(second.path)
        self.assertEqual(self.directory.stat().st_ino, inode)
        self.assertEqual(self.exchange(payload), b"B:" + payload)
        with concurrent.futures.ThreadPoolExecutor(max_workers=3) as pool:
            results = list(pool.map(lambda _: self.ensure(second.path), range(3)))
        self.assertEqual(len(results), 3)
        self.assertEqual(self.directory.stat().st_ino, inode)
        self.assertEqual(self.exchange(payload), b"B:" + payload)

    def test_unavailable_upstream_keeps_listener_with_warning(self):
        missing = str(self.root / "missing")
        result = self.ensure(missing)
        self.assertIn(b"not reachable", result.stderr)
        self.assertTrue(stat.S_ISSOCK((self.directory / "agent.sock").stat().st_mode))

    def test_endpoint_replacement_stops_owned_listener_without_unlinking_replacement(self):
        first = EchoAgent(self.root / "a", b"A:")
        self.addCleanup(first.close)
        self.ensure(first.path)
        pid = self.helper_pid()
        endpoint = self.directory / "agent.sock"
        moved_endpoint = self.root / "moved-agent.sock"
        endpoint.rename(moved_endpoint)
        replacement = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
        self.addCleanup(replacement.close)
        replacement.bind(str(endpoint))
        replacement.listen()
        replacement_identity = (endpoint.stat().st_dev, endpoint.stat().st_ino)
        self.addCleanup(moved_endpoint.unlink, missing_ok=True)
        self.addCleanup(endpoint.unlink, missing_ok=True)

        self.assertTrue(self.wait_for_helper_exit(pid), "relay listener survived endpoint replacement")
        self.assertTrue(stat.S_ISSOCK(endpoint.stat().st_mode))
        self.assertEqual((endpoint.stat().st_dev, endpoint.stat().st_ino), replacement_identity)

    def test_directory_replacement_stops_owned_listener(self):
        first = EchoAgent(self.root / "a", b"A:")
        self.addCleanup(first.close)
        self.ensure(first.path)
        pid = self.helper_pid()
        original_identity = (self.directory.stat().st_dev, self.directory.stat().st_ino)
        moved_directory = self.root / "moved-relay"
        self.directory.rename(moved_directory)
        self.directory.mkdir(mode=0o700)
        self.addCleanup(lambda: os.rename(moved_directory, self.directory)
                        if not self.directory.exists() else None)
        replacement_identity = (self.directory.stat().st_dev, self.directory.stat().st_ino)
        self.assertNotEqual(replacement_identity, original_identity)

        self.assertTrue(self.wait_for_helper_exit(pid), "relay listener survived directory replacement")
        self.assertFalse((self.directory / "agent.sock").exists())

    def test_closed_upstream_fails_exchange_instead_of_spinning(self):
        first = EchoAgent(self.root / "a", b"A:", close_after_request=True)
        self.addCleanup(first.close)
        self.ensure(first.path)
        with self.assertRaisesRegex(AssertionError, "closed before the full response"):
            self.exchange(b"payload")


if __name__ == "__main__":
    unittest.main()
