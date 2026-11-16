class_name StoryGraph
extends RefCounted
## Source-aware story operations. Never reserialize a whole existing scene.

static func structure(row: Dictionary) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	if row.is_empty(): return result
	var lines := _lines(row.doc)
	var span: Vector2i = row.doc.block_range(row.def)
	var end_line: int = row.doc.text.left(span.y).count("\n") + 2
	if row.has("script_field") or row.def.type not in ["scene", "text", "menu"]:
		var key: String = row.get("script_field", "play" if row.def.type == "event" else "talk")
		if row.def.fields.has(key):
			var field: FscParser.Field = row.def.fields[key]
			end_line = field.children[-1].number + 1 if not field.children.is_empty() else field.line + 1
	var roots := script_nodes(row).duplicate()
	if row.def.type == "menu" and not row.has("script_field") and not row.def.options.is_empty():
		roots.append({"kind": "choices", "line": row.def.options[0].line, "options": row.def.options})
	_structure_nodes(roots, end_line, "", lines, result)
	return result

static func _structure_nodes(nodes: Array, limit: int, parent: String, lines: PackedStringArray, result: Array[Dictionary]) -> void:
	for index in nodes.size():
		var node: Dictionary = nodes[index]
		var end: int = nodes[index + 1].line if index + 1 < nodes.size() else limit
		var first := int(node.line)
		if first < 1 or first > lines.size(): continue
		while end > first + 1 and end - 2 < lines.size() and (lines[end - 2].strip_edges().is_empty() or lines[end - 2].strip_edges().begins_with("//")): end -= 1
		var entry := {"node": node, "line": first, "end_line": mini(end, lines.size() + 1), "indent": _indent(lines[first - 1]), "parent": parent, "key": str(node.kind) + ":" + str(first)}
		result.append(entry)
		match str(node.kind):
			"choices":
				var options: Array = []
				for option: Dictionary in node.options:
					var response := option.duplicate()
					response.kind = "response"
					options.append(response)
				_structure_nodes(options, end, entry.key, lines, result)
			"response": _structure_nodes(node.body, end, entry.key, lines, result)
			"if":
				var branches: Array = []
				for branch: Dictionary in node.branches:
					var item := branch.duplicate()
					item.kind = "branch"
					branches.append(item)
				if node["else"] is Array:
					for at in range(first, mini(end - 1, lines.size())):
						if _indent(lines[at]) == entry.indent and lines[at].strip_edges() == "else:": branches.append({"kind": "branch", "line": at + 1, "condition": "", "body": node["else"]})
				_structure_nodes(branches, end, entry.key, lines, result)
			"branch", "outcome": _structure_nodes(node.body, end, entry.key, lines, result)
			"fight":
				var outcomes: Array = []
				for at in range(first, mini(end - 1, lines.size())):
					var label := lines[at].strip_edges().trim_suffix(":")
					if _indent(lines[at]) == str(entry.indent) + "    " and label in node.outcomes:
						outcomes.append({"kind": "outcome", "line": at + 1, "label": label, "body": node.outcomes[label]})
				_structure_nodes(outcomes, end, entry.key, lines, result)

static func node_span(row: Dictionary, line: int, kind: String = "") -> Dictionary:
	for entry: Dictionary in structure(row):
		if entry.line == line and (kind.is_empty() or entry.node.kind == kind): return entry
	return {}

static func insert_block(row: Dictionary, before_line: int, indent: String, content: String, snapshot: String) -> String:
	if not row.doc.writable: return "This pack is read-only."
	if row.doc.text != snapshot: return "This story changed. Reopen it before editing."
	var lines := _lines(row.doc)
	if before_line < 1 or before_line > lines.size() + 1: return "Choose an insertion point in this story."
	var def_span: Vector2i = row.doc.block_range(row.def)
	var end_line: int = row.doc.text.left(def_span.y).count("\n") + 2
	if before_line <= int(row.def.line) or before_line > end_line: return "The insertion point is outside this content."
	var parsed := FscParser.parse("== scene block_draft\n" + content + "\n")
	if not parsed.ok() or parsed.definitions.size() != 1: return "The pasted blocks are not a complete story block."
	var program := Program.compile("block_draft", parsed.definitions[0].nodes)
	if not program.errors.is_empty(): return str(program.errors[0].message)
	var replacement := content.trim_suffix("\n").split("\n")
	for index in range(replacement.size() - 1, -1, -1): _insert_line(row.doc, lines, before_line - 1, (indent + replacement[index]) if not replacement[index].strip_edges().is_empty() else "")
	_save_lines(row.doc, lines)
	return ""

static func remove_block(row: Dictionary, entry: Dictionary, snapshot: String) -> String:
	if not row.doc.writable: return "This pack is read-only."
	if row.doc.text != snapshot: return "This story changed. Reopen it before editing."
	if entry.is_empty() or entry.node.get("inline_field", "") != "" or entry.node.kind in ["branch", "outcome", "choices"]: return "This container must be kept with its surrounding story."
	var lines := _lines(row.doc)
	for index in range(int(entry.line) - 1, int(entry.end_line) - 1):
		if lines[index].strip_edges().begins_with("//"): return "This block contains comments. Move it or keep it to preserve them."
	for index in range(int(entry.end_line) - 2, int(entry.line) - 2, -1): lines.remove_at(index)
	_save_lines(row.doc, lines)
	return ""

