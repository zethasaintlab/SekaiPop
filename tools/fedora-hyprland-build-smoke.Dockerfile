ARG FEDORA_VERSION=44
FROM fedora:${FEDORA_VERSION}

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
    pugixml-devel \
    libzip-devel \
    tomlplusplus-devel \
    xorg-x11-server-Xwayland \
    && dnf5 clean all

COPY tools/fedora-hyprland-source-fetch.sh /usr/local/bin/fedora-hyprland-source-fetch
COPY tools/fedora-hyprland-source-build-smoke.sh /usr/local/bin/fedora-hyprland-source-build-smoke
RUN chmod 0755 /usr/local/bin/fedora-hyprland-source-fetch /usr/local/bin/fedora-hyprland-source-build-smoke \
    && /usr/local/bin/fedora-hyprland-source-fetch /opt/sekaipop/sources

ENTRYPOINT ["/usr/local/bin/fedora-hyprland-source-build-smoke"]
