## game_state.gd  --  registered as the `GameState` autoload.
##
## WHAT: A generic key/value container with change notification and optional
##       JSON persistence.
##
## RESPONSIBLE FOR: holding whatever a game built on this template decides its
##       state is, and telling interested nodes when a value changes.
##
## WHAT IT IS NOT: a save system, an inventory, a player stat block, or a
##       progression tracker. It ships EMPTY and stays empty. If you find
##       yourself adding a `player_health` property here, that is game content
##       and belongs in the game. The template dictates the mechanism, never
##       the schema.
##
## KEYS: Strings. StringName is accepted and converted automatically, which
##       matters because a Dictionary treats &"x" and "x" as distinct keys
##       while a JSON round trip turns one into the other.
##
## VERIFIED JSON HAZARDS (Godot 4.7.1) -- both handled below:
##   1. Integers come back from JSON as floats. TYPE_INT goes in, TYPE_FLOAT
##      comes out. That is why the typed accessors exist; use get_int() rather
##      than get_value() when the value must survive a save.
##   2. JSON.stringify() does not reject non-JSON types, it MANGLES them.
##      Vector2(1, 2) is written as the string "(1.0, 2.0)" and returns as a
##      String. save_to_file() therefore validates first and refuses to write,
##      rather than producing a file that loads without error and is wrong.

extends Node

## Emitted after a value changes. `old_value` is null if the key was unset.
## clear() and load_from_file() emit this once per key that actually changed.
signal state_changed(key: String, old_value: Variant, new_value: Variant)

## Where save_to_file()/load_from_file() go when no path is given. `user://` is
## the only reliably writable location across export platforms, web included.
const DEFAULT_SAVE_PATH: String = "user://game_state.json"

var _values: Dictionary = {}


# --- Core accessors --------------------------------------------------------

## Stores a value, emitting state_changed only if it actually differs.
func set_value(key: String, value: Variant) -> void:
	var had: bool = _values.has(key)
	var old: Variant = _values.get(key)
	if had and old == value:
		return
	_values[key] = value
	state_changed.emit(key, old, value)


func get_value(key: String, default: Variant = null) -> Variant:
	return _values.get(key, default)


func has_value(key: String) -> bool:
	return _values.has(key)


## Returns true if the key existed and was removed.
func erase_value(key: String) -> bool:
	if not _values.has(key):
		return false
	var old: Variant = _values[key]
	_values.erase(key)
	state_changed.emit(key, old, null)
	return true


## Removes everything, emitting one state_changed per key so listeners react to
## their key disappearing instead of silently holding a stale value.
func clear() -> void:
	var previous: Dictionary = _values
	_values = {}
	for key in previous:
		state_changed.emit(key, previous[key], null)


## A copy of every key currently set. Useful for a debug overlay.
func keys() -> PackedStringArray:
	var out := PackedStringArray()
	for key in _values:
		out.append(String(key))
	return out


# --- Typed accessors -------------------------------------------------------
# These exist because of JSON hazard 1 above: after a save/load round trip an
# int is a float. Reading through these makes a value's type independent of
# whether it has been through a file yet.

func get_int(key: String, default: int = 0) -> int:
	var v: Variant = _values.get(key, default)
	return int(v) if (v is int or v is float or v is bool) else default


func get_float(key: String, default: float = 0.0) -> float:
	var v: Variant = _values.get(key, default)
	return float(v) if (v is int or v is float or v is bool) else default


func get_bool(key: String, default: bool = false) -> bool:
	var v: Variant = _values.get(key, default)
	return bool(v) if (v is bool or v is int or v is float) else default


func get_string(key: String, default: String = "") -> String:
	var v: Variant = _values.get(key, default)
	return String(v) if (v is String or v is StringName) else default


# --- Persistence -----------------------------------------------------------
# Optional. A derived game gets working persistence for free without the
# template deciding what a save file contains.

## Writes the whole store to `path` as indented JSON.
## Returns OK, or an error WITHOUT writing anything if any value would be
## mangled by JSON (hazard 2 in the header). A silently lossy save is worse
## than no save.
func save_to_file(path: String = DEFAULT_SAVE_PATH) -> Error:
	var unsafe := PackedStringArray()
	for key in _values:
		if not _is_json_safe(_values[key]):
			unsafe.append("%s (%s)" % [key, type_string(typeof(_values[key]))])
	if not unsafe.is_empty():
		DebugLog.error("Refusing to save: these values cannot survive JSON: %s. Convert them to arrays or strings first."
				% ", ".join(unsafe), "GameState")
		return ERR_INVALID_DATA

	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		var err := FileAccess.get_open_error()
		DebugLog.error("Cannot open '%s' for writing: %s" % [path, error_string(err)], "GameState")
		return err
	file.store_string(JSON.stringify(_values, "\t"))
	file.close()
	DebugLog.info("Saved %d key(s) to %s" % [_values.size(), path], "GameState")
	return OK


## Replaces the whole store from `path`, emitting state_changed for every key
## whose value actually changed. A missing file returns ERR_FILE_NOT_FOUND and
## leaves current state untouched -- that is the normal "no save yet" case, not
## a failure, so it is deliberately not logged as an error.
func load_from_file(path: String = DEFAULT_SAVE_PATH) -> Error:
	if not FileAccess.file_exists(path):
		return ERR_FILE_NOT_FOUND

	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		var err := FileAccess.get_open_error()
		DebugLog.error("Cannot open '%s' for reading: %s" % [path, error_string(err)], "GameState")
		return err
	var text := file.get_as_text()
	file.close()

	# JSON.new().parse() rather than JSON.parse_string(), because it reports the
	# offending line and message instead of just returning null.
	var json := JSON.new()
	var parse_err := json.parse(text)
	if parse_err != OK:
		DebugLog.error("Malformed JSON in '%s' at line %d: %s"
				% [path, json.get_error_line(), json.get_error_message()], "GameState")
		return ERR_PARSE_ERROR
	if not (json.data is Dictionary):
		DebugLog.error("'%s' holds a %s at the top level; expected an object."
				% [path, type_string(typeof(json.data))], "GameState")
		return ERR_INVALID_DATA

	var incoming: Dictionary = json.data
	var previous: Dictionary = _values
	_values = incoming

	# Emit only for keys that actually differ, so reloading identical state is
	# silent rather than a storm of no-op signals.
	var touched := {}
	for key in previous:
		touched[key] = true
	for key in incoming:
		touched[key] = true
	for key in touched:
		var old: Variant = previous.get(key)
		var fresh: Variant = incoming.get(key)
		if old != fresh:
			state_changed.emit(String(key), old, fresh)

	DebugLog.info("Loaded %d key(s) from %s" % [_values.size(), path], "GameState")
	return OK


## True if `value` survives a JSON round trip without being rewritten as
## something else. Recursive, because a Dictionary can hide a Vector2.
func _is_json_safe(value: Variant) -> bool:
	match typeof(value):
		TYPE_NIL, TYPE_BOOL, TYPE_INT, TYPE_FLOAT, TYPE_STRING, TYPE_STRING_NAME:
			return true
		TYPE_ARRAY:
			for item in value:
				if not _is_json_safe(item):
					return false
			return true
		TYPE_DICTIONARY:
			for key in value:
				if not (key is String or key is StringName):
					return false
				if not _is_json_safe(value[key]):
					return false
			return true
		_:
			return false
