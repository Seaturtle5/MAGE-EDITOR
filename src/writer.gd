class_name StoryWriter
extends CodeEdit

func _can_drop_data(_position: Vector2, data: Variant) -> bool:
	return editable and data is Dictionary and data.has("mage_reference")

func _drop_data(position: Vector2, data: Variant) -> void:
	var location := get_line_column_at_pos(position, true)
	set_caret_line(location.y)
	set_caret_column(location.x)
	insert_text_at_caret(str(data.mage_reference))
	grab_focus()
