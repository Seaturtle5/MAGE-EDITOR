class_name PackWorkspace
extends RefCounted
## One writable pack, explicitly loaded reference packs, and shared validation.

var target := ""
var pack_paths: Array[String] = []
var documents: Dictionary = {}
var rows: Array[Dictionary] = []
var db: ContentDB
var diagnostics: Array = []
var validation_paths: Dictionary = {}
var revision := 0
var preview_revision := -1
var preview_db: ContentDB
var history := EditHistory.new()
var validation_revision := -1

func validate_buffers() -> void:
	# The same loader operations as preview_content retain original paths.
	# Assets remain read-only at their pack paths; only text buffers are loaded.
	preview_revision = -1
	db = preview_content()
	Validator.run(db)
	diagnostics = db.diagnostics.duplicate(true)
	for folder: String in pack_paths:
		if manifest(folder).is_empty(): diagnostics.append({"severity": "error", "path": folder.path_join("pack.fsc"), "line": 1, "message": "The manifest must contain exactly one pack definition."})
	validation_revision = revision

func preview_content() -> ContentDB:
	if preview_db != null and preview_revision == revision:
		return preview_db
	preview_db = ContentDB.new()
	var found: Dictionary = {}
	for folder: String in pack_paths:
		var info := manifest(folder)
		if not info.is_empty():
			found[info.id] = info
	var paths: Array = documents.keys()
	paths.sort()
	for id: String in preview_db._load_order(found):
		for path: String in paths:
			if owner(path) != found[id].path:
				continue
			var result := FscParser.parse(documents[path].text, path)
			preview_db._parse_results.append(result)
			for definition: FscParser.Definition in result.definitions:
				if definition.type == "pack":
					preview_db.packs.append({"id": definition.id, "path": found[id].path, "def": definition})
				preview_db._add(definition, result)
	preview_db._finish()
	preview_revision = revision
	return preview_db


static func types() -> Array:
	var out: Array = ContentDB.SCHEMA.keys() + ContentDB.PENDING_TYPES
	out.sort()
	return out


func open_pack(folder: String) -> String:
	var info := manifest(folder)
	if info.is_empty():
		return "Choose a folder containing one valid pack definition in pack.fsc."
	target = folder.simplify_path().trim_suffix("/")
	pack_paths.assign([target])
	documents.clear()
	history.applying = true
	_scan(target, true)
	reindex()
	history.applying = false
	history.reset(documents)
	validate()
	return ""


func add_reference(folder: String) -> String:
	folder = folder.simplify_path().trim_suffix("/")
	if target.is_empty():
		return "Open a working pack first."
	if folder in pack_paths:
		return "This pack is already loaded."
	var info := manifest(folder)
	if info.is_empty():
		return "Choose a folder with a valid pack.fsc."
	for path in pack_paths:
		if manifest(path).id == info.id:
			return "A pack with this ID is already loaded: " + info.id
	# Parent/child packs would make ownership ambiguous.
	for path in pack_paths:
		if folder.begins_with(path + "/") or path.begins_with(folder + "/"):
			return "A reference pack must be separate from the working pack."
	pack_paths.append(folder)
	_scan(folder, false)
	reindex()
	validate()
	return ""


func manifest(folder: String) -> Dictionary:
	var path := folder.path_join("pack.fsc")
	var directory := DirAccess.open(folder)
	if directory == null or directory.is_link("pack.fsc"):
		return {}
	if not FileAccess.file_exists(path):
		return {}
	var contents: String = documents[path].text if documents.has(path) else FileAccess.get_file_as_string(path)
	var parsed := FscParser.parse(contents, path)
	if parsed.definitions.size() != 1 or parsed.definitions[0].type != "pack":
		return {}
	var definition := parsed.definitions[0]
	var requires: Array = []
	if definition.fields.has("requires"):
		for part in definition.fields["requires"].value.split(","):
			if not part.strip_edges().is_empty() and part.strip_edges() != "(none)":
				requires.append(part.strip_edges())
	return {"id": definition.id, "requires": requires, "path": folder, "manifest": path}


