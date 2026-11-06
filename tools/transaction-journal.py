#!/usr/bin/env python3
"""Durable, user-owned installer transaction journal."""
from __future__ import annotations

import argparse
import fcntl
import json
import os
import re
import stat
import sys
import tempfile
from datetime import datetime, timezone
from pathlib import Path
from typing import Any

SCHEMA_VERSION = 1
STATUSES = {"active", "committed", "failed", "needs_recovery"}
EVENT_RE = re.compile(r"^[a-z][a-z0-9_.-]{0,63}$")


def fail(message: str) -> None:
    raise ValueError(message)


def utc_now() -> str:
    return datetime.now(timezone.utc).isoformat(timespec="seconds")


def secure_parent(path: Path) -> None:
    if not path.is_absolute():
        fail("journal path must be absolute")
    parent = path.parent
    parent.mkdir(mode=0o700, parents=True, exist_ok=True)
    current = Path(parent.anchor)
    for component in parent.parts[1:]:
        current = current / component
        info = current.lstat()
        if not stat.S_IS_DIR(info.st_mode) or stat.S_ISLNK(info.st_mode):
            fail(f"journal path contains a non-directory or symlink component: {current}")
    info = parent.lstat()
    if info.st_uid != os.geteuid():
        fail(f"journal parent is not owned by the current user: {parent}")
    os.chmod(parent, 0o700)


def validate_file(path: Path, *, must_exist: bool) -> None:
    try:
        info = path.lstat()
    except FileNotFoundError:
        if must_exist:
            fail(f"journal does not exist: {path}")
        return
    if not stat.S_ISREG(info.st_mode) or stat.S_ISLNK(info.st_mode):
        fail(f"refusing non-regular or symlinked journal: {path}")
    if info.st_uid != os.geteuid():
        fail(f"journal is not owned by the current user: {path}")
    if stat.S_IMODE(info.st_mode) & 0o077:
        fail(f"journal permissions are too broad: {path}")


def load(path: Path) -> dict[str, Any]:
    validate_file(path, must_exist=True)
    try:
        data = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, UnicodeError, json.JSONDecodeError) as exc:
        fail(f"cannot read valid journal JSON: {exc}")
    if not isinstance(data, dict) or data.get("schema_version") != SCHEMA_VERSION:
        fail("unsupported or malformed transaction journal schema")
    if data.get("status") not in STATUSES or not isinstance(data.get("events"), list):
        fail("transaction journal status/events are malformed")
    return data


def atomic_write(path: Path, data: dict[str, Any]) -> None:
    payload = (json.dumps(data, ensure_ascii=False, sort_keys=True, indent=2) + "\n").encode()
    fd, temporary = tempfile.mkstemp(prefix=".transaction-", dir=path.parent)
    try:
        os.fchmod(fd, 0o600)
        with os.fdopen(fd, "wb", closefd=True) as stream:
            stream.write(payload)
            stream.flush()
            os.fsync(stream.fileno())
        os.replace(temporary, path)
        directory_fd = os.open(path.parent, os.O_RDONLY | getattr(os, "O_DIRECTORY", 0))
        try:
            os.fsync(directory_fd)
        finally:
            os.close(directory_fd)
    except BaseException:
        try:
            os.unlink(temporary)
        except FileNotFoundError:
            pass
        raise


def locked(path: Path):
    lock_path = path.with_name(path.name + ".lock")
    validate_file(lock_path, must_exist=False)
    fd = os.open(lock_path, os.O_CREAT | os.O_RDWR | getattr(os, "O_NOFOLLOW", 0), 0o600)
    info = os.fstat(fd)
    if not stat.S_ISREG(info.st_mode) or info.st_uid != os.geteuid():
        os.close(fd)
        fail("transaction lock is not a regular file owned by the current user")
    os.fchmod(fd, 0o600)
    fcntl.flock(fd, fcntl.LOCK_EX)
    return fd


def init(path: Path, transaction_id: str, metadata: dict[str, Any]) -> None:
    secure_parent(path)
    fd = locked(path)
    try:
        validate_file(path, must_exist=False)
        if path.exists():
            fail(f"transaction journal already exists: {path}")
        now = utc_now()
        data = {
            "schema_version": SCHEMA_VERSION,
            "transaction_id": transaction_id,
            "status": "active",
            "created_at": now,
            "updated_at": now,
            "pid": os.getpid(),
            "metadata": metadata,
            "events": [{"name": "transaction_started", "at": now, "detail": ""}],
        }
        atomic_write(path, data)
    finally:
        os.close(fd)


def update(path: Path, operation: str, name: str, detail: str) -> None:
    secure_parent(path)
    if not EVENT_RE.fullmatch(name):
        fail("event name must match [a-z][a-z0-9_.-]{0,63}")
    if len(detail.encode("utf-8")) > 2048:
        fail("event detail exceeds 2048 UTF-8 bytes")
    fd = locked(path)
    try:
        data = load(path)
        if data["status"] != "active":
            fail(f"cannot append to a {data['status']} transaction")
        now = utc_now()
        if operation == "event":
            data["events"].append({"name": name, "at": now, "detail": detail})
        elif operation == "finish":
            if name not in STATUSES - {"active"}:
                fail("finish status must be committed, failed, or needs_recovery")
            data["status"] = name
            data["events"].append({"name": "transaction_" + name, "at": now, "detail": detail})
        else:
            fail("unknown journal operation")
        data["updated_at"] = now
        atomic_write(path, data)
    finally:
        os.close(fd)


def main() -> int:
    parser = argparse.ArgumentParser()
    sub = parser.add_subparsers(dest="command", required=True)
    create = sub.add_parser("init")
    create.add_argument("path", type=Path)
    create.add_argument("transaction_id")
    create.add_argument("--metadata", default="{}")
    event = sub.add_parser("event")
    event.add_argument("path", type=Path)
    event.add_argument("name")
    event.add_argument("detail", nargs="?", default="")
    finish = sub.add_parser("finish")
    finish.add_argument("path", type=Path)
    finish.add_argument("status")
    finish.add_argument("detail", nargs="?", default="")
    show = sub.add_parser("show")
    show.add_argument("path", type=Path)
    args = parser.parse_args()
    try:
        if args.command == "init":
            metadata = json.loads(args.metadata)
            if not isinstance(metadata, dict):
                fail("metadata must be a JSON object")
            init(args.path, args.transaction_id, metadata)
        elif args.command == "event":
            update(args.path, "event", args.name, args.detail)
        elif args.command == "finish":
            update(args.path, "finish", args.status, args.detail)
        else:
            print(json.dumps(load(args.path), ensure_ascii=False, sort_keys=True, indent=2))
        return 0
    except (OSError, ValueError, TypeError) as exc:
        print(f"transaction-journal: {exc}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
