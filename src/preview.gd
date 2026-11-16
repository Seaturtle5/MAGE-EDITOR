class_name StoryPreview
extends VBoxContainer
## Uses the engine's compiler, conditions and text renderer on throwaway state.

signal line_selected(line: int)
signal rendered
var last_entries: Array[Dictionary] = []
var workspace: PackWorkspace
var row: Dictionary = {}
var sample: OptionButton
var output: VBoxContainer
var seed_value := 1
var overrides: Dictionary = {}
var timer: Timer
var sample_form := ""
var sample_level := 1
var settings_dialog: ConfirmationDialog
var settings_values: VBoxContainer
var form_picker: ContentSlot
var level_picker: SpinBox
var value_picker: OptionButton
var value_input: Control
var settings_error: Label

func _ready() -> void:
	add_child(AuthoringLayout.label("PREVIEW AS A PLAYER", 14))
	var bar := HBoxContainer.new()
	add_child(bar)
	sample = OptionButton.new()
	for sex: String in ["Female", "Male", "Herm", "Neuter"]: sample.add_item(sex)
	sample.item_selected.connect(func(_index: int) -> void: refresh())
	bar.add_child(sample)
	var reroll := Button.new()
	reroll.text = "Re-roll"
	reroll.pressed.connect(func() -> void:
		seed_value += 1
		refresh())
	bar.add_child(reroll)
	var settings := Button.new()
	settings.text = "Sample…"
	settings.pressed.connect(_open_settings)
	bar.add_child(settings)
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.custom_minimum_size.y = 150
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_child(scroll)
	output = VBoxContainer.new()
	output.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(output)
	timer = Timer.new()
	timer.one_shot = true
	timer.wait_time = 0.3
	timer.timeout.connect(refresh)
	add_child(timer)
	settings_dialog = ConfirmationDialog.new()
	settings_dialog.title = "Sample player"
	var body := VBoxContainer.new()
	body.custom_minimum_size.x = 400
	settings_dialog.add_child(body)
	body.add_child(AuthoringLayout.label("Body form (leave empty for the default body)", 14, true))
	form_picker = ContentSlot.new()
	body.add_child(form_picker)
	body.add_child(AuthoringLayout.label("Level", 14))
	level_picker = SpinBox.new()
	level_picker.min_value = 1
	level_picker.max_value = 1000
	body.add_child(level_picker)
	body.add_child(AuthoringLayout.label("Change a saved value in this sample", 14))
	value_picker = OptionButton.new()
	value_picker.item_selected.connect(_select_value)
	body.add_child(value_picker)
	settings_values = VBoxContainer.new()
	body.add_child(settings_values)
	settings_error = AuthoringLayout.label("", 13, true)
	body.add_child(settings_error)
	settings_dialog.confirmed.connect(_apply_settings)
	add_child(settings_dialog)

func show_story(value: PackWorkspace, selected: Dictionary) -> void:
	var changed_pack: bool = workspace == null or workspace.target != value.target
	workspace = value
	row = selected
	if changed_pack:
		var config := ConfigFile.new()
		config.load(OS.get_user_data_dir().path_join("preview-samples.cfg"))
		var key := workspace.target.sha256_text()
		overrides = config.get_value(key, "values", {})
		sample_form = config.get_value(key, "form", "")
		sample_level = int(config.get_value(key, "level", 1))
		sample.select(clampi(int(config.get_value(key, "sex", 0)), 0, 3))
	if timer != null: timer.start()

static func sample_game(db: ContentDB, preset: Dictionary, seed_number: int = 1) -> Game:
	var game := Game.new(db, seed_number)
	var sex: String = preset.get("sex", "female")
	if not str(preset.get("form", "")).is_empty(): BodySystem.infect(game, preset.form, true)
	game.set_value("player.cocks", 1 if sex in ["male", "herm"] else 0)
	game.set_value("player.cunts", 1 if sex in ["female", "herm"] else 0)
	game.set_value("player.level", int(preset.get("level", 1)))
	for key: String in preset.get("values", {}): game.set_value(key, preset.values[key])
	game.take_output()
	return game

