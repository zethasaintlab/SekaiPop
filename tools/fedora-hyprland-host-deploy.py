#!/usr/bin/env python3
"""Publish or remove one immutable, manifest-verified Fedora Hyprland release."""

import argparse
import ctypes
import errno
import fcntl
import json
import os
import platform
import pwd
import shutil
import stat
import subprocess
import sys
import tempfile
from pathlib import Path

VERSION = "0.57.1"
COMMIT = "acc1aa0bfd4bd575dcb0f76c35ccf12b660a1ab9"
PORTAL_VERSION = "1.5.0"
PORTAL_COMMIT = "d1467fea8d1895cb7835829c2fbb271a0d37760a"
RELEASE_ID = f"{VERSION}-{COMMIT[:12]}-portal-{PORTAL_VERSION}-{PORTAL_COMMIT[:12]}"
RELEASES = Path("/opt/sekaipop/providers/hyprland/releases")
PROVIDER_ROOT = Path("/opt/sekaipop/providers/hyprland")
SESSION_DIR = Path("/usr/share/wayland-sessions")
SESSION_ENTRY = SESSION_DIR / "sekaipop-hyprland.desktop"
MANIFEST_TOOL = Path(__file__).with_name("fedora-hyprland-host-manifest.py")


def fail(message: str) -> None:
    raise SystemExit(f"Fedora Hyprland host deployment: {message}")


def require_root() -> None:
    if os.geteuid() != 0:
        fail("this helper must be invoked through sudo after the user authorizes publication")


def host_release() -> str:
    values = {}
    try:
        for line in Path("/etc/os-release").read_text(encoding="utf-8").splitlines():
            if "=" in line:
                key, value = line.split("=", 1)
                values[key] = value.strip().strip('"')
    except OSError as error:
        fail(f"cannot read /etc/os-release: {error}")
    release = values.get("VERSION_ID", "")
    if values.get("ID") != "fedora" or release not in {"44", "45"}:
        fail("only Fedora 44 and Fedora 45 are supported")
    if platform.machine() != "x86_64":
        fail("only x86_64 is supported")
    return release


def ensure_secure_directory(path: Path) -> None:
    current = Path("/")
    for component in path.parts[1:]:
        current = current / component
        try:
            metadata = current.lstat()
        except FileNotFoundError:
            try:
                current.mkdir(mode=0o755)
            except FileExistsError:
                pass
            metadata = current.lstat()
        except OSError as error:
            fail(f"cannot inspect system directory {current}: {error}")
        if not stat.S_ISDIR(metadata.st_mode):
            fail(f"system path component is not a real directory: {current}")
        if metadata.st_uid != 0:
            fail(f"system path component is not root-owned: {current}")
        if stat.S_IMODE(metadata.st_mode) & 0o022:
            fail(f"system path component is group/world-writable: {current}")


def run_manifest(prefix: Path, release: str, runtime_prefix: Path) -> None:
    command = [
        sys.executable, str(MANIFEST_TOOL), str(prefix),
        "--fedora-release", release,
        "--hyprland-version", VERSION,
        "--hyprland-commit", COMMIT,
        "--portal-version", PORTAL_VERSION,
        "--portal-commit", PORTAL_COMMIT,
        "--runtime-prefix", str(runtime_prefix),
        "--verify",
    ]
    result = subprocess.run(command, text=True, capture_output=True, check=False)
    if result.returncode != 0:
        fail((result.stderr or result.stdout or "manifest verification failed").strip())


def validate_provenance(prefix: Path, release: str) -> None:
    path = prefix / "BUILD-PROVENANCE"
    try:
        content = path.read_text(encoding="utf-8")
    except (OSError, UnicodeError) as error:
        fail(f"cannot read build provenance: {error}")
    required = [
        f"fedora_version={release}",
        "architecture=x86_64",
        "base_image_ref=docker.io/library/fedora@sha256:",
        f"Hyprland\t{COMMIT}",
    ]
    for value in required:
        if value not in content:
            fail(f"build provenance is missing required identity: {value}")
    build_commit_line = next((line for line in content.splitlines() if line.startswith("sekaipop_build_commit=")), "")
    build_commit = build_commit_line.partition("=")[2]
    if len(build_commit) != 40 or any(character not in "0123456789abcdef" for character in build_commit):
        fail("build provenance does not contain a full SekaiPop commit SHA")
    digest_line = next((line for line in content.splitlines() if line.startswith("base_image_ref=")), "")
    digest = digest_line.partition("@sha256:")[2]
    if len(digest) != 64 or any(character not in "0123456789abcdef" for character in digest):
        fail("build provenance does not contain a valid immutable Fedora image digest")


