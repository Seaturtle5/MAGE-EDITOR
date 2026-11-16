class_name ConditionBuilder
extends VBoxContainer
## Groups compose sentences; the engine checks the resulting condition.

var workspace: PackWorkspace
var mode: OptionButton
var controls: VBoxContainer
var children_group: VBoxContainer
var slots: Dictionary = {}

func configure(value: PackWorkspace) -> void:
	workspace = value
	mode = OptionButton.new()
	for name: String in ["Counter", "Something remembered", "Carried item", "Quest stage", "Player sex", "Chance", "All of", "Any of", "None of"]: mode.add_item(name)
	add_child(mode)
	controls = VBoxContainer.new()
	add_child(controls)
	mode.item_selected.connect(func(_index: int) -> void: _rebuild())
	_rebuild()

func _picker(key: String, options: Array) -> OptionButton:
	var picker := OptionButton.new()
	for option: String in options: picker.add_item(option)
	controls.add_child(picker)
	slots[key] = picker
	return picker

func _rebuild() -> void:
	for child: Node in controls.get_children():
		controls.remove_child(child)
		child.queue_free()
	slots.clear()
	var kind := mode.get_item_text(mode.selected)
	if kind in ["All of", "Any of", "None of"]:
		children_group = VBoxContainer.new()
		controls.add_child(children_group)
		var add := Button.new()
		add.text = "+ Condition in this group"
		add.pressed.connect(_add_child_condition)
		controls.add_child(add)
		_add_child_condition()
		return
	if kind in ["Counter", "Something remembered"]:
		var values: Array = []
		var declarations := workspace.preview_content().values
		for key: String in declarations:
			if declarations[key].kind == ("number" if kind == "Counter" else "flag"): values.append(key)
		if kind == "Counter":
			for key: String in Game.PLAYER_DEFAULTS:
				if Game.PLAYER_DEFAULTS[key] is int: values.append("player." + key)
		values.sort()
		_picker("value", values)
		if kind == "Counter":
			_picker("compare", ["at least", "at most", "equal to", "more than", "less than", "different from"])
			var amount := SpinBox.new()
			amount.min_value = -100000
			amount.max_value = 100000
			amount.value = 3
			controls.add_child(amount)
			slots.amount = amount
		else: _picker("state", ["yes", "no"])
	elif kind in ["Carried item", "Quest stage"]:
		var slot := ContentSlot.new()
		slot.configure(workspace, "item" if kind == "Carried item" else "quest")
		controls.add_child(slot)
		slots.content = slot
		if kind == "Quest stage":
			_picker("stage", [])
			slot.item_selected.connect(func(_index: int) -> void:
				slots.stage.clear()
				for stage: String in workspace.preview_content().quests.get(slot.value(), {}).get("stages", []): slots.stage.add_item(stage))
	elif kind == "Player sex": _picker("sex", ["female", "male", "herm", "neuter"])
	elif kind == "Chance":
		var chance := SpinBox.new()
		chance.min_value = 0
		chance.max_value = 100
		chance.value = 50
		chance.suffix = "%"
		controls.add_child(chance)
		slots.chance = chance

func _add_child_condition() -> void:
	var row := VBoxContainer.new()
	children_group.add_child(row)
	var condition := ConditionBuilder.new()
	condition.configure(workspace)
	row.add_child(condition)
	var remove := Button.new()
	remove.text = "Remove this condition"
	remove.pressed.connect(func() -> void:
		children_group.remove_child(row)
		row.queue_free())
	row.add_child(remove)

func _value(key: String) -> String:
	var picker: OptionButton = slots[key]
	return picker.get_item_text(picker.selected) if picker.selected >= 0 else ""

func line() -> String:
	var kind := mode.get_item_text(mode.selected)
	match kind:
		"Counter": return _value("value") + " " + {"at least": ">=", "at most": "<=", "equal to": "=", "more than": ">", "less than": "<", "different from": "!="}[_value("compare")] + " " + str(int(slots.amount.value))
		"Something remembered": return ("not " if _value("state") == "no" else "") + _value("value")
		"Carried item": return "player has " + slots.content.value()
		"Quest stage": return "quest " + slots.content.value() + " is " + _value("stage")
		"Player sex": return "player is " + _value("sex")
		"Chance": return "chance " + str(int(slots.chance.value)) + "%"
		_:
			var clauses: Array[String] = []
			for row: Node in children_group.get_children():
				var child: ConditionBuilder = row.get_child(0)
				clauses.append("(" + child.line() + ")")
			return ("not (" if kind == "None of" else "") + (" and " if kind == "All of" else " or ").join(clauses) + (")" if kind == "None of" else "")
