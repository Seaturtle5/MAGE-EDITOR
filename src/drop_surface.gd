class_name DropSurface
extends GraphEdit

signal content_dropped(data: Dictionary, position: Vector2)
var workspace: PackWorkspace

func _can_drop_data(_position: Vector2, data: Variant) -> bool:
	return workspace != null and not DragPayload.resolve(workspace, data).is_empty()

func _drop_data(position: Vector2, data: Variant) -> void:
	if _can_drop_data(position, data): content_dropped.emit(data, position)
