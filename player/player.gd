## player.gd  --  attached to player.tscn.
##
## WHAT: A reusable first-person character controller.
##
## RESPONSIBLE FOR: moving a capsule around with WASD, looking with the mouse,
##       gravity, jumping, and an optional crouch. That is the whole list.
##
## WHAT IS DELIBERATELY ABSENT: head bob, footsteps, stamina, lean, an
##       interaction system, weapon handling, health, and a state machine.
##       Every one of those is a game decision. A template that picks them for
##       you is a game, not a template. The extension points below are where
##       they attach.
##
## USING IT: instance player.tscn into any 3D scene. Nothing else is required.
##       All tuning is on the exports; nothing worth changing is buried in
##       code. To extend, either attach a child node that reads this node's
##       public state, or `extends` this script and override
##       _handle_extra_input().
##
## -- VERIFIED GOTCHA: mouse look at 320x240 ---------------------------------
## Measured on Godot 4.7.1 with this project's settings (320x240 content,
## 1280x960 window, stretch mode `viewport`, integer scaling):
##
##   pushed  relative=(100,0)  ->  received relative=(25,0)
##   pushed  screen_relative=(100,0) -> received screen_relative=(100,0)
##
## `relative` is divided by the content-scale factor. That factor is 4 right
## now, but with integer scaling it changes in WHOLE STEPS as the window is
## resized or fullscreened -- 3x, 4x, 5x. A controller built on `relative`
## therefore has mouse sensitivity that visibly jumps when the player resizes
## the window, which is close to impossible to diagnose from the symptom.
##
## `screen_relative` is unscaled window-space motion and is what this
## controller uses. Do not "simplify" it back to `relative`.
##
## -- VERIFIED GOTCHA: get_viewport().size is NOT the framebuffer size --------
## In the same measurement, the real framebuffer is 320x240 and
## get_viewport().get_visible_rect().size correctly reports (320, 240) -- but
## get_viewport().size reports (1280, 960), the WINDOW size. Anything computing
## in framebuffer space (a crosshair, a screen-space ray, a UI offset) must use
## get_visible_rect().size or it will be wrong by the scale factor.
##
## -- NOTE FOR THE WEB EXPORT ------------------------------------------------
## Browsers only grant pointer lock in response to a real user gesture. A
## capture requested from _ready() is refused on web, silently. That is why any
## mouse click while uncaptured re-captures: the click IS the gesture. Keep
## that path, or the web build ships with no mouse look.

extends CharacterBody3D

## Emitted when the mouse is captured or released, so a game can pause, show a
## menu, or swap input hints without this script knowing what any of those are.
signal mouse_capture_changed(captured: bool)

@export_group("Movement")
## Metres per second on the ground. PSX-era games were slow; so is this.
@export var walk_speed: float = 3.0
@export var sprint_speed: float = 5.5
@export var crouch_speed: float = 1.5
## How fast velocity climbs toward the target speed, in m/s per second.
@export var acceleration: float = 12.0
## How fast it falls back to zero when there is no input. Higher than
## acceleration gives a crisp stop rather than an ice-rink slide.
@export var deceleration: float = 16.0
## Fraction of ground control retained in mid-air. 0 = committed to your
## jump arc, 1 = full air steering.
@export_range(0.0, 1.0) var air_control: float = 0.25

@export_group("Jumping and Gravity")
## Upward velocity applied on jump, in m/s.
@export var jump_velocity: float = 4.2
## Multiplies the world gravity from Project Settings (currently 9.8).
## Below 1.0 gives the floaty arc a lot of PS1-era games had.
@export var gravity_scale: float = 1.0

@export_group("Look")
## Degrees of rotation per pixel of unscaled window-space mouse motion.
@export_range(0.01, 1.0, 0.01) var mouse_sensitivity: float = 0.12
## Pitch limits. Kept just inside +/-90 to avoid the degenerate straight-up
## and straight-down orientations.
@export_range(-89.9, 0.0) var pitch_min_degrees: float = -89.0
@export_range(0.0, 89.9) var pitch_max_degrees: float = 89.0
@export var invert_look_y: bool = false

