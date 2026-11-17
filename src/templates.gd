class_name AuthorTemplates
extends RefCounted
## Guided tasks as data: a template is .fsc text with {{placeholders}} and a
## header listing the questions to ask. All filled text is read by the engine.
##
## Header lines: `// title:`, `// about:`, `// kind:` (icon and colour),
## `// step: Title` (a page of the task) and
## `// question: key|Label|kind|default|help`. Kinds: name, prose, number,
## choice:a,b,c, responses, stages, and a content type (location, zone, form,
## item, image ...), with `?` when it may be left empty. A line `field: {{key}}`
## is left out when its answer is empty.

const CONTENT := ["location", "zone", "form", "item", "image", "creature", "character", "quest", "event", "scene"]
## What can be made on the spot when a task needs one, from only a name.
const INLINE := {
	"location": "== location {{id}}\nname: {{name}}\nzone: none\ndescription: Describe this place.",
	"zone": "== zone {{id}}\nname: {{name}}",
	"form": "== form {{id}}\nname: {{name}}\nbody type: humanoid\nscale: 3",
}
const NEW := "+"

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
	result.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return int(a.order) < int(b.order))
	return result

static func load_template(path: String, family: String = "generic") -> Dictionary:
	var data := {"id": path.get_file().get_basename(), "title": "", "about": "", "kind": "", "order": 50, "family": family, "questions": [], "steps": [], "source": ""}
	var step := ""
	for line: String in FileAccess.get_file_as_string(path).split("\n"):
		if line.begins_with("// title: "): data.title = line.trim_prefix("// title: ")
		elif line.begins_with("// about: "): data.about = line.trim_prefix("// about: ")
		elif line.begins_with("// kind: "): data.kind = line.trim_prefix("// kind: ")
		elif line.begins_with("// order: "): data.order = int(line.trim_prefix("// order: "))
		elif line.begins_with("// step: "):
			step = line.trim_prefix("// step: ")
			data.steps.append(step)
		elif line.begins_with("// question: "):
			var parts := line.trim_prefix("// question: ").split("|")
			if parts.size() >= 4:
				if step.is_empty():
					step = "Questions"
					data.steps.append(step)
				data.questions.append({"key": parts[0], "label": parts[1], "kind": parts[2], "default": parts[3], "help": parts[4] if parts.size() > 4 else "", "step": step})
		else: data.source += line + "\n"
	return data

## "label=reply=back;label==end" as [{label, reply, ending}].
static func read_responses(text: String) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for part: String in text.split(";", false):
		var fields := part.split("=")
		if fields[0].strip_edges().is_empty(): continue
		result.append({"label": fields[0].strip_edges(), "reply": fields[1].strip_edges() if fields.size() > 1 else "", "ending": fields[2].strip_edges() if fields.size() > 2 and fields[2].strip_edges() in ["back", "end"] else "back"})
	return result

static func write_responses(responses: Array) -> String:
	var parts: Array[String] = []
	for response: Dictionary in responses: parts.append("%s=%s=%s" % [str(response.label).replace("=", " ").replace(";", ","), str(response.reply).replace("=", " ").replace(";", ","), response.ending])
	return ";".join(parts)

static func _prose_problem(label: String, value: String) -> String:
	for line: String in value.split("\n"):
		if StoryGraph._is_statement(line.strip_edges()): return "Use ordinary text in “" + label + "”. Actions and responses are added afterwards, in the story."
		if TextTemplate.compile(line).has("error"): return "“" + label + "” has brackets the game cannot read. Remove [ and ] or finish them."
	return ""

