# PSX Rendering Pipeline

How this template reproduces PlayStation 1 rendering, and why each decision is
what it is. Everything here was measured on **Godot 4.7.1 stable, Compatibility
(GLES3)** unless stated otherwise.

---

## Renderer Decision (Locked)

**`gl_compatibility`, on desktop, mobile and web. This is not revisitable.**

Godot 4's web export supports only the Compatibility rendering method, running
on WebGL 2.0. Forward+ and Mobile are built around modern low-level graphics
APIs and are unavailable on web until WebGPU support lands. Since web is this
template's primary export target, the renderer choice follows from it.

### What that rules out

**`CompositorEffect` is useless here.** It is a `RenderingDevice` feature and
does not exist under Compatibility. Any tutorial that post-processes via
`CompositorEffect` is describing Forward+ and does not apply.

The portable approach — and the only one that survives an HTML5 build — is the
classic one: a full-rect `ColorRect` on a `CanvasLayer`, running a
`canvas_item` shader that samples `hint_screen_texture`. That is what
`ui/post_process/post_process_stack.tscn` is.

### Verified consequences

| Thing | Behaviour under Compatibility | Where it matters |
|---|---|---|
| `RenderingServer.global_shader_parameter_get()` | **Editor-only.** At runtime GLES3 refuses it and returns null. Global shader params are write-only in a running game. | `psx/look/psx_look.gd`, `ui/debug/debug_overlay.gd` |
| Two sibling screen-reading passes | Do **not** chain. Both sample the same backbuffer; the last one drawn wins. | `ui/post_process/post_process_stack.tscn` |
| Shadows on a light | No meaningful energy penalty on 4.7.1 — see [Lighting Model](#lighting-model). | `levels/test/test_room.tscn` |
| `instance uniform` | Works. Verified resolving on all three spatial shaders. | `psx/shaders/*.gdshader` |

---

## Internal Resolution and Scaling

| Setting | Value |
|---|---|
| `display/window/size/viewport_width` / `_height` | `320` / `240` |
| `window_width_override` / `_height_override` | `1280` / `960` |
| `window/stretch/mode` | `viewport` |
| `window/stretch/aspect` | `keep` |
| `window/stretch/scale_mode` | `integer` |
| `rendering/scaling_3d/mode` | `5` (`SCALING_3D_MODE_NEAREST`) |
| `textures/canvas_textures/default_texture_filter` | `0` (Nearest) |
| `textures/default_filters/use_nearest_mipmap_filter` | `true` |
| `textures/default_filters/anisotropic_filtering_level` | `0` (Disabled) |
| `anti_aliasing/quality/msaa_2d` / `msaa_3d` | `0` (Disabled) |

The last four are already the engine defaults. They are written out explicitly
anyway so the intent is visible in `project.godot` and survives a future change
of engine defaults.

### Two measured gotchas

**`get_viewport().size` is not the framebuffer size.** It reports the *window*
size. Measured with the settings above:

```
window size        : (1280, 960)
get_viewport().size: (1280, 960)   <- the window
get_visible_rect() : (320, 240)    <- the framebuffer
final transform    : scale 4.0
```

Anything computing in framebuffer space — a crosshair, a screen-space ray, a UI
offset — must use `get_viewport().get_visible_rect().size`.

**`InputEventMouseMotion.relative` is divided by the content-scale factor.**
Measured by pushing an event through the real transform path:

| Pushed | Received |
|---|---|
| `relative = (100, 0)` | **`(25, 0)`** |
| `screen_relative = (100, 0)` | `(100, 0)` |

The factor is 4 at 1280x960. With `scale_mode = integer` it changes in **whole
steps** when the window is resized or fullscreened — 3x, 4x, 5x. Mouse look
built on `relative` therefore has sensitivity that visibly jumps on resize,
which is close to impossible to diagnose from the symptom. Use
`screen_relative`, which is unscaled. `player/player.gd` does.

---

## Texture Import Defaults

Set in Project Settings → Import Defaults → Texture, stored in `project.godot`
under `[importer_defaults]`. They apply to **any** texture dropped into a
project made from this template, so assets are correct on arrival without
per-file fiddling.

```ini
[importer_defaults]

texture={
"compress/mode": 0,
"detect_3d/compress_to": 0,
"mipmaps/generate": true,
"process/fix_alpha_border": false
}
```

| Setting | Value | Why |
|---|---|---|
| `compress/mode` | `0` — Lossless | VRAM block compression is built for large photographic textures. On a 64x64 hand-made texture it produces visible colour smearing, and the storage saved is irrelevant at this size. |
| `detect_3d/compress_to` | `0` — Disabled | **The important one.** By default Godot watches for a texture being used in 3D and *silently re-imports it as VRAM Compressed*. You import a crisp texture, use it on a wall, and it degrades on its own. Disabling the detector stops that. |
| `mipmaps/generate` | `true` | Paired with `use_nearest_mipmap_filter`. Without mipmaps, a tiled floor texture aliases into shimmering noise at distance — which reads as a bug, not as retro. |
| `process/fix_alpha_border` | `false` | Bleeds colour into fully transparent pixels to help bilinear filtering. This pipeline filters nearest, so the fix is unnecessary and it rewrites pixels you authored. |

**Filtering is not an import setting in Godot 4.** It lives in project settings
(the table above) and in per-shader sampler hints (`filter_nearest_mipmap` in
the spatial shaders). Do not go looking for it in the Import dock.

### Texture budget

64x64 for individual textures, 128x128 for atlases. This is a discipline, not a
technical limit: it is the size at which the resulting chunkiness reads as
deliberate rather than as a mistake.

The payoff is real. The complete test environment — four textures, all meshes,
all scenes, all scripts — exports to a **117 KB** `.pck`.

---

## Shader System

Exactly six shaders. That number is a constraint, not a coincidence: every new
material combination the Compatibility renderer meets compiles on first use and
can stutter, so shader count is directly a performance budget.

**If you want a seventh, you have probably made per-object variation the
shader's problem when it should be an `instance uniform`'s problem.**

| File | Type | Purpose |
|---|---|---|
| `psx/shaders/psx_opaque.gdshader` | spatial | All opaque world geometry. The workhorse. |
| `psx/shaders/psx_cutout.gdshader` | spatial | Alpha-scissor geometry: railings, foliage, grates. |
| `psx/shaders/psx_billboard.gdshader` | spatial | Camera-facing sprite quads. |
| `psx/shaders/psx_dither.gdshader` | canvas_item | Framebuffer quantisation + ordered dither. |
| `psx/shaders/psx_crt.gdshader` | canvas_item | Optional display emulation. Off by default. |
| `psx/shaders/psx_ui.gdshader` | canvas_item | Optional palette clamp for Control nodes. |

Each file carries a comment block explaining its technique. Read those before
changing one — they exist so the next person learns rather than copies.

### The four spatial techniques

**Vertex snapping.** The PS1's GTE had no floating-point vertex output; screen
positions were integers, so vertices jump between whole pixels as the camera
moves. Reproduced by doing the MVP transform by hand, dividing by `w` to reach
NDC, rounding `xy` onto a grid the size of the framebuffer, and multiplying back
by `w` so the hardware's own perspective divide lands where we chose. Writing
`POSITION` overrides Godot's transform; `VERTEX` and `NORMAL` are left alone, so
lighting stays stable while the silhouette jitters — which is what the real
hardware did.

**Affine texture mapping.** The PS1 interpolated UVs linearly in *screen* space
with no perspective correction, making textures swim on large polygons at
shallow angles. Modern GPUs always interpolate perspective-correctly and there
is no switch. The trick: a varying premultiplied by `w` survives
perspective-correct interpolation as a screen-linear value, because the
rasteriser's own `1/w` weighting cancels the `w` you baked in. Pass `UV * w` and
`w`, divide one by the other in `fragment()`, then blend toward the built-in
`UV` so the artefact is a dial rather than a switch.

> **Affine severity scales with polygon size, and this is the single easiest
> thing to get wrong.** Two triangles covering a 40x80 m floor collapse into
> unreadable horizontal bands. 0.5 m polygons hide the effect entirely. **Around
> 2 m polygons** — roughly PS1-era floor tessellation — gives the authentic
> shear. `levels/test/test_room.tscn` tessellates its floor to exactly that.

**Vertex lighting.** `render_mode vertex_lighting, specular_disabled`. The PS1
did Gouraud shading per vertex and had no specular highlights.

**Colour quantisation.** Applied to the sampled albedo, reproducing the PS1's
15-bit texture memory. Quantisation of the finished *frame* is a separate
concern and belongs to `psx_dither.gdshader` on the post-process layer.

### Post-processing, and the node that must not be deleted

```
PostProcessStack (CanvasLayer, layer 100)
├── DitherPass      (ColorRect, full rect, psx_dither.gdshader)
├── BackBufferCopy  (copy_mode = Viewport)      <-- LOAD-BEARING
└── CRTPass         (ColorRect, full rect, psx_crt.gdshader, off by default)
```

Measured A/B:

| Arrangement | Result |
|---|---|
| DitherPass + CRTPass as plain siblings | **Broken.** CRT samples the pre-dither frame and overwrites the dither entirely. Flat sky, no Bayer pattern. |
| DitherPass + **BackBufferCopy** + CRTPass | Correct. CRT samples the dithered frame. |
| One CanvasLayer per pass | Also correct — Godot inserts a copy at each layer boundary. |

Both ColorRects read `hint_screen_texture`, which resolves to the backbuffer.
Godot captures that backbuffer once per draw group, so without an explicit
re-capture between them both passes see the same image.

**SubViewport chaining is not required.** It was considered and is unnecessary.

Adding a third screen-reading pass means adding another `BackBufferCopy` in
front of it. There is no way to detect a missing one at runtime — it silently
renders the wrong thing.

---

## Shader Globals

Declared centrally in Project Settings → Shader Globals (`[shader_globals]` in
`project.godot`), read by shaders with the `global uniform` keyword, and set at
runtime through `PSXLook`. Every one is consumed by at least one shader; there
are no dead parameters.

| Global | Type | Default | Purpose |
|---|---|---|---|
| `psx_snap_resolution` | `vec2` | `(320, 240)` | Vertex snapping grid. Lower snaps harder. |
| `psx_affine_strength` | `float` | `1.0` | 0 = perspective-correct, 1 = full affine warp. |
| `psx_color_depth` | `float` | `32.0` | Quantisation levels per channel. 32 = the PS1's 5-bit output. |
| `psx_dither_strength` | `float` | `1.0` | Ordered dither intensity. |
| `psx_fog_enabled` | `bool` | `true` | Distance fade toggle. |
| `psx_fog_color` | `vec3` | `(0.05, 0.05, 0.08)` | Fade colour. |
| `psx_fog_near` | `float` | `6.0` | Where the fade begins, in metres. |
| `psx_fog_far` | `float` | `24.0` | Where geometry is fully faded. |
| `psx_jitter_enabled` | `bool` | `true` | Master toggle for vertex snapping. |

### Per-object variation

Two `instance uniform`s, so you never fork a shader to change one number:

```gdscript
mesh_instance.set_instance_shader_parameter("psx_instance_affine", 0.0)
mesh_instance.set_instance_shader_parameter("psx_instance_emission", Color(1, 0.4, 0.1, 0.6))
```

### The CRT pass uses local uniforms, not globals

Nothing else in the pipeline needs to know a CRT filter exists. `PSXLook`
toggles the pass by node visibility; its `curvature`, `scanline_strength` and
`vignette_strength` are ordinary material uniforms.

---

## Global PSX Look Controls

`PSXLook` (autoload, script at `psx/look/psx_look.gd`) owns the runtime value of
every `psx_*` global and pushes it to the rendering server. It has **no
knowledge of any game, level or UI** — it sets rendering parameters, and that is
all it does.

```gdscript
PSXLook.affine_strength = 0.5
PSXLook.apply_preset_path(PSXLook.PRESET_EXTREME)
PSXLook.reset_to_default()
```

Live state is stored as a `PSXLookPreset` resource rather than loose fields, so
there is exactly one definition of what a look consists of. Adding a look
parameter means editing `psx_look_preset.gd` and the shaders — not three places.

### Shipped presets

| Preset | Jitter | Snap | Affine | Colour | Dither | Fog |
|---|---|---|---|---|---|---|
| `clean` | off | 320x240 | 0.0 | 256 | off | 20 → 60 |
| `authentic` | on | 320x240 | 1.0 | 32 | 1.0 | 6 → 24 |
| `extreme` | on | 160x120 | 1.0 | 8 | 1.0 | 3 → 12 |

`clean` is the control case — switch to it to see what the PSX effects are
actually doing. `authentic` is calibrated to real PS1 output and is the default.
`extreme` goes past what the hardware did, for demonstrating range and
stress-testing a scene.

Measured: switching `authentic` → `extreme` takes the framebuffer from **246
distinct levels per channel to 8**. Toggling vertex snapping at a 96x72 grid
moves **36.8% of the frame**.

Every value is written out explicitly in each `.tres`, even where it matches the
script default, so a preset file states the whole look rather than inheriting
half of it silently.

---

## Lighting Model

Baked vertex colours plus one real-time shadowed light. The opaque and cutout
shaders multiply `COLOR` into albedo, so vertex colours are the base lighting;
the real-time light adds the moving part.

### The shadow-brightness warning does not reproduce on 4.7.1

Godot issue #90259 reports that enabling shadows under Compatibility costs
roughly **5x** brightness, requiring compensation. Measured in
`levels/test/test_room.tscn` with an `OmniLight3D`, as mean scene luminance:

| Configuration | Mean luma | vs baseline |
|---|---|---|
| energy 1.0, shadows **off** | 0.1543 | ×1.00 |
| energy 1.0, shadows **on** | 0.1791 | **×1.16** |
| energy 4.0, shadows on | 0.3231 | ×2.09 |
| energy 6.0, shadows on | 0.3810 | ×2.47 |

Enabling shadows made the room **16% brighter, not 5x darker**. Applying the
compensation the warning implies would produce a blown-out white room.

**The method still holds even though the number does not: enable shadows first,
then tune.** Tuning with shadows off and enabling them afterwards means tuning
against a different renderer path. And re-measure before trusting these figures
on a different Godot version — the whole point of writing them down is that they
are checkable.

### Use an OmniLight in an enclosed space

A `DirectionalLight3D` in a sealed room is blocked entirely by its own ceiling
shadow. The test room uses an `OmniLight3D` with ambient from a
`WorldEnvironment`.

---

## Performance Philosophy

The PSX aesthetic is cheap by construction. Do not spend the savings.

- **Shader count is a budget.** Compatibility compiles shaders on first use, so
  every new material combination is a potential stutter the first time a player
  walks into a room. Six shaders, parameterised — not sixty variants.
- **A disabled pass should cost nothing.** The post-process stack toggles passes
  by node visibility, and skips the `BackBufferCopy` entirely when the CRT pass
  is off, rather than branching inside a shader that still runs.
- **Texture memory is nearly free at this budget; audio will dominate.** Use OGG
  Vorbis and keep concurrent voices low.
- **Measure before believing.** Two of the three headline claims this document
  inherited turned out not to hold on 4.7.1. Both were caught by measuring, and
  both are recorded above with their numbers so the next person can re-check
  rather than re-trust.
