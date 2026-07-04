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
