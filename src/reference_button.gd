class_name ReferenceButton
extends Button

signal content_dropped(data: Dictionary)
var workspace: PackWorkspace
var kinds: Array = []

func _can_drop_data(_position: Vector2, data: Variant) -> bool:
	return not disabled and workspace != null and not DragPayload.resolve(workspace, data).is_empty() and data.get("type") in kinds

func _drop_data(position: Vector2, data: Variant) -> void:
	if _can_drop_data(position, data): content_dropped.emit(data)
