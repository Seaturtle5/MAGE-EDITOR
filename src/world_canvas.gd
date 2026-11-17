class_name WorldCanvas
extends VBoxContainer
## The map as the game draws it, one part at a time, with what happens at the
## chosen place beside it. Ways between places are made and removed here
## without rewriting the places' other fields.

signal selected(row: Dictionary)
signal open_requested(row: Dictionary)
signal changed(row: Dictionary)
signal problem(message: String)
signal event_requested(place: Dictionary)
signal place_requested

const DIRECTIONS := ["north", "northeast", "east", "southeast", "south", "southwest", "west", "northwest", "up", "down", "inside", "outside"]
## The part of the map for places the game keeps off its map (holding rooms).
const OFF_MAP := "off map"

var workspace: PackWorkspace
var surface: MapSurface
var region_picker: OptionButton
## The parts of the map, in the game's order: {key, name, places: [ids], own: int}.
var groups: Array[Dictionary] = []
var shown_group := ""
## Every place on the map, with the part it is on.
var nodes: Dictionary = {}
## Where the game's layout puts each place within its part.
var cells: Dictionary = {}
## The ways drawn in the part that is shown: {a, b, both, door}.
var ways: Array[Dictionary] = []
var exits_by_place: Dictionary = {}
var contents_by_place: Dictionary = {}
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
var door_check: CheckButton
var door_name: LineEdit
var door_locked: CheckButton
var scope_note: Label
var _follow := false
var _pictures: Dictionary = {}

func _ready() -> void:
	var toolbar := HBoxContainer.new()
	var title := Label.new()
	title.text = "MAP"
	toolbar.add_child(title)
	region_picker = OptionButton.new()
	region_picker.tooltip_text = "The game shows one part of the world at a time: a region, or the places of an area that belong to no region."
	region_picker.fit_to_longest_item = false
	region_picker.custom_minimum_size.x = 230
	region_picker.item_selected.connect(func(index: int) -> void: show_group(str(region_picker.get_item_metadata(index))))
	toolbar.add_child(region_picker)
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	toolbar.add_child(spacer)
	var add_place := Button.new()
	add_place.text = "+ Place"
	add_place.tooltip_text = "Add a new place to the map."
	add_place.pressed.connect(func() -> void: place_requested.emit())
	toolbar.add_child(add_place)
	var smaller := Button.new()
	smaller.text = "−"
	smaller.tooltip_text = "Zoom out (the mouse wheel does the same)."
	smaller.pressed.connect(func() -> void: surface.zoom_by(1.0 / 1.25, surface.size / 2.0))
	toolbar.add_child(smaller)
	var larger := Button.new()
	larger.text = "+"
	larger.tooltip_text = "Zoom in (the mouse wheel does the same)."
	larger.pressed.connect(func() -> void: surface.zoom_by(1.25, surface.size / 2.0))
	toolbar.add_child(larger)
	var fit := Button.new()
	fit.text = "Fit"
	fit.tooltip_text = "Show every place of this part of the map."
	fit.pressed.connect(_fit_places)
	toolbar.add_child(fit)
	add_child(toolbar)
	var hint := Label.new()
	hint.text = "Drawn as the game draws its map: north is up, ◆ is a fast-travel point. Click a place to see what happens there. Drag from one place to another to connect them (Shift: one way); right-click a way to remove it. Ctrl-drag a place to give it a position of its own."
	hint.theme_type_variation = "MutedLabel"
	hint.add_theme_font_size_override("font_size", 13)
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(hint)
	scope_note = AuthoringLayout.label("", 12, true)
	add_child(scope_note)
	surface = MapSurface.new()
	surface.workspace = workspace
	surface.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	surface.size_flags_vertical = Control.SIZE_EXPAND_FILL
	surface.place_chosen.connect(_choose)
	surface.place_opened.connect(func(id: String) -> void:
		if places_by_id.has(id): open_requested.emit(places_by_id[id]))
	surface.connect_requested.connect(_request_exit)
	surface.way_chosen.connect(_request_remove_exit)
	surface.place_moved.connect(_move_place)
	var split := HSplitContainer.new()
	split.size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_child(split)
	split.add_child(surface)
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
	if surface != null: surface.workspace = value

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
	door_check = CheckButton.new()
	door_check.text = "Through a door"
	form.add_child(door_check)
	door_name = LineEdit.new()
	door_name.placeholder_text = "Name of the door, for example Cellar door"
	form.add_child(door_name)
	door_locked = CheckButton.new()
	door_locked.text = "Locked at first (a story unlocks it)"
	form.add_child(door_locked)
	door_check.toggled.connect(func(on: bool) -> void:
		door_name.visible = on
		door_locked.visible = on
		if on: door_name.grab_focus())
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

