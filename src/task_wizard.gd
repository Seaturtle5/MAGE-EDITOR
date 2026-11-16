class_name TaskWizard
extends ConfirmationDialog
## A guided task: a few pages of questions, a running summary of what will be
## made, and one Create that can be undone as a single step.

signal created(result: Dictionary)
var workspace: PackWorkspace
var template: Dictionary = {}
var fields: Dictionary = {}
var getters: Dictionary = {}
var setters: Dictionary = {}
var step := 0
var steps: Array = []
var pages: Array[Control] = []
var reviewing := false
var bar: HBoxContainer
var host: VBoxContainer
var scroll: ScrollContainer
var sheet: VBoxContainer
var error: Label
var back: Button
var review: VBoxContainer

func _ready() -> void:
	exclusive = true
	dialog_hide_on_ok = false
	var body := VBoxContainer.new()
	body.custom_minimum_size = Vector2(760, 470)
	add_child(body)
	bar = HBoxContainer.new()
	body.add_child(bar)
	var columns := HBoxContainer.new()
	columns.size_flags_vertical = Control.SIZE_EXPAND_FILL
	columns.add_theme_constant_override("separation", 14)
	body.add_child(columns)
	scroll = ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	columns.add_child(scroll)
	host = VBoxContainer.new()
	host.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(host)
	var panel := PanelContainer.new()
	panel.theme_type_variation = "Card"
	panel.custom_minimum_size.x = 230
	columns.add_child(panel)
	sheet = VBoxContainer.new()
	panel.add_child(sheet)
	error = AuthoringLayout.label("", 14)
	error.theme_type_variation = "ErrorLabel"
	body.add_child(error)
	back = add_button("‹ Back", false, "back")
	custom_action.connect(func(action: StringName) -> void:
		if action == "back": go(step - 1))
	get_ok_button().theme_type_variation = "PrimaryButton"
	confirmed.connect(next)

func open(value: PackWorkspace, data: Dictionary) -> void:
	workspace = value
	template = data
	title = data.title
	fields.clear()
	getters.clear()
	setters.clear()
	pages.clear()
	steps = data.steps.duplicate()
	AuthoringLayout.clear(host)
	for name: String in steps:
		var page := VBoxContainer.new()
		page.add_theme_constant_override("separation", 6)
		page.add_child(AuthoringLayout.label(name, 22))
		host.add_child(page)
		pages.append(page)
		for question: Dictionary in data.questions:
			if question.step == name: _question(page, question)
	review = VBoxContainer.new()
	host.add_child(review)
	pages.append(review)
	go(0)
	popup_centered_clamped(Vector2i(820, 600), 0.92)
	if fields.has("name"): fields.name.grab_focus()

func _question(page: VBoxContainer, question: Dictionary) -> void:
	var key: String = question.key
	var kind: String = str(question.kind).trim_suffix("?")
	var caption := AuthoringLayout.label(str(question.label), 15)
	page.add_child(caption)
	if not str(question.help).is_empty(): page.add_child(AuthoringLayout.label(str(question.help), 13, true))
	var control: Control
	if kind in AuthorTemplates.CONTENT:
		var picker := PickerButton.new()
		picker.workspace = workspace
		picker.drop_kinds = [kind]
		picker.placeholder = "Choose " + ("an " if Wording.name(kind).left(1) in ["a", "e", "i", "o", "u"] else "a ") + Wording.name(kind) + ("…" if not str(question.kind).ends_with("?") else " (or leave empty)…")
		picker.text = picker.placeholder
		picker.alignment = HORIZONTAL_ALIGNMENT_LEFT
		picker.options = func() -> Array:
			var result: Array = []
			if str(question.kind).ends_with("?"): result.append({"value": "", "label": "(none)"})
			for row: Dictionary in workspace.rows:
				if row.def.type == kind and row.def.mode != "extend": result.append({"value": row.def.id, "label": Wording.title(row), "detail": "" if row.doc.writable else str(row.pack)})
			return result
		if AuthorTemplates.INLINE.has(kind):
			picker.commands = [{"label": "＋ New " + Wording.name(kind) + "…", "action": func() -> void: _name_new(picker, kind)}]
		picker.picked.connect(func(_value: String) -> void: _changed())
		getters[key] = func() -> String: return picker.value
		setters[key] = func(value: String) -> void: picker.set_value(value)
		control = picker
	elif kind.begins_with("choice:"):
		var options := kind.trim_prefix("choice:").split(",")
		var row := HFlowContainer.new()
		var group := ButtonGroup.new()
		for option: String in options:
			var button := Button.new()
			button.text = option.capitalize()
			button.toggle_mode = true
			button.button_group = group
			button.button_pressed = option == question.default
			button.set_meta("value", option)
			button.pressed.connect(_changed)
			row.add_child(button)
		getters[key] = func() -> String: return str(group.get_pressed_button().get_meta("value")) if group.get_pressed_button() != null else ""
		setters[key] = func(value: String) -> void:
			for button: BaseButton in group.get_buttons(): button.button_pressed = button.get_meta("value") == value
		control = row
	elif kind == "number":
		var amount := SpinBox.new()
		amount.max_value = 100000
		amount.value = float(question.default)
		amount.value_changed.connect(func(_number: float) -> void: _changed())
		getters[key] = func() -> String: return str(int(amount.value))
		setters[key] = func(value: String) -> void: amount.value = float(value)
		control = amount
	elif kind == "prose":
		var text := TextEdit.new()
		text.text = str(question.default)
		text.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
		text.custom_minimum_size.y = 96
		text.theme_type_variation = "StoryBubble"
		text.text_changed.connect(_changed)
		getters[key] = func() -> String: return text.text
		setters[key] = func(value: String) -> void: text.text = value
		control = text
	elif kind == "responses": control = _responses(key, str(question.default))
	elif kind == "stages": control = _stages(key, str(question.default))
	else:
		var input := LineEdit.new()
		input.text = question.default
		input.placeholder_text = "Write a name"
		input.text_changed.connect(func(_text: String) -> void: _changed())
		input.text_submitted.connect(func(_text: String) -> void: next())
		getters[key] = func() -> String: return input.text
		setters[key] = func(value: String) -> void: input.text = value
		control = input
	control.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	fields[key] = control
	page.add_child(control)

