class_name StoryCanvas
extends VBoxContainer
## A conversation canvas that edits individual source passages and responses.

signal changed(row: Dictionary)
signal problem(message: String)
signal details_requested(row: Dictionary)
signal new_story_requested
signal next_story_requested(row: Dictionary, option: Dictionary)

var workspace: PackWorkspace
var graph: GraphEdit
var graph_rows: Dictionary = {}
var graph_options: Dictionary = {}
var graph_play_links: Dictionary = {}
var graph_continuations: Dictionary = {}
var positions: Dictionary = {}
var layout_target := ""
var focused_script: Dictionary = {}
var focused_definition: Dictionary = {}
var focused_id := ""
var show_everything := false
var focus_only := false
## Cards with their own writing controls, as before the side editor. Off: summary cards.
var detailed_cards := false
signal context_changed(row: Dictionary)
var shown_context := ""
var scope_button: Button
var context_label: Label
var context_row: Dictionary = {}
var picker_image: TextureRect
var picker: ConfirmationDialog
var picker_search: LineEdit
var picker_layout: AuthoringLayout
var picker_category := "All"
var picker_categories: Array[Dictionary] = []
var picker_preview: Label
var picker_error: Label
var picker_amount: SpinBox
var picker_amount_label: Label
var picker_new_story: Button
var picker_list: ItemList
var picker_entries: Array[Dictionary] = []
var picker_row: Dictionary = {}
var picker_option: Dictionary = {}
var picker_mode := ""
var picker_original := ""
var picker_action: Dictionary = {}
var picker_branch: Dictionary = {}
var picker_passage: Dictionary = {}
var remove_kind := "response"
var remove_action: Dictionary = {}
var remove_dialog: ConfirmationDialog
var remove_row: Dictionary = {}
var remove_option: Dictionary = {}
var writing_window: Window
var writing_text: TextEdit
var writing_count: Label
var writing_error: Label
var writing_row: Dictionary = {}
var writing_passage: Dictionary = {}
var writing_original := ""
var writing_new_field := ""
var writing_discard: ConfirmationDialog

func _ready() -> void:
	var toolbar := HFlowContainer.new()
	add_child(toolbar)
	var hint := Label.new()
	hint.text = "STORY BOARD"
	toolbar.add_child(hint)
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	toolbar.add_child(spacer)
	var create := Button.new()
	create.text = "+ Story node"
	create.pressed.connect(func() -> void: new_story_requested.emit())
	toolbar.add_child(create)
	scope_button = Button.new()
	scope_button.text = "Show all stories"
	scope_button.pressed.connect(func() -> void:
		show_everything = not show_everything
		scope_button.text = "Show related stories" if show_everything else "Show all stories"
		refresh())
	toolbar.add_child(scope_button)
	var arrange := Button.new()
	arrange.text = "Tidy up"
	arrange.tooltip_text = "Arrange the cards from left to right, following how the stories lead to each other."
	arrange.pressed.connect(tidy)
	toolbar.add_child(arrange)
	var focused := CheckButton.new()
	focused.text = "Focus only"
	focused.toggled.connect(func(enabled: bool) -> void:
		focus_only = enabled
		scope_button.disabled = enabled
		refresh())
	toolbar.add_child(focused)
	context_label = AuthoringLayout.label("Choose a story to start writing.", 14, true)
	add_child(context_label)
	var help := Label.new()
	help.text = "Select a card to see and change its blocks on the right. Drag a response's dot to another story to connect them; right-click a connection to remove it."
	help.theme_type_variation = "MutedLabel"
	help.add_theme_font_size_override("font_size", 12)
	help.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(help)
	graph = DropSurface.new()
	graph.workspace = workspace
	graph.size_flags_vertical = Control.SIZE_EXPAND_FILL
	graph.get_menu_hbox().hide()
	graph.minimap_enabled = false
	graph.right_disconnects = true
	graph.connection_request.connect(_connect_response)
	graph.disconnection_request.connect(_disconnect_response)
	add_child(graph)
	_build_picker()
	_build_long_writer()
	remove_dialog = ConfirmationDialog.new()
	remove_dialog.title = "Remove response"
	remove_dialog.dialog_text = "Remove this response and its story actions? Comments and attribution will be kept."
	remove_dialog.ok_button_text = "Remove response"
	remove_dialog.confirmed.connect(_remove_response)
	add_child(remove_dialog)

func configure(value: PackWorkspace) -> void:
	workspace = value

## Arranges the cards left to right, following how stories lead to each other.
func tidy() -> void:
	var incoming: Dictionary = {}
	var outgoing: Dictionary = {}
	for name: StringName in graph_rows:
		incoming[name] = 0
		outgoing[name] = []
	for link: Dictionary in graph.get_connection_list():
		if link.from_node == link.to_node or not outgoing.has(link.from_node) or not incoming.has(link.to_node): continue
		outgoing[link.from_node].append(link.to_node)
		incoming[link.to_node] += 1
	var depth: Dictionary = {}
	var queue: Array = []
	for name: StringName in graph_rows:
		if incoming[name] == 0:
			depth[name] = 0
			queue.append(name)
	if queue.is_empty() and not graph_rows.is_empty():
		depth[graph_rows.keys()[0]] = 0
		queue.append(graph_rows.keys()[0])
	while not queue.is_empty():
		var name: StringName = queue.pop_front()
		for next: StringName in outgoing[name]:
			if depth.has(next): continue
			depth[next] = int(depth[name]) + 1
			queue.append(next)
	var heights: Dictionary = {}
	for name: StringName in graph_rows:
		var column: int = depth.get(name, 0)
		var card := graph.get_node(NodePath(name)) as GraphNode
		var top: float = heights.get(column, 40.0)
		card.position_offset = Vector2(40 + column * 360, top)
		heights[column] = top + maxf(120.0, card.get_combined_minimum_size().y) + 36.0
		positions[_row_key(graph_rows[name])] = card.position_offset
	_save_layout()

func refresh() -> void:
	if workspace == null or graph == null:
		return
	context_row = _fresh_row(focused_script) if not focused_script.is_empty() else (_fresh_row(focused_definition) if not focused_definition.is_empty() else {})
	context_label.text = "All loaded stories" if show_everything and not focus_only else ("Choose a story to start writing." if context_row.is_empty() else "%s › %s › %s" % [context_row.pack, EventTriggers.title_for(workspace, context_row.def.type, context_row.def.id), str(context_row.get("script_field", "Story")).capitalize()])
	graph.clear_connections()
	for child: Node in graph.get_children():
		if child is GraphNode:
			graph.remove_child(child)
			child.queue_free()
	graph_rows.clear()
	graph_options.clear()
	graph_play_links.clear()
	graph_continuations.clear()
	var destinations: Dictionary = {}
	var visible_rows: Array = workspace.rows.duplicate()
	if not focused_script.is_empty():
		var focused := _fresh_row(focused_script)
		if not focused.is_empty():
			visible_rows.push_front(focused)
	if not show_everything and not focus_only and not focused_id.is_empty():
		var relevant := {focused_id: true}
		var prefix := focused_id.get_slice(".", 0)
		for candidate: Dictionary in workspace.rows:
			if candidate.def.id.begins_with(prefix + "."):
				relevant[candidate.def.id] = true
		var links := workspace.story_links()
		for _step in 2:
			for link: Dictionary in links:
				if relevant.has(link.from.def.id) or relevant.has(link.target):
					relevant[link.from.def.id] = true
					relevant[link.target] = true
		visible_rows = visible_rows.filter(func(candidate: Dictionary) -> bool: return relevant.has(candidate.def.id))
	if focus_only and not context_row.is_empty():
		visible_rows = [context_row]
	context_label.text += " · " + ("This interaction only" if focus_only else ("All packs" if show_everything else "Related stories · links up to two steps away"))
	var y_offsets := [60.0, 60.0, 60.0]
	var index := 0
	for row: Dictionary in visible_rows:
		var d: FscParser.Definition = row.def
		if d.type not in ["scene", "menu", "event", "character"] and not row.has("script_field"):
			continue
		var card := GraphNode.new()
		card.name = "story_" + str(index)
		card.title = d.id + (" · " + str(row.script_field).capitalize() if row.has("script_field") else "") + (" · " + d.mode if d.mode != "define" else "")
		card.custom_minimum_size.x = 300 if detailed_cards else 270
		var key := _row_key(row)
		var column := index % 3
		card.position_offset = positions.get(key, Vector2(45 + column * 380, y_offsets[column]))
		card.dragged.connect(_moved.bind(key))
		graph.add_child(card)
		graph_rows[card.name] = row
		if d.type in ["scene", "menu"] and not row.has("script_field") and (not destinations.has(d.id) or d.mode == "define"):
			destinations[d.id] = card.name
		_build_card(card, row)
		var options := StoryGraph.choices(row)
		graph_options[card.name] = options
		y_offsets[column] += maxf(250.0, card.get_combined_minimum_size().y + 100.0)
		index += 1
	context_label.text += " · %d cards" % graph_rows.size()
	graph.minimap_enabled = graph_rows.size() > 6
	var context_key := _row_key(context_row) if not context_row.is_empty() else ""
	if context_key != shown_context:
		shown_context = context_key
		if not context_row.is_empty(): context_changed.emit(context_row)
		_show_context.call_deferred()
	for from_name: StringName in graph_rows:
		var row: Dictionary = graph_rows[from_name]
		var options: Array = graph_options[from_name]
		for port in options.size():
			var route := StoryGraph.transition(options[port])
			if route.editable and destinations.has(route.target):
				graph.connect_node(from_name, port, destinations[route.target], 0)
		var direct := StoryGraph.primary_transition(row)
		var has_continuation: bool = graph_continuations.get(from_name, false)
		if has_continuation and not direct.is_empty() and destinations.has(direct.target):
			graph.connect_node(from_name, options.size(), destinations[direct.target], 0)
		var calls: Array = graph_play_links.get(from_name, [])
		for i in calls.size():
			var call_target := StoryGraph.play_target(calls[i])
			if destinations.has(call_target):
				graph.connect_node(from_name, options.size() + (1 if has_continuation else 0) + i, destinations[call_target], 0)

