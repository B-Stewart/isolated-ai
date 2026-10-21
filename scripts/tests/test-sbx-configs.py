#!/usr/bin/env python3
"""Offline structure and safety checks for the experimental SBX configs."""

from pathlib import Path
import json
import re
import unittest

import yaml


ROOT = Path(__file__).resolve().parents[2]
SBX = ROOT / "experiments" / "sbx"
PROFILES = sorted((SBX / "profiles").glob("*.yaml"))
KITS = sorted((SBX / "kits").glob("*/spec.yaml"))
FORBIDDEN = re.compile(r"/var/run/docker\.sock|/run/docker\.sock|docker\.sock|/\.ssh")
DEV_DOMAINS = {
    "github.com", "api.github.com", "raw.githubusercontent.com", "npmjs.org",
    "registry.npmjs.org", "pypi.org", "files.pythonhosted.org",
}


def load_yaml(path):
    return yaml.safe_load(path.read_text())


class SandboxConfigTests(unittest.TestCase):
    def test_all_yaml_parses_and_profiles_resolve_to_matching_kits(self):
        documents = {path: load_yaml(path) for path in [*PROFILES, *KITS]}
        self.assertEqual(len(PROFILES), 3)
        self.assertEqual(len(KITS), 2)
        for profile_path in PROFILES:
            profile = documents[profile_path]
            self.assertEqual(profile["schemaVersion"], "1")
            self.assertNotIn("name", profile)
            self.assertNotIn("description", profile)
            self.assertIn("workspace", profile["args"])
            self.assertEqual(set(profile["args"]), {"workspace"})
            self.assertTrue(profile["args"]["workspace"]["required"])
            self.assertEqual(profile["workspace"], "${{ env.args.workspace }}")
            self.assertEqual(profile["sandboxOptions"]["pullPolicy"], "never")
            self.assertEqual(profile["sandboxOptions"]["skills"], "off")
            self.assertNotIn("resources", profile["sandboxOptions"])
            self.assertNotIn("env", profile)
            self.assertEqual(len(profile["kits"]), 1)
            kit_ref = profile["kits"][0]
            kit_path = (profile_path.parent / kit_ref["source"] / "spec.yaml").resolve()
            self.assertTrue(kit_path.is_file(), str(kit_path))
            kit = documents[kit_path]
            self.assertEqual(profile["agent"], kit["name"])
            self.assertEqual(kit["sandbox"]["image"], "${{ kit.args.image }}")
            expected_image = "local/agentic-gamedev-sbx:experiment" if profile_path.name == "gamedev-claude.yaml" else "local/agentic-base-sbx:experiment"
            self.assertEqual(kit_ref["args"]["image"], expected_image)
            self.assertEqual(kit["args"]["image"]["default"], "local/agentic-base-sbx:experiment")

    def test_custom_kits_are_bounded_and_have_safe_credentials_and_entrypoints(self):
        for path in KITS:
            with self.subTest(kit=path.parent.name):
                kit = load_yaml(path)
                self.assertEqual(kit["schemaVersion"], "2")
                self.assertEqual(kit["kind"], "sandbox")
                self.assertNotIn("extends", kit)
                sandbox = kit["sandbox"]
                self.assertEqual(sandbox["entrypoint"], ["claude"] if kit["name"] == "isoai-claude" else ["opencode"])
                credential, = kit["credentials"]
                self.assertEqual(credential["service"], "anthropic")
                self.assertEqual(credential["apiKey"]["name"], "ANTHROPIC_API_KEY")
                self.assertIs(credential["apiKey"]["proxyManaged"], True)
                injection, = credential["apiKey"]["inject"]
                self.assertEqual(injection, {"domain": "api.anthropic.com", "header": "x-api-key", "format": "%s"})
                allowed = set(kit["permissions"]["network"]["allow"])
                self.assertTrue(DEV_DOMAINS <= allowed)
                self.assertIn("api.anthropic.com", allowed)
                self.assertFalse(any("localhost" in host or "127.0.0.1" in host for host in allowed))
                self.assertNotIn("mounts", sandbox)
                self.assertNotRegex(path.read_text(), r"\$\{(?:args|credentials)\.")

    def test_opencode_kit_seeds_native_config_without_host_mcp_or_auto_update(self):
        kit = load_yaml(SBX / "kits" / "isoai-opencode-omo" / "spec.yaml")
        files = kit["setup"]["files"]
        self.assertEqual([item["path"] for item in files], [
            "/home/agent/.config/opencode/opencode.json",
            "/home/agent/.config/opencode/oh-my-opencode-slim.json",
        ])
        config, omo = (json.loads(item["content"]) for item in files)
        self.assertIn("$schema", config)
        self.assertEqual(config["plugins"], ["file:/usr/local/lib/node_modules/oh-my-opencode-slim"])
        self.assertEqual(config["model"], "anthropic/claude-sonnet-4-6")
        self.assertEqual(config["update"], "disable")
        self.assertNotIn("autoupdate", config)
        self.assertNotIn("mcp", config)
        self.assertNotIn("agent", config)
        self.assertNotIn("experimental", config)
        self.assertIs(omo["autoUpdate"], False)
        self.assertEqual(omo["multiplexer"], {"type": "none"})
        self.assertEqual(omo["disabled_mcps"], ["context7", "gh_grep"])
        expected_agents = {"orchestrator", "oracle", "explorer", "designer", "fixer", "council"}
        self.assertEqual(set(omo["agents"]), expected_agents)
        self.assertTrue(all(agent["model"] == "anthropic/claude-sonnet-4-6" for agent in omo["agents"].values()))

    def test_adapter_has_guest_runtime_wiring_without_host_access(self):
        dockerfile = (SBX / "agentic-sbx.dockerfile").read_text()
        self.assertIn("ARG BASE_IMAGE=braydens/agentic-base:latest", dockerfile)
        self.assertIn("FROM ${BASE_IMAGE}", dockerfile)
        self.assertIn("NOPASSWD: ALL", dockerfile)
        self.assertIn("HTTP_PROXY HTTPS_PROXY NO_PROXY http_proxy https_proxy no_proxy", dockerfile)
        self.assertIn("/etc/sandbox-persistent.sh", dockerfile)
        self.assertIn("BASH_ENV=/etc/sandbox-persistent.sh", dockerfile)
        self.assertIn("USER agent", dockerfile)
        self.assertIn("WORKDIR /workspace", dockerfile)
        self.assertNotRegex(dockerfile, FORBIDDEN)


if __name__ == "__main__":
    unittest.main()
