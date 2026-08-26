## psx_look.gd  --  registered as the `PSXLook` autoload.
##
## WHAT: The single runtime owner of every `psx_*` global shader parameter.
##
## RESPONSIBLE FOR: holding the current look, pushing it to the rendering
##       server, and announcing changes. Nothing else.
##
## WHY IT EXISTS: the PSX look is defined by roughly nine numbers that six
##       shaders all read. Without one owner those numbers get duplicated into
##       per-material overrides and drift apart, and there is no way to change
##       the look of a whole scene at once. Global shader parameters solve the
##       shader side; this node is the GDScript side of the same idea.
##
## WHAT IT MUST NEVER DO: know about a game, a level, a player, or a UI. It sets
##       rendering parameters. If you are tempted to add "fade the fog when the
##       player enters the basement", that belongs to the basement.
##
## LIVE STATE: kept as a PSXLookPreset instance rather than as loose fields, so
##       there is exactly one definition of what a look consists of. See
##       psx_look_preset.gd.
##
## VERIFIED GOTCHA (Godot 4.7.1, Compatibility/GLES3): the inverse call,
##       RenderingServer.global_shader_parameter_get(), is EDITOR-ONLY. At
##       runtime the GLES3 driver refuses it with "This function should never be
##       used outside the editor" and returns null. So global shader parameters
##       are write-only in a running game, and this node's `_current` is the
##       only readable source of truth for them. A debug overlay must read
##       PSXLook, never the RenderingServer.
##
## Usage:
##     PSXLook.affine_strength = 0.5
##     PSXLook.apply_preset(preload("res://psx/look/preset_extreme.tres"))
##     PSXLook.reset_to_default()

extends Node

## Emitted after any parameter changes and has been pushed to the renderer.
## Carries no payload on purpose -- listeners re-read whatever they display.
signal look_changed

const PRESET_CLEAN: String = "res://psx/look/preset_clean.tres"
const PRESET_AUTHENTIC: String = "res://psx/look/preset_authentic.tres"
const PRESET_EXTREME: String = "res://psx/look/preset_extreme.tres"

## The look a fresh project boots with, and what reset_to_default() restores.
const DEFAULT_PRESET: String = PRESET_AUTHENTIC

var _current: PSXLookPreset = PSXLookPreset.new()
## Suppresses per-property pushes while a whole preset is being applied, so
## applying a preset emits look_changed once instead of eleven times.
var _applying: bool = false
## Which preset the live values came from, and whether anything has been
## changed since. Purely descriptive -- it exists so a debug overlay can say
## "authentic (modified)" rather than leaving you guessing what you are
## looking at. Nothing in the rendering path reads it.
var _preset_name: String = ""
var _modified: bool = false

# --- Typed accessors -------------------------------------------------------
# Each reads and writes through _current, then pushes just that one parameter.

var jitter_enabled: bool:
	get: return _current.jitter_enabled
	set(value):
		_current.jitter_enabled = value
		_push(&"psx_jitter_enabled", value)

var snap_resolution: Vector2:
	get: return _current.snap_resolution
	set(value):
		_current.snap_resolution = value
		_push(&"psx_snap_resolution", value)

var affine_strength: float:
	get: return _current.affine_strength
	set(value):
		_current.affine_strength = clampf(value, 0.0, 1.0)
		_push(&"psx_affine_strength", _current.affine_strength)

var color_depth: float:
	get: return _current.color_depth
	set(value):
		_current.color_depth = maxf(value, 2.0)
		_push(&"psx_color_depth", _current.color_depth)

var dither_strength: float:
	get: return _current.dither_strength
	set(value):
		_current.dither_strength = clampf(value, 0.0, 1.0)
		_push(&"psx_dither_strength", _current.dither_strength)

var fog_enabled: bool:
	get: return _current.fog_enabled
	set(value):
		_current.fog_enabled = value
		_push(&"psx_fog_enabled", value)

## Exposed as a Color for inspector and editor convenience; the shader global
## is a vec3 and the alpha channel is discarded.
var fog_color: Color:
	get: return _current.fog_color
	set(value):
		_current.fog_color = value
		_push(&"psx_fog_color", Vector3(value.r, value.g, value.b))

