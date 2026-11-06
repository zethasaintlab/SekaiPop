#!/usr/bin/env python3
import importlib.util
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

    print("[PASS] Fedora host publication uses atomic no-replace rename and exact session-entry content")


if __name__ == "__main__":
    main()
