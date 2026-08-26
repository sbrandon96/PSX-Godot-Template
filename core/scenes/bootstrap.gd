## bootstrap.gd  --  attached to bootstrap.tscn, the project's main scene.
##
## WHAT: The single, well-defined entry point of every game built from this
##       template. It is the one scene that is always in the tree.
##
## RESPONSIBLE FOR: owning the root layer structure, wiring the framework
##       together in a documented order, and requesting the first level.
##
## WHY A PERSISTENT ROOT: get_tree().change_scene_to_file() swaps the entire
##       root, which would destroy the post-process stack and the loading
##       screen on every level change and rebuild them from scratch. Here the
##       root stays put and only WorldContainer's contents are swapped, by
##       SceneLoader.
##
## -- Layer ordering, and why the numbers are what they are -------------------
##
##   WorldContainer   (Node3D)              the 3D world; levels live here
##   UILayer          (CanvasLayer,  10)    in-game UI  -- IS post-processed
##   PostProcessLayer (CanvasLayer, 100)    dither, CRT
##   LoadingLayer     (CanvasLayer, 200)    loading screen -- NOT post-processed
##
## A CanvasLayer with a higher `layer` draws later. UILayer sits BELOW the post
## stack on purpose: a HUD should be quantised and dithered along with the
## world, or it reads as a modern overlay pasted onto a PS1 game. The loading
## screen sits ABOVE it, also on purpose: it is framework chrome shown while
## there is no world to be part of, and running it through a CRT curve would
## warp the only thing on screen. That is the answer to "above or through" --
## in-game UI goes through, the loading screen goes above.

extends Node

# ===========================================================================
#  THE ONE LINE A NEW GAME CHANGES
#
#  Point this at your own first scene. That is the entire integration step:
#  everything else in core/, psx/, player/ and ui/ is game-agnostic.
#
#  Leave it empty ("") to boot into an empty world -- useful while building
#  out the framework, and what the template ships with until it has a level
#  worth loading.
# ===========================================================================
const INITIAL_SCENE: String = ""

## Instanced into PostProcessLayer at boot. Empty disables post-processing.
## Wired up in Phase 6, when ui/post_process/ exists.
const POST_PROCESS_SCENE: String = ""

## Instanced into LoadingLayer at boot and hidden immediately. Empty means
## loads happen with no loading screen. Wired up in Phase 6.
const LOADING_SCREEN_SCENE: String = ""

@onready var world_container: Node3D = $WorldContainer
@onready var ui_layer: CanvasLayer = $UILayer
@onready var post_process_layer: CanvasLayer = $PostProcessLayer
@onready var loading_layer: CanvasLayer = $LoadingLayer


func _ready() -> void:
	DebugLog.info("Boot sequence starting", "Bootstrap")

	# --- 1. PSXLook: shader globals pushed to the rendering server. ---------
	# --- 2. GameState: state container ready. ------------------------------
	# Both are autoloads, and Godot runs every autoload's _ready() before the
	# main scene's. By the time this function is entered they are already
	# initialised -- which is precisely why their order in project.godot
	# matters, and why PSXLook is listed first. Steps 1 and 2 are therefore
	# not actions taken here; they are guarantees relied upon from here on.
	# See autoload/README.md.

	# --- 3. Post-processing stack. -----------------------------------------
	_instance_into(POST_PROCESS_SCENE, post_process_layer, "post-process stack")

	# --- 4. Loading screen, hidden until a load starts. --------------------
	var loading_screen := _instance_into(LOADING_SCREEN_SCENE, loading_layer, "loading screen")
	if loading_screen is CanvasItem:
		(loading_screen as CanvasItem).visible = false

	# --- 5. Hand SceneLoader its container, then request the first scene. --
	# SceneLoader has no idea what a bootstrap is; it is told where to put
	# things. That keeps it usable under any root layout.
	SceneLoader.set_world_container(world_container)

	if INITIAL_SCENE.is_empty():
		DebugLog.info("INITIAL_SCENE is empty; booting to an empty world.", "Bootstrap")
	else:
		SceneLoader.load_scene(INITIAL_SCENE)

	DebugLog.info("Boot sequence complete", "Bootstrap")


## Instances `path` under `parent`, or does nothing if the path is empty.
## Returns the instance, or null. A path that is set but broken is a real
## configuration error and is reported as one.
func _instance_into(path: String, parent: Node, what: String) -> Node:
	if path.is_empty():
		DebugLog.debug("No %s configured; skipping." % what, "Bootstrap")
		return null
	if not ResourceLoader.exists(path):
		DebugLog.error("%s scene '%s' not found." % [what.capitalize(), path], "Bootstrap")
		return null

	var packed := load(path) as PackedScene
	if packed == null:
		DebugLog.error("%s scene '%s' is not a PackedScene." % [what.capitalize(), path], "Bootstrap")
		return null

	var instance := packed.instantiate()
	parent.add_child(instance)
	DebugLog.debug("Instanced %s from '%s'." % [what, path], "Bootstrap")
	return instance