func _scan(folder: String, writable: bool) -> void:
	var dir := DirAccess.open(folder)
	if dir == null:
		return
	var files := dir.get_files()
	files.sort()
	for name in files:
		if name.ends_with(".fsc") and not dir.is_link(name):
			var path := folder.path_join(name)
			documents[path] = PackDocument.new(path, writable)
	var children := dir.get_directories()
	children.sort()
	for name in children:
		if not name.begins_with(".") and not dir.is_link(name):
			_scan(folder.path_join(name), writable)


func reindex() -> void:
	rows.clear()
	for path: String in documents:
		var doc: PackDocument = documents[path]
		var counts: Dictionary = {}
		for definition in doc.definitions():
			var pack := owner(path)
			var identity := definition.type + "|" + definition.id + "|" + definition.mode
			var ordinal: int = counts.get(identity, 0)
			counts[identity] = ordinal + 1
			rows.append({"def": definition, "doc": doc, "pack": manifest(pack).get("id", pack.get_file()), "root": pack, "ordinal": ordinal})
	rows.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return (a.def.type + ":" + a.def.id + ":" + a.pack).naturalnocasecmp_to(b.def.type + ":" + b.def.id + ":" + b.pack) < 0)
	revision += 1
	history.checkpoint(documents)


func owner(path: String) -> String:
	for folder in pack_paths:
		if path.begins_with(folder + "/"):
			return folder
	return ""


func find_row(path: String, type: String, id: String, mode: String = "define", ordinal: int = 0) -> Dictionary:
	for row in rows:
		if row.doc.path == path and row.def.type == type and row.def.id == id and row.def.mode == mode and row.ordinal == ordinal:
			return row
	return {}


func dirty_count() -> int:
	var count := 0
	for doc: PackDocument in documents.values():
		if doc.dirty():
			count += 1
	return count


func save_all() -> String:
	# Check the entire write set before the first write.
	for doc: PackDocument in documents.values():
		if not doc.dirty():
			continue
		if not _inside_working_pack(doc.path):
			return "Save stopped; a path is outside the working pack or passes through a link: " + doc.path
		var exists_now := FileAccess.file_exists(doc.path)
		if exists_now != doc.existed_at_open or (exists_now and FileAccess.get_file_as_string(doc.path) != doc.original):
			return "Save stopped; file changed outside the editor: " + doc.path
	for doc: PackDocument in documents.values():
		if doc.dirty():
			var error := doc.save()
			if not error.is_empty():
				return error
	return ""


func add_requirement(id: String) -> String:
	var doc: PackDocument = documents[target.path_join("pack.fsc")]
	var definition := doc.definitions()[0]
	var info := manifest(target)
	var requirements: Array = info.requires
	if id == info.id or id in requirements:
		return ""
	requirements.append(id)
	var error := doc.set_field(definition, "requires", ", ".join(requirements))
	reindex()
	return error


