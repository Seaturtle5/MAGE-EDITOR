class_name StoryEditor
extends VBoxContainer
## The side editor: one story as a list of blocks an author can read, move,
## change and add to. Every change goes through exact source ranges.

signal changed(row: Dictionary)
signal problem(message: String)
signal validated
signal open_requested(type: String, id: String)
signal try_requested(row: Dictionary)

const OUTCOMES := {"won": "If the player wins", "lost": "If the player loses", "fled": "If the player flees", "won by seduction": "If the player wins by seduction", "lost by submitting": "If the player gives in"}
const STORY_NAMES := {"": "Story", "play": "Event story", "talk": "Conversation", "use": "Use story", "encounter": "Encounter", "victory": "If the creature wins", "defeated": "If the creature is defeated", "intro": "Opening", "enter": "On entering", "do": "What happens"}

var workspace: PackWorkspace
var row: Dictionary = {}
var snapshot := ""
var heading: Label
var blocks: VBoxContainer
var block_scroll: ScrollContainer
var show_line: CheckButton
var try_button: Button
var preview: StoryPreview
var folded: Dictionary = {}
var entries: Array[Dictionary] = []
var selection: Array[String] = []
var panels: Dictionary = {}
var badges: Dictionary = {}
var chooser: BlockChooser
var conditions: ConditionDialog
var response_dialog: ConfirmationDialog
var response_fields: Dictionary = {}
var explain: AcceptDialog
var pending: Callable
var check_timer: Timer
var checked_revision := -1
var writer: VBoxContainer
var writer_text: TextEdit
var writer_done: Callable
var focus_line := -1
var drawn_revision := -1
## Blocks copied last, for displays without a system clipboard.
static var clipboard := ""

func _ready() -> void:
	custom_minimum_size.x = 340
	var top := HBoxContainer.new()
	add_child(top)
	heading = AuthoringLayout.label("Choose a story", 18)
	heading.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	heading.autowrap_mode = TextServer.AUTOWRAP_OFF
	heading.clip_text = true
	top.add_child(heading)
	try_button = Button.new()
	try_button.text = "▶ Try it"
	try_button.theme_type_variation = "Ghost"
	try_button.tooltip_text = "Play this story in the real game, for the sample player of the preview. The game opens in its own window with its own saves."
	try_button.pressed.connect(func() -> void:
		if not row.is_empty(): try_requested.emit(row))
	top.add_child(try_button)
	show_line = CheckButton.new()
	show_line.text = "Show the line"
	show_line.tooltip_text = "Show the line of the content format under each block."
	show_line.button_pressed = EditorPrefs.read("authoring", "show_line", false)
	show_line.toggled.connect(func(enabled: bool) -> void:
		EditorPrefs.write("authoring", "show_line", enabled)
		refresh())
	top.add_child(show_line)
	var split := VSplitContainer.new()
	split.size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_child(split)
	block_scroll = ScrollContainer.new()
	block_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	block_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	block_scroll.custom_minimum_size.y = 220
	split.add_child(block_scroll)
	blocks = VBoxContainer.new()
	blocks.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	blocks.add_theme_constant_override("separation", 5)
	block_scroll.add_child(blocks)
	preview = StoryPreview.new()
	preview.custom_minimum_size.y = 170
	split.add_child(preview)
	preview.line_selected.connect(_focus_line)
	preview.rendered.connect(_show_badges)
	chooser = BlockChooser.new()
	add_child(chooser)
	chooser.chosen.connect(func(line: String, keep_open: bool) -> void:
		if pending.is_valid(): pending.call(line, keep_open))
	conditions = ConditionDialog.new()
	add_child(conditions)
	conditions.applied.connect(func(condition: String) -> void:
		if pending.is_valid(): pending.call(condition, false))
	explain = AcceptDialog.new()
	explain.title = "About this block"
	add_child(explain)
	_build_response_dialog()
	check_timer = Timer.new()
	check_timer.one_shot = true
	check_timer.wait_time = 0.3
	check_timer.timeout.connect(func() -> void:
		# With very many packs loaded the full check waits for the Check button.
		if workspace.heavy(): workspace.check_working()
		else: workspace.validate_buffers()
		checked_revision = workspace.revision
		refresh()
		validated.emit())
	add_child(check_timer)

func show_story(value: PackWorkspace, selected: Dictionary) -> void:
	var same: bool = not (row.is_empty() or selected.is_empty() or row.doc.path != selected.doc.path or row.def.id != selected.def.id or row.get("script_field", "") != selected.get("script_field", ""))
	# Already drawn for this very state of the pack: nothing to do.
	if same and workspace == value and drawn_revision == value.revision and writer == null: return
	if not same:
		folded.clear()
		selection.clear()
	workspace = value
	row = selected
	refresh()

static func story_name(story: Dictionary) -> String:
	var key: String = story.get("script_field", "")
	if key.is_empty() and story.def.type not in ["scene", "text", "menu"]: key = StoryBlocks.script_key(story)
	if story.def.type == "menu" and not story.has("script_field"): return "Conversation"
	return STORY_NAMES.get(key, AuthoringCatalog.INTERACTIONS.get(key, [key.capitalize()])[0])

func refresh() -> void:
	if blocks == null or workspace == null: return
	drawn_revision = workspace.revision
	writer = null
	AuthoringLayout.clear(blocks)
	panels.clear()
	badges.clear()
	entries = []
	if not row.is_empty():
		var current := workspace.find_row(row.doc.path, row.def.type, row.def.id, row.def.mode, row.get("ordinal", 0))
		if not current.is_empty() and row.has("script_field"): current.script_field = row.script_field
		row = current
	try_button.visible = not row.is_empty() and Playtest.problem().is_empty() and not Playtest.story_id(row).is_empty()
	if row.is_empty():
		heading.text = "Choose a story"
		blocks.add_child(AuthoringLayout.label("Choose a story card on the board, or an entry in the library, to see its blocks here.", 15, true))
		preview.show_story(workspace, row)
		return
	snapshot = row.doc.text
	heading.text = Wording.title(row) + " › " + story_name(row)
	heading.tooltip_text = heading.text
	entries = StoryGraph.structure(row)
	selection = selection.filter(func(key: String) -> bool: return not _entry(key).is_empty())
	if not row.doc.writable:
		blocks.add_child(AuthoringLayout.label("This story belongs to the pack “%s” and cannot be changed here. Blocks can still be copied." % row.pack, 13, true))
	elif entries.is_empty():
		blocks.add_child(AuthoringLayout.label("Nothing happens here yet. Add the first block, or drop something from the library.", 14, true))
	_render("", blocks, "fight" in StoryBlocks.contexts(row))
	preview.show_story(workspace, row)
	if check_timer != null and checked_revision != workspace.revision: check_timer.start()
	if focus_line > 0: _focus_line.call_deferred(focus_line)

func _entry(key: String) -> Dictionary:
	for entry: Dictionary in entries:
		if entry.key == key: return entry
	return {}

func _siblings(entry: Dictionary) -> Array[Dictionary]:
	return StoryBlocks.children(entries, str(entry.parent)).filter(func(other: Dictionary) -> bool: return other.node.kind not in ["choices", "branch", "outcome"] or other.node.kind == entry.node.kind)

# ------------------------------------------------------------------ drawing

