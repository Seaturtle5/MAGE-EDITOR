class_name PackDocument
extends RefCounted
## Keep original bytes outside the exact range an author changes.

signal changed(before: String)

var path: String
var original: String
var text: String
var writable: bool
var existed_at_open: bool


func _init(file_path: String, can_write: bool) -> void:
	path = file_path
	writable = can_write
	existed_at_open = FileAccess.file_exists(path)
	original = FileAccess.get_file_as_string(path) if existed_at_open else ""
	text = original


func change(value: String) -> void:
	if not writable or value == text:
		return
	var before := text
	text = value
	changed.emit(before)


func dirty() -> bool:
	return original != text


var _parsed_text := ""
var _parsed: FscParser.Result

## The file as the engine's parser reads it. Parsed again only after a change.
func parsed() -> FscParser.Result:
	if _parsed == null or _parsed_text != text:
		_parsed = FscParser.parse(text, path)
		_parsed_text = text
	return _parsed

func definitions() -> Array[FscParser.Definition]:
	return parsed().definitions


func offsets() -> Array[int]:
	var result: Array[int] = [0]
	for i in text.length():
		if text[i] == "\n":
			result.append(i + 1)
	return result


func block_range(definition: FscParser.Definition) -> Vector2i:
	var starts := offsets()
	var begin := starts[definition.line - 1]
	var end := text.length()
	for candidate in definitions():
		if candidate.line > definition.line:
			end = starts[candidate.line - 1]
			break
	# Comments immediately preceding the next definition belong to that
	# definition. Keep them outside this definition's editable range.
	var lines := text.substr(begin, end - begin).split("\n")
	var tail := lines.size() - 1
	while tail > 0 and (lines[tail].strip_edges().is_empty() or lines[tail].strip_edges().begins_with("//")):
		tail -= 1
	var kept := "\n".join(lines.slice(0, tail + 1))
	var block_end := begin + kept.length()
	if block_end < text.length() and block_end > begin and text[block_end] == "\n" and text[block_end - 1] == "\r":
		block_end -= 1
	return Vector2i(begin, block_end)


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
	return ""