## Brings the story in focus into view, once the board has its size.
func _show_context() -> void:
	if not is_inside_tree(): return
	await get_tree().process_frame
	var target := Vector2.ZERO
	for name: StringName in graph_rows:
		if not context_row.is_empty() and _row_key(graph_rows[name]) == _row_key(context_row):
			var card := graph.get_node_or_null(NodePath(name)) as GraphNode
			if card != null:
				card.selected = true
				target = card.position_offset * graph.zoom - Vector2(30, 30)
	graph.scroll_offset = Vector2(maxf(0.0, target.x), maxf(0.0, target.y))

func _row_key(row: Dictionary) -> String:
	var identity := "%s|%s|%s|%s|%d|%s" % [row.doc.path, row.def.type, row.def.id, row.def.mode, row.get("ordinal", 0), row.get("script_field", "")]
	return identity.sha256_text()

func _layout_path() -> String:
	return OS.get_user_data_dir().path_join("layouts").path_join(workspace.target.sha256_text() + ".cfg")

func _load_layout() -> void:
	if workspace == null or workspace.target == layout_target:
		return
	layout_target = workspace.target
	positions.clear()
	var config := ConfigFile.new()
	if config.load(_layout_path()) != OK:
		return
	for key: String in config.get_section_keys("nodes"):
		var value: Variant = config.get_value("nodes", key)
		if value is Vector2:
			positions[key] = value

func _moved(_from: Vector2, to: Vector2, key: String) -> void:
	positions[key] = to
	_save_layout()

func _save_layout() -> void:
	var folder := OS.get_user_data_dir().path_join("layouts")
	if DirAccess.make_dir_recursive_absolute(folder) != OK:
		problem.emit("Could not save the story board layout.")
		return
	var config := ConfigFile.new()
	for node_key: String in positions:
		config.set_value("nodes", node_key, positions[node_key])
	if config.save(_layout_path()) != OK:
		problem.emit("Could not save the story board layout.")

## A summary card: what the story is, how it starts, and where it leads.
## The blocks themselves are read and changed in the side editor.
func _build_summary(card: GraphNode, row: Dictionary) -> void:
	var d: FscParser.Definition = row.def
	card.title = Wording.title(row) + (" · " + StoryEditor.story_name(row) if row.has("script_field") else "")
	card.tooltip_text = "Select to see its blocks in the side editor. Drag a response's dot to another story to connect them."
	var top := HBoxContainer.new()
	card.add_child(top)
	var info := Label.new()
	info.text = Wording.icon(d.type) + " " + Wording.name(d.type).capitalize() + ("" if row.doc.writable else " · " + str(row.pack) + ", read-only")
	info.add_theme_font_size_override("font_size", 12)
	info.add_theme_color_override("font_color", EditorTheme.category_color(d.type))
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(info)
	var open_details := Button.new()
	open_details.text = "Details"
	open_details.theme_type_variation = "Ghost"
	open_details.tooltip_text = "Open everything about this content."
	open_details.pressed.connect(func() -> void: details_requested.emit(row))
	top.add_child(open_details)
	card.set_slot(0, d.type in ["scene", "menu"], 0, Color("d6a86b"), false, 0, Color.WHITE)
	var entries := StoryGraph.structure(row)
	var first := ""
	var counts := {"text": 0, "effect": 0, "if": 0, "fight": 0}
	var calls: Array = []
	for entry: Dictionary in entries:
		var kind: String = entry.node.kind
		if counts.has(kind): counts[kind] += 1
		if kind == "text" and first.is_empty(): first = Wording.prose(_display_dynamic(str(entry.node.text)))
	for passage: Dictionary in StoryGraph.script_nodes(row):
		if passage.kind == "play" and not StoryGraph.play_target(passage).is_empty(): calls.append(passage)
	var excerpt := AuthoringLayout.label(first if first.length() <= 150 else first.left(148) + "…", 14, first.is_empty())
	if first.is_empty(): excerpt.text = "Nothing written yet."
	else: excerpt.theme_type_variation = "StoryLabel"
	excerpt.custom_minimum_size.x = 250
	excerpt.max_lines_visible = 3
	card.add_child(excerpt)
	var facts: Array[String] = []
	for pair: Array in [["text", "passage"], ["effect", "action"], ["if", "condition"], ["fight", "fight"]]:
		if counts[pair[0]] > 0: facts.append("%d %s%s" % [counts[pair[0]], pair[1], "" if counts[pair[0]] == 1 else "s"])
	if not facts.is_empty():
		var summary := AuthoringLayout.label(" · ".join(facts), 12, true)
		card.add_child(summary)
	for option: Dictionary in StoryGraph.choices(row):
		var response := Label.new()
		response.text = "› " + str(option.label) + ("  ◈" if not str(option.condition).is_empty() else "")
		response.tooltip_text = "A response the player can choose." + (" Offered only if " + BlockCatalog.condition_sentence(str(option.condition), workspace).to_lower() + "." if not str(option.condition).is_empty() else "")
		response.mouse_filter = Control.MOUSE_FILTER_PASS
		response.clip_text = true
		response.custom_minimum_size.x = 250
		var slot := card.get_child_count()
		card.add_child(response)
		card.set_slot(slot, false, 0, Color.WHITE, true, 0, Color("e8a660"))
	var direct := StoryGraph.primary_transition(row)
	var is_menu_field: bool = row.has("script_field") and ContentDB.SCHEMA.get(d.type, {}).get(row.script_field, "") == "menu"
	var has_continuation := not direct.is_empty() or (not is_menu_field and (d.type in ["scene", "event", "character"] or row.has("script_field")))
	graph_continuations[card.name] = has_continuation
	if has_continuation:
		var continuation := Label.new()
		continuation.text = "⏹ Ends here" if direct.get("target", "") == "end" else ("↩ Returns to the conversation" if direct.get("target", "") == "back" else "➜ Then continues with…")
		continuation.add_theme_font_size_override("font_size", 12)
		continuation.theme_type_variation = "MutedLabel"
		var slot := card.get_child_count()
		card.add_child(continuation)
		card.set_slot(slot, false, 0, Color.WHITE, true, 0, Color("8fb9cf"))
	graph_play_links[card.name] = calls
	for action: Dictionary in calls:
		var play_label := Label.new()
		play_label.text = "▶ Plays " + BlockCatalog.content_label("scene", StoryGraph.play_target(action), workspace)
		play_label.add_theme_font_size_override("font_size", 12)
		var slot := card.get_child_count()
		card.add_child(play_label)
		card.set_slot(slot, false, 0, Color.WHITE, true, 0, Color("a4c9a2"))
	if row.doc.writable and d.type in ["scene", "menu"] and not row.has("script_field") and workspace.uses(d.id).is_empty():
		var hint := AuthoringLayout.label("⚠ Nothing leads here yet", 12, true)
		card.add_child(hint)