static func move_block(row: Dictionary, entry: Dictionary, before_line: int, indent: String, snapshot: String, copy: bool = false) -> String:
	if not row.doc.writable: return "This pack is read-only."
	if row.doc.text != snapshot: return "This story changed. Reopen it before editing."
	if entry.is_empty() or entry.node.get("inline_field", "") != "" or entry.node.kind in ["branch", "outcome", "choices"]: return "Move the whole condition, fight or response instead."
	if before_line >= int(entry.line) and before_line < int(entry.end_line): return "A block cannot be moved inside itself."
	var lines := _lines(row.doc)
	var payload: Array[String] = []
	for index in range(int(entry.line) - 1, int(entry.end_line) - 1):
		if not lines[index].is_empty() and not lines[index].begins_with(str(entry.indent)): return "This block has mixed indentation and is kept."
		payload.append(lines[index].trim_prefix(str(entry.indent)).trim_suffix("\r"))
	var old: String = row.doc.text
	if not copy:
		for index in range(int(entry.end_line) - 2, int(entry.line) - 2, -1): lines.remove_at(index)
		if before_line >= int(entry.end_line): before_line -= int(entry.end_line) - int(entry.line)
		_save_lines(row.doc, lines)
	var error := insert_block(row, before_line, indent, "\n".join(payload), row.doc.text)
	if not error.is_empty(): row.doc.text = old
	return error

static func wrap_in_condition(row: Dictionary, entry: Dictionary, condition: String, snapshot: String) -> String:
	if not row.doc.writable: return "This pack is read-only."
	if row.doc.text != snapshot: return "This story changed. Reopen it before editing."
	if Condition.compile(condition).has("error"): return "Choose a supported condition."
	if entry.is_empty() or entry.node.kind in ["branch", "outcome", "choices"] or entry.node.has("inline_field"): return "Choose a whole block to wrap."
	var lines := _lines(row.doc)
	for index in range(int(entry.line) - 1, int(entry.end_line) - 1): _replace_line(lines, index, "    " + lines[index].trim_suffix("\r"))
	_insert_line(row.doc, lines, int(entry.line) - 1, str(entry.indent) + "if " + condition + ":")
	_save_lines(row.doc, lines)
	return ""

static func script_nodes(row: Dictionary) -> Array:
	var d: FscParser.Definition = row.def
	if d.type == "scene" and not row.has("script_field"):
		return d.nodes
	var key: String = row.get("script_field", "intro" if d.type == "menu" else ("play" if d.type == "event" else "talk"))
	if not d.fields.has(key):
		return []
	var field: FscParser.Field = d.fields[key]
	if row.has("script_field") and ContentDB.SCHEMA.get(d.type, {}).get(key, "") == "menu":
		return []
	var nodes: Array = []
	if not field.value.is_empty():
		if field.value.begins_with("->"):
			nodes.append({"kind": "goto", "line": field.line, "target": field.value.substr(2).strip_edges(), "inline_field": key})
		else:
			nodes.append({"kind": "text", "line": field.line, "text": field.value, "inline_field": key})
	if not field.children.is_empty():
		nodes.append_array(FscParser.parse_script(field.children, FscParser.Result.new()))
	return nodes

static func set_image(row: Dictionary, node: Dictionary, image: String) -> String:
	if not row.doc.writable: return "This pack is read-only."
	if not image.is_empty() and RegEx.create_from_string("^[a-z0-9_][a-z0-9_.-]*$").search(image) == null:
		return "Choose an image with a lowercase content ID."
	var lines := _lines(row.doc)
	if not node.is_empty():
		var index := int(node.line) - 1
		if index < 0 or index >= lines.size() or lines[index].strip_edges() != "show " + str(node.image):
			return "This image step changed. Reopen it before editing."
		if image.is_empty(): lines.remove_at(index)
		else: _replace_line(lines, index, _indent(lines[index]) + "show " + image)
		_save_lines(row.doc, lines)
		return ""
	if image.is_empty(): return ""
	var nodes := script_nodes(row)
	if not nodes.is_empty() and nodes[0].kind == "show":
		return set_image(row, nodes[0], image)
	if row.def.type == "item" and row.get("script_field", "") == "use" and row.def.fields.has("use action"):
		return "Remove the built-in use activity before adding a story image."
	if not nodes.is_empty() and not nodes[0].has("inline_field"):
		var index := int(nodes[0].line) - 1
		_insert_line(row.doc, lines, index, _indent(lines[index]) + "show " + image)
		_save_lines(row.doc, lines)
		return ""
	if row.def.type == "scene" and not row.has("script_field"):
		var eol := "\r\n" if "\r\n" in row.doc.text else "\n"
		row.doc.replace_block(row.def, row.doc.block(row.def) + eol + "show " + image)
		return ""
	var field: String = row.get("script_field", "intro" if row.def.type == "menu" else ("play" if row.def.type == "event" else "talk"))
	if ContentDB.SCHEMA.get(row.def.type, {}).get(field, "") != "script":
		return "Open a story passage to choose its image."
	if row.def.fields.has(field) and not row.def.fields[field].value.is_empty() and not row.def.fields[field].children.is_empty():
		return "This passage mixes inline text and nested steps; its source is preserved."
	var text: String = row.doc.field_value(row.def, field)
	return row.doc.set_field(row.def, field, "show " + image + ("\n" + text if not text.is_empty() else ""), true)

static func speech(row: Dictionary) -> Dictionary:
	for node: Dictionary in script_nodes(row):
		if node.kind == "text" and not str(node.text).is_empty():
			return node
	return {}

