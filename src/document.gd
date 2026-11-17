class_name PackDocument
extends RefCounted
## Keep original bytes outside the exact range an author changes.

signal changed(before: String)

var path: String
var original: String
## The file's text as it stands in the editor. Every change raises `version`,
## so what is worked out from the text (lines, parsed content, where each
## definition starts and ends) is worked out once per change, however large the file.
var text: String:
	set(value):
		text = value
		version += 1
var version := 0
var writable: bool
var existed_at_open: bool


func _init(file_path: String, can_write: bool, contents: Variant = null) -> void:
	path = file_path
	writable = can_write
	if contents is String:
		# Read already, by whoever loads many files at once.
		existed_at_open = true
		original = contents
	else:
		existed_at_open = FileAccess.file_exists(path)
		original = FileAccess.get_file_as_string(path) if existed_at_open else ""
	text = original


func change(value: String) -> void:
	if not writable or value == text:
		return
	var before := text
	text = value
	changed.emit(before)


var _dirty_version := -1
var _dirty := false

## Whether the text differs from the file. Compared once per change: files can be large.
func dirty() -> bool:
	if _dirty_version != version:
		_dirty = original != text
		_dirty_version = version
	return _dirty


var _parsed_version := -1
var _parsed: FscParser.Result
var _parsed_lines: PackedStringArray
## Set to check every partial parse against a parse of the whole file (tests).
static var verify_parses := false
## How many times a file was parsed whole, and in part (for tests and measuring).
static var whole_parses := 0
static var partial_parses := 0

## The file as the engine's parser reads it. After a change only the
## definitions around the changed lines are parsed again: the others are
## kept, and those further down are moved to their new line numbers.
func parsed() -> FscParser.Result:
	if _parsed != null and _parsed_version == version: return _parsed
	var fresh: PackedStringArray = lines() if writable else PackedStringArray()
	if _parsed == null or not writable or not _reparse(fresh):
		_parsed = FscParser.parse(text, path)
		whole_parses += 1
	elif verify_parses:
		var whole := FscParser.parse(text, path)
		if describe(whole) != describe(_parsed):
			push_error("A partial parse of %s differs from the whole one." % path)
			_parsed = whole
	# A file that cannot change is never parsed in part: its lines are not kept.
	_parsed_lines = fresh if writable else PackedStringArray()
	_parsed_version = version
	return _parsed

## Hands over a parse made elsewhere (on another thread) for the text as it is now.
func adopt(result: FscParser.Result) -> void:
	_parsed = result
	_parsed_lines = lines() if writable else PackedStringArray()
	_parsed_version = version

## Parses again only the definitions the change touched. False when the
## whole file has to be read (too much changed, or no definition to hold on to).
func _reparse(fresh: PackedStringArray) -> bool:
	var old := _parsed_lines
	var definitions := _parsed.definitions
	if definitions.is_empty(): return false
	# The first and last lines that differ.
	var limit := mini(old.size(), fresh.size())
	var first := 0
	while first < limit and old[first] == fresh[first]: first += 1
	if first == old.size() and first == fresh.size(): return true
	var tail := 0
	while tail < limit - first and old[old.size() - 1 - tail] == fresh[fresh.size() - 1 - tail]: tail += 1
	var old_end := old.size() - tail  # first unchanged line index after the change, in the old text
	var delta := fresh.size() - old.size()
	if absi(delta) > 4000 or old_end - first > 4000: return false
	# From the definition before the one that holds the first changed line (a
	# changed header also changes where the one above ends) to the first
	# definition that starts after the change.
	var index := 0
	while index < definitions.size() and definitions[index].line - 1 < first: index += 1
	var keep := maxi(0, index - 2)
	var from: int = definitions[keep].line - 1 if index >= 2 else 0
	var after := index
	while after < definitions.size() and definitions[after].line - 1 < old_end: after += 1
	var until_old: int = definitions[after].line - 1 if after < definitions.size() else old.size()
	var until := until_old + delta
	# A problem further down may name a line in its words: those are read again whole.
	if delta != 0 and _parsed.diagnostics.any(func(item: Dictionary) -> bool: return int(item.line) > until_old): return false
	# Parse the part in between, at its own line numbers.
	var part := "\n".repeat(from) + "\n".join(fresh.slice(from, until))
	# The line break after the part's last line is not in it: nor is its carriage return.
	if until < fresh.size(): part = part.trim_suffix("\r")
	var region := FscParser.parse(part, path)
	partial_parses += 1
	var result := FscParser.Result.new()
	result.path = path
	for at in keep: result.definitions.append(definitions[at])
	result.definitions.append_array(region.definitions)
	for at in range(after, definitions.size()):
		if delta != 0: _shift(definitions[at], delta)
		result.definitions.append(definitions[at])
	for item: Dictionary in _parsed.diagnostics:
		var line := int(item.line)
		if line <= from: result.diagnostics.append(item)
	result.diagnostics.append_array(region.diagnostics)
	for item: Dictionary in _parsed.diagnostics:
		if int(item.line) > until_old: result.diagnostics.append(item)
	_parsed = result
	return true