func create_definition(type: String, id: String, mode: String = "define", initial: String = "") -> String:
	if target.is_empty():
		return "Open a working pack first."
	if type not in types() or type == "pack":
		return "Edit the existing pack manifest in Pack instead."
	if RegEx.create_from_string("^[a-z0-9_][a-z0-9_.-]*$").search(id) == null:
		return "Use lowercase letters, numbers, underscores, dots or hyphens for the ID."
	for row in rows:
		if row.def.type == type and row.def.id == id and (row.doc.writable or mode == "define"):
			return "This type and ID already exist. Use an explicit extension or replacement for reference content."
	var folder := type + "s"
	if type.ends_with("_rules") or type in ["hook", "ending", "status_bar", "values"]:
		folder = "rules"
	elif type in ["region", "zone", "door"]:
		folder = "locations"
	elif type == "form":
		folder = "creatures"
	elif type == "menu" or type == "text" or type == "epilogue":
		folder = "scenes"
	var directory := target.path_join(folder)
	var root := DirAccess.open(target)
	if root == null or root.is_link(folder):
		return "The content folder must be inside the working pack, not a link."
	if DirAccess.make_dir_recursive_absolute(directory) != OK:
		return "Cannot create content folder."
	var path := directory.path_join(id + ".fsc")
	var suffix := 2
	while documents.has(path) or FileAccess.file_exists(path):
		path = directory.path_join(id + "_" + str(suffix) + ".fsc")
		suffix += 1
	var doc := PackDocument.new(path, true)
	documents[path] = doc
	var header := "== " + (mode + " " if mode != "define" else "") + type + " " + id
	var body := initial if not initial.is_empty() else template(type, id)
	doc.change(header + "\n" + body.trim_suffix("\n") + "\n")
	reindex()
	return ""


static func template(type: String, id: String) -> String:
	match type:
		"scene", "text": return "Write your story here."
		"menu": return "title: What would you like to do?\nleave: Leave\n* Look closer\n    You take a closer look."
		"item": return "name: " + id.capitalize() + "\ndescription: Describe this item.\nweight: 1\ncategory: other"
		"event": return "name: " + id.capitalize() + "\nrepeat: once\nplay:\n    Write what happens here."
		"character": return "name: " + id.capitalize() + "\npronouns: they\ndescription: Describe this character.\nvalues:\n    met: flag\ntalk:\n    'Hello.'"
		"creature": return "name: " + id.capitalize() + "\nlevel: 1\nhp: 10\ndamage: 2\nencounter:\n    Describe the encounter."
		"quest": return "name: " + id.capitalize() + "\nstages:\n    not_started\n    complete: The story is complete.\ndone at: complete"
		"location": return "name: " + id.capitalize() + "\nzone: none\ndescription: Describe this place."
		"values": return "values:\n    visited: flag\n    visits: number\n    mood: calm, curious, worried"
		"scenario": return "name: " + id.capitalize() + "\ndescription: Describe this starting point.\nintro:\n    Your story begins."
		"epilogue": return "// This type is defined by the format but not run by the engine yet."
		_:
			var schema: Dictionary = ContentDB.SCHEMA.get(type, {})
			return "name: " + id.capitalize() if schema.has("name") else "// Add fields using the Fields tab."


func validate() -> void:
	if target.is_empty():
		return
	# Validate current buffers, including unsaved work, with the engine's
	# loader and validator. The snapshot also isolates reference packs.
	var snapshot := OS.get_user_data_dir().path_join("validation-" + str(OS.get_process_id()) + "-" + str(Time.get_ticks_usec()))
	DirAccess.make_dir_recursive_absolute(snapshot)
	var mapping: Dictionary = {}
	var found: Dictionary = {}
	for i in pack_paths.size():
		var folder := pack_paths[i]
		var info := manifest(folder)
		if info.is_empty():
			continue
		var stage := snapshot.path_join(str(i))
		_copy_folder(folder, stage)
		mapping[stage] = folder
		for path: String in documents:
			if owner(path) == folder:
				var destination := stage.path_join(path.trim_prefix(folder + "/"))
				DirAccess.make_dir_recursive_absolute(destination.get_base_dir())
				var file := FileAccess.open(destination, FileAccess.WRITE)
				if file != null:
					file.store_string(documents[path].text)
		found[info.id] = {"path": stage, "requires": info.requires, "manifest": stage.path_join("pack.fsc")}
	db = ContentDB.new()
	validation_paths = mapping.duplicate()
	for id: String in db._load_order(found):
		db.load_pack(found[id].path)
	db._finish()
	Validator.run(db)
	diagnostics = db.diagnostics.duplicate(true)
	for diagnostic: Dictionary in diagnostics:
		diagnostic.path = _original_path(diagnostic.path, mapping)
	for declaration: Dictionary in db.values.values():
		if declaration.has("path"):
			declaration.path = _original_path(declaration.path, mapping)
	# An invalid manifest must remain visible even when it cannot be staged.
	for folder in pack_paths:
		if manifest(folder).is_empty():
			diagnostics.append({"severity": "error", "path": folder.path_join("pack.fsc"), "line": 1, "message": "The manifest must contain exactly one pack definition."})
	_remove_folder(snapshot)
	validation_revision = revision


