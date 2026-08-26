## psx_look_preset.gd
##
## WHAT: A saveable profile describing one complete PSX look, in one Resource.
##
## RESPONSIBLE FOR: being the single definition of "what a look is". PSXLook
##       stores its live state as one of these, so adding a look parameter
##       means editing this file and the shaders, not three places.
##
## NOTE: most of these become global shader parameters, but the Post-Processing
##       toggles do not -- they are node visibility, watched by
##       ui/post_process/post_process_stack.gd. They live here anyway, because
##       a "look" that cannot say whether the CRT is on is not a whole look,
##       and splitting the definition across two places is exactly the
##       confusion this resource exists to prevent.
##
## WHY IT EXISTS: presets need to be authored in the inspector, saved as .tres,
##       swapped at runtime, and shipped with the template. A Resource does all
##       of that for free. The alternative -- a Dictionary of magic string keys
##       -- gives up type safety and inspector editing for nothing.
##
## NOTE ON fog_color: exported as a Color so the inspector shows a colour
##       picker, but the shader global `psx_fog_color` is a vec3. PSXLook does
##       the conversion when it pushes. Alpha is ignored.

class_name PSXLookPreset
extends Resource

@export_group("Vertex Jitter")
## Master toggle for vertex snapping. Off = smooth modern vertex positions.
@export var jitter_enabled: bool = true
## The grid vertices snap to, in pixels. Lower values snap harder.
## 320x240 matches the native framebuffer; halving it doubles the wobble.
@export var snap_resolution: Vector2 = Vector2(320, 240)

@export_group("Texturing")
## 0 = perspective-correct (modern), 1 = full PS1 affine warp.
@export_range(0.0, 1.0) var affine_strength: float = 1.0

@export_group("Colour")
## Quantisation levels per channel. 32 = the PS1's 5-bit-per-channel output.
## 256 is effectively off.
@export_range(2.0, 256.0) var color_depth: float = 32.0
## Ordered dither intensity. 0 = hard banding, 1 = full hardware-style dither.
@export_range(0.0, 1.0) var dither_strength: float = 1.0

@export_group("Distance Fade")
@export var fog_enabled: bool = true
@export var fog_color: Color = Color(0.05, 0.05, 0.08)
## Distance at which the fade begins, in metres.
@export var fog_near: float = 6.0
## Distance at which geometry is fully faded out. Pair this with the camera's
## far plane so geometry dissolves instead of popping.
@export var fog_far: float = 24.0

@export_group("Post-Processing")
## Whether the full-screen dither/quantise pass runs. Toggling this off is not
## the same as dither_strength = 0: this skips the pass entirely, while a zero
## strength still quantises (with hard banding instead of dithering).
@export var dither_enabled: bool = true
## Whether the CRT pass runs. Off in every preset this template ships, because
## the CRT filter is a garnish over the PSX look, not part of it.
@export var crt_enabled: bool = false
