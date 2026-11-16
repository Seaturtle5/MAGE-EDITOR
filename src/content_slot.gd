class_name ContentSlot
extends OptionButton
## Every drag target also has an ordinary keyboard accessible picker.

var workspace: PackWorkspace
var kind := ""

func configure(value: PackWorkspace, type: String) -> void:
	workspace = value
	kind = type
	clear()
	add_item("Choose a " + Wording.name(type) + "…")
	set_item_metadata(0, "")
	for row: Dictionary in workspace.rows:
		if row.def.type != kind or row.def.mode == "extend": continue
		add_item(Wording.title(row) + (" · " + row.pack if not row.doc.writable else ""))
		set_item_metadata(item_count - 1, row.def.id)
	tooltip_text = "Choose from the list, or drop a " + Wording.name(kind) + " from the library."

func value() -> String:
	return str(get_item_metadata(selected)) if selected >= 0 else ""

func _can_drop_data(_position: Vector2, data: Variant) -> bool:
	return not DragPayload.resolve(workspace, data).is_empty() and data.get("type") == kind

func _drop_data(_position: Vector2, data: Variant) -> void:
	if not _can_drop_data(_position, data): return
	for index in item_count:
		if get_item_metadata(index) == data.id:
			select(index)
			item_selected.emit(index)
			break
