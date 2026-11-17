class_name PackWorkspace
extends RefCounted
## One writable pack, explicitly loaded reference packs, and shared validation.

signal checked
signal packs_loaded(count: int, refused: Dictionary)

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
## The other packs, loaded once: every check and preview loads only the
## working pack again on top of them (the engine's ContentDB.layer()).
var _base: ContentDB
var _base_key := "-"
## Problems a check of every pack found in the other packs' stories. A check
## of the working pack alone keeps them until every pack is checked again.
var _other_problems: Array = []

# ------------------------------------------------------------ loaded content

## id -> {id, requires, path, manifest} of every loaded pack.
func _found() -> Dictionary:
	var found: Dictionary = {}
	for folder: String in pack_paths:
		var info := manifest(folder)
		if not info.is_empty(): found[info.id] = info
	return found

## folder -> its files in order, for the packs that can (or cannot) be changed.
func _files_by_pack(writable: bool) -> Dictionary:
	var by_pack: Dictionary = {}
	var paths: Array = documents.keys()
	paths.sort()
	for path: String in paths:
		if documents[path].writable != writable: continue
		var folder := owner(path)
		if not by_pack.has(folder): by_pack[folder] = []
		by_pack[folder].append(path)
	return by_pack

## Hands a pack's parsed files to the engine's loader, as the game reads a pack folder.
static func _add_pack(content: ContentDB, folder: String, paths: Array, results: Dictionary, texts: Dictionary = {}) -> void:
	for path: String in paths:
		var result: FscParser.Result = results[path]
		if texts.has(path) and "// UNCONVERTED:" in str(texts[path]): content._check_unconverted(texts[path], path)
		content.diagnostics.append_array(result.diagnostics.duplicate(true))
		content._parse_results.append(result)
		for definition: FscParser.Definition in result.definitions:
			if definition.type == "pack":
				content.packs.append({"id": definition.id, "path": folder, "def": definition, "folder": 0, "art": definition.fields["art"].value if definition.fields.has("art") else ""})
			content._add(definition, result)

## The other packs as the game loads them, each after the packs it needs,
## without the working pack. The engine copies a definition before an
## extension adds to it, so the editor's parsed definitions stay as written.
static func build_base(found: Dictionary, target_id: String, by_pack: Dictionary, results: Dictionary) -> ContentDB:
	var content := ContentDB.new()
	content.protect_definitions = true
	for id: String in content._load_order(found):
		if id != target_id: _add_pack(content, found[id].path, by_pack.get(found[id].path, []), results)
	content._finish()
	return content

func _results(writable: bool) -> Dictionary:
	var results: Dictionary = {}
	for path: String in documents:
		if documents[path].writable == writable: results[path] = documents[path].parsed()
	return results

func base_content() -> ContentDB:
	if _base == null or _base_key != _reference_cache_key:
		var timing := Perf.start()
		_base = build_base(_found(), str(manifest(target).get("id", "")), _files_by_pack(false), _results(false))
		_base_key = _reference_cache_key
		_other_problems.clear()
		Perf.stop("workspace: the other packs' content", timing)
	return _base

## The loaded content with unsaved changes: the working pack over the others.
func _working_content(base: ContentDB, paths: Array, results: Dictionary, texts: Dictionary) -> ContentDB:
	var content := base.layer()
	_add_pack(content, target, paths, results, texts)
	content._finish()
	return content

## What the game would load, unsaved changes included. Worked out again
## after a change, from the working pack alone.
func preview_content() -> ContentDB:
	if preview_db != null and preview_revision == revision:
		return preview_db
	var timing := Perf.start()
	var texts: Dictionary = {}
	var paths: Array = _files_by_pack(true).get(target, [])
	for path: String in paths: texts[path] = documents[path].text
	preview_db = _working_content(base_content(), paths, _results(true), texts)
	preview_revision = revision
	Perf.stop("workspace: content for pickers and preview", timing)
	return preview_db

# -------------------------------------------------------------------- checks

## Takes a finished check's problems: all of them, or the working pack's with
## what the last check of every pack found in the others' stories.
func _take(found: Array, everything: bool, at_revision: int) -> void:
	var fresh: Array = found.duplicate(true)
	for folder: String in pack_paths:
		if manifest(folder).is_empty(): fresh.append({"severity": "error", "path": folder.path_join("pack.fsc"), "line": 1, "message": "The manifest must contain exactly one pack definition."})
	if everything:
		_other_problems = fresh.filter(func(item: Dictionary) -> bool: return not str(item.path).begins_with(target + "/"))
	else:
		var seen: Dictionary = {}
		for item: Dictionary in fresh: seen[str(item.path) + ":" + str(int(item.line)) + ":" + str(item.message)] = true
		for item: Dictionary in _other_problems:
			if not seen.has(str(item.path) + ":" + str(int(item.line)) + ":" + str(item.message)): fresh.append(item)
	diagnostics = fresh
	diagnostics_revision += 1
	validation_revision = at_revision
	for path: String in documents:
		if documents[path].writable: _seen_versions[path] = documents[path].version

## Checks the working pack against the loaded packs with the engine's
## validator, unsaved changes included. With `everything`, the other packs'
## stories are checked again too (slow with many packs).
func validate_buffers(everything: bool = false) -> void:
	preview_revision = -1
	db = preview_content()
	Validator.run(db, [] if everything or pack_paths.size() < 2 else [target])
	_take(db.diagnostics, everything or pack_paths.size() < 2, revision)

# ----- the same check on another thread, for the window

var _check_thread: Thread
var _check_result: Dictionary = {}
var _check_again := false
var _check_again_everything := false
var _thread_parses: Dictionary = {}
var checking := false
var checking_everything := false

## Starts a check that does not hold up the window; `checked` is emitted when
## its result is in (see poll()). A change made meanwhile starts it again.
func request_check(everything: bool = false) -> void:
	if target.is_empty(): return
	if _check_thread != null or _load_thread != null:
		_check_again = true
		_check_again_everything = _check_again_everything or everything
		return
	var job := {"revision": revision, "everything": everything or pack_paths.size() < 2, "target": target, "texts": {}, "versions": {}, "paths": _files_by_pack(true).get(target, []), "base": _base if _base_key == _reference_cache_key else null, "base_key": _reference_cache_key}
	for path: String in job.paths:
		job.texts[path] = documents[path].text
		job.versions[path] = documents[path].version
	if job.base == null:
		job.found = _found()
		job.target_id = str(manifest(target).get("id", ""))
		job.by_pack = _files_by_pack(false)
		job.results = _results(false)
	checking = true
	checking_everything = job.everything
	_check_thread = Thread.new()
	_check_thread.start(_check_job.bind(job))

