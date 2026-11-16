class_name WorldCanvas
extends VBoxContainer
## Visualize places and add directional exits without rewriting their other fields.

signal selected(row: Dictionary)
signal open_requested(row: Dictionary)
signal changed(row: Dictionary)
signal problem(message: String)
signal event_requested(place: Dictionary)

const DIRECTIONS := ["north", "northeast", "east", "southeast", "south", "southwest", "west", "northwest", "up", "down", "inside", "outside"]

var workspace: PackWorkspace
var graph: GraphEdit
var nodes: Dictionary = {}
var rows_by_node: Dictionary = {}
var exits_by_place: Dictionary = {}
var contents_by_place: Dictionary = {}
var positions: Dictionary = {}
var layout_target := ""
var exit_dialog: ConfirmationDialog
var direction: OptionButton
var one_way: CheckButton
var exit_source: Dictionary = {}
var exit_target: Dictionary = {}
var remove_exit_dialog: ConfirmationDialog
var remove_exit_options: OptionButton
var inspector: VBoxContainer
var inspected_id := ""
var places_by_id: Dictionary = {}

func _ready() -> void:
	var toolbar := HBoxContainer.new()
	var title := Label.new()
	title.text = "PLACES & CONNECTIONS"
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	toolbar.add_child(title)
	var fit := Button.new()
	fit.text = "Fit places"
	fit.pressed.connect(_fit_places)
	toolbar.add_child(fit)
	add_child(toolbar)
	var hint := Label.new()
	hint.text = "Drag a right connector to add an exit; right-click a connection to remove an exit. Labels show each direction."
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(hint)
	graph = DropSurface.new()
	graph.workspace = workspace
	graph.size_flags_vertical = Control.SIZE_EXPAND_FILL
	graph.minimap_enabled = false
	graph.right_disconnects = true
	graph.connection_request.connect(_request_exit)
	graph.disconnection_request.connect(_request_remove_exit)
	graph.node_selected.connect(_select_node)
	var split := HSplitContainer.new()
	split.size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_child(split)
	split.add_child(graph)
	graph.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var panel := PanelContainer.new()
	panel.custom_minimum_size.x = 300
	split.add_child(panel)
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	panel.add_child(scroll)
	inspector = VBoxContainer.new()
	inspector.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(inspector)
	_render_inspector()
	_build_dialogs()

func configure(value: PackWorkspace) -> void:
	workspace = value

func _build_dialogs() -> void:
	exit_dialog = ConfirmationDialog.new()
	exit_dialog.title = "Connect places"
	exit_dialog.ok_button_text = "Add exit"
	var form := VBoxContainer.new()
	form.custom_minimum_size = Vector2(390, 0)
	var label := Label.new()
	label.text = "Which direction does the player travel?"
	form.add_child(label)
	direction = OptionButton.new()
	for value: String in DIRECTIONS:
		direction.add_item(value.capitalize())
	form.add_child(direction)
	one_way = CheckButton.new()
	one_way.text = "This exit is one-way"
	form.add_child(one_way)
	var note := Label.new()
	note.text = "A matching return exit is created by default. Shift-drag chooses one way."
	form.add_child(note)
	exit_dialog.add_child(form)
	exit_dialog.confirmed.connect(_add_exit)
	add_child(exit_dialog)
	remove_exit_dialog = ConfirmationDialog.new()
	remove_exit_dialog.title = "Remove an exit"
	remove_exit_dialog.ok_button_text = "Remove exit"
	var remove_form := VBoxContainer.new()
	remove_form.custom_minimum_size.x = 420
	var remove_hint := Label.new()
	remove_hint.text = "Choose which direction to remove. The other direction stays."
	remove_form.add_child(remove_hint)
	remove_exit_options = OptionButton.new()
	remove_form.add_child(remove_exit_options)
	remove_exit_dialog.add_child(remove_form)
	remove_exit_dialog.confirmed.connect(_remove_exit)
	add_child(remove_exit_dialog)

func _field(row: Dictionary, key: String) -> String:
	var definition: FscParser.Definition = row.get("effective", row.def)
	if definition == null:
		definition = row.def
	return definition.fields[key].value if definition.fields.has(key) else ""

func _title(row: Dictionary) -> String:
	var value := _field(row, "name")
	return value if not value.is_empty() else str(row.def.id)

func _load_layout() -> void:
	if layout_target == workspace.target:
		return
	layout_target = workspace.target
	positions.clear()
	var config := ConfigFile.new()
	if config.load(_layout_file()) == OK:
		for key: String in config.get_section_keys("places"):
			positions[key] = config.get_value("places", key)

