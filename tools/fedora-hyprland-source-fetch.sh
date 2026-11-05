#!/usr/bin/env bash
set -Eeuo pipefail

DEST="${1:-/opt/sekaipop/sources}"
mkdir -p -- "$DEST"
[[ -d "$DEST" && ! -L "$DEST" ]] || { printf 'Unsafe source destination: %s\n' "$DEST" >&2; exit 2; }

fetch_tagged_repo() {
    local name="$1" owner="$2" repository="$3" tag="$4" expected="$5" destination="$DEST/$1" actual
    [[ ! -e "$destination" ]] || { printf 'Refusing existing source path: %s\n' "$destination" >&2; return 1; }
    git clone --quiet --depth=1 --branch "$tag" "https://github.com/$owner/$repository.git" "$destination"
    actual="$(git -C "$destination" rev-parse HEAD)"
    [[ "$actual" == "$expected" ]] || {
        printf 'Pinned source mismatch for %s: expected %s, got %s\n' "$name" "$expected" "$actual" >&2
        return 1
    }
    printf 'SOURCE_PIN_OK\t%s\t%s\t%s\n' "$name" "$tag" "$actual"
}

fetch_commit_repo() {
    local name="$1" owner="$2" repository="$3" expected="$4" destination="$DEST/$1" actual
    [[ ! -e "$destination" ]] || { printf 'Refusing existing source path: %s\n' "$destination" >&2; return 1; }
    mkdir -p -- "$destination"
    git -C "$destination" init --quiet
    git -C "$destination" remote add origin "https://github.com/$owner/$repository.git"
    git -C "$destination" fetch --quiet --depth=1 origin "$expected"
    git -C "$destination" checkout --quiet --detach FETCH_HEAD
    actual="$(git -C "$destination" rev-parse HEAD)"
    [[ "$actual" == "$expected" ]] || {
        printf 'Pinned source mismatch for %s: expected %s, got %s\n' "$name" "$expected" "$actual" >&2
        return 1
    }
    printf 'SOURCE_PIN_OK\t%s\tcommit\t%s\n' "$name" "$actual"
}

fetch_tagged_repo Hyprland hyprwm Hyprland v0.57.1 acc1aa0bfd4bd575dcb0f76c35ccf12b660a1ab9
fetch_tagged_repo aquamarine hyprwm aquamarine v0.16.0 b77d67648336223a6c8fb88844ae316e7b72b574
fetch_tagged_repo hyprlang hyprwm hyprlang v0.6.8 3a1c1b25b059dae2c6bbc46991562ba1158d125c
fetch_tagged_repo hyprcursor hyprwm hyprcursor v0.1.13 44e91d467bdad8dcf8bbd2ac7cf49972540980a5
fetch_tagged_repo hyprutils hyprwm hyprutils v0.14.3 0d13d5a624eb093b600d1b2cbe448fb613c86424
fetch_tagged_repo hyprgraphics hyprwm hyprgraphics v0.6.0 ade4ef0a887d2740efb9c9af2ddb175633365e1b
fetch_tagged_repo hyprwayland-scanner hyprwm hyprwayland-scanner v0.4.6 b8632713a6beaf28b56f2a7b0ab2fb7088dbb404
fetch_tagged_repo hyprland-protocols hyprwm hyprland-protocols v0.8.0 044a434ec371f985655389bcef09286b1af3d77c
fetch_tagged_repo glaze stephenberry glaze v7.2.0 b518eec7a22e56ffa238b072c07f47efa7cea97f
fetch_tagged_repo hyprtoolkit hyprwm hyprtoolkit v0.6.0 f8cbaf42e1f7fdc9c7565d7be3e935f6d56c7a39
fetch_tagged_repo xdg-desktop-portal-hyprland hyprwm xdg-desktop-portal-hyprland v1.5.0 d1467fea8d1895cb7835829c2fbb271a0d37760a
fetch_commit_repo hyprwire hyprwm hyprwire a546e42d45e161682f729ebf52375bd4800d7041
fetch_commit_repo udis86 canihavesomecoffee udis86 5336633af70f3917760a6d441ff02d93477b0c86

LUA_ARCHIVE="$DEST/lua-5.5.1.tar.gz"
LUA_PART="$LUA_ARCHIVE.part"
LUA_SHA256=1c4b4068d67061f2a2231ad2b5422e77acea1487ea9890f6320af614f4373dce
LUA_URLS=(
    https://www.lua.org/ftp/lua-5.5.1.tar.gz
    https://www2.tecgraf.puc-rio.br/lua/local/ftp/lua-5.5.1.tar.gz
)
rm -f -- "$LUA_PART" "$LUA_ARCHIVE"
LUA_SOURCE_OK=0
for lua_url in "\${LUA_URLS[@]}"; do
    printf 'Fetching pinned Lua 5.5.1 from %s\n' "$lua_url"
    if curl --fail --location --silent --show-error \
        --connect-timeout 15 --max-time 120 \
        --retry 2 --retry-all-errors --retry-delay 2 \
        "$lua_url" --output "$LUA_PART" &&
        printf '%s  %s\n' "$LUA_SHA256" "$LUA_PART" | sha256sum --check --status; then
        mv -- "$LUA_PART" "$LUA_ARCHIVE"
        LUA_SOURCE_OK=1
        break
    fi
    rm -f -- "$LUA_PART"
    printf 'Lua 5.5.1 download or SHA256 verification failed for %s; trying the next published mirror.\n' "$lua_url" >&2
done
(( LUA_SOURCE_OK == 1 )) || {
    printf 'Could not acquire the official Lua 5.5.1 source archive from any pinned mirror with the expected SHA256.\n' >&2
    exit 1
}
printf 'SOURCE_SHA256_OK\tlua-5.5.1\t%s\n' "$LUA_SHA256"

# The portal's bundled hyprland-protocols submodule is v0.7.1, below its
# own >=0.8.0 requirement. The separately pinned v0.8.0 source is installed
# first; the portal build must resolve it from the private prefix.
# The portal's sdbus-cpp fallback is not fetched: Fedora's official package
# inventory verified sdbus-c++ >=2.0.0 on both target releases.