var fog_near: float:
	get: return _current.fog_near
	set(value):
		_current.fog_near = value
		_push(&"psx_fog_near", value)

var fog_far: float:
	get: return _current.fog_far
	set(value):
		_current.fog_far = value
		_push(&"psx_fog_far", value)

# --- Post-process pass toggles ---------------------------------------------
# These are NOT global shader parameters. There is no uniform to set: enabling
# a pass means making a ColorRect visible. PSXLook owns the intent and emits
# look_changed; ui/post_process/post_process_stack.gd owns the nodes and does
# the work. That keeps PSXLook free of any knowledge of the scene tree.

var dither_enabled: bool:
	get: return _current.dither_enabled
	set(value):
		_current.dither_enabled = value
		_touch()

var crt_enabled: bool:
	get: return _current.crt_enabled
	set(value):
		_current.crt_enabled = value
		_touch()


func _ready() -> void:
	# Run even when the editor is paused or the tree is stopped; shader globals
	# are not gameplay.
	process_mode = Node.PROCESS_MODE_ALWAYS
	reset_to_default()


## Replaces the entire current look. The preset is duplicated, so runtime edits
## never write back into the .tres on disk.
func apply_preset(preset: PSXLookPreset) -> void:
	if preset == null:
		push_error("PSXLook.apply_preset() called with null. Look unchanged.")
		return
	_current = preset.duplicate() as PSXLookPreset
	# "res://psx/look/preset_authentic.tres" -> "authentic"
	var path := preset.resource_path
	_preset_name = path.get_file().get_basename().trim_prefix("preset_") if not path.is_empty() else ""
	# Cleared BEFORE _push_all(), not after: _push_all() emits look_changed
	# synchronously, and listeners read get_preset_name() from inside that
	# emission. Clearing afterwards would leave every listener showing
	# "(modified)" for a preset that was just freshly applied.
	_modified = false
	_push_all()


## Convenience for the three shipped presets and for anything holding a path.
func apply_preset_path(path: String) -> void:
	var preset: PSXLookPreset = load(path) as PSXLookPreset
	if preset == null:
		push_error("PSXLook: '%s' is missing or is not a PSXLookPreset." % path)
		return
	apply_preset(preset)


## Restores DEFAULT_PRESET. Falls back to a code-defined preset if the resource
## is missing, so a broken or deleted .tres degrades to a working look rather
## than to a black screen.
func reset_to_default() -> void:
	var preset: PSXLookPreset = load(DEFAULT_PRESET) as PSXLookPreset
	if preset == null:
		push_warning("PSXLook: '%s' missing; falling back to script defaults." % DEFAULT_PRESET)
		preset = PSXLookPreset.new()
	apply_preset(preset)


## A copy of the live values, for a debug overlay or a save file. Editing the
## returned resource does not affect rendering -- call apply_preset() for that.
func get_current_preset() -> PSXLookPreset:
	return _current.duplicate() as PSXLookPreset


## A human-readable name for the live look: "authentic", "extreme (modified)",
## or "custom" if the values never came from a .tres. For display only.
func get_preset_name() -> String:
	var base := _preset_name if not _preset_name.is_empty() else "custom"
	return base + " (modified)" if _modified else base


# --- Internals -------------------------------------------------------------

func _push(name: StringName, value: Variant) -> void:
	RenderingServer.global_shader_parameter_set(name, value)
	_touch()


## Announces a change. Separate from _push() because the post-process toggles
## change the look without there being any shader global to set.
func _touch() -> void:
	if not _applying:
		_modified = true
		look_changed.emit()


func _push_all() -> void:
	_applying = true
	# Assigning through the properties keeps the clamping rules in one place.
	jitter_enabled = _current.jitter_enabled
	snap_resolution = _current.snap_resolution
	affine_strength = _current.affine_strength
	color_depth = _current.color_depth
	dither_strength = _current.dither_strength
	fog_enabled = _current.fog_enabled
	fog_color = _current.fog_color
	fog_near = _current.fog_near
	fog_far = _current.fog_far
	dither_enabled = _current.dither_enabled
	crt_enabled = _current.crt_enabled
	_applying = false
	look_changed.emit()
