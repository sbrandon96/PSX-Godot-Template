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
| 1 | `PSXLook`     | `res://psx/look/psx_look.gd`      | Phase 3 |
| 2 | `GameState`   | `res://core/state/game_state.gd`  | Phase 4 |
| 3 | `SceneLoader` | `res://core/loading/scene_loader.gd` | Phase 4 |

Why this order:

1. **`PSXLook`** is first because it pushes global shader parameters. Anything
   that instantiates a material during its own `_ready()` should find those
   parameters already set.
2. **`GameState`** holds no dependencies, but must exist before `SceneLoader`,
   since a loaded scene may read state as it enters the tree.
3. **`SceneLoader`** is last because it is the only one that acts on the others.

Every autoload's `_ready()` runs **before the main scene's**. That is why
`bootstrap.gd` treats steps 1 and 2 of its boot sequence as guarantees it can
rely on rather than as actions it performs.

`DebugLog` (`res://core/utilities/debug_log.gd`) is deliberately **not** an
autoload. It is a `class_name` with only static members, so it is reachable
everywhere without occupying a singleton slot or costing a node in the tree.

## Adding an autoload

1. Put the script beside the system it serves.
2. Register it in Project Settings -> Globals -> Autoload.
3. Add a row to the table above, with a one-line reason for its position.
