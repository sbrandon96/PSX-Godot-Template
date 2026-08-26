## debug_overlay.gd  --  attached to debug_overlay.tscn.
##
## WHAT: A developer HUD. Performance counters, the live PSXLook values, and
##       sliders that drive those values in real time.
##
## RESPONSIBLE FOR: making the global look system tangible. If dragging a
##       slider here does not change the picture, the look pipeline is broken
##       and this overlay is how you find that out.
##
## -- STRIPPING IT FROM A SHIPPING GAME --------------------------------------
## Three options, in increasing order of thoroughness:
##
##   1. Leave it. `debug_builds_only` (below) is on by default, so the overlay
##      frees itself during _ready() in an exported release build. It costs one
##      instantiate and one queue_free at boot, and nothing after that.
##   2. Set DEBUG_OVERLAY_SCENE = "" in core/scenes/bootstrap.gd. Never
##      instanced at all.
##   3. Delete ui/debug/ and clear that constant. Nothing else in the template
##      references this directory -- it is a leaf.
##
## -- WHY IT READS PSXLook AND NOT THE RENDERING SERVER ----------------------
## VERIFIED on Godot 4.7.1, Compatibility/GLES3:
## RenderingServer.global_shader_parameter_get() is EDITOR-ONLY. In a running
## game the GLES3 driver refuses it -- "This function should never be used
## outside the editor" -- and returns null. Global shader parameters are
## effectively write-only at runtime, so PSXLook's own state is the only
## readable source of truth. Do not "improve" this by asking the renderer.
##
## -- WHY THE ROWS ARE BUILT IN CODE -----------------------------------------
## Each slider row is a Label, an HSlider and a value Label. Seven of those is
## twenty-one nodes to hand-place in a .tscn and keep aligned. Built from the
## tables below instead, adding a new psx_* global to this overlay is one line.
## The .tscn holds the frame; the script fills it.
##
## -- RESOLUTION -------------------------------------------------------------
## This renders inside the 320x240 viewport like everything else, then upscales
## 4x with the rest of the frame. 8px text becomes 32px on screen and reads
## fine. It sits on layer 300, above the post-process stack, so it is not
## dithered or bent by the CRT -- a debug readout you cannot read is not one.

extends CanvasLayer

## Free itself on _ready() outside a debug build. See "stripping it" above.
@export var debug_builds_only: bool = true
## How often the performance readout refreshes. 60Hz numbers are unreadable.
@export var stats_refresh_interval: float = 0.2

## Continuous look parameters. Adding a row here adds a working slider.
## `key` is a property on PSXLook, except the two snap_* entries which are
## handled explicitly because snap_resolution is a Vector2.
const SLIDERS: Array = [
	{"key": "snap_x", "label": "snap x", "min": 32.0, "max": 640.0, "step": 1.0},
	{"key": "snap_y", "label": "snap y", "min": 24.0, "max": 480.0, "step": 1.0},
	{"key": "affine_strength", "label": "affine", "min": 0.0, "max": 1.0, "step": 0.01},
	{"key": "color_depth", "label": "colour", "min": 2.0, "max": 256.0, "step": 1.0},
	{"key": "dither_strength", "label": "dither", "min": 0.0, "max": 1.0, "step": 0.01},
	{"key": "fog_near", "label": "fog near", "min": 0.0, "max": 100.0, "step": 0.5},
	{"key": "fog_far", "label": "fog far", "min": 1.0, "max": 200.0, "step": 0.5},
]

## Boolean look parameters, same idea.
const TOGGLES: Array = [
	{"key": "jitter_enabled", "label": "vertex jitter"},
	{"key": "fog_enabled", "label": "distance fade"},
	{"key": "dither_enabled", "label": "dither pass"},
	{"key": "crt_enabled", "label": "CRT pass"},
]

const PRESETS: Array = ["clean", "authentic", "extreme"]

@onready var _root: Control = %Root
@onready var _stats_label: Label = %StatsLabel
@onready var _preset_label: Label = %PresetLabel
@onready var _preset_row: HBoxContainer = %PresetRow
@onready var _toggle_grid: GridContainer = %ToggleGrid
@onready var _slider_column: VBoxContainer = %SliderColumn

var _sliders: Dictionary = {}
var _slider_values: Dictionary = {}
var _checkboxes: Dictionary = {}
var _stats_accumulator: float = 0.0
## Set while writing widget values from PSXLook, so the resulting signals are
## not mistaken for user edits and pushed straight back.
var _syncing: bool = false
var _mouse_mode_before: Input.MouseMode = Input.MOUSE_MODE_VISIBLE


func _ready() -> void:
	if debug_builds_only and not OS.is_debug_build():
		queue_free()
		return

	# Keep updating while the game is paused -- a debug overlay that dies with
	# a pause menu is useless for debugging pause menus.
	process_mode = Node.PROCESS_MODE_ALWAYS

	_build_preset_buttons()
	_build_toggles()
	_build_sliders()

	PSXLook.look_changed.connect(_sync_from_look)
	_sync_from_look()

	_root.visible = false
	set_process(false)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed(&"ui_toggle_debug"):
		_set_open(not _root.visible)
		get_viewport().set_input_as_handled()


