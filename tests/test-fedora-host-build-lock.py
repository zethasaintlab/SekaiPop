#!/usr/bin/env python3
import json
import re
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
LOCK = ROOT / "tools" / "fedora-hyprland-base-images.lock.json"
BUILDER = ROOT / "tools" / "fedora-hyprland-host-build.sh"
FETCHER = ROOT / "tools" / "fedora-hyprland-source-fetch.sh"


def main() -> None:
    lock = json.loads(LOCK.read_text(encoding="utf-8"))
    builder = BUILDER.read_text(encoding="utf-8")
    fetcher = FETCHER.read_text(encoding="utf-8")
    assert lock["schema"] == "sekaipop-fedora-hyprland-base-image-lock-v1"
    source = lock["source"]
    assert source["hyprland_version"] == "0.57.1"
    assert source["portal_version"] == "1.5.0"
    for release in ("44", "45"):
        target = lock["targets"][release]
        assert re.fullmatch(r"docker\.io/library/fedora@sha256:[0-9a-f]{64}", target["image"])
        assert target["resolved_tag"] == f"docker.io/library/fedora:{release}"
        assert len(target["artifact_sha256"]) == 64
        assert target["artifact_id"] > 0
    for key in ("hyprland_commit", "portal_commit"):
        commit = source[key]
        assert re.fullmatch(r"[0-9a-f]{40}", commit)
        assert commit in builder
        assert commit in fetcher
    assert "BASE_TAG=" not in builder
    assert "podman pull --tls-verify=true --platform linux/amd64 \"$BASE_IMAGE_REF\"" in builder
    assert "podman start --attach" in builder
    assert "--network none" in builder
    print("[PASS] Fedora host build lock pins both base images and matches source-fetch identities")


if __name__ == "__main__":
    main()