static func choices(row: Dictionary) -> Array:
	var d: FscParser.Definition = row.def
	if d.type == "menu" and not row.has("script_field"):
		return d.options.duplicate()
	if row.has("script_field") and ContentDB.SCHEMA.get(d.type, {}).get(row.script_field, "") == "menu":
		if not d.fields.has(row.script_field):
			return []
		var inner := FscParser.Definition.new()
		inner.type = "menu"
		inner.body = d.fields[row.script_field].children
		FscParser._read_fields(inner, FscParser.Result.new())
		return inner.options.duplicate()
	var out: Array = []
	_collect_choices(script_nodes(row), out)
	return out

static func _collect_choices(nodes: Array, out: Array) -> void:
	for node: Dictionary in nodes:
		match node.kind:
			"choices":
				for option: Dictionary in node.options:
					out.append(option)
					_collect_choices(option.body, out)
			"if":
				for branch: Dictionary in node.branches:
					_collect_choices(branch.body, out)
				if node["else"] is Array:
					_collect_choices(node["else"], out)
			"fight":
				for body: Array in node.outcomes.values():
					_collect_choices(body, out)

static func transition(option: Dictionary) -> Dictionary:
	var body: Array = option.body
	var direct: Array = []
	for index in body.size():
		var node: Dictionary = body[index]
		if node.kind == "goto":
			direct.append({"node": node, "index": index})
		elif _has_nested_goto(node):
			return {"editable": false, "target": "", "reason": "This response has conditional paths."}
	if direct.size() > 1 or (direct.size() == 1 and direct[0].index != body.size() - 1):
		return {"editable": false, "target": "", "reason": "This response has multiple paths."}
	if direct.is_empty():
		return {"editable": true, "target": "", "line": 0}
	return {"editable": true, "target": direct[0].node.target, "line": direct[0].node.line}

static func _has_nested_goto(node: Dictionary) -> bool:
	var lists: Array = []
	match node.kind:
		"if":
			for branch: Dictionary in node.branches:
				lists.append(branch.body)
			if node["else"] is Array:
				lists.append(node["else"])
		"choices":
			for option: Dictionary in node.options:
				lists.append(option.body)
		"fight":
			lists.append_array(node.outcomes.values())
	for nodes: Array in lists:
		for child: Dictionary in nodes:
			if child.kind == "goto" or _has_nested_goto(child):
				return true
	return false

static func _lines(doc: PackDocument) -> PackedStringArray:
	return doc.text.split("\n")

static func _save_lines(doc: PackDocument, lines: PackedStringArray) -> void:
	doc.change("\n".join(lines))

static func _replace_line(lines: PackedStringArray, index: int, value: String) -> void:
	var ending := "\r" if lines[index].ends_with("\r") else ""
	lines[index] = value + ending

static func _insert_line(doc: PackDocument, lines: PackedStringArray, index: int, value: String) -> void:
	var crlf := "\r\n" in doc.text
	if index >= lines.size():
		if crlf and not lines.is_empty() and not lines[-1].ends_with("\r"):
			lines[lines.size() - 1] += "\r"
		lines.append(value)
	else:
		var nearby_crlf := lines[index - 1].ends_with("\r") if index > 0 else crlf
		lines.insert(index, value + ("\r" if nearby_crlf else ""))

static func _indent(line: String) -> String:
	var i := 0
	while i < line.length() and line[i] in [" ", "\t"]:
		i += 1
	return line.left(i)

static func _option_end(lines: PackedStringArray, line: int) -> int:
	var start := line - 1
	var prefix := _indent(lines[start])
	var last := start
	for i in range(start + 1, lines.size()):
		var clean := lines[i].strip_edges()
		if clean.is_empty() or clean.begins_with("//"):
			continue
		if _indent(lines[i]).length() <= prefix.length():
			break
		last = i
	return last + 1

static func set_choice_text(row: Dictionary, option: Dictionary, value: String) -> String:
	var doc: PackDocument = row.doc
	if not doc.writable:
		return "This pack is read-only."
	value = value.strip_edges()
	if value.is_empty() or "\n" in value or "\r" in value:
		return "Enter one line for the player's response."
	var lines := _lines(doc)
	var index := int(option.line) - 1
	if index < 0 or index >= lines.size():
		return "The response has changed; reopen it and try again."
	var raw: String = lines[index].trim_suffix("\r")
	var star := raw.find("*")
	if star < 0:
		return "The response has changed; reopen it and try again."
	var body := raw.substr(star + 1).strip_edges(true, false)
	var prefix := raw.left(raw.length() - body.length())
	var suffix_start := body.length()
	var desc := body.find(" -- ")
	if desc >= 0:
		suffix_start = desc
	var tag := RegEx.create_from_string("\\s+\\[(?:if |then leave|always shown|number )").search(body)
	if tag != null:
		suffix_start = mini(suffix_start, tag.get_start())
	_replace_line(lines, index, prefix + value + body.substr(suffix_start))
	_save_lines(doc, lines)
	return ""

static func set_transition(row: Dictionary, option: Dictionary, target: String) -> String:
	var doc: PackDocument = row.doc
	if not doc.writable:
		return "This pack is read-only."
	var route := transition(option)
	if not route.editable:
		return route.reason
	if not target.is_empty() and RegEx.create_from_string("^[a-z0-9_][a-z0-9_.-]*$").search(target) == null:
		return "Choose a valid destination."
	var lines := _lines(doc)
	var index := int(option.line) - 1
	if index < 0 or index >= lines.size():
		return "The response has changed; reopen it and try again."
	if int(route.line) > 0:
		var goto_index: int = int(route.line) - 1
		if target.is_empty():
			lines.remove_at(goto_index)
		else:
			_replace_line(lines, goto_index, _indent(lines[goto_index]) + "-> " + target)
	elif not target.is_empty():
		var insertion := _option_end(lines, int(option.line))
		_insert_line(doc, lines, insertion, _indent(lines[index]) + "    -> " + target)
	_save_lines(doc, lines)
	return ""