## A part of the map by its key, or {}.
func group(key: String) -> Dictionary:
	for entry: Dictionary in groups:
		if entry.key == key: return entry
	return {}

## What a part of the map is called: its region's or area's name.
func _group_name(content: ContentDB, key: String) -> String:
	if key == OFF_MAP: return "Places kept off the map"
	if key == "zone:": return "Places without a region"
	if key.begins_with("zone:"): return "Area: " + content.typed_value("zone", key.substr(5), "name", key.substr(5).capitalize())
	return content.typed_value("region", key, "name", key.capitalize())

## The game's order for the parts: regions by travel order, then areas, then the rest.
func _group_order(content: ContentDB, key: String) -> int:
	if key == OFF_MAP: return 1 << 23
	if content.has(key, "region"):
		var order := content.typed_value("region", key, "travel order")
		return int(order) if order.is_valid_int() else 1 << 20
	return (1 << 21) if key != "zone:" else (1 << 22)

func refresh() -> void:
	if workspace == null or surface == null:
		return
	exits_by_place.clear()
	contents_by_place.clear()
	places_by_id.clear()
	nodes.clear()
	cells.clear()
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
	# Where the game's own layout puts every place, and on which part of its map.
	var layout := content.map_layout()
	groups.clear()
	for key: String in layout.members:
		var members: Array = []
		var own := 0
		for id: String in layout.members[key]:
			if not places_by_id.has(id): continue
			members.append(id)
			nodes[id] = key
			cells[id] = layout.position.get(id, Vector2i.ZERO)
			if places_by_id[id].doc.writable: own += 1
		if not members.is_empty(): groups.append({"key": key, "name": _group_name(content, key), "places": members, "own": own, "order": _group_order(content, key)})
	var off: Array = places_by_id.keys().filter(func(id: String) -> bool: return not nodes.has(id))
	off.sort()
	if not off.is_empty():
		var own := 0
		for index in off.size():
			nodes[off[index]] = OFF_MAP
			cells[off[index]] = Vector2i(index % 8, index / 8)
			if places_by_id[off[index]].doc.writable: own += 1
		groups.append({"key": OFF_MAP, "name": _group_name(content, OFF_MAP), "places": off, "own": own, "order": _group_order(content, OFF_MAP)})
	groups.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a.order < b.order if a.order != b.order else str(a.name) + str(a.key) < str(b.name) + str(b.key))
	var before := shown_group
	if _follow and nodes.has(inspected_id): shown_group = nodes[inspected_id]
	_follow = false
	if group(shown_group).is_empty():
		# The part with most of your own places, else the first.
		shown_group = str(groups[0].key) if not groups.is_empty() else ""
		var most := 0
		for entry: Dictionary in groups:
			if int(entry.own) > most:
				most = entry.own
				shown_group = entry.key
	region_picker.clear()
	var several: bool = workspace.pack_paths.size() > 1
	for entry: Dictionary in groups:
		var count: int = entry.places.size()
		region_picker.add_item("%s · %d place%s%s" % [entry.name, count, "" if count == 1 else "s", ", %d yours" % int(entry.own) if several and int(entry.own) > 0 else ""])
		region_picker.set_item_metadata(region_picker.item_count - 1, entry.key)
		if entry.key == shown_group: region_picker.select(region_picker.item_count - 1)
	region_picker.visible = groups.size() > 1
	_draw_group(before == shown_group and not surface.places.is_empty())
	_render_inspector()

