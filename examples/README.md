# Example configs

Small configs to verify a prebuilt `qs` / `quickshell` binary on a real desktop.

## Prerequisites

- Graphical session (Wayland compositor with layer-shell, or X11)
- Extracted tarball with `bin/` on `PATH` (and host libs as needed — e.g. on
  NixOS, ensure system lib dirs are on `LD_LIBRARY_PATH` / `nix-ld`)

## Hello bar

Top bar that shows a static label and a live clock.

```bash
# point -p at the file
qs -p examples/hello/shell.qml

# or use the directory as a config (looks for shell.qml)
qs -c examples/hello
```

You should get a dark strip at the top of the screen. Stop with `Ctrl+C` in the
terminal that launched `qs`.

If nothing appears, check the compositor logs / `qs` stderr (missing Wayland
protocols, GPU/GL, or display env vars).
