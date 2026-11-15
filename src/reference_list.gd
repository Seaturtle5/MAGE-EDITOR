class_name ReferenceList
extends ItemList

func _get_drag_data(at_position: Vector2) -> Variant:
	var index := get_item_at_position(at_position, true)
	if index < 0:
		return null
	var data: Dictionary = get_item_metadata(index)
	var preview := Label.new()
	preview.text = data.get("id", "")
	set_drag_preview(preview)
	return {"mage_reference": data.get("id", "")}
