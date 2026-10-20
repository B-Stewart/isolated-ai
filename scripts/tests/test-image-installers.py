#!/usr/bin/env python3
"""Lightweight wiring and shell-syntax checks for image installer scripts."""

from pathlib import Path
import re
import subprocess
import unittest


ROOT = Path(__file__).resolve().parents[2]
IMAGE_DIR = ROOT / "scripts" / "image"
MOUNT_PATTERN = re.compile(
    r"--mount=type=bind,source=([^,\s]+),target=([^,\s]+),ro"
)


def docker_instructions(text):
    """Join Dockerfile continuation lines into individual instructions."""
    instructions = []
    current = ""
    for line in text.splitlines():
        stripped = line.strip()
        if not current and (not stripped or stripped.startswith("#")):
            continue
        current = f"{current} {stripped}".strip()
        if current.endswith("\\"):
            current = current[:-1].rstrip()
        else:
            instructions.append(current)
            current = ""
    if current:
        instructions.append(current)
    return instructions


class ImageInstallerTests(unittest.TestCase):
    def test_all_image_shell_scripts_parse(self):
        scripts = sorted(IMAGE_DIR.rglob("*.sh"))
        self.assertTrue(scripts, "No image installer scripts found")
        for script in scripts:
            with self.subTest(script=script.relative_to(ROOT)):
                subprocess.run(["bash", "-n", str(script)], check=True)

    def test_two_root_dockerfiles_bind_mount_existing_scripts_read_only(self):
        dockerfiles = sorted(ROOT.glob("*.dockerfile"))
        self.assertEqual(len(dockerfiles), 2, "Expected exactly two public image Dockerfiles")
        mounted_sources = set()

        for dockerfile in dockerfiles:
            instructions = docker_instructions(dockerfile.read_text())
            mounts_seen = 0
            for instruction in instructions:
                if not instruction.startswith("RUN "):
                    continue
                for mount in MOUNT_PATTERN.finditer(instruction):
                    source, target = mount.groups()
                    mounted_sources.add(ROOT / source)
                    mounts_seen += 1
                    with self.subTest(dockerfile=dockerfile.name, source=source):
                        self.assertTrue((ROOT / source).is_file(), f"Missing bind source: {source}")
                        self.assertIn(f"bash {target}", instruction)
            self.assertGreater(mounts_seen, 0, f"{dockerfile.name} has no read-only installer binds")
        self.assertEqual(mounted_sources, set(IMAGE_DIR.rglob("*.sh")),
                         "Every image installer must have a read-only Dockerfile bind")

    def test_base_dockerfile_references_expected_installers(self):
        text = (ROOT / "agentic-base.dockerfile").read_text()
        expected = {
            "install-npm-tools.sh",
            "install-system-deps.sh",
            "install-playwright-deps.sh",
            "link-agent-tools.sh",
            "install-runtimes.sh",
            "install-cli-tools.sh",
            "install-spec-kit.sh",
            "install-agent-browser.sh",
        }
        for name in expected:
            with self.subTest(script=name):
                self.assertIn(f"scripts/image/base/{name}", text)


if __name__ == "__main__":
    unittest.main()