@export_group("Stance")
## Capsule height while standing, in metres. Applied to the collision shape at
## runtime, so this export is the single source of truth for player size.
@export var stand_height: float = 1.8
@export var crouch_height: float = 1.0
@export var capsule_radius: float = 0.35
## How fast the capsule and camera move between stances, in metres per second.
@export var crouch_transition_speed: float = 8.0
## Camera height relative to the top of the capsule. Negative sits the eyes
## just below the crown, which is where eyes actually are.
@export var eye_offset: float = -0.15

@export_group("Camera")
@export var camera_near: float = 0.05
## Used only when match_far_plane_to_fog is false.
@export var camera_far: float = 24.0
## Keeps the far plane pinned to PSXLook's fog_far, so geometry finishes
## fading exactly as it is clipped. Without this pairing, distant geometry
## either pops out of a clear scene or fades out long before the far plane and
## wastes the depth range. Turn it off to drive the far plane yourself.
@export var match_far_plane_to_fog: bool = true

@export_group("Mouse Capture")
## Desktop captures immediately. On web this request is refused and the first
## click captures instead -- see the note in the header.
@export var capture_mouse_on_ready: bool = true
## Escape (the built-in `ui_cancel` action) releases the mouse.
@export var escape_releases_mouse: bool = true

@export_group("Interaction")
## The InteractionRay is an EXTENSION POINT, not a feature. It ships disabled
## so it costs nothing until a game wants it. Tick this, then read
## get_interaction_target() from your own script. What "interacting" means is
## deliberately not decided here.
@export var interaction_ray_enabled: bool = false
@export var interaction_distance: float = 2.0

@onready var head: Node3D = $Head
@onready var camera: Camera3D = $Head/Camera3D
@onready var collision_shape: CollisionShape3D = $CollisionShape3D
@onready var interaction_ray: RayCast3D = $Head/InteractionRay

var _capsule: CapsuleShape3D
var _pitch_degrees: float = 0.0
var _current_height: float = 0.0
var _is_crouching: bool = false


func _ready() -> void:
	# The capsule is marked resource_local_to_scene in player.tscn so two
	# instanced players do not share one shape and fight over its height.
	_capsule = collision_shape.shape as CapsuleShape3D
	if _capsule == null:
		DebugLog.error("CollisionShape3D has no CapsuleShape3D.", "Player")
		return

	_current_height = stand_height
	_apply_stance_height(_current_height)

	camera.near = camera_near
	if match_far_plane_to_fog:
		# Looked up rather than referenced directly, so this script still
		# compiles in a project that has not adopted PSXLook.
		var look := get_node_or_null(^"/root/PSXLook")
		if look != null:
			look.look_changed.connect(_sync_far_plane_to_fog)
			_sync_far_plane_to_fog()
		else:
			camera.far = camera_far
	else:
		camera.far = camera_far

	interaction_ray.enabled = interaction_ray_enabled
	interaction_ray.target_position = Vector3(0.0, 0.0, -interaction_distance)

	if capture_mouse_on_ready:
		capture_mouse()


func _unhandled_input(event: InputEvent) -> void:
	if escape_releases_mouse and event.is_action_pressed(&"ui_cancel"):
		release_mouse()
		return

	# Any click while uncaptured re-captures. On web this click is the user
	# gesture the browser requires before it will grant pointer lock.
	if event is InputEventMouseButton and (event as InputEventMouseButton).pressed:
		if Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
			capture_mouse()
			return

	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		# screen_relative, NOT relative -- see the header.
		_apply_look((event as InputEventMouseMotion).screen_relative)
		return

	_handle_extra_input(event)


## EXTENSION POINT. Override in a script that `extends` this one to add input
## handling -- interaction, a flashlight, whatever the game needs -- without
## editing or forking this file.
func _handle_extra_input(_event: InputEvent) -> void:
	pass


func _physics_process(delta: float) -> void:
	_apply_gravity(delta)
	_apply_jump()
	_update_stance(delta)
	_apply_movement(delta)
	move_and_slide()


func _apply_gravity(delta: float) -> void:
	if not is_on_floor():
		velocity += get_gravity() * gravity_scale * delta


func _apply_jump() -> void:
	if Input.is_action_just_pressed(&"jump") and is_on_floor():
		velocity.y = jump_velocity