func _render(parent_key: String, host: VBoxContainer, in_fight: bool) -> void:
	var kids := StoryBlocks.children(entries, parent_key)
	var parent := _entry(parent_key)
	var closing: bool = not kids.is_empty() and kids[-1].node.kind in ["choices", "goto"] and not kids[-1].node.has("inline_field")
	for entry: Dictionary in kids:
		if closing and is_same(entry, kids[-1]): _add_row(host, parent, in_fight)
		_block(entry, host, in_fight)
	if not closing: _add_row(host, parent, in_fight)

func _block(entry: Dictionary, host: VBoxContainer, in_fight: bool) -> void:
	match str(entry.node.kind):
		"choices":
			host.add_child(AuthoringLayout.label("The player chooses:", 13, true))
			for response: Dictionary in StoryBlocks.children(entries, entry.key): _container(response, host, in_fight)
			if row.doc.writable:
				var add := _ghost("+ Response", "Add another response the player can choose.", "AddRow")
				add.pressed.connect(func() -> void: _insert({"line": entry.end_line, "indent": entry.indent}, "* New response", "Add a response"))
				host.add_child(add)
		"if":
			for branch: Dictionary in StoryBlocks.children(entries, entry.key): _container(branch, host, in_fight)
		"fight":
			_container(entry, host, true)
		_: _leaf(entry, host)

func _panel(entry: Dictionary, host: VBoxContainer, container: bool) -> VBoxContainer:
	var panel := DropPanel.new()
	panel.split = not container
	panel.theme_type_variation = "BlockSelected" if entry.key in selection else "Block"
	panel.focus_mode = Control.FOCUS_ALL
	panel.set_meta("source_line", entry.line)
	panel.accepts = func(data: Dictionary) -> bool:
		if not row.doc.writable: return false
		if data.get("mage_kind") == "block": return data.get("path") == row.doc.path and data.get("snapshot") == snapshot and data.get("key") != entry.key
		return not DragPayload.resolve(workspace, data).is_empty()
	panel.dropped.connect(func(data: Dictionary, upper: bool) -> void:
		var spot := StoryBlocks.end_spot(row, entries, entry) if container else StoryBlocks.before_spot(_unit(entry)) if upper else StoryBlocks.after_spot(_unit(entry))
		_dropped(data, spot))
	panel.gui_input.connect(_block_input.bind(entry))
	host.add_child(panel)
	panels[entry.key] = panel
	var body := VBoxContainer.new()
	body.add_theme_constant_override("separation", 3)
	panel.add_child(body)
	for diagnostic: Dictionary in workspace.diagnostics:
		if diagnostic.path == row.doc.path and int(diagnostic.line) == int(entry.line) and diagnostic.severity == "error":
			if entry.key not in selection: panel.theme_type_variation = "BlockProblem"
			var hint := AuthoringLayout.label("⚠ " + str(diagnostic.message), 13)
			hint.theme_type_variation = "ErrorLabel"
			body.add_child(hint)
	return body

func _bar(entry: Dictionary, body: VBoxContainer, icon: String) -> HBoxContainer:
	var bar := HBoxContainer.new()
	bar.add_theme_constant_override("separation", 6)
	body.add_child(bar)
	var unit := _unit(entry)
	var movable: bool = row.doc.writable and not unit.node.has("inline_field") and unit.node.kind not in ["outcome", "choices"] and (entry.node.kind != "branch" or is_same(_first_branch(unit), entry))
	var handle := BlockHandle.new()
	handle.text = "⠿"
	handle.theme_type_variation = "Ghost"
	handle.disabled = not movable
	handle.focus_mode = Control.FOCUS_NONE
	handle.tooltip_text = "Drag to move. Hold Ctrl to copy. The ⋯ menu moves blocks from the keyboard." if movable else "This part stays with its block."
	handle.payload = {"mage_kind": "block", "path": row.doc.path, "snapshot": snapshot, "key": unit.key}
	bar.add_child(handle)
	var symbol := Label.new()
	symbol.text = icon
	symbol.custom_minimum_size.x = 22
	bar.add_child(symbol)
	return bar

func _finish(entry: Dictionary, body: VBoxContainer, bar: HBoxContainer) -> void:
	var more := _ghost("⋯", "More: edit, duplicate, move, wrap in a condition, remove, explain.")
	more.pressed.connect(func() -> void: _open_menu(entry, more))
	bar.add_child(more)
	if show_line.button_pressed:
		var raw := AuthoringLayout.label(StoryGraph._lines(row.doc)[int(entry.line) - 1].strip_edges(), 12)
		raw.theme_type_variation = "CodeLabel"
		body.add_child(raw)

func _ghost(text: String, tooltip: String = "", variation: String = "Ghost") -> Button:
	var button := Button.new()
	button.text = text
	button.tooltip_text = tooltip
	button.theme_type_variation = variation
	button.focus_mode = Control.FOCUS_NONE
	return button

func _link(text: String, action: Callable, tooltip: String = "") -> Label:
	var label := AuthoringLayout.label(text, 15)
	label.theme_type_variation = "AccentLabel"
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.mouse_filter = Control.MOUSE_FILTER_STOP
	label.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	label.tooltip_text = tooltip
	label.gui_input.connect(func(input: InputEvent) -> void:
		if input is InputEventMouseButton and input.pressed and input.button_index == MOUSE_BUTTON_LEFT and row.doc.writable: action.call())
	return label

func _plain(text: String, muted: bool = false) -> Label:
	var label := AuthoringLayout.label(text, 15, muted)
	label.autowrap_mode = TextServer.AUTOWRAP_OFF
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return label

## The entry that moves as one: an "if" for its first branch, else the entry itself.
func _unit(entry: Dictionary) -> Dictionary:
	return _entry(str(entry.parent)) if entry.node.kind == "branch" else entry

func _first_branch(block: Dictionary) -> Dictionary:
	var branches := StoryBlocks.children(entries, str(block.key))
	return branches[0] if not branches.is_empty() else {}

