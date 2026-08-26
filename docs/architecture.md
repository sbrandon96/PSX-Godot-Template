# Architecture

What lives where, what may depend on what, and why the boot path looks the way
it does.

---

## The one rule

**The dependency arrow points one way.**

```
core/  psx/  player/  ui/          ->   FRAMEWORK. Reusable. Knows nothing about a game.
levels/  (and your game's dirs)    ->   CONTENT. May depend on the framework.
```

Nothing in `core/`, `psx/`, `player/` or `ui/` may reference anything in
`levels/`. Content depends on framework; framework never depends on content.

This is the rule that makes the template reusable. Break it once and every
project made from this repo inherits your test room.

Two consequences that look like inconveniences but are the rule working:

- `SceneLoader` does not know where to put a loaded scene. It is *told*, via
  `set_world_container()`, during boot.
- `PSXLook` cannot dim the fog when the player enters the basement. That belongs
  to the basement.

---

## Repository Layout

```
res://
├── core/
│   ├── loading/      scene_loader.gd      -> SceneLoader autoload
│   ├── state/        game_state.gd        -> GameState autoload
│   ├── scenes/       bootstrap.tscn/.gd   -> main scene
│   └── utilities/    debug_log.gd         -> DebugLog (static class)
├── psx/
│   ├── shaders/      the six shaders
│   ├── materials/    drag-and-drop default materials
│   └── look/         psx_look.gd -> PSXLook autoload, + preset resources
├── player/           player.tscn/.gd      reusable first-person controller
├── ui/
│   ├── post_process/ dither + CRT stack
│   ├── loading/      loading screen
│   └── debug/        F3 developer overlay
├── levels/
│   └── test/         technical validation scene ONLY
├── assets/           textures, meshes, audio
├── autoload/         README.md documenting the autoload table
├── tools/            generate_test_textures.gd
├── web/              shell.html — custom web export shell
└── docs/             this
```

`autoload/` holds no scripts. Each singleton's script lives beside the system it
serves, so lifting a subsystem out takes its script with it. The mapping is
documented in [`autoload/README.md`](../autoload/README.md) so the indirection
is not a mystery.

### Naming conventions

| Thing | Convention | Example |
|---|---|---|
| Files and directories | `snake_case` | `scene_loader.gd` |
| Classes and node names | `PascalCase` | `PSXLookPreset`, `WorldContainer` |
| Signals | `snake_case`, past tense | `scene_loaded`, `look_changed` |
| Private members | leading underscore | `_current_scene` |
| Constants | `SCREAMING_SNAKE_CASE` | `DEFAULT_SAVE_PATH` |
| Shaders | `psx_*.gdshader` | `psx_opaque.gdshader` |

---

## Autoloads

Order matters — Godot initialises them top to bottom, and **every autoload's
`_ready()` runs before the main scene's**.

| # | Name | Script | Why here |
|---|---|---|---|
| 1 | `PSXLook` | `psx/look/psx_look.gd` | Pushes global shader parameters. Anything building a material in its own `_ready()` should find them already set. |
| 2 | `GameState` | `core/state/game_state.gd` | No dependencies, but must exist before `SceneLoader` — a loaded scene may read state as it enters the tree. |
| 3 | `SceneLoader` | `core/loading/scene_loader.gd` | Last, because it is the only one that acts on the others. |

`DebugLog` is deliberately **not** an autoload. It is a `class_name` with only
static members, so it is reachable everywhere without occupying a singleton slot
or costing a node in the tree.

---

## Bootstrap Sequence

`core/scenes/bootstrap.tscn` is the project's main scene and the one scene
always in the tree.

```
Bootstrap (Node)
├── WorldContainer   (Node3D)              the 3D world; levels live here
├── UILayer          (CanvasLayer,  10)    in-game UI  -- IS post-processed
├── PostProcessLayer (CanvasLayer, 100)    dither, CRT
├── LoadingLayer     (CanvasLayer, 200)    loading screen -- NOT post-processed
└── (DebugOverlay)   (CanvasLayer, 300)    developer HUD -- NOT post-processed
```

**Why a persistent root.** `get_tree().change_scene_to_file()` replaces the
entire root, which would destroy the post-process stack and the loading screen
on every level change and rebuild them from scratch. Here the root stays put and
only `WorldContainer`'s contents are swapped.

**Layer ordering is a decision, not an accident.** A higher `layer` draws later.
`UILayer` sits *below* the post stack on purpose: a HUD should be quantised and
dithered along with the world, or it reads as a modern overlay pasted onto a PS1
game. The loading screen sits *above* it, also on purpose — it is framework
chrome shown when there is no world to be part of, and a barrel distortion
applied to the only thing on screen just looks like a broken display. (There is
a second reason: the CRT pass samples the backbuffer, which during a load holds
the half-torn-down previous scene.)

So: **in-game UI goes through the post stack; the loading screen goes above it.**
To keep the loading screen looking like it belongs anyway, its text uses
`psx_ui.gdshader` — the same palette clamp from the same globals, without the
screen-space passes.

The debug overlay carries its own `CanvasLayer` at 300 rather than taking a
named slot, because it must outrank the loading screen too (you want the stats
readable *during* a load), and because a leaf that owns its layer is deleted by
deleting one directory.

### Boot order