func _build_card(card: GraphNode, row: Dictionary) -> void:
	if not detailed_cards:
		_build_summary(card, row)
		return
	var d: FscParser.Definition = row.def
	var writable: bool = row.doc.writable
	var info := Label.new()
	info.text = d.type.capitalize() + " · " + str(row.pack) + (" · reference" if not writable else "")
	info.add_theme_font_size_override("font_size", 12)
	card.add_child(info)
	var open_details := Button.new()
	open_details.text = "Content details & interactions"
	open_details.pressed.connect(func() -> void: details_requested.emit(row))
	card.add_child(open_details)
	var image_button := Button.new()
	image_button.text = "Choose opening image…"
	image_button.disabled = not writable or (row.has("script_field") and ContentDB.SCHEMA.get(d.type, {}).get(row.script_field, "") == "menu")
	image_button.pressed.connect(_open_image_picker.bind(row, {}))
	card.add_child(image_button)
	card.set_slot(0, d.type in ["scene", "menu"], 0, Color("d6a86b"), false, 0, Color.WHITE)
	var speech_count := 0
	var calls: Array = []
	for passage: Dictionary in StoryGraph.script_nodes(row):
		match passage.kind:
			"text":
				if not str(passage.text).is_empty():
					_add_bubble(card, row, passage, "STORY / SPEAKER")
					speech_count += 1
			"page_break":
				_add_note(card, "⏸  Wait for the player to continue")
			"effect":
				_add_effect_controls(card, row, {}, passage, writable)
			"play":
				var target := StoryGraph.play_target(passage)
				_add_note(card, "▶  Play " + (target if not target.is_empty() else "another story") + " and return")
				if not target.is_empty():
					calls.append(passage)
			"show":
				_add_image_controls(card, row, passage)
			"if", "fight":
				var branch := VBoxContainer.new()
				_add_branch_preview(branch, row, passage)
				card.add_child(branch)
			"choices":
				_add_note(card, "◇  Player chooses from the responses below")
	if speech_count == 0:
		var add_speech := Button.new()
		add_speech.text = "+ Add speech or narration"
		var menu_field: bool = row.has("script_field") and ContentDB.SCHEMA.get(d.type, {}).get(row.script_field, "") == "menu"
		add_speech.disabled = not writable or menu_field or (d.type not in ["scene", "menu"] and not row.has("script_field"))
		add_speech.pressed.connect(_add_speech.bind(row))
		card.add_child(add_speech)
	var options := StoryGraph.choices(row)
	for option: Dictionary in options:
		var response := VBoxContainer.new()
		response.custom_minimum_size.x = 280
		var label := Label.new()
		label.text = "PLAYER RESPONSE"
		label.add_theme_font_size_override("font_size", 11)
		response.add_child(label)
		var response_line := LineEdit.new()
		response_line.text = str(option.label)
		response_line.placeholder_text = "What the player can say or do"
		response_line.editable = writable
		response_line.focus_exited.connect(_commit_response.bind(row, option, response_line))
		response_line.text_submitted.connect(func(_value: String) -> void: response_line.release_focus())
		response.add_child(response_line)
		var description := LineEdit.new()
		description.text = str(option.description)
		description.placeholder_text = "Optional description shown to the player"
		description.editable = writable
		description.focus_exited.connect(_commit_description.bind(row, option, description))
		description.text_submitted.connect(func(_value: String) -> void: description.release_focus())
		response.add_child(description)
		var exits := CheckButton.new()
		exits.text = "Leave the menu afterwards"
		exits.button_pressed = bool(option.then_leave)
		exits.disabled = not writable
		exits.toggled.connect(_toggle_choice.bind(row, option, "then leave"))
		response.add_child(exits)
		if option.number != null:
			var range_note := Label.new()
			range_note.text = "Player enters a number from %d to %d" % [option.number[0], option.number[1]]
			response.add_child(range_note)
		if not str(option.condition).is_empty():
			var conditional := Label.new()
			conditional.text = "◈ Only if " + _condition_label(Condition.compile(str(option.condition)))
			conditional.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			conditional.custom_minimum_size.x = 260
			conditional.add_theme_font_size_override("font_size", 11)
			response.add_child(conditional)
			var always := CheckButton.new()
			always.text = "Show disabled when unavailable"
			always.button_pressed = bool(option.always_shown)
			always.disabled = not writable
			always.toggled.connect(_toggle_choice.bind(row, option, "always shown"))
			response.add_child(always)
			var clear_condition := Button.new()
			clear_condition.text = "Remove condition"
			clear_condition.disabled = not writable
			clear_condition.pressed.connect(_ask_clear_condition.bind(row, option))
			response.add_child(clear_condition)
		for action: Dictionary in option.body:
			if action.kind == "text":
				_add_bubble(response, row, action, "AFTER THIS RESPONSE")
			elif action.kind == "effect":
				var effect_row := HBoxContainer.new()
				var effect_label := Label.new()
				effect_label.text = "◆ " + _effect_label(str(action.text))
				effect_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
				effect_label.add_theme_font_size_override("font_size", 11)
				effect_row.add_child(effect_label)
				var change_action := Button.new()
				change_action.text = "Change"
				change_action.disabled = not writable
				change_action.pressed.connect(_open_existing_effect.bind(row, option, action))
				effect_row.add_child(change_action)
				var remove_action_button := Button.new()
				remove_action_button.text = "Remove"
				remove_action_button.disabled = not writable
				remove_action_button.pressed.connect(_ask_remove_effect.bind(row, option, action))
				effect_row.add_child(remove_action_button)
				response.add_child(effect_row)
			elif action.kind in ["if", "choices", "fight"]:
				var nested := Label.new()
				nested.text = "◇ Additional branching is preserved"
				nested.add_theme_font_size_override("font_size", 11)
				response.add_child(nested)
		var actions := HBoxContainer.new()
		for spec in [["+ Condition", "condition"], ["+ Action", "effect"]]:
			var button := Button.new()
			button.text = spec[0]
			button.disabled = not writable
			button.pressed.connect(_open_picker.bind(row, option, spec[1]))
			actions.add_child(button)
		var remove := Button.new()
		remove.text = "Remove"
		remove.disabled = not writable
		remove.pressed.connect(_ask_remove.bind(row, option))
		actions.add_child(remove)
		response.add_child(actions)
		var route := StoryGraph.transition(option)
		var destination := Button.new()
		destination.text = "Choose next story…" if str(route.get("target", "")).is_empty() else "Next: " + str(route.target).capitalize()
		destination.clip_text = true
		destination.disabled = not writable or not route.editable
		destination.pressed.connect(_open_picker.bind(row, option, "destination"))
		response.add_child(destination)
		if not route.editable:
			var note := Label.new()
			note.text = "Complex branch · links preserved"
			note.add_theme_font_size_override("font_size", 11)
			response.add_child(note)
		var slot := card.get_child_count()
		card.add_child(response)
		card.set_slot(slot, false, 0, Color.WHITE, true, 0, Color("e8a660"))
	var direct := StoryGraph.primary_transition(row)
	var is_menu_field: bool = row.has("script_field") and ContentDB.SCHEMA.get(d.type, {}).get(row.script_field, "") == "menu"
	var has_continuation := not direct.is_empty() or (not is_menu_field and (d.type in ["scene", "event", "character"] or row.has("script_field")))
	graph_continuations[card.name] = has_continuation
	if has_continuation:
		var continuation := Label.new()
		continuation.text = "Story ends" if direct.get("target", "") == "end" else ("Return to the previous menu" if direct.get("target", "") == "back" else "Then continue automatically")
		continuation.add_theme_font_size_override("font_size", 12)
		var slot := card.get_child_count()
		card.add_child(continuation)
		card.set_slot(slot, false, 0, Color.WHITE, true, 0, Color("8fb9cf"))
	graph_play_links[card.name] = calls
	for action: Dictionary in calls:
		var play_label := Label.new()
		play_label.text = "Play " + StoryGraph.play_target(action) + " and return"
		play_label.add_theme_font_size_override("font_size", 12)
		var slot := card.get_child_count()
		card.add_child(play_label)
		card.set_slot(slot, false, 0, Color.WHITE, true, 0, Color("a4c9a2"))
	var story_action := Button.new()
	story_action.text = "+ Add action"
	story_action.disabled = not writable or is_menu_field or (d.type == "menu" and not row.has("script_field"))
	story_action.pressed.connect(_open_picker.bind(row, {}, "effect"))
	card.add_child(story_action)
	var story_steps := HBoxContainer.new()
	var play_button := Button.new()
	play_button.text = "+ Play story"
	play_button.disabled = story_action.disabled
	play_button.pressed.connect(_open_picker.bind(row, {}, "play"))
	story_steps.add_child(play_button)
	var pause_button := Button.new()
	pause_button.text = "+ Pause"
	pause_button.disabled = story_action.disabled
	pause_button.pressed.connect(_add_pause.bind(row))
	story_steps.add_child(pause_button)
	var end_button := Button.new()
	end_button.text = "End story"
	end_button.disabled = story_action.disabled
	end_button.pressed.connect(_end_story.bind(row))
	story_steps.add_child(end_button)
	card.add_child(story_steps)
	var add_response := Button.new()
	add_response.text = "+ Add response"
	add_response.disabled = not writable or (d.type not in ["scene", "menu"] and options.is_empty() and not row.has("script_field"))
	add_response.pressed.connect(_add_response.bind(row))
	card.add_child(add_response)