def validate_stage(stage: Path, release: str, sudo_uid: int) -> Path:
    base = Path(f"/var/tmp/sekaipop-fedora-provider-{sudo_uid}")
    try:
        base_meta = base.lstat()
        stage_root = stage.parent
        root_meta = stage_root.lstat()
        stage_meta = stage.lstat()
    except OSError as error:
        fail(f"staging path is missing or inaccessible: {error}")
    if not stat.S_ISDIR(base_meta.st_mode) or base_meta.st_uid != sudo_uid or stat.S_IMODE(base_meta.st_mode) & 0o077:
        fail(f"unsafe provider staging root: {base}")
    if stage_root.parent != base or not stage_root.name.startswith("build."):
        fail("staged provider path is outside the expected transaction directory")
    if not stat.S_ISDIR(root_meta.st_mode) or root_meta.st_uid != sudo_uid or stat.S_IMODE(root_meta.st_mode) & 0o077:
        fail("provider transaction directory must be private and owned by the invoking user")
    if not stat.S_ISDIR(stage_meta.st_mode) or stage_meta.st_uid != sudo_uid:
        fail("provider release staging directory must be owned by the invoking user")
    if stat.S_IMODE(stage_meta.st_mode) & 0o6022:
        fail("provider release staging directory has unsafe special or writable permission bits")
    if stage.name != RELEASE_ID or stage.is_symlink():
        fail("staged release identifier does not match the pinned Hyprland source")
    resolved = stage.resolve(strict=True)
    if resolved != stage:
        fail("staged release path contains symlinked path components")
    run_manifest(stage, release, RELEASES / RELEASE_ID)
    validate_provenance(stage, release)
    return stage


def provider_lock() -> int:
    lock_path = PROVIDER_ROOT / ".provider.lock"
    flags = os.O_CREAT | os.O_RDWR
    if hasattr(os, "O_NOFOLLOW"):
        flags |= os.O_NOFOLLOW
    try:
        descriptor = os.open(lock_path, flags, 0o600)
        metadata = os.fstat(descriptor)
    except OSError as error:
        fail(f"cannot open provider transaction lock: {error}")
    if not stat.S_ISREG(metadata.st_mode) or metadata.st_uid != 0 or stat.S_IMODE(metadata.st_mode) != 0o600:
        os.close(descriptor)
        fail("provider transaction lock has unsafe ownership or permissions")
    fcntl.flock(descriptor, fcntl.LOCK_EX)
    return descriptor


def rename_noreplace(source: Path, destination: Path) -> None:
    libc = ctypes.CDLL(None, use_errno=True)
    function = getattr(libc, "renameat2", None)
    if function is None:
        fail("atomic no-replace publication (renameat2) is unavailable")
    function.argtypes = [ctypes.c_int, ctypes.c_char_p, ctypes.c_int, ctypes.c_char_p, ctypes.c_uint]
    function.restype = ctypes.c_int
    result = function(-100, os.fsencode(source), -100, os.fsencode(destination), 1)
    if result != 0:
        error = ctypes.get_errno()
        if error == errno.EEXIST:
            fail(f"refusing to overwrite existing path: {destination}")
        fail(f"atomic release publication failed: {os.strerror(error)}")


def expected_session_entry(release_path: Path) -> str:
    launcher = release_path / "bin" / "sekaipop-hyprland-session"
    return (
        "[Desktop Entry]\n"
        "Name=SekaiPop (Hyprland)\n"
        "Comment=SekaiPop managed Hyprland desktop session\n"
        f"Exec={launcher}\n"
        f"TryExec={launcher}\n"
        "Type=Application\n"
        "DesktopNames=Hyprland\n"
        "Keywords=tiling;wayland;compositor;sekaipop;\n"
    )


def fsync_directory(path: Path) -> None:
    descriptor = os.open(path, os.O_RDONLY | getattr(os, "O_DIRECTORY", 0))
    try:
        os.fsync(descriptor)
    finally:
        os.close(descriptor)


def validate_published_release(release: str) -> Path:
    release_path = RELEASES / RELEASE_ID
    if release_path.is_symlink() or not release_path.is_dir():
        fail(f"managed release is missing or is not a real directory: {release_path}")
    metadata = release_path.lstat()
    if metadata.st_uid != 0:
        fail("managed release is not root-owned")
    run_manifest(release_path, release, release_path)
    validate_provenance(release_path, release)
    return release_path


