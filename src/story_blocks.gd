class_name StoryBlocks
extends RefCounted
## Block-level changes to a story's source. Each takes the text snapshot the
## author was looking at and refuses to act on anything that changed since.

const FIGHT_FIELDS := ["vore", "hard vore", "unbirth", "attack", "grapple", "escape", "struggle", "defeated", "victory", "attacks", "each round", "before attack", "after attack", "fight starts", "miss", "hump", "pounce", "breath warning", "breath direct", "breath partial", "breath miss", "won", "lost", "before flee", "player damage", "avoid", "enemy damage", "second fight", "companion attack"]

## What applies where this story runs, for the chooser's filtering.
static func contexts(row: Dictionary, inside_fight: bool = false) -> Array:
	var result: Array = []
	if row.is_empty(): return result
	var type: String = row.def.type
	var field: String = row.get("script_field", "")
	if type == "event":
		result.append("event")
		if "leaving " in str(row.doc.field_value(row.def, "found by")): result.append("leaving")
	if type == "item" and field == "use": result.append("item_use")
	if type == "creature" and field in ["", "encounter"]: result.append("encounter")
	if type == "character" and field in ["summon", "dismiss"]: result.append("companion")
	if inside_fight or field in FIGHT_FIELDS or type == "combat_rules": result.append("fight")
	return result

static func script_key(row: Dictionary) -> String:
	if row.has("script_field"): return row.script_field
	return {"menu": "intro", "event": "play", "character": "talk", "creature": "encounter", "item": "use", "location": "enter", "ending": "play", "hook": "do", "scenario": "intro"}.get(row.def.type, "")

static func children(entries: Array[Dictionary], key: String) -> Array[Dictionary]:
	return entries.filter(func(entry: Dictionary) -> bool: return entry.parent == key)

## The place for new blocks at the end of a container, or of the whole story
## when `parent` is empty. A closing group of responses stays last.
static func end_spot(row: Dictionary, entries: Array[Dictionary], parent: Dictionary = {}) -> Dictionary:
	var kids := children(entries, str(parent.get("key", "")))
	var menu: bool = row.def.type == "menu" and not row.has("script_field")
	if parent.is_empty() and menu: kids = kids.filter(func(entry: Dictionary) -> bool: return entry.node.kind != "choices")
	if not kids.is_empty() and kids[0].node.has("inline_field"): return {"field": kids[0].node.inline_field, "inline": true}
	if not kids.is_empty():
		var last: Dictionary = kids[-1]
		if last.node.kind in ["choices", "goto"]: return {"line": last.line, "indent": last.indent}
		return {"line": last.end_line, "indent": kids[0].indent}
	if not parent.is_empty(): return {"line": int(parent.line) + 1, "indent": str(parent.indent) + "    "}
	if row.def.type in ["scene", "text"] and not row.has("script_field"): return {"start": true}
	return {"field": script_key(row)}

static func before_spot(entry: Dictionary) -> Dictionary:
	return {"line": entry.line, "indent": entry.indent}

static func after_spot(entry: Dictionary) -> Dictionary:
	return {"line": entry.end_line, "indent": entry.indent}

## Checks that `content` is whole story blocks the engine can read.
static func check(content: String) -> String:
	var parsed := FscParser.parse("== scene block_draft\n" + content + "\n")
	if not parsed.ok() or parsed.definitions.size() != 1: return str(parsed.diagnostics[0].message) if not parsed.diagnostics.is_empty() else "These are not whole story blocks."
	var program := Program.compile("block_draft", parsed.definitions[0].nodes)
	return str(program.errors[0].message) if not program.errors.is_empty() else ""

static func insert(row: Dictionary, spot: Dictionary, content: String, snapshot: String) -> String:
	if not row.doc.writable: return "This pack is read-only."
	if row.doc.text != snapshot: return "This story changed. Reopen it before editing."
	if spot.has("line"): return StoryGraph.insert_block(row, int(spot.line), str(spot.indent), content, snapshot)
	var problem := check(content)
	if not problem.is_empty(): return problem
	if spot.has("start"):
		var lines := StoryGraph._lines(row.doc)
		var span: Vector2i = row.doc.block_range(row.def)
		var last: int = row.doc.text.left(span.y).count("\n") + 1
		var index: int = row.def.line
		while index < last and index < lines.size():
			var clean := lines[index].strip_edges()
			if clean.is_empty() or clean.begins_with("//") or clean.begins_with("source:") or clean.begins_with("tags:") or clean.begins_with("title:"): index += 1
			else: break
		var added := content.split("\n")
		for at in range(added.size() - 1, -1, -1): StoryGraph._insert_line(row.doc, lines, index, added[at])
		StoryGraph._save_lines(row.doc, lines)
		return ""
	var key: String = spot.get("field", "")
	if key.is_empty() or ContentDB.SCHEMA.get(row.def.type, {}).get(key, "") not in ["script", "menu"]: return "Open a story to add blocks to it."
	if row.def.type == "item" and key == "use" and row.def.fields.has("use action"): return "This item starts a built-in activity. Remove that activity in its details before writing a use story."
	var field: FscParser.Field = row.def.fields.get(key)
	if field == null or (field.value.is_empty() and field.children.is_empty()): return row.doc.set_field(row.def, key, content, true)
	if not field.children.is_empty(): return "This story mixes a first line with further steps; it is kept as it is."
	var existing: String = field.value
	return row.doc.set_field(row.def, key, content + "\n" + existing if existing.begins_with("->") else existing + "\n" + content, true)

