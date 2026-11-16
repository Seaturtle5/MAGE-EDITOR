class_name DropPanel
extends PanelContainer
## A panel that takes drags it is asked to accept, and shows where they land.

signal dropped(data: Dictionary, upper_half: bool)
## func(data) -> bool
var accepts: Callable
var hovering := false
var hover_upper := true
var split := false

func _can_drop_data(position: Vector2, data: Variant) -> bool:
	var fine: bool = data is Dictionary and accepts.is_valid() and accepts.call(data)
	if fine:
		hovering = true
		hover_upper = not split or position.y < size.y / 2
		queue_redraw()
	return fine

func _drop_data(position: Vector2, data: Variant) -> void:
	hovering = false
	queue_redraw()
	dropped.emit(data, not split or position.y < size.y / 2)

func _notification(what: int) -> void:
	if what == NOTIFICATION_DRAG_END or what == NOTIFICATION_MOUSE_EXIT:
		if hovering:
			hovering = false
			queue_redraw()

func _draw() -> void:
	if not hovering: return
	var y := 0.0 if hover_upper else size.y
	draw_line(Vector2(0, y), Vector2(size.x, y), EditorTheme.color("info"), 3.0)
