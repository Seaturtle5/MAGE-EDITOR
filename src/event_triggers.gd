class_name EventTriggers
extends VBoxContainer
signal edited
## Visual controls for the engine's trigger phrases; unfamiliar clauses stay intact.

const LABELS := ["Arrives (walk or fast travel)", "Walks into a place", "Fast travels to a place", "Leaves in a direction", "Explores a zone", "Scavenges in a zone", "Explores or scavenges", "Started by another story"]
const PREFIXES := ["arriving at ", "walking into ", "travelling to ", "leaving ", "exploring in ", "scavenging in ", "exploring or scavenging in ", "nowhere"]
const DIRECTIONS := ["north", "northeast", "east", "southeast", "south", "southwest", "west", "northwest", "up", "down", "inside", "outside"]

var workspace: PackWorkspace
var clauses: Array[Dictionary] = []
var editable := true
var target_dialog: ConfirmationDialog
var target_search: LineEdit
var target_list: VBoxContainer
var target_clause: Dictionary = {}
var target_draft: Array[String] = []
var original_text := ""
var original_clauses: Array[Dictionary] = []

static func parse_clause(raw: String) -> Dictionary:
	for index in PREFIXES.size():
		if index == 7:
			if raw in ["nowhere", ""]:
				return {"type": index, "targets": [], "direction": "north", "raw": raw}
			continue
		if raw == PREFIXES[index].strip_edges():
			return {"type": index, "targets": [], "direction": "north"}
		if not raw.begins_with(PREFIXES[index]):
			continue
		var targets: Array[String] = []
		var direction := "north"
		if raw.trim_prefix(PREFIXES[index]).is_empty():
			return {"type": index, "targets": targets, "direction": direction}
		for part: String in raw.trim_prefix(PREFIXES[index]).split(","):
			var words := part.strip_edges().split(" ", false)
			if index == 3:
				if words.size() != 2 or words[1] not in DIRECTIONS or (not targets.is_empty() and direction != words[1]):
					return {"type": -1, "raw": raw}
				direction = words[1]
			elif words.size() != 1:
				return {"type": -1, "raw": raw}
			if RegEx.create_from_string("^[a-z0-9_][a-z0-9_.-]*$").search(words[0]) == null:
				return {"type": -1, "raw": raw}
			targets.append(words[0])
		return {"type": index, "targets": targets, "direction": direction, "raw": raw}
	return {"type": -1, "raw": raw}

static func title_for(value: PackWorkspace, type: String, id: String) -> String:
	var known := value.title_of(type, id)
	if not known.is_empty(): return known
	for candidate: Dictionary in value.rows:
		if candidate.def.type == type and candidate.def.id == id and candidate.def.mode != "extend":
			return candidate.doc.field_value(candidate.def, "name") if candidate.def.fields.has("name") else id.capitalize()
	return id.capitalize()

static func apply_to(value: PackWorkspace, entry: Dictionary, text: String) -> String:
	var current := value.find_row(entry.doc.path, entry.def.type, entry.def.id, entry.def.mode, entry.get("ordinal", 0))
	if current.is_empty() or not current.doc.writable:
		return "This event is read-only or has changed. Reopen it before editing."
	var field: FscParser.Field = current.def.fields.get("found by")
	if field != null and not field.children.is_empty():
		return "This trigger has additional source lines and is preserved."
	var doc: PackDocument = current.doc
	var manifest: PackDocument = value.documents[value.target.path_join("pack.fsc")]
	var before := doc.text
	var manifest_before := manifest.text
	var error := doc.set_field(current.def, "found by", text)
	if not error.is_empty():
		return error
	var found := ContentDB.found_by(text)
	var ids: Dictionary = {"location": found.walking + found.travelling, "zone": found.zones}
	for pair: Array in found.leaving:
		ids.location.append(pair[0])
	for type: String in ids:
		for id: String in ids[type]:
			for candidate: Dictionary in value.rows:
				if candidate.def.type == type and candidate.def.id == id and candidate.def.mode in ["define", "replace"]:
					if not candidate.doc.writable:
						error = value.add_requirement(candidate.pack)
					break
			if not error.is_empty():
				doc.change(before)
				manifest.change(manifest_before)
				value.reindex()
				return error
	value.reindex()
	return ""