## Asks only for a name; the place or area is made together with the task.
func _name_new(picker: PickerButton, kind: String) -> void:
	var dialog := ConfirmationDialog.new()
	dialog.title = "New " + Wording.name(kind)
	dialog.ok_button_text = "Use this name"
	var input := LineEdit.new()
	input.placeholder_text = "Name of the new " + Wording.name(kind)
	input.custom_minimum_size.x = 320
	dialog.add_child(input)
	dialog.register_text_enter(input)
	dialog.confirmed.connect(func() -> void:
		if not input.text.strip_edges().is_empty(): picker.choose(AuthorTemplates.NEW + input.text.strip_edges())
		dialog.queue_free())
	dialog.canceled.connect(dialog.queue_free)
	add_child(dialog)
	dialog.popup_centered()
	input.grab_focus()

func _responses(key: String, initial: String) -> Control:
	var box := VBoxContainer.new()
	var rows := VBoxContainer.new()
	box.add_child(rows)
	var add_row := func(response: Dictionary) -> void:
		var card := PanelContainer.new()
		card.theme_type_variation = "Block"
		var column := VBoxContainer.new()
		card.add_child(column)
		var top := HBoxContainer.new()
		column.add_child(top)
		var label := LineEdit.new()
		label.text = str(response.get("label", ""))
		label.placeholder_text = "What the player says or does"
		label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		label.text_changed.connect(func(_text: String) -> void: _changed())
		top.add_child(label)
		var remove := Button.new()
		remove.text = "✕"
		remove.theme_type_variation = "Ghost"
		remove.tooltip_text = "Remove this response"
		remove.pressed.connect(func() -> void:
			rows.remove_child(card)
			card.queue_free()
			_changed())
		top.add_child(remove)
		var reply := TextEdit.new()
		reply.text = str(response.get("reply", ""))
		reply.placeholder_text = "The reply (leave empty for none)"
		reply.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
		reply.custom_minimum_size.y = 56
		reply.text_changed.connect(_changed)
		column.add_child(reply)
		var ending := OptionButton.new()
		ending.add_item("Then back to the list of responses")
		ending.add_item("Then the talk ends")
		ending.select(1 if response.get("ending", "back") == "end" else 0)
		ending.item_selected.connect(func(_index: int) -> void: _changed())
		column.add_child(ending)
		card.set_meta("read", func() -> Dictionary: return {"label": label.text.strip_edges(), "reply": reply.text.strip_edges(), "ending": "end" if ending.selected == 1 else "back"})
		rows.add_child(card)
	for response: Dictionary in AuthorTemplates.read_responses(initial): add_row.call(response)
	var add := Button.new()
	add.text = "＋ Response"
	add.theme_type_variation = "AddRow"
	add.pressed.connect(func() -> void:
		add_row.call({})
		_changed())
	box.add_child(add)
	getters[key] = func() -> String:
		var responses: Array = []
		for card: Node in rows.get_children():
			var response: Dictionary = card.get_meta("read").call()
			if not str(response.label).is_empty(): responses.append(response)
		return AuthorTemplates.write_responses(responses)
	setters[key] = func(value: String) -> void:
		AuthoringLayout.clear(rows)
		for response: Dictionary in AuthorTemplates.read_responses(value): add_row.call(response)
	return box