1. **`PSXLook`** — shader globals pushed.
2. **`GameState`** — state container ready.
3. **Post-process stack** instanced into `PostProcessLayer`.
4. **Loading screen** instanced into `LoadingLayer`, hidden.
5. **`SceneLoader`** given its container, then asked for `INITIAL_SCENE`.

Steps 1 and 2 are not actions `bootstrap.gd` performs — they are autoloads, and
they have already run by the time `Bootstrap._ready()` is entered. They are
listed because they are *guarantees relied upon* from that point on, and because
that is exactly why the autoload order above matters.

### The four constants at the top of `bootstrap.gd`

```gdscript
const INITIAL_SCENE:       String = "res://levels/test/test_room.tscn"
const POST_PROCESS_SCENE:  String = "res://ui/post_process/post_process_stack.tscn"
const LOADING_SCREEN_SCENE:String = "res://ui/loading/loading_screen.tscn"
const DEBUG_OVERLAY_SCENE: String = "res://ui/debug/debug_overlay.tscn"
```

`INITIAL_SCENE` is **the one line a new game changes.** Empty string disables
any of the four.

---

## Scene Loading

`SceneLoader` streams scenes on a background thread and swaps them under
`WorldContainer`.

```gdscript
SceneLoader.load_scene("res://levels/my_level.tscn")
SceneLoader.load_scene("res://levels/my_level.tscn", false)  # no loading screen
```

| Signal | When |
|---|---|
| `load_started(path)` | Request accepted. |
| `load_progress(percent)` | 0.0–100.0, on frames it changes. |
| `load_completed(path)` | New scene in the tree, old one gone. |
| `load_failed(path, reason)` | Anything went wrong. `reason` is written for a human. |

### Design points worth knowing

**A bad path is rejected before the request is made.** `load_threaded_request()`
returns `OK` for a path that does not exist, and the engine prints its own raw
`Cannot open file` lines from a background thread that cannot be caught or
suppressed. `SceneLoader` pre-checks with `ResourceLoader.exists()`, turning
"a typo fills the output panel with engine internals" into one readable line
naming your path. The full status enum is still handled afterwards, because a
file that exists can still be corrupt.

**Two levels are never alive at once.** The outgoing scene is removed from the
tree *before* the new one is added, because `queue_free()` only takes effect at
end of frame. Freeing without removing first would leave both levels in the
tree — both processing, both receiving input, both visible.

**Concurrent loads are refused, not queued.** Queueing implies a policy (drop?
replace? stack?) the template has no business choosing for you.

**Minimum display time**, default 0.5 s, applies only when a loading screen was
requested. A scene that loads in 30 ms makes the screen appear and vanish within
a blink, which reads as a graphical glitch. The rule lives in `SceneLoader` and
nowhere else, so it cannot disagree with itself.

---

## Game State

`GameState` is a generic key/value container with change notification and
optional JSON persistence. **It is not a save system, an inventory, or a player
stat block.** It ships empty and stays empty. If you find yourself adding a
`player_health` property to it, that is game content and belongs in your game.

```gdscript
GameState.set_value("visited_basement", true)
GameState.get_bool("visited_basement")
GameState.state_changed.connect(func(key, old, new): ...)
GameState.save_to_file()   # user://game_state.json
```

### Two measured JSON hazards, both handled

**Integers come back as floats.** `TYPE_INT` in, `TYPE_FLOAT` out. That is why
the typed accessors exist — `get_int()` makes a value's type independent of
whether it has been through a file yet.

**`JSON.stringify()` does not reject non-JSON types, it mangles them.**
`Vector2(1, 2)` is written as the *string* `"(1.0, 2.0)"` and returns as a
String, with no error at any point. `save_to_file()` therefore validates
recursively and refuses to write, returning `ERR_INVALID_DATA` — a save file
that loads without complaint and is silently wrong is worse than no save.

---

## Extending Without Breaking the Architecture

**Adding a level.** Put it under your own directory, point `INITIAL_SCENE` at
it or call `SceneLoader.load_scene()`. Nothing else changes.

**Extending the player.** Either attach a child node that reads the player's
public state, or write a script that `extends` `player.gd` and overrides
`_handle_extra_input()`. Do not edit `player.gd` — you will fight every template
update.

**Interaction.** `player.gd` ships an `InteractionRay` (disabled, so it costs
nothing) and `get_interaction_target()`, which tells you *what* you are looking
at and takes no position on what should happen next. The four-line hookup is in
that method's docstring. Deciding what "interacting" means is a game decision.

**Per-object shader variation.** Use `set_instance_shader_parameter()`. Do not
fork a shader to change one number — see
[PSX_PIPELINE](psx_pipeline.md#per-object-variation).

**A new global look parameter.** Add it to `psx_look_preset.gd`, add the
`global uniform` to the shaders that use it, add a row to the `SLIDERS` or
`TOGGLES` table in `debug_overlay.gd`. Three edits, and the overlay picks it up
automatically.

**A new autoload.** Put the script beside the system it serves, register it, and
add a row to [`autoload/README.md`](../autoload/README.md) with a one-line
reason for its position.

**Stripping the debug overlay.** It frees itself in release builds already
(`debug_builds_only`). To remove it entirely, clear `DEBUG_OVERLAY_SCENE` in
`bootstrap.gd` and delete `ui/debug/`. Nothing else references that directory.
