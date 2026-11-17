class_name VariantSheets
extends VBoxContainer
## A creature's variants (the shapes it is met in, such as a female and a
## male one): each with its name and a sheet of its own settings.

signal edited(text: String)

var workspace: PackWorkspace
var writable := true
var context: Array = []
var _variants: Array[Dictionary] = []

## The field as [{name, entries: [{name, value}]}]; `ok` is false when it is
## written another way (notes between the lines, deeper levels), which is
## then left alone.
static func read(doc: PackDocument, field: FscParser.Field) -> Dictionary:
	var variants: Array[Dictionary] = []
	if field == null: return {"ok": true, "variants": variants}
	if not field.value.is_empty(): return {"ok": false, "variants": variants}
	var lines := doc.lines()
	if not field.children.is_empty():
		for index in range(field.line, field.children[-1].number):
			if index < lines.size() and lines[index].strip_edges().begins_with("//"): return {"ok": false, "variants": variants}
	for child: FscParser.Line in field.children:
		if child.is_blank(): continue
		var separator := child.text.find(":")
		if separator < 1: return {"ok": false, "variants": variants}
		var name := child.text.left(separator).strip_edges()
		var value := child.text.substr(separator + 1).strip_edges()
		if child.indent == 4 and value.is_empty(): variants.append({"name": name, "entries": []})
		elif child.indent == 8 and not variants.is_empty(): variants[-1].entries.append({"name": name, "value": value})
		else: return {"ok": false, "variants": variants}
	return {"ok": true, "variants": variants}

func configure(pack: PackWorkspace, variants: Array[Dictionary], can_write: bool, where: Array = []) -> void:
	workspace = pack
	writable = can_write
	context = where
	_variants = variants.duplicate(true)
	_build()

func count() -> int:
	return _variants.size()

func names() -> Array:
	return _variants.map(func(variant: Dictionary) -> String: return variant.name)

func text() -> String:
	var lines: Array[String] = []
	for variant: Dictionary in _variants:
		lines.append(str(variant.name) + ":")
		for entry: Dictionary in variant.entries: lines.append("    %s: %s" % [entry.name, entry.value])
	return "\n".join(lines)

func rename(index: int, name: String) -> void:
	name = name.strip_edges().to_lower().replace(" ", "_")
	if index < 0 or index >= _variants.size() or name == _variants[index].name or not name.is_valid_identifier() or name in names(): return
	_variants[index].name = name
	edited.emit(text())

func add(name: String = "") -> void:
	var number := _variants.size() + 1
	if name.is_empty(): name = "variant_%d" % number
	while name in names():
		number += 1
		name = "variant_%d" % number
	_variants.append({"name": name, "entries": [{"name": "gender", "value": "female" if "female" not in _variants.map(func(variant: Dictionary) -> String: return _setting(variant, "gender")) else "male"}]})
	edited.emit(text())

func remove(index: int) -> void:
	if index < 0 or index >= _variants.size(): return
	_variants.remove_at(index)
	edited.emit(text())

## Sets one setting of one variant from its sheet's lines.
func set_lines(index: int, lines: String) -> void:
	if index < 0 or index >= _variants.size(): return
	var entries: Array = []
	for line: String in lines.split("\n", false):
		var separator := line.find(":")
		if separator > 0: entries.append({"name": line.left(separator).strip_edges(), "value": line.substr(separator + 1).strip_edges()})
	_variants[index].entries = entries
	edited.emit(text())

static func _setting(variant: Dictionary, name: String) -> String:
	for entry: Dictionary in variant.entries:
		if entry.name == name: return entry.value
	return ""

func _build() -> void:
	for child: Node in get_children(): child.queue_free()
	add_theme_constant_override("separation", 8)
	if _variants.is_empty(): add_child(AuthoringLayout.label("One shape only. Add variants to meet it as, say, a female and a male one.", 14, true))
	for index in _variants.size():
		var variant: Dictionary = _variants[index]
		var head := HBoxContainer.new()
		head.add_theme_constant_override("separation", 8)
		head.set_meta("variant", index)
		var symbol := Label.new()
		symbol.text = "◈"
		head.add_child(symbol)
		var name := LineEdit.new()
		name.text = variant.name
		name.editable = writable
		name.custom_minimum_size.x = 180
		name.tooltip_text = "The variant's name: one word. Stories name it to meet this shape."
		var keep := func() -> void:
			if is_instance_valid(name) and name.editable:
				rename(index, name.text)
				if is_instance_valid(name): name.text = _variants[index].name if index < _variants.size() else name.text
		name.text_submitted.connect(func(_text: String) -> void: keep.call())
		name.focus_exited.connect(keep)
		head.add_child(name)
		if writable:
			var take := IconButton.new()
			take.text = "×"
			take.tooltip_text = "Remove this variant"
			take.pressed.connect(remove.bind(index))
			head.add_child(take)
		add_child(head)
		var sheet := SettingsSheet.new()
		var entries: Array[Dictionary] = []
		entries.assign(variant.entries)
		sheet.configure(workspace, "creature", "variant", entries, writable, context)
		sheet.edited.connect(func(lines: String) -> void: set_lines(index, lines))
		var inset := MarginContainer.new()
		inset.add_theme_constant_override("margin_left", 22)
		inset.add_child(sheet)
		add_child(inset)
	if writable:
		var more := Button.new()
		more.text = "+ Add a variant"
		more.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
		more.pressed.connect(func() -> void: add())
		add_child(more)
