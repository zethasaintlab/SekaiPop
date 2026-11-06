#!/usr/bin/env python3
import json
import os
import subprocess
import sys
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SCRIPT = ROOT / "tools" / "fedora-hyprland-host-manifest.py"
RUNTIME_PREFIX = Path("/opt/sekaipop/providers/hyprland/releases/0.57.1-test")


def create_prefix(root: Path) -> None:
    (root / "bin").mkdir(parents=True)
    (root / "libexec").mkdir()
    (root / "BUILD-PROVENANCE").write_text("verified provenance\n", encoding="utf-8")
    (root / "bin" / "Hyprland").write_text("binary fixture\n", encoding="utf-8")
    (root / "libexec" / "xdg-desktop-portal-hyprland").write_text("portal fixture\n", encoding="utf-8")


def run(root: Path) -> subprocess.CompletedProcess:
    return subprocess.run(
        [
            sys.executable, str(SCRIPT), str(root),
            "--fedora-release", "44",
            "--hyprland-version", "0.57.1",
            "--hyprland-commit", "a" * 40,
            "--runtime-prefix", str(RUNTIME_PREFIX),
        ],
        text=True,
        capture_output=True,
        check=False,
    )


def main() -> None:
    with tempfile.TemporaryDirectory(prefix="sekaipop-host-manifest-") as temporary:
        base = Path(temporary)
        prefix = base / "prefix"
        create_prefix(prefix)
        (prefix / "lib64").mkdir()
        (prefix / "lib").symlink_to("lib64", target_is_directory=True)
        result = run(prefix)
        assert result.returncode == 0, result.stderr
        manifest = json.loads((prefix / "INSTALL-MANIFEST.json").read_text(encoding="utf-8"))
        assert manifest["prefix"] == str(RUNTIME_PREFIX)
        assert manifest["fedora_release"] == "44"
        assert manifest["hyprland_commit"] == "a" * 40
        files = {entry["path"]: entry for entry in manifest["files"]}
        assert files["bin/Hyprland"]["type"] == "file"
        assert len(files["bin/Hyprland"]["sha256"]) == 64
        assert files["lib"]["type"] == "symlink"
        assert files["lib"]["target"] == "lib64"

        verify_command = [
            sys.executable, str(SCRIPT), str(prefix),
            "--fedora-release", "44",
            "--hyprland-version", "0.57.1",
            "--hyprland-commit", "a" * 40,
            "--runtime-prefix", str(RUNTIME_PREFIX),
            "--verify",
        ]
        verified = subprocess.run(verify_command, text=True, capture_output=True, check=False)
        assert verified.returncode == 0, verified.stderr
        (prefix / "bin" / "Hyprland").write_text("tampered\\n", encoding="utf-8")
        tampered = subprocess.run(verify_command, text=True, capture_output=True, check=False)
        assert tampered.returncode != 0
        assert "do not match" in tampered.stderr

        collision = run(prefix)
        assert collision.returncode != 0
        assert "refusing to overwrite" in collision.stderr

    with tempfile.TemporaryDirectory(prefix="sekaipop-host-manifest-absolute-link-") as temporary:
        prefix = Path(temporary) / "prefix"
        create_prefix(prefix)
        (prefix / "lib64").mkdir()
        (prefix / "libabsolute").symlink_to(RUNTIME_PREFIX / "lib64", target_is_directory=True)
        result = run(prefix)
        assert result.returncode == 0, result.stderr
        manifest = json.loads((prefix / "INSTALL-MANIFEST.json").read_text(encoding="utf-8"))
        absolute_link = next(entry for entry in manifest["files"] if entry["path"] == "libabsolute")
        assert absolute_link["target"] == str(RUNTIME_PREFIX / "lib64")

    with tempfile.TemporaryDirectory(prefix="sekaipop-host-manifest-escape-") as temporary:
        base = Path(temporary)
        prefix = base / "prefix"
        create_prefix(prefix)
        outside = base / "outside"
        outside.write_text("outside\n", encoding="utf-8")
        (prefix / "escape").symlink_to(outside)
        result = run(prefix)
        assert result.returncode != 0
        assert "symlink escapes" in result.stderr

    with tempfile.TemporaryDirectory(prefix="sekaipop-host-manifest-mode-") as temporary:
        prefix = Path(temporary) / "prefix"
        create_prefix(prefix)
        (prefix / "unsafe").write_text("unsafe\n", encoding="utf-8")
        (prefix / "unsafe").chmod(0o666)
        result = run(prefix)
        assert result.returncode != 0
        assert "world-writable" in result.stderr

    print("[PASS] Fedora host manifest hashes files and rejects collisions, escaping symlinks, and unsafe modes")


if __name__ == "__main__":
    main()