static func _original_path(path: String, mapping: Dictionary) -> String:
	for stage: String in mapping:
		if path.begins_with(stage + "/"):
			return mapping[stage] + path.trim_prefix(stage)
	return path


static func _copy_folder(source: String, destination: String) -> void:
	DirAccess.make_dir_recursive_absolute(destination)
	var dir := DirAccess.open(source)
	if dir == null:
		return
	for name in dir.get_files():
		if not dir.is_link(name):
			DirAccess.copy_absolute(source.path_join(name), destination.path_join(name))
	for name in dir.get_directories():
		if not name.begins_with(".") and not dir.is_link(name):
			_copy_folder(source.path_join(name), destination.path_join(name))


static func _remove_folder(path: String) -> void:
	var dir := DirAccess.open(path)
	if dir == null:
		return
	for name in dir.get_files():
		DirAccess.remove_absolute(path.path_join(name))
	for name in dir.get_directories():
		_remove_folder(path.path_join(name))
	DirAccess.remove_absolute(path)


func mentions(row: Dictionary) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var token := RegEx.create_from_string("[a-z0-9_][a-z0-9_.-]*")
	for candidate in rows:
		if candidate.doc.path == row.doc.path and candidate.def.line == row.def.line:
			continue
		var contents: String = candidate.doc.block(candidate.def)
		var lines := contents.split("\n")
		for i in range(1, lines.size()):
			if lines[i].strip_edges().begins_with("//"):
				continue
			for match_token in token.search_all(lines[i]):
				if match_token.get_string() == row.def.id:
					result.append({"row": candidate, "line": candidate.def.line + i})
					break
	return result


func story_links() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var pattern := RegEx.create_from_string("(?:^|:\\s*)(?:->|play)\\s+([a-z0-9_.-]+)")
	var documents_rows: Dictionary = {}
	for row in rows:
		if not documents_rows.has(row.doc.path):
			documents_rows[row.doc.path] = []
		documents_rows[row.doc.path].append(row)
	for path: String in documents_rows:
		var entries: Array = documents_rows[path]
		entries.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a.def.line < b.def.line)
		var lines: PackedStringArray = documents[path].text.split("\n")
		for index in entries.size():
			var row: Dictionary = entries[index]
			var last_line: int = entries[index + 1].def.line - 1 if index + 1 < entries.size() else lines.size()
			for i in range(int(row.def.line), last_line):
				var clean := lines[i].strip_edges()
				if clean.begins_with("//"):
					continue
				var matched := pattern.search(clean)
				if matched != null and matched.get_string(1) not in ["end", "back"]:
					out.append({"from": row, "target": matched.get_string(1), "line": i + 1})
	return out

func _inside_working_pack(path: String) -> bool:
	if target.is_empty() or not path.begins_with(target + "/"):
		return false
	var parts := path.trim_prefix(target + "/").split("/")
	var current := target
	for part: String in parts:
		if part.is_empty() or part == "." or part == "..":
			return false
		var directory := DirAccess.open(current)
		if directory == null or directory.is_link(part):
			return false
		current = current.path_join(part)
	return true


