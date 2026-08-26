## loading_screen.gd  --  attached to loading_screen.tscn.
##
## WHAT: The full-screen panel shown while SceneLoader streams a scene in.
##
## RESPONSIBLE FOR: reacting to SceneLoader's signals, showing progress, and
##       fading itself in and out. It never triggers a load and never decides
##       what loads next.
##
## -- ABOVE POST-PROCESSING, NOT THROUGH IT ----------------------------------
## The bootstrap puts this on LoadingLayer (CanvasLayer, layer 200), which
## draws AFTER PostProcessLayer (100). So the loading screen is NOT dithered
## by the framebuffer pass and NOT bent by the CRT pass. That is deliberate:
##
##   * In-game UI goes THROUGH the post stack, so a HUD is quantised along
##     with the world and does not read as a modern overlay pasted onto a PS1
##     game.
##   * The loading screen goes ABOVE it. It is framework chrome shown when
##     there is no world to be part of, and a barrel distortion applied to the
##     only thing on screen just looks like a broken display. Worse, the CRT
##     pass samples the backbuffer -- during a load that backbuffer holds the
##     half-torn-down previous scene, which would smear through the fade.
##
## To keep it looking like it belongs anyway, the text uses psx_ui.gdshader,
## which applies the same palette clamp and Bayer dither from the same PSXLook
## globals -- without going through the screen-space passes. That is precisely
## the case psx_ui.gdshader was written for.
##
## -- MINIMUM DISPLAY TIME ---------------------------------------------------
## Not enforced here. SceneLoader holds a completed load until its
## minimum_display_time has elapsed and only then emits load_completed, so by
## the time this script is told to hide, the hold is already satisfied. Putting
## the rule in one place keeps the two from disagreeing.

extends Control

## Seconds for the fade in and the fade out.
@export var fade_duration: float = 0.25
## Text shown while loading. A template has no business inventing flavour text.
@export var status_text: String = "LOADING"

@onready var _status_label: Label = %StatusLabel
@onready var _percent_label: Label = %PercentLabel
@onready var _progress_bar: ProgressBar = %ProgressBar

var _tween: Tween = null


func _ready() -> void:
	_status_label.text = status_text
	# Start fully hidden. The bootstrap also hides this on instancing, but a
	# loading screen that flashes on boot because it depended on someone else
	# hiding it is exactly the bug this template should not ship.
	modulate.a = 0.0
	visible = false

	SceneLoader.load_started.connect(_on_load_started)
	SceneLoader.load_progress.connect(_on_load_progress)
	SceneLoader.load_completed.connect(_on_load_completed)
	SceneLoader.load_failed.connect(_on_load_failed)


func _on_load_started(_path: String) -> void:
	# SceneLoader records whether this particular load wanted a screen.
	if not SceneLoader.loading_screen_requested:
		return
	_set_progress(0.0)
	_fade_to(1.0)


func _on_load_progress(percent: float) -> void:
	_set_progress(percent)


func _on_load_completed(_path: String) -> void:
	_fade_to(0.0)


func _on_load_failed(_path: String, _reason: String) -> void:
	# The failure is already reported by SceneLoader. All this needs to do is
	# get out of the way rather than leaving a dead screen up forever.
	_fade_to(0.0)


func _set_progress(percent: float) -> void:
	_progress_bar.value = percent
	_percent_label.text = "%d%%" % roundi(percent)


func _fade_to(target_alpha: float) -> void:
	if _tween != null and _tween.is_valid():
		_tween.kill()
	if target_alpha > 0.0:
		visible = true
	_tween = create_tween()
	_tween.tween_property(self, ^"modulate:a", target_alpha, fade_duration)
	if is_zero_approx(target_alpha):
		# Hide once transparent so it stops being drawn and stops eating input.
		_tween.tween_callback(func() -> void: visible = false)
