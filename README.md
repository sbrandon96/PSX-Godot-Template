# PSX-Godot-Template

A reusable, deliberately boring foundation for PSX-style 3D games in
**Godot 4.7+**.

This repository is a **GitHub Template**, not a game. It encodes the technical
decisions of PSX-era rendering — internal resolution, renderer choice, texture
filtering, shader pipeline, web export — so that each new project starts from a
known-good, runnable baseline instead of a blank scene.

Horror, combat, inventory, story and level content are **not** part of this
template. They belong to the games built from it.

---

## Quick start

1. **Use this template** → **Create a new repository**. (Do not fork — games are
   independent projects, not branches of the framework.)
2. Clone it, open in Godot 4.7+, let the import finish.
3. Press **F5**.

You should land in the PSX test room, in control of the player, with a clean
console. Press **F3** for the debug overlay and drag a slider — the rendering
changes live. Press **F2** to cycle look presets.

Then change one line in `core/scenes/bootstrap.gd`:

```gdscript
const INITIAL_SCENE: String = "res://levels/my_game/first_level.tscn"
```

That is the entire integration step. Everything in `core/`, `psx/`, `player/`
and `ui/` is game-agnostic and needs no edits.

---

## What you get

| | |
|---|---|
| **Six PSX shaders** | Vertex snapping, affine texture mapping, vertex lighting, colour quantisation, distance fade, ordered dither, optional CRT |
| **`PSXLook`** | One place that owns the whole look, with `clean` / `authentic` / `extreme` presets and a `look_changed` signal |
| **Bootstrap architecture** | A persistent root with documented layer ordering, so level swaps do not tear down your UI |
| **Threaded scene loading** | Non-blocking, with progress signals, readable failures, and a loading screen |
| **First-person controller** | Walk, sprint, crouch with a ceiling check, jump, mouse look — all tuning exposed, no game logic baked in |
| **Debug overlay** | F3. Live sliders for every `psx_*` global, performance counters, strips itself from release builds |
| **Web export** | Preset committed, custom shell with the click-to-start gate browsers require |
| **Test environment** | A validation scene that proves every subsystem, and a script that regenerates its textures |

---

## Locked technical decisions

| Parameter | Decision |
|---|---|
| Engine | Godot 4.7+ |
| Renderer | **Compatibility (`gl_compatibility`) — locked, not revisitable** |
| Language | GDScript only |
| Primary export | Web (HTML5 / WebGL 2.0) |
| Target hardware | Desktop browsers. Mobile explicitly out of scope. |
| Internal resolution | 320x240, point-scaled, integer scaling |
| Texture budget | 64x64 individual, 128x128 atlas |
| Lighting model | Baked vertex colours + one real-time shadowed light |

**Why the renderer is locked:** Godot 4's web export supports only the
Compatibility method on WebGL 2.0. Forward+ and Mobile are unavailable on web.
Changing the renderer invalidates the entire toolset — including making
`CompositorEffect`-based post-processing tutorials inapplicable.

---

## Controls

| Key | Does |
|---|---|
| `WASD` / arrows | Move (bound by physical key, so AZERTY gets ZQSD) |
| `Shift` / `Ctrl` or `C` / `Space` | Sprint / crouch / jump |
| `Escape` | Release the mouse |
| **`F3`** | Debug overlay |
| **`F2`** | Cycle look presets (test room only) |

---

## Documentation

| | |
|---|---|
| [`docs/architecture.md`](docs/architecture.md) | Layout, the dependency rule, autoload order, boot sequence, scene loading, game state |
| [`docs/psx_pipeline.md`](docs/psx_pipeline.md) | Renderer lock, resolution, import defaults, the six shaders, shader globals, lighting, performance |
| [`docs/development.md`](docs/development.md) | Making a game from this, the validation checklist, the web build, conventions |
| [`autoload/README.md`](autoload/README.md) | Why singleton scripts do not live in `autoload/` |

Everything in these docs with a number attached was **measured on Godot 4.7.1,
Compatibility/GLES3** — not assumed. Several widely-repeated claims about this
engine version turned out not to hold, and the measurements are written down so
you can re-check them rather than re-trust them. Three worth knowing before you
start:

- `RenderingServer.global_shader_parameter_get()` is **editor-only**; global
  shader parameters are write-only in a running game.
- `InputEventMouseMotion.relative` is **divided by the content-scale factor**,
  so mouse sensitivity built on it jumps when the window is resized. Use
  `screen_relative`.
- Two sibling `hint_screen_texture` passes **do not chain** — the second
  discards the first unless a `BackBufferCopy` sits between them.

---

## Requirements

Godot **4.7 or newer, standard build** (not .NET — C# cannot export to web in
Godot 4). No addons, no plugins, no GDExtension. Export templates are needed
only when you export.

---

## Licence

MIT. See [`LICENSE`](LICENSE).

The test textures are generated procedurally by
[`tools/generate_test_textures.gd`](tools/generate_test_textures.gd), so this
repository contains no third-party art and no licensing ambiguity.