static func render_story(value: PackWorkspace, selected: Dictionary, preset: Dictionary = {}, seed_number: int = 1) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	if selected.is_empty(): return result
	var game := sample_game(value.preview_content(), preset, seed_number)
	var effective := selected.duplicate()
	var definition := game.content.get_def(selected.def.type, selected.def.id)
	if definition != null: effective.def = definition
	var nodes := StoryGraph.script_nodes(effective).duplicate()
	if effective.def.type == "menu" and not effective.has("script_field") and not effective.def.options.is_empty(): nodes.append({"kind": "choices", "line": effective.def.options[0].line, "options": effective.def.options})
	_render_nodes(nodes, game, result, 0)
	game.dispose()
	return result

static func reason(condition: Dictionary, game: Game) -> String:
	match str(condition.get("op", "")):
		"cmp":
			return "%s %s %s" % [Expr.evaluate(condition.left, game), condition.cmp, Expr.evaluate(condition.right, game)]
		"truthy": return str(condition.get("path", "Value")) + " = " + str(game.value(condition.get("path", "")))
		"and", "or": return reason(condition.a, game) + " " + str(condition.op) + " " + reason(condition.b, game)
		"not": return "not (" + reason(condition.a, game) + ")"
		_: return StoryCanvas._condition_label(condition)

static func _render_nodes(nodes: Array, game: Game, result: Array[Dictionary], depth: int) -> bool:
	if depth > 12: return true
	for node: Dictionary in nodes:
		match str(node.kind):
			"text":
				var program := Program.compile("preview", [node])
				for spans: Array in game.runner.render_paragraphs(program, 0, false): result.append({"kind": "text", "text": TextTemplate.plain(spans), "spans": spans, "line": node.line})
			"show": result.append({"kind": "image", "image": node.image, "line": node.line})
			"if":
				var taken := false
				var stopped := false
				for branch: Dictionary in node.branches:
					var condition := Condition.compile(branch.condition)
					var eligible: bool = not taken and not condition.has("error") and Condition.evaluate(condition, game)
					result.append({"kind": "branch", "taken": eligible, "text": branch.condition, "reason": reason(condition, game), "line": branch.line})
					if eligible:
						taken = true
						stopped = _render_nodes(branch.body, game, result, depth + 1)
				if not taken and node["else"] is Array: stopped = _render_nodes(node["else"], game, result, depth + 1)
				if stopped: return true
			"choices":
				for option: Dictionary in node.options:
					var condition := Condition.compile(option.condition) if not str(option.condition).is_empty() else {}
					var eligible: bool = condition.is_empty() or (not condition.has("error") and Condition.evaluate(condition, game))
					var label := TextTemplate.compile(option.label)
					result.append({"kind": "response", "text": TextTemplate.plain(game.render(label)) if not label.has("error") else option.label, "available": eligible, "reason": reason(condition, game) if not eligible else "", "line": option.line})
				return true
			"page_break":
				result.append({"kind": "boundary", "text": "Continue…", "line": node.line})
				return true
			"goto", "play":
				result.append({"kind": "boundary", "text": ("Continue to " if node.kind == "goto" else "Play and return: ") + str(node.target), "line": node.line})
				if node.kind == "goto": return true
			"fight":
				result.append({"kind": "boundary", "text": "Fight " + str(node.creature) + " · try outcomes in playtest", "line": node.line})
				return true
	return false