## Moves a parsed definition down (or up) by a number of lines.
static func _shift(definition: FscParser.Definition, delta: int) -> void:
	definition.line += delta
	for line: FscParser.Line in definition.body: line.number += delta
	for name: String in definition.fields: (definition.fields[name] as FscParser.Field).line += delta
	_shift_nodes(definition.nodes, delta)
	_shift_nodes(definition.options, delta)

static func _shift_nodes(nodes: Array, delta: int) -> void:
	for node: Variant in nodes:
		if node is Dictionary:
			if node.has("line"): node.line += delta
			for key: Variant in node:
				var value: Variant = node[key]
				if value is Array: _shift_nodes(value, delta)
				elif value is Dictionary: _shift_nodes([value], delta)
		elif node is Array: _shift_nodes(node, delta)

## Everything a parse holds, as text: two parses of the same file read the same.
static func describe(result: FscParser.Result) -> String:
	var out: PackedStringArray = []
	for definition: FscParser.Definition in result.definitions:
		out.append("== %s %s %s @%d" % [definition.mode, definition.type, definition.id, definition.line])
		for line: FscParser.Line in definition.body: out.append("  %d/%d %s" % [line.number, line.indent, line.text])
		for name: String in definition.field_order:
			var field: FscParser.Field = definition.fields[name]
			out.append("  field %s=%s @%d [%s]" % [name, field.value, field.line, ",".join(field.children.map(func(line: FscParser.Line) -> String: return str(line.number)))])
		out.append("  nodes " + var_to_str(definition.nodes))
		out.append("  options " + var_to_str(definition.options))
	var problems: PackedStringArray = []
	for item: Dictionary in result.diagnostics: problems.append("! %06d %s %s" % [int(item.line), item.severity, item.message])
	problems.sort()
	out.append_array(problems)
	return "\n".join(out)

func definitions() -> Array[FscParser.Definition]:
	return parsed().definitions


var _lines_version := -1
var _line_cache: PackedStringArray
var _start_cache: Array[int] = []
var _range_version := -1
var _range_cache: Dictionary = {}
var _definition_lines: Array[int] = []

## The text's lines (a carriage return stays on its line). Do not change the
## array: take a copy with `lines().duplicate()` to edit.
func lines() -> PackedStringArray:
	if _lines_version != version:
		_line_cache = text.split("\n")
		_start_cache = [0]
		var at := 0
		for line: String in _line_cache:
			at += line.length() + 1
			_start_cache.append(at)
		_start_cache.pop_back()
		_lines_version = version
	return _line_cache


## Where each line starts in the text. Do not change the array.
func offsets() -> Array[int]:
	lines()
	return _start_cache


## The line (counted from 1) that holds the character at `offset`.
func line_at(offset: int) -> int:
	return offsets().bsearch(offset + 1, true)


func block_range(definition: FscParser.Definition) -> Vector2i:
	if _range_version != version:
		_range_cache.clear()
		_definition_lines.clear()
		for candidate: FscParser.Definition in definitions(): _definition_lines.append(candidate.line)
		_definition_lines.sort()
		_range_version = version
	if _range_cache.has(definition.line): return _range_cache[definition.line]
	var all := lines()
	var starts := _start_cache
	var first: int = definition.line - 1
	var begin := starts[first]
	var next := _definition_lines.bsearch(definition.line + 1, true)
	var tail: int = _definition_lines[next] - 2 if next < _definition_lines.size() else all.size() - 1
	# Comments immediately preceding the next definition belong to that
	# definition. Keep them outside this definition's editable range.
	while tail > first:
		var clean := all[tail].strip_edges()
		if not clean.is_empty() and not clean.begins_with("//"): break
		tail -= 1
	var block_end := starts[tail] + all[tail].length()
	if block_end < text.length() and block_end > begin and all[tail].ends_with("\r"):
		block_end -= 1
	var span := Vector2i(begin, block_end)
	_range_cache[definition.line] = span
	return span


