class_name SlotControl
extends HBoxContainer
## One editable part of a block's sentence: a picker, an amount, a switch...
## The kinds are those of BlockCatalog's slots.

signal edited
var workspace: PackWorkspace
var spec: Dictionary = {}
## Reads another slot of the same sentence: func(name) -> String.
var peers: Callable
var _read: Callable
var _write: Callable
var picker: PickerButton

const SPECIAL := {"who": ["player"], "holder": ["player", "here"], "father": ["random creature"], "zone": ["nowhere", "outside"]}
const VALUE_KINDS := {"value.flag": "flag", "value.number": "number", "value.time": "time", "value.list": "list", "value.text": "text", "value.states": "states"}
const VALUE_WORDS := {"flag": "something to remember", "number": "counter", "time": "time", "list": "list", "text": "text", "states": "stage or mood"}

static func make(pack: PackWorkspace, slot: Dictionary, value: String, others: Callable = Callable()) -> SlotControl:
	var control := SlotControl.new()
	control.workspace = pack
	control.spec = slot
	control.peers = others
	control._build()
	control.set_value(value)
	return control

func value() -> String:
	return str(_read.call())

func set_value(next: String) -> void:
	_write.call(next)

func _peer(name: String) -> String:
	return str(peers.call(name)) if peers.is_valid() else ""

func _build() -> void:
	var kind: String = spec.kind
	if kind == "switch": _build_switch()
	elif kind == "choice": _build_choice()
	elif kind == "int": _build_number()
	elif kind == "amount": _build_amount()
	elif kind == "expr": _build_expression()
	elif kind.begins_with("ids") or kind == "exprs": _build_list()
	elif kind in ["text", "quoted", "plain", "token"]: _build_text()
	else: _build_picker()

func _build_switch() -> void:
	var box := CheckBox.new()
	box.text = str(spec.options[1])
	box.toggled.connect(func(_on: bool) -> void: edited.emit())
	add_child(box)
	_read = func() -> String: return str(spec.options[1]) if box.button_pressed else ""
	_write = func(next: String) -> void: box.set_pressed_no_signal(not next.is_empty())

func _build_choice() -> void:
	var list := OptionButton.new()
	if spec.get("optional", false):
		list.add_item("(leave out)")
		list.set_item_metadata(0, "")
	for index in spec.options.size():
		list.add_item(str(spec.labels[index]))
		list.set_item_metadata(list.item_count - 1, spec.options[index])
	list.item_selected.connect(func(_index: int) -> void: edited.emit())
	add_child(list)
	_read = func() -> String: return str(list.get_item_metadata(list.selected)) if list.selected >= 0 else ""
	_write = func(next: String) -> void:
		for index in list.item_count:
			if list.get_item_metadata(index) == next: list.select(index)

func _spin(low: float = -1000000, high: float = 1000000) -> SpinBox:
	var spin := SpinBox.new()
	spin.min_value = low
	spin.max_value = high
	spin.custom_minimum_size.x = 96
	spin.select_all_on_focus = true
	spin.value_changed.connect(func(_number: float) -> void: edited.emit())
	return spin

func _build_number() -> void:
	var spin := _spin()
	var blank: bool = spec.get("optional", false)
	var used := CheckBox.new()
	used.visible = blank
	used.tooltip_text = "Leave unticked to leave this out."
	used.toggled.connect(func(on: bool) -> void:
		spin.editable = on
		edited.emit())
	add_child(used)
	add_child(spin)
	_read = func() -> String: return "" if blank and not used.button_pressed else str(int(spin.value))
	_write = func(next: String) -> void:
		used.set_pressed_no_signal(not next.is_empty())
		spin.editable = not blank or not next.is_empty()
		spin.set_value_no_signal(float(next) if next.is_valid_int() else 1.0)

