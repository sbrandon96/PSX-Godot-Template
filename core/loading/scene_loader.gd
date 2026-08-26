## scene_loader.gd  --  registered as the `SceneLoader` autoload.
##
## WHAT: Non-blocking scene loading and swapping.
##
## RESPONSIBLE FOR: streaming a scene in on a background thread, reporting
##       progress, swapping it into the bootstrap's world container, and
##       disposing of the outgoing scene without ever leaving two levels alive
##       in the tree at once.
##
## WHY NOT get_tree().change_scene_to_file(): that replaces the ENTIRE root
##       scene, which would take the bootstrap, the post-process stack and the
##       loading screen down with it every time. This template keeps a
##       persistent root and swaps only the world beneath it.
##
## -- VERIFIED FAILURE BEHAVIOUR (Godot 4.7.1) --------------------------------
## ResourceLoader.load_threaded_request() returns OK for a path that does not
## exist. It does not fail, it does not return an error code, and the engine
## prints its own raw "Cannot open file" / "Failed loading resource" lines from
## a background thread before the status ever reports FAILED. There is no way
## to catch or suppress those once the request is made.
##
## So the path is validated with ResourceLoader.exists() BEFORE requesting.
## That check is clean and silent, and it turns "a bad path fills the output
## panel with engine internals" into "one readable error naming the caller's
## path". The status enum is still handled in full afterwards, because a file
## that exists can still be corrupt.
##
## -- MINIMUM DISPLAY TIME ----------------------------------------------------
## A template design decision, not a requirement from the source material. A
## scene that loads in 30ms makes the loading screen appear and vanish within a
## single blink, which reads as a graphical glitch rather than as loading. So a
## completed load is held until minimum_display_time has elapsed. It applies
## only when a loading screen was actually requested.

extends Node

## Emitted when a load has been accepted and started.
signal load_started(path: String)
## Emitted while loading, 0.0 to 100.0. Fires on the frames it changes.
signal load_progress(percent: float)
## Emitted after the new scene is in the tree and the old one is gone.
signal load_completed(path: String)
## Emitted instead of load_completed if anything went wrong. `reason` is
## written for a human reading the output panel.
signal load_failed(path: String, reason: String)

const MINIMUM_DISPLAY_TIME_DEFAULT: float = 0.5

## How long the loading screen stays up at minimum, in seconds. Set to 0.0 to
## disable the hold. Not an @export: autoloads are instanced from script, so
## the inspector never sees this. Set it from code at startup.
var minimum_display_time: float = MINIMUM_DISPLAY_TIME_DEFAULT

## Whether the in-flight load asked for a loading screen. The loading screen
## reads this when it handles load_started, so the signal signature stays
## simple. Meaningless while idle.
var loading_screen_requested: bool = false

## Where loaded scenes are parented. Injected by the bootstrap via
## set_world_container(); SceneLoader deliberately does not know how to find
## it, so it stays usable under any root scene layout.
var _world_container: Node = null

var _current_scene: Node = null
var _current_path: String = ""

# In-flight request state. _requested_path being non-empty IS "a load is
# running"; there is no separate flag to fall out of sync with it.
var _requested_path: String = ""
var _pending_scene: PackedScene = null
var _started_msec: int = 0
var _last_percent: float = -1.0


func _ready() -> void:
	# Only poll while something is actually loading.
	set_process(false)


## Called by the bootstrap during its boot sequence. Must happen before the
## first load_scene() call.
func set_world_container(container: Node) -> void:
	_world_container = container


func is_loading() -> bool:
	return not _requested_path.is_empty()


## The scene currently in the world container, or "" if none.
func get_current_scene_path() -> String:
	return _current_path


func get_current_scene() -> Node:
	return _current_scene


