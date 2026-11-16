class_name ContentTools
extends RefCounted
## Changes that reach across a pack: safe rename, duplicate, delete with its
## consequences. Each returns an error text, or nothing when it worked.

const PROSE := "^(name|title|subtitle|description|about|personal name|species|body text|leave|shows|dismissed|no trophy|status|rest text|carried rest text|ground rest text|purify refusal|artist|link|source|authors|license|version)$|(label|prompt|hint|death|ending|refusal|text)$"

## Applies `change` to the parts of a line where IDs are meant, and returns
## the line. Prose is left alone, except words in square brackets. A
## definition's header line is not handled here.
static func map_code(raw: String, change: Callable) -> String:
	var clean := raw.strip_edges()
	if clean.begins_with("~") or clean.begins_with("->") or clean.begins_with("play ") or clean.begins_with("show ") or (clean.begins_with("fight ") and clean.ends_with(":")) or ((clean.begins_with("if ") or clean.begins_with("else if ")) and clean.ends_with(":")):
		var cut := raw.length()
		# The words a player is asked, or reads as a reason, are prose.
		if clean.begins_with("~ ask ") and ":" in raw: cut = raw.find(":")
		if clean.begins_with("~ ending reason "): cut = 0
		return str(change.call(raw.left(cut))) + raw.substr(cut)
	var named := _field.search(raw)
	if named != null and _prose.search(named.get_string(2)) == null and not clean.begins_with("* "):
		return named.get_string(1) + named.get_string(2) + ":" + named.get_string(3) + str(change.call(named.get_string(4)))
	# Prose, and a response's own words: only what is in square brackets.
	var result := ""
	var last := 0
	for marked: RegExMatch in _bracket.search_all(raw):
		result += raw.substr(last, marked.get_start() - last) + str(change.call(marked.get_string()))
		last = marked.get_end()
	return result + raw.substr(last)

static var _prose := RegEx.create_from_string(PROSE)
static var _field := RegEx.create_from_string("^(\\s*)([a-z][a-z ]*?):(\\s+)(.*)$")
static var _bracket := RegEx.create_from_string("\\[[^\\[\\]]*\\]")

## The parts of a line where IDs are meant, joined: for finding uses.
static func code_text(raw: String) -> String:
	var parts: Array[String] = []
	map_code(raw, func(part: String) -> String:
		parts.append(part)
		return part)
	return " ".join(parts)

## Every place an ID would change: [{doc, line, before, after, where, text}].
static func rename_plan(workspace: PackWorkspace, row: Dictionary, new_id: String) -> Array[Dictionary]:
	var plan: Array[Dictionary] = []
	var old: String = row.def.id
	var type: String = row.def.type
	var token := RegEx.create_from_string("(?<![a-z0-9_.-])" + old.replace(".", "\\.") + "(?![a-z0-9_-])")
	var header := RegEx.create_from_string("^(==\\s+(?:extend\\s+|replace\\s+)?([a-z_]+)\\s+)(\\S+)(.*)$")
	var paths: Array = workspace.documents.keys()
	paths.sort()
	for path: String in paths:
		var doc: PackDocument = workspace.documents[path]
		if not doc.writable: continue
		var lines: PackedStringArray = doc.text.split("\n")
		var owner := ""
		for index in lines.size():
			var raw := lines[index].trim_suffix("\r")
			var clean := raw.strip_edges()
			if clean.is_empty() or clean.begins_with("//"): continue
			var after := raw
			var head := header.search(raw)
			if head != null:
				owner = Wording.readable(head.get_string(3))
				if head.get_string(2) == type and head.get_string(3) == old: after = head.get_string(1) + new_id + head.get_string(4)
			else: after = map_code(raw, func(part: String) -> String: return token.sub(part, new_id, true))
			if after != raw: plan.append({"doc": doc, "line": index + 1, "before": clean, "after": after.strip_edges(), "where": owner + " · " + path.get_file(), "text": after + ("\r" if lines[index].ends_with("\r") else "")})
	return plan

static func rename_problem(workspace: PackWorkspace, row: Dictionary, new_id: String) -> String:
	if not row.doc.writable: return "Content of another pack cannot be renamed here."
	if RegEx.create_from_string("^[a-z0-9_][a-z0-9_.-]*$").search(new_id) == null: return "Use lowercase letters, numbers and underscores."
	if new_id == row.def.id: return "This is the name it already has."
	for other: Dictionary in workspace.rows:
		if other.def.type == row.def.type and other.def.id == new_id: return "Another " + Wording.name(row.def.type) + " already uses this ID."
	return ""