func _leaf(entry: Dictionary, host: VBoxContainer) -> void:
	var node: Dictionary = entry.node
	var writable: bool = row.doc.writable
	var body := _panel(entry, host, false)
	match str(node.kind):
		"text":
			var bar := _bar(entry, body, "💬")
			var prose := RichTextLabel.new()
			prose.bbcode_enabled = not show_line.button_pressed
			prose.fit_content = true
			prose.scroll_active = false
			prose.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			prose.selection_enabled = false
			prose.add_theme_font_override("normal_font", EditorTheme.font("Literata.ttf"))
			prose.add_theme_font_override("italics_font", EditorTheme.font("Literata-Italic.ttf"))
			prose.add_theme_font_override("bold_font", EditorTheme.font("Literata.ttf"))
			prose.add_theme_font_size_override("normal_font_size", 15)
			prose.add_theme_font_size_override("italics_font_size", 15)
			prose.add_theme_font_size_override("bold_font_size", 15)
			prose.add_theme_color_override("default_color", EditorTheme.color("text"))
			prose.text = str(node.text) if show_line.button_pressed else Wording.marked(str(node.text), workspace)
			prose.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			prose.mouse_filter = Control.MOUSE_FILTER_PASS
			prose.tooltip_text = "Double-click to write here. Coloured words change with the game: a name, a condition, one of several versions."
			bar.add_child(prose)
			if writable:
				var write := _ghost("✎", "Write (or double-click the text)")
				write.pressed.connect(func() -> void: _write(entry))
				bar.add_child(write)
			_finish(entry, body, bar)
		"effect":
			var read := BlockCatalog.read_line(str(node.text))
			var bar := _bar(entry, body, str(read.entry.icon) if not read.is_empty() else "🔒")
			if read.is_empty():
				var kept := AuthoringLayout.label("Kept as written: " + str(node.text), 14, true)
				kept.size_flags_horizontal = Control.SIZE_EXPAND_FILL
				kept.tooltip_text = "The editor cannot show this action as a sentence yet. It is kept exactly as it is and still runs in the game."
				bar.add_child(kept)
			else:
				var view := SentenceView.new()
				view.event = row.def.id if row.def.type == "event" else ""
				view.show_sentence(workspace, read.entry, read.slots, writable)
				if read.quiet: view.words("(without telling the player)", "MutedLabel")
				view.slot_changed.connect(func(name: String, value: String) -> void:
					var slots: Dictionary = read.slots.duplicate()
					slots[name] = value
					_set_action(entry, read.entry, slots, read.quiet))
				bar.add_child(view)
			_finish(entry, body, bar)
		"goto", "play":
			var target: String = str(node.target) if node.kind == "goto" else StoryGraph.play_target(node)
			var bar := _bar(entry, body, {"back": "↩", "end": "⏹"}.get(target, "➜") if node.kind == "goto" else "▶")
			var flow := HFlowContainer.new()
			flow.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			bar.add_child(flow)
			flow.add_child(_plain("Then" if node.kind == "goto" else "Play"))
			var picker := _story_picker(node.kind == "goto")
			picker.set_value(target)
			picker.disabled = not writable or (node.kind == "play" and target.is_empty())
			picker.picked.connect(func(next: String) -> void:
				_perform("Change where this leads", func() -> String:
					return StoryBlocks.set_line(row, entry, "-> " + next, snapshot) if node.kind == "goto" else StoryGraph.set_play_target(row, node, next)))
			flow.add_child(picker)
			if node.kind == "play":
				var rest := str(node.target).substr(target.length()).strip_edges()
				flow.add_child(_plain((rest + ", " if not rest.is_empty() else "") + "then come back", true))
			if not target.is_empty() and target not in ["back", "end"]:
				var jump := _ghost("↗", "Open that story")
				jump.pressed.connect(func() -> void: open_requested.emit("scene", target))
				bar.add_child(jump)
			_finish(entry, body, bar)
		"show":
			var bar := _bar(entry, body, "🖼")
			var flow := HFlowContainer.new()
			flow.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			bar.add_child(flow)
			flow.add_child(_plain("Show the picture"))
			var picture := SlotControl.make(workspace, {"name": "image", "kind": "image", "default": "", "hidden": false, "optional": false}, str(node.image) if not str(node.image).is_empty() else "nothing")
			picture.picker.disabled = not writable
			picture.edited.connect(func() -> void: _perform("Change the picture", func() -> String: return StoryBlocks.set_line(row, entry, "show " + picture.value(), snapshot)))
			flow.add_child(picture)
			_finish(entry, body, bar)
		"page_break":
			var bar := _bar(entry, body, "⏸")
			var pause := _plain("Pause until the player continues", true)
			pause.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			bar.add_child(pause)
			_finish(entry, body, bar)
		_:
			var bar := _bar(entry, body, "🔒")
			var kept := _plain("Kept block", true)
			kept.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			bar.add_child(kept)
			_finish(entry, body, bar)

func _story_picker(with_endings: bool) -> PickerButton:
	var picker := PickerButton.new()
	picker.placeholder = "Choose a story…"
	picker.workspace = workspace
	picker.drop_kinds = ["scene", "menu"]
	picker.allow_typing = true
	picker.label_for = func(id: String) -> String: return {"back": "go back to the list of responses", "end": "the story ends here"}.get(id, ("continue with " if with_endings else "") + BlockCatalog.content_label("scene", id, workspace))
	picker.options = func() -> Array:
		var result: Array = []
		if with_endings:
			result.append({"value": "back", "label": "go back to the list of responses"})
			result.append({"value": "end", "label": "the story ends here"})
		for other: Dictionary in workspace.rows:
			if other.def.type in ["scene", "menu"] and other.def.mode != "extend":
				result.append({"value": other.def.id, "label": Wording.title(other), "detail": "" if other.doc.writable else str(other.pack)})
		return result
	return picker

func _container(entry: Dictionary, host: VBoxContainer, in_fight: bool) -> void:
	var node: Dictionary = entry.node
	var writable: bool = row.doc.writable
	var body := _panel(entry, host, true)
	var kids := StoryBlocks.children(entries, entry.key)
	var closed: bool = folded.get(entry.key, false)
	var icon: String = {"response": "›", "fight": "⚔", "outcome": "⚑"}.get(node.kind, "◇")
	var bar := _bar(entry, body, icon)
	var fold := _ghost("▸" if closed else "▾", "Fold or unfold")
	fold.pressed.connect(func() -> void:
		folded[entry.key] = not closed
		refresh())
	bar.add_child(fold)
	bar.move_child(fold, 1)
	match str(node.kind):
		"response":
			var column := VBoxContainer.new()
			column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			column.add_theme_constant_override("separation", 2)
			bar.add_child(column)
			var label := _link("“" + str(node.label) + "”", func() -> void: _edit_response(entry), "Change this response")
			label.theme_type_variation = "StoryLabel"
			column.add_child(label)
			var notes: Array[String] = []
			if not str(node.get("description", "")).is_empty(): notes.append(str(node.description))
			if not str(node.get("condition", "")).is_empty(): notes.append("Only if " + _lower(BlockCatalog.condition_sentence(str(node.condition), workspace)))
			if node.get("then_leave", false): notes.append("Then the conversation ends")
			if node.get("always_shown", false): notes.append("Shown greyed out when it cannot be chosen")
			if not notes.is_empty(): column.add_child(AuthoringLayout.label(" · ".join(notes), 13, true))
		"branch":
			var words: String = str(node.get("condition", ""))
			var first: bool = is_same(_first_branch(_unit(entry)), entry)
			if words.is_empty():
				var otherwise := _plain("Otherwise")
				otherwise.size_flags_horizontal = Control.SIZE_EXPAND_FILL
				bar.add_child(otherwise)
			else:
				bar.add_child(_plain("Only if" if first else "Otherwise, if", true))
				bar.add_child(_link(_lower(BlockCatalog.condition_sentence(words, workspace)), func() -> void: _edit_condition(entry), "Change this condition"))
			var badge := Label.new()
			badge.add_theme_font_size_override("font_size", 12)
			bar.add_child(badge)
			badges[int(entry.line)] = badge
		"fight":
			var flow := HFlowContainer.new()
			flow.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			bar.add_child(flow)
			flow.add_child(_plain("Fight"))
			if node.has("creatures"): flow.add_child(_plain(", ".join(node.creatures.map(func(id: String) -> String: return BlockCatalog.content_label("creature", id, workspace))) + ", one after another"))
			else:
				var creature := SlotControl.make(workspace, {"name": "creature", "kind": "creature", "default": "", "hidden": false, "optional": false}, str(node.creature))
				creature.picker.disabled = not writable
				creature.edited.connect(func() -> void: _perform("Change the creature to fight", func() -> String:
					var line := StoryGraph._lines(row.doc)[int(entry.line) - 1].strip_edges()
					return StoryBlocks.set_line(row, entry, "fight " + creature.value() + line.substr(6 + str(node.creature).length()), snapshot)))
				flow.add_child(creature)
				if not str(node.get("variant", "")).is_empty(): flow.add_child(_plain("(" + str(node.variant) + ")", true))
				if node.has("times"): flow.add_child(_plain(str(node.times) + " times in a row", true))
		"outcome":
			var title := _plain(OUTCOMES.get(str(node.label), str(node.label).capitalize()))
			title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			bar.add_child(title)
	if closed: bar.add_child(_plain("%d inside" % kids.size(), true))
	_finish(entry, body, bar)
	if closed: return
	var nest := MarginContainer.new()
	nest.add_theme_constant_override("margin_left", 14)
	body.add_child(nest)
	var inner := VBoxContainer.new()
	inner.add_theme_constant_override("separation", 5)
	nest.add_child(inner)
	if node.kind == "fight":
		for outcome: Dictionary in kids: _container(outcome, inner, true)
	else: _render(entry.key, inner, in_fight)