func transaction(label: String, operation: Callable) -> String:
	var before := history.capture(documents)
	var previous_baseline := history.baseline
	history.depth += 1
	var result: Variant = operation.call()
	var error := str(result) if result is String else ""
	history.depth -= 1
	if not error.is_empty():
		history.applying = true
		history.restore(documents, before)
		history.baseline = previous_baseline
		reindex()
		history.applying = false
		return error
	history.checkpoint(documents, label)
	reindex()
	return ""

func undo() -> String:
	history.checkpoint(documents)
	history.applying = true
	var label := history.undo(documents)
	reindex()
	history.applying = false
	return label

func redo() -> String:
	history.applying = true
	var label := history.redo(documents)
	reindex()
	history.applying = false
	return label

func unique_id(display_name: String, type: String) -> String:
	var id := RegEx.create_from_string("[^a-z0-9_]+").sub(display_name.to_lower(), "_", true).strip_edges().trim_prefix("_").trim_suffix("_")
	if id.is_empty(): id = type
	var candidate := id
	var suffix := 2
	while rows.any(func(row: Dictionary) -> bool: return row.def.type == type and row.def.id == candidate):
		candidate = id + "_" + str(suffix)
		suffix += 1
	return candidate

func require_content(type: String, id: String) -> String:
	for row: Dictionary in rows:
		if row.def.type == type and row.def.id == id and row.def.mode != "extend":
			return add_requirement(row.pack) if not row.doc.writable else ""
	return ""

func require_value(path: String) -> String:
	var declaration: Dictionary = preview_content().values.get(path, {})
	var folder := owner(str(declaration.get("path", "")))
	if folder.is_empty() or folder == target: return ""
	return add_requirement(manifest(folder).id)

func require_condition(condition: Dictionary) -> String:
	var error := ""
	if condition.get("op") in ["and", "or", "not"]:
		error = require_condition(condition.a)
		if error.is_empty() and condition.has("b"): error = require_condition(condition.b)
	elif condition.get("op") == "cmp":
		for path: String in Expr.paths(condition.left) + Expr.paths(condition.right):
			error = require_value(path)
			if not error.is_empty(): return error
	elif condition.get("op") == "truthy": error = require_value(condition.path)
	elif condition.get("op") == "has_item": error = require_content("item", condition.item)
	elif condition.get("op") == "quest": error = require_content("quest", condition.quest)
	return error

func connect_places(source: Dictionary, destination: Dictionary, direction: String, two_way: bool = true) -> String:
	const OPPOSITE := {"north": "south", "northeast": "southwest", "east": "west", "southeast": "northwest", "south": "north", "southwest": "northeast", "west": "east", "northwest": "southeast", "up": "down", "down": "up", "inside": "outside", "outside": "inside"}
	if direction not in OPPOSITE or source.is_empty() or destination.is_empty(): return "Choose two places and a direction."
	if source.def.id == destination.def.id: return "Choose two different places."
	var pairs: Array = [[source, destination, direction]]
	if two_way: pairs.append([destination, source, OPPOSITE[direction]])
	return transaction("Connect " + Wording.title(source) + " and " + Wording.title(destination), func() -> String:
		for pair: Array in pairs:
			var from: Dictionary = pair[0]
			var to: Dictionary = pair[1]
			var effective := preview_content().get_def("location", from.def.id)
			if effective == null: return "This place changed. Reopen the map."
			if effective.fields.has("exits"):
				for line: FscParser.Line in effective.fields.exits.children:
					if line.text.get_slice(":", 0).strip_edges() == pair[2]:
						return "An exit already uses " + str(pair[2]) + " at " + Wording.title(from) + ". Choose another direction or a one-way exit."
			var writable: Dictionary = {}
			for candidate: Dictionary in rows:
				if candidate.doc.writable and candidate.def.type == "location" and candidate.def.id == from.def.id: writable = candidate
			var entry: String = pair[2] + ": " + to.def.id + (", one way" if not two_way else "")
			var error := ""
			if writable.is_empty(): error = create_definition("location", from.def.id, "extend", "exits:\n    " + entry)
			else:
				var field: FscParser.Field = writable.def.fields.get("exits")
				if field == null: error = writable.doc.set_field(writable.def, "exits", entry, true)
				elif not field.value.is_empty(): return "This exit section uses a layout that must be kept."
				else:
					var lines := StoryGraph._lines(writable.doc)
					var insertion: int = field.children[-1].number if not field.children.is_empty() else field.line
					StoryGraph._insert_line(writable.doc, lines, insertion, "    " + entry)
					StoryGraph._save_lines(writable.doc, lines)
			if not error.is_empty(): return error
			for referenced: Dictionary in [from, to]:
				if not referenced.doc.writable:
					error = add_requirement(referenced.pack)
					if not error.is_empty(): return error
			reindex()
		return "")

