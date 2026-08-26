# Development

Getting a game out of this template, and keeping it working.

---

## Requirements

| | |
|---|---|
| **Godot** | 4.7 or newer, **standard build** (not .NET) |
| **Renderer** | Compatibility. Already set; do not change it. |
| **Export templates** | Required only when you export. Editor → Manage Export Templates. |
| **Language** | GDScript only. C# projects cannot be exported to web in Godot 4. |
| **Blender** | Optional, for assets. 1 unit = 1 metre. |

Keep the editor on Compatibility. Previewing lighting in Forward+ and assuming
Compatibility will match is a reliable way to waste an afternoon — it will not
match.

---

## Creating a Game From the Template

1. **Use this template → Create a new repository.** Do not fork; games are
   independent projects, not branches of the framework.
2. Clone it and open in Godot 4.7+. Let the import finish.
3. Press **F5**. You should land in the PSX test room, in control of the player.
4. Make your first level somewhere under a directory of your own.
5. Change **one line** in `core/scenes/bootstrap.gd`:

   ```gdscript
   const INITIAL_SCENE: String = "res://levels/my_game/first_level.tscn"
   ```

6. Delete `levels/test/` when you no longer need it. Nothing in the framework
   references it — that is enforced by the
   [dependency rule](architecture.md#the-one-rule).

That is the entire integration step. Everything in `core/`, `psx/`, `player/`
and `ui/` is game-agnostic and needs no edits.

### What to change next, roughly in order

| Want | Where |
|---|---|
| Different movement feel | `@export`s on `player/player.tscn` — all of them, no magic numbers in code |
| Different look | `PSXLook.apply_preset()`, or author your own `PSXLookPreset` `.tres` |
| Your own textures | Drop them in. Import defaults are already correct — see [PSX_PIPELINE](psx_pipeline.md#texture-import-defaults) |
| A HUD | Put it under `Bootstrap/UILayer` so it is post-processed with the world |
| Persistence | `GameState.save_to_file()` / `load_from_file()` |
| Interaction | Enable the player's `InteractionRay`, then `get_interaction_target()` |

---

## Running the Test Environment

**F5.** You should get: loading screen → test room → player in control.

| Key | Does |
|---|---|
| `WASD` / arrows | Move |
| `Shift` | Sprint |
| `Ctrl` / `C` | Crouch |
| `Space` | Jump |
| `Escape` | Release the mouse |
| **`F3`** | Debug overlay — live PSX sliders |
| **`F2`** | Cycle PSXLook presets (test room only) |

Input is bound by **`physical_keycode`**, so WASD stays under the same fingers
on AZERTY (ZQSD) and Dvorak.

### What the test room is proving

It is a technical validation scene, not a game level, and it must never become
one. Each element is there to expose one thing:

| Element | Proves |
|---|---|
| Checkerboard floor, ~2 m polygons, shallow angle | Affine texture mapping. A regular grid is the only pattern where warped-vs-correct is obvious at a glance. |
| Row of cubes receding from spawn | Vertex snapping and distance fade on flat faces. |
| Row of capsules | Quantisation and vertex-lighting banding, which flat boxes hide. |
| Slowly rotating tilted cube | That snapping happens in *screen space* and is not baked into the mesh. |
| Alpha-cutout grate | `psx_cutout.gdshader` binary transparency. |
| Billboard lamp | `psx_billboard.gdshader` camera-facing quad. |
| Shadowed `OmniLight3D` + `WorldEnvironment` | The lighting model, at a tuned energy. |

---

## Validation Checklist

Run this after any change to the render pipeline. Every item was verified on
Godot 4.7.1, Compatibility/GLES3, before this document was written.

**Console**

- [ ] Reimport from a deleted `.godot/`: zero errors, zero warnings.
- [ ] F5 boot: zero errors, zero warnings. *A phase is not done if the console
      is dirty.*

**Look**

- [ ] Cubes and capsules snap and jitter as you move.
- [ ] The floor visibly shears its texture at a shallow angle.
- [ ] The framebuffer is dithered and colour-quantised.
- [ ] Distant geometry fades into fog rather than popping.
- [ ] The shadowed light reads correctly — not blown out, not black.
- [ ] `F3` opens; dragging a slider changes rendering **live**.
- [ ] `F2` cycles clean → authentic → extreme and all three look distinct.

**Runtime**

- [ ] A deliberately bad path in `SceneLoader.load_scene()` produces one clean
      readable error, not a crash and not engine spam.
- [ ] Loading screen appears during a load and disappears after.
- [ ] `Escape` releases the mouse; clicking recaptures it.

---

## Web Build

Web is the primary export target. **Export early and often** — do not leave the
first web build until the end, when every problem arrives at once.

### Building

```
Project → Export → Web → Export Project
```
or headless:
```bash
godot --headless --path . --export-release "Web" builds/web/index.html
```

`export_presets.cfg` **is committed** — a template whose export settings do not
travel with it is not a template. It is safe to commit because the Web preset
carries no credentials. Android and iOS presets *do* store keystore paths and
passwords; if you add one, keep secrets in a Godot editor setting or re-ignore
the file.

### Serving it

`file://` will not work — wasm needs HTTP. Locally:

```bash
python -m http.server 8000 --directory builds/web
```

On a real host, **ensure Brotli or gzip is enabled**. The Godot wasm runtime is
~40 MB uncompressed and compresses very well; this is frequently the difference
between a five-second and a forty-second first load.

Your own payload will be tiny — this is where the PSX aesthetic pays for itself.
The complete test environment exports to a **117 KB** `.pck`. Audio will
dominate your asset size, not textures. Use OGG Vorbis.

### Threads and COOP/COEP

The shipped preset has **`thread_support = false`** deliberately.

Thread support requires the host to send two headers so the browser will enable
`SharedArrayBuffer`:

```
Cross-Origin-Opener-Policy: same-origin
Cross-Origin-Embedder-Policy: require-corp
```

itch.io has a checkbox for this. Many static hosts — including basic GitHub
Pages configurations — cannot send custom headers, and **a threaded build on a
host without the headers fails at load**, which is the worst possible failure
mode for a jam or a portfolio link. Non-threaded works everywhere at some
performance cost.

Ship non-threaded unless you know where it is hosted and have verified the
headers arrive.

### The custom HTML shell

`web/shell.html`, wired into the preset. It is deliberately unstyled — no title
card, no theming — because a template should not ship anybody's art direction.
Everything in it is infrastructure:

- **A click-to-start gate.** Not decoration. Browsers refuse to start an
  `AudioContext`, and refuse pointer lock, until the page has seen a real user
  gesture. Godot's default shell has no gate, so a build made with it launches
  silent and cannot capture the mouse until the player happens to click.
  `player/player.gd` documents the same constraint from the engine side; this is
  the other half of that fix.
- **Honest progress**, in real bytes rather than an indeterminate bar.
- **A Safari warning.** Safari has known WebGL 2.0 issues that Chromium and
  Firefox do not; detect and say so rather than rendering wrong.
- **`image-rendering: pixelated`** on the canvas, so the browser never smooths
  the upscale.

Style it when you style your game. Keep the `$GODOT_*` placeholders.

### Verified so far

On Godot 4.7 stable, served over local HTTP, loaded in a Chromium browser:

```
Godot Engine v4.7.stable.official
OpenGL API OpenGL ES 3.0 (WebGL 2.0 (OpenGL ES 3.0 Chromium)) - Compatibility
Build configuration: Emscripten 4.0.20, single-threaded, no GDExtension support.
```

The export produces a complete build, the wasm loads and compiles, the engine
initialises **on WebGL 2.0 under Compatibility**, `startGame()` resolves, and
the shell's gate reaches "ready → CLICK TO START". The renderer lock holds on
web, which is the thing that most needed proving.

**Not yet verified: a rendered frame in a browser.** The automated harness used
here runs the page hidden, and browsers throttle `requestAnimationFrame` to zero
on hidden documents, so Godot's main loop never ticks. Work through the
checklist below on a real visible browser window before shipping.

### Web testing checklist

- [ ] Cold load in Chrome, Edge and Firefox on your target OSes.
- [ ] Cold load with the browser cache cleared — the real first-time experience.
- [ ] Audio starts correctly after the click-to-start gate.
- [ ] Fullscreen toggles and does not break integer viewport scaling.
- [ ] Pointer lock captures on click and releases on `Escape`.
- [ ] `GameState` persistence survives a page reload.
- [ ] Alt-tab / backgrounding does not corrupt state or audio.
- [ ] Framerate holds in your heaviest room.
- [ ] No visible hitch from shader compilation on first entering a room.
- [ ] It works embedded in an iframe (itch.io embeds by default).

On shader compilation hitches: Compatibility compiles shaders on first use, so
every new material combination can stutter once. Keeping to the six shaders and
parameterising them — rather than authoring variants — is the mitigation, which
is why the shader count is a rule and not a suggestion.

---

## Branching and Versioning

**For the template itself:** `main` is always in a state where a fresh clone
boots to the test room with a clean console. Changes land as one commit per
coherent unit of work, with what was measured recorded in the commit body.

**For a game made from it:** it is your repository — branch however you like.
There is no upstream merge path, and that is intentional. Take the template as a
starting point and own it; do not try to track this repo as a dependency.

---

## Regenerating the Test Textures

The four 64x64 test textures are generated, not drawn, so the repository carries
no third-party art and the assets are reviewable as a diff:

```bash
godot --headless --path . --script tools/generate_test_textures.gd
```

Output is deterministic — the RNG is seeded — so re-running produces no diff
unless the generator changed.

---

## Conventions

- **GDScript only.** No C#, no GDExtension, no third-party addons.
- **Every file gets a header comment** stating what it is, what it is
  responsible for, and — where non-obvious — why it exists.
- **Static typing.** Type parameters and returns.
- **Prefer boring.** No clever metaprogramming, no signal spaghetti, no
  premature abstraction. If a straightforward script solves it, write it.
- **Do not re-export what the base class already exposes.** `CharacterBody3D`
  already puts `floor_max_angle` in the inspector; duplicating it into an
  `@export` creates two sources of truth for one value.
- **Measure before believing.** Two of the inherited assumptions about this
  engine version turned out to be wrong, and both were caught by measuring. Any
  claim in these docs with a number attached was checked; re-check them on a new
  Godot version rather than trusting them.
