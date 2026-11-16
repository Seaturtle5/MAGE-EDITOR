class_name DraftAutosave
extends RefCounted
## Recovery is separate from explicit saves and rejects changed disk originals.

var directory := OS.get_user_data_dir().path_join("drafts")

func path_for(target: String) -> String:
	return directory.path_join(target.sha256_text() + ".json")

func read_draft(target: String) -> Dictionary:
	var path := path_for(target)
	if not FileAccess.file_exists(path): return {}
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not parsed is Dictionary or parsed.get("version") != 1 or parsed.get("target") != target: return {}
	return parsed

func save(workspace: PackWorkspace) -> String:
	if workspace.target.is_empty(): return ""
	if workspace.dirty_count() == 0:
		discard(workspace.target)
		return ""
	var entries: Array = []
	for doc: PackDocument in workspace.documents.values():
		if doc.writable and doc.dirty():
			entries.append({"path": doc.path, "text": doc.text, "original": doc.original, "existed": doc.existed_at_open})
	if DirAccess.make_dir_recursive_absolute(directory) != OK: return "Could not create draft recovery folder."
	var path := path_for(workspace.target)
	var temporary := path + ".tmp"
	var file := FileAccess.open(temporary, FileAccess.WRITE)
	if file == null: return "Could not write recovery draft."
	file.store_string(JSON.stringify({"version": 1, "target": workspace.target, "references": workspace.pack_paths.slice(1), "documents": entries}))
	file.flush()
	var error := file.get_error()
	file.close()
	if error != OK: return "Could not finish recovery draft."
	if DirAccess.rename_absolute(temporary, path) != OK: return "Could not replace recovery draft."
	return ""

func restore(workspace: PackWorkspace) -> String:
	var draft := read_draft(workspace.target)
	if draft.is_empty(): return "No recovery draft is available."
	var entries: Variant = draft.get("documents", [])
	if not entries is Array: return "This recovery draft is invalid."
	for entry: Variant in entries:
		if not entry is Dictionary or not entry.get("path") is String or not entry.get("text") is String or not entry.get("original") is String or not entry.get("existed") is bool:
			return "This recovery draft is invalid."
		if not workspace._inside_working_pack(entry.path): return "A recovery path is outside the working pack or passes through a link."
		var exists := FileAccess.file_exists(entry.path)
		if exists != entry.existed or (exists and FileAccess.get_file_as_string(entry.path) != entry.original):
			return "File changed since this draft was made: " + entry.path + ". Recovery stopped; the draft is kept."
	return workspace.transaction("Restore unsaved draft", func() -> String:
		for entry: Dictionary in entries:
			if not workspace.documents.has(entry.path): workspace.documents[entry.path] = PackDocument.new(entry.path, true)
			workspace.documents[entry.path].change(entry.text)
		return "")

func discard(target: String) -> void:
	if FileAccess.file_exists(path_for(target)): DirAccess.remove_absolute(path_for(target))
