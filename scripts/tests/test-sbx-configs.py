#!/usr/bin/env python3
"""Offline structure and safety checks for the experimental SBX configs."""

from pathlib import Path
import json
import os
import re
import shutil
import subprocess
import tempfile
import unittest

import yaml


ROOT = Path(__file__).resolve().parents[2]
SBX = ROOT / "experiments" / "sbx"
PROFILES = {
    "plain": SBX / "profiles" / "opencode.yaml",
    "omo": SBX / "profiles" / "opencode-omo.yaml",
}
WORKLOADS = SBX / "workloads"
MIXINS = SBX / "mixins"
FORBIDDEN = re.compile(r"/var/run/docker\.sock|/run/docker\.sock|docker\.sock|/\.ssh")
EXPECTED_MIXINS = {
    "mcp-context7", "mcp-codegraph", "skills", "browser",
}


def load_yaml(path):
    return yaml.safe_load(path.read_text())


class SandboxConfigTests(unittest.TestCase):
    def test_profiles_select_v3_scaffold_and_explicit_workspace(self):
        self.assertEqual(set(PROFILES), {"plain", "omo"})
        expected = EXPECTED_MIXINS
        for variant, path in PROFILES.items():
            with self.subTest(profile=path.name):
                profile = load_yaml(path)
                self.assertEqual(profile["schemaVersion"], "1")
                self.assertEqual(set(profile["args"]), {"workspace", "base_image"})
                self.assertIs(profile["args"]["workspace"]["required"], True)
                self.assertIs(profile["args"]["base_image"]["required"], True)
                self.assertEqual(profile["workspace"], "${{ env.args.workspace }}")
                self.assertEqual(profile["sandboxOptions"]["skills"], "off")
                self.assertEqual(profile["sandboxOptions"]["cpus"], 2)
                self.assertEqual(profile["sandboxOptions"]["memory"], "4g")
                sources = {item["source"] for item in profile["kits"]}
                self.assertIn("../workloads/opencode", sources)
                for item in profile["kits"]:
                    if item["source"] != "../mixins/skills":
                        self.assertEqual(item["args"]["base_image"], "${{ env.args.base_image }}")
                selected_mixins = {
                    Path(source).name for source in sources
                    if source.startswith("../mixins/")
                }
                self.assertEqual(selected_mixins, expected | ({"omo"} if variant == "omo" else set()))
                text = path.read_text()
                self.assertNotRegex(text, FORBIDDEN)
                self.assertNotRegex(text, r"(?i)host[-_ ]?(?:mcp|skill)|lifecycle|permission.?bypass")

    def test_v3_workload_and_mixin_descriptors_are_paired_and_resolvable(self):
        descriptor_paths = [*WORKLOADS.glob("*/*.yaml"), *MIXINS.glob("*/*.yaml")]
        self.assertTrue(descriptor_paths)
        for path in descriptor_paths:
            with self.subTest(descriptor=path):
                descriptor = load_yaml(path)
                self.assertEqual(descriptor["schemaVersion"], "3")
                self.assertEqual(descriptor["kind"], "workload" if path.parent.parent == WORKLOADS else "mixin")
                for feature in descriptor.get("provides", []):
                    self.assertRegex(feature, r"^[a-z][a-z0-9-]*@[0-9]+\.[0-9]+\.[0-9]+$")
                self.assertTrue(path.with_suffix(".dockerfile").is_file())
                self.assertEqual(path.read_text().splitlines()[0], "# syntax=docker/sandbox-kit:3")
                text = path.read_text() + "\n" + path.with_suffix(".dockerfile").read_text()
                self.assertNotRegex(text, FORBIDDEN)
                self.assertNotRegex(text, r"(?i)--dangerously-skip-permissions|--yolo")
        descriptor_path = WORKLOADS / "opencode" / "opencode.yaml"
        opencode = load_yaml(descriptor_path)
        self.assertEqual(opencode["schemaVersion"], "3")
        self.assertEqual(opencode["kind"], "workload")
        dockerfile = WORKLOADS / "opencode" / "opencode.dockerfile"
        self.assertTrue(descriptor_path.read_text().splitlines()[0].startswith("# syntax=docker/sandbox-kit:3"))
        self.assertIn("/opt/isoai/runtime/launch-opencode", dockerfile.read_text())
        self.assertIn("com.docker.sandbox/sbx@1", {item["type"] for item in opencode["capabilities"]})
        self.assertIn("api.anthropic.com", json.dumps(opencode))
        self.assertIn("ANTHROPIC_API_KEY", json.dumps(opencode))
        self.assertNotIn("workload", opencode)
        self.assertNotIn("credentials", opencode)
        self.assertTrue(dockerfile.is_file())

    def test_profiles_have_no_legacy_v2_adapters_kits_or_profiles(self):
        for path in SBX.rglob("*.yaml"):
            if "node_modules" not in path.parts:
                with self.subTest(yaml=path.relative_to(SBX)):
                    self.assertNotEqual(str(load_yaml(path).get("schemaVersion")), "2")
        self.assertFalse((SBX / "agentic-sbx.dockerfile").exists())
        legacy_kits = SBX / "kits"
        self.assertFalse(legacy_kits.exists() and any(legacy_kits.iterdir()))
        self.assertFalse((SBX / "profiles" / "base-claude.yaml").exists())
        self.assertFalse((SBX / "profiles" / "gamedev-claude.yaml").exists())

    def test_mixin_fragments_are_valid_unique_and_sandbox_local(self):
        destinations = set()
        fragments = []
        fragment_paths = [*WORKLOADS.glob("*/files/fragments/*.json"), *MIXINS.glob("*/files/fragments/*.json")]
        self.assertTrue(fragment_paths)
        for path in fragment_paths:
            with self.subTest(fragment=path):
                fragment = json.loads(path.read_text())
                fragments.append((path, fragment))
                self.assertNotRegex(path.read_text(), FORBIDDEN)
                # Fragment filenames are the stable assembly identity.
                self.assertNotIn(path.name, {item[0].name for item in fragments[:-1]})
        for kit_dir in [WORKLOADS / "opencode", *MIXINS.glob("*")]:
            for text_file in kit_dir.rglob("*"):
                if text_file.is_file() and text_file.suffix in {".yaml", ".dockerfile"}:
                    for match in re.finditer(r"/opt/isoai/opencode/fragments\.d/([^\s:'\"]+\.json)", text_file.read_text()):
                        self.assertNotIn(match.group(1), destinations)
                        destinations.add(match.group(1))
        self.assertEqual({path.name for path, _ in fragments}, destinations)

    def test_assembler_composes_plain_and_omo_when_node_is_available(self):
        node = shutil.which("node")
        if node is None:
            self.skipTest("node is unavailable; assembler integration needs a Node runtime")
        assembler = SBX / "runtime" / "assemble-opencode.mjs"
        base = SBX / "runtime" / "opencode-base.json"
        for variant, profile_path in PROFILES.items():
            with self.subTest(profile=variant), tempfile.TemporaryDirectory() as temp:
                temp_path = Path(temp)
                fragments_dir = temp_path / "fragments"
                fragments_dir.mkdir()
                profile = load_yaml(profile_path)
                for kit in profile["kits"]:
                    source = (profile_path.parent / kit["source"]).resolve()
                    for fragment in source.glob("files/fragments/*.json"):
                        shutil.copyfile(fragment, fragments_dir / fragment.name)
                home = temp_path / "home"
                env = {
                    **os.environ,
                    "HOME": str(home),
                    "ISOAI_OPENCODE_BASE": str(base),
                    "ISOAI_OPENCODE_FRAGMENTS": str(fragments_dir),
                }
                subprocess.run([node, str(assembler)], check=True, env=env, capture_output=True, text=True)
                config_path = home / ".config" / "opencode" / "opencode.json"
                config = json.loads(config_path.read_text())
                self.assertEqual(config_path.stat().st_mode & 0o777, 0o600)
                servers = config.get("mcp", {}).get("servers", {})
                self.assertEqual(set(servers), {"context7", "codegraph"})
                self.assertTrue(config.get("skills"))
                plugins = config.get("plugins", [])
                has_omo = any("oh-my-opencode-slim" in plugin for plugin in plugins)
                if variant == "plain":
                    self.assertFalse(has_omo)
                else:
                    self.assertTrue(has_omo)


if __name__ == "__main__":
    unittest.main()