## Shows another part of the map.
func show_group(key: String) -> void:
	if group(key).is_empty() or key == shown_group: return
	shown_group = key
	for index in region_picker.item_count:
		if region_picker.get_item_metadata(index) == key: region_picker.select(index)
	_draw_group(false)

## Hands the shown part's places and ways to the drawing.
func _draw_group(keep_view: bool) -> void:
	var content := workspace.preview_content()
	var entry := group(shown_group)
	var list: Array[Dictionary] = []
	var stubs: Array[Dictionary] = []
	ways.clear()
	var inside: Dictionary = {}
	for id: String in entry.get("places", []): inside[id] = true
	var seen: Dictionary = {}
	for id: String in entry.get("places", []):
		var row: Dictionary = places_by_id[id]
		var zone := _field(row, "zone")
		var note := _contents_summary(contents_by_place.get(id, []))
		if zone not in ["", "none"]: note = "Area: " + workspace.title_of("zone", zone) + "\n" + note
		if not row.doc.writable: note += "\nFrom " + str(row.pack)
		list.append({"id": id, "name": _title(row), "cell": cells[id], "own": row.doc.writable, "fast": "fast travel" in content.list_field(id, "flags"), "note": note})
		for exit: Dictionary in exits_by_place.get(id, []):
			var to: String = exit.target
			if to.is_empty() or to == id or not places_by_id.has(to): continue
			if not inside.has(to):
				stubs.append({"from": id, "step": Vector2(MapLayout.step_of(str(exit.direction))[0]), "name": _title(places_by_id[to])})
				continue
			var door: bool = "door " in str(exit.text)
			if seen.has(to + ">" + id):
				var back: Dictionary = seen[to + ">" + id]
				back.both = true
				if door: back.door = true
			elif not seen.has(id + ">" + to):
				var way := {"a": id, "b": to, "both": false, "door": door}
				seen[id + ">" + to] = way
				ways.append(way)
	var picture: Texture2D = null
	if content.has(shown_group, "region"):
		var file := content.image_file(content.image_of("region", shown_group))
		if not file.is_empty():
			if not _pictures.has(file):
				var loaded := Image.load_from_file(file)
				_pictures[file] = ImageTexture.create_from_image(loaded) if loaded != null else null
			picture = _pictures[file]
	surface.selected = inspected_id if inside.has(inspected_id) else ""
	surface.show_map(list, ways, stubs, picture, keep_view)
	var total: int = places_by_id.size()
	scope_note.visible = groups.size() > 1
	scope_note.text = "%s: %d of the %d places. The other parts of the world are in the list above." % [entry.get("name", ""), list.size(), total]

## Whether a way between two places is drawn, either way round.
func connected(a: String, b: String) -> bool:
	return ways.any(func(way: Dictionary) -> bool: return (way.a == a and way.b == b) or (way.a == b and way.b == a))

func _fit_places() -> void:
	surface.fit()

func _choose(id: String) -> void:
	if not places_by_id.has(id): return
	_show_contents(places_by_id[id])
	selected.emit(places_by_id[id])

