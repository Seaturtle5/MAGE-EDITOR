class_name CalcBar
extends VBoxContainer
## A calculation built from chips instead of typed: numbers, saved values,
## plus / minus / times / divided by, brackets and random spans, in the order
## they are read. The engine's own reader says whether it is complete.

signal changed
var workspace: PackWorkspace
var _tokens: Array[String] = []
var _raw := ""
var _flow: HFlowContainer
var _note: Label

const SIGNS := {"+": "+", "-": "−", "*": "×", "/": "÷", "%": "mod"}
const SIGN_WORDS := {"+": "plus", "-": "minus", "*": "times", "/": "divided by", "%": "the remainder after dividing by"}
const WORDS := {"random": "a random number from", "to": "to", "min": "the smaller of", "max": "the larger of", "sqrt": "the square root of", "entry": "entry number", "of": "of", "count": "how many entries in", "up": "but at most", "down": "but at least"}

func _init() -> void:
	add_theme_constant_override("separation", 4)
	_flow = HFlowContainer.new()
	_flow.custom_minimum_size.x = 320
	_flow.add_theme_constant_override("h_separation", 4)
	_flow.add_theme_constant_override("v_separation", 4)
	add_child(_flow)
	var tools := HFlowContainer.new()
	tools.add_theme_constant_override("h_separation", 4)
	add_child(tools)
	var number := _tool("+ number", "Add a number.")
	number.pressed.connect(func() -> void: _append(["1"]))
	tools.add_child(number)
	var counter := PickerButton.new()
	counter.placeholder = "+ counter…"
	counter.text = counter.placeholder
	counter.theme_type_variation = "AddRow"
	counter.focus_mode = Control.FOCUS_NONE
	counter.tooltip_text = "Add a saved number: a counter of your stories, or one of the player's numbers."
	counter.allow_typing = true
	counter.options = func() -> Array: return _value_options()
	counter.label_for = func(_value: String) -> String: return counter.placeholder
	counter.picked.connect(func(path: String) -> void:
		if not path.is_empty(): _append([path]))
	tools.add_child(counter)
	for sign: String in ["+", "-", "*", "/"]:
		var button := _tool(SIGNS[sign], SIGN_WORDS[sign].capitalize())
		button.pressed.connect(func() -> void: _append([sign]))
		tools.add_child(button)
	for bracket: String in ["(", ")"]:
		var button := _tool(bracket, "Open a group: what is inside is worked out first." if bracket == "(" else "Close the group.")
		button.pressed.connect(func() -> void: _append([bracket]))
		tools.add_child(button)
	var random := _tool("🎲 random", "Add a random whole number between two numbers.")
	random.pressed.connect(func() -> void: _append(["random", "1", "to", "6"]))
	tools.add_child(random)
	for function: Array in [["min", "smaller of", "The smaller of two numbers."], ["max", "larger of", "The larger of two numbers."]]:
		var button := _tool(str(function[1]), str(function[2]))
		button.pressed.connect(func() -> void: _append([str(function[0]), "(", "1", ",", "2", ")"]))
		tools.add_child(button)
	var root := _tool("√", "The whole-number square root of what is in the brackets.")
	root.pressed.connect(func() -> void: _append(["sqrt", "(", "9", ")"]))
	tools.add_child(root)
	for kind: Array in [["+ list size…", "How many entries a list has.", ["count", "of"]], ["+ list entry…", "One entry of a list: the first is number 1.", ["entry", "1", "of"]]]:
		var list := PickerButton.new()
		list.placeholder = str(kind[0])
		list.text = list.placeholder
		list.theme_type_variation = "AddRow"
		list.focus_mode = Control.FOCUS_NONE
		list.tooltip_text = str(kind[1])
		list.allow_typing = true
		list.options = func() -> Array: return _value_options("list")
		list.label_for = func(_value: String) -> String: return list.placeholder
		list.picked.connect(func(path: String) -> void:
			if not path.is_empty(): _append((kind[2] as Array) + [path]))
		tools.add_child(list)
	var back := _tool("⌫", "Take out the last part.")
	back.pressed.connect(func() -> void:
		if _tokens.is_empty(): return
		_tokens.pop_back()
		_edited())
	tools.add_child(back)
	_note = AuthoringLayout.label("", 12, true)
	add_child(_note)

func _tool(text: String, tooltip: String) -> Button:
	var button := Button.new()
	button.text = text
	button.tooltip_text = tooltip
	button.theme_type_variation = "AddRow"
	button.focus_mode = Control.FOCUS_NONE
	return button

