# `autoload/`

Autoloads are registered in `project.godot` under `[autoload]`, but most of the
scripts they point at **live next to the system they belong to**, not in this
directory. That indirection is deliberate, and this file is where it stops being
a mystery.

The rule: a singleton's script lives with its subsystem, so that deleting or
lifting the subsystem out of the template takes its script with it.

## Registered autoloads

Order matters. Godot initialises autoloads top to bottom, and later ones may
read earlier ones during `_ready()`.

| # | Autoload name | Script | Added in |
|---|---------------|--------|----------|
| 1 | `PSXLook`     | `res://psx/look/psx_look.gd` | Phase 3 |

`PSXLook` is first because it pushes global shader parameters, and anything that
instantiates a material during its own `_ready()` should find those parameters
already set.

## Adding an autoload

1. Put the script beside the system it serves.
2. Register it in Project Settings -> Globals -> Autoload.
3. Add a row to the table above, with a one-line reason for its position.
