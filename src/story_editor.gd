class_name StoryEditor
extends VBoxContainer
## The board supplies context; this panel changes exact source ranges.

signal changed(row: Dictionary)
signal problem(message: String)
signal validated
var workspace: PackWorkspace
var row: Dictionary = {}
var snapshot := ""
var heading: Label
var blocks: VBoxContainer
var block_scroll: ScrollContainer
var show_line: CheckButton
var preview: StoryPreview
var folded: Dictionary = {}
var edit_dialog: ConfirmationDialog
var edit_text: TextEdit
var edit_entry: Dictionary = {}
var edit_original := ""
var edit_error: Label
var condition_dialog: ConfirmationDialog
var condition: ConditionBuilder
var condition_entry: Dictionary = {}
var condition_error: Label
var condition_form: VBoxContainer
var action_dialog: ConfirmationDialog
var action_search: LineEdit
var action_list: ItemList
var action_slots: VBoxContainer
var action_fields: Dictionary = {}
var action_entries: Array[Dictionary] = []
var action_entry: Dictionary = {}
var action_error: Label
var check_timer: Timer
var checked_revision := -1

func _ready() -> void:
	custom_minimum_size.x = 320
	heading = AuthoringLayout.label("Choose a story card", 18, true)
	add_child(heading)
	show_line = CheckButton.new()
	show_line.text = "Show the line"
	var settings := ConfigFile.new()
	settings.load(OS.get_user_data_dir().path_join("preferences.cfg"))
	show_line.button_pressed = settings.get_value("authoring", "show_line", false)
	show_line.toggled.connect(func(enabled: bool) -> void:
		settings.load(OS.get_user_data_dir().path_join("preferences.cfg"))
		settings.set_value("authoring", "show_line", enabled)
		settings.save(OS.get_user_data_dir().path_join("preferences.cfg"))
		refresh())
	add_child(show_line)
	var scroll := ScrollContainer.new()
	block_scroll = scroll
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_child(scroll)
	blocks = VBoxContainer.new()
	blocks.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(blocks)
	preview = StoryPreview.new()
	add_child(preview)
	preview.line_selected.connect(_focus_line)
	_build_dialogs()
	check_timer = Timer.new()
	check_timer.one_shot = true
	check_timer.wait_time = 0.3
	check_timer.timeout.connect(func() -> void:
		workspace.validate_buffers()
		checked_revision = workspace.revision
		refresh()
		validated.emit())
	add_child(check_timer)

func show_story(value: PackWorkspace, selected: Dictionary) -> void:
	if row.is_empty() or selected.is_empty() or row.doc.path != selected.doc.path or row.def.id != selected.def.id or row.get("script_field", "") != selected.get("script_field", ""): folded.clear()
	workspace = value
	row = selected
	refresh()

func refresh() -> void:
	if blocks == null or workspace == null: return
	for child: Node in blocks.get_children():
		blocks.remove_child(child)
		child.queue_free()
	if row.is_empty(): return
	var current := workspace.find_row(row.doc.path, row.def.type, row.def.id, row.def.mode, row.get("ordinal", 0))
	if current.is_empty():
		row = {}
		heading.text = "Choose a story card"
		return
	if row.has("script_field"): current.script_field = row.script_field
	row = current
	snapshot = row.doc.text
	heading.text = Wording.title(row) + " › " + str(row.get("script_field", "story"))
	var entries := StoryGraph.structure(row)
	var hidden: Dictionary = {}
	for entry: Dictionary in entries:
		if hidden.has(entry.parent):
			hidden[entry.key] = true
			continue
		if entry.node.kind == "choices": continue
		_add_block(entry, entries)
		if folded.get(entry.key, false): hidden[entry.key] = true
	var add := Button.new()
	add.text = "+ Add action"
	add.disabled = not row.doc.writable
	add.pressed.connect(_open_actions)
	blocks.add_child(add)
	var speech := Button.new()
	speech.text = "+ Speech"
	speech.disabled = not row.doc.writable
	speech.pressed.connect(func() -> void: _perform("Add speech", func() -> String: return StoryGraph.add_speech(row)))
	blocks.add_child(speech)
	preview.show_story(workspace, row)
	if check_timer != null and checked_revision != workspace.revision: check_timer.start()

