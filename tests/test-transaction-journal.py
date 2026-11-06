#!/usr/bin/env python3
import json
import os
import subprocess
import sys
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
TOOL = ROOT / "tools" / "transaction-journal.py"


def run(*args, expected=0):
    result = subprocess.run([sys.executable, str(TOOL), *map(str, args)], text=True, capture_output=True)
    if result.returncode != expected:
        raise AssertionError(f"expected exit {expected}, got {result.returncode}: {result.stderr}")
    return result


def main():
    with tempfile.TemporaryDirectory(prefix="sekaipop-journal-") as temporary:
        base = Path(temporary)
        journal = base / "state" / "installer-transactions" / "tx-1.json"
        run("init", journal, "tx-1", "--metadata", '{"distro":"fedora","release":"45"}')
        data = json.loads(journal.read_text())
        assert data["status"] == "active"
        assert data["events"][0]["name"] == "transaction_started"
        assert data["metadata"]["release"] == "45"
        assert journal.stat().st_mode & 0o777 == 0o600
        run("recover-check", journal.parent)

        run("event", journal, "provider.preflight", "Fedora 45 supported")
        run("event", journal, "podman.validated", "rootless=true")
        data = json.loads(journal.read_text())
        assert [item["name"] for item in data["events"]][-2:] == ["provider.preflight", "podman.validated"]

        run("event", journal, "invalid event", expected=1)
        run("init", journal, "tx-1", expected=1)
        run("finish", journal, "committed", "all required phases validated")
        data = json.loads(journal.read_text())
        assert data["status"] == "committed"
        assert data["events"][-1]["name"] == "transaction_committed"
        run("event", journal, "late.event", expected=1)
        run("finish", journal, "failed", expected=1)

        concurrent = base / "state" / "installer-transactions" / "tx-concurrent.json"
        run("init", concurrent, "tx-concurrent")
        processes = [
            subprocess.Popen([sys.executable, str(TOOL), "event", str(concurrent), f"worker-{index}"],
                             stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
            for index in range(12)
        ]
        for process in processes:
            stdout, stderr = process.communicate(timeout=10)
            assert process.returncode == 0, (stdout, stderr)
        data = json.loads(concurrent.read_text())
        names = [item["name"] for item in data["events"]]
        assert len(names) == 13 and len(set(names)) == 13

        symlink_journal = base / "state" / "installer-transactions" / "linked.json"
        symlink_journal.symlink_to(journal)
        run("event", symlink_journal, "attack", expected=1)

        lock = concurrent.with_name(concurrent.name + ".lock")
        lock.unlink()
        lock.symlink_to(journal)
        run("event", concurrent, "lock.attack", expected=1)

        malformed = base / "state" / "installer-transactions" / "malformed.json"
        malformed.write_text('{"schema_version":999}')
        malformed.chmod(0o600)
        run("event", malformed, "unsafe", expected=1)
        malformed.unlink()

        stale = base / "state" / "installer-transactions" / "tx-stale.json"
        run("init", stale, "tx-stale")
        stale_data = json.loads(stale.read_text())
        stale_data["pid"] = 99999999
        stale_data["pid_start_time"] = "1"
        stale.write_text(json.dumps(stale_data))
        stale.chmod(0o600)
        run("recover-check", stale.parent, expected=1)
        assert json.loads(stale.read_text())["status"] == "needs_recovery"

    print("Durable transaction journal fixtures passed.")


if __name__ == "__main__":
    main()
