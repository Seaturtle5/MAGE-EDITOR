class_name DragPayload
extends RefCounted

static func content(row: Dictionary) -> Dictionary:
	return {"mage_kind": "content", "mage_reference": row.def.id, "type": row.def.type, "id": row.def.id, "path": row.doc.path, "mode": row.def.mode, "ordinal": row.get("ordinal", 0), "title": Wording.title(row)}

static func resolve(workspace: PackWorkspace, data: Variant) -> Dictionary:
	if not data is Dictionary or data.get("mage_kind") != "content": return {}
	return workspace.find_row(data.get("path", ""), data.get("type", ""), data.get("id", ""), data.get("mode", "define"), data.get("ordinal", 0))