static func add_choice(row: Dictionary) -> String:
	var doc: PackDocument = row.doc
	var d: FscParser.Definition = row.def
	if not doc.writable:
		return "This pack is read-only."
	var options := choices(row)
	var lines := _lines(doc)
	var insertion := -1
	var indent := ""
	if not options.is_empty():
		# Add to the first choice group, not to a nested conditional branch.
		var first: Dictionary = options[0]
		indent = _indent(lines[int(first.line) - 1])
		var last: Dictionary = first
		for option: Dictionary in options:
			if _indent(lines[int(option.line) - 1]) != indent:
				continue
			if int(option.line) > _option_end(lines, int(last.line)) + 1:
				break
			last = option
		insertion = _option_end(lines, int(last.line))
	elif row.has("script_field"):
		var field: String = row.script_field
		if d.fields.has(field) and not d.fields[field].value.is_empty() and not d.fields[field].children.is_empty():
			return "This passage has an introduction and additional steps; those are preserved until they can be edited safely."
		var existing := doc.field_value(d, field)
		var addition := "* New response"
		if not existing.is_empty():
			addition = existing + "\n\n" + addition
		return doc.set_field(d, field, addition)
	elif d.type in ["menu", "scene"]:
		var span := doc.block_range(d)
		var before := doc.text.left(span.y).replace("\r\n", "\n")
		insertion = before.count("\n") + 1
		if d.type == "scene":
			for i in range(d.line, mini(insertion, lines.size())):
				if lines[i].begins_with("-> "):
					insertion = i
					break
	else:
		return "Create a story node for the first response."
	_insert_line(doc, lines, insertion, indent + "* New response")
	_save_lines(doc, lines)
	return ""

static func set_speech(row: Dictionary, node: Dictionary, value: String) -> String:
	var doc: PackDocument = row.doc
	if not doc.writable:
		return "This pack is read-only."
	if node.is_empty():
		return "There is no plain speech block to edit here."
	if not passage_exists(row, node):
		return "This passage changed. Reopen it before editing."
	var original: String = node.text
	if "[" in original or "]" in original:
		return "This passage contains dynamic text; it is preserved until visual editing supports it."
	value = value.replace("\r\n", "\n").strip_edges()
	if value.is_empty():
		return "Enter some story text."
	for paragraph_line: String in value.split("\n"):
		if _is_statement(paragraph_line.strip_edges()):
			return "Use ordinary text here; add choices and actions with the buttons."
	if node.has("inline_field"):
		var field: FscParser.Field = row.def.fields[node.inline_field]
		if field.children.is_empty():
			return doc.set_field(row.def, str(node.inline_field), value)
		if "\n" in value:
			return "This passage needs to remain one line because other story steps follow it."
		var field_lines := _lines(doc)
		var field_index := field.line - 1
		_replace_line(field_lines, field_index, _indent(field_lines[field_index]) + str(node.inline_field) + ": " + value)
		_save_lines(doc, field_lines)
		return ""
	var lines := _lines(doc)
	var start := int(node.line) - 1
	if start < 0 or start >= lines.size():
		return "The passage has changed; reopen it and try again."
	var indent := _indent(lines[start])
	var scan := start + 1
	var following_text: Array[int] = []
	var comment_between_lines := false
	while scan < lines.size():
		var clean := lines[scan].strip_edges()
		if clean.begins_with("//"):
			comment_between_lines = true
			scan += 1
			continue
		if clean.is_empty() or _indent(lines[scan]) != indent or _is_statement(clean):
			break
		if comment_between_lines:
			return "This passage contains a note between lines and cannot be changed safely yet."
		following_text.append(scan)
		scan += 1
	for i in range(following_text.size() - 1, -1, -1):
		lines.remove_at(following_text[i])
	var replacement := value.split("\n")
	for i in range(replacement.size() - 1, -1, -1):
		var content: String = replacement[i]
		if i == 0:
			_replace_line(lines, start, indent + content)
		else:
			_insert_line(doc, lines, start + 1, indent + content)
	_save_lines(doc, lines)
	return ""

static func prose_block(row: Dictionary, node: Dictionary) -> Dictionary:
	if not passage_exists(row, node):
		return {"error": "This passage changed. Reopen it before editing."}
	if "[" in str(node.text) or "]" in str(node.text):
		return {"error": "This passage has changing text and cannot be edited as plain prose."}
	if node.has("inline_field"):
		return {"text": str(node.text), "inline": true}
	var lines := _lines(row.doc)
	var start := int(node.line) - 1
	if start < 0 or start >= lines.size():
		return {"error": "This passage changed. Reopen it before editing."}
	var indent := _indent(lines[start])
	var last := start
	var index := start + 1
	while index < lines.size():
		var raw: String = lines[index].trim_suffix("\r")
		var clean := raw.strip_edges()
		if clean.begins_with("//"):
			var look := index + 1
			while look < lines.size() and lines[look].strip_edges().begins_with("//"):
				look += 1
			if look < lines.size():
				var next := lines[look].strip_edges()
				if not next.is_empty() and _indent(lines[look]) == indent and not _is_statement(next):
					return {"error": "This passage contains a note between lines and cannot be changed safely yet."}
			break
		if clean.is_empty():
			index += 1
			continue
		if _indent(raw) != indent or _is_statement(clean) or "[" in clean or "]" in clean:
			break
		last = index
		index += 1
	var paragraphs := PackedStringArray()
	for line_index in range(start, last + 1):
		var raw: String = lines[line_index].trim_suffix("\r")
		paragraphs.append(raw.substr(indent.length()) if not raw.strip_edges().is_empty() else "")
	return {"text": "\n".join(paragraphs), "start": start, "end": last, "indent": indent}