func _layout_file() -> String:
	return OS.get_user_data_dir().path_join("layouts").path_join("world-" + workspace.target.sha256_text() + ".cfg")

func _moved(_from: Vector2, to: Vector2, id: String) -> void:
	positions[id] = to
	var config := ConfigFile.new()
	for key: String in positions:
		config.set_value("places", key, positions[key])
	DirAccess.make_dir_recursive_absolute(_layout_file().get_base_dir())
	config.save(_layout_file())

func refresh() -> void:
	if workspace == null or graph == null:
		return
	_load_layout()
	graph.clear_connections()
	for child: Node in graph.get_children():
		if child is GraphNode:
			graph.remove_child(child)
			child.queue_free()
	nodes.clear()
	rows_by_node.clear()
	exits_by_place.clear()
	contents_by_place.clear()
	places_by_id.clear()
	var content := workspace.preview_content()
	var event_rows: Dictionary = {}
	var places: Array[Dictionary] = []
	var people: Dictionary = {}
	var items_by_place: Dictionary = {}
	var events_at: Dictionary = {}
	var events_in: Dictionary = {}
	var bases: Dictionary = {}
	for row: Dictionary in workspace.rows:
		if row.def.type != "location" or row.def.mode not in ["define", "replace"]:
			continue
		var id: String = row.def.id
		var effective: FscParser.Definition = content.get_def("location", id)
		var effective_path: String = effective.path if effective != null else ""
		if not bases.has(id) or row.doc.path == effective_path or (row.doc.writable and row.def.mode == "replace"):
			if not bases.has(id) or not (bases[id].doc.writable and bases[id].def.mode == "replace"):
				bases[id] = row
	for row: Dictionary in workspace.rows:
		var d: FscParser.Definition = row.def
		if d.type == "location":
			if d.mode != "extend" and (not bases.has(d.id) or bases[d.id] != row):
				continue
			if d.mode != "extend": places.append(row)
			for item: String in _field(row, "items").split(",", false):
				if not items_by_place.has(d.id): items_by_place[d.id] = []
				items_by_place[d.id].append(item.strip_edges())
			if d.fields.has("exits"):
				for line: FscParser.Line in d.fields.exits.children:
					var parts := line.text.split(":", true, 1)
					if parts.size() != 2: continue
					var value: String = parts[1].strip_edges()
					var entry := {"direction": parts[0].strip_edges(), "target": SceneRunner.exit_target(value), "text": value, "row": row, "line": line.number, "source": line.text}
					if not exits_by_place.has(d.id): exits_by_place[d.id] = []
					exits_by_place[d.id].append(entry)
		elif d.type == "character" and d.mode in ["define", "replace"]:
			var effective: FscParser.Definition = content.get_def("character", d.id)
			if effective == null or effective.path != row.doc.path or effective.mode != d.mode: continue
			var display := row.duplicate()
			display.effective = effective
			var home := _field(display, "lives at")
			if not home.is_empty():
				if not people.has(home): people[home] = []
				people[home].append(display)
		elif d.type == "event" and d.mode in ["define", "replace"]:
			var effective: FscParser.Definition = content.get_def("event", d.id)
			if effective == null or effective.path != row.doc.path or effective.mode != d.mode or event_rows.has(d.id): continue
			event_rows[d.id] = true
			var display := row.duplicate()
			display.effective = effective
			var found := ContentDB.found_by(_field(display, "found by"))
			for place: String in found.walking + found.travelling:
				if not events_at.has(place): events_at[place] = []
				if display not in events_at[place]: events_at[place].append(display)
			for leaving: Array in found.leaving:
				if not events_at.has(leaving[0]): events_at[leaving[0]] = []
				if display not in events_at[leaving[0]]: events_at[leaving[0]].append(display)
			for zone: String in found.zones:
				if not events_in.has(zone): events_in[zone] = []
				if display not in events_in[zone]: events_in[zone].append(display)
	for index in places.size():
		var display: Dictionary = places[index].duplicate()
		display.effective = content.get_def("location", display.def.id)
		places[index] = display
	var place_names: Dictionary = {}
	var region_bounds: Dictionary = {}
	for place: Dictionary in places:
		place_names[place.def.id] = _title(place)
		var region := _field(place, "region")
		if not region_bounds.has(region):
			region_bounds[region] = {"min_x": 2147483647, "max_x": -2147483647, "min_y": 2147483647, "max_y": -2147483647, "unplaced": 0}
		var bounds: Dictionary = region_bounds[region]
		var point := _field(place, "map").split(",")
		if point.size() == 2 and point[0].strip_edges().is_valid_int() and point[1].strip_edges().is_valid_int():
			bounds.min_x = mini(bounds.min_x, int(point[0]))
			bounds.max_x = maxi(bounds.max_x, int(point[0]))
			bounds.min_y = mini(bounds.min_y, int(point[1]))
			bounds.max_y = maxi(bounds.max_y, int(point[1]))
		else:
			bounds.unplaced += 1
	var regions: Array = region_bounds.keys()
	regions.sort()
	var region_offset := 0
	for region: String in regions:
		var bounds: Dictionary = region_bounds[region]
		if bounds.min_x == 2147483647:
			bounds.min_x = 0
			bounds.max_x = -1
			bounds.min_y = 0
			bounds.max_y = -1
		bounds.offset = region_offset
		bounds.unplaced_index = 0
		var columns: int = maxi(bounds.max_x - bounds.min_x + 1, mini(bounds.unplaced, 4))
		region_offset += (columns + 1) * 330
	var index := 0
	for row: Dictionary in places:
		var id: String = row.def.id
		places_by_id[id] = row
		var entries: Array[Dictionary] = []
		for item_id: String in items_by_place.get(id, []):
			if not item_id.is_empty(): entries.append({"kind": "Item", "id": item_id})
		for person: Dictionary in people.get(id, []): entries.append({"kind": "Character", "row": person})
		var seen_events: Dictionary = {}
		for event: Dictionary in events_at.get(id, []):
			entries.append({"kind": "At this place", "row": event})
			seen_events[event.def.id] = true
		for event: Dictionary in events_in.get(_field(row, "zone"), []):
			if not seen_events.has(event.def.id):
				entries.append({"kind": "Zone-wide", "row": event})
				seen_events[event.def.id] = true
		contents_by_place[id] = entries
		var card := GraphNode.new()
		card.name = "place_" + str(index)
		card.title = _title(row)
		card.custom_minimum_size.x = 250
		var bounds: Dictionary = region_bounds[_field(row, "region")]
		var unplaced: int = bounds.unplaced_index
		var pos := Vector2(60 + int(bounds.offset) + (unplaced % 4) * 330, 60 + (int(bounds.max_y) - int(bounds.min_y) + 2 + unplaced / 4) * 240)
		var coord := _field(row, "map").split(",")
		if coord.size() == 2 and coord[0].strip_edges().is_valid_int() and coord[1].strip_edges().is_valid_int():
			pos = Vector2(60 + int(bounds.offset) + (int(coord[0]) - int(bounds.min_x)) * 330, 60 + (int(coord[1]) - int(bounds.min_y)) * 240)
		else:
			bounds.unplaced_index += 1
		card.position_offset = positions.get(id.sha256_text(), pos)
		card.dragged.connect(_moved.bind(id.sha256_text()))
		graph.add_child(card)
		nodes[id] = card.name
		rows_by_node[card.name] = row
		var info := Label.new()
		info.text = "Your pack" if row.doc.writable else "Reference · " + str(row.pack)
		if not _field(row, "region").is_empty():
			info.text += "  ·  " + _field(row, "region").capitalize()
		if _field(row, "zone") not in ["", "none"]:
			info.text += "  ·  " + _field(row, "zone").capitalize()
		card.add_child(info)
		card.set_slot(0, true, 0, Color("b87d38"), true, 0, Color("b87d38"))
		for exit: Dictionary in exits_by_place.get(id, []):
			var exit_label := Label.new()
			var destination: String = place_names.get(exit.target, exit.text)
			if "door " in str(exit.text) and not str(exit.target).is_empty():
				destination += " · " + str(exit.text).get_slice("door ", 1).get_slice(",", 0).capitalize()
			if "one way" in str(exit.text):
				destination += " · one way"
			exit_label.text = str(exit.direction).capitalize() + " → " + destination
			card.add_child(exit_label)
		var details := Button.new()
		details.text = _contents_summary(entries)
		details.pressed.connect(_show_contents.bind(row))
		card.add_child(details)
		var add_event := Button.new()
		add_event.text = "+ Add event here"
		add_event.pressed.connect(func() -> void: event_requested.emit(row))
		card.add_child(add_event)
		index += 1
	for place: String in exits_by_place:
		if not nodes.has(place): continue
		for exit: Dictionary in exits_by_place[place]:
			if nodes.has(exit.target) and not graph.is_node_connected(nodes[place], 0, nodes[exit.target], 0) and not graph.is_node_connected(nodes[exit.target], 0, nodes[place], 0):
				graph.connect_node(nodes[place], 0, nodes[exit.target], 0)
	_render_inspector()