static func _lower(text: String) -> String:
	return text.left(1).to_lower() + text.substr(1)

class AddHere extends HBoxContainer:
	signal dropped(data: Dictionary)
	var accepts: Callable

	func _can_drop_data(_position: Vector2, data: Variant) -> bool:
		return data is Dictionary and accepts.is_valid() and accepts.call(data)

	func _drop_data(_position: Vector2, data: Variant) -> void:
		dropped.emit(data)

func _add_row(host: VBoxContainer, parent: Dictionary, in_fight: bool) -> void:
	if not row.doc.writable: return
	var bar := AddHere.new()
	bar.add_theme_constant_override("separation", 4)
	bar.accepts = func(data: Dictionary) -> bool:
		if data.get("mage_kind") == "block": return data.get("path") == row.doc.path and data.get("snapshot") == snapshot
		return not DragPayload.resolve(workspace, data).is_empty()
	bar.dropped.connect(func(data: Dictionary) -> void: _dropped(data, StoryBlocks.end_spot(row, entries, parent)))
	host.add_child(bar)
	var spot := func() -> Dictionary: return StoryBlocks.end_spot(row, entries, parent)
	var text := _ghost("+ Text", "Add speech or narration here (Ctrl+Enter).", "AddRow")
	text.pressed.connect(func() -> void: _write({}, spot.call(), bar))
	bar.add_child(text)
	var action := _ghost("+ Action", "Add something that happens: give an item, change a counter, move the player…", "AddRow")
	action.pressed.connect(func() -> void: _choose_action(spot.call(), in_fight))
	bar.add_child(action)
	var more := _ghost("+ More ▾", "Conditions, responses, links to other stories, pictures, pauses and fights.", "AddRow")
	more.pressed.connect(func() -> void: _open_add_menu(more, spot.call(), in_fight))
	bar.add_child(more)
	bar.set_meta("spot", spot)

# ----------------------------------------------------------------- changing

func _perform(label: String, operation: Callable) -> bool:
	if row.is_empty() or row.doc.text != snapshot:
		problem.emit("This story changed. Choose it again before editing.")
		return false
	var error := workspace.transaction(label, func() -> String:
		var result: String = operation.call()
		if not result.is_empty(): return result
		var parsed := FscParser.parse(row.doc.text, row.doc.path)
		if not parsed.ok(): return str(parsed.diagnostics[0].message)
		return "")
	if not error.is_empty():
		problem.emit(error)
		return false
	refresh()
	changed.emit(row)
	return true

func _insert(spot: Dictionary, content: String, label: String) -> bool:
	return _perform(label, func() -> String: return StoryBlocks.insert(row, spot, content, snapshot))

func _require(line: String) -> String:
	var read := BlockCatalog.read_line(line)
	if read.is_empty(): return ""
	for slot: Dictionary in read.entry.slots:
		var value: String = read.slots.get(slot.name, "")
		if value.is_empty(): continue
		var issue := ""
		if str(slot.kind).begins_with("value"): issue = workspace.require_value(value)
		elif slot.kind in PackWorkspace.types(): issue = workspace.require_content(slot.kind, value)
		if not issue.is_empty(): return issue
	return ""

func _set_action(entry: Dictionary, candidate: Dictionary, slots: Dictionary, quiet: bool) -> void:
	var line := BlockCatalog.action_line(candidate, slots, quiet)
	var compiled := Effect.compile(line)
	if compiled.has("error"):
		problem.emit("The engine cannot read this: " + str(compiled.error))
		return
	_perform("Change “" + BlockCatalog.sentence(line, workspace) + "”", func() -> String:
		var issue := StoryBlocks.set_line(row, entry, "~ " + line, snapshot)
		return issue if not issue.is_empty() else _require(line))

func _choose_action(spot: Dictionary, in_fight: bool, offers: Array = []) -> void:
	var place := [spot]
	pending = func(line: String, keep_open: bool) -> void:
		var before: int = row.doc.text.count("\n")
		var done := _perform("Add “" + BlockCatalog.sentence(line, workspace) + "”", func() -> String:
			var issue := StoryBlocks.insert(row, place[0], "~ " + line, snapshot)
			return issue if not issue.is_empty() else _require(line))
		# "Add & next" keeps adding below what was just added.
		if done and keep_open and place[0].has("line"): place[0] = {"line": int(place[0].line) + row.doc.text.count("\n") - before, "indent": place[0].indent}
		elif done and keep_open: place[0] = StoryBlocks.end_spot(row, entries, {})
	chooser.open(workspace, "action", StoryBlocks.contexts(row, in_fight), offers, {}, row.def.id if row.def.type == "event" else "")

func _edit_action(entry: Dictionary, in_fight: bool) -> void:
	var read := BlockCatalog.read_line(str(entry.node.text))
	if read.is_empty(): return
	pending = func(line: String, _keep_open: bool) -> void:
		_perform("Change “" + BlockCatalog.sentence(line, workspace) + "”", func() -> String:
			var issue := StoryBlocks.set_line(row, entry, "~ " + line, snapshot)
			return issue if not issue.is_empty() else _require(line))
	chooser.open(workspace, "action", StoryBlocks.contexts(row, in_fight), [], read, row.def.id if row.def.type == "event" else "")

func _ask_condition(text: String, title: String, then: Callable) -> void:
	pending = func(condition: String, _keep_open: bool) -> void: then.call(condition)
	conditions.open(workspace, text, StoryBlocks.contexts(row), row.def.id if row.def.type == "event" else "", title)

func _edit_condition(entry: Dictionary) -> void:
	_ask_condition(str(entry.node.condition), "Change the condition", func(condition: String) -> void:
		_perform("Change a condition", func() -> String:
			var issue := StoryGraph.set_branch_condition(row, entry.node, condition)
			return issue if not issue.is_empty() else workspace.require_condition(Condition.compile(condition))))

func _wrap(targets: Array[Dictionary]) -> void:
	_ask_condition("", "Only if…", func(condition: String) -> void:
		_perform("Put %s inside “Only if”" % ("a block" if targets.size() == 1 else "%d blocks" % targets.size()), func() -> String:
			var ordered := targets.duplicate()
			ordered.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return int(a.line) < int(b.line))
			for index in range(1, ordered.size()):
				if int(ordered[index].line) != int(ordered[index - 1].end_line): return "Choose blocks that follow each other."
			var whole := {"node": {"kind": "group"}, "line": ordered[0].line, "end_line": ordered[-1].end_line, "indent": ordered[0].indent}
			var issue := StoryGraph.wrap_in_condition(row, whole, condition, snapshot)
			return issue if not issue.is_empty() else workspace.require_condition(Condition.compile(condition))))