## Offers to connect two places; the direction is the one the second lies in on the map.
func _request_exit(from: String, to: String, single: bool = false) -> void:
	if not places_by_id.has(from) or not places_by_id.has(to) or from == to:
		return
	exit_source = places_by_id[from]
	exit_target = places_by_id[to]
	var wanted := ""
	var delta := Vector2(cells.get(to, Vector2i.ZERO) - cells.get(from, Vector2i.ZERO))
	if nodes.get(from, "") == nodes.get(to, "") and delta != Vector2.ZERO:
		var nearest := -2.0
		for name: String in MapLayout.STEPS:
			var along := Vector2(MapLayout.STEPS[name]).normalized().dot(delta.normalized())
			if along > nearest:
				nearest = along
				wanted = name
	var first_available := -1
	for index in DIRECTIONS.size():
		var taken := false
		for existing: Dictionary in exits_by_place.get(exit_source.def.id, []):
			if existing.direction == DIRECTIONS[index]:
				taken = true
		direction.set_item_disabled(index, taken)
		if not taken and (first_available < 0 or DIRECTIONS[index] == wanted):
			first_available = index
	if first_available < 0:
		problem.emit("This place already has an exit in every available direction.")
		return
	direction.select(first_available)
	one_way.button_pressed = single
	door_check.button_pressed = false
	door_name.text = ""
	door_name.hide()
	door_locked.button_pressed = false
	door_locked.hide()
	exit_dialog.title = "Connect %s → %s" % [_title(exit_source), _title(exit_target)]
	exit_dialog.popup_centered()

## Asks which of the ways between two places to remove.
func _request_remove_exit(from: String, to: String) -> void:
	if not places_by_id.has(from) or not places_by_id.has(to):
		return
	var first: Dictionary = places_by_id[from]
	var second: Dictionary = places_by_id[to]
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
	_remove_exit_entry(remove_exit_options.get_item_metadata(remove_exit_options.selected))

## Takes one way out of its place's exits; the way back stays.
func _remove_exit_entry(entry: Dictionary) -> void:
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
	var door := {"name": door_name.text, "locked": door_locked.button_pressed} if door_check.button_pressed else {}
	var error := workspace.connect_places(exit_source, exit_target, DIRECTIONS[direction.selected], not one_way.button_pressed, door)
	if not error.is_empty():
		problem.emit(error)
		return
	var updated := workspace.find_row(exit_source.doc.path, "location", exit_source.def.id, exit_source.def.mode, exit_source.get("ordinal", 0))
	changed.emit(updated)

## Gives a place a position of its own on the game's map (Ctrl-drag), or with
## `clear` hands it back to the game's layout.
func _move_place(id: String, cell: Vector2i, clear: bool = false) -> void:
	var shown: Dictionary = places_by_id.get(id, {})
	if shown.is_empty() or nodes.get(id, "") == OFF_MAP: return
	var row := workspace.find_row(shown.doc.path, "location", shown.def.id, shown.def.mode, shown.get("ordinal", 0))
	if row.is_empty() or not row.doc.writable:
		problem.emit("%s belongs to another pack: its position on the map cannot be changed here." % _title(shown))
		return
	if not clear:
		if cells.get(id, Vector2i.ZERO) == cell: return
		for other: String in cells:
			if other != id and nodes[other] == nodes[id] and cells[other] == cell:
				problem.emit("%s is already there." % _title(places_by_id[other]))
				return
	var error := workspace.transaction(("Let the game place %s" if clear else "Move %s on the map") % _title(shown), func() -> String:
		return row.doc.remove_simple_field(row.def, "map") if clear else row.doc.set_field(row.def, "map", "%d, %d" % [cell.x, cell.y]))
	if not error.is_empty():
		problem.emit(error)
		return
	changed.emit(workspace.find_row(row.doc.path, "location", row.def.id, row.def.mode, row.get("ordinal", 0)))

## Asks for a door's name and lock, then puts the door on a way that exists.
func _ask_door(place: Dictionary, exit: Dictionary) -> void:
	var dialog := ConfirmationDialog.new()
	dialog.title = "A door on the way " + str(exit.direction)
	dialog.ok_button_text = "Add the door"
	var form := VBoxContainer.new()
	form.custom_minimum_size.x = 340
	dialog.add_child(form)
	var name_input := LineEdit.new()
	name_input.placeholder_text = "Name of the door"
	form.add_child(name_input)
	var locked := CheckButton.new()
	locked.text = "Locked at first (a story unlocks it)"
	form.add_child(locked)
	dialog.register_text_enter(name_input)
	dialog.confirmed.connect(func() -> void:
		var error := workspace.add_door(str(place.def.id), str(exit.direction), name_input.text, locked.button_pressed)
		if not error.is_empty(): problem.emit(error)
		else: changed.emit(workspace.find_row(place.doc.path, "location", place.def.id, place.def.mode, place.get("ordinal", 0)))
		dialog.queue_free())
	dialog.canceled.connect(dialog.queue_free)
	add_child(dialog)
	dialog.popup_centered()
	name_input.grab_focus()