def register_session(release: str) -> None:
    ensure_secure_directory(SESSION_DIR)
    lock_fd = provider_lock()
    temporary = None
    try:
        release_path = validate_published_release(release)
        source_entry = release_path / "share" / "wayland-sessions" / "sekaipop-hyprland.desktop"
        launcher = release_path / "bin" / "sekaipop-hyprland-session"
        expected = expected_session_entry(release_path)
        for path in (source_entry, launcher):
            try:
                metadata = path.lstat()
            except OSError as error:
                fail(f"required session artifact is missing: {path}: {error}")
            if not stat.S_ISREG(metadata.st_mode) or metadata.st_uid != 0:
                fail(f"required session artifact is not a root-owned regular file: {path}")
        if stat.S_IMODE(source_entry.stat().st_mode) != 0o644:
            fail("staged session desktop entry must have mode 0644")
        if not os.access(launcher, os.X_OK):
            fail("staged session launcher is not executable")
        if source_entry.read_text(encoding="utf-8") != expected:
            fail("staged session desktop entry does not match the managed release")

        if SESSION_ENTRY.exists() or SESSION_ENTRY.is_symlink():
            if SESSION_ENTRY.is_symlink() or not SESSION_ENTRY.is_file():
                fail(f"refusing to overwrite an existing session entry: {SESSION_ENTRY}")
            metadata = SESSION_ENTRY.lstat()
            if metadata.st_uid == 0 and stat.S_IMODE(metadata.st_mode) == 0o644 and SESSION_ENTRY.read_text(encoding="utf-8") == expected:
                print(f"FEDORA_HYPRLAND_SESSION_ALREADY_REGISTERED\\t{SESSION_ENTRY}")
                return
            fail(f"conflicting session entry preserved: {SESSION_ENTRY}")

        descriptor, temporary_name = tempfile.mkstemp(prefix=".sekaipop-hyprland.", dir=SESSION_DIR)
        temporary = Path(temporary_name)
        try:
            with os.fdopen(descriptor, "w", encoding="utf-8", newline="\n") as stream:
                stream.write(expected)
                stream.flush()
                os.fsync(stream.fileno())
            os.chmod(temporary, 0o644)
            rename_noreplace(temporary, SESSION_ENTRY)
            temporary = None
            fsync_directory(SESSION_DIR)
        except BaseException:
            if temporary is not None and temporary.exists():
                temporary.unlink()
            raise
        print(f"FEDORA_HYPRLAND_SESSION_REGISTERED\\t{SESSION_ENTRY}")
    finally:
        if temporary is not None and temporary.exists():
            temporary.unlink()
        os.close(lock_fd)


def unregister_session(release: str) -> None:
    ensure_secure_directory(SESSION_DIR)
    lock_fd = provider_lock()
    try:
        release_path = validate_published_release(release)
        expected = expected_session_entry(release_path)
        if not SESSION_ENTRY.exists() and not SESSION_ENTRY.is_symlink():
            print(f"FEDORA_HYPRLAND_SESSION_ALREADY_UNREGISTERED\\t{SESSION_ENTRY}")
            return
        if SESSION_ENTRY.is_symlink() or not SESSION_ENTRY.is_file():
            fail(f"refusing to remove a non-regular session entry: {SESSION_ENTRY}")
        metadata = SESSION_ENTRY.lstat()
        if metadata.st_uid != 0 or stat.S_IMODE(metadata.st_mode) != 0o644:
            fail("session entry ownership or permissions changed; preserving it")
        if SESSION_ENTRY.read_text(encoding="utf-8") != expected:
            fail("session entry content changed; preserving it")
        SESSION_ENTRY.unlink()
        fsync_directory(SESSION_DIR)
        print(f"FEDORA_HYPRLAND_SESSION_UNREGISTERED\\t{SESSION_ENTRY}")
    finally:
        os.close(lock_fd)


def publish(stage: Path, release: str, sudo_uid: int) -> None:
    stage = validate_stage(stage, release, sudo_uid)
    ensure_secure_directory(RELEASES)
    lock_fd = provider_lock()
    temporary = None
    try:
        destination = RELEASES / RELEASE_ID
        if destination.exists() or destination.is_symlink():
            if destination.is_symlink() or not destination.is_dir():
                fail(f"existing release path is not a real directory: {destination}")
            run_manifest(destination, release, destination)
            validate_provenance(destination, release)
            print(f"FEDORA_HYPRLAND_RELEASE_ALREADY_PUBLISHED\t{destination}")
            return

        temporary = Path(tempfile.mkdtemp(prefix=f".{RELEASE_ID}.staging-", dir=RELEASES))
        shutil.copytree(stage, temporary, dirs_exist_ok=True, symlinks=True, copy_function=shutil.copy2)
        os.chmod(temporary, 0o755)
        run_manifest(temporary, release, destination)
        validate_provenance(temporary, release)
        rename_noreplace(temporary, destination)
        temporary = None
        fsync_directory(RELEASES)
        print(f"FEDORA_HYPRLAND_RELEASE_PUBLISHED\t{destination}")
    finally:
        if temporary is not None and temporary.exists():
            shutil.rmtree(temporary)
        os.close(lock_fd)