func _check_job(job: Dictionary) -> void:
	# This thread parses the working pack for itself: the window's own parse
	# moves with every edit.
	var results: Dictionary = {}
	for path: String in job.paths:
		var kept: Array = _thread_parses.get(path, [])
		if kept.is_empty() or kept[0] != job.texts[path]:
			kept = [job.texts[path], FscParser.parse(job.texts[path], path)]
			_thread_parses[path] = kept
		results[path] = kept[1]
	for path: String in _thread_parses.keys():
		if not results.has(path): _thread_parses.erase(path)
	var base: ContentDB = job.base
	if base == null: base = build_base(job.found, job.target_id, job.by_pack, job.results)
	var content := base.layer()
	_add_pack(content, job.target, job.paths, results, job.texts)
	content._finish()
	Validator.run(content, [] if job.everything else [job.target])
	_check_result = {"job": job, "found": content.diagnostics, "base": base}

func _check_finished(result: Dictionary) -> void:
	var job: Dictionary = result.job
	checking = false
	if job.target != target: return
	if job.base == null and job.base_key == _reference_cache_key and (_base == null or _base_key != _reference_cache_key):
		_base = result.base
		_base_key = job.base_key
	var again: bool = _check_again or job.revision != revision
	var everything: bool = _check_again_everything or (job.everything and job.revision != revision and pack_paths.size() >= 2)
	_check_again = false
	_check_again_everything = false
	if job.revision == revision and job.base_key == _reference_cache_key:
		_take(result.found, job.everything, revision)
		checked.emit()
	if again: request_check(everything)

## Collects what the other threads have finished. The window calls it every frame.
func poll() -> void:
	if _load_thread != null and not _load_thread.is_alive():
		_load_thread.wait_to_finish()
		_load_thread = null
		var result := _load_result
		_load_result = {}
		_load_finished(result)
	if _check_thread != null and not _check_thread.is_alive():
		_check_thread.wait_to_finish()
		_check_thread = null
		var result := _check_result
		_check_result = {}
		_check_finished(result)

## Waits for the work on other threads to end and takes its results (tests, closing the window).
func settle() -> void:
	while _check_thread != null or _load_thread != null:
		OS.delay_msec(2)
		poll()

# ----- loading other packs

var _load_thread: Thread
var _load_result: Dictionary = {}
var loading := false
var loading_count := 0

## The packs in the folder beside the working pack that belong with it: the
## packs it needs, the packs that need it, and the packs that need a pack it
## needs too (the other packs of the same game).
func packs_beside() -> Array:
	var out: Array = []
	var mine := manifest(target)
	if mine.is_empty(): return out
	var parent := target.get_base_dir()
	var infos: Dictionary = {mine.id: mine}
	for folder: String in pack_paths:
		var info := manifest(folder)
		if not info.is_empty(): infos[info.id] = info
	var candidates: Dictionary = {}
	for name: String in DirAccess.get_directories_at(parent):
		var folder := parent.path_join(name)
		if folder == target or folder in pack_paths or name.begins_with("."): continue
		var info := manifest(folder)
		if info.is_empty() or infos.has(info.id): continue
		infos[info.id] = info
		candidates[info.id] = folder
	var needs := func(id: String) -> Dictionary:
		var seen: Dictionary = {}
		var queue: Array = [id]
		while not queue.is_empty():
			var next: String = queue.pop_back()
			for other: String in infos.get(next, {}).get("requires", []):
				if not seen.has(other):
					seen[other] = true
					queue.append(other)
		return seen
	var wanted: Dictionary = needs.call(mine.id)
	for id: String in candidates:
		var theirs: Dictionary = needs.call(id)
		var shared: bool = wanted.has(id) or theirs.has(mine.id)
		for other: String in theirs:
			if wanted.has(other): shared = true
		if shared: out.append(candidates[id])
	out.sort()
	return out

## Reads pack folders: their files, parsed on every processor at once, and
## the rows of their definitions in order. Touches nothing of the workspace,
## so it can run on another thread.
static func read_packs(folders: Array, taken_ids: Dictionary, taken_paths: Array) -> Dictionary:
	var out := {"accepted": [], "refused": {}, "documents": {}, "rows": [], "infos": {}}
	var ids := taken_ids.duplicate()
	var paths: Array = taken_paths.duplicate()
	var files: Array[String] = []
	var owners: Array[String] = []
	for raw: String in folders:
		var folder := raw.simplify_path().trim_suffix("/")
		if folder in paths: continue
		var info := read_manifest(folder)
		if info.is_empty(): out.refused[folder] = "It has no valid pack.fsc."
		elif ids.has(info.id): out.refused[folder] = "A pack with the ID %s is already loaded." % info.id
		elif paths.any(func(path: String) -> bool: return folder.begins_with(path + "/") or path.begins_with(folder + "/")): out.refused[folder] = "It must be separate from the packs already loaded."
		else:
			ids[info.id] = true
			paths.append(folder)
			out.accepted.append(folder)
			out.infos[folder] = info
			var found: Array[String] = []
			_list_files(folder, found)
			for path: String in found:
				files.append(path)
				owners.append(folder)
	var texts: Array[String] = []
	for path: String in files: texts.append(FileAccess.get_file_as_string(path))
	var results: Array = []
	results.resize(files.size())
	if files.size() > 8:
		var task := WorkerThreadPool.add_group_task(func(index: int) -> void: results[index] = FscParser.parse(texts[index], files[index]), files.size(), -1, false, "Reading packs")
		WorkerThreadPool.wait_for_group_task_completion(task)
	else:
		for index in files.size(): results[index] = FscParser.parse(texts[index], files[index])
	var rows: Array[Dictionary] = []
	for index in files.size():
		var doc := PackDocument.new(files[index], false, texts[index])
		doc.adopt(results[index])
		out.documents[files[index]] = doc
		rows.append_array(rows_of(doc, str(out.infos[owners[index]].id), owners[index]))
	rows.sort_custom(_row_order)
	out.rows = rows
	return out

static func _list_files(folder: String, out: Array[String]) -> void:
	var dir := DirAccess.open(folder)
	if dir == null: return
	var files := dir.get_files()
	files.sort()
	for name in files:
		if name.ends_with(".fsc") and not dir.is_link(name): out.append(folder.path_join(name))
	var children := dir.get_directories()
	children.sort()
	for name in children:
		if not name.begins_with(".") and not dir.is_link(name): _list_files(folder.path_join(name), out)