func _value_options(kind: String = "number") -> Array:
	var result: Array = []
	if workspace == null: return result
	var declared: Dictionary = workspace.preview_content().values
	var keys: Array = declared.keys()
	keys.sort()
	for key: String in keys:
		if str(declared[key].get("kind", "")) == kind: result.append({"value": key, "label": BlockCatalog.value_label(key, workspace), "detail": "counter" if kind == "number" else kind})
	if kind != "number": return result
	for key: String in Validator.PLAYER_VALUES:
		if not declared.has("player." + key): result.append({"value": "player." + key, "label": "the player's " + key.replace("_", " ").replace(".", " "), "detail": "player"})
	return result

## The calculation as the content format writes it.
func text() -> String:
	return _raw

func set_text(value: String) -> void:
	_raw = value.strip_edges()
	_tokens.clear()
	var read := Expr.tokenize(_raw)
	if read.size() > 0 and read[0] == "<error>": _tokens.append(_raw)
	else:
		for token: String in read: _tokens.append(token)
	_draw()

static func join(tokens: Array) -> String:
	var out := " ".join(tokens)
	return out.replace("( ", "(").replace(" )", ")").replace(" ,", ",")

func _append(more: Array) -> void:
	for token: String in more: _tokens.append(token)
	_edited()

func _edited() -> void:
	_raw = join(_tokens)
	_draw()
	changed.emit()

func _draw() -> void:
	for child: Node in _flow.get_children():
		_flow.remove_child(child)
		child.queue_free()
	if _tokens.is_empty():
		var empty := AuthoringLayout.label("Build the calculation with the buttons below.", 13, true)
		empty.autowrap_mode = TextServer.AUTOWRAP_OFF
		_flow.add_child(empty)
	for index in _tokens.size(): _flow.add_child(_chip(index))
	var problem := "" if _tokens.is_empty() else str(Expr.parse(_raw).get("error", ""))
	_note.text = "" if problem.is_empty() else "Not complete yet: " + problem
	_note.visible = not problem.is_empty()

func _chip(index: int) -> Control:
	var token: String = _tokens[index]
	if token.is_valid_int():
		var number := LineEdit.new()
		number.text = token
		number.custom_minimum_size.x = 56
		number.alignment = HORIZONTAL_ALIGNMENT_CENTER
		number.tooltip_text = "A number. Type another to change it."
		var keep := func() -> void:
			if not is_instance_valid(number): return
			var next := number.text.strip_edges()
			if next == _tokens[index]: return
			if not next.is_valid_int():
				number.text = _tokens[index]
				return
			_tokens[index] = next
			_raw = join(_tokens)
			_note.visible = Expr.parse(_raw).has("error")
			changed.emit()
		number.text_submitted.connect(func(_text: String) -> void: keep.call())
		number.focus_exited.connect(keep)
		return number
	if "." in token and RegEx.create_from_string("^[a-z0-9_]+\\.[a-z0-9_.]+$").search(token) != null:
		var value := PickerButton.new()
		value.theme_type_variation = "Chip"
		value.focus_mode = Control.FOCUS_NONE
		value.workspace = workspace
		value.allow_typing = true
		value.placeholder = "Choose a counter…"
		value.label_for = func(path: String) -> String: return BlockCatalog.value_label(path, workspace)
		value.options = func() -> Array: return _value_options()
		value.set_value(token)
		value.tooltip_text = "A saved number. Choose to pick another."
		value.picked.connect(func(path: String) -> void:
			if path.is_empty() or path == _tokens[index]: return
			_tokens[index] = path
			_edited())
		return value
	var chip := Button.new()
	chip.theme_type_variation = "Chip"
	chip.focus_mode = Control.FOCUS_NONE
	chip.text = SIGNS.get(token, WORDS.get(token, token))
	chip.tooltip_text = (str(SIGN_WORDS[token]).capitalize() + ". Choose to change or remove it.") if SIGNS.has(token) else "Choose to remove it."
	chip.pressed.connect(func() -> void:
		var menu := PopupMenu.new()
		if SIGNS.has(token):
			for sign: String in SIGNS:
				menu.add_item("%s  %s" % [SIGNS[sign], SIGN_WORDS[sign]])
				menu.set_item_metadata(menu.item_count - 1, sign)
			menu.add_separator()
		menu.add_item("Remove")
		menu.set_item_metadata(menu.item_count - 1, "")
		menu.index_pressed.connect(func(at: int) -> void:
			var chosen: String = str(menu.get_item_metadata(at))
			if chosen.is_empty(): _tokens.remove_at(index)
			else: _tokens[index] = chosen
			_edited())
		menu.popup_hide.connect(menu.queue_free)
		add_child(menu)
		menu.popup(Rect2i(Vector2i(chip.get_screen_position()) + Vector2i(0, int(chip.size.y)), Vector2i.ZERO)))
	return chip
