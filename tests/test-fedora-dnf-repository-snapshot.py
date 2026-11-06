#!/usr/bin/env python3
import json
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SCRIPT = ROOT / "tools" / "fedora-dnf-repository-snapshot.py"


class DnfRepositorySnapshotTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.root = Path(self.temp.name)
        self.config = self.root / "fedora.repo"
        self.config.write_text("[fedora]\nname=Fedora\n", encoding="utf-8")
        self.link = self.root / "fedora-link.repo"
        self.link.symlink_to(self.config)
        self.info = self.root / "repo-info.json"
        self.inventory = self.root / "inventory.json"
        self.hashes = self.root / "hashes.json"

    def tearDown(self):
        self.temp.cleanup()

    def run_snapshot(self, records):
        self.info.write_text(json.dumps(records), encoding="utf-8")
        return subprocess.run(
            [sys.executable, str(SCRIPT), "--repo-info", str(self.info),
             "--inventory", str(self.inventory), "--hashes", str(self.hashes)],
            text=True, capture_output=True, check=False,
        )

    def valid_repository(self, config_path=None):
        return {
            "id": "fedora",
            "is_enabled": True,
            "repo_file_path": str(config_path or self.config),
            "revision": "20261106",
            "timestamp": 1793923200,
        }

    def test_enabled_repositories_and_symlinked_config_are_snapshotted(self):
        result = self.run_snapshot([
            {**self.valid_repository(self.link)},
            {**self.valid_repository(), "id": "updates"},
            {"id": "disabled", "is_enabled": False, "repo_file_path": str(self.config)},
        ])
        self.assertEqual(result.returncode, 0, result.stderr)
        inventory = json.loads(self.inventory.read_text(encoding="utf-8"))
        hashes = json.loads(self.hashes.read_text(encoding="utf-8"))
        self.assertEqual([r["id"] for r in inventory["repositories"]], ["fedora", "updates"])
        self.assertEqual(len(hashes["files"]), 1)
        self.assertEqual(hashes["files"][0]["resolved_path"], str(self.config))
        self.assertEqual(sorted(hashes["files"][0]["repository_ids"]), ["fedora", "updates"])
        self.assertEqual(len(hashes["files"][0]["sha256"]), 64)

    def test_empty_enabled_repository_set_fails_closed(self):
        result = self.run_snapshot([{"id": "disabled", "is_enabled": False}])
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("no enabled repositories", result.stderr)
        self.assertFalse(self.inventory.exists())
        self.assertFalse(self.hashes.exists())

    def test_missing_repository_config_fails_closed(self):
        result = self.run_snapshot([
            self.valid_repository(self.root / "missing.repo")
        ])
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("cannot be resolved", result.stderr)
        self.assertFalse(self.inventory.exists())
        self.assertFalse(self.hashes.exists())

    def test_enabled_repository_without_metadata_identity_fails_closed(self):
        record = self.valid_repository()
        record["revision"] = ""
        record["timestamp"] = 0
        result = self.run_snapshot([record])
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("no metadata revision", result.stderr)
        self.assertFalse(self.inventory.exists())
        self.assertFalse(self.hashes.exists())

    def test_existing_inventory_output_is_never_overwritten(self):
        self.inventory.write_text("preserve inventory", encoding="utf-8")
        result = self.run_snapshot([self.valid_repository()])
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("refusing to overwrite existing output", result.stderr)
        self.assertEqual(self.inventory.read_text(encoding="utf-8"), "preserve inventory")
        self.assertFalse(self.hashes.exists())

    def test_existing_hash_output_is_preserved_and_inventory_is_rolled_back(self):
        self.hashes.write_text("preserve hashes", encoding="utf-8")
        result = self.run_snapshot([self.valid_repository()])
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("refusing to overwrite existing output", result.stderr)
        self.assertEqual(self.hashes.read_text(encoding="utf-8"), "preserve hashes")
        self.assertFalse(self.inventory.exists())
        self.assertEqual(list(self.root.glob(".dnf-provenance.*")), [])


if __name__ == "__main__":
    unittest.main(verbosity=2)