func _add_block(entry: Dictionary, entries: Array[Dictionary]) -> void:
	var box := BlockTarget.new()
	box.path = row.doc.path
	box.snapshot = snapshot
	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", mini(str(entry.indent).replace("\t", "    ").length(), 24) * 2)
	blocks.add_child(margin)
	margin.add_child(box)
	box.set_meta("source_line", entry.line)
	box.focus_mode = Control.FOCUS_ALL
	for diagnostic: Dictionary in workspace.diagnostics:
		if diagnostic.path == row.doc.path and int(diagnostic.line) == int(entry.line) and diagnostic.severity == "error":
			var hint := AuthoringLayout.label(diagnostic.message, 13, true)
			hint.add_theme_color_override("font_color", EditorTheme.color("bad"))
			box.add_child(hint)
	box.received.connect(func(data: Dictionary) -> void:
		var source := StoryGraph.node_span(row, data.line, data.kind)
		_perform("Move story block", func() -> String: return StoryGraph.move_block(row, source, entry.line, entry.indent, snapshot, data.get("copy", false))))
	var bar := HBoxContainer.new()
	box.add_child(bar)
	var handle := BlockHandle.new()
	handle.text = "⠿"
	handle.tooltip_text = "Drag to move. Ctrl-drag copies. The arrow buttons also move blocks."
	handle.payload = {"mage_kind": "block", "path": row.doc.path, "snapshot": snapshot, "line": entry.line, "kind": entry.node.kind}
	bar.add_child(handle)
	var node: Dictionary = entry.node
	var text: String = {"text": "Speech", "response": "Response · " + str(node.get("label", "")), "branch": "Otherwise" if str(node.get("condition", "")).is_empty() else "Only if " + str(node.get("condition", "")), "if": "Only if…", "fight": "Fight " + str(node.get("creature", "")), "outcome": str(node.get("label", "Result")), "goto": "Continue · " + str(node.get("target", "")), "play": "Play and return · " + str(node.get("target", "")), "show": "Picture · " + str(node.get("image", "")), "page_break": "Pause"}.get(node.kind, "Kept block")
	if node.kind == "effect": text = BlockCatalog.sentence(node.text)
	if node.kind == "text": text = Wording.prose(StoryCanvas._display_dynamic(str(node.text)))
	var label := AuthoringLayout.label(text, 15, true)
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.custom_minimum_size.x = 140
	bar.add_child(label)
	var container: bool = node.kind in ["if", "fight", "branch", "outcome", "response"]
	if container:
		var fold := Button.new()
		fold.text = "▸" if folded.get(entry.key, false) else "▾"
		fold.pressed.connect(func() -> void:
			folded[entry.key] = not folded.get(entry.key, false)
			refresh())
		bar.add_child(fold)
	box.tooltip_text = "Line %d" % int(entry.line)
	if show_line.button_pressed:
		var raw := AuthoringLayout.label(StoryGraph._lines(row.doc)[int(entry.line) - 1].strip_edges(), 12, true)
		raw.add_theme_color_override("font_color", EditorTheme.color("muted"))
		box.add_child(raw)
	var tools := HFlowContainer.new()
	box.add_child(tools)
	var kept: bool = node.has("inline_field") or node.kind in ["branch", "outcome"] or (node.kind == "effect" and BlockCatalog.read_line(node.text).is_empty())
	if node.kind == "text" and not node.has("inline_field"):
		var edit := Button.new()
		edit.text = "Write…"
		edit.disabled = not row.doc.writable
		edit.pressed.connect(func() -> void:
			var passage := StoryGraph.prose_block(row, node)
			if passage.has("error"):
				problem.emit(passage.error)
				return
			edit_entry = entry
			edit_original = passage.text
			edit_text.text = edit_original
			edit_error.text = ""
			edit_dialog.popup_centered())
		tools.add_child(edit)
	if kept or not row.doc.writable: return
	for operation: String in ["↑", "↓", "Copy", "Only if…", "Remove"]:
		var button := Button.new()
		button.text = operation
		button.pressed.connect(_block_action.bind(operation, entry, entries))
		tools.add_child(button)