func _build_amount() -> void:
	var mode := OptionButton.new()
	for title: String in ["exactly", "a random number from", "this % of what there is", "a calculation"]: mode.add_item(title)
	if spec.get("optional", false): mode.add_item("(leave out)")
	var first := _spin()
	var between := Label.new()
	between.text = "to"
	var second := _spin()
	var formula := CalcBar.new()
	formula.workspace = workspace
	formula.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	formula.changed.connect(func() -> void: edited.emit())
	mode.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	for child: Control in [mode, first, between, second, formula]: add_child(child)
	var show := func() -> void:
		first.visible = mode.selected < 3
		between.visible = mode.selected == 1
		second.visible = mode.selected == 1
		formula.visible = mode.selected == 3
	mode.item_selected.connect(func(_index: int) -> void:
		show.call()
		edited.emit())
	_read = func() -> String:
		match mode.selected:
			0: return str(int(first.value))
			1: return "%d to %d" % [int(first.value), int(second.value)]
			2: return str(int(first.value)) + "%"
			3: return formula.text()
		return ""
	_write = func(next: String) -> void:
		var bounds := Effect._range_re.search(next)
		var percent := Effect._percent_re.search(next)
		if next.is_empty() and spec.get("optional", false): mode.select(4)
		elif next.is_empty() or next.is_valid_int():
			mode.select(0)
			first.set_value_no_signal(float(next) if next.is_valid_int() else 1.0)
		elif bounds != null:
			mode.select(1)
			first.set_value_no_signal(float(bounds.get_string(1)))
			second.set_value_no_signal(float(bounds.get_string(2)))
		elif percent != null:
			mode.select(2)
			first.set_value_no_signal(float(percent.get_string(1)))
		else:
			mode.select(3)
			formula.set_text(next)
		show.call()

func _build_expression() -> void:
	var mode := OptionButton.new()
	for title: String in ["the number", "the counter", "a calculation", "the text"]: mode.add_item(title)
	if spec.get("optional", false): mode.add_item("(leave out)")
	var number := _spin()
	var counter := _value_picker("value.number")
	var formula := CalcBar.new()
	formula.workspace = workspace
	formula.changed.connect(func() -> void: edited.emit())
	var words := LineEdit.new()
	words.placeholder_text = "Write the text"
	words.custom_minimum_size.x = 220
	words.text_changed.connect(func(_text: String) -> void: edited.emit())
	formula.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	mode.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	for child: Control in [mode, number, counter, formula, words]: add_child(child)
	var show := func() -> void:
		number.visible = mode.selected == 0
		counter.visible = mode.selected == 1
		formula.visible = mode.selected == 2
		words.visible = mode.selected == 3
	mode.item_selected.connect(func(_index: int) -> void:
		show.call()
		edited.emit())
	_read = func() -> String:
		match mode.selected:
			0: return str(int(number.value))
			1: return counter.value
			2: return formula.text()
			3: return "\"" + words.text.replace("\"", "'") + "\""
		return ""
	_write = func(next: String) -> void:
		if next.is_empty() and spec.get("optional", false): mode.select(4)
		elif next.is_empty() or next.is_valid_int():
			mode.select(0)
			number.set_value_no_signal(float(next) if next.is_valid_int() else 1.0)
		elif RegEx.create_from_string("^[a-z0-9_]+\\.[a-z0-9_.]+$").search(next) != null:
			mode.select(1)
			counter.set_value(next)
		elif next.length() >= 2 and next.begins_with("\"") and next.ends_with("\"") and next.count("\"") == 2:
			mode.select(3)
			words.text = next.substr(1, next.length() - 2)
		else:
			mode.select(2)
			formula.set_text(next)
		show.call()

func _build_text() -> void:
	var input := LineEdit.new()
	input.custom_minimum_size.x = 260
	input.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var kind: String = spec.kind
	input.placeholder_text = {"text": "Write the words the player reads", "quoted": "Write the text", "token": "A name, or a text in \"quotes\"", "exprs": "One or more entries, with commas between", "father": "A creature or character, or: random creature"}.get(kind, "IDs with commas between" if kind.begins_with("ids") else "")
	input.text_changed.connect(func(_text: String) -> void: edited.emit())
	add_child(input)
	_read = func() -> String: return input.text.strip_edges()
	_write = func(next: String) -> void: input.text = next

