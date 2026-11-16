class_name IconButton
extends Label
## A small symbol that can be pressed. Much lighter to build than a Button,
## which matters where every block of a long story has several.

signal pressed
var disabled := false:
	set(value):
		disabled = value
		modulate.a = 0.35 if disabled else 1.0
		mouse_default_cursor_shape = Control.CURSOR_ARROW if disabled else Control.CURSOR_POINTING_HAND

func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	custom_minimum_size = Vector2(26, 26)
	theme_type_variation = "MutedLabel"

func _gui_input(event: InputEvent) -> void:
	if disabled or not event is InputEventMouseButton or event.button_index != MOUSE_BUTTON_LEFT: return
	if event.pressed: accept_event()
	elif Rect2(Vector2.ZERO, size).has_point(event.position) and not get_viewport().gui_is_dragging():
		accept_event()
		pressed.emit()

func _notification(what: int) -> void:
	if what == NOTIFICATION_MOUSE_ENTER and not disabled: theme_type_variation = "AccentLabel"
	elif what == NOTIFICATION_MOUSE_EXIT: theme_type_variation = "MutedLabel"