static func set_prose_block(row: Dictionary, node: Dictionary, original: String, value: String) -> String:
	if not row.doc.writable:
		return "This pack is read-only."
	var block := prose_block(row, node)
	if block.has("error"):
		return block.error
	if block.text != original:
		return "This passage changed. Copy your draft and reopen it before applying."
	if block.get("inline", false):
		return set_speech(row, node, value)
	value = value.replace("\r\n", "\n").strip_edges()
	if value.is_empty():
		return "Enter some story text."
	for paragraph_line: String in value.split("\n"):
		if _is_statement(paragraph_line.strip_edges()):
			return "Use ordinary text here; add choices and actions with the buttons."
	var lines := _lines(row.doc)
	for index in range(int(block.end), int(block.start), -1):
		lines.remove_at(index)
	var replacement := value.split("\n")
	for index in range(replacement.size() - 1, -1, -1):
		var new_line: String = str(block.indent) + replacement[index]
		if index == 0:
			_replace_line(lines, int(block.start), new_line)
		else:
			_insert_line(row.doc, lines, int(block.start) + 1, new_line)
	_save_lines(row.doc, lines)
	return ""

static func _is_statement(text: String) -> bool:
	return text == "---" or text.begins_with("~") or text.begins_with("* ") or text == "*" or text.begins_with("->") or text.begins_with("play ") or text.begins_with("show ") or (text.begins_with("if ") and text.ends_with(":")) or text == "else:" or (text.begins_with("else if ") and text.ends_with(":")) or (text.begins_with("fight ") and text.ends_with(":")) or text.begins_with("==")

static func start_script(row: Dictionary, field: String, value: String) -> String:
	if not row.doc.writable: return "This pack is read-only."
	if row.def.type == "item" and field == "use" and row.def.fields.has("use action"):
		return "This item starts a built-in activity. Remove that activity in Use & reactions before writing a use story."
	if row.def.fields.has(field): return "This interaction changed. Your draft has been kept; reopen it before applying."
	if ContentDB.SCHEMA.get(row.def.type, {}).get(field, "") != "script": return "Choose a story passage to start writing."
	value = value.replace("\r\n", "\n").strip_edges()
	if value.is_empty(): return "Enter some story text."
	for line: String in value.split("\n"):
		if _is_statement(line.strip_edges()) or "[" in line or "]" in line:
			return "Use ordinary prose here. Add choices, actions and variations on the story board."
	return row.doc.set_field(row.def, field, value, true)

static func add_condition(row: Dictionary, option: Dictionary, condition: String) -> String:
	if not row.doc.writable:
		return "This pack is read-only."
	if Condition.compile(condition).has("error"):
		return "This condition is not supported by the engine."
	var lines := _lines(row.doc)
	var index := int(option.line) - 1
	if index < 0 or index >= lines.size():
		return "The response has changed; reopen it and try again."
	var pattern := RegEx.create_from_string("\\[if ([^\\[\\]]+)\\]")
	var match_result := pattern.search(lines[index])
	if match_result == null:
		_replace_line(lines, index, lines[index].trim_suffix("\r") + " [if " + condition + "]")
	else:
		var combined := "(" + match_result.get_string(1) + ") and (" + condition + ")"
		if Condition.compile(combined).has("error"):
			return "This existing condition cannot be combined safely."
		var line := lines[index].trim_suffix("\r")
		_replace_line(lines, index, line.left(match_result.get_start()) + "[if " + combined + "]" + line.substr(match_result.get_end()))
	_save_lines(row.doc, lines)
	return ""

static func add_effect(row: Dictionary, option: Dictionary, effect: String) -> String:
	if not row.doc.writable:
		return "This pack is read-only."
	if Effect.compile(effect).has("error"):
		return "This action is not supported by the engine."
	var route := transition(option)
	if not route.editable:
		return "This response has conditional paths; its action order needs separate editing."
	var lines := _lines(row.doc)
	var start := int(option.line) - 1
	if start < 0 or start >= lines.size():
		return "The response has changed; reopen it and try again."
	var at: int = int(route.line) - 1 if int(route.line) > 0 else _option_end(lines, int(option.line))
	_insert_line(row.doc, lines, at, _indent(lines[start]) + "    ~ " + effect)
	_save_lines(row.doc, lines)
	return ""

static func primary_transition(row: Dictionary) -> Dictionary:
	var nodes := script_nodes(row)
	if not nodes.is_empty() and nodes[-1].kind == "goto":
		return nodes[-1]
	return {}

static func remove_choice(row: Dictionary, option: Dictionary) -> String:
	if not row.doc.writable:
		return "This pack is read-only."
	var lines := _lines(row.doc)
	var start := int(option.line) - 1
	if start < 0 or start >= lines.size():
		return "The response has changed; reopen it and try again."
	var end := _option_end(lines, int(option.line))
	# Keep comments, including attribution and migration notes.
	for i in range(end - 1, start - 1, -1):
		if not lines[i].strip_edges().begins_with("//"):
			lines.remove_at(i)
	_save_lines(row.doc, lines)
	return ""