## A pack's ID and the packs it needs, read from its folder.
static func read_manifest(folder: String) -> Dictionary:
	var path := folder.path_join("pack.fsc")
	var directory := DirAccess.open(folder)
	if directory == null or directory.is_link("pack.fsc") or not FileAccess.file_exists(path): return {}
	return _manifest_of(FscParser.parse(FileAccess.get_file_as_string(path), path), folder)

static func _manifest_of(parsed: FscParser.Result, folder: String) -> Dictionary:
	# Like the game: the file names one pack; it may hold other definitions too.
	var named := parsed.definitions.filter(func(candidate: FscParser.Definition) -> bool: return candidate.type == "pack")
	if named.size() != 1: return {}
	var definition: FscParser.Definition = named[0]
	var requires: Array = []
	if definition.fields.has("requires"):
		for part in definition.fields["requires"].value.split(","):
			if not part.strip_edges().is_empty() and part.strip_edges() != "(none)":
				requires.append(part.strip_edges())
	return {"id": definition.id, "requires": requires, "path": folder, "manifest": folder.path_join("pack.fsc")}

## Takes what read_packs() brought into the workspace.
func _adopt(read: Dictionary) -> void:
	var first: bool = _reference_rows.is_empty() and pack_paths.size() == 1
	for folder: String in read.accepted: pack_paths.append(folder)
	documents.merge(read.documents)
	if first:
		# Nothing but the working pack was loaded: the rows are ready as read.
		_reference_rows = read.rows
		_reference_keys.clear()
		_reference_index.clear()
		for row: Dictionary in _reference_rows:
			_reference_keys.append(row.sort)
			_reference_index[row_key(row.doc.path, row.def.type, row.def.id, row.def.mode, row.ordinal)] = row
		_reference_cache_key = "|".join(pack_paths) + "|" + str(documents.size())
	_base = read.get("base", null)
	_base_key = _reference_cache_key if _base != null and first else "-"
	_other_problems.clear()
	reindex()

## Loads other packs to use their content without holding up the window;
## `packs_loaded` is emitted when they are in (see poll()).
func load_packs(folders: Array) -> void:
	if target.is_empty() or folders.is_empty() or _load_thread != null: return
	var ids: Dictionary = {}
	for path: String in pack_paths: ids[manifest(path).get("id", "")] = true
	var job := {"folders": folders, "ids": ids, "paths": pack_paths.duplicate(), "target": target, "found": _found(), "target_id": str(manifest(target).get("id", "")), "by_pack": _files_by_pack(false), "results": _results(false)}
	loading = true
	loading_count = folders.size()
	_load_thread = Thread.new()
	_load_thread.start(_load_job.bind(job))

func _load_job(job: Dictionary) -> void:
	var read := read_packs(job.folders, job.ids, job.paths)
	# The other packs' content, ready for the first check and the pickers.
	var found: Dictionary = job.found.duplicate()
	var by_pack: Dictionary = job.by_pack.duplicate()
	var results: Dictionary = job.results.duplicate()
	for folder: String in read.accepted:
		found[read.infos[folder].id] = read.infos[folder]
		by_pack[folder] = []
	var paths: Array = read.documents.keys()
	paths.sort()
	for path: String in paths:
		results[path] = read.documents[path].parsed()
		for folder: String in read.accepted:
			if path.begins_with(folder + "/"):
				by_pack[folder].append(path)
				break
	read.base = build_base(found, job.target_id, by_pack, results)
	read.job = job
	_load_result = read

func _load_finished(read: Dictionary) -> void:
	loading = false
	if read.job.target != target: return
	var before := _reference_rows.is_empty() and pack_paths.size() == 1
	if not before: read.erase("base")
	_adopt(read)
	packs_loaded.emit(read.accepted.size(), read.refused)
	if _check_again:
		var everything := _check_again_everything
		_check_again = false
		_check_again_everything = false
		request_check(everything)

static func types() -> Array:
	var out: Array = ContentDB.SCHEMA.keys() + ContentDB.PENDING_TYPES
	out.sort()
	return out


## Packs up to this size are checked in full, at once, when opened and after each change.
const LIGHT := 400

func open_pack(folder: String) -> String:
	var info := read_manifest(folder)
	if info.is_empty():
		return "Choose a folder containing one valid pack definition in pack.fsc."
	settle()
	target = folder.simplify_path().trim_suffix("/")
	pack_paths.assign([target])
	documents.clear()
	_manifests.clear()
	_reference_rows.clear()
	_reference_keys.clear()
	_reference_index.clear()
	_reference_cache_key = ""
	_own_rows.clear()
	_checks.clear()
	_seen_versions.clear()
	_other_problems.clear()
	_base = null
	_base_key = "-"
	preview_db = null
	diagnostics = []
	history.applying = true
	_scan(target, true)
	reindex()
	history.applying = false
	history.reset(documents)
	# A small pack is checked at once. A large one opens first: its check
	# follows on another thread (see request_check()).
	if rows.size() <= LIGHT: validate()
	return ""


func add_reference(folder: String) -> String:
	folder = folder.simplify_path().trim_suffix("/")
	if target.is_empty():
		return "Open a working pack first."
	if folder in pack_paths:
		return "This pack is already loaded."
	var refused := add_references([folder])
	return str(refused.get(folder, "")).replace("It has no valid pack.fsc.", "Choose a folder with a valid pack.fsc.").replace("It must be separate from the packs already loaded.", "A reference pack must be separate from the working pack.")


## Adds several packs to use their content, with one check at the end.
## Returns the folders that could not be added, with the reason.
func add_references(folders: Array) -> Dictionary:
	if target.is_empty(): return {"": "Open a working pack first."}
	settle()
	var ids: Dictionary = {}
	for path: String in pack_paths: ids[manifest(path).get("id", "")] = true
	var read := read_packs(folders, ids, pack_paths)
	_adopt(read)
	if heavy(): check_working()
	else: validate()
	return read.refused

var _manifests: Dictionary = {}

func manifest(folder: String) -> Dictionary:
	var path := folder.path_join("pack.fsc")
	# A loaded pack's manifest is read again only when its text changed.
	if documents.has(path):
		if _manifests.has(path) and _manifests[path].version == documents[path].version: return _manifests[path].info
		var directory := DirAccess.open(folder)
		var info: Dictionary = {} if directory == null or directory.is_link("pack.fsc") else _manifest_of(documents[path].parsed(), folder)
		_manifests[path] = {"version": documents[path].version, "info": info}
		return info
	return read_manifest(folder)