func _add_bubble(parent: Node, row: Dictionary, passage: Dictionary, caption: String) -> void:
	var label := Label.new()
	label.text = caption
	label.add_theme_font_size_override("font_size", 11)
	parent.add_child(label)
	var dynamic := "[" in str(passage.text) or "]" in str(passage.text)
	var parts := StoryGraph.dynamic_parts(row, passage) if dynamic else []
	if dynamic and not parts.is_empty():
		var group := VBoxContainer.new()
		group.custom_minimum_size.x = 275
		for part: Dictionary in parts:
			if part.kind == "tag":
				_add_note(group, _tag_label(str(part.text)))
			elif not str(part.text).is_empty():
				var fragment := _bubble_edit(str(part.text), row.doc.writable)
				fragment.custom_minimum_size.y = 48
				fragment.focus_exited.connect(_commit_fragment.bind(row, passage, part, fragment))
				group.add_child(fragment)
		parent.add_child(group)
		if str(passage.text).count("[one of]") == 1:
			var alternative := Button.new()
			alternative.text = "+ Alternative"
			alternative.disabled = not row.doc.writable
			alternative.pressed.connect(_add_alternative.bind(row, passage))
			parent.add_child(alternative)
		return
	var box := _bubble_edit(_display_dynamic(str(passage.text)) if dynamic else str(passage.text), row.doc.writable and not dynamic)
	if dynamic:
		box.tooltip_text = "This multi-line dynamic passage is preserved; visual editing is not available yet."
	box.focus_exited.connect(_commit_speech.bind(row, passage, box))
	parent.add_child(box)
	if not dynamic and row.doc.writable:
		var tools := HBoxContainer.new()
		var expand := Button.new()
		expand.text = "Open writing space"
		expand.pressed.connect(_open_long_writer.bind(row, passage))
		tools.add_child(expand)
		parent.add_child(tools)
		tools = HBoxContainer.new()
		var variation := Button.new()
		variation.text = "+ Variations"
		variation.pressed.connect(_make_variation.bind(row, passage))
		tools.add_child(variation)
		var condition := Button.new()
		condition.text = "+ Conditional text"
		condition.pressed.connect(_open_passage_picker.bind(row, passage))
		tools.add_child(condition)
		parent.add_child(tools)

func _build_long_writer() -> void:
	writing_window = Window.new()
	writing_window.visible = false
	writing_window.title = "Writing space"
	writing_window.transient = true
	writing_window.exclusive = true
	writing_window.min_size = Vector2i(440, 320)
	writing_window.close_requested.connect(_cancel_long_writer)
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side in ["margin_left", "margin_right", "margin_top", "margin_bottom"]:
		margin.add_theme_constant_override(side, 16)
	writing_window.add_child(margin)
	var layout := VBoxContainer.new()
	layout.add_theme_constant_override("separation", 10)
	margin.add_child(layout)
	var hint := Label.new()
	hint.text = "Write as much as you need. Blank lines create separate paragraphs."
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	layout.add_child(hint)
	writing_text = TextEdit.new()
	writing_text.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
	writing_text.size_flags_vertical = Control.SIZE_EXPAND_FILL
	writing_text.add_theme_font_size_override("font_size", 18)
	writing_text.add_theme_font_override("font", EditorTheme.font("Literata.ttf"))
	writing_text.text_changed.connect(_update_writing_count)
	layout.add_child(writing_text)
	writing_error = Label.new()
	writing_error.theme_type_variation = "ErrorLabel"
	writing_error.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	layout.add_child(writing_error)
	var footer := HBoxContainer.new()
	writing_count = Label.new()
	writing_count.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	footer.add_child(writing_count)
	var cancel := Button.new()
	cancel.text = "Cancel"
	cancel.pressed.connect(_cancel_long_writer)
	footer.add_child(cancel)
	var apply := Button.new()
	apply.text = "Apply text"
	apply.pressed.connect(_apply_long_writer)
	footer.add_child(apply)
	layout.add_child(footer)
	writing_discard = ConfirmationDialog.new()
	writing_discard.title = "Discard writing?"
	writing_discard.dialog_text = "Your changes in this writing space have not been applied."
	writing_discard.ok_button_text = "Discard"
	writing_discard.confirmed.connect(writing_window.hide)
	writing_window.add_child(writing_discard)
	add_child(writing_window)

func _open_long_writer(row: Dictionary, passage: Dictionary) -> void:
	writing_new_field = ""
	writing_window.title = "Writing space"
	var current := _fresh_row(row)
	if current.is_empty():
		problem.emit("This story changed. Reopen it before editing.")
		return
	var passages: Array = []
	StoryGraph._collect_passages(StoryGraph.script_nodes(current), passages)
	for option: Dictionary in StoryGraph.choices(current):
		StoryGraph._collect_passages(option.body, passages)
	for candidate: Dictionary in passages:
		if candidate.get("line") == passage.get("line"):
			var block := StoryGraph.prose_block(current, candidate)
			if block.has("error"):
				problem.emit(block.error)
				return
			writing_row = current
			writing_passage = candidate
			writing_error.text = ""
			writing_text.text = str(block.text)
			writing_original = writing_text.text
			_update_writing_count()
			var available := get_window().size
			writing_window.popup_centered(Vector2i(maxi(440, int(available.x * 0.8)), maxi(320, int(available.y * 0.8))))
			writing_text.grab_focus()
			return
	problem.emit("This passage changed. Reopen it before editing.")

func start_writing(row: Dictionary, field: String) -> void:
	var current := _fresh_row(row)
	if current.is_empty() or not current.doc.writable or current.def.fields.has(field): return
	writing_row = current
	writing_new_field = field
	writing_passage = {}
	writing_original = ""
	writing_error.text = ""
	writing_text.text = ""
	writing_text.placeholder_text = "Write the beginning of this interaction…"
	_update_writing_count()
	var available := get_window().size
	writing_window.title = "Start writing · " + field.capitalize()
	writing_window.popup_centered(Vector2i(maxi(440, int(available.x * 0.8)), maxi(320, int(available.y * 0.8))))
	writing_text.grab_focus()

func _update_writing_count() -> void:
	if writing_count != null:
		writing_count.text = "%d words" % writing_text.text.replace("\n", " ").replace("\t", " ").split(" ", false).size()

func _cancel_long_writer() -> void:
	if writing_text.text != writing_original:
		writing_discard.popup_centered()
	else:
		writing_window.hide()

func _apply_long_writer() -> void:
	var current := _fresh_row(writing_row)
	if current.is_empty():
		writing_error.text = "This story changed. Copy your draft and reopen it before applying."
		return
	var error := StoryGraph.start_script(current, writing_new_field, writing_text.text) if not writing_new_field.is_empty() else StoryGraph.set_prose_block(current, writing_passage, writing_original, writing_text.text)
	if not error.is_empty():
		writing_error.text = error
		return
	writing_window.hide()
	_finish(current, "")

func _bubble_edit(value: String, can_edit: bool) -> TextEdit:
	var box := TextEdit.new()
	box.custom_minimum_size = Vector2(275, 72)
	box.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
	box.text = value
	box.editable = can_edit
	box.theme_type_variation = "StoryBubble"
	return box

func _tag_label(tag: String) -> String:
	var inner := tag.trim_prefix("[").trim_suffix("]")
	if inner.begins_with("if "):
		return "IF " + _condition_label(Condition.compile(inner.substr(3)))
	if inner.begins_with("else if "):
		return "OTHERWISE IF " + _condition_label(Condition.compile(inner.substr(8)))
	match inner:
		"else": return "OTHERWISE"
		"end if": return "CONTINUE"
		"one of": return "ONE OF THESE VARIATIONS"
		"or": return "ANOTHER VARIATION"
		"at random", "purely at random", "in random order": return "CHOOSE RANDOMLY"
		"cycling": return "CYCLE THROUGH VARIATIONS"
		"stopping": return "USE EACH VARIATION ONCE"
		"sticky", "sticky random": return "KEEP THE CHOSEN VARIATION"
		_: return "INSERT " + inner.capitalize()

func _commit_fragment(row: Dictionary, passage: Dictionary, part: Dictionary, editor: TextEdit) -> void:
	if not is_instance_valid(editor) or not editor.editable or editor.text == str(part.text):
		return
	var current := _fresh_row(row)
	if current.is_empty():
		problem.emit("This passage changed. Reopen it before editing.")
		return
	_finish(current, StoryGraph.set_dynamic_fragment(current, passage, part, editor.text))

func _fresh_row(row: Dictionary) -> Dictionary:
	var fresh := workspace.find_row(row.doc.path, row.def.type, row.def.id, row.def.mode, row.get("ordinal", 0))
	if not fresh.is_empty() and row.has("script_field"):
		fresh = fresh.duplicate()
		fresh.script_field = row.script_field
	return fresh

func focus_definition(row: Dictionary) -> void:
	_load_layout()
	focused_script.clear()
	focused_definition = row.duplicate()
	focused_id = str(row.def.id) if not row.is_empty() else ""
	show_everything = false
	if scope_button != null:
		scope_button.text = "Show all stories"
	if graph != null:
		graph.scroll_offset = Vector2.ZERO
		refresh()

func focus_script(row: Dictionary, field: String) -> void:
	_load_layout()
	focused_id = str(row.def.id)
	show_everything = false
	focused_script = row.duplicate()
	focused_script.script_field = field
	graph.scroll_offset = Vector2.ZERO
	refresh()

func _fresh_option(row: Dictionary, line: int) -> Dictionary:
	for option: Dictionary in StoryGraph.choices(row):
		if int(option.line) == line:
			return option
	return {}

func _finish(row: Dictionary, error: String) -> void:
	if not error.is_empty():
		problem.emit(error)
		return
	workspace.reindex()
	changed.emit(_fresh_row(row))