## Replaces one statement line (an action, a link, a picture, a header), keeping its indentation.
static func set_line(row: Dictionary, entry: Dictionary, statement: String, snapshot: String) -> String:
	if not row.doc.writable: return "This pack is read-only."
	if row.doc.text != snapshot: return "This story changed. Reopen it before editing."
	if entry.node.has("inline_field"):
		return row.doc.set_field(row.def, str(entry.node.inline_field), statement)
	var lines := StoryGraph._lines(row.doc)
	var index := int(entry.line) - 1
	if index < 0 or index >= lines.size(): return "This story changed. Reopen it before editing."
	StoryGraph._replace_line(lines, index, StoryGraph._indent(lines[index]) + statement)
	StoryGraph._save_lines(row.doc, lines)
	return ""

## The source of a block, without its indentation: what copy and the writing box use.
static func source(row: Dictionary, entry: Dictionary) -> String:
	if entry.node.has("inline_field"): return str(entry.node.get("text", ""))
	var lines := StoryGraph._lines(row.doc)
	var out: Array[String] = []
	for index in range(int(entry.line) - 1, mini(int(entry.end_line) - 1, lines.size())):
		out.append(lines[index].trim_suffix("\r").trim_prefix(str(entry.indent)))
	while not out.is_empty() and out[-1].strip_edges().is_empty(): out.remove_at(out.size() - 1)
	return "\n".join(out)

## Rewrites a passage of prose. Blank lines make new paragraphs.
static func set_text(row: Dictionary, entry: Dictionary, value: String, snapshot: String) -> String:
	if not row.doc.writable: return "This pack is read-only."
	if row.doc.text != snapshot: return "This story changed. Reopen it before editing."
	value = value.replace("\r\n", "\n").replace("\r", "\n").strip_edges()
	if value.is_empty(): return "Write some text, or remove the block instead."
	for line: String in value.split("\n"):
		if StoryGraph._is_statement(line.strip_edges()): return "A line here starts like an action or a response. Add those with “Add here” instead."
		var compiled := TextTemplate.compile(line)
		if compiled.has("error"): return "The text has a problem: " + str(compiled.error)
	if entry.node.has("inline_field"):
		var field: FscParser.Field = row.def.fields[entry.node.inline_field]
		if not field.children.is_empty() and "\n" in value: return "This first line must stay one line because other steps follow it."
		if field.children.is_empty(): return row.doc.set_field(row.def, str(entry.node.inline_field), value)
		return set_line(row, entry, str(entry.node.inline_field) + ": " + value, snapshot)
	var lines := StoryGraph._lines(row.doc)
	for index in range(int(entry.line) - 1, int(entry.end_line) - 1):
		if lines[index].strip_edges().begins_with("//"): return "This passage holds a note between its lines; it is kept as it is."
	for index in range(int(entry.end_line) - 2, int(entry.line) - 2, -1): lines.remove_at(index)
	var added := value.split("\n")
	for at in range(added.size() - 1, -1, -1): StoryGraph._insert_line(row.doc, lines, int(entry.line) - 1, (str(entry.indent) + added[at]) if not added[at].strip_edges().is_empty() else "")
	StoryGraph._save_lines(row.doc, lines)
	return ""

## Adds "else if <condition>:" or, with an empty condition, "else:" to an if block.
static func add_branch(row: Dictionary, entries: Array[Dictionary], block: Dictionary, condition: String, snapshot: String) -> String:
	if not row.doc.writable: return "This pack is read-only."
	if row.doc.text != snapshot: return "This story changed. Reopen it before editing."
	if block.node.kind != "if": return "Choose an “Only if” block."
	if not condition.is_empty() and Condition.compile(condition).has("error"): return "The engine cannot read this condition."
	var branches := children(entries, block.key)
	var otherwise: Dictionary = {}
	for branch: Dictionary in branches:
		if str(branch.node.get("condition", "")).is_empty(): otherwise = branch
	if condition.is_empty() and not otherwise.is_empty(): return "This block already has an “Otherwise”."
	var lines := StoryGraph._lines(row.doc)
	var at: int = int(otherwise.line) - 1 if not otherwise.is_empty() else int(block.end_line) - 1
	StoryGraph._insert_line(row.doc, lines, at, str(block.indent) + ("else if " + condition + ":" if not condition.is_empty() else "else:"))
	StoryGraph._save_lines(row.doc, lines)
	return ""

