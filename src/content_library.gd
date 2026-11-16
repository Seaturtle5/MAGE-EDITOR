class_name ContentLibrary
extends Tree
## The library: choose an entry to open it, or drag it somewhere. Pressing
## the pointer on an entry does not open it yet, so a drag can start from
## what is on screen; it opens when the pointer is let go in place.

signal open_requested
var pressed_at := Vector2(-1, -1)

func _ready() -> void:
	item_activated.connect(func() -> void: open_requested.emit())

func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed: pressed_at = event.position
		elif pressed_at.x >= 0:
			var still: bool = pressed_at.distance_to(event.position) < 8 and not get_viewport().gui_is_dragging()
			pressed_at = Vector2(-1, -1)
			if still and get_selected() != null and get_item_at_position(event.position) == get_selected(): open_requested.emit()

func _get_drag_data(at_position: Vector2) -> Variant:
	var item := get_item_at_position(at_position)
	if item == null: return null
	var row: Variant = item.get_metadata(0)
	if not row is Dictionary or not row.has("def") or row.def.type == "file": return null
	pressed_at = Vector2(-1, -1)
	var preview := Label.new()
	preview.text = Wording.icon(row.def.type) + " " + Wording.title(row)
	set_drag_preview(preview)
	return DragPayload.content(row)