func _commit_response(row: Dictionary, option: Dictionary, editor: LineEdit) -> void:
	if not is_instance_valid(editor) or editor.text.strip_edges() == str(option.label):
		return
	var current := _fresh_row(row)
	if current.is_empty():
		problem.emit("This response changed. Reopen it before editing.")
		return
	var fresh := _fresh_option(current, int(option.line))
	if fresh.is_empty():
		problem.emit("This response changed. Reopen it before editing.")
		return
	_finish(current, StoryGraph.set_choice_text(current, fresh, editor.text))

func _commit_description(row: Dictionary, option: Dictionary, editor: LineEdit) -> void:
	if not is_instance_valid(editor) or editor.text.strip_edges() == str(option.description):
		return
	var current := _fresh_row(row)
	if current.is_empty():
		problem.emit("This response changed. Reopen it before editing.")
		return
	var fresh := _fresh_option(current, int(option.line))
	if fresh.is_empty():
		problem.emit("This response changed. Reopen it before editing.")
		return
	_finish(current, StoryGraph.set_choice_description(current, fresh, editor.text))

func _toggle_choice(enabled: bool, row: Dictionary, option: Dictionary, tag: String) -> void:
	var current := _fresh_row(row)
	if current.is_empty():
		return
	var fresh := _fresh_option(current, int(option.line))
	if not fresh.is_empty():
		_finish(current, StoryGraph.set_choice_toggle(current, fresh, tag, enabled))

func _commit_speech(row: Dictionary, passage: Dictionary, editor: TextEdit) -> void:
	if not is_instance_valid(editor) or not editor.editable or editor.text == str(passage.text):
		return
	var current := _fresh_row(row)
	if current.is_empty():
		problem.emit("This passage changed. Reopen it before editing.")
		return
	_finish(current, StoryGraph.set_speech(current, passage, editor.text))

func _add_response(row: Dictionary) -> void:
	var current := _fresh_row(row)
	if not current.is_empty():
		_finish(current, StoryGraph.add_choice(current))

func _add_speech(row: Dictionary) -> void:
	var current := _fresh_row(row)
	if not current.is_empty():
		_finish(current, StoryGraph.add_speech(current))

func _ask_remove(row: Dictionary, option: Dictionary) -> void:
	remove_row = row
	remove_option = option
	remove_kind = "response"
	remove_dialog.dialog_text = "Remove this response and its story actions? Comments and attribution will be kept."
	remove_dialog.popup_centered()

func _ask_clear_condition(row: Dictionary, option: Dictionary) -> void:
	remove_row = row
	remove_option = option
	remove_kind = "condition"
	remove_dialog.dialog_text = "Remove all visibility conditions from this response?"
	remove_dialog.popup_centered()

func _ask_remove_effect(row: Dictionary, option: Dictionary, action: Dictionary) -> void:
	remove_row = row
	remove_option = option
	remove_action = action
	remove_kind = "effect"
	remove_dialog.dialog_text = "Remove this action from the response?"
	remove_dialog.popup_centered()

func _remove_response() -> void:
	var current := _fresh_row(remove_row)
	if current.is_empty():
		return
	if remove_kind == "effect" and remove_option.is_empty():
		_finish(current, StoryGraph.set_effect(current, remove_action, ""))
		return
	var option := _fresh_option(current, int(remove_option.line))
	if option.is_empty():
		return
	match remove_kind:
		"condition": _finish(current, StoryGraph.clear_condition(current, option))
		"effect": _finish(current, StoryGraph.set_effect(current, remove_action, ""))
		_: _finish(current, StoryGraph.remove_choice(current, option))

func _connect_response(from: StringName, port: int, to: StringName, _to_port: int) -> void:
	if not graph_rows.has(from) or not graph_rows.has(to):
		return
	var source: Dictionary = _fresh_row(graph_rows[from])
	var target: Dictionary = graph_rows[to]
	var options: Array = graph_options[from]
	if source.is_empty() or not source.doc.writable:
		problem.emit("Choose a story in your working pack to create a link.")
		return
	var error := ""
	var has_continuation: bool = graph_continuations.get(from, false)
	var play_index := port - options.size() - (1 if has_continuation else 0)
	if port == options.size() and has_continuation:
		error = StoryGraph.set_primary_transition(source, str(target.def.id))
	elif play_index >= 0 and play_index < (graph_play_links.get(from, []) as Array).size():
		error = StoryGraph.set_play_target(source, graph_play_links[from][play_index], str(target.def.id))
	elif port >= 0 and port < options.size():
		var option := _fresh_option(source, int(options[port].line))
		if option.is_empty():
			problem.emit("This response changed. Reopen it before linking.")
			return
		error = StoryGraph.set_transition(source, option, str(target.def.id))
	else:
		return
	if error.is_empty() and target.root != workspace.target:
		var dependency_error := workspace.add_requirement(target.pack)
		if not dependency_error.is_empty():
			problem.emit("The link was made. Add the reference pack as a dependency: " + dependency_error)
	_finish(source, error)

func _disconnect_response(from: StringName, port: int, _to: StringName, _to_port: int) -> void:
	if not graph_rows.has(from) or not graph_options.has(from):
		return
	var source: Dictionary = _fresh_row(graph_rows[from])
	var options: Array = graph_options[from]
	if source.is_empty():
		return
	var has_continuation: bool = graph_continuations.get(from, false)
	var play_index := port - options.size() - (1 if has_continuation else 0)
	if port == options.size() and has_continuation:
		_finish(source, StoryGraph.set_primary_transition(source, ""))
	elif play_index >= 0 and play_index < (graph_play_links.get(from, []) as Array).size():
		_finish(source, StoryGraph.set_play_target(source, graph_play_links[from][play_index], ""))
	elif port >= 0 and port < options.size():
		var option := _fresh_option(source, int(options[port].line))
		if not option.is_empty():
			_finish(source, StoryGraph.set_transition(source, option, ""))

func _effect_label(text: String) -> String:
	var readable := AuthoringCatalog.effect_label(text)
	if readable != text: return readable
	var effect := Effect.compile(text)
	match str(effect.get("op", "")):
		"give": return "Give " + str(effect.get("item", "an item"))
		"take": return "Take " + str(effect.get("item", "an item"))
		"quest": return "Update " + str(effect.get("quest", "quest")) + " → " + str(effect.get("stage", ""))
		"schedule": return "Schedule a story"
		"set": return "Set " + str(effect.get("path", "value")) + " to " + _expression_label(effect.get("value", {}))
		"change": return ("Increase " if int(effect.get("sign", 1)) > 0 else "Decrease ") + str(effect.get("path", "value"))
		"spend": return "Pass time"
		_: return "Story action"

func _build_picker() -> void:
	picker = ConfirmationDialog.new()
	picker.title = "Choose an action"
	picker.ok_button_text = "Add"
	picker.dialog_hide_on_ok = false
	picker_layout = AuthoringLayout.new()
	picker_layout.custom_minimum_size = Vector2(720, 420)
	picker.add_child(picker_layout)
	add_child(picker)
	picker_layout.footer.hide()
	picker_layout.numbered = false
	picker_layout.section_requested.connect(func(category: String) -> void:
		picker_category = category
		picker_layout.set_sections(picker_categories, category)
		_filter_picker())
	picker_layout.page.add_child(AuthoringLayout.label("Choose what should happen", 23))
	picker_search = LineEdit.new()
	picker_search.placeholder_text = "Search what you want to happen…"
	picker_search.text_changed.connect(func(_text: String) -> void: _filter_picker())
	picker_layout.page.add_child(picker_search)
	picker_list = ItemList.new()
	picker_list.custom_minimum_size.y = 250
	picker_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	picker_list.item_selected.connect(_preview_picker)
	picker_list.item_activated.connect(func(_index: int) -> void: _apply_picker())
	picker_layout.page.add_child(picker_list)
	picker_layout.sheet.add_child(AuthoringLayout.label("YOUR SELECTION", 13, true))
	picker_image = TextureRect.new()
	picker_image.custom_minimum_size.y = 120
	picker_image.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	picker_image.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	picker_layout.sheet.add_child(picker_image)
	picker_image.hide()
	picker_preview = AuthoringLayout.label("Choose an entry to see what it does.", 17)
	picker_layout.sheet.add_child(picker_preview)
	picker_amount_label = AuthoringLayout.label("Amount", 14, true)
	picker_layout.sheet.add_child(picker_amount_label)
	picker_amount = SpinBox.new()
	picker_amount.min_value = 1
	picker_amount.max_value = 1000000
	picker_amount.value = 1
	picker_amount.value_changed.connect(func(_value: float) -> void: _update_picker_preview())
	picker_layout.sheet.add_child(picker_amount)
	picker_layout.sheet.move_child(picker_amount_label, 1)
	picker_layout.sheet.move_child(picker_amount, 2)
	picker_error = AuthoringLayout.label("", 14)
	picker_error.theme_type_variation = "ErrorLabel"
	picker_layout.sheet.add_child(picker_error)
	picker.confirmed.connect(_apply_picker)
	picker_new_story = picker.add_button("+ New story…", false)
	picker_new_story.pressed.connect(func() -> void:
		var current := _fresh_row(picker_row)
		if current.is_empty() or picker_option.is_empty(): return
		var option := _fresh_option(current, int(picker_option.line))
		if option.is_empty(): return
		picker.hide()
		next_story_requested.emit(current, option))