## Removes one "else if" or "else" with its blocks. The first branch goes with the whole block.
static func remove_branch(row: Dictionary, entries: Array[Dictionary], branch: Dictionary, snapshot: String) -> String:
	if not row.doc.writable: return "This pack is read-only."
	if row.doc.text != snapshot: return "This story changed. Reopen it before editing."
	var lines := StoryGraph._lines(row.doc)
	if lines[int(branch.line) - 1].strip_edges().begins_with("if "): return "Remove the whole “Only if” block instead."
	for index in range(int(branch.line) - 1, int(branch.end_line) - 1):
		if lines[index].strip_edges().begins_with("//"): return "This part holds notes; it is kept as it is."
	for index in range(int(branch.end_line) - 2, int(branch.line) - 2, -1): lines.remove_at(index)
	StoryGraph._save_lines(row.doc, lines)
	return ""

## Removes an "Only if" header and keeps its blocks, when there is nothing else in it.
static func unwrap(row: Dictionary, entries: Array[Dictionary], block: Dictionary, snapshot: String) -> String:
	if not row.doc.writable: return "This pack is read-only."
	if row.doc.text != snapshot: return "This story changed. Reopen it before editing."
	if block.node.kind != "if" or children(entries, block.key).size() != 1: return "Remove the other branches first."
	var lines := StoryGraph._lines(row.doc)
	for index in range(int(block.line), int(block.end_line) - 1):
		if not lines[index].strip_edges().is_empty() and not lines[index].begins_with(str(block.indent) + "    "): return "This block has unusual indentation; it is kept as it is."
	for index in range(int(block.line), int(block.end_line) - 1):
		if not lines[index].strip_edges().is_empty(): StoryGraph._replace_line(lines, index, str(block.indent) + lines[index].trim_suffix("\r").substr(str(block.indent).length() + 4))
	lines.remove_at(int(block.line) - 1)
	StoryGraph._save_lines(row.doc, lines)
	return ""

## Adds a won / lost / fled part to a fight.
static func add_outcome(row: Dictionary, entries: Array[Dictionary], fight: Dictionary, outcome: String, snapshot: String) -> String:
	if not row.doc.writable: return "This pack is read-only."
	if row.doc.text != snapshot: return "This story changed. Reopen it before editing."
	if fight.node.kind != "fight" or fight.node.outcomes.has(outcome): return "This fight already has that part."
	var kids := children(entries, fight.key)
	var lines := StoryGraph._lines(row.doc)
	var indent: String = str(kids[0].indent) if not kids.is_empty() else str(fight.indent) + "    "
	var at: int = int(kids[-1].end_line) - 1 if not kids.is_empty() else int(fight.line)
	StoryGraph._insert_line(row.doc, lines, at, indent + outcome + ":")
	StoryGraph._save_lines(row.doc, lines)
	return ""

## Moves several neighbouring blocks as one, to just before `before_line`.
static func move_many(row: Dictionary, blocks: Array[Dictionary], before_line: int, indent: String, snapshot: String, copy: bool = false) -> String:
	if not row.doc.writable: return "This pack is read-only."
	if row.doc.text != snapshot: return "This story changed. Reopen it before editing."
	if blocks.is_empty(): return "Choose a block first."
	var ordered := blocks.duplicate()
	ordered.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return int(a.line) < int(b.line))
	var payload: Array[String] = []
	for block: Dictionary in ordered:
		if block.node.has("inline_field") or block.node.kind in ["branch", "outcome", "choices"]: return "Move the whole condition, fight or response instead."
		if before_line > int(block.line) and before_line < int(block.end_line): return "A block cannot be moved inside itself."
		payload.append(source(row, block))
	var old: String = row.doc.text
	var target := before_line
	if not copy:
		var lines := StoryGraph._lines(row.doc)
		for at in range(ordered.size() - 1, -1, -1):
			var block: Dictionary = ordered[at]
			for index in range(int(block.end_line) - 2, int(block.line) - 2, -1): lines.remove_at(index)
			if before_line >= int(block.end_line): target -= int(block.end_line) - int(block.line)
		StoryGraph._save_lines(row.doc, lines)
	var error := StoryGraph.insert_block(row, target, indent, "\n".join(payload), row.doc.text)
	if not error.is_empty(): row.doc.text = old
	return error

## One response line: "* label -- description [if condition] [then leave] [always shown]".
static func response_line(label: String, description: String, condition: String, leaves: bool, always: bool, extra: String = "") -> String:
	return "* " + label.strip_edges() + (" -- " + description.strip_edges() if not description.strip_edges().is_empty() else "") + (" [if " + condition + "]" if not condition.is_empty() else "") + (" [then leave]" if leaves else "") + (" [always shown]" if always else "") + extra
