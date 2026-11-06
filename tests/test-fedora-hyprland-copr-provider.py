#!/usr/bin/env python3
import importlib.util
import tempfile
import unittest
from pathlib import Path
from types import SimpleNamespace
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[1]
MODULE_PATH = ROOT / "tools" / "fedora-hyprland-copr-provider.py"
SPEC = importlib.util.spec_from_file_location("fedora_hyprland_copr_provider", MODULE_PATH)
MODULE = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(MODULE)


class FedoraCoprProviderTests(unittest.TestCase):
    def test_repo_content_is_pinned_and_fail_closed(self):
        content = MODULE.expected_repo_content()
        self.assertIn("[sekaipop-copr-lionheartp-hyprland]", content)
        self.assertIn("gpgcheck=1", content)
        self.assertIn("repo_gpgcheck=0", content)
        self.assertIn("skip_if_unavailable=0", content)
        self.assertIn("sslverify=1", content)
        self.assertIn(f"gpgkey=file://{MODULE.KEY_FILE}", content)

    def test_session_entry_uses_packaged_launcher_without_changing_default(self):
        content = MODULE.expected_session_content()
        self.assertIn("Name=SekaiPop (Hyprland)", content)
        self.assertIn("Exec=/usr/bin/start-hyprland", content)
        self.assertIn("TryExec=/usr/bin/start-hyprland", content)
        self.assertNotIn("X-Session", content)

    def test_key_fingerprint_parser_returns_full_primary_fingerprint(self):
        fingerprint = MODULE.load_lock()["provider"]["key_fingerprint"]
        output = f"pub:::::::::\nfpr:::::::::{fingerprint}:\nuid:::::::::lionheartp_Hyprland:\n"
        result = SimpleNamespace(returncode=0, stdout=output, stderr="")
        with tempfile.TemporaryDirectory(prefix="sekaipop-copr-key-") as temporary:
            key_file = Path(temporary) / "key.gpg"
            key_file.write_bytes(b"mock OpenPGP public key")
            with patch.object(MODULE.subprocess, "run", return_value=result):
                self.assertEqual(MODULE.key_fingerprint(key_file), fingerprint)

    def test_key_fingerprint_parser_rejects_missing_fingerprint(self):
        result = SimpleNamespace(returncode=0, stdout="pub:::::::::\nuid:::::::::no fingerprint:\n", stderr="")
        with tempfile.TemporaryDirectory(prefix="sekaipop-copr-key-") as temporary:
            key_file = Path(temporary) / "key.gpg"
            key_file.write_bytes(b"mock OpenPGP public key")
            with patch.object(MODULE.subprocess, "run", return_value=result):
                with self.assertRaisesRegex(SystemExit, "fingerprint"):
                    MODULE.key_fingerprint(key_file)

    def test_repo_file_accepts_exact_managed_policy(self):
        with tempfile.TemporaryDirectory(prefix="sekaipop-copr-repo-") as temporary:
            path = Path(temporary) / "provider.repo"
            path.write_text(MODULE.expected_repo_content(), encoding="utf-8")
            self.assertTrue(MODULE.validate_existing_repo(path, "44"))

    def test_repo_file_rejects_disabled_or_unverified_policy(self):
        with tempfile.TemporaryDirectory(prefix="sekaipop-copr-repo-") as temporary:
            path = Path(temporary) / "provider.repo"
            content = MODULE.expected_repo_content().replace("gpgcheck=1", "gpgcheck=0")
            path.write_text(content, encoding="utf-8")
            with self.assertRaises(SystemExit):
                MODULE.validate_existing_repo(path, "44")

    def test_atomic_write_never_overwrites_existing_file(self):
        with tempfile.TemporaryDirectory(prefix="sekaipop-copr-atomic-") as temporary:
            path = Path(temporary) / "repo.conf"
            MODULE.atomic_write_noreplace(path, b"trusted=1\n", 0o644)
            self.assertEqual(path.read_bytes(), b"trusted=1\n")
            with self.assertRaises(SystemExit):
                MODULE.atomic_write_noreplace(path, b"trusted=0\n", 0o644)
            self.assertEqual(path.read_bytes(), b"trusted=1\n")

    def test_installed_package_requires_exact_nevra_and_pinned_signature(self):
        expected_key_id = MODULE.load_lock()["provider"]["key_fingerprint"][-16:].lower()
        with patch.object(
            MODULE,
            "run",
            side_effect=[
                "0:0.57.1-1.fc44.x86_64",
                f"RSA/SHA256, Tue 03 Nov 2026, Key ID {expected_key_id}",
            ],
        ):
            self.assertEqual(
                MODULE.installed_package_query("hyprland", "44"),
                "0:0.57.1-1.fc44.x86_64",
            )

    def test_installed_package_rejects_wrong_signing_key(self):
        with patch.object(
            MODULE,
            "run",
            side_effect=[
                "0:0.57.1-1.fc44.x86_64",
                "RSA/SHA256, Tue 03 Nov 2026, Key ID 0000000000000000",
            ],
        ):
            with self.assertRaises(SystemExit):
                MODULE.installed_package_query("hyprland", "44")


if __name__ == "__main__":
    unittest.main(verbosity=2)