func _stages(key: String, initial: String) -> Control:
	var box := VBoxContainer.new()
	var rows := VBoxContainer.new()
	box.add_child(rows)
	var add_row := func(text: String) -> void:
		var row := HBoxContainer.new()
		var input := LineEdit.new()
		input.text = text
		input.placeholder_text = "Name of this stage"
		input.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		input.text_changed.connect(func(_text: String) -> void: _changed())
		row.add_child(input)
		for pair: Array in [["↑", -1, "Move earlier"], ["↓", 1, "Move later"]]:
			var move := Button.new()
			move.text = pair[0]
			move.theme_type_variation = "Ghost"
			move.tooltip_text = pair[2]
			move.pressed.connect(func() -> void:
				var target: int = clampi(row.get_index() + int(pair[1]), 0, rows.get_child_count() - 1)
				rows.move_child(row, target)
				_changed())
			row.add_child(move)
		var remove := Button.new()
		remove.text = "✕"
		remove.theme_type_variation = "Ghost"
		remove.tooltip_text = "Remove this stage"
		remove.pressed.connect(func() -> void:
			rows.remove_child(row)
			row.queue_free()
			_changed())
		row.add_child(remove)
		row.set_meta("input", input)
		rows.add_child(row)
	for stage: String in initial.split(";", false): add_row.call(stage)
	var add := Button.new()
	add.text = "＋ Stage"
	add.theme_type_variation = "AddRow"
	add.pressed.connect(func() -> void:
		add_row.call("")
		_changed())
	box.add_child(add)
	getters[key] = func() -> String:
		var names: Array[String] = []
		for row: Node in rows.get_children():
			var text: String = (row.get_meta("input") as LineEdit).text.strip_edges()
			if not text.is_empty(): names.append(text)
		return ";".join(names)
	setters[key] = func(value: String) -> void:
		AuthoringLayout.clear(rows)
		for stage: String in value.split(";", false): add_row.call(stage)
	return box

func answers() -> Dictionary:
	var result: Dictionary = {}
	for key: String in getters: result[key] = str(getters[key].call())
	return result

func set_answer(key: String, value: String) -> void:
	setters[key].call(value)
	_changed()

func _changed() -> void:
	error.text = ""
	_summary()

func _pieces(text: String) -> Array[String]:
	var result: Array[String] = []
	for definition: FscParser.Definition in FscParser.parse(text, "").definitions:
		var name: String = definition.fields.name.value if definition.fields.has("name") else Wording.readable(definition.id)
		result.append(Wording.icon(definition.type) + "  " + name + "   ·   " + Wording.name(definition.type))
	return result

func _summary() -> void:
	AuthoringLayout.clear(sheet)
	sheet.add_child(AuthoringLayout.label("YOU ARE MAKING", 12, true))
	var given := answers()
	sheet.add_child(AuthoringLayout.label(str(given.get("name", "")) if not str(given.get("name", "")).strip_edges().is_empty() else str(template.title), 19))
	var result := AuthorTemplates.fill(template, given, workspace)
	if result.has("error"):
		sheet.add_child(AuthoringLayout.label(str(result.error), 14, true))
	else:
		for piece: String in _pieces(result.text): sheet.add_child(AuthoringLayout.label(piece, 14))
		var ready := AuthoringLayout.label("✓ Ready to create", 14)
		ready.theme_type_variation = "GoodLabel"
		sheet.add_child(ready)
	sheet.add_child(AuthoringLayout.label("Nothing is made until you choose Create. It can be undone in one step.", 12, true))

func go(index: int) -> void:
	step = clampi(index, 0, steps.size())
	reviewing = step == steps.size()
	for at in pages.size(): pages[at].visible = at == step
	AuthoringLayout.clear(bar)
	var titles: Array = steps + ["Review"]
	for at in titles.size():
		var button := Button.new()
		button.text = "%d  %s" % [at + 1, titles[at]]
		button.toggle_mode = true
		button.button_pressed = at == step
		button.theme_type_variation = "StepButton"
		button.pressed.connect(func() -> void:
			if at <= step: go(at)
			else:
				go(step)
				_advance_to(at))
		bar.add_child(button)
	back.visible = step > 0
	ok_button_text = "Create" if reviewing else ("Next: %s ›" % titles[step + 1])
	error.text = ""
	scroll.scroll_vertical = 0
	if reviewing:
		AuthoringLayout.clear(review)
		review.add_child(AuthoringLayout.label("Ready to create", 22))
		var result := AuthorTemplates.fill(template, answers(), workspace)
		for piece: String in _pieces(str(result.get("text", ""))): review.add_child(AuthoringLayout.label(piece, 16))
		review.add_child(AuthoringLayout.label("Everything is connected for you. After creating, it opens so you can read it as a player would, and change any part.", 14, true))
	_summary()

## Moves forward page by page, stopping at the first page with something missing.
func _advance_to(target: int) -> void:
	while step < target:
		var before := step
		next()
		if step == before: return

func _page_problem() -> String:
	var result := AuthorTemplates.fill(template, answers(), workspace)
	if not result.has("error"): return ""
	if reviewing: return result.error
	# Only what this page (or an earlier one) asks for holds the author here.
	for question: Dictionary in template.questions:
		if question.key == result.get("key", "") and steps.find(question.step) <= step: return result.error
	return ""

func next() -> void:
	var problem := _page_problem()
	if not problem.is_empty():
		error.text = problem
		return
	if not reviewing:
		go(step + 1)
		return
	var result := AuthorTemplates.create(template, answers(), workspace)
	if result.has("error"):
		error.text = result.error
		return
	hide()
	created.emit(result)
