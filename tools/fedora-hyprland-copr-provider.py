#!/usr/bin/env python3
"""Install the pinned, community-maintained Fedora Hyprland COPR and register SekaiPop's session."""

import argparse
import configparser
import fcntl
import hashlib
import json
import os
import platform
import re
import stat
import subprocess
import sys
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
LOCK_PATH = ROOT / "tools" / "fedora-hyprland-copr.lock.json"
REPO_DIR = Path("/etc/yum.repos.d")
REPO_FILE = REPO_DIR / "sekaipop-lionheartp-hyprland.repo"
KEY_DIR = Path("/etc/pki/rpm-gpg")
KEY_FILE = KEY_DIR / "RPM-GPG-KEY-sekaipop-lionheartp-hyprland"
SESSION_DIR = Path("/usr/share/wayland-sessions")
SESSION_ENTRY = SESSION_DIR / "sekaipop-hyprland.desktop"
STATE_DIR = Path("/var/lib/sekaipop/fedora-hyprland-copr")
STATE_FILE = STATE_DIR / "ownership.json"
LOCK_FILE = STATE_DIR / ".provider.lock"


def fail(message: str) -> None:
    raise SystemExit(f"Fedora Hyprland COPR provider: {message}")


def run(command: list[str], *, capture: bool = True) -> str:
    try:
        result = subprocess.run(
            command,
            text=True,
            capture_output=capture,
            check=False,
        )
    except OSError as error:
        fail(f"cannot execute {command[0]}: {error}")
    if result.returncode != 0:
        detail = (result.stderr or result.stdout or "").strip() if capture else ""
        fail(f"{' '.join(command)} failed{': ' + detail if detail else ''}")
    return result.stdout.strip() if capture else ""


def require_root() -> None:
    if os.geteuid() != 0:
        fail("invoke this helper through sudo after approving the installation plan")


def invoking_uid() -> int:
    value = os.environ.get("SUDO_UID", "")
    if not value.isdigit() or int(value) == 0:
        fail("SUDO_UID is missing or invalid; invoke through sudo from the normal user account")
    return int(value)


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