static func add_speech(row: Dictionary) -> String:
	var doc: PackDocument = row.doc
	var d: FscParser.Definition = row.def
	if not doc.writable:
		return "This pack is read-only."
	if row.has("script_field"):
		var field: String = row.script_field
		if ContentDB.SCHEMA.get(d.type, {}).get(field, "") == "menu":
			return "This menu's responses can be edited on the board."
		var existing := doc.field_value(d, field)
		return doc.set_field(d, field, "Write what happens here." + ("\n\n" + existing if not existing.is_empty() else ""))
	if d.type == "menu":
		if d.fields.has("intro"):
			return "This conversation already has an introduction."
		return doc.set_field(d, "intro", "Write what the speaker says.")
	if d.type != "scene":
		return "Create a story node to add a passage."
	var lines := _lines(doc)
	var index := d.line
	while index < lines.size():
		var clean := lines[index].strip_edges()
		if clean.is_empty() or clean.begins_with("//") or clean.begins_with("source:") or clean.begins_with("tags:"):
			index += 1
			continue
		break
	_insert_line(doc, lines, index, "Write what happens here.")
	_insert_line(doc, lines, index + 1, "")
	_save_lines(doc, lines)
	return ""

static func set_primary_transition(row: Dictionary, target: String) -> String:
	var doc: PackDocument = row.doc
	var d: FscParser.Definition = row.def
	if not doc.writable:
		return "This pack is read-only."
	if not target.is_empty() and RegEx.create_from_string("^[a-z0-9_][a-z0-9_.-]*$").search(target) == null:
		return "Choose a valid destination."
	var direct := primary_transition(row)
	if not direct.is_empty():
		if direct.has("inline_field"):
			return doc.set_field(d, str(direct.inline_field), "-> " + target if not target.is_empty() else "")
		var lines := _lines(doc)
		var index := int(direct.line) - 1
		if index < 0 or index >= lines.size():
			return "This story changed; reopen it before editing."
		if target.is_empty():
			lines.remove_at(index)
		else:
			_replace_line(lines, index, _indent(lines[index]) + "-> " + target)
		_save_lines(doc, lines)
		return ""
	if target.is_empty():
		return ""
	if d.type == "scene":
		var block := doc.block(d)
		var eol := "\r\n" if "\r\n" in doc.text else "\n"
		doc.replace_block(d, block + eol + "-> " + target)
		return ""
	if d.type in ["event", "character"] or row.has("script_field"):
		var field: String = row.get("script_field", "play" if d.type == "event" else "talk")
		var text := doc.field_value(d, field)
		return doc.set_field(d, field, (text + "\n" if not text.is_empty() else "") + "-> " + target)
	return "This kind of story has no automatic continuation."

static func clear_condition(row: Dictionary, option: Dictionary) -> String:
	if not row.doc.writable:
		return "This pack is read-only."
	var lines := _lines(row.doc)
	var index := int(option.line) - 1
	if index < 0 or index >= lines.size():
		return "This response has changed; reopen it and try again."
	var pattern := RegEx.create_from_string("\\s*\\[if [^\\[\\]]+\\]")
	var clean := lines[index].trim_suffix("\r")
	_replace_line(lines, index, pattern.sub(clean, "", true))
	_save_lines(row.doc, lines)
	return ""

static func set_effect(row: Dictionary, action: Dictionary, effect: String) -> String:
	if not row.doc.writable:
		return "This pack is read-only."
	if not effect.is_empty() and Effect.compile(effect).has("error"):
		return "This action is not supported by the engine."
	var lines := _lines(row.doc)
	var index := int(action.line) - 1
	if index < 0 or index >= lines.size() or not lines[index].strip_edges().begins_with("~"):
		return "This action has changed; reopen it and try again."
	if lines[index].strip_edges().substr(1).strip_edges() != str(action.text):
		return "This action has changed; reopen it and try again."
	if effect.is_empty():
		lines.remove_at(index)
	else:
		_replace_line(lines, index, _indent(lines[index]) + "~ " + effect)
	_save_lines(row.doc, lines)
	return ""

static func passage_exists(row: Dictionary, wanted: Dictionary) -> bool:
	var found: Array = []
	_collect_passages(script_nodes(row), found)
	for option: Dictionary in choices(row):
		_collect_passages(option.body, found)
	for passage: Dictionary in found:
		if passage.get("kind") == "text" and passage.get("line") == wanted.get("line") and passage.get("text") == wanted.get("text"):
			return true
	return false

static func _collect_passages(nodes: Array, out: Array) -> void:
	for node: Dictionary in nodes:
		if node.kind == "text":
			out.append(node)
		elif node.kind == "if":
			for branch: Dictionary in node.branches:
				_collect_passages(branch.body, out)
			if node["else"] is Array:
				_collect_passages(node["else"], out)
		elif node.kind == "choices":
			for option: Dictionary in node.options:
				_collect_passages(option.body, out)
		elif node.kind == "fight":
			for body: Array in node.outcomes.values():
				_collect_passages(body, out)

static func play_target(node: Dictionary) -> String:
	if node.get("kind", "") != "play":
		return ""
	var result := RegEx.create_from_string("^([a-z0-9_.-]+)(?:\\s|$)").search(str(node.target))
	return result.get_string(1) if result != null else ""