func _scan(folder: String, writable: bool) -> void:
	var files: Array[String] = []
	_list_files(folder, files)
	for path: String in files: documents[path] = PackDocument.new(path, writable)


## More content than this is checked in full only when asked, and its
## preview is refreshed on request: a full check of every pack takes seconds.
const HEAVY := 4000
var _reference_rows: Array[Dictionary] = []
var _reference_keys: Array[String] = []
var _reference_index: Dictionary = {}
var _reference_cache_key := ""
var _own_rows: Dictionary = {}
var _own_index: Dictionary = {}
var _own_names: PackedStringArray = []
var _own_places: Array[int] = []
var _rows_key := "-"

func heavy() -> bool:
	return rows.size() > HEAVY

static func _key_order(a: String, b: String) -> bool:
	return a.naturalnocasecmp_to(b) < 0

static func _row_order(a: Dictionary, b: Dictionary) -> bool:
	return str(a.sort).naturalnocasecmp_to(str(b.sort)) < 0

static func row_key(path: String, type: String, id: String, mode: String, ordinal: int) -> String:
	return path + "|" + type + "|" + id + "|" + mode + "|" + str(ordinal)

## A row for each definition of a file: {def, doc, pack, root, ordinal, sort}.
static func rows_of(doc: PackDocument, pack_id: String, pack: String) -> Array[Dictionary]:
	var counts: Dictionary = {}
	var out: Array[Dictionary] = []
	for definition in doc.definitions():
		var identity := definition.type + "|" + definition.id + "|" + definition.mode
		var ordinal: int = counts.get(identity, 0)
		counts[identity] = ordinal + 1
		out.append({"def": definition, "doc": doc, "pack": pack_id, "root": pack, "ordinal": ordinal, "sort": definition.type + ":" + definition.id + ":" + pack_id})
	return out

func _rows_of(path: String, pack_ids: Dictionary) -> Array[Dictionary]:
	var pack := owner(path)
	return rows_of(documents[path], pack_ids.get(pack, pack.get_file()), pack)

## Lists every definition, in one order for the whole workspace. The other
## packs never change, so their part is worked out once; of the working pack
## only the files that changed are read again, and rows of the others stay
## the very same objects.
func reindex() -> void:
	var pack_ids: Dictionary = {}
	for folder: String in pack_paths: pack_ids[folder] = manifest(folder).get("id", folder.get_file())
	var key := "|".join(pack_paths) + "|" + str(documents.size())
	if key != _reference_cache_key:
		_reference_rows.clear()
		_reference_keys.clear()
		_reference_index.clear()
		for path: String in documents:
			if not documents[path].writable: _reference_rows.append_array(_rows_of(path, pack_ids))
		_reference_rows.sort_custom(_row_order)
		for row: Dictionary in _reference_rows:
			_reference_keys.append(row.sort)
			_reference_index[row_key(row.doc.path, row.def.type, row.def.id, row.def.mode, row.ordinal)] = row
		_reference_cache_key = key
	var own: Array[Dictionary] = []
	var target_id: String = pack_ids.get(target, "")
	for path: String in _own_rows.keys():
		if not documents.has(path) or not is_same(documents[path], _own_rows[path].doc): _own_rows.erase(path)
	for path: String in documents:
		var doc: PackDocument = documents[path]
		if not doc.writable: continue
		var kept: Dictionary = _own_rows.get(path, {})
		if kept.is_empty() or kept.version != doc.version or kept.pack != target_id:
			kept = {"version": doc.version, "pack": target_id, "doc": doc, "rows": _rows_of(path, pack_ids)}
			_own_rows[path] = kept
		own.append_array(kept.rows)
	# The same definitions as before, in the same files: the list keeps its
	# order and only takes the rows as they are now.
	var names: PackedStringArray = []
	var keys: PackedStringArray = []
	for row: Dictionary in own:
		var name := row_key(row.doc.path, row.def.type, row.def.id, row.def.mode, row.ordinal)
		keys.append(name)
		names.append(name + "|" + str(row.pack))
	if names == _own_names and _rows_key == _reference_cache_key and not rows.is_empty():
		for index in own.size(): _own_index[keys[index]] = own[index]
		for index: int in _own_places:
			var old: Dictionary = rows[index]
			rows[index] = _own_index[row_key(old.doc.path, old.def.type, old.def.id, old.def.mode, old.ordinal)]
		revision += 1
		history.checkpoint(documents)
		return
	_own_names = names
	_rows_key = _reference_cache_key
	own.sort_custom(_row_order)
	_own_index.clear()
	for row: Dictionary in own: _own_index[row_key(row.doc.path, row.def.type, row.def.id, row.def.mode, row.ordinal)] = row
	# The working pack's rows go in between the others', each at its place.
	_own_places.clear()
	rows.clear()
	var at := 0
	for row: Dictionary in own:
		var before := _reference_keys.bsearch_custom(row.sort, _key_order, true)
		if before > at:
			rows.append_array(_reference_rows.slice(at, before))
			at = before
		_own_places.append(rows.size())
		rows.append(row)
	if at < _reference_rows.size(): rows.append_array(_reference_rows.slice(at) if at > 0 else _reference_rows)
	revision += 1
	history.checkpoint(documents)

var _checks: Dictionary = {}
var _check_blocks: Dictionary = {}

## What the story compiler says about one definition: [[line offset, message]].
## Kept per block text, so only a definition that changed is compiled again.
func _block_problems(definition: FscParser.Definition, doc: PackDocument) -> Array:
	var key := str(definition.type) + "\n" + doc.block(definition)
	if _check_blocks.has(key): return _check_blocks[key]
	var out: Array = []
	var scripts: Array = [definition.nodes] if definition.type in ["scene", "text"] else []
	for field_key: String in definition.fields:
		if ContentDB.SCHEMA.get(definition.type, {}).get(field_key, "") == "script": scripts.append(StoryGraph.script_nodes({"def": definition, "doc": doc, "script_field": field_key}))
	for nodes: Array in scripts:
		for problem: Dictionary in Program.compile(definition.id, nodes, doc.path).errors: out.append([int(problem.line) - int(definition.line), problem.message])
	if _check_blocks.size() > 60000: _check_blocks.clear()
	_check_blocks[key] = out
	return out

