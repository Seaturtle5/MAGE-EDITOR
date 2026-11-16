class_name ConditionBuilder
extends VBoxContainer
## A condition as groups of sentences: all of, any of, none of. Sentences come
## from the block catalog; the engine checks the finished condition.

signal changed
var workspace: PackWorkspace
var root: Dictionary = {"op": "all", "items": []}
var context: Array = []
var event := ""
var chooser: BlockChooser
var adding_to: Dictionary = {}
var replacing: Dictionary = {}
const GROUPS := [["all", "All of these are true"], ["any", "Any one of these is true"], ["none", "None of these is true"]]

func configure(pack: PackWorkspace, text: String = "", where: Array = [], about_event: String = "") -> void:
	workspace = pack
	context = where
	event = about_event
	root = _group(BlockCatalog.condition_tree(text)) if not text.strip_edges().is_empty() else {"op": "all", "items": []}
	if chooser == null:
		chooser = BlockChooser.new()
		add_child(chooser)
		chooser.chosen.connect(_chosen)
	rebuild()

static func _group(tree: Dictionary) -> Dictionary:
	var item := _item(tree)
	return item if item.op in ["all", "any", "none"] else {"op": "all", "items": [item]}

static func _item(tree: Dictionary) -> Dictionary:
	match str(tree.op):
		"all", "any": return {"op": tree.op, "items": tree.items.map(func(child: Dictionary) -> Dictionary: return _item(child))}
		"not":
			var inner := _item(tree.item)
			return {"op": "none", "items": inner.items} if inner.op == "any" else {"op": "none", "items": [inner]}
	return {"op": tree.op, "text": tree.text}

static func _tree(item: Dictionary) -> Dictionary:
	if item.op in ["is", "kept"]: return {"op": "is", "text": item.text}
	var parts: Array = []
	for child: Dictionary in item.items:
		if child.op in ["is", "kept"] or not child.items.is_empty(): parts.append(_tree(child))
	if item.op == "none": return {"op": "not", "item": parts[0] if parts.size() == 1 else {"op": "any", "items": parts}} if not parts.is_empty() else {"op": "is", "text": ""}
	if parts.size() == 1: return parts[0]
	return {"op": item.op, "items": parts} if not parts.is_empty() else {"op": "is", "text": ""}

## The finished condition; empty while nothing has been added.
func line() -> String:
	return BlockCatalog.condition_text(_flat(_tree(root)))

## Joins a group into its parent when both are the same kind.
static func _flat(tree: Dictionary) -> Dictionary:
	if tree.op == "not": return {"op": "not", "item": _flat(tree.item)}
	if tree.op not in ["all", "any"]: return tree
	var items: Array = []
	for child: Dictionary in tree.items:
		var flat := _flat(child)
		if flat.op == tree.op: items.append_array(flat.items)
		else: items.append(flat)
	return {"op": tree.op, "items": items}

func is_empty() -> bool:
	return line().is_empty()

func rebuild() -> void:
	for child: Node in get_children():
		if child == chooser: continue
		remove_child(child)
		child.queue_free()
	add_child(_group_panel(root, {}))

