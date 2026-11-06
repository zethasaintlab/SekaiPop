#!/usr/bin/env python3
import json
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
LOCK = ROOT / "tools" / "fedora-hyprland-copr.lock.json"


class FedoraCoprProviderLockTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.data = json.loads(LOCK.read_text(encoding="utf-8"))

    def test_provider_trust_policy_is_explicit(self):
        provider = self.data["provider"]
        self.assertEqual(provider["id"], "lionheartp/Hyprland")
        self.assertEqual(provider["repo_id"], "sekaipop-copr-lionheartp-hyprland")
        self.assertFalse(provider["official_fedora_repository"])
        self.assertFalse(provider["upstream_recommended"])
        self.assertTrue(provider["package_gpgcheck"])
        self.assertFalse(provider["repository_gpgcheck"])
        self.assertTrue(provider["sslverify"])
        self.assertRegex(provider["key_fingerprint"], r"^[A-F0-9]{40}$")
        self.assertEqual(len(provider["key_fingerprint"]), 40)
        self.assertTrue(provider["key_url"].startswith("https://download.copr.fedorainfracloud.org/"))

    def test_fedora_44_and_45_package_nevras_are_pinned(self):
        releases = self.data["releases"]
        self.assertEqual(set(releases), {"44", "45"})
        for release in ("44", "45"):
            target = releases[release]
            self.assertEqual(target["architecture"], "x86_64")
            hyprland = target["hyprland"]
            portal = target["portal"]
            self.assertEqual(hyprland["version"], "0.57.1")
            self.assertEqual(hyprland["release"], f"1.fc{release}")
            self.assertEqual(hyprland["nevra"], f"hyprland-0.57.1-1.fc{release}.x86_64")
            self.assertEqual(hyprland["build_id"], 11249153)
            self.assertRegex(hyprland["source_commit"], r"^[0-9a-f]{40}$")
            self.assertEqual(portal["epoch"], 1)
            self.assertEqual(portal["version"], "1.5.0")
            self.assertEqual(portal["release"], f"1.fc{release}")
            self.assertEqual(portal["nevra"], f"xdg-desktop-portal-hyprland-1:1.5.0-1.fc{release}.x86_64")
            self.assertEqual(portal["build_id"], 11218611)
            self.assertEqual(portal["source_tag"], "v1.5.0")
            self.assertEqual(portal["sdbus_cpp_version"], "2.3.1")

    def test_key_validity_window_is_ordered(self):
        provider = self.data["provider"]
        self.assertLess(provider["key_created_utc"], provider["key_expires_utc"])
        self.assertTrue(provider["key_expires_utc"].startswith("2030-"))

    def test_repository_urls_are_https_and_release_aware(self):
        provider = self.data["provider"]
        self.assertTrue(provider["repo_baseurl"].startswith("https://"))
        self.assertIn("$releasever", provider["repo_baseurl"])
        self.assertIn("$basearch", provider["repo_baseurl"])
        self.assertIn("lionheartp/Hyprland", provider["repo_baseurl"])


if __name__ == "__main__":
    unittest.main(verbosity=2)
