class_name SavedValueRow
extends VBoxContainer
## Guided declaration controls; the selected engine interprets existing values.

signal edited

const GUIDANCE := {
	"Flag": "Remember whether something happened. Starts off; a story can turn it on or off.",
	"Number": "Count visits, trust or another quantity. Choose a starting number and optional limits.",
	"Text": "Remember words, such as a name entered by the player. Leave blank to start empty.",
	"Time": "Remember when something happened. Starts unset; a story records the time for later checks.",
	"States": "Remember one stage or mood. Separate choices with commas; the first is the starting state.",
	"List": "Remember an ordered collection. Separate starting entries with commas, or leave it empty."
}

var name_input: LineEdit
var types: HFlowContainer
var initial: LineEdit
var initial_label: Label
var hint: Label
var bounds: VBoxContainer
var limited: CheckButton
var minimum: LineEdit
var maximum: LineEdit
var combat_limit: CheckButton
var combat_maximum: LineEdit
var original_spec := ""
var touched := false
var active_kind := ""
var configuring := true

func configure(value_name: String, spec: String, writable: bool) -> void:
	original_spec = spec
	name_input = LineEdit.new()
	name_input.text = value_name
	name_input.placeholder_text = "Value name, e.g. visits or met_guide"
	name_input.editable = writable
	add_child(name_input)
	types = HFlowContainer.new()
	add_child(types)
	initial = LineEdit.new()
	initial.editable = writable
	add_child(initial)
	initial_label = AuthoringLayout.label("", 14)
	add_child(initial_label)
	move_child(initial_label, 2)
	hint = AuthoringLayout.label("", 14, true)
	add_child(hint)
	bounds = VBoxContainer.new()
	add_child(bounds)
	limited = CheckButton.new()
	limited.text = "Keep within limits"
	limited.disabled = not writable
	bounds.add_child(limited)
	minimum = _number_input("Lowest value", writable)
	maximum = _number_input("Highest value", writable)
	combat_limit = CheckButton.new()
	combat_limit.text = "Allow a higher limit during fights"
	combat_limit.disabled = not writable
	bounds.add_child(combat_limit)
	combat_maximum = _number_input("Highest value during fights", writable)
	minimum.text = "0"
	maximum.text = "100"
	combat_maximum.text = "100"
	var declaration := _read_spec(spec)
	var current: String = str(declaration.get("kind", "flag")).capitalize()
	if spec.is_empty(): current = "Flag"
	active_kind = current
	match current:
		"Number":
			initial.text = str(declaration.get("default", 0))
			limited.button_pressed = declaration.has("min")
			minimum.text = str(declaration.get("min", 0))
			maximum.text = str(declaration.get("max", 100))
			combat_limit.button_pressed = declaration.has("fight_max")
			combat_maximum.text = str(declaration.get("fight_max", 100))
		"Text": initial.text = spec.trim_prefix("text").strip_edges()
		"List": initial.text = spec.trim_prefix("list").strip_edges()
		"States": initial.text = spec
	var group := ButtonGroup.new()
	for title: String in GUIDANCE:
		var button := Button.new()
		button.text = title
		button.tooltip_text = GUIDANCE[title]
		button.toggle_mode = true
		button.button_group = group
		button.button_pressed = title == current
		button.disabled = not writable
		button.pressed.connect(func() -> void:
			if selected_kind() == active_kind: return
			active_kind = selected_kind()
			# A previous type's starting value must never become another type's data.
			initial.text = "0" if selected_kind() == "Number" else ""
			limited.button_pressed = false
			combat_limit.button_pressed = false
			_changed())
		types.add_child(button)
	name_input.text_changed.connect(func(_text: String) -> void: edited.emit())
	initial.text_changed.connect(func(_text: String) -> void: _changed())
	limited.toggled.connect(func(_on: bool) -> void: _changed())
	combat_limit.toggled.connect(func(_on: bool) -> void: _changed())
	configuring = false
	_refresh()

func _number_input(title: String, writable: bool) -> LineEdit:
	var line := VBoxContainer.new()
	line.add_child(AuthoringLayout.label(title, 14))
	var input := LineEdit.new()
	input.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	input.editable = writable
	input.text_changed.connect(func(_text: String) -> void: _changed())
	line.add_child(input)
	bounds.add_child(line)
	return input

static func _read_spec(spec: String) -> Dictionary:
	var parsed := FscParser.parse("== values draft\nvalues:\n    entry: " + spec + "\n", "")
	var db := ContentDB.new()
	for definition: FscParser.Definition in parsed.definitions: db._add(definition, parsed)
	return db.values.get("draft.entry", {})

func selected_kind() -> String:
	for button: Button in types.get_children():
		if button.button_pressed: return button.text
	return "Flag"

func _changed() -> void:
	if configuring: return
	touched = true
	_refresh()
	edited.emit()

func _refresh() -> void:
	var kind := selected_kind()
	hint.text = GUIDANCE[kind]
	initial.visible = kind not in ["Flag", "Time"]
	initial_label.visible = initial.visible
	initial_label.text = {"Number": "Starting number", "Text": "Starting words", "States": "Possible states (starting state first)", "List": "Starting entries"}.get(kind, "")
	initial.placeholder_text = {"Number": "Starting number (0 if empty)", "Text": "Starting words (optional)", "States": "e.g. unknown, introduced, trusted", "List": "e.g. apple, bread (optional)"}.get(kind, "")
	bounds.visible = kind == "Number"
	minimum.get_parent().visible = limited.button_pressed
	maximum.get_parent().visible = limited.button_pressed
	combat_limit.visible = limited.button_pressed
	combat_maximum.get_parent().visible = limited.button_pressed and combat_limit.button_pressed

func declaration() -> Dictionary:
	# Unchanged declarations retain their exact spelling and any unfamiliar syntax.
	if not touched and not original_spec.is_empty(): return {"spec": original_spec}
	var kind := selected_kind()
	var value := initial.text.strip_edges()
	if "\n" in value or "\r" in value: return {"error": "Keep the starting value on one line."}
	match kind:
		"Flag", "Time": return {"spec": kind.to_lower()}
		"Number":
			if value.is_empty(): value = "0"
			if not value.is_valid_int(): return {"error": "Enter a whole starting number."}
			var spec := "number " + value
			if limited.button_pressed:
				if not minimum.text.is_valid_int() or not maximum.text.is_valid_int(): return {"error": "Enter whole numbers for both limits."}
				var low := int(minimum.text)
				var high := int(maximum.text)
				if low > high: return {"error": "The lowest value must not exceed the highest value."}
				if int(value) < low or int(value) > high: return {"error": "Choose a starting number within the limits."}
				spec += " (%d to %d" % [low, high]
				if combat_limit.button_pressed:
					if not combat_maximum.text.is_valid_int() or int(combat_maximum.text) < high: return {"error": "The fight limit must be a whole number at least as high as the normal limit."}
					spec += ", up to %d in fights" % int(combat_maximum.text)
				spec += ")"
			return {"spec": spec}
		"Text", "List": return {"spec": kind.to_lower() + (" " + value if not value.is_empty() else "")}
		"States":
			var seen := {}
			for state: String in value.split(","):
				state = state.strip_edges()
				if RegEx.create_from_string("^[a-z][a-z0-9_]*$").search(state) == null: return {"error": "Give each state a short name using lowercase letters and underscores, separated by commas."}
				if seen.has(state): return {"error": "Each state needs a different name."}
				seen[state] = true
			if _read_spec(value).get("kind", "") != "states": return {"error": "These names describe a different value type. Choose different state names."}
			return {"spec": value}
	return {"error": "Choose what this value remembers."}