static func describe(value: PackWorkspace, text: String) -> String:
	var sentences: Array[String] = []
	for part: String in text.split(";"):
		var clause := parse_clause(part.strip_edges())
		var type: int = clause.type
		if type < 0:
			sentences.append("Additional trigger (preserved): " + part.strip_edges())
			continue
		if type == 7:
			sentences.append("Started by another story; has no automatic map trigger.")
			continue
		var names: Array[String] = []
		for id: String in clause.targets:
			names.append(title_for(value, "zone" if type in [4, 5, 6] else "location", id))
		var verbs := ["On arrival at %s (walking or fast travel)", "When walking into %s", "When fast travelling to %s", "When leaving %s heading " + str(clause.direction), "When exploring in %s", "When scavenging in %s", "When exploring or scavenging in %s"]
		sentences.append(verbs[type] % ", ".join(names))
	return "\nOR ".join(sentences)

static func describe_condition(value: PackWorkspace, text: String) -> String:
	if text.is_empty():
		return "No extra condition"
	# One wording for conditions everywhere: the block catalog's sentences.
	if not Condition.compile(text).has("error"): return BlockCatalog.condition_sentence(text, value)
	var sentence := _condition_sentence(value, Condition.compile(text))
	return text if sentence.is_empty() else sentence

static func _condition_sentence(value: PackWorkspace, condition: Dictionary) -> String:
	var op := str(condition.get("op", ""))
	match op:
		"and", "or":
			var first := _condition_sentence(value, condition.a)
			var second := _condition_sentence(value, condition.b)
			return "(" + first + ") " + op.to_upper() + " (" + second + ")" if not first.is_empty() and not second.is_empty() else ""
		"not":
			var inner := _condition_sentence(value, condition.a)
			return "Not (" + inner + ")" if not inner.is_empty() else ""
		"quest": return title_for(value, "quest", condition.quest) + " " + str(condition.rel) + " " + str(condition.stage).capitalize()
		"has_item": return str(condition.get("who", "player")).capitalize() + (" does not have " if condition.get("neg", false) else " has ") + title_for(value, "item", condition.item)
		"time": return "It is " + ("not " if condition.get("neg", false) else "") + str(condition.slot)
	return ""

func configure(value: PackWorkspace, text: String, can_edit: bool = true) -> void:
	workspace = value
	editable = can_edit
	original_text = text
	clauses.clear()
	for part: String in text.split(";"):
		clauses.append(parse_clause(part.strip_edges()))
	original_clauses.assign(clauses.duplicate(true))
	_render()

func value() -> String:
	if clauses == original_clauses:
		return original_text
	var parts: Array[String] = []
	for clause: Dictionary in clauses:
		if clause.has("raw"):
			parts.append(clause.raw if not str(clause.raw).is_empty() else "nowhere")
			continue
		var type: int = clause.type
		var targets: Array[String] = []
		for id: String in clause.targets:
			targets.append(id + (" " + str(clause.direction) if type == 3 else ""))
		parts.append("nowhere" if type == 7 else PREFIXES[type] + ", ".join(targets))
	return "; ".join(parts) if not parts.is_empty() else "nowhere"

func validation_error() -> String:
	for index in clauses.size():
		var clause: Dictionary = clauses[index]
		if clause.type in [-1, 7]:
			continue
		if clause.targets.is_empty():
			return "Trigger %d: choose at least one place or zone." % (index + 1)
	return ""

func _note(text: String, parent: Node) -> void:
	var label := Label.new()
	label.text = text
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.theme_type_variation = "MutedLabel"
	parent.add_child(label)