func _fit_places() -> void:
	var bounds := Rect2()
	var first := true
	for child: Node in graph.get_children():
		if child is GraphNode:
			var rect := Rect2(child.position_offset, child.size)
			bounds = rect if first else bounds.merge(rect)
			first = false
	if first:
		return
	var area := graph.size - Vector2(80, 80)
	var scale := minf(area.x / maxf(bounds.size.x, 1), area.y / maxf(bounds.size.y, 1))
	graph.zoom = clampf(scale, graph.zoom_min, 1.0)
	graph.scroll_offset = bounds.position * graph.zoom - Vector2(40, 40)

func _select_node(node: Node) -> void:
	if rows_by_node.has(node.name):
		_show_contents(rows_by_node[node.name])
		selected.emit(rows_by_node[node.name])

func _request_exit(from: StringName, _from_port: int, to: StringName, _to_port: int) -> void:
	if not rows_by_node.has(from) or not rows_by_node.has(to) or from == to:
		return
	exit_source = rows_by_node[from]
	exit_target = rows_by_node[to]
	var first_available := -1
	for index in DIRECTIONS.size():
		var taken := false
		for existing: Dictionary in exits_by_place.get(exit_source.def.id, []):
			if existing.direction == DIRECTIONS[index]:
				taken = true
		direction.set_item_disabled(index, taken)
		if not taken and first_available < 0:
			first_available = index
	if first_available < 0:
		problem.emit("This place already has an exit in every available direction.")
		return
	direction.select(first_available)
	one_way.button_pressed = Input.is_key_pressed(KEY_SHIFT)
	exit_dialog.title = "Connect %s → %s" % [_title(exit_source), _title(exit_target)]
	exit_dialog.popup_centered()