func _dropped(data: Dictionary, spot: Dictionary) -> void:
	if data.get("mage_kind") == "block":
		var moving: Array[Dictionary] = []
		for key: String in (selection if data.key in selection else [data.key]):
			var entry := _entry(key)
			if not entry.is_empty(): moving.append(entry)
		if not spot.has("line"):
			problem.emit("Add a first block here before moving others in.")
			return
		_perform("Copy blocks" if data.get("copy", false) else "Move blocks", func() -> String: return StoryBlocks.move_many(row, moving, int(spot.line), str(spot.indent), snapshot, data.get("copy", false)))
		return
	var content := DragPayload.resolve(workspace, data)
	if content.is_empty(): return
	var offers := drop_offers(content)
	if offers.is_empty():
		problem.emit("Nothing can be done with " + Wording.title(content) + " inside a story yet. Drop it on a matching chip instead.")
		return
	var menu := PopupMenu.new()
	for index in offers.size(): menu.add_item(str(offers[index].label), index)
	menu.add_separator()
	menu.add_item("Something else with " + Wording.title(content) + "…", 1000)
	menu.id_pressed.connect(func(id: int) -> void:
		if id == 1000:
			_choose_action(spot, false, offers.filter(func(offer: Dictionary) -> bool: return offer.has("entry")))
			return
		var offer: Dictionary = offers[id]
		if offer.has("content"): _insert(spot, str(offer.content), str(offer.label))
		elif offer.get("complete", false):
			var line := BlockCatalog.action_line(offer.entry, chooser._starting(offer.entry, offer.slots))
			_perform(str(offer.label), func() -> String:
				var issue := StoryBlocks.insert(row, spot, "~ " + line, snapshot)
				return issue if not issue.is_empty() else _require(line))
		else:
			_choose_action(spot, false, [offer])
			chooser._show_form(offer.entry, offer.slots, false))
	menu.popup_hide.connect(menu.queue_free)
	add_child(menu)
	menu.popup(Rect2i(DisplayServer.mouse_get_position(), Vector2i.ZERO))

## What dropping a piece of library content into a story can mean.
func drop_offers(content: Dictionary) -> Array:
	var id: String = content.def.id
	var name := Wording.title(content)
	var offers: Array = []
	var catalog := func(entry_id: String, slots: Dictionary, complete: bool) -> void:
		var candidate := BlockCatalog.by_id(entry_id)
		offers.append({"entry": candidate, "slots": slots, "complete": complete, "label": BlockCatalog.describe(candidate, chooser._starting(candidate, slots), workspace)})
	match str(content.def.type):
		"item":
			catalog.call("give", {"item": id}, true)
			catalog.call("take", {"item": id}, true)
		"location":
			catalog.call("go", {"place": id}, true)
			catalog.call("discover", {"place": id}, true)
			catalog.call("move", {"place": id}, false)
		"character":
			catalog.call("companion.add", {"who": id}, true)
			catalog.call("move", {"who": id}, false)
			catalog.call("trait.add", {"who": id}, false)
		"form":
			catalog.call("infect", {"form": id}, true)
			catalog.call("transform", {"form": id}, true)
		"creature":
			offers.append({"label": "Fight " + name, "content": "fight " + id + ":\n    won:\n    lost:"})
			catalog.call("infect", {"form": id}, true)
		"condition": catalog.call("condition", {"condition": id}, true)
		"event":
			catalog.call("activate.on", {"event": id}, true)
			catalog.call("resolve.other", {"event": id}, true)
			catalog.call("outcome_of", {"event": id}, false)
		"quest": catalog.call("quest", {"quest": id}, false)
		"feat": catalog.call("feat.add", {"feat": id}, true)
		"door":
			catalog.call("lock.unlock", {"door": id}, true)
			catalog.call("lock.lock", {"door": id}, true)
		"ending":
			catalog.call("trigger_ending", {"ending": id}, true)
			catalog.call("ending", {"ending": id}, true)
		"image": offers.append({"label": "Show the picture " + name, "content": "show " + id})
		"scene", "menu":
			offers.append({"label": "Play " + name + ", then come back", "content": "play " + id})
			offers.append({"label": "Continue with " + name, "content": "-> " + id})
	return offers

# -------------------------------------------------------------------- menus

func _targets(entry: Dictionary) -> Array[Dictionary]:
	var unit := _unit(entry)
	var chosen: Array[Dictionary] = []
	if unit.key in selection:
		for key: String in selection:
			var other := _entry(key)
			if not other.is_empty(): chosen.append(other)
	else: chosen.append(unit)
	return chosen

func _open_menu(entry: Dictionary, anchor: Control) -> void:
	var menu := PopupMenu.new()
	var actions: Array[Callable] = []
	var add := func(label: String, action: Callable, enabled: bool = true) -> void:
		menu.add_item(label, actions.size())
		menu.set_item_disabled(menu.item_count - 1, not enabled)
		actions.append(action)
	var node: Dictionary = entry.node
	var unit := _unit(entry)
	var writable: bool = row.doc.writable
	var in_fight: bool = "fight" in StoryBlocks.contexts(row) or _inside_fight(entry)
	var siblings := _siblings(unit)
	var index := siblings.find(unit)
	var movable: bool = writable and not unit.node.has("inline_field") and unit.node.kind not in ["outcome", "choices"]
	var whole: bool = node.kind != "branch" or is_same(_first_branch(unit), entry)
	match str(node.kind):
		"text": add.call("✎  Write…", func() -> void: _write(entry), writable)
		"effect": add.call("✎  Change every part…", func() -> void: _edit_action(entry, in_fight), writable and not BlockCatalog.read_line(str(node.text)).is_empty())
		"response": add.call("✎  Change the response…", func() -> void: _edit_response(entry), writable)
		"branch":
			if not str(node.get("condition", "")).is_empty(): add.call("✎  Change the condition…", func() -> void: _edit_condition(entry), writable)
			if whole:
				add.call("+  Add “Otherwise, if…”", func() -> void:
					_ask_condition("", "Otherwise, if…", func(condition: String) -> void:
						_perform("Add “Otherwise, if”", func() -> String: return StoryBlocks.add_branch(row, entries, unit, condition, snapshot))), writable)
				add.call("+  Add “Otherwise”", func() -> void: _perform("Add “Otherwise”", func() -> String: return StoryBlocks.add_branch(row, entries, unit, "", snapshot)), writable and unit.node["else"] == null)
				add.call("Remove the condition, keep what is inside", func() -> void: _perform("Remove a condition", func() -> String: return StoryBlocks.unwrap(row, entries, unit, snapshot)), writable and StoryBlocks.children(entries, unit.key).size() == 1)
			else: add.call("Remove this part", func() -> void: _perform("Remove part of a condition", func() -> String: return StoryBlocks.remove_branch(row, entries, entry, snapshot)), writable)
		"fight":
			for outcome: String in OUTCOMES:
				if not node.outcomes.has(outcome): add.call("+  Add “" + str(OUTCOMES[outcome]) + "”", func() -> void: _perform("Add a fight result", func() -> String: return StoryBlocks.add_outcome(row, entries, entry, outcome, snapshot)), writable)
	if whole and node.kind != "outcome":
		menu.add_separator()
		add.call("Add above…", func() -> void: _open_add_menu(anchor, StoryBlocks.before_spot(unit), in_fight), movable)
		add.call("Duplicate", func() -> void: _perform("Duplicate blocks", func() -> String:
			var group := _targets(entry)
			var last: Dictionary = group[0]
			for other: Dictionary in group:
				if int(other.end_line) > int(last.end_line): last = other
			return StoryBlocks.move_many(row, group, int(last.end_line), str(unit.indent), snapshot, true)), movable)
		add.call("Move up", func() -> void: _perform("Move a block up", func() -> String: return StoryBlocks.move_many(row, [unit], int(siblings[index - 1].line), str(unit.indent), snapshot)), movable and index > 0)
		add.call("Move down", func() -> void: _perform("Move a block down", func() -> String: return StoryBlocks.move_many(row, [unit], int(siblings[index + 1].end_line), str(unit.indent), snapshot)), movable and index >= 0 and index + 1 < siblings.size())
		if node.kind != "response": add.call("Only if…  (put inside a condition)", func() -> void: _wrap(_targets(entry)), movable)
		menu.add_separator()
		add.call("Copy", func() -> void: _copy(_targets(entry)))
		add.call("Cut", func() -> void: _cut(_targets(entry)), movable)
		add.call("Paste below", func() -> void: _paste(StoryBlocks.after_spot(unit)), writable and not unit.node.has("inline_field"))
		menu.add_separator()
		add.call("Remove", func() -> void: _remove(_targets(entry)), movable)
	menu.add_separator()
	add.call("Explain", func() -> void: _explain(entry))
	menu.id_pressed.connect(func(id: int) -> void: actions[id].call())
	menu.popup_hide.connect(menu.queue_free)
	add_child(menu)
	menu.popup(Rect2i(Vector2i(anchor.get_screen_position()) + Vector2i(0, int(anchor.size.y)), Vector2i.ZERO))

