#!/usr/bin/env python3
"""Static inventory of QML imports and explicit executable references.

Maintainer audit aid, not a complete parser for QML or shell. Dynamic command
construction and indirect execution require manual review.
"""
from __future__ import annotations

import argparse
import collections
import pathlib
import re

ROOT = pathlib.Path(__file__).resolve().parents[1]
QML_ROOT = ROOT / "sekaipop"
SHELL_ROOTS = (ROOT / "installer", ROOT / "sekaipop" / "scripts")
QML_IMPORT = re.compile(r"^\s*import\s+([A-Za-z_][A-Za-z0-9_.]*)(?:\s+([0-9]+(?:\.[0-9]+)*))?", re.M)
QML_COMMAND = re.compile(r"(?:\bcommand\s*:\s*\[|\bexecDetached\s*\(\s*\[)\s*['\"]([^'\"]+)['\"]", re.M)
QML_COMMAND_STRING = re.compile(r"\bcommand\s*:\s*['\"]([^'\"]+)['\"]", re.M)
SHELL_PROBE = re.compile(r"\b(?:sp_have|command\s+-v|type\s+-P|which)\s+['\"]?([A-Za-z0-9_.+-]+)")
SHELL_EXEC = re.compile(r"^\s*(?:if\s+|elif\s+|!?\s*)?(?:exec|env|sudo|timeout)\s+([A-Za-z0-9_./+-]+)", re.M)
SHELL_BUILTINS = {
    ":", ".", "alias", "bg", "break", "builtin", "caller", "cd", "command",
    "continue", "declare", "dirs", "disown", "echo", "enable", "eval", "exec",
    "exit", "export", "false", "fc", "fg", "getopts", "hash", "help", "history",
    "jobs", "kill", "let", "local", "logout", "mapfile", "popd", "printf",
    "pushd", "pwd", "read", "readonly", "return", "set", "shift", "shopt",
    "source", "suspend", "test", "times", "trap", "true", "type", "typeset",
    "ulimit", "umask", "unalias", "unset", "wait",
}
INTERNAL_PREFIXES = ("sp_", "pm_", "qs_", "hypr_", "sekaipop_")


def files_under(root: pathlib.Path, suffix: str) -> list[pathlib.Path]:
    if not root.exists():
        return []
    return sorted(p for p in root.rglob(f"*{suffix}") if p.is_file())


def command_name(raw: str) -> str | None:
    value = raw.strip()
    if not value or "$" in value or "{" in value or "}" in value:
        return None
    token = value.split()[0].strip("\"'")
    if not token or token.startswith("$"):
        return None
    return pathlib.PurePosixPath(token).name


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--format", choices=("markdown", "tsv"), default="markdown")
    args = parser.parse_args()

    qml_files = files_under(QML_ROOT, ".qml")
    shell_files = sorted({file for root in SHELL_ROOTS for file in files_under(root, ".sh")})
    imports: dict[str, set[str]] = collections.defaultdict(set)
    qml_commands: dict[str, set[str]] = collections.defaultdict(set)
    shell_probes: dict[str, set[str]] = collections.defaultdict(set)
    shell_execs: dict[str, set[str]] = collections.defaultdict(set)

    for path in qml_files:
        rel = path.relative_to(ROOT).as_posix()
        source = path.read_text(encoding="utf-8", errors="replace")
        for module, version in QML_IMPORT.findall(source):
            imports[module + (f" {version}" if version else "")].add(rel)
        for raw in QML_COMMAND.findall(source) + QML_COMMAND_STRING.findall(source):
            name = command_name(raw)
            if name:
                qml_commands[name].add(rel)

    for path in shell_files:
        rel = path.relative_to(ROOT).as_posix()
        source = path.read_text(encoding="utf-8", errors="replace")
        source = "\n".join(line for line in source.splitlines() if not line.lstrip().startswith("#"))
        for match in SHELL_PROBE.finditer(source):
            name = match.group(1)
            if name not in SHELL_BUILTINS and not name.startswith(INTERNAL_PREFIXES):
                shell_probes[name].add(rel)
        for match in SHELL_EXEC.finditer(source):
            name = command_name(match.group(1))
            if name and name not in SHELL_BUILTINS and not name.startswith(INTERNAL_PREFIXES):
                shell_execs[name].add(rel)


    if args.format == "tsv":
        print("section\tname\toccurrences\tfiles")
        for section, values in (
            ("qml-import", imports),
            ("qml-executable", qml_commands),
            ("shell-probe", shell_probes),
        ):
            for name, paths in sorted(values.items()):
                print(f"{section}\t{name}\t{len(paths)}\t{';'.join(sorted(paths))}")
        return 0

    print("# Static dependency inventory\n")
    print(f"- QML files scanned: {len(qml_files)}")
    print(f"- Installer and project shell scripts scanned: {len(shell_files)}")
    print("- Static references only; this is not proof of complete runtime dependency coverage.")
    print("- Dynamic command construction, indirect execution, and generated QML require manual review.\n")
    for title, values in (
        ("QML import modules", imports),
        ("Explicit executable references in QML Process/execDetached commands", qml_commands),
        ("Explicit shell executable probes", shell_probes),
        ("Explicit shell execution wrappers", shell_execs),
    ):
        print(f"## {title}\n")
        if not values:
            print("_No references found._\n")
            continue
        print("| Name | Files |")
        print("|---|---:|")
        for name, paths in sorted(values.items()):
            print(f"| {name} | {len(paths)} |")
        print()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