func _request_remove_exit(from: StringName, _from_port: int, to: StringName, _to_port: int) -> void:
	if not rows_by_node.has(from) or not rows_by_node.has(to):
		return
	var first: Dictionary = rows_by_node[from]
	var second: Dictionary = rows_by_node[to]
	remove_exit_options.clear()
	for pair: Array in [[first, second], [second, first]]:
		for exit: Dictionary in exits_by_place.get(pair[0].def.id, []):
			if exit.target != pair[1].def.id or not exit.row.doc.writable:
				continue
			remove_exit_options.add_item("%s · %s → %s" % [_title(pair[0]), str(exit.direction).capitalize(), _title(pair[1])])
			remove_exit_options.set_item_metadata(remove_exit_options.item_count - 1, exit)
	if remove_exit_options.item_count == 0:
		problem.emit("These exits belong to reference packs and cannot be removed here.")
		return
	remove_exit_dialog.popup_centered()

func _remove_exit() -> void:
	if remove_exit_options.selected < 0:
		return
	var entry: Dictionary = remove_exit_options.get_item_metadata(remove_exit_options.selected)
	var old: Dictionary = entry.row
	var current := workspace.find_row(old.doc.path, "location", old.def.id, old.def.mode, old.get("ordinal", 0))
	if current.is_empty() or not current.doc.writable:
		problem.emit("This exit changed. Reopen the map and try again.")
		return
	var field: FscParser.Field = current.def.fields.get("exits")
	var matched := false
	if field != null:
		for line: FscParser.Line in field.children:
			if line.number == int(entry.line) and line.text == entry.source:
				matched = true
	if not matched:
		problem.emit("This exit changed. Reopen the map and try again.")
		return
	var lines: PackedStringArray = current.doc.text.split("\n")
	var index: int = int(entry.line) - 1
	if index < 0 or index >= lines.size() or lines[index].strip_edges() != entry.source:
		problem.emit("This exit changed. Reopen the map and try again.")
		return
	lines.remove_at(index)
	current.doc.change("\n".join(lines))
	workspace.reindex()
	changed.emit(workspace.find_row(current.doc.path, "location", current.def.id, current.def.mode, current.get("ordinal", 0)))

