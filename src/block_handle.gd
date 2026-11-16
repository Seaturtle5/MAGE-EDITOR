class_name BlockHandle
extends Button

var payload: Dictionary = {}

func _get_drag_data(_position: Vector2) -> Variant:
	var preview := Label.new()
	preview.text = "Move story block"
	set_drag_preview(preview)
	var data := payload.duplicate()
	data.copy = Input.is_key_pressed(KEY_CTRL)
	return data