## A picker for the area or region of a place, with a way to make a new one.
func _place_setting(place: Dictionary, key: String, type: String, caption: String, none: String) -> void:
	_inspector_label(caption, inspector, 13)
	var picker := PickerButton.new()
	picker.workspace = workspace
	picker.drop_kinds = [type]
	picker.placeholder = none
	picker.text = none
	picker.disabled = not place.doc.writable
	picker.alignment = HORIZONTAL_ALIGNMENT_LEFT
	picker.options = func() -> Array:
		var result: Array = [{"value": "", "label": none}]
		for row: Dictionary in workspace.rows:
			if row.def.type == type and row.def.mode != "extend": result.append({"value": row.def.id, "label": Wording.title(row), "detail": "" if row.doc.writable else str(row.pack)})
		return result
	picker.commands = [{"label": "+ New " + Wording.name(type) + "…", "action": func() -> void:
		var dialog := ConfirmationDialog.new()
		dialog.title = "New " + Wording.name(type)
		dialog.ok_button_text = "Create"
		var input := LineEdit.new()
		input.placeholder_text = "Name"
		input.custom_minimum_size.x = 300
		dialog.add_child(input)
		dialog.register_text_enter(input)
		dialog.confirmed.connect(func() -> void:
			if input.text.strip_edges().is_empty(): return
			var id := workspace.unique_id(input.text, type)
			var error := workspace.transaction("New %s %s" % [Wording.name(type), input.text.strip_edges()], func() -> String: return workspace.create_definition(type, id, "define", "name: " + input.text.strip_edges()))
			if not error.is_empty(): problem.emit(error)
			else: picker.choose(id)
			dialog.queue_free())
		dialog.canceled.connect(dialog.queue_free)
		add_child(dialog)
		dialog.popup_centered()
		input.grab_focus()}]
	var current := _field(place, key)
	picker.set_value("" if current == "none" else current)
	picker.picked.connect(func(id: String) -> void:
		var row := workspace.find_row(place.doc.path, "location", place.def.id, place.def.mode, place.get("ordinal", 0))
		if row.is_empty(): return
		var error := workspace.transaction("Set the %s of %s" % [Wording.name(type), _title(row)], func() -> String:
			var issue: String = row.doc.set_field(row.def, key, id if not id.is_empty() else "none") if key == "zone" or not id.is_empty() else row.doc.remove_simple_field(row.def, key)
			return issue if not issue.is_empty() or id.is_empty() else workspace.require_content(type, id))
		if not error.is_empty():
			problem.emit(error)
			return
		changed.emit(workspace.find_row(row.doc.path, "location", row.def.id, row.def.mode, row.get("ordinal", 0))))
	inspector.add_child(picker)

