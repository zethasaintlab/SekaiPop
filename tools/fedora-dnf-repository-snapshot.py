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
        # Hard-link publication is atomic and fails if another writer won.
        os.link(temporary, path)
    except FileExistsError:
        fail(f"refusing concurrent output collision: {path}")
    finally:
        try:
            os.unlink(temporary)
        except FileNotFoundError:
            pass


def snapshot(repo_info_path, inventory_path, hashes_path):
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

    inventory = {
        "schema": "sekaipop-dnf5-repository-inventory-v1",
        "repositories": enabled,
    }
    hash_inventory = {
        "schema": "sekaipop-dnf-repository-config-hashes-v1",
        "files": sorted(hashes, key=lambda item: item["resolved_path"]),
    }
    atomic_create(inventory_path, json.dumps(inventory, indent=2, sort_keys=True) + "\n")
    try:
        atomic_create(hashes_path, json.dumps(hash_inventory, indent=2, sort_keys=True) + "\n")
    except BaseException:
        # atomic_create reports expected validation/collision failures via SystemExit,
        # which does not derive from Exception. Remove only the first output we created.
        try:
            os.unlink(inventory_path)
        except FileNotFoundError:
            pass
        raise
    print(f"DNF_REPOSITORY_PROVENANCE_OK\t{len(enabled)} repositories\t{len(hashes)} config files")


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--repo-info", required=True)
    parser.add_argument("--inventory", required=True)
    parser.add_argument("--hashes", required=True)
    args = parser.parse_args()
    snapshot(args.repo_info, args.inventory, args.hashes)


if __name__ == "__main__":
    main()