var _titles: Dictionary = {}
var _titles_revision := -1

## The name an author sees for content; with an empty type, any type holding the ID.
func title_of(type: String, id: String) -> String:
	if _titles_revision != revision:
		_titles.clear()
		for row: Dictionary in rows:
			if row.def.mode == "extend" or not row.def.fields.has("name"): continue
			var title: String = row.def.fields.name.value
			if title.is_empty(): continue
			_titles[row.def.type + ":" + row.def.id] = title
			if not _titles.has(":" + row.def.id) or row.def.type == "character": _titles[":" + row.def.id] = title
		_titles_revision = revision
	return _titles.get(type + ":" + id, _titles.get(":" + id, "") if type in ["", "who", "holder"] else "")

## Adds "name: spec" to a definition's values (for example "trust: number 0").
func declare_value(type: String, id: String, name: String, spec: String) -> String:
	if RegEx.create_from_string("^[a-z_][a-z0-9_]*$").search(name) == null: return "Use a name of letters and numbers."
	if spec.strip_edges().is_empty(): return "Name at least two stages, with commas between."
	if preview_content().values.has(id + "." + name): return "This name is already used there. Choose another."
	for row: Dictionary in rows:
		if not row.doc.writable or row.def.type != type or row.def.id != id or row.def.mode == "replace": continue
		var field: FscParser.Field = row.def.fields.get("values")
		if field == null: return row.doc.set_field(row.def, "values", name + ": " + spec, true)
		if not field.value.is_empty(): return "These saved values use a layout that must be kept."
		var lines := StoryGraph._lines(row.doc)
		var last: int = field.children[-1].number if not field.children.is_empty() else field.line
		StoryGraph._insert_line(row.doc, lines, last, "    " + name + ": " + spec)
		StoryGraph._save_lines(row.doc, lines)
		return ""
	return "Choose content in your own pack to hold this value."

var _words: Dictionary = {}
var _words_revision := -1

## Words already used in the loaded packs, to suggest where the engine takes any word.
func known_words(list: String) -> Array:
	if BlockCatalog.WORDS.has(list): return BlockCatalog.WORDS[list]
	if _words_revision != revision:
		_words.clear()
		_words_revision = revision
	if _words.has(list): return _words[list]
	var found: Dictionary = {}
	var pattern: RegEx = null
	match list:
		"trait": pattern = RegEx.create_from_string("\\btrait(?: [+-])? ([a-z0-9_]+)")
		"mode": pattern = RegEx.create_from_string("\\bmode ([a-z0-9_]+)")
		"variant": pattern = RegEx.create_from_string("\\bvariant ([a-z0-9_]+)")
		"place_flag": pattern = RegEx.create_from_string("\\bflagged ([a-z][a-z ]*?)(?:\\]|:| and | or |$)")
		"ending_flag": pattern = RegEx.create_from_string("\\bending flag ([a-z0-9_]+)")
		"interest": pattern = RegEx.create_from_string("\\binterested in ([a-z_]+)")
	for row: Dictionary in rows:
		if list == "tag" and row.def.type in ["tag", "filter"]: found[row.def.id] = true
		if list == "tag" and row.def.fields.has("tags"):
			for tag: String in str(row.def.fields.tags.value).split(","):
				if not tag.strip_edges().is_empty(): found[tag.strip_edges()] = true
		if list == "place_flag" and row.def.fields.has("flags"):
			for flag: String in str(row.def.fields.flags.value).split(","):
				if not flag.strip_edges().is_empty(): found[flag.strip_edges()] = true
	if pattern != null:
		for path: String in documents:
			for matched: RegExMatch in pattern.search_all(documents[path].text): found[matched.get_string(1)] = true
	if list == "place_flag":
		for flag: String in Validator.LOCATION_FLAGS: found[flag] = true
	var result: Array = found.keys()
	result.sort()
	_words[list] = result
	return result