## Several entries as chips: content IDs chosen from a list, or list entries
## (numbers and texts) typed one at a time.
func _build_list() -> void:
	var content: bool = str(spec.kind).begins_with("ids")
	var entries: Array[String] = []
	var flow := HFlowContainer.new()
	flow.custom_minimum_size.x = 320
	flow.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	add_child(flow)
	var single := {"name": "entry", "kind": str(spec.kind).get_slice(".", 1) if content else "", "default": "", "hidden": false, "optional": false}
	var show := [Callable()]
	show[0] = func() -> void:
		for child: Node in flow.get_children():
			flow.remove_child(child)
			child.queue_free()
		for entry: String in entries:
			var chip := Button.new()
			chip.theme_type_variation = "Chip"
			chip.text = (BlockCatalog.content_label(str(single.kind), entry, workspace) if content else BlockCatalog.amount_label(entry, workspace)) + "  ✕"
			chip.tooltip_text = "Remove"
			chip.pressed.connect(func() -> void:
				entries.erase(entry)
				show[0].call()
				edited.emit())
			flow.add_child(chip)
		if content:
			var add := PickerButton.new()
			add.placeholder = "+ Add…"
			add.text = add.placeholder
			add.theme_type_variation = "AddRow"
			add.allow_typing = true
			add.workspace = workspace
			add.drop_kinds = _content_types(str(single.kind))
			add.options = func() -> Array:
				var result: Array = []
				for special: String in SPECIAL.get(str(single.kind), []): result.append({"value": special, "label": special})
				for row: Dictionary in workspace.rows:
					if row.def.type in add.drop_kinds and row.def.mode != "extend" and row.def.id not in entries: result.append({"value": row.def.id, "label": Wording.title(row), "detail": "" if row.doc.writable else str(row.pack)})
				return result
			add.picked.connect(func(id: String) -> void:
				if id.is_empty() or id in entries: return
				entries.append(id)
				show[0].call()
				edited.emit())
			flow.add_child(add)
		else:
			var input := LineEdit.new()
			input.placeholder_text = "Add a number or a text, then Enter"
			input.custom_minimum_size.x = 250
			input.text_submitted.connect(func(text: String) -> void:
				var clean := text.strip_edges()
				if clean.is_empty(): return
				# A number, a saved value or a calculation stays as it is; other words are a text.
				var raw := clean if clean.is_valid_int() or clean.begins_with("\"") or (not Expr.parse(clean).has("error") and RegEx.create_from_string("[.()+*/-]|^entry |^count ").search(clean) != null) else "\"" + clean.replace("\"", "'") + "\""
				entries.append(raw)
				show[0].call()
				edited.emit()
				for child: Node in flow.get_children():
					if child is LineEdit: (child as LineEdit).grab_focus())
			flow.add_child(input)
	show[0].call()
	_read = func() -> String: return ", ".join(entries)
	_write = func(next: String) -> void:
		entries.clear()
		for part: Variant in (next.split(",", false) if content else Effect._split_top(next)):
			if not str(part).strip_edges().is_empty(): entries.append(str(part).strip_edges())
		show[0].call()

func _value_picker(kind: String) -> PickerButton:
	var button := PickerButton.new()
	var wanted: String = VALUE_KINDS.get(kind, "")
	button.placeholder = "Choose " + ("a " + VALUE_WORDS[wanted] if not wanted.is_empty() else "a value") + "…"
	button.text = button.placeholder
	button.allow_typing = true
	button.label_for = func(path: String) -> String: return BlockCatalog.value_label(path, workspace)
	button.options = func() -> Array:
		var result: Array = []
		var declared: Dictionary = workspace.preview_content().values
		var keys: Array = declared.keys()
		keys.sort()
		for key: String in keys:
			if not wanted.is_empty() and str(declared[key].get("kind", "")) != wanted: continue
			result.append({"value": key, "label": BlockCatalog.value_label(key, workspace), "detail": VALUE_WORDS.get(str(declared[key].get("kind", "")), "value")})
		if wanted in ["", "number"]:
			for key: String in Validator.PLAYER_VALUES:
				if not declared.has("player." + key): result.append({"value": "player." + key, "label": "the player's " + key.replace("_", " ").replace(".", " "), "detail": "player"})
		return result
	if not wanted.is_empty() and wanted != "list":
		button.commands = [{"label": "+ New " + str(VALUE_WORDS[wanted]) + "…", "action": func() -> void: _new_value(button, wanted)}]
	button.picked.connect(func(_next: String) -> void: edited.emit())
	return button

