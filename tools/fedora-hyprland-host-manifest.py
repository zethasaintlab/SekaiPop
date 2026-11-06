#!/usr/bin/env python3
"""Generate a strict, symlink-contained ownership manifest for a Fedora provider build."""

import argparse
import hashlib
import json
import os
import stat
import tempfile
from pathlib import Path


def fail(message: str) -> None:
    raise SystemExit(f"Fedora host manifest: {message}")


def digest_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def inside(path: Path, root: Path) -> bool:
    try:
        path.relative_to(root)
        return True
    except ValueError:
        return False


def inventory(root: Path, runtime_prefix: Path) -> list[dict]:
    entries = []
    pending = [root]
    while pending:
        directory = pending.pop()
        try:
            children = sorted(os.scandir(directory), key=lambda item: item.name)
        except OSError as error:
            fail(f"cannot enumerate {directory}: {error}")
        for child in children:
            path = Path(child.path)
            relative = path.relative_to(root).as_posix()
            if relative == "INSTALL-MANIFEST.json":
                continue
            try:
                metadata = path.lstat()
            except OSError as error:
                fail(f"cannot stat {relative}: {error}")
            mode = stat.S_IMODE(metadata.st_mode)
            if mode & 0o6000:
                fail(f"setuid/setgid mode is forbidden: {relative}")
            if mode & 0o002:
                fail(f"world-writable provider artifact is forbidden: {relative}")
            if stat.S_ISLNK(metadata.st_mode):
                target = os.readlink(path)
                try:
                    if Path(target).is_absolute():
                        target_path = Path(target)
                        if not inside(target_path, runtime_prefix):
                            fail(f"absolute symlink escapes runtime prefix: {relative} -> {target}")
                        resolved = (root / target_path.relative_to(runtime_prefix)).resolve(strict=True)
                    else:
                        resolved = (path.parent / target).resolve(strict=True)
                except (OSError, RuntimeError) as error:
                    fail(f"dangling or cyclic symlink {relative}: {error}")
                if not inside(resolved, root):
                    fail(f"symlink escapes provider prefix: {relative} -> {target}")
                entries.append({"path": relative, "type": "symlink", "mode": mode, "target": target})
            elif stat.S_ISDIR(metadata.st_mode):
                entries.append({"path": relative, "type": "directory", "mode": mode})
                pending.append(path)
            elif stat.S_ISREG(metadata.st_mode):
                if metadata.st_nlink != 1:
                    fail(f"hard-linked regular files are not accepted: {relative}")
                entries.append({
                    "path": relative,
                    "type": "file",
                    "mode": mode,
                    "size": metadata.st_size,
                    "sha256": digest_file(path),
                })
            else:
                fail(f"unsupported special file in provider prefix: {relative}")
    entries.sort(key=lambda item: item["path"])
    return entries


def verify(root: Path, runtime_prefix: Path, fedora_release: str, version: str, commit: str) -> int:
    manifest = root / "INSTALL-MANIFEST.json"
    try:
        metadata = manifest.lstat()
    except OSError as error:
        fail(f"manifest is missing: {error}")
    if not stat.S_ISREG(metadata.st_mode) or stat.S_IMODE(metadata.st_mode) != 0o600:
        fail("manifest must be a regular mode-0600 file")
    try:
        data = json.loads(manifest.read_text(encoding="utf-8"))
    except (OSError, UnicodeError, json.JSONDecodeError) as error:
        fail(f"manifest cannot be parsed: {error}")
    expected = {
        "schema": "sekaipop-fedora-hyprland-install-manifest-v1",
        "provider": "sekaipop-managed-source",
        "fedora_release": fedora_release,
        "architecture": "x86_64",
        "hyprland_version": version,
        "hyprland_commit": commit,
        "prefix": str(runtime_prefix),
    }
    for key, value in expected.items():
        if data.get(key) != value:
            fail(f"manifest field {key!r} does not match the expected value")
    if not isinstance(data.get("files"), list):
        fail("manifest file inventory is missing or malformed")
    actual = inventory(root, runtime_prefix)
    if data["files"] != actual:
        fail("provider files do not match the recorded ownership manifest")
    return len(actual)


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("prefix")
    parser.add_argument("--fedora-release", choices=("44", "45"), required=True)
    parser.add_argument("--hyprland-version", required=True)
    parser.add_argument("--hyprland-commit", required=True)
    parser.add_argument("--runtime-prefix", required=True)
    parser.add_argument("--verify", action="store_true")
    args = parser.parse_args()

    root_arg = Path(args.prefix)
    if root_arg.is_symlink() or not root_arg.is_dir():
        fail("provider prefix must be an existing, non-symlink directory")
    root = root_arg.resolve(strict=True)
    runtime_prefix = Path(args.runtime_prefix)
    if not runtime_prefix.is_absolute() or ".." in runtime_prefix.parts:
        fail("runtime prefix must be a normalized absolute path")
    if not (root / "BUILD-PROVENANCE").is_file():
        fail("BUILD-PROVENANCE is missing")
    if not (root / "bin" / "Hyprland").is_file():
        fail("Hyprland executable is missing")
    if not (root / "libexec" / "xdg-desktop-portal-hyprland").is_file():
        fail("Hyprland portal executable is missing")

    if args.verify:
        count = verify(root, runtime_prefix, args.fedora_release, args.hyprland_version, args.hyprland_commit)
        print(f"FEDORA_HOST_MANIFEST_VERIFIED\\t{count} entries\\t{root}")
        return

    output = root / "INSTALL-MANIFEST.json"
    if output.exists() or output.is_symlink():
        fail("refusing to overwrite an existing INSTALL-MANIFEST.json")
    data = {
        "schema": "sekaipop-fedora-hyprland-install-manifest-v1",
        "provider": "sekaipop-managed-source",
        "fedora_release": args.fedora_release,
        "architecture": "x86_64",
        "hyprland_version": args.hyprland_version,
        "hyprland_commit": args.hyprland_commit,
        "prefix": str(runtime_prefix),
        "files": inventory(root, runtime_prefix),
    }
    payload = json.dumps(data, indent=2, sort_keys=True) + "\n"
    fd, temporary = tempfile.mkstemp(prefix=".INSTALL-MANIFEST.", dir=root)
    try:
        with os.fdopen(fd, "w", encoding="utf-8", newline="\n") as stream:
            stream.write(payload)
            stream.flush()
            os.fsync(stream.fileno())
        os.chmod(temporary, 0o600)
        os.link(temporary, output)
    except FileExistsError:
        fail("manifest path was created concurrently")
    finally:
        try:
            os.unlink(temporary)
        except FileNotFoundError:
            pass
    print(f"FEDORA_HOST_MANIFEST_OK\t{len(data['files'])} entries\t{output}")


if __name__ == "__main__":
    main()
