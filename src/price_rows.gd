class_name PriceRows
extends VBoxContainer
## What a shop sells or buys: "item: price" lines, optionally "[if condition]".
## Items can be chosen from a list or dropped in from the library.

signal edited(text: String)

var workspace: PackWorkspace
var writable := true
var context: Array = []
var _rows: Array[Dictionary] = []
var _dialog: ConditionDialog
var _target := -1

## The field's lines as {item, price, condition}; `ok` is false when a line is
## written another way, which is then left alone.
static func read(doc: PackDocument, field: FscParser.Field) -> Dictionary:
	var entries: Array[Dictionary] = []
	if field == null: return {"ok": true, "entries": entries}
	if not field.value.is_empty(): return {"ok": false, "entries": entries}
	var lines := doc.text.split("\n")
	if not field.children.is_empty():
		for index in range(field.line, field.children[-1].number):
			if index < lines.size() and lines[index].strip_edges().begins_with("//"): return {"ok": false, "entries": entries}
	var pattern := RegEx.create_from_string("^(\\w+)\\s*:\\s*(\\d+)(?:\\s*\\[if (.+)\\])?$")
	for child: FscParser.Line in field.children:
		if child.is_blank(): continue
		var found := pattern.search(child.text.strip_edges())
		if child.indent != 4 or found == null: return {"ok": false, "entries": entries}
		if not found.get_string(3).is_empty() and Condition.compile(found.get_string(3)).has("error"): return {"ok": false, "entries": entries}
		entries.append({"item": found.get_string(1), "price": int(found.get_string(2)), "condition": found.get_string(3)})
	return {"ok": true, "entries": entries}

func configure(pack: PackWorkspace, entries: Array[Dictionary], can_write: bool, where: Array = []) -> void:
	workspace = pack
	writable = can_write
	context = where
	_rows = entries.duplicate(true)
	_build()

func text() -> String:
	var lines: Array[String] = []
	for row: Dictionary in _rows:
		lines.append("%s: %d%s" % [row.item, int(row.price), " [if %s]" % row.condition if not str(row.condition).is_empty() else ""])
	return "\n".join(lines)

func count() -> int:
	return _rows.size()

func has_item(id: String) -> bool:
	return _rows.any(func(row: Dictionary) -> bool: return row.item == id)

## Adds an item at a price; an item that is listed already is left as it is.
func add(id: String, price: int = 1) -> bool:
	if id.is_empty() or has_item(id): return false
	_rows.append({"item": id, "price": price, "condition": ""})
	edited.emit(text())
	return true

func set_price(index: int, price: int) -> void:
	if index < 0 or index >= _rows.size() or int(_rows[index].price) == price: return
	_rows[index].price = maxi(price, 0)
	edited.emit(text())

func set_item(index: int, id: String) -> void:
	if index < 0 or index >= _rows.size() or id.is_empty() or _rows[index].item == id or has_item(id): return
	_rows[index].item = id
	edited.emit(text())

func set_condition(index: int, condition: String) -> void:
	if index < 0 or index >= _rows.size() or _rows[index].condition == condition: return
	if not condition.is_empty():
		if Condition.compile(condition).has("error"): return
		workspace.require_condition(Condition.compile(condition))
	_rows[index].condition = condition
	edited.emit(text())

func remove(index: int) -> void:
	if index < 0 or index >= _rows.size(): return
	_rows.remove_at(index)
	edited.emit(text())

func _can_drop_data(_position: Vector2, data: Variant) -> bool:
	return writable and data is Dictionary and data.get("type") == "item" and not DragPayload.resolve(workspace, data).is_empty() and not has_item(str(data.get("id", "")))

func _drop_data(_position: Vector2, data: Variant) -> void:
	add(str(data.id))

func _ask(index: int) -> void:
	if _dialog == null:
		_dialog = ConditionDialog.new()
		add_child(_dialog)
		_dialog.applied.connect(func(condition: String) -> void: set_condition(_target, condition))
	_target = index
	_dialog.open(workspace, str(_rows[index].condition), context, "", "Offered only if…", true)

func _item_picker(value: String) -> SlotControl:
	return SlotControl.make(workspace, {"name": "item", "kind": "item", "optional": false}, value)

func _build() -> void:
	for child: Node in get_children():
		if child != _dialog: child.queue_free()
	add_theme_constant_override("separation", 6)
	mouse_filter = Control.MOUSE_FILTER_PASS
	if _rows.is_empty(): add_child(AuthoringLayout.label("Nothing yet." + (" Add an item, or drop one here from the library." if writable else ""), 14, true))
	for index in _rows.size():
		var row: Dictionary = _rows[index]
		var line := HBoxContainer.new()
		line.add_theme_constant_override("separation", 8)
		line.set_meta("row", index)
		var item := _item_picker(row.item)
		item.edited.connect(func() -> void: set_item(index, item.value()))
		line.add_child(item)
		line.add_child(AuthoringLayout.label("for", 14, true))
		var price := SpinBox.new()
		price.min_value = 0
		price.max_value = 1000000
		price.set_value_no_signal(int(row.price))
		price.editable = writable
		price.tooltip_text = "The price, in what the shop trades in."
		price.value_changed.connect(func(next: float) -> void: set_price(index, int(next)))
		line.add_child(price)
		var only := AuthoringLayout.label("only if " + BlockCatalog.condition_sentence(row.condition, workspace) if not str(row.condition).is_empty() else "", 14)
		only.theme_type_variation = "AccentLabel"
		only.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		line.add_child(only)
		if writable:
			var when := Button.new()
			when.text = "Only if…"
			when.tooltip_text = "Offer it only while a condition holds."
			when.pressed.connect(_ask.bind(index))
			line.add_child(when)
			var take := IconButton.new()
			take.text = "×"
			take.tooltip_text = "Take it off the list"
			take.pressed.connect(remove.bind(index))
			line.add_child(take)
		else:
			for button: Node in item.find_children("*", "BaseButton", true, false): (button as BaseButton).disabled = true
		add_child(line)
	if writable:
		var more := _item_picker("")
		more.picker.placeholder = "+ Add an item…"
		more.picker.text = more.picker.placeholder
		more.edited.connect(func() -> void: add(more.value()))
		add_child(more)