func _build_picker() -> void:
	var kind: String = spec.kind
	if kind.begins_with("value"):
		picker = _value_picker(kind)
	else:
		picker = PickerButton.new()
		picker.allow_typing = true
		picker.workspace = workspace
		var title := BlockCatalog.slot_title(spec)
		picker.placeholder = "Choose " + ("an " if title.left(1) in ["a", "e", "i", "o", "u"] else "a ") + title + "…"
		picker.text = picker.placeholder
		picker.options = _options
		picker.label_for = func(id: String) -> String: return BlockCatalog.label(spec, id, workspace)
		picker.drop_kinds = spec.get("types", _content_types(kind))
		picker.picked.connect(func(_next: String) -> void: edited.emit())
		# Results and stages can be made where they are first needed.
		if kind == "result": picker.commands = [{"label": "+ New result…", "action": func() -> void: _new_word("result", "What can come of this event? One or two words, such as “taken” or “left behind”.")}]
		if kind == "stage": picker.commands = [{"label": "+ New stage…", "action": func() -> void: _new_word("stage", "The next step of the quest, in one or two words.")}]
	add_child(picker)
	_read = func() -> String: return picker.value
	_write = func(next: String) -> void: picker.set_value(next)

static func _content_types(kind: String) -> Array:
	match kind:
		"who": return ["character", "creature"]
		"holder": return ["character", "location"]
		"form": return ["form", "creature"]
		"father": return ["creature", "character"]
		"script": return ["scene"]
	return [kind] if kind in PackWorkspace.types() else []

func _options() -> Array:
	var kind: String = spec.kind
	var result: Array = []
	var db := workspace.preview_content()
	match kind:
		"stage":
			for stage: String in db.quests.get(_peer("quest"), {}).get("stages", []): result.append({"value": stage, "label": stage.replace("_", " ")})
			return result
		"result":
			var event := _peer("event")
			if event.is_empty() and peers.is_valid(): event = _peer("@event")
			var definition := db.get_def("event", event)
			if definition != null:
				for outcome: String in db._list(definition, "outcomes"): result.append({"value": outcome, "label": outcome.replace("_", " ")})
			return result
		"state":
			for state: String in db.values.get(_peer("value"), {}).get("states", []): result.append({"value": state, "label": state.replace("_", " ")})
			return result
		"option":
			for option: String in db.levels.get(_peer("level"), {}).get("options", []): result.append({"value": option, "label": option.replace("_", " ")})
			return result
	if kind.begins_with("word.") or kind.begins_with("phrase."):
		for word: String in workspace.known_words(kind.get_slice(".", 1)): result.append({"value": word, "label": word.replace("_", " ")})
		return result
	for special: String in SPECIAL.get(kind, []): result.append({"value": special, "label": BlockCatalog.content_label(kind, special, workspace)})
	if kind == "item" and peers.is_valid() and not _peer("creature").is_empty(): result.append({"value": "none", "label": "nothing"})
	var types: Array = spec.get("types", _content_types(kind))
	var seen: Dictionary = {}
	for row: Dictionary in workspace.rows:
		if row.def.type not in types or row.def.mode == "extend" or seen.has(row.def.id): continue
		seen[row.def.id] = true
		result.append({"value": row.def.id, "label": Wording.title(row), "detail": ("" if row.doc.writable else str(row.pack)) + (" · " + Wording.name(row.def.type) if types.size() > 1 else "")})
	return result

