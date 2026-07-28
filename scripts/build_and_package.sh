#!/usr/bin/env bash
# Build quickshell from upstream and produce a relocatable tarball with bundled Qt.
set -euo pipefail

QUICKSHELL_VERSION="${QUICKSHELL_VERSION:?QUICKSHELL_VERSION is required}"
BUILD_TARGET="${BUILD_TARGET:-linux-amd64}"
OUTPUT_DIR="${OUTPUT_DIR:-/out}"
QT_VERSION="${QT_VERSION:-6.8.3}"
QT_ROOT="${QT_ROOT:-/opt/Qt}"
# Prefer explicit QT_PREFIX, then /opt/Qt/current (image symlink), then arch dirs
if [[ -z "${QT_PREFIX:-}" ]]; then
  if [[ -d /opt/Qt/current ]]; then
    QT_PREFIX=/opt/Qt/current
  elif [[ -d "${QT_ROOT}/${QT_VERSION}/gcc_64" ]]; then
    QT_PREFIX="${QT_ROOT}/${QT_VERSION}/gcc_64"
  elif [[ -d "${QT_ROOT}/${QT_VERSION}/gcc_arm64" ]]; then
    QT_PREFIX="${QT_ROOT}/${QT_VERSION}/gcc_arm64"
  else
    QT_PREFIX="${QT_ROOT}/${QT_VERSION}/gcc_64"
  fi
fi
UPSTREAM_REPO="${UPSTREAM_REPO:-https://github.com/quickshell-mirror/quickshell.git}"
DISTRIBUTOR="${DISTRIBUTOR:-actions-precompiled}"
JOBS="${JOBS:-$(nproc)}"
KEEP_SYMBOLS="${KEEP_SYMBOLS:-1}"

# Normalize tag (accept 0.3.0 or v0.3.0)
RAW_VERSION="${QUICKSHELL_VERSION}"
if [[ "$RAW_VERSION" =~ ^v ]]; then
  TAG="${RAW_VERSION#v}"
  NORMALIZED_TAG="$RAW_VERSION"
else
  TAG="$RAW_VERSION"
  NORMALIZED_TAG="v${RAW_VERSION}"
fi

case "$BUILD_TARGET" in
  linux-amd64|linux-x86_64) ARCHIVE_SUFFIX="linux-amd64" ;;
  linux-aarch64|linux-arm64) ARCHIVE_SUFFIX="linux-aarch64" ;;
  *)
    echo "Unsupported BUILD_TARGET: $BUILD_TARGET (linux-amd64, linux-aarch64)" >&2
    exit 1
    ;;
esac

if [[ ! -d "$QT_PREFIX" ]]; then
  echo "Qt prefix not found: $QT_PREFIX" >&2
  exit 1
fi

export PATH="${QT_PREFIX}/bin:${PATH}"
export CMAKE_PREFIX_PATH="${QT_PREFIX}${CMAKE_PREFIX_PATH:+:${CMAKE_PREFIX_PATH}}"
export PKG_CONFIG_PATH="${QT_PREFIX}/lib/pkgconfig${PKG_CONFIG_PATH:+:${PKG_CONFIG_PATH}}"
export LD_LIBRARY_PATH="${QT_PREFIX}/lib${LD_LIBRARY_PATH:+:${LD_LIBRARY_PATH}}"

WORKDIR="${WORKDIR:-/tmp/quickshell-build}"
SRC_DIR="${WORKDIR}/src"
BUILD_DIR="${WORKDIR}/build"
STAGE_DIR="${WORKDIR}/stage"
PREFIX_DIR="${STAGE_DIR}/quickshell"

rm -rf "$WORKDIR"
mkdir -p "$SRC_DIR" "$BUILD_DIR" "$PREFIX_DIR" "$OUTPUT_DIR"

echo "========================================="
echo "Building quickshell ${QUICKSHELL_VERSION}"
echo "  BUILD_TARGET:  ${BUILD_TARGET}"
echo "  ARCHIVE:       quickshell-${TAG}-${ARCHIVE_SUFFIX}.tar.gz"
echo "  Qt:            ${QT_PREFIX}"
echo "  Distributor:   ${DISTRIBUTOR}"
echo "========================================="

# --- fetch source ---
clone_tag() {
  local try_tag="$1"
  git clone --depth 1 --branch "$try_tag" "$UPSTREAM_REPO" "$SRC_DIR"
}