var _uses: Dictionary = {}
var _uses_revision := -1

## Where each ID is mentioned in the working pack: id -> [{row, line, text}].
## Comments and the content's own block do not count.
func uses_index() -> Dictionary:
	if _uses_revision == revision: return _uses
	_uses.clear()
	_uses_revision = revision
	var known: Dictionary = {}
	for row: Dictionary in rows: known[row.def.id] = true
	var token := RegEx.create_from_string("[a-z0-9_][a-z0-9_-]*")
	for row: Dictionary in rows:
		if not row.doc.writable: continue
		var lines: PackedStringArray = str(row.doc.block(row.def)).split("\n")
		for index in range(1, lines.size()):
			var clean := lines[index].strip_edges()
			if clean.is_empty() or clean.begins_with("//"): continue
			var seen: Dictionary = {}
			var code := ContentTools.code_text(lines[index].trim_suffix("\r"))
			for matched: RegExMatch in token.search_all(code):
				var id := matched.get_string()
				if not known.has(id) or id == row.def.id or seen.has(id): continue
				# In "adam.trust" only the owner is content; "trust" is its value.
				if matched.get_start() > 0 and code[matched.get_start() - 1] == ".": continue
				seen[id] = true
				if not _uses.has(id): _uses[id] = []
				_uses[id].append({"row": row, "line": int(row.def.line) + index, "text": clean})
	return _uses

func uses(id: String) -> Array:
	return uses_index().get(id, [])

## Short notes on what a piece of content still needs, for the home page.
func hints(row: Dictionary) -> Array[String]:
	var notes: Array[String] = []
	var definition: FscParser.Definition = row.def
	var used := uses(definition.id).size()
	match str(definition.type):
		"scene", "menu":
			notes.append("✓ written" if not StoryGraph.structure(row).is_empty() else "⚠ nothing written yet")
			notes.append("✓ connected" if used > 0 else "⚠ nothing leads here yet")
		"event":
			notes.append("✓ written" if definition.fields.has("play") else "⚠ nothing written yet")
			notes.append("✓ has a start" if definition.fields.has("found by") or used > 0 else "⚠ nothing starts this yet")
		"character":
			notes.append("✓ talks" if definition.fields.has("talk") else "⚠ no conversation yet")
			notes.append("✓ has a home" if definition.fields.has("lives at") else "⚠ lives nowhere yet")
		"item":
			notes.append("✓ can be used" if definition.fields.has("use") or definition.fields.has("use action") or definition.fields.has("equipment") or definition.fields.has("weapon") else "· no use story")
			notes.append("✓ can be found" if used > 0 else "⚠ nothing gives this yet")
		"location":
			notes.append("✓ connected" if definition.fields.has("exits") or used > 0 else "⚠ no paths lead here yet")
		"quest":
			notes.append("✓ moved by stories" if used > 0 else "⚠ nothing moves this quest yet")
		"creature":
			notes.append("✓ can be met" if definition.fields.has("found in") or used > 0 else "⚠ met nowhere yet")
		_:
			notes.append(Wording.name(definition.type))
	return notes