func _block_action(operation: String, entry: Dictionary, entries: Array[Dictionary]) -> void:
	if operation == "Only if…":
		condition_entry = entry
		if condition != null:
			condition.get_parent().remove_child(condition)
			condition.queue_free()
		condition = ConditionBuilder.new()
		condition.configure(workspace)
		condition_form.add_child(condition)
		condition_error.text = ""
		condition_dialog.popup_centered()
		return
	_perform(operation + " story block", func() -> String:
		if operation == "Remove": return StoryGraph.remove_block(row, entry, snapshot)
		if operation == "Copy": return StoryGraph.move_block(row, entry, entry.end_line, entry.indent, snapshot, true)
		var siblings: Array[Dictionary] = []
		for candidate: Dictionary in entries:
			if candidate.parent == entry.parent and candidate.node.kind not in ["choices", "branch", "outcome"]: siblings.append(candidate)
		var index := siblings.find(entry)
		if index < 0: return "Choose a movable block."
		var target: int = int(siblings[index - 1].line) if operation == "↑" and index > 0 else int(siblings[index + 1].end_line) if operation == "↓" and index + 1 < siblings.size() else -1
		if target < 0: return "This block is already at the edge of its group."
		return StoryGraph.move_block(row, entry, target, entry.indent, snapshot))

func _perform(label: String, operation: Callable) -> void:
	if row.is_empty() or row.doc.text != snapshot:
		problem.emit("This story changed. Reopen it before editing.")
		return
	var error := workspace.transaction(label, func() -> String:
		var result: String = operation.call()
		if not result.is_empty(): return result
		var parsed := FscParser.parse(row.doc.text, row.doc.path)
		if not parsed.ok(): return str(parsed.diagnostics[0].message)
		return "")
	if not error.is_empty():
		problem.emit(error)
		return
	refresh()
	changed.emit(row)

func _build_dialogs() -> void:
	edit_dialog = ConfirmationDialog.new()
	edit_dialog.title = "Write a passage"
	edit_dialog.dialog_hide_on_ok = false
	var body := VBoxContainer.new()
	body.custom_minimum_size = Vector2(540, 360)
	edit_dialog.add_child(body)
	edit_text = TextEdit.new()
	edit_text.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
	edit_text.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_child(edit_text)
	edit_error = AuthoringLayout.label("", 14, true)
	body.add_child(edit_error)
	edit_dialog.confirmed.connect(func() -> void:
		if row.doc.text != snapshot:
			edit_error.text = "This story changed. Copy your text and reopen it."
			return
		var error := workspace.transaction("Write passage", func() -> String: return StoryGraph.set_prose_block(row, edit_entry.node, edit_original, edit_text.text))
		if not error.is_empty():
			edit_error.text = error
			return
		edit_dialog.hide()
		refresh()
		changed.emit(row))
	add_child(edit_dialog)
	condition_dialog = ConfirmationDialog.new()
	condition_dialog.title = "Only if…"
	condition_dialog.dialog_hide_on_ok = false
	condition_error = AuthoringLayout.label("", 14, true)
	condition_form = VBoxContainer.new()
	condition_form.custom_minimum_size.x = 420
	condition_dialog.add_child(condition_form)
	condition_form.add_child(condition_error)
	condition_dialog.confirmed.connect(func() -> void:
		var error := workspace.transaction("Wrap block in condition", func() -> String:
			var issue := StoryGraph.wrap_in_condition(row, condition_entry, condition.line(), snapshot)
			if not issue.is_empty(): return issue
			return workspace.require_condition(Condition.compile(condition.line())))
		if not error.is_empty():
			condition_error.text = error
			return
		condition_dialog.hide()
		refresh()
		changed.emit(row))
	add_child(condition_dialog)
	_build_action_dialog()

func _build_action_dialog() -> void:
	action_dialog = ConfirmationDialog.new()
	action_dialog.title = "What should happen?"
	action_dialog.dialog_hide_on_ok = false
	var body := VBoxContainer.new()
	body.custom_minimum_size = Vector2(450, 400)
	action_dialog.add_child(body)
	action_search = LineEdit.new()
	action_search.placeholder_text = "Search heal, trust, teleport…"
	body.add_child(action_search)
	action_list = ItemList.new()
	action_list.custom_minimum_size.y = 180
	body.add_child(action_list)
	action_slots = VBoxContainer.new()
	body.add_child(action_slots)
	action_error = AuthoringLayout.label("", 14, true)
	body.add_child(action_error)
	action_search.text_changed.connect(func(_text: String) -> void: _filter_actions())
	action_list.item_selected.connect(_choose_action)
	action_dialog.confirmed.connect(_apply_action)
	add_child(action_dialog)