if ! clone_tag "$NORMALIZED_TAG" 2>/dev/null; then
  rm -rf "$SRC_DIR"
  mkdir -p "$SRC_DIR"
  if ! clone_tag "$TAG"; then
    echo "Failed to clone tag ${NORMALIZED_TAG} or ${TAG} from ${UPSTREAM_REPO}" >&2
    exit 1
  fi
fi

# --- configure & build ---
# Prefix /usr → DESTDIR layout is usr/bin, usr/share, ...; we flatten to bin/ share/ after.
cmake -G Ninja -S "$SRC_DIR" -B "$BUILD_DIR" \
  -DCMAKE_BUILD_TYPE=RelWithDebInfo \
  -DCMAKE_INSTALL_PREFIX=/usr \
  -DCMAKE_PREFIX_PATH="${QT_PREFIX}" \
  -DDISTRIBUTOR="${DISTRIBUTOR}" \
  -DINSTALL_QML_PREFIX=lib/qt6/qml \
  -DVENDOR_CPPTRACE=ON \
  -DUSE_JEMALLOC=ON \
  -DCRASH_HANDLER=ON \
  -DWAYLAND=ON \
  -DX11=ON \
  -DHYPRLAND=ON \
  -DI3=ON \
  -DSERVICE_PIPEWIRE=ON \
  -DSERVICE_STATUS_NOTIFIER=ON \
  -DSERVICE_MPRIS=ON \
  -DSERVICE_PAM=ON \
  -DSERVICE_POLKIT=ON \
  -DCMAKE_INSTALL_RPATH='\$ORIGIN/../lib' \
  -DCMAKE_BUILD_RPATH_USE_ORIGIN=ON \
  -DCMAKE_INSTALL_RPATH_USE_LINK_PATH=OFF

cmake --build "$BUILD_DIR" --parallel "$JOBS"
DESTDIR="$PREFIX_DIR" cmake --install "$BUILD_DIR"