## What the parser and the story compiler say about one file of the working pack.
func _check_document(doc: PackDocument) -> Array:
	var kept: Dictionary = _checks.get(doc.path, {})
	if not kept.is_empty() and kept.version == doc.version and is_same(kept.doc, doc): return kept.found
	var found: Array = []
	var result := doc.parsed()
	found.append_array(result.diagnostics.duplicate(true))
	for definition: FscParser.Definition in result.definitions:
		for problem: Array in _block_problems(definition, doc):
			found.append({"severity": "error", "path": doc.path, "line": int(definition.line) + int(problem[0]), "message": problem[1]})
	_checks[doc.path] = {"version": doc.version, "doc": doc, "found": found}
	return found

var _seen_versions: Dictionary = {}

## The check after a change: a small pack in full at once; a larger one, or
## one with many packs beside it, quickly for what changed, with the full
## check of the pack following on another thread.
func check_after_edit() -> void:
	if rows.size() <= LIGHT: validate()
	else:
		check_working()
		request_check()

## A quick check of the working pack's changed files: what the parser and the
## story compiler say, at once. What the last check found elsewhere is kept
## until the next one (see request_check()).
func check_working() -> void:
	var changed: Dictionary = {}
	for path: String in documents:
		var doc: PackDocument = documents[path]
		if doc.writable and _seen_versions.get(path, -1) != doc.version: changed[path] = true
	var gone: bool = diagnostics.any(func(item: Dictionary) -> bool: return str(item.path).begins_with(target + "/") and not documents.has(item.path))
	if changed.is_empty() and not gone: return
	var fresh: Array = diagnostics.filter(func(item: Dictionary) -> bool: return not changed.has(item.path) and not (str(item.path).begins_with(target + "/") and not documents.has(item.path)))
	for path: String in changed:
		fresh.append_array(_check_document(documents[path]))
		_seen_versions[path] = documents[path].version
	diagnostics = fresh
	diagnostics_revision += 1

## Raised whenever the list of problems is replaced.
var diagnostics_revision := 0
var _problem_lines: Dictionary = {}
var _problem_lines_revision := -1

## The problems at one line of a file, found without going through the whole list.
func problems_at(path: String, line: int) -> Array:
	if _problem_lines_revision != diagnostics_revision:
		_problem_lines.clear()
		for item: Dictionary in diagnostics:
			var key := str(item.path) + ":" + str(int(item.line))
			if not _problem_lines.has(key): _problem_lines[key] = []
			_problem_lines[key].append(item)
		_problem_lines_revision = diagnostics_revision
	return _problem_lines.get(path + ":" + str(line), [])

var _owners: Dictionary = {}

func owner(path: String) -> String:
	if _owners.has(path) and _owners[path] in pack_paths: return _owners[path]
	for folder in pack_paths:
		if path.begins_with(folder + "/"):
			_owners[path] = folder
			return folder
	return ""


func find_row(path: String, type: String, id: String, mode: String = "define", ordinal: int = 0) -> Dictionary:
	var key := row_key(path, type, id, mode, ordinal)
	return _own_index.get(key, _reference_index.get(key, {}))


func dirty_count() -> int:
	var count := 0
	for path: String in _own_rows:
		if _own_rows[path].doc.dirty(): count += 1
	for doc: PackDocument in documents.values():
		if doc.writable and not _own_rows.has(doc.path) and doc.dirty(): count += 1
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
	var definition: FscParser.Definition = doc.definitions().filter(func(candidate: FscParser.Definition) -> bool: return candidate.type == "pack")[0]
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


## Checks the working pack against the loaded packs with the engine's
## validator, unsaved changes included; with `everything`, every pack's
## stories again. Diagnostics carry the files' own paths.
func validate(everything: bool = false) -> void:
	if target.is_empty():
		return
	validate_buffers(everything)


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


var _link_cache: Array[Dictionary] = []
var _link_cache_key := ""
var _own_links: Dictionary = {}
static var _link_pattern := RegEx.create_from_string("(?m)(?:^[ \\t]*|:[ \\t]*)(?:->|play)[ \\t]+([a-z0-9_.-]+)")

func _own_link_lists() -> Array:
	var lists: Array = []
	for path: String in _own_links.keys():
		if not _own_rows.has(path): _own_links.erase(path)
	for path: String in _own_rows:
		var kept: Dictionary = _own_links.get(path, {})
		if kept.is_empty() or kept.version != _own_rows[path].version or not is_same(kept.doc, _own_rows[path].doc):
			var links: Array[Dictionary] = []
			for row: Dictionary in _own_rows[path].rows:
				for found: Array in _block_links(row.doc.block(row.def)): links.append({"from": row, "target": found[1], "line": int(row.def.line) + int(found[0])})
			kept = {"version": _own_rows[path].version, "doc": _own_rows[path].doc, "links": links}
			_own_links[path] = kept
		lists.append(kept.links)
	return lists

var _link_blocks: Dictionary = {}
static var _line_link := RegEx.create_from_string("(?:^|:\\s*)(?:->|play)\\s+([a-z0-9_.-]+)")

## The links of one definition's block: [[line offset, target]]. Kept per
## block text, so only a block that changed is read again.
func _block_links(block: String) -> Array:
	if _link_blocks.has(block): return _link_blocks[block]
	var out: Array = []
	if "->" in block or "play " in block:
		var lines := block.split("\n")
		for index in lines.size():
			var raw := lines[index]
			if "->" not in raw and "play " not in raw: continue
			var clean := raw.strip_edges()
			if clean.begins_with("//"): continue
			var matched := _line_link.search(clean)
			if matched != null and matched.get_string(1) not in ["end", "back"]: out.append([index, matched.get_string(1)])
	if _link_blocks.size() > 60000: _link_blocks.clear()
	_link_blocks[block] = out
	return out

func _reference_links() -> Array[Dictionary]:
	if _link_cache_key != _reference_cache_key:
		_link_cache.clear()
		for path: String in documents:
			if not documents[path].writable: _link_cache.append_array(links_in(documents[path], _reference_rows_of(path)))
		_link_cache_key = _reference_cache_key
	return _link_cache

## Where stories lead: [{from, target, line}] for every "-> story" and "play story".
## The other packs' links are found once; yours again for the files that changed.
func story_links() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for list: Array in _own_link_lists(): out.append_array(list)
	out.append_array(_reference_links())
	return out

var _reference_by_path: Dictionary = {}
var _reference_by_id: Dictionary = {}
var _reference_under: Dictionary = {}
var _reference_by_path_key := ""
var _reference_touching: Dictionary = {}
var _reference_touching_key := ""

