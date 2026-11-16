class_name ContentDropMenu
extends ConfirmationDialog
## A drop is a proposal. Source changes only after the author chooses its use.

signal applied(row: Dictionary)
signal open_requested(row: Dictionary)
var workspace: PackWorkspace
var source: Dictionary = {}
var destination: Dictionary = {}
var original := ""
var options: OptionButton
var error: Label
var actions: Array[Dictionary] = []

func _ready() -> void:
	title = "What should happen?"
	ok_button_text = "Apply"
	dialog_hide_on_ok = false
	var body := VBoxContainer.new()
	body.custom_minimum_size.x = 450
	add_child(body)
	options = OptionButton.new()
	body.add_child(options)
	error = AuthoringLayout.label("", 14, true)
	body.add_child(error)
	confirmed.connect(_apply)

func open(value: PackWorkspace, content: Dictionary, target: Dictionary) -> void:
	workspace = value
	source = content
	destination = target
	original = str(target.doc.text) if not target.is_empty() else ""
	actions.clear()
	options.clear()
	error.text = ""
	title = "Use " + Wording.title(source)
	actions.append({"label": "Open " + Wording.title(source), "kind": "open"})
	if not target.is_empty() and target.doc.writable:
		if target.def.type == "location":
			match str(source.def.type):
				"character":
					if source.doc.writable: actions.append({"label": "Make this their home place", "kind": "home"})
				"item": actions.append({"label": "Put this item in the place", "kind": "ground"})
				"event":
					if source.doc.writable: actions.append({"label": "Start this event when arriving here", "kind": "arrival"})
		elif target.def.type in ["scene", "menu", "character", "event", "creature", "item"] or target.has("script_field"):
			match str(source.def.type):
				"item":
					actions.append({"label": "Give one " + Wording.title(source), "kind": "effect", "line": "give " + source.def.id + " 1"})
					actions.append({"label": "Take one " + Wording.title(source), "kind": "effect", "line": "take " + source.def.id + " 1"})
				"location": actions.append({"label": "Move the player here", "kind": "effect", "line": "go to " + source.def.id})
				"image": actions.append({"label": "Show this picture", "kind": "image"})
				"condition": actions.append({"label": "Apply for 2 turns", "kind": "effect", "line": "condition " + source.def.id + " for 2 turns"})
				"scene": actions.append({"label": "Play this story, then come back", "kind": "play"})
				"form": actions.append({"label": "Mutate toward this form", "kind": "effect", "line": "infect " + source.def.id})
	for action: Dictionary in actions: options.add_item(action.label)
	if actions.size() > 1: options.select(1)
	popup_centered()

func _apply() -> void:
	if source.is_empty() or actions.is_empty(): return
	var current := workspace.find_row(source.doc.path, source.def.type, source.def.id, source.def.mode, source.get("ordinal", 0))
	if current.is_empty():
		error.text = "This content changed. Choose it again."
		return
	var action: Dictionary = actions[options.selected]
	if action.kind == "open":
		hide()
		open_requested.emit(current)
		return
	var target := workspace.find_row(destination.doc.path, destination.def.type, destination.def.id, destination.def.mode, destination.get("ordinal", 0))
	if target.is_empty() or target.doc.text != original:
		error.text = "The destination changed. Drop the content again."
		return
	if destination.has("script_field"): target.script_field = destination.script_field
	var problem := workspace.transaction(action.label, func() -> String:
		var result := ""
		match str(action.kind):
			"effect": result = StoryGraph.add_primary_effect(target, action.line)
			"image": result = StoryGraph.set_image(target, {}, current.def.id)
			"play": result = StoryGraph.add_story_step(target, "play " + current.def.id)
			"home": result = current.doc.set_field(current.def, "lives at", target.def.id)
			"ground":
				var previous: String = target.doc.field_value(target.def, "items")
				if "\n" in previous: return "These ground items use a complex layout and are kept."
				result = target.doc.set_field(target.def, "items", previous + (", " if not previous.is_empty() else "") + current.def.id)
			"arrival": result = EventTriggers.apply_to(workspace, current, "arriving at " + target.def.id)
		if not result.is_empty(): return result
		for row: Dictionary in [current, target]:
			if not row.doc.writable:
				result = workspace.add_requirement(row.pack)
				if not result.is_empty(): return result
		return "")
	if not problem.is_empty():
		error.text = problem
		return
	hide()
	applied.emit(workspace.find_row(target.doc.path, target.def.type, target.def.id, target.def.mode, target.get("ordinal", 0)))