func _apply_movement(delta: float) -> void:
	var input_dir := Input.get_vector(&"move_left", &"move_right", &"move_forward", &"move_back")
	# Input is relative to where the body faces; -Z is forward in Godot.
	var direction := (transform.basis * Vector3(input_dir.x, 0.0, input_dir.y))
	direction.y = 0.0
	if not direction.is_zero_approx():
		direction = direction.normalized()

	var target_speed := walk_speed
	if _is_crouching:
		target_speed = crouch_speed
	elif Input.is_action_pressed(&"sprint") and is_on_floor():
		target_speed = sprint_speed

	var control := 1.0 if is_on_floor() else air_control
	var rate := (acceleration if not direction.is_zero_approx() else deceleration) * control
	velocity.x = move_toward(velocity.x, direction.x * target_speed, rate * delta)
	velocity.z = move_toward(velocity.z, direction.z * target_speed, rate * delta)


func _update_stance(delta: float) -> void:
	var wants_crouch := Input.is_action_pressed(&"crouch")

	# Refuse to stand up into a ceiling. Without this the capsule grows through
	# the geometry above and the player is ejected.
	if _is_crouching and not wants_crouch and not _has_room_to_stand():
		wants_crouch = true

	_is_crouching = wants_crouch
	var target_height := crouch_height if _is_crouching else stand_height
	if not is_equal_approx(_current_height, target_height):
		_current_height = move_toward(_current_height, target_height, crouch_transition_speed * delta)
		_apply_stance_height(_current_height)


## Sweeps the current capsule upward by the height it still needs to grow. If
## that sweep hits nothing, a standing capsule fits.
func _has_room_to_stand() -> bool:
	var needed := stand_height - _current_height
	if needed <= 0.0:
		return true
	return not test_move(global_transform, Vector3.UP * needed)


func _apply_stance_height(height: float) -> void:
	# A capsule cannot be shorter than its own two hemispheres.
	_capsule.radius = capsule_radius
	_capsule.height = maxf(height, capsule_radius * 2.0)
	# Origin sits at the feet, so the shape is centred half a height up.
	collision_shape.position.y = _capsule.height * 0.5
	head.position.y = _capsule.height + eye_offset


func _apply_look(motion: Vector2) -> void:
	# Yaw turns the whole body so movement follows the view; pitch is
	# head-only, or the capsule would tip over.
	rotate_y(deg_to_rad(-motion.x * mouse_sensitivity))

	var pitch_delta := -motion.y * mouse_sensitivity
	if invert_look_y:
		pitch_delta = -pitch_delta
	_pitch_degrees = clampf(_pitch_degrees + pitch_delta, pitch_min_degrees, pitch_max_degrees)
	head.rotation_degrees.x = _pitch_degrees


func _sync_far_plane_to_fog() -> void:
	var look := get_node_or_null(^"/root/PSXLook")
	if look == null:
		return
	camera.far = maxf(look.fog_far, camera.near + 0.1)


# --- Public API ------------------------------------------------------------

func capture_mouse() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	mouse_capture_changed.emit(true)


func release_mouse() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	mouse_capture_changed.emit(false)


func is_mouse_captured() -> bool:
	return Input.mouse_mode == Input.MOUSE_MODE_CAPTURED


func is_crouching() -> bool:
	return _is_crouching


## Current horizontal speed in m/s. Useful for a debug overlay, or for a game
## that wants to drive footsteps or head bob from outside this script.
func get_horizontal_speed() -> float:
	return Vector2(velocity.x, velocity.z).length()


## EXTENSION POINT for interaction. Returns whatever the InteractionRay is
## pointing at, or null. Requires interaction_ray_enabled.
##
## This template deliberately stops here: it will tell you WHAT you are looking
## at, and takes no position on what should happen next. Handle the `interact`
## action in your own script:
##
##     func _handle_extra_input(event):
##         if event.is_action_pressed("interact"):
##             var target = get_interaction_target()
##             if target and target.has_method("interact"):
##                 target.interact(self)
func get_interaction_target() -> Object:
	if not interaction_ray.enabled:
		return null
	return interaction_ray.get_collider() if interaction_ray.is_colliding() else null
