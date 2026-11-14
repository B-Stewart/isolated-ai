#!/usr/bin/env python3
"""Lightweight wiring and shell-syntax checks for image installer scripts."""

from pathlib import Path
import os
import re
import subprocess
import tempfile
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
    def test_opencode_quota_uses_bounded_npm_selector_and_owned_links(self):
        npm_tools = (IMAGE_DIR / "base" / "install-npm-tools.sh").read_text()
        links = (IMAGE_DIR / "base" / "link-agent-tools.sh").read_text()

        self.assertLess(
            npm_tools.index("npm install -g oh-my-opencode-slim@3"),
            npm_tools.index("npm install -g @slkiser/opencode-quota@6"),
        )
        self.assertIn("npm install -g @slkiser/opencode-quota@6", npm_tools)
        self.assertIn(
            "ln -sf ../lib/node_modules/@slkiser/opencode-quota/dist/bin/opencode-quota.js /usr/local/bin/opencode-quota",
            links,
        )
        self.assertIn(
            "ln -sf /usr/local/bin/opencode-quota /home/agent/.local/bin/opencode-quota",
            links,
        )
        ownership = links.split("chown -h 1000:1000 \\\n", 1)[1]
        self.assertIn("/home/agent/.local/bin/opencode-quota", ownership)

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
            "link-agent-tools.sh",
            "install-runtimes.sh",
            "install-cli-tools.sh",
            "install-spec-kit.sh",
            "install-agent-browser.sh",
        }
        for name in expected:
            with self.subTest(script=name):
                self.assertIn(f"scripts/image/base/{name}", text)

    def test_base_runtime_and_cli_installer_interfaces(self):
        dockerfile = (ROOT / "agentic-base.dockerfile").read_text()
        instructions = docker_instructions(dockerfile)

        for name in ("UV_VERSION", "DOTNET_VERSION", "BUN_VERSION", "RTK_VERSION"):
            with self.subTest(argument=name):
                self.assertNotRegex(dockerfile, rf"(?m)^\s*ARG\s+{name}(?:=|\s|$)")
        self.assertRegex(dockerfile, r"(?m)^\s*ARG\s+DOCKER_GID=999$")

        runtime_run = next(i for i in instructions if "install-runtimes.sh" in i)
        cli_run = next(i for i in instructions if "install-cli-tools.sh" in i)
        self.assertTrue(runtime_run.endswith("bash /tmp/install-runtimes.sh"))
        self.assertTrue(cli_run.endswith('bash /tmp/install-cli-tools.sh "${DOCKER_GID}"'))

    def test_runtime_and_rtk_versions_use_bounded_git_tag_selectors(self):
        runtimes = (IMAGE_DIR / "base" / "install-runtimes.sh").read_text()
        cli_tools = (IMAGE_DIR / "base" / "install-cli-tools.sh").read_text()
        for script, text in (("runtimes", runtimes), ("cli-tools", cli_tools)):
            with self.subTest(script=script):
                self.assertIn("git ls-remote", text)
                self.assertIn("sort -V", text)
        self.assertIn('dotnet-sdk-10.0', runtimes)

        # Run the scripts' actual command-substitution pipelines with a fake git
        # that returns synthetic refs; no installer or network call is run.
        cases = (
            (runtimes, "uv_version", "0.10.0"),
            (runtimes, "bun_version", "bun-v1.10.0"),
            (cli_tools, "rtk_version", "v1.10.0"),
        )
        with tempfile.TemporaryDirectory() as directory:
            stub_dir = Path(directory)
            git_stub = stub_dir / "git"
            git_stub.write_text(
                "#!/bin/sh\n"
                "case \"$*\" in\n"
                "  *astral-sh/uv*) tags='0.9.0 0.10.0 0.10.0-rc.1 1.0.0' ;;\n"
                "  *oven-sh/bun*) tags='bun-v1.9.0 bun-v1.10.0 bun-v1.10.0-rc.1 bun-v2.0.0' ;;\n"
                "  *rtk-ai/rtk*) tags='v1.9.0 v1.10.0 v1.10.0-rc.1 v2.0.0' ;;\n"
                "  *) exit 2 ;;\n"
                "esac\n"
                "[ \"${GIT_STUB_MODE:-}\" != network-error ] || exit 1\n"
                "[ \"${GIT_STUB_MODE:-}\" != empty-tags ] || tags=''\n"
                "for tag in $tags; do printf 'deadbeef\\trefs/tags/%s\\n' \"$tag\"; done\n"
            )
            git_stub.chmod(0o755)
            env = {**os.environ, "PATH": f"{stub_dir}:{os.environ['PATH']}"}
            for script, variable, expected in cases:
                with self.subTest(variable=variable):
                    match = re.search(
                        rf"(?ms)^{variable}=\$\(\s*(.*?)\s*\n\)", script
                    )
                    self.assertIsNotNone(match, f"Missing {variable} selector pipeline")
                    assignment = f"{variable}=$({match.group(1)})"
                    result = subprocess.run(
                        ["bash", "-c", f"set -euo pipefail; {assignment}; printf '%s' \"${variable}\""],
                        check=True, capture_output=True, text=True, env=env,
                    )
                    self.assertEqual(result.stdout, expected)

                    for mode in ("empty-tags", "network-error"):
                        with self.subTest(variable=variable, failure=mode):
                            failure_env = {**env, "GIT_STUB_MODE": mode}
                            failed = subprocess.run(
                                ["bash", "-c", f"set -euo pipefail; {assignment}"],
                                capture_output=True, text=True, env=failure_env,
                            )
                            self.assertNotEqual(failed.returncode, 0)

    def test_spec_kit_uses_script_owned_major_bounded_pypi_selector(self):
        dockerfile = (ROOT / "agentic-base.dockerfile").read_text()
        installer = (IMAGE_DIR / "base" / "install-spec-kit.sh").read_text()

        self.assertNotIn("SPEC_KIT_TAG", dockerfile)
        spec_kit_run = next(
            instruction
            for instruction in docker_instructions(dockerfile)
            if "install-spec-kit.sh" in instruction
        )
        self.assertTrue(spec_kit_run.endswith("bash /tmp/install-spec-kit.sh"))
        self.assertIn("uv tool install 'specify-cli>=1,<2'", installer)

    def test_playwright_cli_and_hooks_removed_agent_browser_provisioning_remains(self):
        base = (ROOT / "agentic-base.dockerfile").read_text()
        npm_tools = (IMAGE_DIR / "base" / "install-npm-tools.sh").read_text()
        links = (IMAGE_DIR / "base" / "link-agent-tools.sh").read_text()
        isoai = (ROOT / "scripts" / "isoai").read_text()
        agent_browser = (IMAGE_DIR / "base" / "install-agent-browser.sh").read_text()

        self.assertIn("npm install -g agent-browser@0", npm_tools)
        self.assertIn("/usr/local/bin/agent-browser", links)
        self.assertIn("/home/agent/.local/bin/agent-browser", links)
        self.assertIn("install-agent-browser.sh", base)
        self.assertIn("agent-browser install --with-deps", agent_browser)
        self.assertFalse((IMAGE_DIR / "base" / "install-playwright-deps.sh").exists())
        self.assertNotIn("@playwright/cli", npm_tools)
        self.assertNotIn("playwright-cli", links)
        self.assertNotIn("PLAYWRIGHT_SKIP_BROWSER_GC", base)

        for text in (base, agent_browser, npm_tools, links, isoai):
            with self.subTest(text=text[:40]):
                self.assertNotIn("isolated-pw-browsers", text)
                self.assertNotIn("ms-playwright", text)
        self.assertNotIn("playwright", isoai.lower())

        for path in (
            ROOT / ".devcontainer" / "devcontainer.json",
            ROOT / ".devcontainer" / "devcontainer.firewall.jsonc",
            ROOT / ".devcontainer" / "devcontainer.gd.jsonc",
        ):
            text = path.read_text().lower()
            with self.subTest(config=path.name):
                self.assertNotIn("playwright", text)
                self.assertNotIn("isolated-pw-browsers", text)


if __name__ == "__main__":
    unittest.main()
