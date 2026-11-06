#!/usr/bin/env python3
"""Create a strict, symlink-aware DNF5 repository provenance snapshot."""

import argparse
import hashlib
import json
import os
import stat
import tempfile


def fail(message):
    raise SystemExit(f"DNF repository provenance: {message}")


def sha256_file(path):
    digest = hashlib.sha256()
    with open(path, "rb") as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def atomic_create(path, content):
    parent = os.path.dirname(os.path.abspath(path))
    if not os.path.isdir(parent) or os.path.islink(parent):
        fail(f"output parent is missing or symlinked: {parent}")
    if os.path.lexists(path):
        fail(f"refusing to overwrite existing output: {path}")
    fd, temporary = tempfile.mkstemp(prefix=".dnf-provenance.", dir=parent)
    try:
        with os.fdopen(fd, "w", encoding="utf-8", newline="\n") as stream:
            stream.write(content)
            stream.flush()
            os.fsync(stream.fileno())
        os.link(temporary, path)
    except FileExistsError:
        fail(f"refusing concurrent output collision: {path}")
    finally:
        try:
            os.unlink(temporary)
        except FileNotFoundError:
            pass


OFFICIAL_REPO_CONFIG_ROOTS = ("/etc/yum.repos.d/", "/usr/share/dnf5/repos.d/")


def validate_official_fedora_repositories(enabled, release):
    allowed_ids = {"fedora", "updates", "fedora-cisco-openh264"}
    required_ids = {"fedora", "updates"}
    ids = {item.get("id") for item in enabled}
    if not required_ids.issubset(ids) or not ids.issubset(allowed_ids):
        fail(f"unexpected enabled Fedora repository set: {sorted(str(item) for item in ids)}")

    key_name = f"RPM-GPG-KEY-fedora-{release}-x86_64"
    key_hashes = {}
    for repo in enabled:
        repo_id = repo.get("id")
        if repo.get("pkg_gpgcheck") is not True:
            fail(f"package signature verification is not enabled for {repo_id}")
        expected_repo = {
            "fedora": f"fedora-{release}",
            "updates": f"updates-released-f{release}",
            "fedora-cisco-openh264": f"fedora-cisco-openh264-{release}",
        }[repo_id]
        metalink = repo.get("metalink")
        if metalink != f"https://mirrors.fedoraproject.org/metalink?repo={expected_repo}&arch=x86_64":
            fail(f"repository {repo_id} does not use the expected official Fedora metalink")
        if repo.get("base_url") not in ([], None) or repo.get("mirrorlist") not in ("", None):
            fail(f"repository {repo_id} contains an unexpected baseurl or mirrorlist")
        config_path = repo.get("repo_file_path", "")
        resolved_config = os.path.realpath(config_path)
        if not any(resolved_config.startswith(root) for root in OFFICIAL_REPO_CONFIG_ROOTS):
            fail(f"repository {repo_id} configuration is outside Fedora repository directories")
        keys = repo.get("gpg_key")
        if not isinstance(keys, list) or not keys:
            fail(f"repository {repo_id} has no Fedora signing key")
        for key_uri in keys:
            if not isinstance(key_uri, str) or not key_uri.startswith("file://"):
                fail(f"repository {repo_id} uses a non-local or untrusted signing key")
            configured_key_path = os.path.abspath(key_uri[7:])
            if os.path.basename(configured_key_path) != key_name:
                fail(f"repository {repo_id} uses an unexpected Fedora signing key: {configured_key_path}")
            key_path = os.path.realpath(configured_key_path)
            if not (
                key_path.startswith("/etc/pki/rpm-gpg/")
                or key_path.startswith("/usr/share/pki/rpm-gpg/")
            ):
                fail(f"repository {repo_id} signing key resolves outside Fedora key directories: {key_path}")
            try:
                metadata = os.stat(key_path)
            except OSError as error:
                fail(f"Fedora signing key for {repo_id} cannot be read: {error}")
            if not stat.S_ISREG(metadata.st_mode):
                fail(f"Fedora signing key for {repo_id} is not a regular file")
            key_hashes[key_path] = sha256_file(key_path)
    return [
        {"resolved_path": path, "sha256": digest}
        for path, digest in sorted(key_hashes.items())
    ]


def snapshot(repo_info_path, inventory_path, hashes_path, fedora_release=None):
    with open(repo_info_path, "r", encoding="utf-8") as stream:
        records = json.load(stream)
    if not isinstance(records, list):
        fail("dnf5 repo info JSON must be an array")

    enabled = [item for item in records if isinstance(item, dict) and item.get("is_enabled") is True]
    if not enabled:
        fail("DNF5 reported no enabled repositories")

    enabled.sort(key=lambda item: str(item.get("id", "")))
    hashes = []
    seen = set()
    for repo in enabled:
        repo_id = repo.get("id")
        config_path = repo.get("repo_file_path")
        if not isinstance(repo_id, str) or not repo_id.strip():
            fail("enabled repository has no valid id")
        if not isinstance(config_path, str) or not config_path.strip():
            fail(f"enabled repository {repo_id} has no repo_file_path")
        revision = repo.get("revision")
        timestamp = repo.get("timestamp")
        if not isinstance(revision, (str, int)) or not str(revision).strip():
            fail(f"enabled repository {repo_id} has no metadata revision")
        if isinstance(timestamp, bool) or not isinstance(timestamp, int) or timestamp <= 0:
            fail(f"enabled repository {repo_id} has no valid metadata timestamp")
        resolved = os.path.realpath(config_path)
        try:
            metadata = os.stat(resolved)
        except OSError as error:
            fail(f"repository config for {repo_id} cannot be resolved: {error}")
        if not stat.S_ISREG(metadata.st_mode):
            fail(f"repository config for {repo_id} is not a regular file: {resolved}")
        if resolved not in seen:
            seen.add(resolved)
            hashes.append({
                "configured_path": config_path,
                "resolved_path": resolved,
                "sha256": sha256_file(resolved),
                "repository_ids": [repo_id],
            })
        else:
            for item in hashes:
                if item["resolved_path"] == resolved:
                    item["repository_ids"].append(repo_id)
                    break

    gpg_keys = []
    if fedora_release is not None:
        if fedora_release not in {"44", "45"}:
            fail("strict official Fedora repository validation supports only releases 44 and 45")
        gpg_keys = validate_official_fedora_repositories(enabled, fedora_release)

    inventory = {
        "schema": "sekaipop-dnf5-repository-inventory-v1",
        "repositories": enabled,
    }
    hash_inventory = {
        "schema": "sekaipop-dnf-repository-config-hashes-v1",
        "files": sorted(hashes, key=lambda item: item["resolved_path"]),
        "gpg_keys": gpg_keys,
    }
    atomic_create(inventory_path, json.dumps(inventory, indent=2, sort_keys=True) + "\n")
    try:
        atomic_create(hashes_path, json.dumps(hash_inventory, indent=2, sort_keys=True) + "\n")
    except BaseException:
        try:
            os.unlink(inventory_path)
        except FileNotFoundError:
            pass
        raise
    print(f"DNF_REPOSITORY_PROVENANCE_OK\t{len(enabled)} repositories\t{len(hashes)} config files\t{len(gpg_keys)} signing keys")


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--repo-info", required=True)
    parser.add_argument("--inventory", required=True)
    parser.add_argument("--hashes", required=True)
    parser.add_argument("--fedora-release", choices=("44", "45"))
    args = parser.parse_args()
    snapshot(args.repo_info, args.inventory, args.hashes, args.fedora_release)


if __name__ == "__main__":
    main()
