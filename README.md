# quickshell prebuilt binaries

Relocatable [quickshell](https://quickshell.org/) builds for Linux, published as
tarballs you can unpack and use with [mise](https://mise.jdx.dev/), asdf, or a
plain `PATH` entry.

Quickshell is a QtQuick toolkit for desktop shells (bars, widgets, lock screens,
and similar) on Wayland and X11. Upstream ships source only; this repo compiles
and packages it.

## Why not `buildenv`?

The generic [buildenv](https://github.com/actions-precompiled/buildenv) image is
aimed at small C/C++ cross builds. Quickshell needs a full **Qt 6 SDK** (including
private headers) and many desktop libraries (Wayland, PipeWire, PAM, …). This
repo uses its own `Dockerfile` instead.

There is also **no Dagger** pipeline here — just Docker + `create_releases`, same
shape as the other actions-precompiled packages.

## Supported targets

| Target | Builder | Notes |
|--------|---------|--------|
| `linux-amd64` | `ubuntu-latest` | Qt **6.8.3** (`gcc_64`) bundled |
| `linux-aarch64` | `ubuntu-24.04-arm` | Qt **6.8.3** (`gcc_arm64`) bundled |

Native builds only (no QEMU). GitHub’s free arm64 runners are for **public**
repos; private repos need paid arm runners or self-hosted.

Windows is out of scope (desktop shell integrations are Linux-oriented).

## Artifact layout

Each release asset looks like:

```text
quickshell-0.3.0-linux-amd64.tar.gz
└── quickshell/
    ├── bin/
    │   ├── qs            → quickshell
    │   ├── quickshell    (wrapper: sets lib/plugin/qml paths)
    │   ├── quickshell.bin
    │   └── qt.conf
    ├── lib/              (bundled Qt + a few non-system libs)
    ├── plugins/          (Qt platform / image / wayland plugins)
    ├── qml/              (Qt QML modules)
    ├── share/
    └── BUILDINFO.txt
```

Install example:

```bash
mkdir -p ~/.local/quickshell
tar -xzf quickshell-0.3.0-linux-amd64.tar.gz -C ~/.local/quickshell --strip-components=1
export PATH="$HOME/.local/quickshell/bin:$PATH"
qs --help
```

System libraries such as `libwayland-client`, `libpipewire`, `libpam`, and GPU
stacks are **not** fully bundled — they come from the host. **Qt is bundled** so
the private-API match required by quickshell stays consistent.

## Building

### Prerequisites

- Docker
- GitHub CLI (`gh`) for release publishing
- Network (clones upstream + pulls base image)

### Commands

```bash
# Build the latest missing upstream tags and publish GitHub releases
./create_releases

# Build one version locally (no gh release) — host arch default
LOCAL_BUILD=1 ./create_releases v0.3.0

# See what would be built
DRY_RUN=1 ./create_releases

# Explicit target(s)
TARGETS=linux-amd64 LOCAL_BUILD=1 ./create_releases v0.3.0
TARGETS="linux-amd64 linux-aarch64" LOCAL_BUILD=1 ./create_releases v0.3.0
```

`create_releases` is a stdlib Python script (`python3 ./create_releases` also works).
Default `TARGETS` matches the host (`linux-amd64` or `linux-aarch64`).

Environment variables:

| Variable | Meaning |
|----------|---------|
| `LOCAL_BUILD` | Build only; skip `gh release create/upload` |
| `DRY_RUN` | List versions, do not build |
| `TARGETS` | Space-separated targets (default `linux-amd64`) |
| `BUILD_OUTPUT_DIR` | Output root (default `$PWD/target`) |
| `SKIP_IMAGE_BUILD` | Reuse an already-built `quickshell-buildenv:local` |
| `IMAGE_NAME` / `IMAGE_TAG` | Override image name |

### What the container does

1. Clones [quickshell-mirror/quickshell](https://github.com/quickshell-mirror/quickshell) at the requested tag  
2. Configures CMake against the image’s Qt 6.8.3 prefix  
3. Builds with the usual shell features enabled (Wayland, Hyprland, PipeWire, PAM, …)  
4. Installs into a staging prefix and bundles Qt libs / plugins / QML  
5. Writes `bin/quickshell` wrapper + `qt.conf`  
6. Emits `quickshell-<version>-linux-amd64.tar.gz` under `target/<target>/`

Distributor flag passed to CMake: `actions-precompiled`.

## CI

| Workflow | Trigger | Publishes releases? | What |
|----------|---------|---------------------|------|
| `build-artifacts.yml` | **push** / PR to main | **No** | Dry-run plan of missing tags + smoke-build latest for `linux-amd64` and `linux-aarch64`; upload workflow artifacts |
| `build-releases.yml` | **`workflow_dispatch` only** | **Yes** | Auto-detect (or pass) missing upstream tags → matrix build both arches → create GitHub releases and upload tarballs |

No schedule cron: nothing publishes unless you run **Publish Missing Releases** by hand.

Orchestration is `create_releases` (Python 3 **stdlib only**): version planning via
the GitHub API (`urllib`), then it puppets `docker` / `gh` through `subprocess`.

## Versioning

Release tags track **upstream** tags (`v0.3.0`, `0.2.1`, …). The tarball name
always uses the version **without** a leading `v` when upstream used one
(`quickshell-0.3.0-linux-amd64.tar.gz`).

## Notes / limitations

- Quickshell must be built against the same Qt it runs with (private APIs). That
  is why Qt is vendored in the tarball.
- glibc is from Ubuntu 24.04 — older distros may not run the binary.
- First Docker image build downloads the Qt SDK and is large/slow; later builds
  reuse the image layer cache.

## License

Upstream quickshell is LGPL-3.0. This packaging glue is provided under the same
terms as other actions-precompiled repos unless noted otherwise.
