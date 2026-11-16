class_name BlockTarget
extends VBoxContainer

signal received(data: Dictionary)
var path := ""
var snapshot := ""

func _can_drop_data(_position: Vector2, data: Variant) -> bool:
	return data is Dictionary and data.get("mage_kind") == "block" and data.get("path") == path and data.get("snapshot") == snapshot

func _drop_data(position: Vector2, data: Variant) -> void:
	if _can_drop_data(position, data): received.emit(data)