## Chooses a place: its part of the map is shown and what happens there is listed.
func _show_contents(row: Dictionary) -> void:
	inspected_id = row.def.id
	if nodes.has(inspected_id):
		if nodes[inspected_id] != shown_group: show_group(nodes[inspected_id])
		surface.selected = inspected_id
		surface.reveal(inspected_id)
		surface.queue_redraw()
	else:
		# The map has not been drawn yet: it opens on this place's part.
		_follow = true
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
		_inspector_label("Click a place on the map to see its events, people, items and ways out.", inspector)
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
	# The ways out, in words: each leads to its place, also on another part of the map.
	_inspector_label("WAYS OUT", inspector, 13)
	var out: Array = exits_by_place.get(inspected_id, [])
	if out.is_empty(): _inspector_label("None yet. Drag from this place to another on the map.", inspector, 13)
	for exit: Dictionary in out:
		var line := HBoxContainer.new()
		inspector.add_child(line)
		var target: String = exit.target
		var go := Button.new()
		go.theme_type_variation = "Ghost"
		go.alignment = HORIZONTAL_ALIGNMENT_LEFT
		go.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		go.clip_text = true
		var named: String = _title(places_by_id[target]) if places_by_id.has(target) else str(exit.text)
		go.text = "%s → %s%s%s" % [str(exit.direction).capitalize(), named, " · 🚪" if "door " in str(exit.text) else "", " · one way" if "one way" in str(exit.text) else ""]
		go.tooltip_text = "Go to %s on the map." % named if places_by_id.has(target) else "This way leads into an area, not to one place."
		go.disabled = not places_by_id.has(target)
		go.pressed.connect(func() -> void: _choose(target))
		line.add_child(go)
		if exit.row.doc.writable:
			var drop := Button.new()
			drop.text = "✕"
			drop.theme_type_variation = "Ghost"
			drop.tooltip_text = "Remove this way. The way back, if there is one, stays."
			drop.pressed.connect(func() -> void: _remove_exit_entry(exit))
			line.add_child(drop)
	if nodes.get(inspected_id, "") != OFF_MAP:
		var by_hand := not _field(place, "map").is_empty()
		_inspector_label("ON THE MAP", inspector, 13)
		_inspector_label("Placed by hand at %s. The places joined to it by north, south, east or west follow it." % _field(place, "map") if by_hand else "Placed by the game from its ways. Ctrl-drag it on the map to give it a position of its own.", inspector, 13)
		if by_hand and place.doc.writable:
			var release := Button.new()
			release.theme_type_variation = "AddRow"
			release.text = "Let the game place it"
			release.pressed.connect(func() -> void: _move_place(inspected_id, Vector2i.ZERO, true))
			inspector.add_child(release)
	else:
		_inspector_label("This place is kept off the game's map.", inspector, 13)
	_place_setting(place, "zone", "zone", "AREA: WHAT IS FOUND AND MET WHILE EXPLORING HERE", "No area: nothing to explore")
	_place_setting(place, "region", "region", "REGION: ITS PART OF THE MAP AND TRAVEL LIST", "The region of the nearest place that has one")
	var doors: Dictionary = {}
	for exit: Dictionary in exits_by_place.get(inspected_id, []):
		var named := RegEx.create_from_string("\\bdoor ([a-z0-9_]+)").search(str(exit.text))
		if named != null: doors[named.get_string(1)] = str(exit.direction)
	# A way out without a door can get one: both sides of the way are changed.
	for exit: Dictionary in exits_by_place.get(inspected_id, []):
		if "door " in str(exit.text) or not exit.row.doc.writable or not places_by_id.has(str(exit.target)): continue
		var add_door := Button.new()
		add_door.theme_type_variation = "AddRow"
		add_door.text = "+ Door on the way %s to %s" % [str(exit.direction), _title(places_by_id[str(exit.target)])]
		add_door.tooltip_text = "Make a door for this way. It is added on both sides."
		add_door.clip_text = true
		add_door.pressed.connect(func() -> void: _ask_door(place, exit))
		inspector.add_child(add_door)
	if not doors.is_empty(): _inspector_label("DOORS", inspector, 13)
	for id: String in doors:
		for row: Dictionary in workspace.rows:
			if row.def.type != "door" or row.def.id != id or row.def.mode == "extend": continue
			var open_door := Button.new()
			var state := _field(row, "locked")
			open_door.text = "🚪 %s, %s  ·  %s" % [_title(row), str(doors[id]), "locked" if state == "yes" else ("open" if state in ["", "no"] else "locked when a condition holds")]
			open_door.tooltip_text = "Open the door's details: its name, lock and what the player reads."
			open_door.clip_text = true
			open_door.pressed.connect(func() -> void: open_requested.emit(row))
			inspector.add_child(open_door)
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
