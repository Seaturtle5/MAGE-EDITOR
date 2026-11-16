class_name AuthorTemplates
extends RefCounted
## Questions and source live together; all rendered source uses the engine.

static func available(workspace: PackWorkspace, include_game: bool = false) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var game := include_game or workspace.pack_paths.any(func(path: String) -> bool: return workspace.manifest(path).get("id") == "core-mechanics")
	for folder: String in ["generic", "flexible_survival"]:
		if folder == "flexible_survival" and not game: continue
		var root := "res://src/templates/" + folder
		var directory := DirAccess.open(root)
		if directory == null: continue
		var files := directory.get_files()
		files.sort()
		for file: String in files:
			if file.ends_with(".fsc"): result.append(load_template(root.path_join(file), folder))
	return result

static func load_template(path: String, family: String = "generic") -> Dictionary:
	var data := {"id": path.get_file().get_basename(), "title": "", "about": "", "kind": "", "family": family, "questions": [], "source": ""}
	for line: String in FileAccess.get_file_as_string(path).split("\n"):
		if line.begins_with("// title: "): data.title = line.trim_prefix("// title: ")
		elif line.begins_with("// about: "): data.about = line.trim_prefix("// about: ")
		elif line.begins_with("// kind: "): data.kind = line.trim_prefix("// kind: ")
		elif line.begins_with("// question: "):
			var parts := line.trim_prefix("// question: ").split("|")
			if parts.size() == 4: data.questions.append({"key": parts[0], "label": parts[1], "kind": parts[2], "default": parts[3]})
		else: data.source += line + "\n"
	return data

static func fill(template: Dictionary, answers: Dictionary, workspace: PackWorkspace) -> Dictionary:
	var values := answers.duplicate()
	for question: Dictionary in template.questions:
		var value: String = str(values.get(question.key, question.default)).strip_edges()
		if value.is_empty() and not str(question.kind).ends_with("?"): return {"error": "Choose or write " + question.label.to_lower() + "."}
		if question.kind == "name" and ("\n" in value or "\r" in value): return {"error": "The name must fit on one line."}
		if question.kind == "number" and (not value.is_valid_int() or int(value) < 0): return {"error": question.label + " needs a positive whole number or zero."}
		if question.kind.begins_with("choice:") and value not in question.kind.trim_prefix("choice:").split(","): return {"error": "Choose " + question.label.to_lower() + " from the list."}
		if str(question.kind).trim_suffix("?") in ["location", "zone", "form", "item", "image"] and not value.is_empty():
			if not workspace.rows.any(func(row: Dictionary) -> bool: return row.def.type == str(question.kind).trim_suffix("?") and row.def.id == value): return {"error": "Choose an existing " + Wording.name(question.kind) + "."}
		values[question.key] = value
	if str(template.id) in ["event", "exploration_find"]:
		values.item_effect = "~ give " + str(values.get("item", "")) + " 1" if not str(values.get("item", "")).is_empty() else "// No item is given."
	if str(template.id) == "item":
		values.consumed = "no" if values.get("category") == "other" else "yes"
		values.item_reaction = ("~ drink " if values.get("category") == "drink" else "~ eat ") + str(values.get("hunger", "10")) if values.get("category") != "other" else "You use the item."
	var parsed := FscParser.parse(template.source.replace("{{id}}", "draft"), "")
	var kind: String = parsed.definitions[0].type if not parsed.definitions.is_empty() else "scene"
	values.id = workspace.unique_id(str(values.get("name", "New story")), kind)
	if values.has("stages"):
		var stage_names := str(values.stages).replace(";", "\n").split("\n", false)
		if stage_names.size() < 2: return {"error": "Add at least two quest stages."}
		var ids: Array[String] = []
		var entries: Array[String] = []
		for stage: String in stage_names:
			var id := workspace.unique_id(stage.strip_edges(), "stage")
			if stage.strip_edges().is_empty() or id in ids: return {"error": "Give each quest stage a different name."}
			ids.append(id)
			entries.append(id + ": " + stage.strip_edges())
		values.stage_lines = "\n".join(entries)
		values.last_stage = ids[-1]
	var difficulty: String = values.get("strength", "even")
	var stats: Array = {"weak": [1, 10, 2], "even": [3, 25, 5], "strong": [6, 50, 10]}.get(difficulty, [3, 25, 5])
	values.merge({"level": stats[0], "hp": stats[1], "damage": stats[2]})
	var lines: Array[String] = []
	for line: String in str(template.source).split("\n"):
		var indent := line.left(line.length() - line.strip_edges(true, false).length())
		for key: String in values:
			line = line.replace("{{" + key + "}}", str(values[key]).replace("\r", "").replace("\n", "\n" + indent))
		lines.append(line)
	var text := "\n".join(lines)
	if "{{" in text: return {"error": "The template has an unanswered question."}
	return {"text": text, "id": values.id, "type": kind, "name": str(values.get("name", ""))}

static func create(template: Dictionary, answers: Dictionary, workspace: PackWorkspace) -> Dictionary:
	var filled := fill(template, answers, workspace)
	if filled.has("error"): return filled
	var previous_errors: Array[String] = []
	workspace.validate()
	for diagnostic: Dictionary in workspace.diagnostics:
		if diagnostic.severity == "error": previous_errors.append(diagnostic.message)
	var error := workspace.transaction("Create " + str(template.title), func() -> String:
		if template.family == "flexible_survival":
			for path: String in workspace.pack_paths:
				if workspace.manifest(path).get("id") == "core-mechanics":
					var issue := workspace.add_requirement("core-mechanics")
					if not issue.is_empty(): return issue
		var temporary := PackDocument.new("", true)
		temporary.text = filled.text
		for definition: FscParser.Definition in temporary.definitions():
			var block := temporary.block(definition)
			var first_end := block.find("\n")
			var problem := workspace.create_definition(definition.type, definition.id, definition.mode, block.substr(first_end + 1))
			if not problem.is_empty(): return problem
		for question: Dictionary in template.questions:
			if str(question.kind).trim_suffix("?") not in ["location", "zone", "form", "item", "image"]: continue
			for row: Dictionary in workspace.rows:
				if row.def.type == str(question.kind).trim_suffix("?") and row.def.id == answers.get(question.key) and not row.doc.writable:
					var problem := workspace.add_requirement(row.pack)
					if not problem.is_empty(): return problem
		workspace.validate()
		for diagnostic: Dictionary in workspace.diagnostics:
			if diagnostic.severity == "error" and diagnostic.message not in previous_errors: return diagnostic.message
		return "")
	if not error.is_empty():
		workspace.validate()
		return {"error": error}
	return filled