func refresh() -> void:
	if output == null or workspace == null: return
	for child: Node in output.get_children():
		output.remove_child(child)
		child.queue_free()
	last_entries = render_story(workspace, row, {"sex": ["female", "male", "herm", "neuter"][sample.selected], "form": sample_form, "level": sample_level, "values": overrides}, seed_value)
	rendered.emit()
	for entry: Dictionary in last_entries:
		if entry.kind == "branch": continue
		if entry.kind == "image" and not str(entry.image).is_empty():
			var path := workspace.preview_content().image_file(entry.image)
			if not path.is_empty():
				var picture := Image.load_from_file(path)
				if picture != null:
					var image := TextureRect.new()
					image.texture = ImageTexture.create_from_image(picture)
					image.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
					image.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
					image.custom_minimum_size.y = 100
					output.add_child(image)
			continue
		var text: String = entry.get("text", "Picture: " + str(entry.get("image", "")))
		if entry.kind == "response": text = "› " + text + (" · Hidden because: " + str(entry.reason) if not entry.available else "")
		var button := Button.new()
		button.text = text
		button.alignment = HORIZONTAL_ALIGNMENT_LEFT
		button.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		button.flat = true
		if entry.kind == "response" and not entry.available: button.add_theme_color_override("font_color", EditorTheme.color("muted"))
		button.pressed.connect(func() -> void: line_selected.emit(entry.line))
		output.add_child(button)
	output.add_child(AuthoringLayout.label("Actions are not applied in this text preview.", 12, true))

func _open_settings() -> void:
	if workspace == null: return
	form_picker.configure(workspace, "form")
	for index in form_picker.item_count:
		if form_picker.get_item_metadata(index) == sample_form: form_picker.select(index)
	level_picker.value = sample_level
	value_picker.clear()
	value_picker.add_item("Choose a counter, flag or stage…")
	value_picker.set_item_metadata(0, "")
	for key: String in workspace.preview_content().values:
		var declaration: Dictionary = workspace.preview_content().values[key]
		if declaration.kind in ["number", "flag", "states", "text"]:
			value_picker.add_item(key)
			value_picker.set_item_metadata(value_picker.item_count - 1, key)
	_select_value(0)
	settings_error.text = "%d sample values set. These settings never change the pack or game saves." % overrides.size()
	AuthoringLayout.popup(settings_dialog, Vector2i(460, 380))

func _select_value(index: int) -> void:
	for child: Node in settings_values.get_children():
		settings_values.remove_child(child)
		child.queue_free()
	value_input = null
	var key: String = value_picker.get_item_metadata(index)
	if key.is_empty(): return
	var declaration: Dictionary = workspace.preview_content().values[key]
	var value: Variant = overrides.get(key, declaration.get("default"))
	match str(declaration.kind):
		"number":
			var input := SpinBox.new()
			input.min_value = -100000
			input.max_value = 100000
			input.value = float(value)
			value_input = input
		"flag":
			var input := CheckButton.new()
			input.text = "Remembered"
			input.button_pressed = bool(value)
			value_input = input
		"states":
			var input := OptionButton.new()
			for state: String in declaration.states:
				input.add_item(state)
				if state == str(value): input.select(input.item_count - 1)
			value_input = input
		_:
			var input := LineEdit.new()
			input.text = str(value)
			value_input = input
	settings_values.add_child(value_input)

func _apply_settings() -> void:
	sample_form = form_picker.value()
	sample_level = int(level_picker.value)
	var key: String = value_picker.get_item_metadata(value_picker.selected)
	if not key.is_empty() and value_input != null:
		if value_input is SpinBox: overrides[key] = int(value_input.value)
		elif value_input is CheckButton: overrides[key] = value_input.button_pressed
		elif value_input is OptionButton: overrides[key] = value_input.get_item_text(value_input.selected)
		else: overrides[key] = value_input.text
	var config := ConfigFile.new()
	var path := OS.get_user_data_dir().path_join("preview-samples.cfg")
	config.load(path)
	var section := workspace.target.sha256_text()
	for pair: Array in [["values", overrides], ["form", sample_form], ["level", sample_level], ["sex", sample.selected]]: config.set_value(section, pair[0], pair[1])
	config.save(path)
	refresh()