func _index_references() -> void:
	if _reference_by_path_key == _reference_cache_key: return
	_reference_by_path.clear()
	_reference_by_id.clear()
	_reference_under.clear()
	for row: Dictionary in _reference_rows:
		var path: String = row.doc.path
		if not _reference_by_path.has(path): _reference_by_path[path] = []
		_reference_by_path[path].append(row)
		var id: String = row.def.id
		if not _reference_by_id.has(id): _reference_by_id[id] = []
		_reference_by_id[id].append(row)
		if "." in id:
			var head := id.get_slice(".", 0)
			if not _reference_under.has(head): _reference_under[head] = []
			_reference_under[head].append(row)
	_reference_by_path_key = _reference_cache_key

func _reference_rows_of(path: String) -> Array:
	_index_references()
	return _reference_by_path.get(path, [])

## Every definition with this ID, in any pack and of any type.
func rows_with_id(id: String) -> Array:
	_index_references()
	var out: Array = _own_with_id(id).duplicate()
	out.append_array(_reference_by_id.get(id, []))
	return out

var _own_by_id: Dictionary = {}
var _own_by_id_revision := -1

func _own_with_id(id: String) -> Array:
	if _own_by_id_revision != revision:
		_own_by_id.clear()
		for path: String in _own_rows:
			for row: Dictionary in _own_rows[path].rows:
				if _own_by_id.has(row.def.id): _own_by_id[row.def.id].append(row)
				else: _own_by_id[row.def.id] = [row]
		_own_by_id_revision = revision
	return _own_by_id.get(id, [])

## Every definition whose ID starts with "<head>." (a character's own stories, for one).
func rows_under(head: String) -> Array:
	_index_references()
	var out: Array = []
	for path: String in _own_rows:
		for row: Dictionary in _own_rows[path].rows:
			if str(row.def.id).begins_with(head + "."): out.append(row)
	out.append_array(_reference_under.get(head, []))
	return out

## The story links that start in or lead to content with this ID.
func links_touching(id: String) -> Array:
	if _reference_touching_key != _reference_cache_key:
		_reference_touching.clear()
		for link: Dictionary in _reference_links():
			for key: String in [str(link.from.def.id), str(link.target)]:
				if not _reference_touching.has(key): _reference_touching[key] = []
				_reference_touching[key].append(link)
		_reference_touching_key = _reference_cache_key
	var out: Array = []
	for list: Array in _own_link_lists():
		for link: Dictionary in list:
			if link.from.def.id == id or link.target == id: out.append(link)
	out.append_array(_reference_touching.get(id, []))
	return out

## The links of one file: its text is searched in one go, and each find is
## given to the definition whose lines hold it. `entries` are the file's rows.
static func links_in(doc: PackDocument, entries: Array) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var text: String = doc.text
	if entries.is_empty() or ("->" not in text and "play " not in text): return out
	entries = entries.duplicate()
	entries.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a.def.line < b.def.line)
	var index := 0
	var line := 1
	var counted := 0
	var last_line := 0
	for matched: RegExMatch in _link_pattern.search_all(text):
		var at := matched.get_start()
		line += text.count("\n", counted, at) if at > counted else 0
		counted = at
		# The match may begin at the line's start or after "field:"; either way its line is the one that holds the target.
		var target_at := matched.get_start(1)
		var target_line := line + (text.count("\n", at, target_at) if target_at > at else 0)
		if target_line == last_line: continue
		var begin := text.rfind("\n", target_at) + 1
		var head := text.substr(begin, mini(target_at - begin, 200)).strip_edges()
		if head.begins_with("//"): continue
		var target := matched.get_string(1)
		if target in ["end", "back"]: continue
		last_line = target_line
		while index + 1 < entries.size() and int(entries[index + 1].def.line) <= target_line: index += 1
		if int(entries[index].def.line) <= target_line: out.append({"from": entries[index], "target": target, "line": target_line})
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
	var timing := Perf.start()
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
	Perf.stop("workspace: the change itself", timing)
	timing = Perf.start()
	history.checkpoint(documents, label)
	Perf.stop("workspace: history", timing)
	timing = Perf.start()
	reindex()
	Perf.stop("workspace: reindex", timing)
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

## Puts a new door on a way out that exists, and on the way back if there is one.
func add_door(place: String, direction: String, name: String, locked: bool) -> String:
	if name.strip_edges().is_empty(): return "Give the door a name."
	return transaction("Add the door " + name.strip_edges(), func() -> String:
		var door_id := unique_id(name, "door")
		var made := create_definition("door", door_id, "define", "name: " + name.strip_edges() + "\nlocked: " + ("yes\nlocked text: It is locked." if locked else "no"))
		if not made.is_empty(): return made
		var target := ""
		var changed := 0
		# The way out, then the way back from where it leads.
		for step in 2:
			var from := place if step == 0 else target
			var to := "" if step == 0 else place
			if from.is_empty(): break
			for row: Dictionary in rows:
				if not row.doc.writable or row.def.type != "location" or row.def.id != from or not row.def.fields.has("exits"): continue
				var lines := StoryGraph._lines(row.doc)
				for line: FscParser.Line in row.def.fields.exits.children:
					var parts := line.text.split(":", true, 1)
					if parts.size() != 2 or "door " in parts[1]: continue
					var leads := SceneRunner.exit_target(parts[1].strip_edges())
					if (step == 0 and parts[0].strip_edges() != direction) or (step == 1 and leads != to): continue
					var value := parts[1].strip_edges()
					var one_way := value.ends_with(", one way")
					StoryGraph._replace_line(lines, line.number - 1, StoryGraph._indent(lines[line.number - 1]) + parts[0].strip_edges() + ": " + value.trim_suffix(", one way") + ", door " + door_id + (", one way" if one_way else ""))
					if step == 0: target = leads
					changed += 1
					break
				StoryGraph._save_lines(row.doc, lines)
		return "" if changed > 0 else "This way out is no longer there, or belongs to another pack.")