def load_lock() -> dict:
    try:
        data = json.loads(LOCK_PATH.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as error:
        fail(f"cannot read the pinned provider lock: {error}")
    provider = data.get("provider", {})
    if (
        data.get("schema_version") != 1
        or provider.get("repo_id") != "sekaipop-copr-lionheartp-hyprland"
        or provider.get("key_fingerprint") != "97E23476C89635135407C7D5E9BA41342C4B2995"
        or provider.get("package_gpgcheck") is not True
        or provider.get("repository_gpgcheck") is not False
        or provider.get("upstream_recommended") is not False
    ):
        fail("provider lock violates the reviewed COPR trust policy")
    return data


def release_data(release: str) -> dict:
    data = load_lock()
    try:
        result = data["releases"][release]
    except KeyError:
        fail(f"Fedora {release} has no pinned COPR package set")
    if result.get("architecture") != "x86_64":
        fail("provider lock architecture does not match the supported host")
    return result


def expected_repo_id() -> str:
    return load_lock()["provider"]["repo_id"]


def expected_repo_content() -> str:
    provider = load_lock()["provider"]
    return (
        f"[{provider['repo_id']}]\n"
        "name=SekaiPop managed Hyprland provider (lionheartp/Hyprland COPR)\n"
        f"baseurl={provider['repo_baseurl']}\n"
        "type=rpm-md\n"
        "skip_if_unavailable=0\n"
        "gpgcheck=1\n"
        f"gpgkey=file://{KEY_FILE}\n"
        "repo_gpgcheck=0\n"
        "enabled=1\n"
        "enabled_metadata=1\n"
        "sslverify=1\n"
    )


def expected_session_content() -> str:
    return (
        "[Desktop Entry]\n"
        "Name=SekaiPop (Hyprland)\n"
        "Comment=SekaiPop managed Hyprland desktop session\n"
        "Exec=/usr/bin/start-hyprland\n"
        "TryExec=/usr/bin/start-hyprland\n"
        "Type=Application\n"
        "DesktopNames=Hyprland\n"
        "Keywords=tiling;wayland;compositor;sekaipop;\n"
    )


def ensure_secure_directory(path: Path, mode: int = 0o755) -> None:
    current = Path("/")
    for component in path.parts[1:]:
        current = current / component
        try:
            metadata = current.lstat()
        except FileNotFoundError:
            try:
                current.mkdir(mode=mode if current == path else 0o755)
            except FileExistsError:
                pass
            metadata = current.lstat()
        except OSError as error:
            fail(f"cannot inspect system directory {current}: {error}")
        if not stat.S_ISDIR(metadata.st_mode) or metadata.st_uid != 0:
            fail(f"system directory is not a real root-owned directory: {current}")
        if stat.S_IMODE(metadata.st_mode) & 0o022:
            fail(f"system directory is group/world writable: {current}")
    if path == STATE_DIR and stat.S_IMODE(path.stat().st_mode) != 0o700:
        os.chmod(path, 0o700)


def fsync_directory(path: Path) -> None:
    descriptor = os.open(path, os.O_RDONLY | getattr(os, "O_DIRECTORY", 0))
    try:
        os.fsync(descriptor)
    finally:
        os.close(descriptor)


def atomic_write_noreplace(path: Path, content: bytes, mode: int) -> None:
    descriptor, temporary_name = tempfile.mkstemp(prefix=f".{path.name}.", dir=path.parent)
    temporary = Path(temporary_name)
    try:
        os.fchmod(descriptor, mode)
        with os.fdopen(descriptor, "wb", closefd=True) as stream:
            stream.write(content)
            stream.flush()
            os.fsync(stream.fileno())
        try:
            os.link(temporary, path, follow_symlinks=False)
        except FileExistsError:
            fail(f"refusing to overwrite existing system file: {path}")
        temporary.unlink()
        fsync_directory(path.parent)
    finally:
        if temporary.exists():
            temporary.unlink()


def atomic_replace(path: Path, content: bytes, mode: int) -> None:
    descriptor, temporary_name = tempfile.mkstemp(prefix=f".{path.name}.", dir=path.parent)
    temporary = Path(temporary_name)
    try:
        os.fchmod(descriptor, mode)
        with os.fdopen(descriptor, "wb", closefd=True) as stream:
            stream.write(content)
            stream.flush()
            os.fsync(stream.fileno())
        os.replace(temporary, path)
        fsync_directory(path.parent)
    finally:
        if temporary.exists():
            temporary.unlink()


def provider_lock():
    ensure_secure_directory(STATE_DIR, 0o700)
    flags = os.O_CREAT | os.O_RDWR | getattr(os, "O_NOFOLLOW", 0)
    try:
        descriptor = os.open(LOCK_FILE, flags, 0o600)
        metadata = os.fstat(descriptor)
    except OSError as error:
        fail(f"cannot open provider transaction lock: {error}")
    if not stat.S_ISREG(metadata.st_mode) or metadata.st_uid != 0 or stat.S_IMODE(metadata.st_mode) != 0o600:
        os.close(descriptor)
        fail("provider lock has unsafe ownership or permissions")
    fcntl.flock(descriptor, fcntl.LOCK_EX)
    return descriptor


def key_fingerprint(path: Path) -> str:
    try:
        metadata = path.lstat()
    except OSError as error:
        fail(f"cannot inspect signing key file: {error}")
    if not stat.S_ISREG(metadata.st_mode) or metadata.st_size > 65536:
        fail("signing key must be a regular file no larger than 64 KiB")
    output = run(["gpg", "--batch", "--no-options", "--with-colons", "--show-keys", str(path)])
    fingerprints = [
        line.split(":")[9].upper()
        for line in output.splitlines()
        if line.startswith("fpr:") and len(line.split(":")) > 9
    ]
    if not fingerprints:
        fail("GPG did not expose a signing-key fingerprint")
    return fingerprints[0]


def validate_invoking_key_file(path: Path, sudo_uid: int) -> bytes:
    try:
        metadata = path.lstat()
        content = path.read_bytes()
    except OSError as error:
        fail(f"cannot read downloaded COPR key: {error}")
    if not stat.S_ISREG(metadata.st_mode) or metadata.st_uid != sudo_uid:
        fail("downloaded COPR key must be a regular file owned by the invoking user")
    if stat.S_IMODE(metadata.st_mode) & 0o077:
        fail("downloaded COPR key file must not be group/world accessible")
    fingerprint = key_fingerprint(path)
    expected = load_lock()["provider"]["key_fingerprint"]
    if fingerprint != expected:
        fail(f"COPR signing-key fingerprint mismatch: expected {expected}, received {fingerprint}")
    return content


def parse_repo_file(path: Path) -> configparser.RawConfigParser:
    parser = configparser.RawConfigParser(interpolation=None, strict=False)
    try:
        with path.open("r", encoding="utf-8") as stream:
            parser.read_file(stream)
    except (OSError, configparser.Error, UnicodeError) as error:
        fail(f"cannot parse existing DNF repository file {path}: {error}")
    return parser


def validate_existing_repo(path: Path, release: str) -> bool:
    parser = parse_repo_file(path)
    repo_id = expected_repo_id()
    if not parser.has_section(repo_id):
        return False
    section = parser[repo_id]
    provider = load_lock()["provider"]
    expected_values = {
        "baseurl": provider["repo_baseurl"],
        "gpgcheck": "1",
        "repo_gpgcheck": "0",
        "enabled": "1",
        "sslverify": "1",
        "skip_if_unavailable": "0",
        "type": "rpm-md",
        "enabled_metadata": "1",
    }
    for key, value in expected_values.items():
        if section.get(key, "").strip() != value:
            fail(f"existing COPR repository has an unexpected {key} value; preserving {path}")
    gpgkey = section.get("gpgkey", "").strip()
    if gpgkey not in {
        f"file://{KEY_FILE}",
        provider["key_url"],
    }:
        fail(f"existing COPR repository has an unexpected signing-key URL; preserving {path}")
    return True


def find_existing_repo(release: str) -> Path | None:
    for path in sorted(REPO_DIR.glob("*.repo")):
        if path.is_symlink() or not path.is_file():
            continue
        metadata = path.lstat()
        if metadata.st_uid != 0 or stat.S_IMODE(metadata.st_mode) & 0o022:
            fail(f"existing DNF repository file has unsafe ownership or permissions: {path}")
        if validate_existing_repo(path, release):
            return path
    return None


def save_state(state: dict) -> None:
    ensure_secure_directory(STATE_DIR, 0o700)
    if STATE_FILE.exists() or STATE_FILE.is_symlink():
        metadata = STATE_FILE.lstat()
        if STATE_FILE.is_symlink() or not stat.S_ISREG(metadata.st_mode):
            fail("provider ownership state is not a regular file; preserving it")
        if metadata.st_uid != 0 or stat.S_IMODE(metadata.st_mode) != 0o600:
            fail("provider ownership state has unsafe ownership or permissions")
    atomic_replace(STATE_FILE, (json.dumps(state, sort_keys=True, indent=2) + "\n").encode(), 0o600)

def load_state() -> dict:
    try:
        metadata = STATE_FILE.lstat()
        if not stat.S_ISREG(metadata.st_mode) or metadata.st_uid != 0 or stat.S_IMODE(metadata.st_mode) != 0o600:
            fail("provider ownership state has unsafe ownership or permissions")
        return json.loads(STATE_FILE.read_text(encoding="utf-8"))
    except FileNotFoundError:
        return {}
    except (OSError, json.JSONDecodeError) as error:
        fail(f"cannot read provider ownership state: {error}")


def install_repo(key_path: Path, release: str, sudo_uid: int) -> None:
    ensure_secure_directory(REPO_DIR)
    ensure_secure_directory(KEY_DIR)
    content = validate_invoking_key_file(key_path, sudo_uid)
    fingerprint = load_lock()["provider"]["key_fingerprint"]
    key_created = False
    if KEY_FILE.exists() or KEY_FILE.is_symlink():
        if KEY_FILE.is_symlink() or not KEY_FILE.is_file():
            fail(f"existing signing-key path is not a regular file: {KEY_FILE}")
        key_metadata = KEY_FILE.lstat()
        if key_metadata.st_uid != 0 or stat.S_IMODE(key_metadata.st_mode) != 0o644:
            fail(f"existing signing-key file has unsafe ownership or permissions: {KEY_FILE}")
        if key_fingerprint(KEY_FILE) != fingerprint:
            fail(f"existing signing-key file has a different fingerprint; preserving {KEY_FILE}")
    else:
        atomic_write_noreplace(KEY_FILE, content, 0o644)
        key_created = True

    run(["rpmkeys", "--import", str(KEY_FILE)])
    existing_repo = find_existing_repo(release)
    repo_created = False
    if existing_repo is None:
        if REPO_FILE.exists() or REPO_FILE.is_symlink():
            fail(f"repository file path is occupied; preserving {REPO_FILE}")
        atomic_write_noreplace(REPO_FILE, expected_repo_content().encode(), 0o644)
        existing_repo = REPO_FILE
        repo_created = True

    state = {
        "schema_version": 1,
        "fedora_release": release,
        "repo_id": expected_repo_id(),
        "repo_file": str(existing_repo),
        "repo_file_created_by_sekaipop": repo_created,
        "key_file": str(KEY_FILE),
        "key_file_created_by_sekaipop": key_created,
        "key_fingerprint": fingerprint,
        "key_sha256": hashlib.sha256(content).hexdigest(),
        "package_gpgcheck": True,
        "repository_gpgcheck": False,
    }
    save_state(state)
    print(f"FEDORA_COPR_REPO_READY\t{expected_repo_id()}\t{fingerprint}")


def installed_package_query(name: str, release: str, *, portal: bool = False) -> str:
    result = release_data(release)["portal" if portal else "hyprland"]
    output = run(["rpm", "-q", "--qf", "%{EPOCHNUM}:%{VERSION}-%{RELEASE}.%{ARCH}", name])
    expected = str(result.get("epoch", 0)) + ":" + result["version"] + "-" + result["release"] + ".x86_64"
    if output != expected:
        fail(f"{name} NEVRA mismatch: expected {expected}, received {output}")
    signature = run(["rpm", "-q", "--qf", "%{SIGPGP:pgpsig}", name])
    match = re.search(r"Key ID ([0-9a-fA-F]{16})", signature)
    expected_key_id = load_lock()["provider"]["key_fingerprint"][-16:].lower()
    if not match or match.group(1).lower() != expected_key_id:
        fail(f"{name} RPM signature does not match the pinned COPR key")
    return output


def require_rpm_owner(path: str, package: str) -> None:
    owner = run(["rpm", "-qf", "--qf", "%{NAME}", path])
    if owner != package:
        fail(f"{path} is not owned by the expected RPM {package}; received {owner}")


def validate_repo_state(release: str) -> None:
    state = load_state()
    if not state or state.get("fedora_release") != release or state.get("repo_id") != expected_repo_id():
        fail("managed COPR repository state is missing or does not match this host")
    repo_path = Path(state.get("repo_file", ""))
    if repo_path.is_symlink() or not repo_path.is_file() or not validate_existing_repo(repo_path, release):
        fail("managed COPR repository configuration is missing or no longer satisfies the pinned policy")
    if state.get("key_fingerprint") != load_lock()["provider"]["key_fingerprint"]:
        fail("managed COPR state has an unexpected signing-key fingerprint")
    if not KEY_FILE.is_file() or KEY_FILE.is_symlink():
        fail("managed COPR signing-key file is missing or has changed")
    key_metadata = KEY_FILE.lstat()
    if key_metadata.st_uid != 0 or stat.S_IMODE(key_metadata.st_mode) != 0o644:
        fail("managed COPR signing-key file has unsafe ownership or permissions")
    if key_fingerprint(KEY_FILE) != state["key_fingerprint"]:
        fail("managed COPR signing-key file has changed")


def validate_installed_provider(release: str) -> None:
    validate_repo_state(release)
    installed_package_query("hyprland", release)
    installed_package_query("xdg-desktop-portal-hyprland", release, portal=True)
    required = (
        ("/usr/bin/Hyprland", "hyprland"),
        ("/usr/bin/start-hyprland", "hyprland"),
        ("/usr/lib/systemd/user/hyprland-session.target", "hyprland"),
        ("/usr/libexec/xdg-desktop-portal-hyprland", "xdg-desktop-portal-hyprland"),
        ("/usr/lib/systemd/user/xdg-desktop-portal-hyprland.service", "xdg-desktop-portal-hyprland"),
        ("/usr/share/dbus-1/services/org.freedesktop.impl.portal.desktop.hyprland.service", "xdg-desktop-portal-hyprland"),
        ("/usr/share/xdg-desktop-portal/portals/hyprland.portal", "xdg-desktop-portal-hyprland"),
    )
    for path, package in required:
        if not Path(path).is_file():
            fail(f"required RPM-owned runtime file is missing: {path}")
        require_rpm_owner(path, package)


def register_session(release: str) -> None:
    ensure_secure_directory(SESSION_DIR)
    validate_installed_provider(release)
    expected = expected_session_content()
    if SESSION_ENTRY.exists() or SESSION_ENTRY.is_symlink():
        if SESSION_ENTRY.is_symlink() or not SESSION_ENTRY.is_file():
            fail(f"refusing to overwrite a non-regular session entry: {SESSION_ENTRY}")
        metadata = SESSION_ENTRY.lstat()
        if metadata.st_uid != 0 or stat.S_IMODE(metadata.st_mode) != 0o644:
            fail("existing SekaiPop session entry has unsafe ownership or permissions")
        if SESSION_ENTRY.read_text(encoding="utf-8") != expected:
            fail("existing SekaiPop session entry differs from the managed COPR session; preserving it")
        print(f"FEDORA_COPR_SESSION_ALREADY_REGISTERED\t{SESSION_ENTRY}")
        return
    atomic_write_noreplace(SESSION_ENTRY, expected.encode(), 0o644)
    print(f"FEDORA_COPR_SESSION_REGISTERED\t{SESSION_ENTRY}")


def unregister_session() -> None:
    ensure_secure_directory(SESSION_DIR)
    if not SESSION_ENTRY.exists() and not SESSION_ENTRY.is_symlink():
        print(f"FEDORA_COPR_SESSION_ALREADY_UNREGISTERED\t{SESSION_ENTRY}")
        return
    if SESSION_ENTRY.is_symlink() or not SESSION_ENTRY.is_file():
        fail(f"refusing to remove a non-regular session entry: {SESSION_ENTRY}")
    metadata = SESSION_ENTRY.lstat()
    if metadata.st_uid != 0 or stat.S_IMODE(metadata.st_mode) != 0o644:
        fail("session entry ownership or permissions changed; preserving it")
    if SESSION_ENTRY.read_text(encoding="utf-8") != expected_session_content():
        fail("session entry content changed; preserving it")
    SESSION_ENTRY.unlink()
    fsync_directory(SESSION_DIR)
    print(f"FEDORA_COPR_SESSION_UNREGISTERED\t{SESSION_ENTRY}")


def remove_repo(release: str) -> None:
    ensure_secure_directory(REPO_DIR)
    for package in ("hyprland", "xdg-desktop-portal-hyprland"):
        result = subprocess.run(["rpm", "-q", package], text=True, capture_output=True, check=False)
        if result.returncode == 0:
            fail(f"{package} is still installed; preserve the COPR repository for package updates")
    state = load_state()
    if not state:
        print("FEDORA_COPR_REPO_NOT_MANAGED")
        return
    if state.get("fedora_release") != release or state.get("repo_id") != expected_repo_id():
        fail("provider ownership state does not match this Fedora host")
    path = Path(state.get("repo_file", ""))
    if state.get("repo_file_created_by_sekaipop"):
        if path.is_symlink() or not path.is_file():
            fail(f"managed COPR repository file changed; preserving {path}")
        metadata = path.lstat()
        if metadata.st_uid != 0 or stat.S_IMODE(metadata.st_mode) != 0o644:
            fail(f"managed COPR repository file has unsafe ownership or permissions; preserving {path}")
        if expected_repo_content() != path.read_text(encoding="utf-8"):
            fail(f"managed COPR repository file content changed; preserving {path}")
        path.unlink()
        fsync_directory(path.parent)
    STATE_FILE.unlink(missing_ok=True)
    fsync_directory(STATE_DIR)
    print("FEDORA_COPR_REPO_REMOVED")


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("action", choices=("install-repo", "remove-repo", "register-session", "unregister-session", "verify"))
    parser.add_argument("--key-file")
    args = parser.parse_args()
    require_root()
    release = host_release()
    sudo_uid = invoking_uid()
    lock_fd = provider_lock()
    try:
        if args.action == "install-repo":
            if not args.key_file:
                fail("install-repo requires --key-file")
            install_repo(Path(args.key_file), release, sudo_uid)
        elif args.action == "remove-repo":
            remove_repo(release)
        elif args.action == "register-session":
            register_session(release)
        elif args.action == "unregister-session":
            unregister_session()
        else:
            validate_installed_provider(release)
            print("FEDORA_COPR_PROVIDER_VERIFIED")
    finally:
        os.close(lock_fd)


if __name__ == "__main__":
    main()
