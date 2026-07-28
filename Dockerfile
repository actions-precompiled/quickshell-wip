# Build environment for relocatable quickshell binaries.
# Native multi-arch: build this image on amd64 or arm64 runners (no QEMU cross).
# Qt is installed via aqtinstall so we control the ABI and can bundle matching libs.
FROM ubuntu:24.04

# Optional override for buildx; default is empty so we detect the *container*
# arch with uname (plain `docker build` does not always set TARGETARCH, and a
# Dockerfile default of amd64 wrongly installed x86_64 Qt on arm64 runners).
ARG TARGETARCH=
ARG QT_VERSION=6.8.3

# Map host arch → aqt host / arch / install dir name
#   amd64/x86_64  → linux + linux_gcc_64      → gcc_64
#   arm64/aarch64 → linux_arm64 + linux_gcc_arm64 → gcc_arm64
RUN set -eux; \
    ARCH="${TARGETARCH}"; \
    if [ -z "${ARCH}" ]; then ARCH="$(uname -m)"; fi; \
    case "${ARCH}" in \
      amd64|x86_64) \
        echo "linux" > /tmp/qt_host; \
        echo "linux_gcc_64" > /tmp/qt_arch; \
        echo "gcc_64" > /tmp/qt_dir; \
        ;; \
      arm64|aarch64) \
        echo "linux_arm64" > /tmp/qt_host; \
        echo "linux_gcc_arm64" > /tmp/qt_arch; \
        echo "gcc_arm64" > /tmp/qt_dir; \
        ;; \
      *) echo "Unsupported arch=${ARCH} (TARGETARCH='${TARGETARCH}')" >&2; exit 1 ;; \
    esac; \
    echo "Qt arch mapping: host=$(cat /tmp/qt_host) arch=$(cat /tmp/qt_arch) dir=$(cat /tmp/qt_dir)"

ENV DEBIAN_FRONTEND=noninteractive \
    QT_VERSION=${QT_VERSION} \
    QT_ROOT=/opt/Qt

RUN apt-get update && apt-get install -y --no-install-recommends \
        build-essential \
        ca-certificates \
        cmake \
        curl \
        git \
        ninja-build \
        pkg-config \
        python3 \
        python3-pip \
        python3-venv \
        patchelf \
        file \
        jq \
        libdrm-dev \
        libwayland-dev \
        wayland-protocols \
        libxcb1-dev \
        libxcb-composite0-dev \
        libxcb-icccm4-dev \
        libxcb-image0-dev \
        libxcb-keysyms1-dev \
        libxcb-randr0-dev \
        libxcb-render-util0-dev \
        libxcb-shape0-dev \
        libxcb-util-dev \
        libxcb-xfixes0-dev \
        libxcb-xkb-dev \
        libxkbcommon-dev \
        libxkbcommon-x11-dev \
        libpipewire-0.3-dev \
        libpam0g-dev \
        libpolkit-agent-1-dev \
        libglib2.0-dev \
        libgbm-dev \
        libvulkan-dev \
        libegl1-mesa-dev \
        libgl1-mesa-dev \
        libcli11-dev \
        libjemalloc-dev \
        libunwind-dev \
        libdwarf-dev \
        libelf-dev \
        spirv-tools \
        mesa-common-dev \
        zlib1g-dev \
        libssl-dev \
        libfontconfig1-dev \
        libfreetype-dev \
        libdbus-1-dev \
        libicu-dev \
        libpcre2-dev \
        libpng-dev \
        libjpeg-dev \
        libharfbuzz-dev \
        libinput-dev \
        libmtdev-dev \
        libts-dev \
        libx11-dev \
        libx11-xcb-dev \
        libxext-dev \
        libxi-dev \
        libxrender-dev \
        libsm-dev \
        libice-dev \
    && rm -rf /var/lib/apt/lists/*

# Install Qt SDK (private headers + libs) via aqtinstall for this architecture
RUN set -eux; \
    QT_HOST="$(cat /tmp/qt_host)"; \
    QT_ARCH="$(cat /tmp/qt_arch)"; \
    QT_DIR="$(cat /tmp/qt_dir)"; \
    QT_PREFIX="/opt/Qt/${QT_VERSION}/${QT_DIR}"; \
    python3 -m venv /opt/aqt-venv; \
    /opt/aqt-venv/bin/pip install --no-cache-dir aqtinstall; \
    /opt/aqt-venv/bin/aqt install-qt "${QT_HOST}" desktop "${QT_VERSION}" "${QT_ARCH}" \
        -O /opt/Qt \
        -m qtshadertools qtimageformats; \
    test -x "${QT_PREFIX}/bin/qmake"; \
    "${QT_PREFIX}/bin/qmake" -query QT_VERSION; \
    # Persist for runtime containers
    printf '%s\n' "${QT_PREFIX}" > /etc/qt-prefix; \
    ln -sfn "${QT_PREFIX}" /opt/Qt/current; \
    rm -rf /root/.cache /tmp/*

# Default env points at /opt/Qt/current (arch-specific gcc_64 or gcc_arm64)
ENV PATH=/opt/Qt/current/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin \
    CMAKE_PREFIX_PATH=/opt/Qt/current \
    PKG_CONFIG_PATH=/opt/Qt/current/lib/pkgconfig \
    LD_LIBRARY_PATH=/opt/Qt/current/lib \
    QT_PREFIX=/opt/Qt/current

WORKDIR /src
COPY scripts/build_and_package.sh /usr/local/bin/build_and_package.sh
RUN chmod +x /usr/local/bin/build_and_package.sh

ENTRYPOINT ["/usr/local/bin/build_and_package.sh"]