func _render() -> void:
	for child: Node in get_children():
		if child == target_dialog:
			continue
		remove_child(child)
		child.queue_free()
	_note("When & where does it start?", self)
	for clause: Dictionary in clauses:
		var panel := PanelContainer.new()
		add_child(panel)
		var column := VBoxContainer.new()
		panel.add_child(column)
		if clause.type == -1:
			_note("Additional trigger kept as written: " + str(clause.raw), column)
			continue
		var line := HBoxContainer.new()
		column.add_child(line)
		var timing := OptionButton.new()
		for label: String in LABELS:
			timing.add_item(label)
		timing.select(clause.type)
		timing.disabled = not editable
		timing.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		timing.item_selected.connect(func(index: int) -> void:
			var previous_zone: bool = clause.type in [4, 5, 6]
			clause.type = index
			if previous_zone != (index in [4, 5, 6]) or index == 7:
				clause.targets = []
			clause.erase("raw")
			_render())
		line.add_child(timing)
		var remove := Button.new()
		remove.text = "Remove"
		remove.disabled = not editable
		remove.pressed.connect(func() -> void:
			clauses.erase(clause)
			if clauses.is_empty(): clauses.append(parse_clause("nowhere"))
			_render())
		line.add_child(remove)
		if clause.type == 7:
			_note("A story action must start this event. It will not appear on the map.", column)
			continue
		var choose := Button.new()
		var names: Array[String] = []
		for id: String in clause.targets:
			names.append(title_for(workspace, "zone" if clause.type in [4, 5, 6] else "location", id))
		choose.text = "Choose " + ("zones…" if clause.type in [4, 5, 6] else "places…") if names.is_empty() else ", ".join(names) + "  ·  Change…"
		choose.clip_text = true
		choose.disabled = not editable
		choose.pressed.connect(_choose_targets.bind(clause))
		column.add_child(choose)
		if clause.type == 3:
			var direction := OptionButton.new()
			for name: String in DIRECTIONS:
				direction.add_item("Heading " + name)
			direction.select(DIRECTIONS.find(clause.direction))
			direction.disabled = not editable
			direction.item_selected.connect(func(index: int) -> void: clause.direction = DIRECTIONS[index]; clause.erase("raw"); edited.emit())
			column.add_child(direction)
			_note("This interrupts the exit. Add ‘Continue the move’ on the story board when the player should leave.", column)
		if clause.type in [4, 5, 6]:
			_note("Zone events can be found from every place in that zone. They join a random event pool.", column)
			if clause.type in [5, 6]:
				_note("Scavenging starts from a fast-travel destination.", column)
		elif clause.type in [0, 2]:
			_note("Fast travel only applies to places marked as travel destinations.", column)
	var add := Button.new()
	add.text = "+ Another way to start (OR)"
	add.disabled = not editable
	add.pressed.connect(func() -> void:
		clauses.append({"type": 1, "targets": [], "direction": "north"})
		_render())
	add_child(add)
	edited.emit()

func _choose_targets(clause: Dictionary) -> void:
	if target_dialog == null:
		target_dialog = ConfirmationDialog.new()
		target_dialog.ok_button_text = "Use selected places"
		var form := VBoxContainer.new()
		form.custom_minimum_size = Vector2(460, 360)
		target_dialog.add_child(form)
		target_search = LineEdit.new()
		target_search.placeholder_text = "Find a place or zone…"
		form.add_child(target_search)
		target_search.text_changed.connect(func(_text: String) -> void:
			for child: Node in target_list.get_children():
				child.visible = target_search.text.to_lower() in str(child.get_meta("search")))
		var scroll := ScrollContainer.new()
		scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
		form.add_child(scroll)
		target_list = VBoxContainer.new()
		target_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		scroll.add_child(target_list)
		target_dialog.confirmed.connect(func() -> void:
			target_clause.targets = target_draft.duplicate()
			target_clause.erase("raw")
			_render())
		add_child(target_dialog)
	target_clause = clause
	target_draft.assign(clause.targets)
	target_search.text = ""
	for child: Node in target_list.get_children():
		target_list.remove_child(child)
		child.queue_free()
	var type := "zone" if clause.type in [4, 5, 6] else "location"
	target_dialog.title = "Choose " + ("zones" if type == "zone" else "places")
	target_dialog.ok_button_text = "Use selection"
	var seen: Dictionary = {}
	for row: Dictionary in workspace.rows:
		if row.def.type != type or row.def.mode == "extend" or seen.has(row.def.id):
			continue
		var id: String = row.def.id
		seen[id] = true
		var check := CheckBox.new()
		check.text = title_for(workspace, type, id) + "  ·  " + str(row.pack)
		check.tooltip_text = id
		check.set_meta("search", (check.text + " " + id).to_lower())
		check.button_pressed = id in target_draft
		check.toggled.connect(func(enabled: bool) -> void:
			if enabled and id not in target_draft: target_draft.append(id)
			elif not enabled: target_draft.erase(id))
		target_list.add_child(check)
	if seen.is_empty():
		_note("Create a " + type + " first, or add a reference pack containing one.", target_list)
	target_dialog.popup_centered()
