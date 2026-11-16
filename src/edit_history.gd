class_name EditHistory
extends RefCounted
## Text snapshots share document objects so saving does not reset undo.

signal changed
var steps: Array[Dictionary] = []
var cursor := 0
var baseline: Dictionary = {}
var depth := 0
var applying := false
var label := ""

func capture(documents: Dictionary) -> Dictionary:
	var result: Dictionary = {}
	for path: String in documents:
		var doc: PackDocument = documents[path]
		if doc.writable:
			result[path] = {"doc": doc, "text": doc.text}
	return result

func reset(documents: Dictionary) -> void:
	steps.clear()
	cursor = 0
	baseline = capture(documents)
	changed.emit()

func checkpoint(documents: Dictionary, description: String = "") -> void:
	if applying or depth > 0: return
	var after := capture(documents)
	if same(baseline, after): return
	steps.resize(cursor)
	var title := description if not description.is_empty() else "Edit content"
	steps.append({"label": title, "before": baseline, "after": after})
	cursor += 1
	baseline = after
	changed.emit()

func same(a: Dictionary, b: Dictionary) -> bool:
	if a.size() != b.size(): return false
	for path: String in a:
		if not b.has(path) or a[path].text != b[path].text: return false
	return true

func restore(documents: Dictionary, snapshot: Dictionary) -> void:
	for path: String in documents.keys():
		var doc: PackDocument = documents[path]
		if not doc.writable or snapshot.has(path): continue
		if doc.existed_at_open:
			# Undo after Save empties the created file on the next explicit Save.
			# Never remove a file that may now belong to another application.
			doc.text = ""
		else:
			documents.erase(path)
	for path: String in snapshot:
		var entry: Dictionary = snapshot[path]
		documents[path] = entry.doc
		entry.doc.text = entry.text
	baseline = capture(documents)

func undo(documents: Dictionary) -> String:
	if cursor == 0: return ""
	cursor -= 1
	var step: Dictionary = steps[cursor]
	restore(documents, step.before)
	changed.emit()
	return step.label

func redo(documents: Dictionary) -> String:
	if cursor >= steps.size(): return ""
	var step: Dictionary = steps[cursor]
	cursor += 1
	restore(documents, step.after)
	changed.emit()
	return step.label
