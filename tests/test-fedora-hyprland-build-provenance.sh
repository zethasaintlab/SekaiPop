#!/usr/bin/env bash
set -Eeuo pipefail

ROOT="$(cd -- "$(dirname -- "$0")/.." && pwd -P)"
WRITER="$ROOT/tools/fedora-hyprland-build-provenance.sh"
TMP="$(mktemp -d)"
trap 'rm -rf -- "$TMP"' EXIT
mkdir -p "$TMP/bin" "$TMP/sources" "$TMP/output"
cat > "$TMP/os-release" <<'OS'
ID=fedora
VERSION_ID=44
PRETTY_NAME="Fedora Linux 44 (Test)"
OS
for name in Hyprland aquamarine hyprlang hyprcursor hyprutils hyprgraphics \
    hyprwayland-scanner hyprland-protocols glaze hyprtoolkit \
    xdg-desktop-portal-hyprland hyprwire udis86; do
    mkdir "$TMP/sources/$name"
done
printf 'pinned lua test archive\n' > "$TMP/sources/lua-5.5.1.tar.gz"

cat > "$TMP/bin/rpm" <<'RPM'
#!/usr/bin/env bash
[[ "$1" == -qa ]] || exit 2
printf 'gcc\t0:16.1.1-1.fc44\tx86_64\n'
printf 'glibc\t0:2.43-1.fc44\tx86_64\n'
RPM
cat > "$TMP/bin/dnf5" <<'DNF'
#!/usr/bin/env bash
[[ "$1" == repolist && "$2" == --enabled && "$3" == -v ]] || exit 2
printf 'Repo-id : fedora\nRepo-id : updates\n'
DNF
cat > "$TMP/bin/git" <<'GIT'
#!/usr/bin/env bash
if [[ "$1" == -C && "$3" == rev-parse ]]; then
    printf '0123456789abcdef0123456789abcdef01234567\n'
elif [[ "$1" == --version ]]; then
    printf 'git version 2.49.0\n'
else
    exit 2
fi
GIT
cat > "$TMP/bin/tool-version" <<'TOOL'
#!/usr/bin/env bash
name="$(basename -- "$0")"
case "$name" in
    gcc) printf 'gcc (GCC) 16.1.1\n' ;;
    g++) printf '16.1.1\n' ;;
    cmake) printf 'cmake version 4.1.0\n' ;;
    ninja) printf '1.13.0\n' ;;
    meson) printf '1.9.0\n' ;;
    pkg-config) printf '1.8.1\n' ;;
    uname) printf 'x86_64\n' ;;
    *) exit 2 ;;
esac
TOOL
for name in gcc g++ cmake ninja meson pkg-config uname; do
    ln -s tool-version "$TMP/bin/$name"
done
chmod +x "$TMP/bin/rpm" "$TMP/bin/dnf5" "$TMP/bin/git" "$TMP/bin/tool-version"
export PATH="$TMP/bin:$PATH"
export SEKAIPOP_OS_RELEASE_FILE="$TMP/os-release"
export SEKAIPOP_BASE_IMAGE_REF="docker.io/library/fedora@sha256:0123456789abcdef"

OUT="$TMP/output/BUILD-PROVENANCE"
"$WRITER" "$OUT" "$TMP/sources" | grep -Fq 'FEDORA_BUILD_PROVENANCE_OK' || {
    printf '[FAIL] provenance generation marker missing\n' >&2
    exit 1
}
grep -Fq 'fedora_version=44' "$OUT"
grep -Fq 'architecture=x86_64' "$OUT"
grep -Fq 'base_image_ref=docker.io/library/fedora@sha256:0123456789abcdef' "$OUT"
grep -Fq 'source_commits' "$OUT"
grep -Fq $'Hyprland\t0123456789abcdef0123456789abcdef01234567' "$OUT"
grep -Fq 'source_archive.lua-5.5.1.sha256=' "$OUT"
grep -Fq 'gcc=gcc (GCC) 16.1.1' "$OUT"
grep -Fq 'Repo-id : updates' "$OUT"
grep -Fq 'glibc' "$OUT"
printf '[PASS] provenance records Fedora, immutable image, source commits, toolchain, RPMs and repositories\n'

printf 'preserve this file\n' > "$TMP/output/existing"
if "$WRITER" "$TMP/output/existing" "$TMP/sources" >/dev/null 2>&1; then
    printf '[FAIL] existing provenance output was overwritten\n' >&2
    exit 1
fi
grep -Fq 'preserve this file' "$TMP/output/existing"
printf '[PASS] existing provenance output is refused and preserved\n'

if env -u SEKAIPOP_BASE_IMAGE_REF "$WRITER" "$TMP/output/no-digest" "$TMP/sources" >/dev/null 2>&1; then
    printf '[FAIL] mutable or missing base image reference was accepted\n' >&2
    exit 1
fi
printf '[PASS] missing immutable base image reference is rejected\n'

mv "$TMP/sources/Hyprland" "$TMP/sources/Hyprland.missing"
if "$WRITER" "$TMP/output/missing-source" "$TMP/sources" >/dev/null 2>&1; then
    printf '[FAIL] missing pinned source was accepted\n' >&2
    exit 1
fi
printf '[PASS] missing pinned source is rejected\n'

if compgen -G "$TMP/output/.BUILD-PROVENANCE.tmp.*" >/dev/null; then
    printf '[FAIL] temporary provenance file leaked after test\n' >&2
    exit 1
fi
printf '\nFedora build provenance fixtures passed.\n'