static func set_play_target(row: Dictionary, action: Dictionary, target: String) -> String:
	if not row.doc.writable:
		return "This pack is read-only."
	if not target.is_empty() and RegEx.create_from_string("^[a-z0-9_][a-z0-9_.-]*$").search(target) == null:
		return "Choose a valid destination."
	var lines := _lines(row.doc)
	var index := int(action.line) - 1
	if index < 0 or index >= lines.size():
		return "This story action changed. Reopen it before editing."
	var clean := lines[index].strip_edges()
	if not clean.begins_with("play ") or clean.substr(5).strip_edges() != str(action.target):
		return "This story action changed. Reopen it before editing."
	if target.is_empty():
		lines.remove_at(index)
	else:
		var old_target := play_target(action)
		if old_target.is_empty():
			return "This story action has a special target that cannot be rewired yet."
		var remainder: String = str(action.target).substr(old_target.length())
		_replace_line(lines, index, _indent(lines[index]) + "play " + target + remainder)
	_save_lines(row.doc, lines)
	return ""

static func add_primary_effect(row: Dictionary, effect: String) -> String:
	var doc: PackDocument = row.doc
	var d: FscParser.Definition = row.def
	if not doc.writable:
		return "This pack is read-only."
	if Effect.compile(effect).has("error"):
		return "This action is not supported by the engine."
	if d.type == "item" and row.get("script_field", "") == "use" and d.fields.has("use action"):
		return "This item starts a built-in activity. Remove that activity in Use & reactions before adding reactions."
	# A story-level action must run before the player chooses a response.
	for node: Dictionary in script_nodes(row):
		if node.kind != "choices": continue
		var lines := _lines(doc)
		var at := int(node.line) - 1
		_insert_line(doc, lines, at, _indent(lines[at]) + "~ " + effect)
		_save_lines(doc, lines)
		return ""
	var direct := primary_transition(row)
	if not direct.is_empty():
		if direct.has("inline_field"):
			return doc.set_field(d, str(direct.inline_field), "~ " + effect + "\n-> " + str(direct.target), true)
		var lines := _lines(doc)
		var at := int(direct.line) - 1
		_insert_line(doc, lines, at, _indent(lines[at]) + "~ " + effect)
		_save_lines(doc, lines)
		return ""
	if d.type == "scene" and not row.has("script_field"):
		var eol := "\r\n" if "\r\n" in doc.text else "\n"
		doc.replace_block(d, doc.block(d) + eol + "~ " + effect)
		return ""
	var field: String = row.get("script_field", "play" if d.type == "event" else "talk")
	if ContentDB.SCHEMA.get(d.type, {}).get(field, "") != "script":
		return "Open a story passage to add an action."
	if d.fields.has(field) and not d.fields[field].value.is_empty() and not d.fields[field].children.is_empty():
		return "This passage has an introduction and additional steps; those are preserved until they can be edited safely."
	if d.fields.has(field) and not d.fields[field].children.is_empty():
		var lines := _lines(doc)
		var at: int = d.fields[field].children[-1].number
		_insert_line(doc, lines, at, "    ~ " + effect)
		_save_lines(doc, lines)
		return ""
	var text := doc.field_value(d, field)
	return doc.set_field(d, field, (text + "\n" if not text.is_empty() else "") + "~ " + effect, true)

static func set_choice_description(row: Dictionary, option: Dictionary, value: String) -> String:
	if not row.doc.writable:
		return "This pack is read-only."
	value = value.strip_edges()
	if "\n" in value or "\r" in value:
		return "Use a single line for the response description."
	var lines := _lines(row.doc)
	var index := int(option.line) - 1
	if index < 0 or index >= lines.size():
		return "This response has changed; reopen it and try again."
	var raw := lines[index].trim_suffix("\r")
	var star := raw.find("*")
	if star < 0:
		return "This response has changed; reopen it and try again."
	var body := raw.substr(star + 1).strip_edges(true, false)
	var prefix := raw.left(raw.length() - body.length())
	var tags := RegEx.create_from_string("\\s+\\[(?:if |then leave|always shown|number )").search(body)
	var suffix := body.substr(tags.get_start()) if tags != null else ""
	var result := prefix + str(option.label) + (" -- " + value if not value.is_empty() else "") + suffix
	_replace_line(lines, index, result)
	_save_lines(row.doc, lines)
	return ""

static func set_choice_toggle(row: Dictionary, option: Dictionary, tag: String, enabled: bool) -> String:
	if not row.doc.writable or tag not in ["then leave", "always shown"]:
		return "This response cannot be changed."
	var lines := _lines(row.doc)
	var index := int(option.line) - 1
	if index < 0 or index >= lines.size():
		return "This response has changed; reopen it and try again."
	var line := lines[index].trim_suffix("\r")
	var token := " [" + tag + "]"
	if enabled and token not in line:
		line += token
	elif not enabled:
		line = line.replace(token, "")
	_replace_line(lines, index, line)
	_save_lines(row.doc, lines)
	return ""

static func add_story_step(row: Dictionary, step: String) -> String:
	var doc: PackDocument = row.doc
	var d: FscParser.Definition = row.def
	if not doc.writable:
		return "This pack is read-only."
	if step != "---" and not step.begins_with("play "):
		return "This story step is not supported."
	var direct := primary_transition(row)
	if not direct.is_empty():
		if direct.has("inline_field"):
			return doc.set_field(d, str(direct.inline_field), step + "\n-> " + str(direct.target), true)
		var lines := _lines(doc)
		var at := int(direct.line) - 1
		_insert_line(doc, lines, at, _indent(lines[at]) + step)
		_save_lines(doc, lines)
		return ""
	if d.type == "scene" and not row.has("script_field"):
		var eol := "\r\n" if "\r\n" in doc.text else "\n"
		doc.replace_block(d, doc.block(d) + eol + step)
		return ""
	var field: String = row.get("script_field", "play" if d.type == "event" else "talk")
	if ContentDB.SCHEMA.get(d.type, {}).get(field, "") != "script":
		return "Open a story passage to add this step."
	if d.fields.has(field) and not d.fields[field].value.is_empty() and not d.fields[field].children.is_empty():
		return "This passage has an introduction and additional steps; those are preserved until they can be edited safely."
	var text := doc.field_value(d, field)
	return doc.set_field(d, field, (text + "\n" if not text.is_empty() else "") + step, true)

