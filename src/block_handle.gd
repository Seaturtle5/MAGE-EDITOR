class_name BlockHandle
extends IconButton
## The grip of a block: drag it to move the block, with Ctrl to copy.

var payload: Dictionary = {}

func _get_drag_data(_position: Vector2) -> Variant:
	if disabled: return null
	var preview := Label.new()
	preview.text = "Move story block"
	set_drag_preview(preview)
	var data := payload.duplicate()
	data.copy = Input.is_key_pressed(KEY_CTRL)
	return data
