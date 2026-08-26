## post_process_stack.gd  --  attached to post_process_stack.tscn.
##
## WHAT: The screen-space PSX passes, in order: framebuffer dither/quantise,
##       then optional CRT emulation.
##
## RESPONSIBLE FOR: owning the pass nodes and switching them on and off to
##       match PSXLook. It holds no look values of its own -- PSXLook is the
##       single source of truth, and this node is the hands.
##
## -- WHY THIS ARCHITECTURE AND NOT CompositorEffect -------------------------
## This template is locked to the Compatibility renderer, because that is the
## only rendering method Godot 4 supports for web export. CompositorEffect is a
## RenderingDevice feature and does not exist under Compatibility. The portable
## approach -- the only one that survives an HTML5 build -- is a full-rect
## ColorRect on a CanvasLayer running a canvas_item shader that samples
## `hint_screen_texture`.
##
## -- THE BackBufferCopy IS LOAD-BEARING. DO NOT DELETE IT. ------------------
## Measured on Godot 4.7.1, Compatibility/GLES3, in this project:
##
##   DitherPass + CRTPass as plain siblings  -> CRT samples the PRE-dither
##                                              frame and overwrites the
##                                              dither entirely. Flat sky, no
##                                              Bayer pattern, no quantisation.
##   DitherPass + BackBufferCopy + CRTPass   -> correct. CRT samples the
##                                              dithered frame.
##
## Both ColorRects read `hint_screen_texture`, which resolves to the
## backbuffer. Godot captures that backbuffer once for the draw group, so
## without an explicit re-capture between them, both passes see the same
## pre-post-process image and the last one drawn wins.
##
## A separate CanvasLayer per pass also works, because Godot inserts a copy at
## each layer boundary. That was rejected here only because it spreads one
## coherent effect chain across several nodes for no gain. SubViewport chaining
## is NOT required -- it was considered and is unnecessary.
##
## -- ADDING A THIRD PASS ----------------------------------------------------
## Append: another BackBufferCopy, then your ColorRect. Every screen-reading
## pass after the first needs a copy in front of it. There is no way to detect
## a missing one at runtime; it just silently renders the wrong thing.

extends CanvasLayer

@onready var dither_pass: ColorRect = $DitherPass
@onready var backbuffer: BackBufferCopy = $BackBufferCopy
@onready var crt_pass: ColorRect = $CRTPass


func _ready() -> void:
	PSXLook.look_changed.connect(_sync_to_look)
	_sync_to_look()


## Mirrors PSXLook's pass toggles onto node visibility. A hidden ColorRect is
## not drawn at all, so a disabled pass costs nothing -- this is a real toggle,
## not a shader branch.
func _sync_to_look() -> void:
	dither_pass.visible = PSXLook.dither_enabled
	crt_pass.visible = PSXLook.crt_enabled
	# Nothing reads the backbuffer after the dither pass unless CRT is on, so
	# skip the full-screen copy when it would be thrown away. On a web build
	# that is a real saving, not a micro-optimisation.
	backbuffer.visible = PSXLook.crt_enabled