## Adds a result to the event, or a stage to the quest, the sentence names.
func _new_word(kind: String, hint: String) -> void:
	var owner := (_peer("event") if not _peer("event").is_empty() else _peer("@event")) if kind == "result" else _peer("quest")
	var dialog := ConfirmationDialog.new()
	dialog.title = "New " + kind
	dialog.ok_button_text = "Add"
	dialog.dialog_hide_on_ok = false
	var body := VBoxContainer.new()
	body.custom_minimum_size.x = 360
	dialog.add_child(body)
	body.add_child(AuthoringLayout.label(hint if not owner.is_empty() else ("Choose the event first." if kind == "result" else "Choose the quest first."), 14, true))
	var input := LineEdit.new()
	input.editable = not owner.is_empty()
	body.add_child(input)
	var problem := AuthoringLayout.label("", 13)
	problem.theme_type_variation = "ErrorLabel"
	body.add_child(problem)
	dialog.register_text_enter(input)
	dialog.confirmed.connect(func() -> void:
		if owner.is_empty():
			dialog.hide()
			return
		var id := workspace.unique_id(input.text, kind)
		var error := workspace.transaction("New %s “%s”" % [kind, input.text.strip_edges()], func() -> String:
			if input.text.strip_edges().is_empty(): return "Give it a name."
			return workspace.add_outcome(owner, id) if kind == "result" else workspace.add_stage(owner, id))
		if not error.is_empty():
			problem.text = error
			return
		dialog.hide()
		picker.choose(id))
	dialog.canceled.connect(dialog.queue_free)
	add_child(dialog)
	dialog.popup_centered()
	input.grab_focus()

## Declares a value where it is first needed: only a name and an owner are asked.
func _new_value(button: PickerButton, kind: String) -> void:
	var dialog := ConfirmationDialog.new()
	dialog.title = "New " + str(VALUE_WORDS[kind])
	dialog.ok_button_text = "Create"
	dialog.dialog_hide_on_ok = false
	var body := VBoxContainer.new()
	body.custom_minimum_size.x = 380
	dialog.add_child(body)
	body.add_child(AuthoringLayout.label("Who or what does it belong to?", 14))
	var owner := PickerButton.new()
	owner.placeholder = "Choose a character, place, item, quest…"
	owner.text = owner.placeholder
	owner.options = func() -> Array:
		var result: Array = []
		for row: Dictionary in workspace.rows:
			if row.doc.writable and row.def.mode == "define" and ContentDB.SCHEMA.get(row.def.type, {}).has("values"):
				result.append({"value": row.def.type + ":" + row.def.id, "label": Wording.title(row), "detail": Wording.name(row.def.type)})
		return result
	body.add_child(owner)
	body.add_child(AuthoringLayout.label("Name", 14))
	var name_input := LineEdit.new()
	name_input.placeholder_text = {"flag": "met, door opened, promised…", "number": "trust, visits, coins…", "time": "last visit", "text": "nickname", "states": "mood"}.get(kind, "")
	body.add_child(name_input)
	var start := LineEdit.new()
	if kind in ["number", "states"]:
		body.add_child(AuthoringLayout.label("Starting number" if kind == "number" else "The stages, first one is the start (commas between)", 14))
		start.text = "0" if kind == "number" else ""
		start.placeholder_text = "" if kind == "number" else "calm, curious, worried"
		body.add_child(start)
	var problem := AuthoringLayout.label("", 13, true)
	problem.theme_type_variation = "ErrorLabel"
	body.add_child(problem)
	dialog.confirmed.connect(func() -> void:
		var parts := owner.value.split(":")
		if parts.size() != 2:
			problem.text = "Choose who or what it belongs to."
			return
		var declaration := {"flag": "flag", "time": "time", "text": "text", "number": "number " + (start.text.strip_edges() if start.text.strip_edges().is_valid_int() else "0"), "states": start.text.strip_edges()}[kind] as String
		var id := workspace.unique_id(name_input.text, "value")
		var error := workspace.transaction("New " + str(VALUE_WORDS[kind]) + " " + name_input.text.strip_edges(), func() -> String:
			return workspace.declare_value(parts[0], parts[1], id, declaration) if not name_input.text.strip_edges().is_empty() else "Give it a name.")
		if not error.is_empty():
			problem.text = error
			return
		dialog.hide()
		button.choose(parts[1] + "." + id))
	dialog.canceled.connect(dialog.queue_free)
	add_child(dialog)
	dialog.popup_centered()
	name_input.grab_focus()
