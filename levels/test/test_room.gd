## test_room.gd  --  attached to test_room.tscn.
##
## WHAT: The two lines of behaviour the technical validation scene needs.
##
## RESPONSIBLE FOR: turning the demo cube, and cycling PSXLook presets on a
##       keypress so the range of the look system can be seen without opening
##       the debug overlay.
##
## THIS IS NOT A GAME LEVEL AND MUST NOT BECOME ONE. No triggers, no doors, no
##       pickups, no scares, no scripted events. If you want to build a game,
##       copy this scene somewhere under your own directory and gut it. The
##       moment this file grows a third responsibility it has stopped being a
##       test and started being content, and the template has lost the one
##       scene that tells you whether the renderer still works.
##
## WHY THE CUBE TURNS: vertex snapping quantises the PROJECTED position, so it
##       has to be re-evaluated every frame from a moving camera or a moving
##       object. A static scene cannot tell you whether the snap is happening
##       in screen space or was simply baked into the mesh. A cube rotating
##       slowly on a tilted axis makes the answer obvious -- its edges crawl.
##
## WHY F2 AND NOT AN INPUT ACTION: preset cycling is a property of this test
##       scene, not of the template. Adding it to the shared input map would
##       push a debug-only binding onto every project made from this template.
##       A raw key check, scoped to the one scene that wants it, does not.

extends Node3D

## Degrees per second for the demo cube. Slow on purpose: fast rotation hides
## the per-frame vertex snapping behind motion blur in the eye.
@export var cube_rotation_speed: float = 24.0

@onready var rotating_cube: MeshInstance3D = $Props/RotatingCube

@onready var _preset_paths: Array[String] = [
	PSXLook.PRESET_CLEAN,
	PSXLook.PRESET_AUTHENTIC,
	PSXLook.PRESET_EXTREME,
]
## Starts at authentic, matching what PSXLook boots with.
var _preset_index: int = 1


func _process(delta: float) -> void:
	rotating_cube.rotate_y(deg_to_rad(cube_rotation_speed * delta))


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey:
		var key := event as InputEventKey
		if key.pressed and not key.echo and key.physical_keycode == KEY_F2:
			_preset_index = (_preset_index + 1) % _preset_paths.size()
			PSXLook.apply_preset_path(_preset_paths[_preset_index])
			DebugLog.info("Preset -> %s" % PSXLook.get_preset_name(), "TestRoom")
