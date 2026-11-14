#!/usr/bin/env python3
"""Network-disabled image smoke tests; build the six YAML kits before running.

Copies their files into disposable Docker images to exercise guest behavior.
This does not validate SBX's composition engine, mounts, or network policy.
"""

import json
import subprocess
import unittest
import uuid


def docker(*args, **kwargs):
    result = subprocess.run(["docker", *args], text=True, capture_output=True,
                            timeout=120, **kwargs)
    if result.returncode:
        raise RuntimeError(f"docker {args[0]} failed ({result.returncode}):\n{result.stdout}{result.stderr}")
    return result.stdout


class SandboxImageTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        suffix = uuid.uuid4().hex[:12]
        cls.images = {name: f"local/isoai-sbx-smoke:{suffix}-{name}" for name in ("plain", "omo")}
        cls.addClassCleanup(cls.remove_images)
        kits = ("opencode", "mcp-context7", "mcp-codegraph", "skills", "browser", "omo")
        for kit in kits:
            docker("image", "inspect", f"local/isoai-sbx-{kit}:scaffold")
        recipe = "FROM local/isoai-sbx-opencode:scaffold\n"
        for kit in kits[1:-1]:
            recipe += f"COPY --from=local/isoai-sbx-{kit}:scaffold / /\n"
        docker("build", "--network", "none", "-t", cls.images["plain"], "-", input=recipe)
        docker("build", "--network", "none", "-t", cls.images["omo"], "-", input=(
            f"FROM {cls.images['plain']}\nCOPY --from=local/isoai-sbx-omo:scaffold / /\n"))

    @classmethod
    def remove_images(cls):
        for image in cls.images.values():
            subprocess.run(["docker", "image", "rm", image], capture_output=True, timeout=30)

    def guest(self, image, script):
        return docker("run", "--rm", "--network", "none", "--entrypoint", "/bin/sh",
                      image, "-ec", script)

    def test_tools_in_all_bash_modes(self):
        for variant, image in self.images.items():
            for mode in ("-c", "-lc", "-ic", "-lic"):
                with self.subTest(profile=variant, mode=mode):
                    self.guest(image, f"""
                        test "$(id -u)" = 1000
                        bash {mode} 'set -eu
                            for tool in opencode node tooling-node tooling-npm codegraph agent-browser; do
                                command -v "$tool"
                            done
                            opencode --version
                        '
                    """)

    def test_opencode_consumes_the_generated_configuration(self):
        for variant, image in self.images.items():
            with self.subTest(profile=variant):
                result = json.loads(self.guest(image, """
                    /opt/isoai/runtime/launch-opencode debug config > /tmp/parsed.json
                    tooling-node -e '
                        const fs = require("node:fs");
                        const read = p => JSON.parse(fs.readFileSync(p, "utf8"));
                        console.log(JSON.stringify({
                            sources: read("/tmp/parsed.json"),
                            generated: read(process.env.HOME + "/.config/opencode/opencode.json"),
                            sidecar: fs.existsSync(process.env.HOME + "/.config/opencode/oh-my-opencode-slim.json"),
                            package: fs.existsSync("/opt/isoai/mixins/omo/vendor/node_modules/oh-my-opencode-slim")
                        }));
                    '
                """))
                document = next(source["info"] for source in result["sources"]
                                if source.get("path", "").endswith("/opencode.json"))
                servers = document["mcp"]["servers"]
                self.assertEqual(set(servers), {"context7", "codegraph"})
                self.assertEqual(servers["codegraph"]["command"], [
                    "/opt/isoai/mixins/codegraph/codegraph", "serve", "--mcp",
                ])
                self.assertEqual(servers, result["generated"]["mcp"]["servers"])
                self.assertEqual(document["skills"], ["/opt/isoai/mixins/skills"])
                self.assertEqual(bool(document["plugins"]), variant == "omo")
                self.assertEqual(result["sidecar"], variant == "omo")
                self.assertEqual(result["package"], variant == "omo")

    def test_project_node_does_not_replace_tooling_node(self):
        self.guest(self.images["plain"], """
            mkdir -p /tmp/project /opt/isoai/mise/installs/node/0.0.0/bin
            printf '%s\n' '#!/bin/sh' 'echo project-node' > /opt/isoai/mise/installs/node/0.0.0/bin/node
            chmod +x /opt/isoai/mise/installs/node/0.0.0/bin/node
            printf '%s\n' '[tools]' 'node = "0.0.0"' > /tmp/project/mise.toml
            cd /tmp/project
            mise trust
            mise reshim
            for mode in -c -lc -ic -lic; do
                bash "$mode" 'set -eu
                    test "$(node --version)" = project-node
                    test "$(tooling-node --version)" = "$(/opt/isoai/tooling/node/bin/node --version)"
                    tooling-npm --version
                    opencode --version
                    codegraph --version
                    agent-browser --version
                '
            done
        """)


if __name__ == "__main__":
    unittest.main(verbosity=2)
