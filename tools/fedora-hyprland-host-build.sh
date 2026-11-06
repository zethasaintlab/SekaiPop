#!/usr/bin/env bash
set -Eeuo pipefail

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)"
. /etc/os-release
FEDORA_RELEASE="${VERSION_ID:-}"
[[ "${ID:-}" == fedora && "$FEDORA_RELEASE" =~ ^(44|45)$ ]] || {
    printf 'The managed Hyprland builder supports only Fedora 44/45 hosts.\n' >&2
    exit 2
}
[[ "$(uname -m)" == x86_64 ]] || {
    printf 'The managed Hyprland builder supports x86_64 only.\n' >&2
    exit 2
}
(( EUID != 0 )) || {
    printf 'Run the builder as a normal user; rootless Podman is mandatory.\n' >&2
    exit 2
}
command -v podman >/dev/null 2>&1 || {
    printf 'Podman is not installed. The installer must provision it before invoking this builder.\n' >&2
    exit 2
}
rootless="$(podman info --format '{{.Host.Security.Rootless}}')"
[[ "$rootless" == true ]] || {
    printf 'Refusing to build with rootful Podman.\n' >&2
    exit 2
}

BASE_TAG="docker.io/library/fedora:$FEDORA_RELEASE"
podman pull --tls-verify=true --platform linux/amd64 "$BASE_TAG"
BASE_IMAGE_REF="$(podman image inspect --format '{{range .RepoDigests}}{{println .}}{{end}}' "$BASE_TAG" |
    awk -v prefix="docker.io/library/fedora@" 'index($0, prefix) == 1 && $0 ~ /@sha256:[0-9a-f]{64}$/ {print; exit}')"
[[ "$BASE_IMAGE_REF" =~ ^docker\.io/library/fedora@sha256:[0-9a-f]{64}$ ]] || {
    printf 'Could not resolve the official Fedora image to an immutable digest.\n' >&2
    exit 1
}

command -v git >/dev/null 2>&1 || {
    printf 'Git is required to record the exact SekaiPop build revision.\\n' >&2
    exit 2
}
BUILD_GIT_COMMIT="$(git -C "$ROOT" rev-parse --verify HEAD)"
[[ "$BUILD_GIT_COMMIT" =~ ^[0-9a-f]{40}$ ]] || {
    printf 'Could not determine the full SekaiPop source commit.\\n' >&2
    exit 1
}

IMAGE_TAG="localhost/sekaipop-fedora-hyprland:$FEDORA_RELEASE-${BASE_IMAGE_REF##*@sha256:}"
podman build --platform linux/amd64 --pull=never \
    --build-arg "FEDORA_BASE_IMAGE=$BASE_IMAGE_REF" \
    --file "$ROOT/tools/fedora-hyprland-build-smoke.Dockerfile" \
    --tag "$IMAGE_TAG" "$ROOT"

HYPRLAND_VERSION=0.57.1
HYPRLAND_COMMIT=acc1aa0bfd4bd575dcb0f76c35ccf12b660a1ab9
RELEASE_ID="$HYPRLAND_VERSION-${HYPRLAND_COMMIT:0:12}"
STAGE_PARENT="/var/tmp/sekaipop-fedora-provider-$UID"
[[ ! -L "$STAGE_PARENT" ]] || {
    printf 'Refusing symlinked provider staging directory: %s\n' "$STAGE_PARENT" >&2
    exit 1
}
mkdir -p -- "$STAGE_PARENT"
[[ -d "$STAGE_PARENT" && -O "$STAGE_PARENT" ]] || {
    printf 'Provider staging directory must be owned by the current user: %s\n' "$STAGE_PARENT" >&2
    exit 1
}
chmod 0700 "$STAGE_PARENT"
STAGE_ROOT="$(mktemp -d "$STAGE_PARENT/build.XXXXXX")"
chmod 0700 "$STAGE_ROOT"
CONTAINER_RELEASE_ROOT=/opt/sekaipop/providers/hyprland/releases
CONTAINER_PREFIX="$CONTAINER_RELEASE_ROOT/$RELEASE_ID"

printf 'Building Hyprland %s (%s) for Fedora %s in a rootless, network-isolated container.\n' \
    "$HYPRLAND_VERSION" "$HYPRLAND_COMMIT" "$FEDORA_RELEASE"
BUILD_LOG="$STAGE_ROOT/build.log"
podman run --rm --network none \
    --volume "$STAGE_ROOT:$CONTAINER_RELEASE_ROOT:Z" \
    --env "SEKAIPOP_HYPR_PREFIX=$CONTAINER_PREFIX" \
    --env "SEKAIPOP_PROVENANCE_OUTPUT=$CONTAINER_PREFIX/BUILD-PROVENANCE" \
    --env "SEKAIPOP_BUILD_GIT_COMMIT=$BUILD_GIT_COMMIT" \
    "$IMAGE_TAG" 2>&1 | tee "$BUILD_LOG"

python3 "$ROOT/tools/fedora-hyprland-host-manifest.py" \
    "$STAGE_ROOT/$RELEASE_ID" \
    --fedora-release "$FEDORA_RELEASE" \
    --hyprland-version "$HYPRLAND_VERSION" \
    --hyprland-commit "$HYPRLAND_COMMIT" \
    --runtime-prefix "$CONTAINER_PREFIX"

printf 'FEDORA_HYPRLAND_HOST_BUILD_READY\t%s\t%s\n' "$RELEASE_ID" "$STAGE_ROOT/$RELEASE_ID"
printf 'Build output is staged for the separate privileged publication phase; no host files or packages were changed.\n'