func _group_panel(group: Dictionary, parent: Dictionary) -> Control:
	var panel := DropPanel.new()
	panel.theme_type_variation = "Card"
	panel.accepts = func(data: Dictionary) -> bool: return data.get("mage_kind") == "condition" and data.get("builder") == get_instance_id() and not _inside(data.item, group) and not is_same(data.item, group) and not is_same(data.parent, group)
	panel.dropped.connect(func(data: Dictionary, _upper: bool) -> void:
		_take(data.parent, data.item)
		group.items.append(data.item)
		_changed())
	var body := VBoxContainer.new()
	panel.add_child(body)
	var head := HBoxContainer.new()
	body.add_child(head)
	var mode := OptionButton.new()
	for pair: Array in GROUPS: mode.add_item(pair[1])
	mode.select(["all", "any", "none"].find(group.op))
	mode.item_selected.connect(func(index: int) -> void:
		group.op = GROUPS[index][0]
		_changed())
	head.add_child(mode)
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(spacer)
	if not parent.is_empty():
		var remove := Button.new()
		remove.text = "✕"
		remove.theme_type_variation = "Ghost"
		remove.tooltip_text = "Remove this group"
		remove.pressed.connect(func() -> void:
			_take(parent, group)
			_changed())
		head.add_child(remove)
	if group.items.is_empty(): body.add_child(AuthoringLayout.label("Nothing here yet. Add a condition below.", 13, true))
	for item: Dictionary in group.items:
		if item.op in ["all", "any", "none"]:
			var nested := MarginContainer.new()
			nested.add_theme_constant_override("margin_left", 14)
			nested.add_child(_group_panel(item, group))
			body.add_child(nested)
			continue
		body.add_child(_row(item, group))
	var tools := HBoxContainer.new()
	body.add_child(tools)
	var add := Button.new()
	add.text = "+ Condition"
	add.theme_type_variation = "AddRow"
	add.pressed.connect(add_to.bind(group))
	tools.add_child(add)
	var nest := Button.new()
	nest.text = "+ Group"
	nest.theme_type_variation = "AddRow"
	nest.tooltip_text = "Add a group inside this one, for example “any of” inside “all of”."
	nest.pressed.connect(func() -> void:
		group.items.append({"op": "any" if group.op == "all" else "all", "items": []})
		_changed())
	tools.add_child(nest)
	return panel

func _row(item: Dictionary, group: Dictionary) -> Control:
	var row := HBoxContainer.new()
	var handle := BlockHandle.new()
	handle.text = "⠿"
	handle.tooltip_text = "Drag into another group"
	handle.payload = {"mage_kind": "condition", "builder": get_instance_id(), "item": item, "parent": group}
	row.add_child(handle)
	var read := BlockCatalog.read_predicate(item.text)
	if read.is_empty():
		var kept := AuthoringLayout.label("Kept as written: " + str(item.text), 14, true)
		kept.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(kept)
	else:
		var view := SentenceView.new()
		view.event = event
		view.show_sentence(workspace, read.entry, read.slots)
		view.slot_changed.connect(func(name: String, value: String) -> void:
			var slots: Dictionary = read.slots.duplicate()
			slots[name] = value
			var next := BlockCatalog.render(read.entry, slots)
			if Condition.compile(next).has("error"): return
			item.text = next
			_changed())
		row.add_child(view)
		var edit := Button.new()
		edit.text = "✎"
		edit.theme_type_variation = "Ghost"
		edit.tooltip_text = "Change every part of this condition"
		edit.pressed.connect(func() -> void:
			replacing = item
			adding_to = {}
			chooser.open(workspace, "condition", context, [], read, event))
		row.add_child(edit)
	var remove := Button.new()
	remove.text = "✕"
	remove.theme_type_variation = "Ghost"
	remove.tooltip_text = "Remove this condition"
	remove.pressed.connect(func() -> void:
		_take(group, item)
		_changed())
	row.add_child(remove)
	return row

static func _take(group: Dictionary, item: Dictionary) -> void:
	for index in group.items.size():
		if is_same(group.items[index], item):
			group.items.remove_at(index)
			return

static func _inside(ancestor: Dictionary, group: Dictionary) -> bool:
	if not ancestor.has("items"): return false
	for child: Dictionary in ancestor.items:
		if is_same(child, group) or _inside(child, group): return true
	return false

func add_to(group: Dictionary) -> void:
	adding_to = group
	replacing = {}
	chooser.open(workspace, "condition", context, [], {}, event)

## Adds a condition written in the content format to a group (the outer one by default).
func add_text(text: String, group: Dictionary = {}) -> String:
	if Condition.compile(text).has("error"): return "The engine cannot read this condition."
	var target: Dictionary = group if not group.is_empty() else root
	var item := _item(BlockCatalog.condition_tree(text))
	if item.op == target.op and item.has("items"): target.items.append_array(item.items)
	else: target.items.append(item)
	_changed()
	return ""

func _chosen(text: String, _keep_open: bool) -> void:
	if not replacing.is_empty():
		replacing.text = " ".join(Condition._words(text))
		replacing = {}
		_changed()
	else: add_text(text, adding_to)

func _changed() -> void:
	rebuild()
	changed.emit()