def invoking_user_unit_directory(sudo_uid: int, supplied: str | None) -> Path:
    if supplied:
        path = Path(supplied)
    else:
        try:
            home = Path(pwd.getpwuid(sudo_uid).pw_dir)
        except KeyError:
            fail(f"cannot resolve the invoking user's home directory for UID {sudo_uid}")
        path = home / ".config" / "systemd" / "user"
    if not path.is_absolute():
        fail("user systemd unit directory must be an absolute path")
    if path.exists() or path.is_symlink():
        metadata = path.lstat()
        if path.is_symlink() or not stat.S_ISDIR(metadata.st_mode):
            fail(f"user systemd unit directory is not a real directory: {path}")
        if metadata.st_uid != sudo_uid:
            fail(f"user systemd unit directory is not owned by invoking UID {sudo_uid}: {path}")
        if stat.S_IMODE(metadata.st_mode) & 0o022:
            fail(f"user systemd unit directory is group/world writable: {path}")
    return path


def assert_no_user_unit_links(release_path: Path, sudo_uid: int, supplied_unit_dir: str | None) -> None:
    unit_dir = invoking_user_unit_directory(sudo_uid, supplied_unit_dir)
    if not unit_dir.is_dir():
        return
    expected_sources = (
        release_path / "lib64" / "systemd" / "user" / "hyprland-session.target",
        release_path / "lib" / "systemd" / "user" / "xdg-desktop-portal-hyprland.service",
    )
    for name, source in zip(
        ("hyprland-session.target", "xdg-desktop-portal-hyprland.service"),
        expected_sources,
    ):
        destination = unit_dir / name
        if not destination.is_symlink():
            continue
        try:
            target = destination.resolve(strict=False)
            expected = source.resolve(strict=False)
        except OSError as error:
            fail(f"cannot safely inspect user systemd unit link {destination}: {error}")
        if target == expected:
            fail(f"remove the invoking user's managed systemd unit link before removing this release: {destination}")


def remove(release: str, sudo_uid: int, user_unit_dir: str | None) -> None:
    ensure_secure_directory(RELEASES)
    lock_fd = provider_lock()
    try:
        destination = RELEASES / RELEASE_ID
        if SESSION_ENTRY.exists() or SESSION_ENTRY.is_symlink():
            fail("unregister the SekaiPop display-manager session before removing its release")
        if destination.is_symlink() or not destination.is_dir():
            fail(f"managed release is missing or is not a real directory: {destination}")
        assert_no_user_unit_links(destination, sudo_uid, user_unit_dir)
        metadata = destination.lstat()
        if metadata.st_uid != 0:
            fail("managed release is not root-owned")
        run_manifest(destination, release, destination)
        validate_provenance(destination, release)
        shutil.rmtree(destination)
        fsync_directory(RELEASES)
        print(f"FEDORA_HYPRLAND_RELEASE_REMOVED\t{destination}")
    finally:
        os.close(lock_fd)


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("action", choices=("publish", "register-session", "unregister-session", "remove"))
    parser.add_argument("--stage")
    parser.add_argument("--user-unit-dir")
    args = parser.parse_args()
    require_root()
    release = host_release()
    sudo_uid_text = os.environ.get("SUDO_UID")
    if not sudo_uid_text or not sudo_uid_text.isdigit() or int(sudo_uid_text) == 0:
        fail("SUDO_UID is missing or invalid; invoke this helper through sudo from the normal user account")
    sudo_uid = int(sudo_uid_text)
    ensure_secure_directory(PROVIDER_ROOT)
    if args.action == "publish":
        if not args.stage:
            fail("publish requires --stage")
        publish(Path(args.stage), release, sudo_uid)
    elif args.action == "register-session":
        register_session(release)
    elif args.action == "unregister-session":
        unregister_session(release)
    else:
        remove(release, sudo_uid, args.user_unit_dir)


if __name__ == "__main__":
    main()