## Applies the chosen lines of a rename plan as one undo step. A rename that
## would leave the pack with more problems than before is taken back.
static func rename(workspace: PackWorkspace, row: Dictionary, new_id: String, plan: Array) -> String:
	var problem := rename_problem(workspace, row, new_id)
	if not problem.is_empty(): return problem
	workspace.validate()
	var before := workspace.diagnostics.filter(func(item: Dictionary) -> bool: return item.severity == "error").size()
	return workspace.transaction("Rename %s to %s" % [row.def.id, new_id], func() -> String:
		var changed: Dictionary = {}
		for entry: Dictionary in plan:
			var doc: PackDocument = entry.doc
			if not changed.has(doc.path): changed[doc.path] = {"doc": doc, "lines": doc.text.split("\n")}
			changed[doc.path].lines[int(entry.line) - 1] = entry.text
		for path: String in changed: changed[path].doc.change("\n".join(changed[path].lines))
		workspace.reindex()
		workspace.validate()
		var after := workspace.diagnostics.filter(func(item: Dictionary) -> bool: return item.severity == "error").size()
		if after > before: return "Renaming this way would leave %d new problem%s (the first: %s). Nothing was changed." % [after - before, "" if after - before == 1 else "s", str(workspace.diagnostics.filter(func(item: Dictionary) -> bool: return item.severity == "error")[-1].message)]
		return "")

## A copy with a new ID and "copy" in its name. Returns {id} or {error}.
static func make_copy(workspace: PackWorkspace, row: Dictionary) -> Dictionary:
	var definition: FscParser.Definition = row.def
	if definition.type == "pack": return {"error": "A pack has one manifest."}
	var block: String = row.doc.block(definition)
	var body := block.substr(block.find("\n") + 1) if "\n" in block else ""
	var id := workspace.unique_id(str(definition.id) + "_copy", definition.type)
	var lines := body.replace("\r\n", "\n").split("\n")
	for index in lines.size():
		if lines[index].begins_with("name: "): lines[index] = lines[index] + " copy"
	var error := workspace.transaction("Duplicate " + Wording.title(row), func() -> String:
		return workspace.create_definition(definition.type, id, "define", "\n".join(lines)))
	return {"error": error} if not error.is_empty() else {"id": id, "type": definition.type}

## Lines that only exist to use this content: actions, links and pictures.
static func removable_uses(workspace: PackWorkspace, row: Dictionary) -> Array:
	return workspace.uses(row.def.id).filter(func(use: Dictionary) -> bool:
		var text: String = use.text
		return text.begins_with("~") or text.begins_with("-> ") or text.begins_with("play ") or text.begins_with("show "))

## Removes the content; with `uses_too`, also the action and link lines that use it.
static func delete(workspace: PackWorkspace, row: Dictionary, uses_too: bool) -> String:
	if not row.doc.writable: return "Content of another pack cannot be deleted here."
	if row.def.type == "pack": return "The pack's own entry cannot be deleted."
	return workspace.transaction("Delete " + Wording.title(row), func() -> String:
		var doomed: Dictionary = {}
		if uses_too:
			for use: Dictionary in removable_uses(workspace, row):
				var path: String = use.row.doc.path
				if not doomed.has(path): doomed[path] = []
				doomed[path].append(int(use.line))
		var span: Vector2i = row.doc.block_range(row.def)
		var first_line: int = row.doc.text.left(span.x).count("\n") + 1
		var last_line: int = row.doc.text.left(span.y).count("\n") + 1
		for path: String in doomed:
			var doc: PackDocument = workspace.documents[path]
			var lines := doc.text.split("\n")
			var numbers: Array = doomed[path]
			numbers.sort()
			numbers.reverse()
			for number: int in numbers:
				if path == row.doc.path and number >= first_line and number <= last_line: continue
				lines.remove_at(number - 1)
				if path == row.doc.path and number < first_line:
					first_line -= 1
					last_line -= 1
			doc.change("\n".join(lines))
		var remaining: PackedStringArray = str(row.doc.text).split("\n")
		for number in range(last_line, first_line - 1, -1): remaining.remove_at(number - 1)
		row.doc.change("\n".join(remaining))
		return "")
