# Example configs

Small configs to verify a prebuilt `quickshell` binary on a real desktop
(`qs` is the same binary via symlink).

## Prerequisites

- Graphical session (Wayland compositor with layer-shell, or X11)
- Extracted tarball with `bin/` on `PATH` (and host libs as needed — e.g. on
  NixOS, ensure system lib dirs are on `LD_LIBRARY_PATH` / `nix-ld`)

## Hello bar

Top bar that shows a static label and a live clock.

```bash
cd examples/hello
quickshell -p shell.qml
```

Or with an absolute/relative path from the repo root:

```bash
quickshell -p examples/hello/shell.qml
```

You should get a dark strip at the top of the screen. Stop with `Ctrl+C` in the
terminal that launched it.

If nothing appears, check the compositor logs / stderr (missing Wayland
protocols, GPU/GL, or display env vars).