func _open_actions() -> void:
	action_search.text = ""
	action_error.text = ""
	_filter_actions()
	action_dialog.popup_centered()

func _filter_actions() -> void:
	action_entries = BlockCatalog.entries(action_search.text)
	action_entries = action_entries.filter(func(entry: Dictionary) -> bool:
		if entry.id == "cancel_use": return row.def.type == "item" and row.get("script_field") == "use"
		if entry.id == "no_fight": return row.def.type == "creature" and row.get("script_field") == "encounter"
		if entry.id == "continue_moving": return row.def.type == "event" and "leaving " in row.doc.field_value(row.def, "found by")
		return true)
	action_list.clear()
	action_entry = {}
	for child: Node in action_slots.get_children():
		action_slots.remove_child(child)
		child.queue_free()
	for entry: Dictionary in action_entries: action_list.add_item(entry.category + " · " + entry.sentence)

func _choose_action(index: int) -> void:
	action_entry = action_entries[index]
	action_fields.clear()
	for child: Node in action_slots.get_children():
		action_slots.remove_child(child)
		child.queue_free()
	for slot: String in action_entry.slots:
		action_slots.add_child(AuthoringLayout.label(slot.capitalize(), 14))
		var control: Control
		if slot in ["item", "character", "location", "event", "quest", "condition", "form", "door", "feat"]:
			var content := ContentSlot.new()
			content.configure(workspace, slot)
			control = content
		elif slot in ["amount", "turns"]:
			var amount := SpinBox.new()
			amount.min_value = 0 if slot == "turns" else -100000
			amount.max_value = 100000
			amount.value = float(action_entry.defaults[action_entry.slots.find(slot)])
			control = amount
		else:
			var picker := OptionButton.new()
			var values: Array = []
			if slot == "value":
				var kind: String = {"remember": "flag", "record_time": "time"}.get(action_entry.id, "number")
				for key: String in workspace.preview_content().values:
					if workspace.preview_content().values[key].kind == kind: values.append(key)
			for value: String in values:
				if value not in [""]: picker.add_item(value)
			control = picker
		action_fields[slot] = control
		action_slots.add_child(control)
	if action_fields.has("stage") or action_fields.has("result"):
		var content_key := "quest" if action_fields.has("stage") else "event"
		var choice_key := "stage" if content_key == "quest" else "result"
		var content: ContentSlot = action_fields[content_key]
		content.item_selected.connect(func(_index: int) -> void:
			var picker: OptionButton = action_fields[choice_key]
			picker.clear()
			var db := workspace.preview_content()
			var options: Array = db.quests.get(content.value(), {}).get("stages", []) if content_key == "quest" else db._list(db.get_def("event", content.value()), "outcomes") if db.get_def("event", content.value()) != null else []
			for option: String in options: picker.add_item(option))

func _apply_action() -> void:
	if action_entry.is_empty():
		action_error.text = "Choose what should happen."
		return
	var values: Dictionary = {}
	for key: String in action_fields:
		var control: Control = action_fields[key]
		var value: String = control.value() if control is ContentSlot else str(int(control.value)) if control is SpinBox else control.get_item_text(control.selected) if control.selected >= 0 else ""
		if value.is_empty():
			action_error.text = "Choose " + key + "."
			return
		values[key] = value
	var line := BlockCatalog.render(action_entry, values)
	var error := workspace.transaction("Add " + BlockCatalog.sentence(line), func() -> String:
		if row.doc.text != snapshot: return "This story changed. Reopen the chooser."
		var issue := StoryGraph.add_primary_effect(row, line)
		if not issue.is_empty(): return issue
		for key: String in values:
			if key == "value": issue = workspace.require_value(values[key])
			elif key in PackWorkspace.types(): issue = workspace.require_content(key, values[key])
			if not issue.is_empty(): return issue
		return "")
	if not error.is_empty():
		action_error.text = error
		return
	action_dialog.hide()
	refresh()
	changed.emit(row)

func _focus_line(line: int) -> void:
	folded.clear()
	refresh()
	for margin: Node in blocks.get_children():
		if margin.get_child_count() == 0: continue
		var box := margin.get_child(0) as Control
		if box.get_meta("source_line", -1) == line:
			block_scroll.ensure_control_visible.call_deferred(box)
			box.grab_focus.call_deferred()
			break