func _add_exit() -> void:
	var error := workspace.connect_places(exit_source, exit_target, DIRECTIONS[direction.selected], not one_way.button_pressed)
	if not error.is_empty():
		problem.emit(error)
		return
	var updated := workspace.find_row(exit_source.doc.path, "location", exit_source.def.id, exit_source.def.mode, exit_source.get("ordinal", 0))
	changed.emit(updated)

func _show_contents(row: Dictionary) -> void:
	inspected_id = row.def.id
	_render_inspector()

func _inspector_label(text: String, parent: Node, size: int = 14) -> void:
	var label := Label.new()
	label.text = text
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.add_theme_font_size_override("font_size", size)
	parent.add_child(label)

func _contents_summary(entries: Array) -> String:
	var events := entries.filter(func(entry: Dictionary) -> bool: return entry.has("row") and entry.row.def.type == "event").size()
	var people := entries.filter(func(entry: Dictionary) -> bool: return entry.kind == "Character").size()
	return "Events %d · People %d · Items %d" % [events, people, entries.size() - events - people]

func _render_inspector() -> void:
	for child: Node in inspector.get_children():
		inspector.remove_child(child)
		child.queue_free()
	if not places_by_id.has(inspected_id):
		_inspector_label("What happens here?", inspector, 20)
		_inspector_label("Select a place to see its events, people and items.\n\nAdd an event from any place card to choose when it starts.", inspector)
		return
	var place: Dictionary = places_by_id[inspected_id]
	_inspector_label(_title(place), inspector, 21)
	var entries: Array = contents_by_place.get(inspected_id, [])
	var events := entries.filter(func(entry: Dictionary) -> bool: return entry.has("row") and entry.row.def.type == "event")
	_inspector_label(_contents_summary(entries), inspector)
	var add := Button.new()
	add.text = "+ Add event here"
	add.pressed.connect(func() -> void: event_requested.emit(place))
	inspector.add_child(add)
	var edit := Button.new()
	edit.text = "Place details"
	edit.pressed.connect(func() -> void: open_requested.emit(place))
	inspector.add_child(edit)
	_inspector_label("EVENTS", inspector, 13)
	if events.is_empty():
		_inspector_label("No automatic events are associated with this place or its zone.", inspector)
	for entry: Dictionary in events:
		var event: Dictionary = entry.row
		var panel := PanelContainer.new()
		inspector.add_child(panel)
		var card := VBoxContainer.new()
		panel.add_child(card)
		_inspector_label(_title(event), card, 17)
		_inspector_label(str(entry.kind) + " · " + ("Your pack" if event.doc.writable else "Reference"), card, 12)
		_inspector_label(EventTriggers.describe(workspace, _field(event, "found by")), card)
		var requirement := _field(event, "requires")
		_inspector_label("Only if: " + EventTriggers.describe_condition(workspace, requirement), card)
		var repeat := _field(event, "repeat")
		_inspector_label("Repeat: " + {"": "Once", "once": "Once", "always": "Whenever eligible", "until resolved": "Until the story resolves it"}.get(repeat, repeat), card)
		var found := ContentDB.found_by(_field(event, "found by"))
		if not found.walking.is_empty() or not found.travelling.is_empty():
			_inspector_label("Arrival: %s chance · %s turn cooldown" % [_field(event, "chance") if not _field(event, "chance").is_empty() else "100%", _field(event, "cooldown") if not _field(event, "cooldown").is_empty() else "0"], card)
		if _field(event, "active") == "no":
			_inspector_label("Inactive until another story enables it", card)
		if _field(event, "replaces trip") == "yes":
			_inspector_label("Replaces the fast-travel trip", card)
		var open := Button.new()
		open.text = "Open event setup" if event.doc.writable else "View event setup"
		open.pressed.connect(func() -> void: open_requested.emit(event))
		card.add_child(open)
	_inspector_label("PEOPLE & ITEMS", inspector, 13)
	for entry: Dictionary in entries:
		if entry.has("row") and entry.row.def.type == "event": continue
		var content: Dictionary = entry.get("row", {})
		if content.is_empty():
			for candidate: Dictionary in workspace.rows:
				if candidate.def.type == "item" and candidate.def.id == entry.get("id", "") and candidate.def.mode == "define":
					content = candidate
					break
		var button := Button.new()
		button.text = str(entry.kind) + " · " + (_title(content) if not content.is_empty() else str(entry.get("id", "Unknown")))
		button.clip_text = true
		button.disabled = content.is_empty()
		button.pressed.connect(func() -> void: open_requested.emit(content))
		inspector.add_child(button)