func _open_existing_effect(row: Dictionary, option: Dictionary, action: Dictionary) -> void:
	_open_picker(row, option, "effect")
	picker_action = action
	picker.title = "Change this action"
	var original := Effect.compile(str(action.text))
	var amount: Dictionary = original.get("amount", original.get("times", {}))
	if not amount.is_empty() and (amount.size() != 1 or amount.get("value", {}).get("op", "") != "num" or float(amount.get("value", {}).get("v", 0)) < 1 or float(amount.get("value", {}).get("v", 0)) > picker_amount.max_value):
		picker_preview.text = "Current: " + AuthoringCatalog.effect_label(str(action.text)) + "\n\nChoose a replacement to change this action."
		return
	if original.get("op", "") == "condition" and (int(original.turns) < 1 or int(original.turns) > picker_amount.max_value):
		picker_preview.text = "This duration is outside the guided range. Choose a replacement, or cancel to preserve it."
		return
	var identity := original.duplicate()
	for key: String in ["quiet", "amount", "times", "turns"]: identity.erase(key)
	for entry: Dictionary in picker_entries:
		var candidate := Effect.compile(str(entry.value)).duplicate()
		for key: String in ["quiet", "amount", "times", "turns"]: candidate.erase(key)
		if candidate != identity: continue
		picker_category = str(entry.category)
		picker_layout.set_sections(picker_categories, picker_category)
		_filter_picker()
		for index in picker_list.item_count:
			if picker_list.get_item_metadata(index).value != entry.value: continue
			picker_list.select(index)
			picker_list.ensure_current_is_visible()
			_preview_picker(index)
			if original.get("op", "") == "condition": picker_amount.value = int(original.turns)
			elif not amount.is_empty(): picker_amount.value = float(amount.value.v)
			return
	picker_preview.text = "Current: " + AuthoringCatalog.effect_label(str(action.text)) + "\n\nSpecialized controls for this action are not available yet. Choose a supported replacement, or cancel to keep it."

func _open_picker(row: Dictionary, option: Dictionary, mode: String, initial_category: String = "") -> void:
	picker_action = {}
	picker_branch = {}
	picker_passage = {}
	picker_row = row
	picker_original = row.doc.text
	picker_option = option
	picker_mode = mode
	picker.title = "Choose a condition" if mode in ["condition", "branch_condition", "passage_condition", "event_condition"] else ("Choose the next story" if mode == "destination" else ("Choose a story to play" if mode == "play" else "Choose an action"))
	picker_entries.clear()
	if mode == "image":
		picker.title = "Choose a story image"
		var seen := {}
		# Match the runtime's first pack / extension precedence for image IDs.
		for pack: Dictionary in workspace.preview_content().packs:
			var folder: String = str(pack.path).path_join("images")
			if not DirAccess.dir_exists_absolute(folder): continue
			var ids: Array[String] = []
			for file: String in DirAccess.get_files_at(folder):
				if file.get_extension() in ["png", "jpg", "jpeg", "webp"] and file.get_basename() not in ids: ids.append(file.get_basename())
			for id: String in ids:
				if seen.has(id): continue
				for extension: String in ["png", "jpg", "jpeg", "webp"]:
					var path := folder.path_join(id + "." + extension)
					if not FileAccess.file_exists(path): continue
					seen[id] = true
					var artist := workspace.preview_content().typed_value("image", id, "artist")
					picker_entries.append({"label": id.capitalize() + " · " + str(pack.id), "value": id, "image_path": path, "category": "Images", "help": "Artist: " + (artist if not artist.is_empty() else "No credit entry yet") + "\nChoose Pack → Import image to add your own artwork.", "pack": pack.id, "root": pack.path})
					break
	if mode == "effect" or _condition_mode():
		for id: String in workspace.preview_content().all_of("condition"):
			var definition := workspace.preview_content().get_def("condition", id)
			var name := workspace.preview_content().typed_value("condition", id, "name", id)
			var owner := workspace.owner(definition.path)
			var pack: String = workspace.manifest(owner).get("id", "")
			if mode == "effect":
				picker_entries.append({"label": "Apply " + name, "value": "condition " + id + " for 1 turns", "template": "condition " + id + " for {amount} turns", "amount_label": "Duration in turns", "default_amount": 2, "category": "Temporary conditions", "help": "Apply the bonuses once; remove them when the duration ends. Applying again extends the duration without stacking bonuses. Configure bonuses in the condition’s Details → Temporary bonuses.", "pack": pack, "root": owner})
			else:
				for has: bool in [true, false]:
					picker_entries.append({"label": name + (" is active" if has else " is not active"), "value": "player " + ("has" if has else "does not have") + " condition " + id, "category": "Temporary conditions", "help": "Check whether this timed condition or meter stage is active.", "pack": pack, "root": owner})
	if mode == "effect":
		for reaction: Dictionary in AuthoringCatalog.basic_reactions():
			reaction.pack = ""
			reaction.root = ""
			picker_entries.append(reaction)
		for stat: String in ["xp", "score", "strength", "dexterity", "stamina", "charisma", "intelligence", "perception"]:
			for sign: String in ["+", "-"]:
				picker_entries.append({"label": ("Increase " if sign == "+" else "Decrease ") + stat.capitalize(), "value": "player." + stat + " " + sign + " 1", "category": "Attributes", "help": "Change the player's " + stat + ".", "pack": "", "root": ""})
	if mode in ["condition", "branch_condition", "passage_condition", "event_condition"]:
		picker_entries.append({"label": "Player health is below…", "value": "player.hp < 10", "template": "player.hp < {amount}", "amount_label": "Health below", "default_amount": 10, "category": "Health & needs", "help": "This condition passes only below the chosen number of health points.", "pack": "", "root": ""})
	if mode == "effect" and row.def.type == "event" and not ContentDB.found_by(row.doc.field_value(row.def, "found by")).leaving.is_empty():
		picker_entries.append({"label": "Continue the move · let the player leave", "value": "continue moving", "pack": "", "root": ""})
	if mode in ["condition", "branch_condition", "passage_condition", "event_condition"]:
		for time: String in ["day", "night"]:
			picker_entries.append({"label": "It is " + time, "value": "time is " + time, "pack": "", "root": ""})
	if mode in ["play", "destination"]:
		for entry: Dictionary in workspace.rows:
			if entry.def.type in ["scene", "menu"] and entry.def.mode == "define":
				picker_entries.append({"label": "Play " + EventTriggers.title_for(workspace, entry.def.type, entry.def.id) + " · " + str(entry.pack), "value": entry.def.id, "pack": entry.pack, "root": entry.root})
	if mode == "effect":
		for entry: Dictionary in workspace.rows:
			if entry.def.type != "form" or entry.def.mode != "define": continue
			var id: String = entry.def.id
			var name := EventTriggers.title_for(workspace, "form", id)
			picker_entries.append({"label": "Attempt mutation toward " + name, "value": "infect " + id, "template": "infect " + id + " {amount} times", "amount_label": "Mutation attempts", "category": "Body changes", "help": "Attempt gradual mutation; infection rules and resistance apply. To respect food-infection protections, use the item's Food mutation setting.", "pack": entry.pack, "root": entry.root})
			picker_entries.append({"label": "Transform fully into " + name, "value": "transform into " + id, "category": "Body changes", "help": "Transform every defined part at once, bypassing gradual-infection blocking and resistance.", "pack": entry.pack, "root": entry.root})
	for entry: Dictionary in workspace.rows:
		if mode in ["play", "destination", "image"] or entry.def.type != "item" or entry.def.mode != "define":
			continue
		var id: String = entry.def.id
		var display: String = entry.def.fields["name"].value if entry.def.fields.has("name") else id
		if mode in ["condition", "branch_condition", "passage_condition", "event_condition"]:
			picker_entries.append({"label": "Player has " + display, "value": "player has " + id, "pack": entry.pack, "root": entry.root})
			picker_entries.append({"label": "Player does not have " + display, "value": "player does not have " + id, "pack": entry.pack, "root": entry.root})
		else:
			picker_entries.append({"label": "Give " + display, "value": "give " + id, "pack": entry.pack, "root": entry.root})
			picker_entries.append({"label": "Take " + display, "value": "take " + id, "pack": entry.pack, "root": entry.root})
	if mode not in ["play", "destination", "image"]:
		var content := workspace.preview_content()
		var keys: Array = content.values.keys()
		keys.sort()
		for key: String in keys:
			var declaration: Dictionary = content.values[key]
			var root := workspace.owner(str(declaration.get("path", "")))
			var pack: String = workspace.manifest(root).get("id", "") if not root.is_empty() else ""
			var kind := str(declaration.get("kind", ""))
			if kind == "flag":
				if mode in ["condition", "branch_condition", "passage_condition", "event_condition"]:
					picker_entries.append({"label": key + " is set", "value": key, "pack": pack, "root": root})
					picker_entries.append({"label": key + " is not set", "value": "not " + key, "pack": pack, "root": root})
				else:
					picker_entries.append({"label": "Set " + key, "value": key + " = yes", "pack": pack, "root": root})
					picker_entries.append({"label": "Clear " + key, "value": key + " = no", "pack": pack, "root": root})
			elif kind == "states":
				for state: String in declaration.get("states", []):
					var target := "quest " + key.trim_prefix("quest.") if key.begins_with("quest.") else key
					var label := (key + " is " + state) if mode in ["condition", "branch_condition", "passage_condition", "event_condition"] else ("Set " + key + " to " + state)
					var value := target + (" is " if mode in ["condition", "branch_condition", "passage_condition", "event_condition"] else " = ") + state
					picker_entries.append({"label": label, "value": value, "pack": pack, "root": root})
			elif kind == "number":
				if mode in ["condition", "branch_condition", "passage_condition", "event_condition"]:
					picker_entries.append({"label": key + " is above zero", "value": key + " > 0", "pack": pack, "root": root})
					for comparison: Array in [["is at least", ">="], ["is at most", "<="], ["equals", "="]]:
						picker_entries.append({"label": key + " " + str(comparison[0]), "value": key + " " + str(comparison[1]) + " 1", "template": key + " " + str(comparison[1]) + " {amount}", "amount_label": "Compare with", "min_amount": -1000000, "help": "Check this saved number against the number you choose.", "pack": pack, "root": root})
				else:
					picker_entries.append({"label": "Increase " + key, "value": key + " + 1", "pack": pack, "root": root})
					picker_entries.append({"label": "Decrease " + key, "value": key + " - 1", "pack": pack, "root": root})
			elif kind == "time":
				if mode in ["condition", "branch_condition", "passage_condition", "event_condition"]:
					picker_entries.append({"label": "Time passed since " + key, "value": "since " + key + " >= 1 turns", "template": "since " + key + " >= {amount} turns", "amount_label": "Turns passed", "min_amount": 0, "help": "Check that at least this many turns have passed. An unrecorded time counts as long ago and also passes this check.", "pack": pack, "root": root})
				else:
					picker_entries.append({"label": "Record the current time in " + key, "value": key + " = now", "help": "Remember this moment so a later condition can check the time passed.", "pack": pack, "root": root})
			elif kind == "list" and mode in ["condition", "branch_condition", "passage_condition", "event_condition"]:
				picker_entries.append({"label": key + " is empty", "value": key + " is empty", "pack": pack, "root": root})
				picker_entries.append({"label": key + " has entries", "value": key + " is not empty", "pack": pack, "root": root})
	picker_category = "All" if initial_category.is_empty() else initial_category
	picker_categories = [{"key": "All", "title": "All"}]
	var available: Dictionary = {}
	for entry: Dictionary in picker_entries:
		entry.category = entry.get("category", _entry_category(entry))
		available[entry.category] = true
	for category: String in ["Images", "Temporary conditions", "Health & needs", "Body changes", "Attributes", "Items", "Story progress", "Saved values", "Time & movement", "Stories"]:
		if available.has(category): picker_categories.append({"key": category, "title": category})
	if not available.has(picker_category): picker_category = "All"
	picker_layout.set_sections(picker_categories, picker_category)
	picker_layout.page.get_child(0).text = picker.title
	picker.ok_button_text = "Use condition" if _condition_mode() else ("Connect selected story" if mode == "destination" else ("Play selected story" if mode == "play" else "Add action"))
	if mode == "image": picker.ok_button_text = "Use image"
	picker_new_story.visible = mode == "destination"
	picker_error.text = ""
	picker_search.placeholder_text = "Search artwork by name or pack…" if mode == "image" else "Search what you want to happen…"
	picker_search.text = ""
	_filter_picker()
	picker.popup_centered_clamped(Vector2i(790, 550), 0.9)
	picker_search.grab_focus()