## Connects two places, both ways by default. With `door` (name, locked) a
## door is made for the way between them, in the same undo step.
func connect_places(source: Dictionary, destination: Dictionary, direction: String, two_way: bool = true, door: Dictionary = {}) -> String:
	const OPPOSITE := {"north": "south", "northeast": "southwest", "east": "west", "southeast": "northwest", "south": "north", "southwest": "northeast", "west": "east", "northwest": "southeast", "up": "down", "down": "up", "inside": "outside", "outside": "inside"}
	if direction not in OPPOSITE or source.is_empty() or destination.is_empty(): return "Choose two places and a direction."
	if source.def.id == destination.def.id: return "Choose two different places."
	var pairs: Array = [[source, destination, direction]]
	if two_way: pairs.append([destination, source, OPPOSITE[direction]])
	return transaction("Connect " + Wording.title(source) + " and " + Wording.title(destination) + (" through " + str(door.name) if not door.is_empty() else ""), func() -> String:
		var door_id := ""
		if not door.is_empty():
			if str(door.get("name", "")).strip_edges().is_empty(): return "Give the door a name."
			door_id = unique_id(str(door.name), "door")
			var made := create_definition("door", door_id, "define", "name: " + str(door.name).strip_edges() + "\nlocked: " + ("yes\nlocked text: It is locked." if door.get("locked", false) else "no"))
			if not made.is_empty(): return made
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
			var entry: String = pair[2] + ": " + to.def.id + (", door " + door_id if not door_id.is_empty() else "") + (", one way" if not two_way else "")
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
var _reference_titles: Dictionary = {}
var _reference_titles_key := "-"

static func _collect_titles(from: Array, into: Dictionary) -> void:
	for row: Dictionary in from:
		if row.def.mode == "extend" or not row.def.fields.has("name"): continue
		var title: String = row.def.fields.name.value
		if title.is_empty(): continue
		into[row.def.type + ":" + row.def.id] = title
		if not into.has(":" + row.def.id) or row.def.type == "character": into[":" + row.def.id] = title

## The name an author sees for content; with an empty type, any type holding the ID.
func title_of(type: String, id: String) -> String:
	if _reference_titles_key != _reference_cache_key:
		_reference_titles.clear()
		_collect_titles(_reference_rows, _reference_titles)
		_reference_titles_key = _reference_cache_key
	if _titles_revision != revision:
		_titles.clear()
		for path: String in _own_rows: _collect_titles(_own_rows[path].rows, _titles)
		_titles_revision = revision
	var exact := type + ":" + id
	if _titles.has(exact): return _titles[exact]
	if _reference_titles.has(exact): return _reference_titles[exact]
	if type in ["", "who", "holder"]: return _titles.get(":" + id, _reference_titles.get(":" + id, ""))
	return ""

## Adds a named result to an event's outcomes, so stories can record and check it.
func add_outcome(event: String, name: String) -> String:
	if RegEx.create_from_string("^[a-z_][a-z0-9_]*$").search(name) == null: return "Use a name of letters and numbers."
	for row: Dictionary in rows:
		if not row.doc.writable or row.def.type != "event" or row.def.id != event or row.def.mode == "replace": continue
		var field: FscParser.Field = row.def.fields.get("outcomes")
		if field != null and not field.children.is_empty(): return "These results use a layout that must be kept."
		var existing: String = field.value if field != null else ""
		for part: String in existing.split(","):
			if part.strip_edges().get_slice("=", 0).strip_edges() == name: return ""
		return row.doc.set_field(row.def, "outcomes", (existing + ", " if not existing.is_empty() else "") + name)
	return "Choose an event of your own pack to add a result to."

## Adds a stage at the end of a quest's stages.
func add_stage(quest: String, name: String) -> String:
	if RegEx.create_from_string("^[a-z_][a-z0-9_]*$").search(name) == null: return "Use a name of letters and numbers."
	if name in preview_content().quests.get(quest, {}).get("stages", []): return ""
	for row: Dictionary in rows:
		if not row.doc.writable or row.def.type != "quest" or row.def.id != quest or row.def.mode == "replace": continue
		var field: FscParser.Field = row.def.fields.get("stages")
		if field == null or field.children.is_empty(): return "This quest has no list of stages to add to."
		var lines := StoryGraph._lines(row.doc)
		StoryGraph._insert_line(row.doc, lines, field.children[-1].number, "    " + name)
		StoryGraph._save_lines(row.doc, lines)
		return ""
	return "Choose a quest of your own pack to add a stage to."

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
var _reference_words: Dictionary = {}
var _reference_words_key := "-"

func _words_in(list: String, writable: bool) -> Dictionary:
	var found: Dictionary = {}
	var pattern: RegEx = null
	match list:
		"trait": pattern = RegEx.create_from_string("\\btrait(?: [+-])? ([a-z0-9_]+)")
		"mode": pattern = RegEx.create_from_string("\\bmode ([a-z0-9_]+)")
		"variant": pattern = RegEx.create_from_string("\\bvariant ([a-z0-9_]+)")
		"place_flag": pattern = RegEx.create_from_string("\\bflagged ([a-z][a-z ]*?)(?:\\]|:| and | or |$)")
		"ending_flag": pattern = RegEx.create_from_string("\\bending flag ([a-z0-9_]+)")
		"interest": pattern = RegEx.create_from_string("\\binterested in ([a-z_]+)")
		"moment": pattern = RegEx.create_from_string("(?m)^\\s*(?:~ moment|on:) ([a-z0-9_]+(?: [a-z0-9_]+)*)\\s*$")
	var source: Array = []
	if writable:
		for path: String in _own_rows: source.append_array(_own_rows[path].rows)
	else: source = _reference_rows
	for row: Dictionary in source:
		if list == "tag" and row.def.type in ["tag", "filter"]: found[row.def.id] = true
		if list == "tag" and row.def.fields.has("tags"):
			for tag: String in str(row.def.fields.tags.value).split(","):
				if not tag.strip_edges().is_empty(): found[tag.strip_edges()] = true
		if list == "place_flag" and row.def.fields.has("flags"):
			for flag: String in str(row.def.fields.flags.value).split(","):
				if not flag.strip_edges().is_empty(): found[flag.strip_edges()] = true
	if pattern != null:
		for path: String in documents:
			if documents[path].writable != writable: continue
			for matched: RegExMatch in pattern.search_all(documents[path].text): found[matched.get_string(1)] = true
	return found

## Words already used in the loaded packs, to suggest where the engine takes any word.
## The other packs are read once; the working pack again after a change.
func known_words(list: String) -> Array:
	if BlockCatalog.WORDS.has(list): return BlockCatalog.WORDS[list]
	if _reference_words_key != _reference_cache_key:
		_reference_words.clear()
		_reference_words_key = _reference_cache_key
		_words_revision = -1
	if _words_revision != revision:
		_words.clear()
		_words_revision = revision
	if _words.has(list): return _words[list]
	if not _reference_words.has(list): _reference_words[list] = _words_in(list, false)
	var found: Dictionary = _reference_words[list].duplicate()
	found.merge(_words_in(list, true))
	if list == "place_flag":
		for flag: String in Validator.LOCATION_FLAGS: found[flag] = true
	var result: Array = found.keys()
	result.sort()
	_words[list] = result
	return result

var _uses: Dictionary = {}
var _uses_revision := -1
var _use_files: Dictionary = {}
var _use_blocks: Dictionary = {}
static var _use_token := RegEx.create_from_string("[a-z0-9_][a-z0-9_-]*")

## Every word of a definition's block that could name content:
## {lines: [[line offset, text]], words: {word: [indexes into lines]}}.
## Comments do not count. Kept per block text, so only a block that changed
## is read again.
func _block_words(block: String) -> Dictionary:
	if _use_blocks.has(block): return _use_blocks[block]
	var out := {"lines": [], "words": {}}
	var lines := block.split("\n")
	for index in range(1, lines.size()):
		var clean := lines[index].strip_edges()
		if clean.is_empty() or clean.begins_with("//"): continue
		var code := ContentTools.code_text(lines[index].trim_suffix("\r"))
		var at: int = out.lines.size()
		var any := false
		for matched: RegExMatch in _use_token.search_all(code):
			# In "adam.trust" only the owner is content; "trust" is its value.
			if matched.get_start() > 0 and code[matched.get_start() - 1] == ".": continue
			var word := matched.get_string()
			if not out.words.has(word): out.words[word] = [at]
			elif out.words[word][-1] != at: out.words[word].append(at)
			any = true
		if any: out.lines.append([index, clean])
	if _use_blocks.size() > 60000: _use_blocks.clear()
	_use_blocks[block] = out
	return out

## word -> the rows of one file of the working pack whose blocks mention it.
## Kept as positions in the file, and brought up to date only for the blocks
## that changed.
func _file_uses(path: String) -> Dictionary:
	var own: Dictionary = _own_rows.get(path, {})
	if own.is_empty(): return {}
	var kept: Dictionary = _use_files.get(path, {})
	if kept.is_empty() or not is_same(kept.doc, own.doc) or kept.blocks.size() != own.rows.size():
		kept = {"version": -1, "doc": own.doc, "blocks": [], "places": {}}
		for row: Dictionary in own.rows: kept.blocks.append("")
		_use_files[path] = kept
	if kept.version != own.version:
		for at in own.rows.size():
			var row: Dictionary = own.rows[at]
			var block: String = row.doc.block(row.def)
			if block == kept.blocks[at]: continue
			if not str(kept.blocks[at]).is_empty():
				for word: String in _block_words(kept.blocks[at]).words:
					if kept.places.has(word): kept.places[word].erase(at)
			for word: String in _block_words(block).words:
				if kept.places.has(word): kept.places[word].append(at)
				else: kept.places[word] = [at]
			kept.blocks[at] = block
		kept.version = own.version
		kept.erase("words")
	return kept.places

## The rows of one file whose blocks mention a word.
func _rows_using(path: String, word: String) -> Array:
	var out: Array = []
	var rows_here: Array = _own_rows[path].rows
	for at: int in _file_uses(path).get(word, []): out.append(rows_here[at])
	return out

## The lines of one definition that mention a word: [{row, line, text}].
func _uses_in(row: Dictionary, word: String) -> Array:
	var out: Array = []
	if word == row.def.id: return out
	var found: Dictionary = _block_words(row.doc.block(row.def))
	for at: int in found.words.get(word, []): out.append({"row": row, "line": int(row.def.line) + int(found.lines[at][0]), "text": found.lines[at][1]})
	return out

## Where each ID is mentioned in the working pack: id -> [{row, line, text}].
## Comments and the content's own block do not count.
func uses_index() -> Dictionary:
	if _uses_revision == revision: return _uses
	_uses.clear()
	_uses_revision = revision
	var known: Dictionary = {}
	for row: Dictionary in rows: known[row.def.id] = true
	for path: String in _own_rows:
		var words := _file_uses(path)
		for word: String in words:
			if not known.has(word): continue
			for row: Dictionary in _rows_using(path, word):
				var found := _uses_in(row, word)
				if found.is_empty(): continue
				if not _uses.has(word): _uses[word] = []
				_uses[word].append_array(found)
	return _uses

## Where one ID is mentioned in the working pack.
func uses(id: String) -> Array:
	if _uses_revision == revision: return _uses.get(id, [])
	var found: Array = []
	for path: String in _own_rows:
		for row: Dictionary in _rows_using(path, id): found.append_array(_uses_in(row, id))
	return found

## Whether anything in the working pack mentions an ID (cheaper than listing where).
func is_used(id: String) -> bool:
	for path: String in _own_rows:
		for row: Dictionary in _rows_using(path, id):
			if row.def.id != id: return true
	return false

## Short notes on what a piece of content still needs, for the home page.
func hints(row: Dictionary) -> Array[String]:
	var notes: Array[String] = []
	var definition: FscParser.Definition = row.def
	var used := 1 if is_used(definition.id) else 0
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


## Every place in the working pack that changes or reads a saved value:
## [{row, line, text, changes}]. "adam.trust + 1" changes; a condition reads.
func value_uses(path: String) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var token := RegEx.create_from_string("(?<![a-z0-9_.])" + path.replace(".", "\\.") + "(?![a-z0-9_.])")
	var change := RegEx.create_from_string("^~\\s*(?:" + path.replace(".", "\\.") + " (?:=|\\+|-|earlier|later)|(?:add|remove|clear|sort|ask) .*" + path.replace(".", "\\.") + ")")
	var short := path.trim_prefix("player.") if path.begins_with("player.") else ""
	var stat := RegEx.create_from_string("^~\\s*" + short + " [+-] ") if not short.is_empty() else null
	var quest := RegEx.create_from_string("\\bquest " + path.trim_prefix("quest.") + "\\b") if path.begins_with("quest.") else null
	for row: Dictionary in rows:
		if not row.doc.writable: continue
		var lines: PackedStringArray = str(row.doc.block(row.def)).split("\n")
		for index in range(1, lines.size()):
			var clean := lines[index].strip_edges()
			if clean.is_empty() or clean.begins_with("//"): continue
			var code := ContentTools.code_text(lines[index].trim_suffix("\r"))
			var changes: bool = change.search(clean) != null or (stat != null and stat.search(clean) != null) or (quest != null and clean.begins_with("~ quest "))
			if token.search(code) == null and not (stat != null and stat.search(clean) != null) and not (quest != null and quest.search(code) != null): continue
			result.append({"row": row, "line": int(row.def.line) + index, "text": clean, "changes": changes})
	return result