func _inside_fight(entry: Dictionary) -> bool:
	var current := entry
	while not current.is_empty():
		if current.node.kind in ["fight", "outcome"]: return true
		current = _entry(str(current.parent))
	return false

func _open_add_menu(anchor: Control, spot: Dictionary, in_fight: bool) -> void:
	var menu := PopupMenu.new()
	var actions: Array[Callable] = []
	var add := func(label: String, action: Callable) -> void:
		menu.add_item(label, actions.size())
		actions.append(action)
	add.call("💬  Text: speech or narration", func() -> void: _write({}, spot))
	add.call("⚡  Action: something happens…", func() -> void: _choose_action(spot, in_fight))
	add.call("◇  Only if…: a condition with blocks inside", func() -> void:
		_ask_condition("", "Only if…", func(condition: String) -> void:
			_perform("Add “Only if”", func() -> String:
				var issue := StoryBlocks.insert(row, spot, "if " + condition + ":", snapshot)
				return issue if not issue.is_empty() else workspace.require_condition(Condition.compile(condition)))))
	add.call("›  Response: something the player can choose", func() -> void:
		if row.def.type == "menu" and not row.has("script_field") and not spot.has("line"): _perform("Add a response", func() -> String: return StoryGraph.add_choice(row))
		else: _insert(spot, "* New response", "Add a response"))
	menu.add_separator()
	add.call("➜  Continue with another story…", func() -> void: _pick_story(anchor, true, func(target: String) -> void: _insert(spot, "-> " + target, "Add a link to a story")))
	add.call("▶  Play a story, then come back…", func() -> void: _pick_story(anchor, false, func(target: String) -> void: _insert(spot, "play " + target, "Play a story")))
	add.call("🖼  Show a picture…", func() -> void:
		var picture := SlotControl.make(workspace, {"name": "image", "kind": "image", "default": "", "hidden": false, "optional": false}, "")
		picture.hide()
		add_child(picture)
		picture.edited.connect(func() -> void:
			_insert(spot, "show " + picture.value(), "Show a picture")
			picture.queue_free())
		picture.picker.open(DisplayServer.mouse_get_position()))
	add.call("⏸  Pause until the player continues", func() -> void: _insert(spot, "---", "Add a pause"))
	add.call("⚔  Fight a creature…", func() -> void:
		var creature := SlotControl.make(workspace, {"name": "creature", "kind": "creature", "default": "", "hidden": false, "optional": false}, "")
		creature.hide()
		add_child(creature)
		creature.edited.connect(func() -> void:
			_insert(spot, "fight " + creature.value() + ":\n    won:\n    lost:", "Add a fight")
			creature.queue_free())
		creature.picker.open(DisplayServer.mouse_get_position()))
	menu.add_separator()
	add.call("Paste", func() -> void: _paste(spot))
	menu.id_pressed.connect(func(id: int) -> void: actions[id].call())
	menu.popup_hide.connect(menu.queue_free)
	add_child(menu)
	menu.popup(Rect2i(Vector2i(anchor.get_screen_position()) + Vector2i(0, int(anchor.size.y)), Vector2i.ZERO))

func _pick_story(_anchor: Control, with_endings: bool, then: Callable) -> void:
	var picker := _story_picker(with_endings)
	picker.hide()
	add_child(picker)
	picker.picked.connect(func(target: String) -> void:
		then.call(target)
		picker.queue_free())
	picker.open(DisplayServer.mouse_get_position())

func _explain(entry: Dictionary) -> void:
	var node: Dictionary = entry.node
	var text := ""
	match str(node.kind):
		"text": text = "Text the player reads: speech or narration. Double-click to write. Square brackets hold words that change, such as a name."
		"effect":
			var read := BlockCatalog.read_line(str(node.text))
			text = (BlockCatalog.sentence(str(node.text), workspace) + "\n\n" + str(read.entry.help)) if not read.is_empty() else "An action the editor cannot show as a sentence yet. It is kept exactly as written and still runs in the game."
		"branch": text = "The blocks inside happen only when the condition holds. “Otherwise” parts are tried in order when it does not."
		"response": text = "Something the player can choose. The blocks inside happen when it is chosen."
		"fight", "outcome": text = "A fight with the creature. Each result of the fight has its own blocks."
		"goto": text = "The story continues somewhere else and does not come back here."
		"play": text = "Another story plays, and then this one continues with the next block."
		"show": text = "Changes the picture shown with the story."
		"page_break": text = "The game waits here until the player continues."
	explain.dialog_text = text + "\n\nIn the content format, line %d:\n%s" % [int(entry.line), StoryGraph._lines(row.doc)[int(entry.line) - 1].strip_edges()]
	AuthoringLayout.popup(explain, Vector2i(520, 260))

# ---------------------------------------------------------------- clipboard

func _copy(targets: Array[Dictionary]) -> void:
	var ordered := targets.duplicate()
	ordered.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return int(a.line) < int(b.line))
	var parts: Array[String] = []
	for entry: Dictionary in ordered: parts.append(StoryBlocks.source(row, entry))
	clipboard = "\n".join(parts)
	if DisplayServer.has_feature(DisplayServer.FEATURE_CLIPBOARD): DisplayServer.clipboard_set(clipboard)

func _cut(targets: Array[Dictionary]) -> void:
	_copy(targets)
	_remove(targets)

func _paste(spot: Dictionary) -> void:
	var system := DisplayServer.clipboard_get() if DisplayServer.has_feature(DisplayServer.FEATURE_CLIPBOARD) else ""
	var text := (system if not system.strip_edges().is_empty() else clipboard).replace("\r\n", "\n").strip_edges(false, true)
	if text.strip_edges().is_empty():
		problem.emit("Nothing to paste. Copy a block first.")
		return
	var lines := text.split("\n")
	var common := 1000
	for line: String in lines:
		if not line.strip_edges().is_empty(): common = mini(common, StoryGraph._indent(line).length())
	var cleaned: Array[String] = []
	for line: String in lines: cleaned.append(line.substr(mini(common, line.length())))
	_insert(spot, "\n".join(cleaned), "Paste blocks")