# Flatten DESTDIR/usr → package root; drop static/dev junk from vendored cpptrace
if [[ -d "$PREFIX_DIR/usr" ]]; then
  # Move payload up
  shopt -s dotglob nullglob
  for entry in "$PREFIX_DIR"/usr/*; do
    base="$(basename "$entry")"
    if [[ -e "$PREFIX_DIR/$base" ]]; then
      cp -a "$entry"/. "$PREFIX_DIR/$base"/ 2>/dev/null || mv "$entry"/* "$PREFIX_DIR/$base"/
    else
      mv "$entry" "$PREFIX_DIR/$base"
    fi
  done
  shopt -u dotglob nullglob
  rm -rf "$PREFIX_DIR/usr"
fi

# cpptrace/zstd/libdwarf install headers + static libs we do not ship
rm -rf \
  "$PREFIX_DIR/include" \
  "$PREFIX_DIR/lib/cmake" \
  "$PREFIX_DIR/lib/pkgconfig" \
  "$PREFIX_DIR/lib"/*.a \
  "$PREFIX_DIR/lib"/*.la \
  2>/dev/null || true

if [[ ! -x "$PREFIX_DIR/bin/quickshell" ]]; then
  echo "Install did not produce bin/quickshell" >&2
  find "$PREFIX_DIR" -type f | head -80 >&2
  exit 1
fi

# Real binary lives as quickshell.bin; public names are wrappers
mv "$PREFIX_DIR/bin/quickshell" "$PREFIX_DIR/bin/quickshell.bin"
# Drop cmake-created qs symlink if present; recreated as wrapper below
rm -f "$PREFIX_DIR/bin/qs"

# --- bundle Qt and non-system shared libs ---
mkdir -p "$PREFIX_DIR/lib" "$PREFIX_DIR/plugins" "$PREFIX_DIR/qml"

is_system_lib() {
  local libpath="$1"
  case "$libpath" in
    /lib/*|/lib64/*|/usr/lib/*|/usr/lib64/*)
      local base
      base="$(basename "$libpath")"
      case "$base" in
        # Bundle these even from system paths — common version skew / crash-handler deps
        libicu*.so*|libjemalloc.so*|libjemalloc.so.*|libunwind.so*|libdouble-conversion.so*|libpcre2-16.so*|libmd4c.so*|libxcb-cursor.so*)
          return 1
          ;;
        *)
          return 0
          ;;
      esac
      ;;
    *)
      return 1
      ;;
  esac
}

declare -A SEEN_LIBS=()

copy_lib() {
  local src="$1"
  [[ -z "$src" || ! -e "$src" ]] && return 0
  local real
  real="$(readlink -f "$src")"
  [[ -z "$real" || ! -f "$real" ]] && return 0
  if [[ -n "${SEEN_LIBS[$real]+x}" ]]; then
    return 0
  fi
  SEEN_LIBS[$real]=1

  if is_system_lib "$real"; then
    return 0
  fi

  local base
  base="$(basename "$real")"
  case "$base" in
    ld-linux*.so*|ld-*.so) return 0 ;;
  esac

  echo "  bundling $real"
  cp -a "$real" "$PREFIX_DIR/lib/"

  local srcbase
  srcbase="$(basename "$src")"
  if [[ "$srcbase" != "$base" && ! -e "$PREFIX_DIR/lib/$srcbase" ]]; then
    ln -sfn "$base" "$PREFIX_DIR/lib/$srcbase"
  fi

  local dep
  while read -r dep; do
    [[ -z "$dep" ]] && continue
    copy_lib "$dep"
  done < <(ldd "$real" 2>/dev/null | awk '/=> \// { print $3 }' || true)
}

echo "Collecting shared library dependencies..."
mapfile -d '' ELF_FILES < <(find "$PREFIX_DIR" -type f -print0)

for bin in "${ELF_FILES[@]}"; do
  file "$bin" | grep -q 'ELF' || continue
  while read -r dep; do
    [[ -z "$dep" ]] && continue
    copy_lib "$dep"
  done < <(ldd "$bin" 2>/dev/null | awk '/=> \// { print $3 }' || true)
done

echo "Bundling Qt plugins and QML modules..."
QT_PLUGIN_SRC="${QT_PREFIX}/plugins"
QT_QML_SRC="${QT_PREFIX}/qml"

copy_plugin_dir() {
  local name="$1"
  if [[ -d "${QT_PLUGIN_SRC}/${name}" ]]; then
    cp -a "${QT_PLUGIN_SRC}/${name}" "${PREFIX_DIR}/plugins/"
  fi
}

copy_plugin_dir platforms
copy_plugin_dir wayland-decoration-client
copy_plugin_dir wayland-graphics-integration-client
copy_plugin_dir wayland-shell-integration
copy_plugin_dir wayland-decoration-server
copy_plugin_dir xcbglintegrations
copy_plugin_dir platforminputcontexts
copy_plugin_dir platformthemes
copy_plugin_dir imageformats
copy_plugin_dir iconengines
copy_plugin_dir qmltooling
copy_plugin_dir generic
copy_plugin_dir tls
copy_plugin_dir networkinformation
copy_plugin_dir sqldrivers

if [[ -d "$QT_QML_SRC" ]]; then
  cp -a "${QT_QML_SRC}/." "${PREFIX_DIR}/qml/"
fi

# Scan plugins/qml for further deps
while IFS= read -r -d '' plug; do
  file "$plug" | grep -q 'ELF' || continue
  while read -r dep; do
    [[ -z "$dep" ]] && continue
    copy_lib "$dep"
  done < <(ldd "$plug" 2>/dev/null | awk '/=> \// { print $3 }' || true)
done < <(find "$PREFIX_DIR/plugins" "$PREFIX_DIR/qml" -type f \( -name '*.so' -o -name '*.so.*' \) -print0 2>/dev/null)

# Explicit core Qt libs (dlopen targets ldd may miss)
for pattern in \
  libQt6Core.so* libQt6Gui.so* libQt6Qml.so* libQt6Quick.so* \
  libQt6QuickControls2.so* libQt6QuickTemplates2.so* libQt6QuickLayouts.so* \
  libQt6QuickControls2Impl.so* libQt6QuickShapes.so* libQt6QuickEffects.so* \
  libQt6Widgets.so* libQt6DBus.so* libQt6Network.so* libQt6OpenGL.so* \
  libQt6Svg.so* libQt6WaylandClient.so* libQt6WaylandEglClientHwIntegration.so* \
  libQt6WlShellIntegration.so* libQt6XcbQpa.so* \
  libQt6QmlModels.so* libQt6QmlWorkerScript.so* libQt6QmlMeta.so* \
  libQt6Labs*.so* libQt6ShaderTools.so* \
  libicudata.so* libicui18n.so* libicuuc.so*
do
  for f in "${QT_PREFIX}/lib/"$pattern; do
    [[ -e "$f" ]] || continue
    copy_lib "$f"
  done
done

# qt.conf next to the real binary (also found via wrapper's directory)
cat > "$PREFIX_DIR/bin/qt.conf" <<'QTC'
[Paths]
Prefix = ..
Libraries = lib
Plugins = plugins
QmlImports = qml
Imports = qml
QTC

# Launcher sets library / Qt paths so the tree is relocatable under any prefix
cat > "$PREFIX_DIR/bin/quickshell" <<'WRAP'
#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
export LD_LIBRARY_PATH="${ROOT}/lib${LD_LIBRARY_PATH:+:${LD_LIBRARY_PATH}}"
export QT_PLUGIN_PATH="${ROOT}/plugins${QT_PLUGIN_PATH:+:${QT_PLUGIN_PATH}}"
# Qt QML modules + quickshell's installed tooling metadata (modules are also statically linked)
QML_ROOTS="${ROOT}/qml"
if [[ -d "${ROOT}/lib/qt6/qml" ]]; then
  QML_ROOTS="${QML_ROOTS}:${ROOT}/lib/qt6/qml"
fi
export QML2_IMPORT_PATH="${QML_ROOTS}${QML2_IMPORT_PATH:+:${QML2_IMPORT_PATH}}"
export QML_IMPORT_PATH="${QML_ROOTS}${QML_IMPORT_PATH:+:${QML_IMPORT_PATH}}"
exec "${ROOT}/bin/quickshell.bin" "$@"
WRAP
chmod +x "$PREFIX_DIR/bin/quickshell"
ln -sfn quickshell "$PREFIX_DIR/bin/qs"

# RPATH as belt-and-suspenders for the real binary and bundled libs
echo "Setting RPATH on ELF files..."
while IFS= read -r -d '' elf; do
  file "$elf" | grep -q 'ELF' || continue
  case "$elf" in
    */bin/*)
      patchelf --set-rpath '$ORIGIN/../lib' "$elf" 2>/dev/null || true
      ;;
    */lib/*)
      patchelf --set-rpath '$ORIGIN' "$elf" 2>/dev/null || true
      ;;
    */plugins/*|*/qml/*)
      patchelf --set-rpath '$ORIGIN/../../lib:$ORIGIN/../../../lib:$ORIGIN/../../../../lib' "$elf" 2>/dev/null || true
      ;;
  esac
done < <(find "$PREFIX_DIR" -type f -print0)

if [[ "$KEEP_SYMBOLS" != "1" ]]; then
  echo "Stripping binaries..."
  while IFS= read -r -d '' elf; do
    file "$elf" | grep -q 'ELF' || continue
    strip --strip-unneeded "$elf" 2>/dev/null || true
  done < <(find "$PREFIX_DIR" -type f -print0)
fi

cat > "$PREFIX_DIR/BUILDINFO.txt" <<META
package=quickshell
version=${TAG}
upstream_tag=${NORMALIZED_TAG}
qt_version=${QT_VERSION}
build_target=${BUILD_TARGET}
distributor=${DISTRIBUTOR}
built_at=$(date -u +%Y-%m-%dT%H:%M:%SZ)
META

echo "Smoke check (dynamic linker)..."
if ! LD_LIBRARY_PATH="$PREFIX_DIR/lib" ldd "$PREFIX_DIR/bin/quickshell.bin" | tee /tmp/qs-ldd.txt | grep -q 'not found'; then
  echo "All linked libraries resolved."
else
  echo "Unresolved libraries:" >&2
  grep 'not found' /tmp/qs-ldd.txt >&2 || true
  exit 1
fi

# --help may fail without a display; only fail on loader errors
set +e
LD_LIBRARY_PATH="$PREFIX_DIR/lib" "$PREFIX_DIR/bin/quickshell.bin" --help >/tmp/qs-help.txt 2>&1
set -e
if grep -qi 'error while loading shared libraries\|cannot open shared object' /tmp/qs-help.txt; then
  cat /tmp/qs-help.txt >&2
  exit 1
fi
head -n 8 /tmp/qs-help.txt || true

ARCHIVE_NAME="quickshell-${TAG}-${ARCHIVE_SUFFIX}.tar.gz"
echo "Creating ${ARCHIVE_NAME}..."
tar -czf "${OUTPUT_DIR}/${ARCHIVE_NAME}" -C "$STAGE_DIR" quickshell

echo "========================================="
echo "Done: ${OUTPUT_DIR}/${ARCHIVE_NAME}"
ls -lh "${OUTPUT_DIR}/${ARCHIVE_NAME}"
echo "Contents (top):"
# Avoid SIGPIPE under pipefail when head closes early
tar -tzf "${OUTPUT_DIR}/${ARCHIVE_NAME}" | head -n 30 || true
echo "========================================="