func _condition_mode() -> bool:
	return picker_mode in ["condition", "branch_condition", "passage_condition", "event_condition"]

func _entry_category(entry: Dictionary) -> String:
	if picker_mode in ["play", "destination"]: return "Stories"
	var compiled := Condition.compile(entry.value) if _condition_mode() else Effect.compile(entry.value)
	var op := str(compiled.get("op", ""))
	if op in ["has_item", "give", "take"]: return "Items"
	if op == "quest" or str(compiled.get("path", "")).begins_with("quest."): return "Story progress"
	if op in ["time", "continue_moving", "spend"] or entry.value == "continue moving": return "Time & movement"
	return "Saved values"

func _filter_picker() -> void:
	picker_list.clear()
	var query := picker_search.text.to_lower().strip_edges()
	for entry: Dictionary in picker_entries:
		if picker_category != "All" and entry.get("category", "") != picker_category: continue
		if not query.is_empty() and query not in (str(entry.label) + " " + str(entry.value) + " " + str(entry.get("help", "")) + " " + str(entry.get("keywords", ""))).to_lower(): continue
		picker_list.add_item(entry.label)
		picker_list.set_item_metadata(picker_list.item_count - 1, entry)
	picker.get_ok_button().disabled = true
	picker_preview.text = "No matching choices. Try another category or search." if picker_list.item_count == 0 else "Choose an entry to see what it does."
	picker_amount.hide()
	picker_amount_label.hide()
	picker_image.hide()
	if picker_mode == "image" and picker_list.item_count == 0: picker_preview.text = "No matching artwork. Choose Pack → Import image, then reopen this chooser."

func _preview_picker(_index: int) -> void:
	picker_error.text = ""
	var selected := picker_list.get_selected_items()
	if selected.is_empty(): return
	var entry: Dictionary = picker_list.get_item_metadata(selected[0])
	var action := Effect.compile(entry.value) if picker_mode == "effect" else {}
	picker_amount.visible = entry.has("template") or action.get("op", "") in ["give", "take", "change"]
	picker_amount_label.visible = picker_amount.visible
	picker_amount_label.text = str(entry.get("amount_label", "Amount"))
	picker_amount.min_value = float(entry.get("min_amount", 1))
	picker_amount.set_value_no_signal(float(entry.get("default_amount", 1)))
	picker.get_ok_button().disabled = false
	_update_picker_preview()

func _picker_entry() -> Dictionary:
	var indexes := picker_list.get_selected_items()
	if indexes.is_empty(): return {}
	var entry: Dictionary = picker_list.get_item_metadata(indexes[0]).duplicate()
	if entry.has("template"):
		entry.value = str(entry.template).replace("{amount}", str(int(picker_amount.value)))
	elif picker_mode == "effect" and picker_amount.visible:
		var action := Effect.compile(entry.value)
		if action.get("op", "") in ["give", "take"]:
			entry.value = str(action.op) + " " + str(action.item if not str(action.item).is_empty() else action.get("item_path", "")) + " " + str(int(picker_amount.value))
		elif action.get("op", "") == "change":
			entry.value = str(action.path) + (" + " if int(action.sign) > 0 else " - ") + str(int(picker_amount.value))
	if not picker_action.is_empty() and Effect.compile(str(picker_action.text)).get("quiet", false): entry.value = str(entry.value) + " quietly"
	return entry

func _update_picker_preview() -> void:
	var entry := _picker_entry()
	if entry.is_empty(): return
	var context := "Runs before the first set of player responses or final story link, after preceding steps. Earlier branches can skip it."
	if not picker_action.is_empty(): context = "Replaces this action at the same point, keeping its surrounding conditions."
	if picker_mode == "play": context = "Plays another story and returns here. Added before the final story link, after existing steps."
	if picker_mode == "destination": context = "Continues to the selected story after this response."
	picker_image.hide()
	if picker_mode == "image":
		var picture := Image.load_from_file(str(entry.image_path))
		if picture != null:
			picker_image.texture = ImageTexture.create_from_image(picture)
			picker_image.show()
		context = "Shown at the beginning of this interaction, before its text and choices." if picker_passage.is_empty() else "Replaces this image at the same point in the story."
	if picker_mode != "image" and picker_row.def.type == "item" and picker_row.get("script_field", "") == "use":
		context = "When the player uses this item. Added before the first set of player responses or final story link." if picker_action.is_empty() else "When the use story reaches this reaction. Its position and surrounding conditions stay the same."
	if picker_mode != "image" and picker_row.def.type == "condition" and picker_row.get("script_field", "") == "each turn":
		context = "Runs on each active turn before the expiry turn. This is a repeated action; it is not reversed when the condition ends."
	if picker_mode == "event_condition": context = "This event can run only when this requirement passes."
	elif _condition_mode(): context = "This controls when this choice or passage is available."
	elif not picker_option.is_empty(): context = "After the player chooses: “" + str(picker_option.label) + "”"
	picker_preview.text = str(entry.label) + ("\n" + picker_amount_label.text + ": %d" % int(picker_amount.value) if picker_amount.visible else "") + "\n\n" + str(entry.get("help", "")) + "\n\n" + context