static func set_branch_condition(row: Dictionary, branch: Dictionary, condition: String) -> String:
	if not row.doc.writable:
		return "This pack is read-only."
	if Condition.compile(condition).has("error"):
		return "This condition is not supported by the engine."
	var lines := _lines(row.doc)
	var index := int(branch.line) - 1
	if index < 0 or index >= lines.size():
		return "This branch has changed; reopen it and try again."
	var raw := lines[index].trim_suffix("\r")
	var expression := RegEx.create_from_string("^(\\s*)(if|else if)\\s+(.+):\\s*$").search(raw)
	if expression == null or expression.get_string(3).strip_edges() != str(branch.condition):
		return "This branch has changed; reopen it and try again."
	_replace_line(lines, index, expression.get_string(1) + expression.get_string(2) + " " + condition + ":")
	_save_lines(row.doc, lines)
	return ""

static func dynamic_parts(row: Dictionary, passage: Dictionary) -> Array:
	var lines := _lines(row.doc)
	var index := int(passage.line) - 1
	if index < 0 or index >= lines.size():
		return []
	var physical := lines[index].trim_suffix("\r").strip_edges()
	var text: String = passage.text
	if physical != text:
		return []
	var parts: Array = []
	var pattern := RegEx.create_from_string("\\[[^\\[\\]]+\\]")
	var previous := 0
	for tag in pattern.search_all(text):
		if tag.get_start() > previous:
			parts.append({"kind": "text", "start": previous, "end": tag.get_start(), "text": text.substr(previous, tag.get_start() - previous)})
		parts.append({"kind": "tag", "text": tag.get_string()})
		previous = tag.get_end()
	if previous < text.length():
		parts.append({"kind": "text", "start": previous, "end": text.length(), "text": text.substr(previous)})
	return parts

static func set_dynamic_fragment(row: Dictionary, passage: Dictionary, part: Dictionary, value: String) -> String:
	if not row.doc.writable:
		return "This pack is read-only."
	if "[" in value or "]" in value or "\n" in value or "\r" in value:
		return "Use one line of ordinary text in this part of the bubble."
	if not passage_exists(row, passage):
		return "This passage changed. Reopen it before editing."
	var parts := dynamic_parts(row, passage)
	var exists := false
	for candidate: Dictionary in parts:
		if candidate.kind == "text" and candidate.start == part.start and candidate.end == part.end and candidate.text == part.text:
			exists = true
			break
	if not exists:
		return "This passage changed. Reopen it before editing."
	var lines := _lines(row.doc)
	var index := int(passage.line) - 1
	var raw := lines[index].trim_suffix("\r")
	var indent := _indent(raw)
	var text: String = passage.text
	var trailing := raw.substr(indent.length() + text.length())
	var updated := text.left(int(part.start)) + value + text.substr(int(part.end))
	_replace_line(lines, index, indent + updated + trailing)
	_save_lines(row.doc, lines)
	return ""

static func set_dynamic_text(row: Dictionary, passage: Dictionary, value: String) -> String:
	if not row.doc.writable:
		return "This pack is read-only."
	if not passage_exists(row, passage):
		return "This passage changed. Reopen it before editing."
	var lines := _lines(row.doc)
	var index := int(passage.line) - 1
	if index < 0 or index >= lines.size():
		return "This passage changed. Reopen it before editing."
	var raw := lines[index].trim_suffix("\r")
	var indent := _indent(raw)
	var text: String = passage.text
	if raw.strip_edges() != text:
		return "This multi-line passage cannot be changed as a single variation yet."
	var trailing := raw.substr(indent.length() + text.length())
	_replace_line(lines, index, indent + value + trailing)
	_save_lines(row.doc, lines)
	return ""

static func make_variation(row: Dictionary, passage: Dictionary) -> String:
	var text: String = passage.text
	if "[" in text or "]" in text:
		return "This passage already contains changing text."
	return set_dynamic_text(row, passage, "[one of]" + text + "[or]Write another variation.[at random]")

static func add_alternative(row: Dictionary, passage: Dictionary) -> String:
	var text: String = passage.text
	if text.count("[one of]") != 1:
		return "Choose a passage with one set of variations."
	var start := text.find("[one of]")
	var end := -1
	for ending in ["[at random]", "[purely at random]", "[cycling]", "[stopping]", "[sticky]", "[sticky random]", "[in random order]", "[as decreasingly likely outcomes]"]:
		var position := text.find(ending, start)
		if position >= 0 and (end < 0 or position < end):
			end = position
	if end < 0:
		return "This variation has an ending that cannot be edited safely yet."
	return set_dynamic_text(row, passage, text.left(end) + "[or]Write another variation." + text.substr(end))

static func make_conditional_text(row: Dictionary, passage: Dictionary, condition: String) -> String:
	if Condition.compile(condition).has("error"):
		return "This condition is not supported by the engine."
	var text: String = passage.text
	if "[" in text or "]" in text:
		return "This passage already contains changing text."
	return set_dynamic_text(row, passage, "[if " + condition + "]" + text + "[else]Write an alternative.[end if]")
