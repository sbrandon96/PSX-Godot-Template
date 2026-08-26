## debug_log.gd
##
## WHAT: Leveled logging with a single global threshold.
##
## RESPONSIBLE FOR: letting framework code narrate what it is doing during
##       development without that narration reaching a shipped build.
##
## WHY IT EXISTS: Godot's print() has no level and no off switch, so the usual
##       outcome is either a silent framework you cannot debug or a shipping
##       game that spams stdout. One threshold fixes both. This is the only
##       utility in core/utilities/ -- see the note at the bottom of this file
##       for why the other two the plan called for were not written.
##
## USAGE:
##     DebugLog.info("Scene loaded", "SceneLoader")
##     DebugLog.level = DebugLog.Level.SILENT   # e.g. from an options menu
##
## STRIPPING IT FROM A SHIPPING GAME: you do not have to. The default level is
##       already WARN in a release build, so debug() and info() cost one integer
##       comparison and nothing else. Set Level.SILENT to mute it entirely.

class_name DebugLog
extends RefCounted

enum Level {
	DEBUG = 0,  ## Verbose framework narration. Debug builds only by default.
	INFO = 1,   ## Notable, infrequent events.
	WARN = 2,   ## Something is wrong but recoverable. Routed to push_warning().
	ERROR = 3,  ## Something failed. Routed to push_error().
	SILENT = 4, ## Nothing is emitted.
}

## Messages below this level are discarded. Set once at startup, or at runtime.
static var level: Level = Level.DEBUG


static func _static_init() -> void:
	# A shipped build should be quiet by default without anyone remembering to
	# make it quiet.
	level = Level.DEBUG if OS.is_debug_build() else Level.WARN


static func debug(message: String, context: String = "") -> void:
	if level <= Level.DEBUG:
		print(_format("DEBUG", message, context))


static func info(message: String, context: String = "") -> void:
	if level <= Level.INFO:
		print(_format("INFO", message, context))


## Routed to push_warning() so it appears in the editor's Debugger panel and in
## the output panel, not just stdout.
static func warn(message: String, context: String = "") -> void:
	if level <= Level.WARN:
		push_warning(_format("WARN", message, context))


## Routed to push_error() for the same reason. Reserve this for real failures:
## a clean boot of this template must produce none.
static func error(message: String, context: String = "") -> void:
	if level <= Level.ERROR:
		push_error(_format("ERROR", message, context))


static func _format(tag: String, message: String, context: String) -> String:
	if context.is_empty():
		return "[%s] %s" % [tag, message]
	return "[%s] %s: %s" % [tag, context, message]

# ---------------------------------------------------------------------------
# DELIBERATELY NOT WRITTEN: math_utils.gd and node_utils.gd
#
# The plan named three utility scripts, then said not to build a utility
# library speculatively. Both of the other two would have been wrappers around
# things Godot already ships:
#
#   math_utils "snapping"       -> @GlobalScope.snappedf() / snapped()
#   math_utils "remapping"      -> @GlobalScope.remap()
#   math_utils "safe division"  -> @GlobalScope.is_zero_approx()
#   node_utils "safe child lookup"   -> Node.get_node_or_null()
#   node_utils "deferred free helper"-> Node.queue_free() (already deferred)
#
# Re-exporting the standard library under a project-specific name makes code
# harder to read, not easier, and invites drift from the engine's own
# semantics. If a genuinely non-obvious helper appears later -- something with
# actual logic in it -- that is when the file should be created.
# ---------------------------------------------------------------------------
