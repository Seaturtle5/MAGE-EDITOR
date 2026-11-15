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
	_scan(target, true)
	reindex()
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
