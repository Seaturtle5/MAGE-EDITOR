class_name ContentLibrary
extends Tree

func _get_drag_data(at_position: Vector2) -> Variant:
	var item := get_item_at_position(at_position)
	if item == null: return null
	var row: Variant = item.get_metadata(0)
	if not row is Dictionary or not row.has("def") or row.def.type == "file": return null
	var preview := Label.new()
	preview.text = Wording.icon(row.def.type) + " " + Wording.title(row)
	set_drag_preview(preview)
	return DragPayload.content(row)