func block(definition: FscParser.Definition) -> String:
	var span := block_range(definition)
	return text.substr(span.x, span.y - span.x)


func replace_block(definition: FscParser.Definition, value: String) -> void:
	var span := block_range(definition)
	change(text.left(span.x) + value + text.substr(span.y))


func field_value(definition: FscParser.Definition, name: String) -> String:
	if not definition.fields.has(name):
		return ""
	var field: FscParser.Field = definition.fields[name]
	var out := field.value
	for child in field.children:
		if not out.is_empty():
			out += "\n"
		out += " ".repeat(maxi(0, child.indent - 4)) + child.text
	return out


func set_field(definition: FscParser.Definition, name: String, value: String, force_block: bool = false) -> String:
	if not writable:
		return "Reference packs are read-only."
	var eol := "\r\n" if "\r\n" in text else "\n"
	value = value.replace("\r\n", "\n").replace("\r", "\n")
	var replacement := name + ":"
	if force_block and value.is_empty():
		pass
	elif force_block or "\n" in value:
		for line in value.split("\n"):
			replacement += eol + "    " + line
	elif not value.is_empty():
		replacement += " " + value
	if not definition.fields.has(name):
		var span := block_range(definition)
		# Scene metadata must precede the prose.
		if definition.type in FscParser.SCRIPT_TYPES:
			var header_end := text.find("\n", span.x)
			if header_end < 0:
				change(text + eol + replacement)
			else:
				change(text.left(header_end + 1) + replacement + eol + text.substr(header_end + 1))
		else:
			change(text.left(span.y) + eol + replacement + text.substr(span.y))
		return ""
	var field: FscParser.Field = definition.fields[name]
	var starts := offsets()
	var begin := starts[field.line - 1]
	var end_line := field.line
	if not field.children.is_empty():
		end_line = field.children[-1].number
	var end := starts[end_line] if end_line < starts.size() else text.length()
	var previous := text.substr(begin, end - begin)
	# Never erase comments nested inside a complex field through a form.
	for line in previous.split("\n"):
		if line.strip_edges().begins_with("//"):
			return "This field contains comments. Edit it in Source to preserve them."
	if previous.ends_with("\n"):
		replacement += eol
	change(text.left(begin) + replacement + text.substr(end))
	return ""


func remove_simple_field(definition: FscParser.Definition, name: String) -> String:
	if not writable: return "Reference packs are read-only."
	var field: FscParser.Field = definition.fields.get(name)
	if field == null: return ""
	if not field.children.is_empty(): return "This property has additional source lines and is preserved."
	var starts := offsets()
	var begin: int = starts[field.line - 1]
	var end: int = starts[field.line] if field.line < starts.size() else text.length()
	change(text.left(begin) + text.substr(end))
	return ""


func save() -> String:
	if not writable:
		return "Reference packs are read-only."
	if not dirty():
		return ""
	var exists_now := FileAccess.file_exists(path)
	if exists_now != existed_at_open or (exists_now and FileAccess.get_file_as_string(path) != original):
		return "File changed outside the editor. Save stopped: " + path
	# A sibling temporary file permits one atomic rename on the same volume.
	var temporary := path + ".mage-tmp-" + str(OS.get_process_id())
	if FileAccess.file_exists(temporary):
		return "A previous temporary file needs attention: " + temporary
	var file := FileAccess.open(temporary, FileAccess.WRITE)
	if file == null:
		return "Cannot write: " + temporary
	file.store_string(text)
	file.flush()
	var write_error := file.get_error()
	file.close()
	if write_error != OK:
		DirAccess.remove_absolute(temporary)
		return "Could not finish writing: " + path
	var err := DirAccess.rename_absolute(temporary, path)
	if err != OK:
		DirAccess.remove_absolute(temporary)
		return "Could not replace: " + path
	original = text
	existed_at_open = true
	_dirty_version = -1
	return ""
