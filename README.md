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
quickshell --help   # or: qs --help
```

System libraries such as `libwayland-client`, `libpipewire`, `libpam`, and GPU
stacks are **not** fully bundled — they come from the host. **Qt is bundled** so
the private-API match required by quickshell stays consistent.

## Building

### Prerequisites

- Docker
- Network (clones upstream + pulls base image)
- GitHub CLI (`gh`) only if you use `--publish`

### Commands

```bash
# Build one version locally (default — no GitHub release)
./create_releases v0.3.0

# Auto-detect tags not released here yet, still local-only
./create_releases

# See what would be built
./create_releases --dry-run
# or: DRY_RUN=1 ./create_releases

# Explicit target(s)
TARGETS=linux-amd64 ./create_releases v0.3.0
TARGETS="linux-amd64 linux-aarch64" ./create_releases v0.3.0

# Build and publish GitHub releases (opt-in)
./create_releases --publish
./create_releases --publish v0.3.0
# or: PUBLISH=1 ./create_releases v0.3.0
```

`create_releases` is a uv script (`#!/usr/bin/env -S uv run --script`, stdlib deps only).
Install tools with `mise install` (see `mise.toml`). Then run `./create_releases …`.
Default `TARGETS` matches the host (`linux-amd64` or `linux-aarch64`).
**Publish is off by default** so local builds are safe.

| Flag / env | Meaning |
|------------|---------|
| `--publish` / `PUBLISH=1` | Create GitHub releases and upload tarballs |
| `--dry-run` / `DRY_RUN=1` | List versions, do not build |
| `--skip-smoke` / `SKIP_SMOKE=1` | Skip post-build smoke test |
| `--smoke-only` | Only smoke-test existing `target/` tarballs (no build) |
| `TARGETS` | Space-separated targets (default: host arch) |
| `BUILD_OUTPUT_DIR` | Output root (default `$PWD/target`) |
| `SKIP_IMAGE_BUILD` | Reuse an already-built `quickshell-buildenv:local` |
| `IMAGE_NAME` / `IMAGE_TAG` | Override image name |

Smoke tests extract the tarball and run `quickshell --help` / `--version` under
**Xvfb** (X Virtual Framebuffer — a shadow/virtual X server via `xvfb-run`), with
`QT_QPA_PLATFORM=xcb`. Install: `xvfb` plus basic Mesa/X11 libs (`libgl1`,
`libegl1`, …). CI uploads the tarball first, then runs smoke.

### What the container does

1. Clones [quickshell-mirror/quickshell](https://github.com/quickshell-mirror/quickshell) at the requested tag  
2. Configures CMake against the image’s Qt 6.8.3 prefix  
3. Builds with the usual shell features enabled (Wayland, Hyprland, PipeWire, PAM, …)  
4. Installs into a staging prefix and bundles Qt libs / plugins / QML  
5. Writes `bin/quickshell` wrapper + `qt.conf`  
6. Emits `quickshell-<version>-linux-amd64.tar.gz` under `target/<target>/`

Distributor flag passed to CMake: `actions-precompiled`.

## CI

Same shape as [tesseract-bin](https://github.com/actions-precompiled/tesseract-bin): **one Build run per version**, fan-out via dispatcher.

| Workflow | Trigger | Publishes? | What |
|----------|---------|------------|------|
| `build.yml` | push / PR | **No** | Build **latest** upstream tag for amd64 + aarch64; upload artifacts; Xvfb smoke |
| `build.yml` | `workflow_dispatch` | optional | Build **one** given version; optional GitHub Release (`publish` / `recreate`) |
| `dispatch-missing.yml` | `workflow_dispatch` only | optional | Plan missing tags, then `gh workflow run build.yml` **once per version** (isolated failures) |

Push/PR never publishes. To ship releases: run **Dispatch Missing Builds** with `publish=true` (or dispatch a single **Build** with version + publish).

Orchestration is `create_releases` (uv script + curl/docker/gh).

## Example config

A minimal top bar lives in [`examples/hello/`](examples/hello/) for manual testing:

```bash
# after extract + PATH
cd examples/hello && quickshell -p shell.qml
# or from repo root:
quickshell -p examples/hello/shell.qml
```

See [examples/README.md](examples/README.md).

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
