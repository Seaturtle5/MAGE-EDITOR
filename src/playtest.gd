class_name Playtest
extends RefCounted
## Runs the real game on the loaded packs, unsaved changes included, in its own
## window with its own saves and settings. The player's saves and the other
## packs are never touched.

var folder := ""
var process := -1

static func engine_path() -> String:
	return OS.get_environment("MAGE_ENGINE_PATH")

## Why the game cannot be started, or nothing.
static func problem() -> String:
	var path := engine_path()
	if path.is_empty(): return "The game is not connected. Start the editor with “run.sh --engine PATH” to try your pack in the game."
	if not FileAccess.file_exists(path.path_join("project.godot")) or not FileAccess.file_exists(path.path_join("ui/main.gd")): return "This engine folder has no game to run: " + path
	return ""

## The story of a piece of content, as the game's --play option takes it.
static func story_id(row: Dictionary) -> String:
	if row.is_empty(): return ""
	var type: String = row.def.type
	var field: String = row.get("script_field", "")
	if type in ["scene", "menu"] and field.is_empty(): return row.def.id
	if type == "event" and field in ["", "play"]: return "event:" + str(row.def.id)
	var key := field if not field.is_empty() else StoryBlocks.script_key(row)
	return "%s:%s#%s" % [type, row.def.id, key] if not key.is_empty() else ""

static func scenarios(workspace: PackWorkspace) -> Array[Dictionary]:
	var own: Array[Dictionary] = []
	var others: Array[Dictionary] = []
	for row: Dictionary in workspace.rows:
		if row.def.type == "scenario" and row.def.mode != "extend":
			if row.doc.writable: own.append(row)
			else: others.append(row)
	return own + others

## A place to stand in while a story is tried: where its owner lives, where
## its event is found, where a scenario starts, or any place.
static func place_for(workspace: PackWorkspace, row: Dictionary) -> String:
	var db := workspace.preview_content()
	var places: Dictionary = {}
	for other: Dictionary in workspace.rows:
		if other.def.type == "location" and other.def.mode != "extend": places[other.def.id] = other.doc.writable
	if not row.is_empty():
		if row.def.type == "location": return row.def.id
		var home: String = row.doc.field_value(row.def, "lives at")
		if places.has(home): return home
		for word: String in str(row.doc.field_value(row.def, "found by")).replace(";", " ").split(" ", false):
			if places.has(word): return word
	for scenario: Dictionary in scenarios(workspace):
		var start: String = db.typed_value("scenario", scenario.def.id, "start", "")
		if places.has(start): return start
	for id: String in places:
		if places[id]: return id
	return places.keys()[0] if not places.is_empty() else ""

## The values a sample player starts with, as --set options.
static func sample_values(sample: Dictionary) -> Dictionary:
	var values: Dictionary = {}
	var sex: String = sample.get("sex", "")
	if not sex.is_empty():
		values["player.cocks"] = 1 if sex in ["male", "herm"] else 0
		values["player.cunts"] = 1 if sex in ["female", "herm"] else 0
	if int(sample.get("level", 1)) > 1: values["player.level"] = int(sample.level)
	for key: String in sample.get("values", {}): values[key] = sample.values[key]
	return values

## The game's command line for this try-out: {args, packs} or {error}.
## `begin` is {scenario: id} or {start: location}; `play` a story or nothing.
func arguments(workspace: PackWorkspace, begin: Dictionary, play: String = "", sample: Dictionary = {}) -> Dictionary:
	if workspace.target.is_empty(): return {"error": "Open a pack first."}
	if not begin.has("scenario") and str(begin.get("start", "")).is_empty(): return {"error": "The game needs a place to start in. Add a place to your pack first."}
	# The game checks everything itself as it loads; with very many packs the quick check is enough here.
	if workspace.rows.size() > PackWorkspace.LIGHT: workspace.check_working()
	else: workspace.validate()
	var errors := workspace.diagnostics.filter(func(item: Dictionary) -> bool: return item.severity == "error")
	if not errors.is_empty(): return {"error": "The game cannot start while the pack has problems. The first: " + str(errors[0].message)}
	clear()
	folder = OS.get_user_data_dir().path_join("playtest-%d-%d" % [OS.get_process_id(), Time.get_ticks_msec()])
	if DirAccess.make_dir_recursive_absolute(folder.path_join("data")) != OK: return {"error": "Could not make a folder for the try-out."}
	var working := workspace.target
	if workspace.dirty_count() > 0:
		# Unsaved changes are tried too: the game reads a copy that holds them.
		working = folder.path_join("pack")
		PackWorkspace._copy_folder(workspace.target, working)
		for path: String in workspace.documents:
			var doc: PackDocument = workspace.documents[path]
			if not doc.writable: continue
			var copy := working.path_join(path.trim_prefix(workspace.target + "/"))
			DirAccess.make_dir_recursive_absolute(copy.get_base_dir())
			var file := FileAccess.open(copy, FileAccess.WRITE)
			if file == null: return {"error": "Could not write the try-out copy of " + path.get_file()}
			file.store_string(doc.text)
	var packs: Array[String] = [working]
	for reference: String in workspace.pack_paths.slice(1): packs.append(reference)
	var args: Array[String] = ["--path", engine_path(), "--", "--only-packs"]
	for pack: String in packs: args.append_array(["--packs", pack])
	args.append_array(["--data", folder.path_join("data")])
	if begin.has("scenario"): args.append_array(["--scenario", str(begin.scenario)])
	else: args.append_array(["--start", str(begin.start)])
	if not play.is_empty(): args.append_array(["--play", play])
	var values := sample_values(sample)
	for key: String in values:
		var value: Variant = values[key]
		args.append_array(["--set", key + "=" + ("yes" if value is bool and value else "no" if value is bool else str(value))])
	return {"args": args, "packs": packs}

## Starts the game. Returns an error text, or nothing when it started.
func run(workspace: PackWorkspace, begin: Dictionary, play: String = "", sample: Dictionary = {}) -> String:
	var issue := problem()
	if not issue.is_empty(): return issue
	stop()
	var prepared := arguments(workspace, begin, play, sample)
	if prepared.has("error"): return prepared.error
	process = OS.create_process(OS.get_executable_path(), prepared.args)
	return "" if process > 0 else "The game could not be started."

func running() -> bool:
	return process > 0 and OS.is_process_running(process)

func stop() -> void:
	if running(): OS.kill(process)
	process = -1

## Removes the try-out's own folder: its copy of the pack and its saves.
func clear() -> void:
	if not folder.is_empty() and folder.begins_with(OS.get_user_data_dir().path_join("playtest-")): PackWorkspace._remove_folder(folder)
	folder = ""