func _apply_picker() -> void:
	var entry := _picker_entry()
	if entry.is_empty():
		picker_error.text = "Choose an entry first."
		return
	var current := _fresh_row(picker_row)
	if current.is_empty() or current.doc.text != picker_original:
		picker_error.text = "This story changed. Reopen the chooser before applying."
		return
	var option: Dictionary = {}
	if not picker_option.is_empty():
		option = _fresh_option(current, int(picker_option.line))
		if option.is_empty():
			picker_error.text = "This response changed. Reopen it before editing."
			return
	var before: String = current.doc.text
	var manifest: PackDocument = workspace.documents[workspace.target.path_join("pack.fsc")]
	var manifest_before := manifest.text
	var error := ""
	if picker_mode == "image":
		error = StoryGraph.set_image(current, picker_passage, entry.value)
	elif picker_mode == "event_condition":
		var previous: String = current.doc.field_value(current.def, "requires")
		# Preserve both requirements when adding another condition.
		var condition: String = entry.value if previous.is_empty() else "(" + previous + ") and (" + str(entry.value) + ")"
		if Condition.compile(condition).has("error"):
			picker_error.text = "The existing condition cannot be combined safely and has been preserved."
			return
		error = current.doc.set_field(current.def, "requires", condition)
	elif picker_mode == "passage_condition":
		error = StoryGraph.make_conditional_text(current, picker_passage, entry.value)
	elif picker_mode == "branch_condition":
		error = StoryGraph.set_branch_condition(current, picker_branch, entry.value)
	elif picker_mode == "play":
		error = StoryGraph.add_story_step(current, "play " + str(entry.value))
	elif picker_mode == "destination":
		error = StoryGraph.set_transition(current, option, entry.value)
	elif picker_mode == "condition" and option.is_empty():
		picker_error.text = "Select a response to add a condition."
		return
	elif picker_mode == "condition":
		error = StoryGraph.add_condition(current, option, entry.value)
	elif not picker_action.is_empty():
		error = StoryGraph.set_effect(current, picker_action, entry.value)
	elif option.is_empty():
		error = StoryGraph.add_primary_effect(current, entry.value)
	else:
		error = StoryGraph.add_effect(current, option, entry.value)
	if error.is_empty() and not str(entry.root).is_empty() and entry.root != workspace.target:
		error = workspace.add_requirement(entry.pack)
	if not error.is_empty():
		current.doc.change(before)
		manifest.change(manifest_before)
		workspace.reindex()
		picker_error.text = error
		return
	_finish(current, "")
	picker.hide()

static func _display_dynamic(value: String) -> String:
	var result := value
	result = RegEx.create_from_string("\\[if ([^\\]]+)\\]").sub(result, "\nIf $1: ", true)
	result = RegEx.create_from_string("\\[else if ([^\\]]+)\\]").sub(result, "\nOtherwise if $1: ", true)
	result = result.replace("[else]", "\nOtherwise: ").replace("[end if]", "")
	result = result.replace("[one of]", "").replace("[or]", " / ")
	for ending in ["[at random]", "[purely at random]", "[cycling]", "[stopping]", "[sticky]", "[in random order]"]:
		result = result.replace(ending, "")
	return result.strip_edges()

static func _condition_label(condition: Dictionary) -> String:
	match str(condition.get("op", "")):
		"and": return _condition_label(condition.a) + " and " + _condition_label(condition.b)
		"or": return _condition_label(condition.a) + " or " + _condition_label(condition.b)
		"not": return "not " + _condition_label(condition.a)
		"has_condition": return str(condition.id).capitalize() + (" is not active" if condition.get("neg", false) else " is active")
		"truthy": return str(condition.get("path", "a flag")) + " is set"
		"has_item": return str(condition.get("who", "player")) + (" does not have " if condition.get("neg", false) else " has ") + str(condition.get("item", "an item"))
		"quest": return str(condition.get("quest", "Quest")) + " " + str(condition.get("rel", "is")) + " " + str(condition.get("stage", ""))
		"time": return "time is " + ("not " if condition.get("neg", false) else "") + str(condition.get("slot", ""))
		"order": return str(condition.get("path", "value")) + " is " + str(condition.get("rel", "")) + " " + str(condition.get("state", ""))
		"cmp": return _expression_label(condition.get("left", {})) + " " + str(condition.get("cmp", "=")) + " " + _expression_label(condition.get("right", {}))
		_: return "a saved condition is met"

static func _expression_label(expression: Dictionary) -> String:
	if expression.has("v"):
		return str(expression.v)
	return "a value"

func _add_note(parent: Node, text: String) -> void:
	var note := Label.new()
	note.text = text
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	note.custom_minimum_size.x = 270
	note.add_theme_font_size_override("font_size", 12)
	parent.add_child(note)

func _add_effect_controls(parent: Node, row: Dictionary, option: Dictionary, action: Dictionary, writable: bool) -> void:
	var controls := HBoxContainer.new()
	var text := Label.new()
	text.text = "◆ " + _effect_label(str(action.text))
	text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	text.add_theme_font_size_override("font_size", 11)
	controls.add_child(text)
	var change := Button.new()
	change.text = "Change"
	change.disabled = not writable
	change.pressed.connect(_open_existing_effect.bind(row, option, action))
	controls.add_child(change)
	var remove := Button.new()
	remove.text = "Remove"
	remove.disabled = not writable
	remove.pressed.connect(_ask_remove_effect.bind(row, option, action))
	controls.add_child(remove)
	parent.add_child(controls)

func _add_branch_preview(parent: Node, row: Dictionary, node: Dictionary) -> void:
	if node.kind == "if":
		for branch: Dictionary in node.branches:
			var condition_row := HBoxContainer.new()
			var title := Label.new()
			title.text = "IF " + _condition_label(Condition.compile(str(branch.condition)))
			title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			title.custom_minimum_size.x = 210
			title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			condition_row.add_child(title)
			var change := Button.new()
			change.text = "Change"
			change.disabled = not row.doc.writable
			change.pressed.connect(_open_branch_picker.bind(row, branch))
			condition_row.add_child(change)
			parent.add_child(condition_row)
			_add_branch_body(parent, row, branch.body)
		if node["else"] is Array:
			_add_note(parent, "OTHERWISE")
			_add_branch_body(parent, row, node["else"])
	else:
		_add_note(parent, "FIGHT " + str(node.get("creature", "")))
		for outcome: String in node.outcomes:
			_add_note(parent, outcome.capitalize())
			_add_branch_body(parent, row, node.outcomes[outcome])

func _add_branch_body(parent: Node, row: Dictionary, nodes: Array) -> void:
	for node: Dictionary in nodes:
		match node.kind:
			"text": _add_bubble(parent, row, node, "STORY / SPEAKER")
			"effect": _add_effect_controls(parent, row, {}, node, row.doc.writable)
			"if", "fight": _add_branch_preview(parent, row, node)
			"choices": _add_note(parent, "Player chooses from the responses below")
			"goto": _add_note(parent, "Continue to " + str(node.target))
			"play": _add_note(parent, "Play " + StoryGraph.play_target(node) + " and return")
			"page_break": _add_note(parent, "Wait for the player to continue")
			"show": _add_note(parent, "Show image: " + str(node.image))

func _add_pause(row: Dictionary) -> void:
	var current := _fresh_row(row)
	if not current.is_empty():
		_finish(current, StoryGraph.add_story_step(current, "---"))

func _open_branch_picker(row: Dictionary, branch: Dictionary) -> void:
	_open_picker(row, {}, "branch_condition")
	picker_branch = branch

func _end_story(row: Dictionary) -> void:
	var current := _fresh_row(row)
	if not current.is_empty():
		_finish(current, StoryGraph.set_primary_transition(current, "end"))

func _make_variation(row: Dictionary, passage: Dictionary) -> void:
	var current := _fresh_row(row)
	if not current.is_empty():
		_finish(current, StoryGraph.make_variation(current, passage))

func _add_alternative(row: Dictionary, passage: Dictionary) -> void:
	var current := _fresh_row(row)
	if not current.is_empty():
		_finish(current, StoryGraph.add_alternative(current, passage))

func _open_passage_picker(row: Dictionary, passage: Dictionary) -> void:
	_open_picker(row, {}, "passage_condition")
	picker_passage = passage
	picker.title = "When should this text appear?"

func _open_image_picker(row: Dictionary, node: Dictionary) -> void:
	_open_picker(row, {}, "image")
	picker_passage = node

func _add_image_controls(parent: Node, row: Dictionary, node: Dictionary) -> void:
	var controls := HBoxContainer.new()
	var change := Button.new()
	change.text = "Image: " + str(node.image).capitalize()
	change.clip_text = true
	change.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	change.disabled = not row.doc.writable
	change.pressed.connect(_open_image_picker.bind(row, node))
	controls.add_child(change)
	var remove := Button.new()
	remove.text = "Remove"
	remove.disabled = not row.doc.writable
	remove.pressed.connect(func() -> void:
		var current := _fresh_row(row)
		if not current.is_empty(): _finish(current, StoryGraph.set_image(current, node, "")))
	controls.add_child(remove)
	parent.add_child(controls)