func _set_open(open: bool) -> void:
	_root.visible = open
	set_process(open)
	if open:
		# Dragging a slider needs a cursor. Remember what the mouse was doing
		# so closing the overlay puts it back -- this way the overlay works
		# whether it was opened from gameplay or from a menu, and it never
		# needs to know which.
		_mouse_mode_before = Input.mouse_mode
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		_stats_accumulator = stats_refresh_interval
		_sync_from_look()
	else:
		Input.mouse_mode = _mouse_mode_before


func _process(delta: float) -> void:
	_stats_accumulator += delta
	if _stats_accumulator < stats_refresh_interval:
		return
	_stats_accumulator = 0.0
	_refresh_stats()


# --- Construction ----------------------------------------------------------

func _build_preset_buttons() -> void:
	for preset_name: String in PRESETS:
		var button := Button.new()
		button.text = preset_name
		button.add_theme_font_size_override(&"font_size", 8)
		button.pressed.connect(func() -> void:
			PSXLook.apply_preset_path("res://psx/look/preset_%s.tres" % preset_name))
		_preset_row.add_child(button)


func _build_toggles() -> void:
	for entry: Dictionary in TOGGLES:
		var key: String = entry["key"]
		var box := CheckBox.new()
		box.text = entry["label"]
		box.add_theme_font_size_override(&"font_size", 8)
		box.toggled.connect(func(pressed: bool) -> void:
			if not _syncing:
				PSXLook.set(key, pressed))
		_toggle_grid.add_child(box)
		_checkboxes[key] = box


func _build_sliders() -> void:
	for entry: Dictionary in SLIDERS:
		var key: String = entry["key"]

		var row := HBoxContainer.new()
		row.add_theme_constant_override(&"separation", 4)

		var name_label := Label.new()
		name_label.text = entry["label"]
		name_label.custom_minimum_size = Vector2(46, 0)
		name_label.add_theme_font_size_override(&"font_size", 8)
		row.add_child(name_label)

		var slider := HSlider.new()
		slider.min_value = entry["min"]
		slider.max_value = entry["max"]
		slider.step = entry["step"]
		slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		slider.custom_minimum_size = Vector2(0, 8)
		slider.value_changed.connect(func(value: float) -> void:
			if _syncing:
				return
			_set_look_value(key, value)
			_slider_values[key].text = _format(key, value))
		row.add_child(slider)

		var value_label := Label.new()
		value_label.custom_minimum_size = Vector2(34, 0)
		value_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		value_label.add_theme_font_size_override(&"font_size", 8)
		row.add_child(value_label)

		_slider_column.add_child(row)
		_sliders[key] = slider
		_slider_values[key] = value_label


# --- Sync ------------------------------------------------------------------

## Pulls every widget back into agreement with PSXLook. Runs on look_changed,
## so pressing a preset button moves all the sliders.
func _sync_from_look() -> void:
	_syncing = true
	for key: String in _sliders:
		var value := _get_look_value(key)
		# set_value_no_signal, or writing the widget would look like a user
		# edit and push straight back into PSXLook.
		(_sliders[key] as HSlider).set_value_no_signal(value)
		(_slider_values[key] as Label).text = _format(key, value)
	for key: String in _checkboxes:
		(_checkboxes[key] as CheckBox).button_pressed = bool(PSXLook.get(key))
	_preset_label.text = "look: %s" % PSXLook.get_preset_name()
	_syncing = false


## snap_resolution is a Vector2, so its two axes are special-cased. Everything
## else is a plain float property on PSXLook.
func _get_look_value(key: String) -> float:
	match key:
		"snap_x":
			return PSXLook.snap_resolution.x
		"snap_y":
			return PSXLook.snap_resolution.y
		_:
			return float(PSXLook.get(key))


func _set_look_value(key: String, value: float) -> void:
	match key:
		"snap_x":
			PSXLook.snap_resolution = Vector2(value, PSXLook.snap_resolution.y)
		"snap_y":
			PSXLook.snap_resolution = Vector2(PSXLook.snap_resolution.x, value)
		_:
			PSXLook.set(key, value)


func _format(key: String, value: float) -> String:
	return "%d" % roundi(value) if float(SLIDERS[_index_of(key)]["step"]) >= 1.0 else "%.2f" % value


func _index_of(key: String) -> int:
	for i in SLIDERS.size():
		if SLIDERS[i]["key"] == key:
			return i
	return 0


func _refresh_stats() -> void:
	var lines := PackedStringArray()
	lines.append("fps %d   frame %.1fms" % [
		roundi(Performance.get_monitor(Performance.TIME_FPS)),
		Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0])
	# Godot exposes primitives, not vertices; labelled honestly rather than
	# calling a primitive count a vertex count.
	lines.append("draws %d   prims %d" % [
		roundi(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)),
		roundi(Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME))])

	# The active 3D camera rather than a Player reference: in a first-person
	# template the camera IS the player's eye, and this way the overlay works
	# in a scene with no player at all and ui/ stays free of a dependency on
	# player/ for one label.
	var camera := get_viewport().get_camera_3d()
	if camera != null:
		var p := camera.global_position
		lines.append("cam %.1f %.1f %.1f" % [p.x, p.y, p.z])
	else:
		lines.append("cam (none)")

	var scene_path := SceneLoader.get_current_scene_path()
	lines.append("scene %s" % (scene_path.get_file() if not scene_path.is_empty() else "(none)"))

	_stats_label.text = "\n".join(lines)