func _remove(targets: Array[Dictionary]) -> void:
	_perform("Remove %s" % ("a block" if targets.size() == 1 else "%d blocks" % targets.size()), func() -> String:
		var ordered := targets.duplicate()
		ordered.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return int(a.line) > int(b.line))
		for entry: Dictionary in ordered:
			var issue := StoryGraph.remove_block(row, entry, row.doc.text)
			if not issue.is_empty(): return issue
		return "")

# ----------------------------------------------------------------- selection

func _block_input(input: InputEvent, entry: Dictionary) -> void:
	var unit := _unit(entry)
	if input is InputEventMouseButton and input.pressed:
		if input.button_index == MOUSE_BUTTON_RIGHT:
			_open_menu(entry, panels[entry.key])
			return
		if input.button_index != MOUSE_BUTTON_LEFT: return
		if input.double_click and entry.node.kind == "text" and row.doc.writable:
			_write(entry)
			return
		if input.ctrl_pressed or input.meta_pressed:
			if unit.key in selection: selection.erase(unit.key)
			else: selection.append(unit.key)
		elif input.shift_pressed and not selection.is_empty():
			var siblings := _siblings(unit)
			var from := siblings.find(_entry(selection[-1]))
			var to := siblings.find(unit)
			if from >= 0 and to >= 0:
				selection.clear()
				for index in range(mini(from, to), maxi(from, to) + 1): selection.append(siblings[index].key)
		else: selection = [unit.key]
		_show_selection()
		panels[entry.key].grab_focus()
	elif input is InputEventKey and input.pressed and not input.echo:
		var targets := _targets(entry)
		var command: bool = input.ctrl_pressed or input.meta_pressed
		if input.keycode == KEY_DELETE: _remove(targets)
		elif command and input.keycode == KEY_C: _copy(targets)
		elif command and input.keycode == KEY_X: _cut(targets)
		elif command and input.keycode == KEY_V: _paste(StoryBlocks.after_spot(unit))
		elif command and input.keycode == KEY_D: _perform("Duplicate a block", func() -> String: return StoryBlocks.move_many(row, [unit], int(unit.end_line), str(unit.indent), snapshot, true))
		elif command and input.keycode == KEY_ENTER: _write({}, StoryBlocks.after_spot(unit))
		elif input.keycode == KEY_ENTER and entry.node.kind == "text": _write(entry)
		elif input.keycode == KEY_ENTER and entry.node.kind == "effect": _edit_action(entry, _inside_fight(entry))
		elif input.alt_pressed and input.keycode in [KEY_UP, KEY_DOWN]:
			var siblings := _siblings(unit)
			var index := siblings.find(unit)
			var goal := index + (-1 if input.keycode == KEY_UP else 1)
			if index >= 0 and goal >= 0 and goal < siblings.size():
				focus_line = int(siblings[goal].line) if input.keycode == KEY_UP else int(unit.line) + int(siblings[goal].end_line) - int(siblings[goal].line)
				_perform("Move a block", func() -> String: return StoryBlocks.move_many(row, [unit], int(siblings[goal].line) if input.keycode == KEY_UP else int(siblings[goal].end_line), str(unit.indent), snapshot))
		else: return
		accept_event()

func _show_selection() -> void:
	for key: String in panels:
		var panel: PanelContainer = panels[key]
		var entry := _entry(key)
		var chosen: bool = _unit(entry).key in selection
		if chosen: panel.theme_type_variation = "BlockSelected"
		elif panel.theme_type_variation == "BlockSelected": panel.theme_type_variation = "Block"

func _focus_line(line: int) -> void:
	focus_line = -1
	var opened := false
	for entry: Dictionary in entries:
		if int(entry.line) <= line and line < int(entry.end_line) and folded.get(entry.key, false):
			folded.erase(entry.key)
			opened = true
	if opened: refresh()
	var best: Control = null
	for key: String in panels:
		var entry := _entry(key)
		if int(entry.line) <= line and line < maxi(int(entry.end_line), int(entry.line) + 1): best = panels[key]
	if best == null: return
	_reveal.call_deferred(best)

func _reveal(control: Control) -> void:
	if not is_instance_valid(control) or not control.is_inside_tree() or not block_scroll.is_ancestor_of(control): return
	block_scroll.ensure_control_visible(control)
	if control.focus_mode != Control.FOCUS_NONE and control.is_visible_in_tree(): control.grab_focus()

## Opens the block that holds a line of this story's file (from a problem or a search).
func focus_source_line(line: int) -> void:
	_focus_line(line)

func _show_badges() -> void:
	for line: int in badges:
		var label: Label = badges[line]
		if not is_instance_valid(label): continue
		label.text = ""
		for entry: Dictionary in preview.last_entries:
			if entry.kind == "branch" and int(entry.line) == line:
				label.text = "✓ taken" if entry.taken else "✗ skipped"
				label.theme_type_variation = "GoodLabel" if entry.taken else "MutedLabel"
				label.tooltip_text = "For the sample player in the preview: " + str(entry.reason)

# ------------------------------------------------------------------ writing