## Begins loading `path` and swapping it in when ready.
## Rejects the request -- via load_failed, with a readable reason -- rather
## than raising, so a caller can respond in one place.
func load_scene(path: String, show_loading_screen: bool = true) -> void:
	if is_loading():
		_reject(path, "a load of '%s' is already in progress" % _requested_path)
		return
	if _world_container == null:
		_reject(path, "no world container registered; call SceneLoader.set_world_container() first")
		return
	if path.is_empty():
		_reject(path, "empty scene path")
		return
	# The pre-check that keeps engine internals out of the output panel.
	if not ResourceLoader.exists(path):
		_reject(path, "no such resource (check the path and that the file is imported)")
		return

	var err := ResourceLoader.load_threaded_request(path)
	if err != OK:
		_reject(path, "load_threaded_request failed: %s" % error_string(err))
		return

	_requested_path = path
	_pending_scene = null
	_started_msec = Time.get_ticks_msec()
	_last_percent = -1.0
	loading_screen_requested = show_loading_screen
	set_process(true)
	DebugLog.info("Loading '%s'" % path, "SceneLoader")
	load_started.emit(path)


func _process(_delta: float) -> void:
	if not is_loading():
		set_process(false)
		return

	# Once the resource is in hand we are only waiting on the display timer.
	if _pending_scene != null:
		if _minimum_time_elapsed():
			_swap_in()
		return

	var progress := []
	var status := ResourceLoader.load_threaded_get_status(_requested_path, progress)

	match status:
		ResourceLoader.THREAD_LOAD_IN_PROGRESS:
			var percent: float = (progress[0] as float) * 100.0 if not progress.is_empty() else 0.0
			if not is_equal_approx(percent, _last_percent):
				_last_percent = percent
				load_progress.emit(percent)

		ResourceLoader.THREAD_LOAD_LOADED:
			var resource := ResourceLoader.load_threaded_get(_requested_path)
			if not (resource is PackedScene):
				_fail("loaded, but it is a %s and not a PackedScene"
						% ("null" if resource == null else resource.get_class()))
				return
			_pending_scene = resource
			_last_percent = 100.0
			load_progress.emit(100.0)
			if _minimum_time_elapsed():
				_swap_in()

		ResourceLoader.THREAD_LOAD_FAILED:
			_fail("the file exists but failed to load; it may be corrupt or reference a missing dependency")

		ResourceLoader.THREAD_LOAD_INVALID_RESOURCE:
			_fail("invalid resource; nothing was ever requested for this path")


func _minimum_time_elapsed() -> bool:
	if not loading_screen_requested or minimum_display_time <= 0.0:
		return true
	var elapsed: float = (Time.get_ticks_msec() - _started_msec) / 1000.0
	return elapsed >= minimum_display_time


## Instantiates the pending scene, removes the outgoing one, and parents the
## new one. Order matters: the outgoing scene is removed from the tree BEFORE
## the new one is added, because queue_free() only takes effect at the end of
## the frame. Freeing without removing first would leave both levels in the
## tree simultaneously -- both running _process, both receiving input, both
## visible.
func _swap_in() -> void:
	var path := _requested_path
	var instance := _pending_scene.instantiate()

	for child in _world_container.get_children():
		_world_container.remove_child(child)
		child.queue_free()

	_world_container.add_child(instance)
	_current_scene = instance
	_current_path = path

	_reset()
	DebugLog.info("Loaded '%s'" % path, "SceneLoader")
	load_completed.emit(path)


## Failure after a request was accepted. Cleans up the in-flight state so the
## next load_scene() is not rejected as "already in progress".
func _fail(reason: String) -> void:
	var path := _requested_path
	_reset()
	DebugLog.error("Failed to load '%s': %s" % [path, reason], "SceneLoader")
	load_failed.emit(path, reason)


## Rejection before a request was made. Kept separate from _fail() so it never
## touches in-flight state belonging to another load.
func _reject(path: String, reason: String) -> void:
	DebugLog.error("Refusing to load '%s': %s" % [path, reason], "SceneLoader")
	load_failed.emit(path, reason)


func _reset() -> void:
	_requested_path = ""
	_pending_scene = null
	_last_percent = -1.0
	loading_screen_requested = false
	set_process(false)
