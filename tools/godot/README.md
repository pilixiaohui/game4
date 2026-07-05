# Godot binary

`bin/godot` is the project entrypoint used by local automation and CI.

The Godot editor binary is not committed as a normal Git blob because the Linux
4.7 executable is larger than GitHub's 100 MB blob limit. Use one of these
explicit sources:

1. Set `GODOT_BIN` to an executable Godot 4.7 binary.
2. Place `Godot_v4.7-stable_linux.x86_64` in this directory.
3. Install `godot4` or `godot` on `PATH`.

The wrapper intentionally does not contain daemon- or workspace-specific
absolute fallbacks. Runtime environments that provide a cached binary should
expose it through `GODOT_BIN`.

## Recommended validation commands

Pure headless is the stable gate for logic, catalog, and natural simulation
checks:

```sh
GODOT_BIN=/path/to/Godot_v4.7-stable_linux.x86_64 ./bin/godot --headless --path . --script res://scripts/validate_headless.gd
GODOT_BIN=/path/to/Godot_v4.7-stable_linux.x86_64 ./bin/godot --headless --path . --script res://scripts/natural_playthrough.gd
GODOT_BIN=/path/to/Godot_v4.7-stable_linux.x86_64 ./bin/godot --headless --path . --script res://scripts/natural_support_matrix.gd
```

Visual and layout gates require a display server. In CI or a local terminal
without a desktop session, run them through `xvfb-run`:

```sh
GODOT_BIN=/path/to/Godot_v4.7-stable_linux.x86_64 xvfb-run -a ./bin/godot --path . --script res://scripts/visual_smoke.gd
GODOT_BIN=/path/to/Godot_v4.7-stable_linux.x86_64 xvfb-run -a ./bin/godot --path . --script res://scripts/ui_bounds_check.gd
```

Do not use pure `--headless` visual smoke as a stable gate; it is intentionally
limited to validate/natural scripts.