## Writes prose in place: an existing passage (entry) or a new one at a spot.
func _write(entry: Dictionary, spot: Dictionary = {}, replace: Control = null) -> void:
	if not row.doc.writable: return
	if writer != null and is_instance_valid(writer): writer.queue_free()
	var host: Control = replace if replace != null else panels.get(entry.get("key", ""), null)
	var hides := host != null
	if host == null and spot.has("line"):
		for other: Dictionary in entries:
			if int(other.line) == int(spot.line) and panels.has(other.key): host = panels[other.key]
	var box := VBoxContainer.new()
	writer = box
	var input := TextEdit.new()
	writer_text = input
	input.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
	input.scroll_fit_content_height = true
	input.custom_minimum_size.y = 84
	input.theme_type_variation = "StoryBubble"
	input.placeholder_text = "Write what the player reads. An empty line starts a new paragraph."
	var original := StoryBlocks.source(row, entry) if not entry.is_empty() else ""
	input.text = original
	box.add_child(input)
	var tools := HBoxContainer.new()
	box.add_child(tools)
	var insert := MenuButton.new()
	insert.text = "Insert ▾"
	insert.flat = false
	insert.tooltip_text = "Insert words that change: a name, he or she, a counter's number."
	var words := [["The player's name", "[name of player]"], ["A character's name…", "name"], ["He / she / they for a character…", "he"], ["Him / her / them…", "him"], ["His / her / their…", "his"], ["A counter's number…", "value"], ["Emphasis (italic)", "*"], ["Strong (bold)", "**"]]
	for pair: Array in words: insert.get_popup().add_item(pair[0])
	insert.get_popup().id_pressed.connect(func(id: int) -> void: _insert_markup(input, words[id][1]))
	tools.add_child(insert)
	var vary := _ghost("Vary", "Offer several versions of the selected words; the game picks one each time.", "AddRow")
	vary.pressed.connect(func() -> void:
		var chosen := input.get_selected_text() if input.has_selection() else "one version"
		input.insert_text_at_caret("[one of]" + chosen + "[or]another version[at random]"))
	tools.add_child(vary)
	var only := _ghost("Only if…", "Show the selected words only when a condition holds.", "AddRow")
	only.pressed.connect(func() -> void:
		var chosen := input.get_selected_text() if input.has_selection() else "these words"
		_ask_condition("", "Show these words only if…", func(condition: String) -> void: input.insert_text_at_caret("[if " + condition + "]" + chosen + "[else]other words[end if]")))
	tools.add_child(only)
	var count := AuthoringLayout.label("", 12, true)
	count.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	count.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	count.autowrap_mode = TextServer.AUTOWRAP_OFF
	tools.add_child(count)
	var recount := func() -> void: count.text = "%d words" % input.text.split(" ", false).size() if not input.text.strip_edges().is_empty() else ""
	input.text_changed.connect(recount)
	recount.call()
	var cancel := _ghost("Cancel", "Leave the text as it was (Esc).", "AddRow")
	tools.add_child(cancel)
	var apply := Button.new()
	apply.text = "Done"
	apply.theme_type_variation = "PrimaryButton"
	apply.tooltip_text = "Keep this text (Ctrl+Enter)."
	tools.add_child(apply)
	var message := AuthoringLayout.label("", 13)
	message.theme_type_variation = "ErrorLabel"
	box.add_child(message)
	var close := func() -> void:
		writer = null
		refresh()
	writer_done = func() -> void:
		var value := input.text
		if not entry.is_empty() and value.strip_edges() == original.strip_edges():
			close.call()
			return
		if row.doc.text != snapshot:
			message.text = "This story changed meanwhile. Copy your text, then choose the story again."
			return
		var error := workspace.transaction("Write text", func() -> String:
			var issue := StoryBlocks.set_text(row, entry, value, snapshot) if not entry.is_empty() else StoryBlocks.insert(row, spot, value.replace("\r\n", "\n").strip_edges(), snapshot) if _prose_only(value).is_empty() else _prose_only(value)
			if not issue.is_empty(): return issue
			var parsed := FscParser.parse(row.doc.text, row.doc.path)
			return str(parsed.diagnostics[0].message) if not parsed.ok() else "")
		if not error.is_empty():
			message.text = error
			return
		writer = null
		refresh()
		changed.emit(row)
	apply.pressed.connect(writer_done)
	cancel.pressed.connect(close)
	input.gui_input.connect(func(event: InputEvent) -> void:
		if event is InputEventKey and event.pressed:
			if event.keycode == KEY_ESCAPE:
				close.call()
				input.accept_event()
			elif event.keycode == KEY_ENTER and (event.ctrl_pressed or event.meta_pressed):
				writer_done.call()
				input.accept_event())
	if host != null and host.get_parent() != null:
		var parent := host.get_parent()
		parent.add_child(box)
		parent.move_child(box, host.get_index())
		if hides: host.hide()
	else: blocks.add_child(box)
	input.grab_focus()
	_reveal.call_deferred(box)

static func _prose_only(value: String) -> String:
	if value.strip_edges().is_empty(): return "Write some text first."
	for line: String in value.split("\n"):
		if StoryGraph._is_statement(line.strip_edges()): return "A line here starts like an action or a response. Add those with “Action” or “More” instead."
	return ""

func _insert_markup(input: TextEdit, what: String) -> void:
	if what.begins_with("["):
		input.insert_text_at_caret(what)
		return
	if what in ["*", "**"]:
		input.insert_text_at_caret(what + (input.get_selected_text() if input.has_selection() else "words") + what)
		return
	var spec := {"name": "pick", "kind": "value.number" if what == "value" else "who", "default": "", "hidden": false, "optional": false}
	var control := SlotControl.make(workspace, spec, "")
	control.hide()
	add_child(control)
	control.edited.connect(func() -> void:
		input.insert_text_at_caret("[" + control.value() + "]" if what == "value" else "[" + what + " of " + control.value() + "]")
		input.grab_focus()
		control.queue_free())
	control.picker.open(DisplayServer.mouse_get_position())

# ---------------------------------------------------------------- responses

func _build_response_dialog() -> void:
	response_dialog = ConfirmationDialog.new()
	response_dialog.title = "Response"
	response_dialog.ok_button_text = "Apply"
	response_dialog.dialog_hide_on_ok = false
	var body := VBoxContainer.new()
	body.custom_minimum_size.x = 520
	response_dialog.add_child(body)
	body.add_child(AuthoringLayout.label("What the player can choose", 14, true))
	var label := LineEdit.new()
	label.placeholder_text = "Ask about the camp"
	body.add_child(label)
	body.add_child(AuthoringLayout.label("A short note shown under it (optional)", 14, true))
	var description := LineEdit.new()
	body.add_child(description)
	var condition := AuthoringLayout.label("", 14)
	body.add_child(condition)
	var buttons := HBoxContainer.new()
	body.add_child(buttons)
	var change := Button.new()
	change.text = "Only if…"
	buttons.add_child(change)
	var clear := Button.new()
	clear.text = "Always offer it"
	buttons.add_child(clear)
	var leaves := CheckBox.new()
	leaves.text = "After this response, the conversation ends"
	body.add_child(leaves)
	var always := CheckBox.new()
	always.text = "Show it greyed out when it cannot be chosen"
	body.add_child(always)
	var error := AuthoringLayout.label("", 14)
	error.theme_type_variation = "ErrorLabel"
	body.add_child(error)
	response_fields = {"label": label, "description": description, "condition": condition, "leaves": leaves, "always": always, "error": error, "text": "", "entry": {}}
	var show := func() -> void:
		var text: String = response_fields.text
		condition.text = "Offered only if " + _lower(BlockCatalog.condition_sentence(text, workspace)) if not text.is_empty() else "Always offered."
		clear.visible = not text.is_empty()
	response_fields.show = show
	change.pressed.connect(func() -> void:
		_ask_condition(str(response_fields.text), "Offer this response only if…", func(next: String) -> void:
			response_fields.text = next
			show.call()))
	clear.pressed.connect(func() -> void:
		response_fields.text = ""
		show.call())
	response_dialog.confirmed.connect(func() -> void:
		var entry: Dictionary = response_fields.entry
		if label.text.strip_edges().is_empty() or "[" in label.text and "]" not in label.text:
			error.text = "Write what the player can choose."
			return
		var number: Variant = entry.node.get("number")
		var extra: String = " [number %d to %d]" % [number[0], number[1]] if number is Array else ""
		var text: String = response_fields.text
		if not _perform("Change a response", func() -> String:
			var issue := StoryBlocks.set_line(row, entry, StoryBlocks.response_line(label.text, description.text, text, leaves.button_pressed, always.button_pressed, extra), snapshot)
			return issue if not issue.is_empty() or text.is_empty() else workspace.require_condition(Condition.compile(text))): return
		response_dialog.hide())
	label.text_submitted.connect(func(_text: String) -> void: response_dialog.get_ok_button().pressed.emit())
	add_child(response_dialog)

func _edit_response(entry: Dictionary) -> void:
	var node: Dictionary = entry.node
	response_fields.entry = entry
	response_fields.label.text = str(node.label)
	response_fields.description.text = str(node.get("description", ""))
	response_fields.text = str(node.get("condition", ""))
	response_fields.leaves.button_pressed = node.get("then_leave", false)
	response_fields.always.button_pressed = node.get("always_shown", false)
	response_fields.error.text = ""
	response_fields.show.call()
	AuthoringLayout.popup(response_dialog, Vector2i(560, 380))
	response_fields.label.grab_focus()
	response_fields.label.select_all()
