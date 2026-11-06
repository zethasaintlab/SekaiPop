#!/usr/bin/env python3
import importlib.util
import os
import tempfile
from pathlib import Path

SCRIPT = Path(__file__).resolve().parents[1] / "tools" / "fedora-hyprland-host-deploy.py"
SPEC = importlib.util.spec_from_file_location("sekaipop_fedora_host_deploy", SCRIPT)
assert SPEC and SPEC.loader
MODULE = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(MODULE)


def main() -> None:
    release = Path("/opt/sekaipop/providers/hyprland/releases/0.57.1-acc1aa0bfd4b-portal-1.5.0-d1467fea8d18")
    launcher = release / "bin" / "sekaipop-hyprland-session"
    expected_session = (
        "[Desktop Entry]\n"
        "Name=SekaiPop (Hyprland)\n"
        "Comment=SekaiPop managed Hyprland desktop session\n"
        f"Exec={launcher}\n"
        f"TryExec={launcher}\n"
        "Type=Application\n"
        "DesktopNames=Hyprland\n"
        "Keywords=tiling;wayland;compositor;sekaipop;\n"
    )
    assert MODULE.expected_session_entry(release) == expected_session

    with tempfile.TemporaryDirectory(prefix="sekaipop-host-rename-") as temporary:
        root = Path(temporary)
        source = root / "source"
        destination = root / "destination"
        source.mkdir()
        (source / "artifact").write_text("verified\n", encoding="utf-8")
        MODULE.rename_noreplace(source, destination)
        assert not source.exists()
        assert (destination / "artifact").read_text(encoding="utf-8") == "verified\n"

        second_source = root / "second-source"
        second_source.mkdir()
        (second_source / "artifact").write_text("must-not-overwrite\n", encoding="utf-8")
        try:
            MODULE.rename_noreplace(second_source, destination)
        except SystemExit as error:
            assert "refusing to overwrite" in str(error)
        else:
            raise AssertionError("existing destination was overwritten")
        assert (destination / "artifact").read_text(encoding="utf-8") == "verified\n"
        assert second_source.exists()

    with tempfile.TemporaryDirectory(prefix="sekaipop-host-unit-guard-") as temporary:
        root = Path(temporary)
        release = root / "release"
        unit_dir = root / "config" / "systemd" / "user"
        target = release / "lib64" / "systemd" / "user" / "hyprland-session.target"
        release_portal = release / "lib" / "systemd" / "user" / "xdg-desktop-portal-hyprland.service"
        target.parent.mkdir(parents=True)
        release_portal.parent.mkdir(parents=True)
        unit_dir.mkdir(parents=True)
        target.write_text("[Unit]\\n", encoding="utf-8")
        release_portal.write_text("[Service]\\n", encoding="utf-8")
        os.chmod(unit_dir, 0o700)
        managed_link = unit_dir / "hyprland-session.target"
        managed_link.symlink_to(target)
        try:
            MODULE.assert_no_user_unit_links(release, os.getuid(), str(unit_dir))
        except SystemExit as error:
            assert "remove the invoking user's managed systemd unit link" in str(error)
        else:
            raise AssertionError("managed user systemd unit link did not block release removal")
        managed_link.unlink()
        unrelated = unit_dir / "hyprland-session.target"
        unrelated.symlink_to(root / "unrelated.target")
        MODULE.assert_no_user_unit_links(release, os.getuid(), str(unit_dir))
        unrelated.unlink()
        (unit_dir / "hyprland-session.target").write_text("user-owned\\n", encoding="utf-8")
        MODULE.assert_no_user_unit_links(release, os.getuid(), str(unit_dir))

    print("[PASS] Fedora host publication uses atomic no-replace rename and exact session-entry and user-unit removal guards")


if __name__ == "__main__":
    main()
