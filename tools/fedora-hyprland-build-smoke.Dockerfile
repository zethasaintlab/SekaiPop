# The zero digest is intentionally unusable; callers must pass a resolved immutable Fedora image digest.
ARG FEDORA_BASE_IMAGE=docker.io/library/fedora@sha256:0000000000000000000000000000000000000000000000000000000000000000
FROM ${FEDORA_BASE_IMAGE}
ARG FEDORA_BASE_IMAGE
ENV SEKAIPOP_BASE_IMAGE_REF=${FEDORA_BASE_IMAGE}

ENV LANG=C.UTF-8
ENV LC_ALL=C.UTF-8

RUN dnf5 install -y \
    binutils \
    cmake \
    ninja-build \
    gcc-c++ \
    meson \
    pkgconf-pkg-config \
    python3 \
    cpio \
    make \
    readline-devel \
    ncurses-devel \
    git \
    curl \
    tar \
    gzip \
    xz \
    libxkbcommon-devel \
    wayland-devel \
    wayland-protocols-devel \
    libinput-devel \
    libuuid-devel \
    cairo-devel \
    pango-devel \
    pixman-devel \
    libXcursor-devel \
    libdrm-devel \
    libeis-devel \
    mesa-libgbm-devel \
    glib2-devel \
    re2-devel \
    muParser-devel \
    lcms2-devel \
    libcanberra-devel \
    libglvnd-devel \
    glslang-devel \
    libxcb-devel \
    xcb-util-wm-devel \
    xcb-util-errors-devel \
    pipewire-devel \
    libseat-devel \
    systemd-devel \
    libdisplay-info-devel \
    hwdata-devel \
    iniparser-devel \
    abseil-cpp-devel \
    libjpeg-turbo-devel \
    libwebp-devel \
    file-devel \
    libpng-devel \
    librsvg2-devel \
    sdbus-cpp-devel \
    libffi-devel \
    pugixml-devel \
    libzip-devel \
    tomlplusplus-devel \
    xorg-x11-server-Xwayland \
    && mkdir -p /opt/sekaipop \
    && dnf5 repolist --enabled -v > /opt/sekaipop/ENABLED-DNF-REPOSITORIES \
    && find /etc/yum.repos.d -maxdepth 1 -type f -name '*.repo' -print0 | sort -z | xargs -0 -r sha256sum > /opt/sekaipop/DNF-REPO-CONFIG-SHA256 \
    && dnf5 clean all

COPY tools/fedora-hyprland-source-fetch.sh /usr/local/bin/fedora-hyprland-source-fetch
COPY tools/fedora-hyprland-build-provenance.sh /usr/local/bin/fedora-hyprland-build-provenance
COPY tools/fedora-hyprland-source-build-smoke.sh /usr/local/bin/fedora-hyprland-source-build-smoke
COPY tools/private-prefix-validation.sh /usr/local/bin/sekaipop-private-prefix-validation
RUN chmod 0755 /usr/local/bin/fedora-hyprland-source-fetch /usr/local/bin/fedora-hyprland-source-build-smoke /usr/local/bin/sekaipop-private-prefix-validation /usr/local/bin/fedora-hyprland-build-provenance \
    && /usr/local/bin/fedora-hyprland-source-fetch /opt/sekaipop/sources

ENTRYPOINT ["/usr/local/bin/fedora-hyprland-source-build-smoke"]
