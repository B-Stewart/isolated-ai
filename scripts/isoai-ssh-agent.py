#!/usr/bin/env python3
"""Forward the container's stable agent socket to the current host socket."""

import fcntl
import os
import socket
import stat
import subprocess
import sys
import tempfile
import threading
import time


def warn(message):
    print(f"isoai-ssh-agent: warning: {message}", file=sys.stderr)


def listener_ready(path):
    client = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
    client.settimeout(0.2)
    try:
        client.connect(path)
        return True
    except OSError:
        return False
    finally:
        client.close()


def update_upstream(directory, upstream):
    fd, temporary = tempfile.mkstemp(prefix=".upstream-", dir=directory)
    try:
        os.fchmod(fd, 0o600)
        with os.fdopen(fd, "w", encoding="utf-8") as file:
            file.write(upstream)
        os.replace(temporary, os.path.join(directory, "upstream"))
    finally:
        if os.path.exists(temporary):
            os.unlink(temporary)


def upstream_available(path):
    if not path:
        return False
    client = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
    client.settimeout(0.5)
    try:
        client.connect(path)
        return True
    except OSError:
        return False
    finally:
        client.close()


def ensure(directory, upstream):
    os.makedirs(directory, mode=0o700, exist_ok=True)
    info = os.lstat(directory)
    if not stat.S_ISDIR(info.st_mode) or info.st_uid != os.geteuid():
        raise RuntimeError("relay directory must be a directory owned by this user")
    os.chmod(directory, 0o700)
    directory = os.path.realpath(directory)
    endpoint = os.path.join(directory, "agent.sock")
    if len(endpoint.encode()) >= 104:
        raise RuntimeError("relay socket path is too long")
    if upstream and (not os.path.isabs(upstream) or len(upstream.encode()) >= 104):
        warn("host SSH agent path is invalid; forwarding will be unavailable")
        upstream = ""

    lock_path = os.path.join(directory, ".lock")
    lock_fd = os.open(lock_path, os.O_CREAT | os.O_RDWR, 0o600)
    try:
        fcntl.flock(lock_fd, fcntl.LOCK_EX)
        update_upstream(directory, upstream)
        if listener_ready(endpoint):
            pass
        else:
            if os.path.lexists(endpoint):
                endpoint_info = os.lstat(endpoint)
                if not stat.S_ISSOCK(endpoint_info.st_mode):
                    raise RuntimeError("private relay endpoint exists but is not a socket")
                os.unlink(endpoint)
            process = subprocess.Popen(
                [sys.executable, os.path.abspath(__file__), "serve", directory],
                stdin=subprocess.DEVNULL,
                stdout=subprocess.DEVNULL,
                stderr=subprocess.DEVNULL,
                close_fds=True,
                start_new_session=True,
            )
            deadline = time.monotonic() + 5
            while time.monotonic() < deadline and process.poll() is None:
                if listener_ready(endpoint):
                    break
                time.sleep(0.05)
            else:
                process.terminate()
                process.wait(timeout=2)
                raise RuntimeError("relay listener did not become ready")
            if not listener_ready(endpoint):
                process.terminate()
                process.wait(timeout=2)
                raise RuntimeError("relay listener stopped during readiness check")
    finally:
        os.close(lock_fd)

    if upstream and not upstream_available(upstream):
        warn("relay listener is ready, but the host SSH agent is not reachable")
    elif not upstream:
        warn("relay listener is ready, but no host SSH agent is available")


def pipe(source, destination):
    try:
        while True:
            data = source.recv(65536)
            if not data:
                break
            destination.sendall(data)
    except OSError:
        pass
    finally:
        try:
            destination.shutdown(socket.SHUT_WR)
        except OSError:
            pass


def relay(client, directory):
    remote = None
    try:
        first = client.recv(65536)
        if not first:
            return
        with open(os.path.join(directory, "upstream"), encoding="utf-8") as file:
            upstream = file.read()
        if not upstream:
            return
        remote = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
        remote.connect(upstream)
        remote.sendall(first)
        inbound = threading.Thread(target=pipe, args=(client, remote), daemon=True)
        outbound = threading.Thread(target=pipe, args=(remote, client), daemon=True)
        inbound.start()
        outbound.start()
        inbound.join()
        outbound.join()
    except OSError:
        pass
    finally:
        client.close()
        if remote is not None:
            remote.close()


def path_identity(path):
    info = os.stat(path, follow_symlinks=False)
    return info.st_dev, info.st_ino


def serve(directory):
    directory_identity = path_identity(directory)
    endpoint = os.path.join(directory, "agent.sock")
    server = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
    server.bind(endpoint)
    os.chmod(endpoint, 0o600)
    endpoint_identity = path_identity(endpoint)
    server.listen()
    server.settimeout(1)
    try:
        while True:
            try:
                if path_identity(directory) != directory_identity or \
                        path_identity(endpoint) != endpoint_identity:
                    break
            except OSError:
                break
            try:
                client, _ = server.accept()
            except socket.timeout:
                continue
            threading.Thread(target=relay, args=(client, directory), daemon=True).start()
    finally:
        server.close()


def main():
    if len(sys.argv) >= 3 and sys.argv[1] == "ensure" and len(sys.argv) <= 4:
        ensure(sys.argv[2], sys.argv[3] if len(sys.argv) == 4 else "")
    elif len(sys.argv) == 3 and sys.argv[1] == "serve":
        serve(sys.argv[2])
    else:
        print(f"Usage: {sys.argv[0]} ensure DIRECTORY [UPSTREAM]", file=sys.stderr)
        return 2
    return 0


if __name__ == "__main__":
    try:
        sys.exit(main())
    except (OSError, RuntimeError) as error:
        warn(str(error))
        sys.exit(1)