static func fill(template: Dictionary, answers: Dictionary, workspace: PackWorkspace) -> Dictionary:
	var values := answers.duplicate()
	var extra: Array[String] = []
	var taken: Dictionary = {}
	for question: Dictionary in template.questions:
		var kind: String = str(question.kind).trim_suffix("?")
		var optional: bool = str(question.kind).ends_with("?")
		var value: String = str(values.get(question.key, question.default)).strip_edges()
		var label: String = question.label
		if value.is_empty() and not optional: return {"error": "Still needed: " + label.to_lower().trim_suffix("?") + ".", "key": question.key}
		if kind == "name" and ("\n" in value or "\r" in value): return {"error": "The name must fit on one line.", "key": question.key}
		if kind == "number" and (not value.is_valid_int() or int(value) < 0): return {"error": label + " needs a whole number, zero or more.", "key": question.key}
		if kind.begins_with("choice:") and value not in kind.trim_prefix("choice:").split(","): return {"error": "Choose " + label.to_lower() + " from the list.", "key": question.key}
		if kind == "prose":
			var issue := _prose_problem(label, value)
			if not issue.is_empty(): return {"error": issue, "key": question.key}
		if kind == "responses":
			var lines: Array[String] = []
			var responses := read_responses(value)
			if responses.is_empty(): return {"error": "Add at least one response.", "key": question.key}
			for response: Dictionary in responses:
				if "[" in str(response.label) or "]" in str(response.label) or " -- " in str(response.label): return {"error": "Keep each response to plain words.", "key": question.key}
				var issue := _prose_problem(label, str(response.reply))
				if not issue.is_empty(): return {"error": issue, "key": question.key}
				lines.append("* " + str(response.label))
				for reply_line: String in str(response.reply).split("\n", false): lines.append("    " + reply_line.strip_edges())
				lines.append("    -> " + str(response.ending))
			value = "\n".join(lines)
		if kind in CONTENT and not value.is_empty():
			if value.begins_with(NEW):
				if not INLINE.has(kind): return {"error": "Choose an existing " + Wording.name(kind) + ".", "key": question.key}
				var new_name := value.trim_prefix(NEW).strip_edges()
				if new_name.is_empty() or "\n" in new_name: return {"error": "Give the new " + Wording.name(kind) + " a name.", "key": question.key}
				var new_id := workspace.unique_id(new_name, kind)
				while taken.has(kind + ":" + new_id): new_id += "_2"
				taken[kind + ":" + new_id] = true
				extra.append(str(INLINE[kind]).replace("{{id}}", new_id).replace("{{name}}", new_name))
				value = new_id
			elif not workspace.rows.any(func(row: Dictionary) -> bool: return row.def.type == kind and row.def.id == value): return {"error": "Choose an existing " + Wording.name(kind) + " for “" + label + "”.", "key": question.key}
		values[question.key] = value
	values.area_or_none = str(values.get("area", "")) if not str(values.get("area", "")).is_empty() else "none"
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
		if stage_names.size() < 2: return {"error": "Add at least two quest stages.", "key": "stages"}
		var ids: Array[String] = []
		var entries: Array[String] = []
		for stage: String in stage_names:
			var id := workspace.unique_id(stage.strip_edges(), "stage")
			if stage.strip_edges().is_empty() or id in ids: return {"error": "Give each quest stage a different name.", "key": "stages"}
			ids.append(id)
			entries.append(id + ": " + stage.strip_edges())
		values.stage_lines = "\n".join(entries)
		values.last_stage = ids[-1]
	var difficulty: String = values.get("strength", "even")
	var stats: Array = {"weak": [1, 10, 2], "even": [3, 25, 5], "strong": [6, 50, 10]}.get(difficulty, [3, 25, 5])
	values.merge({"level": stats[0], "hp": stats[1], "damage": stats[2]})
	var lines: Array[String] = []
	var lone := RegEx.create_from_string("^\\s*[a-z ]+: \\{\\{(\\w+)\\}\\}\\s*$")
	for line: String in str(template.source).split("\n"):
		var alone := lone.search(line)
		if alone != null and str(values.get(alone.get_string(1), "x")).is_empty(): continue
		var indent := line.left(line.length() - line.strip_edges(true, false).length())
		for key: String in values:
			line = line.replace("{{" + key + "}}", str(values[key]).replace("\r", "").replace("\n", "\n" + indent))
		lines.append(line)
	var text := "\n".join(lines)
	if "{{" in text: return {"error": "The template has an unanswered question."}
	if not extra.is_empty(): text = "\n".join(extra) + "\n" + text
	return {"text": text, "id": values.id, "type": kind, "name": str(values.get("name", ""))}

static func create(template: Dictionary, answers: Dictionary, workspace: PackWorkspace) -> Dictionary:
	var filled := fill(template, answers, workspace)
	if filled.has("error"): return filled
	var previous_errors: Array[String] = []
	var check := func() -> void:
		if workspace.rows.size() > PackWorkspace.LIGHT: workspace.check_working()
		else: workspace.validate()
	check.call()
	for diagnostic: Dictionary in workspace.diagnostics:
		if diagnostic.severity == "error": previous_errors.append(diagnostic.message)
	var error := workspace.transaction("Create " + (str(filled.name) if not str(filled.name).is_empty() else str(template.title)), func() -> String:
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
			if str(question.kind).trim_suffix("?") not in CONTENT: continue
			for row: Dictionary in workspace.rows:
				if row.def.type == str(question.kind).trim_suffix("?") and row.def.id == answers.get(question.key) and not row.doc.writable:
					var problem := workspace.add_requirement(row.pack)
					if not problem.is_empty(): return problem
		check.call()
		for diagnostic: Dictionary in workspace.diagnostics:
			if diagnostic.severity == "error" and diagnostic.message not in previous_errors: return diagnostic.message
		return "")
	if not error.is_empty():
		check.call()
		return {"error": error}
	return filled
