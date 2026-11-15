class_name VisualDetails
extends VBoxContainer
## Friendly, schema-backed forms for pack definitions.

signal changed(row: Dictionary)
signal problem(message: String)
signal story_requested(row: Dictionary, field: String)
signal condition_requested(row: Dictionary)
signal reaction_requested(row: Dictionary, action: Dictionary, category: String)

const REFERENCES := {
	"lives at": ["location"], "start": ["location"], "region": ["region"], "zone": ["zone"],
	"form": ["form"], "purified": ["item"], "image": ["image"], "logo": ["image"], "background": ["image"],
	"run by": ["character"], "found in": ["zone"], "items": ["item"], "at": ["location"],
	"trades for": ["item"], "generic": ["event"]
}
const PRIMARY_FIELDS := ["name", "description", "pronouns", "image", "lives at", "found by", "repeat", "requires", "chance", "cooldown", "priority", "category", "weight", "level", "hp", "damage", "zone", "start"]
const SWITCH_FIELDS := {
	"item": ["consumed", "keep", "in combat", "plural"],
	"creature": ["unique", "group", "infectious", "research bypass", "magic", "seduction immune"],
	"event": ["active", "replaces trip"],
	"menu": ["pause after each"]
}
const CHOICE_FIELDS := {
	"event": {"repeat": ["once", "until resolved", "always"]},
	"creature": {"active": ["always", "day", "night"], "gender": Validator.CREATURE_GENDERS}
}
const NUMBER_FIELDS := {
	"item": ["weight"],
	"event": ["priority", "cooldown"],
	"creature": ["level", "hp", "damage", "libido", "hit bonus", "dodge bonus", "mind bonus"]
}

var workspace: PackWorkspace
var row: Dictionary = {}
var body: VBoxContainer
var show_all := false
var layout: AuthoringLayout
var section := "overview"
var selection_key := ""
var property_key := ""
var property_query := ""
var property_category := "All"
var item_options_open := false
var property_list: ItemList
var property_count: Label
var property_entries: Array[Dictionary] = []
var pending_rows := false
var pending_sections: Dictionary = {}
var applying_rows := false
var picker: ConfirmationDialog
var picker_search: LineEdit
var picker_list: ItemList
var picker_field := ""
var picker_hint: Label
var picker_rows: Array[Dictionary] = []
var trigger_dialog: ConfirmationDialog
var trigger_editor: EventTriggers
var trigger_original := ""

func _ready() -> void:
	layout = AuthoringLayout.new()
	add_child(layout)
	body = layout.page
	layout.section_requested.connect(go_to_section)
	picker = ConfirmationDialog.new()
	picker.title = "Choose from loaded packs"
	picker.ok_button_text = "Use selection"
	var box := VBoxContainer.new()
	box.custom_minimum_size = Vector2(450, 420)
	picker.add_child(box)
	picker_search = LineEdit.new()
	picker_search.placeholder_text = "Search…"
	picker_search.text_changed.connect(func(_text: String) -> void: _filter_picker())
	box.add_child(picker_search)
	picker_list = ItemList.new()
	picker_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	picker_list.item_activated.connect(func(_i: int) -> void: _apply_reference(); picker.hide())
	box.add_child(picker_list)
	picker_hint = AuthoringLayout.label("", 14, true)
	box.add_child(picker_hint)
	picker_list.item_selected.connect(func(_index: int) -> void: picker.get_ok_button().disabled = false)
	picker.confirmed.connect(_apply_reference)
	add_child(picker)
	trigger_dialog = ConfirmationDialog.new()
	trigger_dialog.title = "When & where does this event happen?"
	trigger_dialog.ok_button_text = "Apply triggers"
	trigger_dialog.dialog_hide_on_ok = false
	var trigger_scroll := ScrollContainer.new()
	trigger_scroll.custom_minimum_size = Vector2(540, 370)
	trigger_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	trigger_dialog.add_child(trigger_scroll)
	trigger_editor = EventTriggers.new()
	trigger_editor.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	trigger_scroll.add_child(trigger_editor)
	trigger_dialog.confirmed.connect(_apply_triggers)
	add_child(trigger_dialog)

func show_definition(value: PackWorkspace, selected: Dictionary) -> void:
	if pending_rows:
		return
	workspace = value
	var identity := "" if selected.is_empty() else "%s|%s|%s|%s|%s" % [selected.doc.path, selected.def.type, selected.def.id, selected.def.mode, selected.get("ordinal", 0)]
	if identity != selection_key:
		section = "overview"
		property_key = ""
		property_query = ""
		property_category = "All"
		item_options_open = false
		show_all = false
		selection_key = identity
	row = selected
	_refresh()

func go_to_section(key: String) -> void:
	var focus := get_viewport().gui_get_focus_owner()
	if focus != null and body.is_ancestor_of(focus):
		focus.release_focus()
	if pending_rows:
		problem.emit("Apply your edited entries before changing sections.")
		return
	section = key
	_refresh()
	layout.page_scroll.scroll_vertical = 0

func _refresh() -> void:
	AuthoringLayout.clear(body)
	AuthoringLayout.clear(layout.sheet)
	if row.is_empty() or row.def.type == "file":
		layout.navigation.hide()
		layout.footer.hide()
		body.add_child(AuthoringLayout.label("Select content to see its details.", 20))
		return
	layout.navigation.show()
	layout.footer.show()
	var d: FscParser.Definition = row.def
	var schema: Dictionary = ContentDB.SCHEMA.get(d.type, {})
	var sections: Array[Dictionary] = [{"key": "overview", "title": "Overview"}]
	if d.type == "event":
		sections.append_array([{"key": "when", "title": "When & where"}, {"key": "conditions", "title": "Conditions"}])
	if d.type == "condition": sections.append({"key": "bonuses", "title": "Temporary bonuses"})
	if d.type == "item": sections.append({"key": "use", "title": "Use & reactions"})
	sections.append_array([{"key": "stories", "title": "Stories"}, {"key": "settings", "title": "Settings"}, {"key": "properties", "title": "Properties"}])
	layout.set_sections(sections, section)
	_build_summary()
	var titles := {"overview": "The essentials", "when": "When does it happen?", "conditions": "What needs to be true?", "stories": "Write what happens", "settings": "Other settings", "properties": "What can this content do?", "use": "When the player uses this item", "bonuses": "What changes while this is active?"}
	body.add_child(AuthoringLayout.label(titles.get(section, "Details"), 24))
	var hints := {"overview": "Start with the basics, then choose a section above.", "when": "Choose how the player finds this event and where it can happen.", "conditions": "Choose requirements and how often this event can run.", "stories": "Choose an interaction to write. Existing passages stay connected to this content.", "settings": "Adjust the settings already used by this content.", "properties": "Browse every available property, including ones already in use. Choose one to see what it does.", "use": "Write the use story, choose reactions and decide whether the item is used up."}
	_event_note(hints.get(section, ""))
	var basics: Array[String] = []
	var settings: Array[String] = []
	var optional: Array[String] = []
	var keys: Array = schema.keys()
	keys.sort()
	for key: String in PRIMARY_FIELDS:
		if d.type == "event" and key in ["found by", "repeat", "requires", "chance", "cooldown", "priority"]: continue
		if schema.has(key) and (d.fields.has(key) or key in ["name", "description"]): basics.append(key)
	for key: String in keys:
		if schema[key] in ["script", "menu"] or key in basics: continue
		if d.type == "event" and key in ["found by", "repeat", "requires", "chance", "cooldown", "priority"]: continue
		if d.fields.has(key): settings.append(key)
		else: optional.append(key)
	match section:
		"overview":
			_add_section("", basics, schema)
			var destinations: Array = [["Stories & interactions", "Write passages and player responses.", "stories"], ["Settings", "Adjust values and other existing settings.", "settings"], ["Browse all properties", "Find what this content can do, with categories and explanations.", "properties"]]
			if d.type == "condition":
				destinations.push_front(["Temporary bonuses", "Change attributes, then apply this condition from a story or item for a chosen duration.", "bonuses"])
			if d.type == "item":
				destinations.push_front(["Use & reactions", "Set healing, food effects, mutation and whether this item is used up.", "use"])
			if d.type == "event":
				destinations.push_front(["When & where", EventTriggers.describe(workspace, row.doc.field_value(d, "found by")), "when"])
			for entry: Array in destinations:
				var card := AuthoringLayout.choice(entry[0], entry[1])
				card.pressed.connect(go_to_section.bind(entry[2]))
				body.add_child(card)
		"when", "conditions": _add_event_flow()
		"stories": _add_story_cards(schema)
		"settings":
			_add_section("", settings, schema)
			if settings.is_empty(): _event_note("No additional settings yet. Browse Properties to choose one.")
		"properties": _add_property_catalog(schema)
		"use": _add_item_use()
		"bonuses": _add_bonus_flow()

func _add_bonus_flow() -> void:
	_event_note("These attribute changes last until the condition expires. Choose the duration when applying it from a story or item.")
	_add_rows("while active", "bonuses")
	var repeated := AuthoringLayout.choice("Every active turn", "Open repeated actions, such as restoring 5 health. Runs before the final expiry turn.")
	repeated.disabled = not row.doc.writable and not row.def.fields.has("each turn")
	repeated.pressed.connect(func() -> void:
		if pending_rows: problem.emit("Apply or discard your bonus edits first."); return
		story_requested.emit(row, "each turn"))
	body.add_child(repeated)
	var reaction := Button.new()
	reaction.text = "+ Add repeated reaction"
	reaction.disabled = not row.doc.writable
	reaction.pressed.connect(func() -> void:
		if pending_rows: problem.emit("Apply or discard your bonus edits first."); return
		var script := row.duplicate()
		script.script_field = "each turn"
		reaction_requested.emit(script, {}, "Health & needs"))
	body.add_child(reaction)
	var help := Button.new()
	help.text = "How do I connect this to my story?"
	help.toggle_mode = true
	body.add_child(help)
	var guidance := AuthoringLayout.label("1. Choose attribute changes and Apply entries.\n2. In a story or item, choose Add action → Temporary conditions. Select this condition and its duration.\n3. Use Add condition → Temporary conditions to unlock a response while it is active.\n\nApplying again extends the duration without stacking bonuses. Creating a condition alone does not start it.\n\nTemporary flat HP bonuses are not supported. Restore health adds HP up to the current maximum; restored health is retained when the condition expires. Stamina changes health using the game’s rules.", 14, true)
	guidance.hide()
	body.add_child(guidance)
	help.toggled.connect(func(open: bool) -> void: guidance.visible = open)

func _add_property_catalog(schema: Dictionary) -> void:
	property_entries.clear()
	var keys: Array = schema.keys()
	keys.sort()
	var categories: Array[String] = ["All"]
	for key: String in keys:
		var entry := AuthoringCatalog.property(row.def.type, key, schema[key])
		entry.present = row.def.fields.has(key)
		property_entries.append(entry)
		if entry.category not in categories: categories.append(entry.category)
	var order := ["All", "Basics", "Use & reactions", "Interactions", "World & discovery", "Story rules", "Body & combat", "Advanced"]
	categories.sort_custom(func(a: String, b: String) -> bool: return order.find(a) < order.find(b))
	property_entries.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		if a.category != b.category: return order.find(a.category) < order.find(b.category)
		return str(a.title).naturalnocasecmp_to(str(b.title)) < 0)
	var controls := HBoxContainer.new()
	body.add_child(controls)
	var search := LineEdit.new()
	search.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	search.placeholder_text = "Search by name or purpose…"
	search.text = property_query
	controls.add_child(search)
	var category := OptionButton.new()
	for name: String in categories: category.add_item(name)
	category.select(maxi(0, categories.find(property_category)))
	controls.add_child(category)
	property_count = AuthoringLayout.label("", 13, true)
	body.add_child(property_count)
	property_list = ItemList.new()
	property_list.custom_minimum_size.y = 130 if not property_key.is_empty() else 180
	property_list.item_selected.connect(func(index: int) -> void:
		if pending_rows:
			problem.emit("Apply your edited entries before choosing another property.")
			return
		property_key = str(property_list.get_item_metadata(index))
		_refresh())
	body.add_child(property_list)
	search.text_changed.connect(func(text: String) -> void: property_query = text; _filter_properties())
	category.item_selected.connect(func(index: int) -> void: property_category = categories[index]; _filter_properties())
	_filter_properties()
	if property_key.is_empty() or not schema.has(property_key):
		_event_note("Choose a property above. Browsing never adds or changes it.")
		return
	var info := AuthoringCatalog.property(row.def.type, property_key, schema[property_key])
	body.add_child(AuthoringLayout.label(info.title, 21))
	if row.def.type == "event" and property_key in ["found by", "requires"]:
		var open := AuthoringLayout.choice("Open " + ("When & where" if property_key == "found by" else "Conditions"), "Choose named places or build a condition visually.")
		open.pressed.connect(go_to_section.bind("when" if property_key == "found by" else "conditions"))
		body.add_child(open)
	elif row.def.type == "item" and property_key in ["use", "infectious", "consumed", "in combat"]:
		var open := AuthoringLayout.choice("Open Use & reactions", "See the use story, effects and food mutation together.")
		open.pressed.connect(go_to_section.bind("use"))
		body.add_child(open)
	elif row.def.type == "condition" and property_key == "while active":
		var open := AuthoringLayout.choice("Open Temporary bonuses", "Choose attributes and see how to apply this condition.")
		open.pressed.connect(go_to_section.bind("bonuses"))
		body.add_child(open)
	else: _add_field(property_key, schema[property_key])

func _filter_properties() -> void:
	property_list.clear()
	var query := property_query.to_lower().strip_edges()
	for entry: Dictionary in property_entries:
		if property_category != "All" and entry.category != property_category: continue
		if not query.is_empty() and query not in str(entry.search): continue
		property_list.add_item(str(entry.title) + (" · In use" if entry.present else " · Available"))
		var index := property_list.item_count - 1
		property_list.set_item_metadata(index, entry.key)
		property_list.set_item_tooltip(index, entry.help)
		if entry.key == property_key: property_list.select(index)
	if not property_list.get_selected_items().is_empty(): property_list.ensure_current_is_visible()
	property_count.text = "%d of %d properties · %s" % [property_list.item_count, property_entries.size(), "Search again or change category." if property_list.item_count == 0 else "Select to see help and controls."]

func _item_script() -> Dictionary:
	var script := row.duplicate()
	script.script_field = "use"
	return script

func _add_item_use() -> void:
	var activity: String = row.doc.field_value(row.def, "use action")
	if not activity.is_empty():
		_event_note("This item starts a built-in activity: " + activity.capitalize() + ". Remove it before adding a use story or scripted reactions.")
	var controls := HFlowContainer.new()
	body.add_child(controls)
	var write := Button.new()
	write.text = "Write or open use story…"
	write.disabled = (not row.doc.writable and not row.def.fields.has("use")) or not activity.is_empty()
	write.pressed.connect(func() -> void: story_requested.emit(row, "use"))
	controls.add_child(write)
	var add := Button.new()
	add.text = "+ Add reaction"
	add.theme_type_variation = "PrimaryButton"
	add.disabled = not row.doc.writable or not activity.is_empty()
	add.pressed.connect(func() -> void: reaction_requested.emit(_item_script(), {}, "Health & needs"))
	controls.add_child(add)
	_event_note("Reactions run in the order below. Open the story board to write text, add choices or inspect conditions.")
	var nodes := StoryGraph.script_nodes(_item_script())
	_add_item_steps(nodes)
	if nodes.is_empty(): _event_note("No story text or scripted reactions yet. Add a reaction to start with health, hunger, thirst or body changes.")
	body.add_child(AuthoringLayout.label("After the use story: food mutation", 20))
	_event_note("Optionally attempt a mutation toward a chosen form. Food-infection protections apply. Leave this unset for ordinary food.")
	_add_item_form()
	var options := Button.new()
	options.text = "Consumption & combat settings"
	options.toggle_mode = true
	options.button_pressed = item_options_open
	body.add_child(options)
	var start := body.get_child_count()
	_add_field("consumed", "text")
	_event_note("Used up by default: the game removes one item automatically. No extra take-item reaction is needed.")
	_add_field("in combat", "text")
	var settings: Array[Node] = body.get_children().slice(start)
	for control: Control in settings: control.visible = item_options_open
	options.toggled.connect(func(open: bool) -> void:
		item_options_open = open
		for control: Control in settings: control.visible = open)
	_event_note("New reactions go before the first set of player responses or final story link. Branches or early returns can skip later reactions; inspect them on the story board.")
	if not activity.is_empty(): _add_field("use action", "text")

func _add_item_steps(nodes: Array, depth: int = 0) -> void:
	for node: Dictionary in nodes:
		if node.kind == "effect":
			var line := HBoxContainer.new()
			var change := Button.new()
			change.text = AuthoringCatalog.effect_label(str(node.text))
			change.alignment = HORIZONTAL_ALIGNMENT_LEFT
			change.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			change.clip_text = true
			change.tooltip_text = change.text
			change.disabled = not row.doc.writable
			change.pressed.connect(func() -> void: reaction_requested.emit(_item_script(), node, ""))
			line.add_child(change)
			var remove := Button.new()
			remove.text = "Remove"
			remove.disabled = not row.doc.writable
			remove.pressed.connect(func() -> void:
				var current := _current_row()
				if current.is_empty(): return
				current.script_field = "use"
				var error := StoryGraph.set_effect(current, node, "")
				if not error.is_empty(): problem.emit(error); return
				workspace.reindex()
				changed.emit(_current_row()))
			line.add_child(remove)
			body.add_child(line)
		elif node.kind == "text": _event_note(str(node.text).left(180) + ("…" if str(node.text).length() > 180 else ""))
		elif node.kind == "if" and depth < 3:
			for branch: Dictionary in node.branches:
				_event_note("Only if: " + EventTriggers.describe_condition(workspace, str(branch.condition)))
				_add_item_steps(branch.body, depth + 1)
			if node.get("else") is Array and not node["else"].is_empty():
				_event_note("Otherwise:")
				_add_item_steps(node["else"], depth + 1)
		elif node.kind == "choices" and depth < 3:
			for option: Dictionary in node.options:
				_event_note("After choosing: “" + str(option.label) + "”" + (" · Only if: " + EventTriggers.describe_condition(workspace, str(option.condition)) if not str(option.condition).is_empty() else ""))
				_add_item_steps(option.body, depth + 1)
		elif node.kind == "goto": _event_note("Continue to: " + str(node.target))
		elif node.kind == "play": _event_note("Play story and return: " + str(node.target))
		elif node.kind == "page_break": _event_note("Wait for the player to continue")
		else: _event_note("Additional story steps · Open the use story to inspect them.")

func _add_item_form() -> void:
	var value: String = row.doc.field_value(row.def, "infectious")
	_event_note("No food mutation" if value.is_empty() else "Toward: " + EventTriggers.title_for(workspace, "form", value))
	var controls := HBoxContainer.new()
	body.add_child(controls)
	var choose := Button.new()
	choose.text = "Choose mutation form…"
	choose.disabled = not row.doc.writable or row.def.fields.has("use action")
	choose.pressed.connect(_open_reference.bind("infectious"))
	controls.add_child(choose)
	var clear := Button.new()
	clear.text = "No food mutation"
	clear.visible = not value.is_empty()
	clear.disabled = not row.doc.writable or value.is_empty()
	clear.pressed.connect(_clear_item_field.bind("infectious"))
	controls.add_child(clear)

func _clear_item_field(key: String) -> void:
	if pending_rows: return
	var current := _current_row()
	if current.is_empty(): return
	var error: String = current.doc.remove_simple_field(current.def, key)
	if not error.is_empty(): problem.emit(error); return
	workspace.reindex()
	changed.emit(_current_row())

func _build_summary() -> void:
	var sheet := layout.sheet
	sheet.add_child(AuthoringLayout.label("AT A GLANCE", 13, true))
	var name: String = row.doc.field_value(row.def, "name")
	sheet.add_child(AuthoringLayout.label(name if not name.is_empty() else str(row.def.id).capitalize(), 22))
	sheet.add_child(AuthoringLayout.label(AuthoringLayout.type_name(row.def.type) + " · " + ("Your pack" if row.doc.writable else "Reference · view only"), 14, true))
	if section == "properties" and ContentDB.SCHEMA.get(row.def.type, {}).has(property_key):
		var info := AuthoringCatalog.property(row.def.type, property_key, ContentDB.SCHEMA[row.def.type][property_key])
		sheet.add_child(AuthoringLayout.label(info.title, 19))
		sheet.add_child(AuthoringLayout.label(info.help, 14))
		sheet.add_child(AuthoringLayout.label("In use" if row.def.fields.has(property_key) else "Available · added when you apply a value", 13, true))
	if row.def.type == "event":
		sheet.add_child(AuthoringLayout.label(EventTriggers.describe(workspace, row.doc.field_value(row.def, "found by")), 15))
		sheet.add_child(AuthoringLayout.label("Only if: " + EventTriggers.describe_condition(workspace, row.doc.field_value(row.def, "requires")), 14, true))
		var repeat: String = row.doc.field_value(row.def, "repeat")
		sheet.add_child(AuthoringLayout.label("Repeat: " + {"": "Once", "once": "Once", "always": "Whenever eligible", "until resolved": "Until resolved"}.get(repeat, repeat), 14))
	else:
		for key: String in ["lives at", "zone", "region", "category"]:
			var value: String = row.doc.field_value(row.def, key)
			if not value.is_empty(): sheet.add_child(AuthoringLayout.label(key.capitalize() + ": " + value.capitalize(), 14))
	if row.def.type == "item":
		sheet.add_child(AuthoringLayout.label("Used up after use" if row.doc.field_value(row.def, "consumed") != "no" else "Reusable", 15))
		var form: String = row.doc.field_value(row.def, "infectious")
		sheet.add_child(AuthoringLayout.label("Food mutation: " + ("None" if form.is_empty() else EventTriggers.title_for(workspace, "form", form)), 14, true))
		var actions := 0
		for node: Dictionary in StoryGraph.script_nodes(_item_script()):
			if node.kind == "effect": actions += 1
		sheet.add_child(AuthoringLayout.label("%d direct use reactions" % actions, 14, true))
	if row.def.type == "condition":
		sheet.add_child(AuthoringLayout.label("Apply from a story or item. Set duration there.", 14))
	if row.def.type != "condition":
		var count := StoryGraph.choices(row).size()
		sheet.add_child(AuthoringLayout.label("%d player responses" % count, 14, true))
	sheet.add_child(AuthoringLayout.label("Unsaved changes" if row.doc.dirty() else "Saved", 13, true))
	sheet.add_child(AuthoringLayout.label("Use Save all to keep your changes.", 13, true))

func _add_story_cards(schema: Dictionary) -> void:
	if row.def.type in ["scene", "text", "menu"]:
		var button := AuthoringLayout.choice("Open story board", "Write passages, add responses and connect the next story.")
		button.pressed.connect(func() -> void: story_requested.emit(row, "@body"))
		body.add_child(button)
	var descriptions := {"ends": "When this condition expires; its bonuses have already been removed", "each turn": "While active, on each turn before the final expiry turn", "enters": "When a meter enters this condition’s stage (not ordinary timed application)", "still": "When a meter remains in this stage", "play": "What happens during this event", "talk": "Conversation and player responses", "description": "What the player sees", "enter": "When the player enters this place", "presence": "While the player is here", "actions": "Things the player can choose to do", "use": "When the player uses this item", "observe": "Things the player can examine"}
	var titles := {"play": "Event story", "talk": "Conversation", "enter": "On entering", "presence": "While here", "actions": "Player actions", "use": "Use this item", "observe": "Examine surroundings"}
	var search := LineEdit.new()
	search.placeholder_text = "Find an interaction…"
	body.add_child(search)
	var choices := VBoxContainer.new()
	body.add_child(choices)
	var keys: Array = schema.keys()
	keys.sort()
	var priority := ["play", "talk", "use", "enter", "actions", "observe", "description"]
	for index in range(priority.size() - 1, -1, -1):
		if priority[index] in keys:
			keys.erase(priority[index])
			keys.push_front(priority[index])
	for key: String in keys:
		if schema[key] not in ["script", "menu"]: continue
		var exists: bool = row.def.fields.has(key)
		var card := AuthoringLayout.choice(titles.get(key, key.capitalize()), descriptions.get(key, "Write this interaction.") + (" · Existing" if exists else (" · Start writing" if row.doc.writable else " · Not defined")))
		card.disabled = not row.doc.writable and not exists
		card.pressed.connect(func() -> void: story_requested.emit(row, key))
		card.set_meta("search", (key + " " + str(descriptions.get(key, ""))).to_lower())
		choices.add_child(card)
	search.text_changed.connect(func(text: String) -> void:
		for card: Control in choices.get_children(): card.visible = text.to_lower() in str(card.get_meta("search")))

func _event_note(text: String) -> void:
	if text.is_empty(): return
	var label := Label.new()
	label.text = text
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.theme_type_variation = "MutedLabel"
	body.add_child(label)

func _add_event_flow() -> void:
	if section == "when":
		_event_note(EventTriggers.describe(workspace, row.doc.field_value(row.def, "found by")))
		var change := AuthoringLayout.choice("Change when & where", "Choose named places, zones and ways to start this event.")
		change.disabled = not row.doc.writable
		change.pressed.connect(_open_triggers)
		body.add_child(change)
		_event_note("Zone events belong to a shared encounter pool. Arrival events are checked on entry.")
		return
	var requirement: String = row.doc.field_value(row.def, "requires")
	_event_note("Only if: " + EventTriggers.describe_condition(workspace, requirement))
	var controls := HFlowContainer.new()
	body.add_child(controls)
	var add := Button.new()
	add.text = "+ Add condition"
	add.disabled = not row.doc.writable
	add.pressed.connect(func() -> void:
		if not pending_rows: condition_requested.emit(row))
	controls.add_child(add)
	var clear := Button.new()
	clear.text = "Remove all conditions"
	clear.disabled = not row.doc.writable or requirement.is_empty()
	clear.pressed.connect(func() -> void: _set_value("requires", ""))
	controls.add_child(clear)
	for key: String in ["repeat", "chance", "cooldown", "priority"]:
		if row.def.fields.has(key) or key == "repeat" or show_all: _add_field(key, "text")
	var more := Button.new()
	more.text = "Fewer frequency options" if show_all else "More frequency options"
	more.pressed.connect(func() -> void: show_all = not show_all; _refresh())
	body.add_child(more)

func _open_triggers() -> void:
	if pending_rows:
		problem.emit("Apply your edited entries before changing triggers.")
		return
	var current := _current_row()
	if current.is_empty():
		return
	trigger_original = current.doc.field_value(current.def, "found by")
	var field: FscParser.Field = current.def.fields.get("found by")
	if field != null and not field.children.is_empty():
		problem.emit("This trigger has additional source lines and is preserved.")
		return
	trigger_editor.configure(workspace, trigger_original, current.doc.writable)
	trigger_dialog.popup_centered()

func _apply_triggers() -> void:
	var current := _current_row()
	if current.is_empty() or current.doc.field_value(current.def, "found by") != trigger_original:
		problem.emit("This trigger changed. Reopen it before applying your changes.")
		return
	var error := trigger_editor.validation_error()
	if error.is_empty():
		error = EventTriggers.apply_to(workspace, current, trigger_editor.value())
	if not error.is_empty():
		problem.emit(error)
		return
	trigger_dialog.hide()
	changed.emit(_current_row())

func _add_section(title: String, keys: Array[String], schema: Dictionary) -> void:
	if keys.is_empty():
		return
	if not title.is_empty():
		var heading := Label.new()
		heading.text = title
		heading.add_theme_font_size_override("font_size", 17)
		body.add_child(heading)
	for key: String in keys:
		_add_field(key, str(schema[key]))

func _add_field(key: String, kind: String) -> void:
	var d: FscParser.Definition = row.def
	var doc: PackDocument = row.doc
	var caption := Label.new()
	caption.text = {"play": "Story", "requires": "Only if", "repeat": "Can happen", "chance": "Arrival chance (%)", "cooldown": "Arrival cooldown (turns)", "priority": "Priority (lower first)"}.get(key, key.capitalize()) if d.type == "event" else key.capitalize()
	if d.type == "item": caption.text = AuthoringCatalog.property(d.type, key, kind).title
	caption.add_theme_font_size_override("font_size", 13)
	body.add_child(caption)
	var field: FscParser.Field = d.fields.get(key)
	var value := doc.field_value(d, key)
	if d.type == "item" and key == "infectious":
		_add_item_form()
		return
	if d.type == "item" and key == "use action":
		var activity := OptionButton.new()
		var activities := ["", "rest", "wait", "explore", "scavenge"]
		for name: String in activities: activity.add_item("None · use a story instead" if name.is_empty() else name.capitalize())
		if value not in activities:
			_event_note("Unrecognized activity preserved: " + value)
			return
		activity.select(activities.find(value))
		activity.disabled = not doc.writable
		activity.item_selected.connect(func(index: int) -> void:
			if index == 0: _clear_item_field(key)
			elif d.fields.has("use"): problem.emit("This item already has a use story. Keep it, or remove it in Source before choosing a built-in activity.")
			else: _set_value(key, activities[index]))
		body.add_child(activity)
		return
	if d.type == "event" and key == "chance" and ContentDB.found_by(doc.field_value(d, "found by")).form == "arrival" and value.trim_suffix("%").is_valid_int() and int(value.trim_suffix("%")) >= 0 and int(value.trim_suffix("%")) <= 100:
		var line := HBoxContainer.new()
		var slider := HSlider.new()
		slider.min_value = 0
		slider.max_value = 100
		slider.step = 1
		slider.value = int(value.trim_suffix("%"))
		slider.editable = doc.writable
		slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var amount := Label.new()
		amount.text = str(int(slider.value)) + "%"
		amount.custom_minimum_size.x = 45
		var state := {"dragging": false}
		slider.drag_started.connect(func() -> void: state.dragging = true)
		slider.value_changed.connect(func(next: float) -> void:
			amount.text = str(int(next)) + "%"
			if not state.dragging:
				_set_value(key, str(int(next)) + ("%" if value.ends_with("%") else "")))
		slider.drag_ended.connect(func(changed: bool) -> void:
			state.dragging = false
			if changed:
				_set_value(key, str(int(slider.value)) + ("%" if value.ends_with("%") else "")))
		line.add_child(slider)
		line.add_child(amount)
		body.add_child(line)
		return
	if key in SWITCH_FIELDS.get(d.type, []) and value.is_empty():
		var setting := OptionButton.new()
		setting.add_item({"consumed": "Yes · use up one item (default)", "in combat": "No · outside fights only (default)"}.get(key, "Use game default") if d.type == "item" else "Use game default")
		setting.add_item("Enabled")
		setting.add_item("Disabled")
		setting.set_item_disabled(0, true)
		setting.disabled = not doc.writable
		setting.item_selected.connect(func(index: int) -> void:
			if index > 0:
				_set_value(key, "yes" if index == 1 else "no"))
		body.add_child(setting)
		return
	if key in SWITCH_FIELDS.get(d.type, []) and value in ["yes", "no"]:
		var toggle := CheckButton.new()
		toggle.text = ("Use up one item" if value == "yes" else "Keep the item") if d.type == "item" and key == "consumed" else ("Enabled" if value == "yes" else "Disabled")
		toggle.button_pressed = value == "yes"
		toggle.disabled = not doc.writable
		toggle.toggled.connect(func(enabled: bool) -> void: _set_value(key, "yes" if enabled else "no"))
		body.add_child(toggle)
		return
	var options: Array = CHOICE_FIELDS.get(d.type, {}).get(key, [])
	if not options.is_empty() and (value.is_empty() or value in options):
		var choice := OptionButton.new()
		choice.add_item("Once (game default)" if d.type == "event" and key == "repeat" else "Use default")
		choice.set_item_disabled(0, true)
		for option: String in options:
			choice.add_item({"once": "Once", "until resolved": "Until the story resolves it", "always": "Whenever eligible"}.get(option, option.capitalize()) if d.type == "event" and key == "repeat" else option.capitalize())
		choice.select(options.find(value) + 1)
		choice.disabled = not doc.writable
		choice.item_selected.connect(func(index: int) -> void:
			if index > 0:
				_set_value(key, options[index - 1]))
		body.add_child(choice)
		return
	if key in NUMBER_FIELDS.get(d.type, []) and value.is_valid_int():
		var number := SpinBox.new()
		number.min_value = -1000000
		number.max_value = 1000000
		number.allow_lesser = true
		number.allow_greater = true
		number.step = 1
		number.value = int(value)
		number.editable = doc.writable
		number.value_changed.connect(func(next: float) -> void: _set_value(key, str(int(next))))
		body.add_child(number)
		return
	if kind == "script" and key == "description" and (field == null or (field.children.is_empty() and "[" not in field.value and "]" not in field.value and not field.value.begins_with("->"))):
		var description := TextEdit.new()
		description.custom_minimum_size.y = 85
		description.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
		description.placeholder_text = "Write a description…"
		description.text = doc.field_value(d, key)
		description.editable = doc.writable
		description.focus_exited.connect(_save_text.bind(key, description))
		body.add_child(description)
		return
	if kind == "script" or kind == "menu":
		var story := Button.new()
		story.text = "Write " + key + " on the story board" if kind == "script" else "Edit " + key + " choices on the story board"
		if d.type == "event" and key == "play":
			story.text = "Write what happens on the story board"
		story.alignment = HORIZONTAL_ALIGNMENT_LEFT
		story.pressed.connect(func() -> void: story_requested.emit(row, key))
		body.add_child(story)
		return
	if kind in ["fields", "values", "stages", "effects"]:
		_add_rows(key, kind)
		return
	if (field != null and not field.children.is_empty()) or (kind == "text" and key in ["description", "about"]):
		var long_text := TextEdit.new()
		long_text.custom_minimum_size.y = 85
		long_text.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
		long_text.text = doc.field_value(d, key)
		long_text.editable = doc.writable and (field == null or not _field_has_comments(doc, field))
		long_text.focus_exited.connect(_save_text.bind(key, long_text))
		body.add_child(long_text)
		return
	var line := HBoxContainer.new()
	body.add_child(line)
	var input := LineEdit.new()
	input.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	input.text = doc.field_value(d, key)
	input.editable = doc.writable
	input.placeholder_text = "Not set"
	input.focus_exited.connect(_save_line.bind(key, input))
	input.text_submitted.connect(func(_v: String) -> void: input.release_focus())
	line.add_child(input)
	if REFERENCES.has(key) or (d.type == "item" and key == "infectious"):
		var choose := Button.new()
		choose.text = "Choose…"
		choose.disabled = not doc.writable
		choose.pressed.connect(_open_reference.bind(key))
		line.add_child(choose)

func _field_has_comments(doc: PackDocument, field: FscParser.Field) -> bool:
	if field.children.is_empty():
		return false
	var lines := doc.text.split("\n")
	for i in range(field.line, field.children[-1].number):
		if i < lines.size() and lines[i].strip_edges().begins_with("//"):
			return true
	return false

func _current_row() -> Dictionary:
	if row.is_empty():
		return {}
	return workspace.find_row(row.doc.path, row.def.type, row.def.id, row.def.mode, row.get("ordinal", 0))

func _save_line(key: String, input: LineEdit) -> void:
	if is_instance_valid(input):
		_set_value(key, input.text)

func _save_text(key: String, input: TextEdit) -> void:
	if is_instance_valid(input) and input.editable:
		_set_value(key, input.text)

func _set_value(key: String, value: String, force_block: bool = false) -> bool:
	if pending_rows and not applying_rows:
		problem.emit("Apply or remove the unfinished entries before editing another field.")
		return false
	var current := _current_row()
	if current.is_empty() or not current.doc.writable:
		return false
	if current.def.type == "event" and key == "requires" and value.is_empty():
		return _clear_event_requirement(current)
	if current.doc.field_value(current.def, key) == value or (value.is_empty() and not current.def.fields.has(key)):
		return true
	var before: String = current.doc.text
	var error: String = current.doc.set_field(current.def, key, value, force_block)
	if error.is_empty() and current.def.type == "item" and key == "infectious" and not value.is_empty() and not current.def.fields.has("use") and not current.def.fields.has("use action"):
		var fresh: FscParser.Definition
		for definition: FscParser.Definition in current.doc.definitions():
			if definition.type == "item" and definition.id == current.def.id: fresh = definition; break
		if fresh != null: error = current.doc.set_field(fresh, "use", "", true)
	if not error.is_empty(): current.doc.change(before)
	if not error.is_empty():
		problem.emit(error)
		return false
	workspace.reindex()
	changed.emit(workspace.find_row(current.doc.path, current.def.type, current.def.id, current.def.mode, current.get("ordinal", 0)))
	return true

func _clear_event_requirement(current: Dictionary) -> bool:
	var field: FscParser.Field = current.def.fields.get("requires")
	if field == null:
		return true
	if not field.children.is_empty():
		problem.emit("This condition has additional source lines and is preserved.")
		return false
	var doc: PackDocument = current.doc
	var offsets := doc.offsets()
	var begin: int = offsets[field.line - 1]
	var end: int = offsets[field.line] if field.line < offsets.size() else doc.text.length()
	doc.change(doc.text.left(begin) + doc.text.substr(end))
	workspace.reindex()
	changed.emit(_current_row())
	return true

func _add_rows(key: String, kind: String) -> void:
	if key == "while active" and row.def.type == "condition": kind = "bonuses"
	var d: FscParser.Definition = row.def
	var doc: PackDocument = row.doc
	var field: FscParser.Field = d.fields.get(key)
	var entries: Array[Dictionary] = []
	if field != null:
		if kind == "bonuses" and not field.value.is_empty():
			_event_note("This section has inline rules and is preserved unchanged.")
			return
		if _field_has_comments(doc, field):
			var note := Label.new()
			note.text = "This section contains author notes and is preserved."
			body.add_child(note)
			return
		for child: FscParser.Line in field.children:
			if child.is_blank():
				continue
			if child.indent != 4:
				var note := Label.new()
				note.text = "This section has nested settings and is preserved."
				body.add_child(note)
				return
			var separator := child.text.find(":")
			if separator < 0 and kind not in ["stages", "bonuses"]:
				var note := Label.new()
				note.text = "This section contains additional rules and is preserved."
				body.add_child(note)
				return
			if kind == "bonuses":
				entries.append({"name": "", "value": child.text})
				continue
			entries.append({"name": child.text.left(separator).strip_edges() if separator >= 0 else child.text, "value": child.text.substr(separator + 1).strip_edges() if separator >= 0 else ""})
	if kind == "values":
		_event_note("These values belong to %s. Flags remember yes/no; numbers count; states track progress. Stories can check and change them after you apply. Changing a name can break existing stories and saves." % d.id)
	var list := VBoxContainer.new()
	list.set_meta("source", doc.text)
	body.add_child(list)
	var error_label := AuthoringLayout.label("", 14)
	error_label.theme_type_variation = "ErrorLabel"
	error_label.hide()
	(layout.sheet if kind in ["values", "bonuses"] else body).add_child(error_label)
	list.set_meta("error_label", error_label)
	for entry: Dictionary in entries:
		_add_row_controls(list, entry.name, entry.value, doc.writable, kind, key)
	if doc.writable:
		var buttons: BoxContainer = VBoxContainer.new() if kind in ["values", "bonuses"] else HBoxContainer.new()
		var add := Button.new()
		add.text = "+ Add bonus" if kind == "bonuses" else "+ Add entry"
		add.pressed.connect(func() -> void:
			_add_row_controls(list, "", "", true, kind, key)
			_mark_rows(key))
		buttons.add_child(add)
		var apply := Button.new()
		apply.text = "Apply entries"
		apply.pressed.connect(_save_rows.bind(key, kind, list))
		buttons.add_child(apply)
		var discard := Button.new()
		discard.text = "Discard entry edits"
		discard.pressed.connect(func() -> void:
			pending_sections.erase(key)
			pending_rows = not pending_sections.is_empty()
			_refresh())
		buttons.add_child(discard)
		(layout.sheet if kind in ["values", "bonuses"] else body).add_child(buttons)

func _add_row_controls(parent: VBoxContainer, name: String, value: String, writable: bool, kind: String, section: String) -> void:
	if kind == "bonuses":
		var entry := AttributeBonusRow.new()
		entry.configure(value, writable)
		entry.edited.connect(_mark_rows.bind(section))
		if writable:
			var remove := Button.new()
			remove.text = "Remove"
			remove.pressed.connect(func() -> void: _mark_rows(section); entry.queue_free())
			entry.add_child(remove)
		parent.add_child(entry)
		return
	if kind == "values":
		var entry := SavedValueRow.new()
		entry.configure(name, value, writable)
		entry.edited.connect(_mark_rows.bind(section))
		if writable:
			var remove := Button.new()
			remove.text = "Remove"
			remove.pressed.connect(func() -> void: _mark_rows(section); entry.queue_free())
			entry.add_child(remove)
		parent.add_child(entry)
		return
	var line := HBoxContainer.new()
	var name_input := LineEdit.new()
	name_input.text = name
	name_input.placeholder_text = "Name"
	name_input.editable = writable
	name_input.custom_minimum_size.x = 110
	name_input.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	line.add_child(name_input)
	if writable:
		name_input.text_changed.connect(func(_v: String) -> void: _mark_rows(section))
	if kind == "fields" and section in ["relationship", "body", "equipment", "weapon"] and value in ["yes", "no"]:
		var switch := CheckButton.new()
		switch.text = "Enabled" if value == "yes" else "Disabled"
		switch.button_pressed = value == "yes"
		switch.disabled = not writable
		switch.toggled.connect(func(enabled: bool) -> void:
			switch.text = "Enabled" if enabled else "Disabled"
			_mark_rows(section))
		line.add_child(switch)
	else:
		var value_input := LineEdit.new()
		value_input.text = value
		value_input.placeholder_text = "Value"
		value_input.editable = writable
		value_input.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		if writable:
			value_input.text_changed.connect(func(_v: String) -> void: _mark_rows(section))
		line.add_child(value_input)
	if writable:
		var remove := Button.new()
		remove.text = "Remove"
		remove.pressed.connect(func() -> void:
			_mark_rows(section)
			line.queue_free())
		line.add_child(remove)
	parent.add_child(line)

func _rows_error(list: VBoxContainer, message: String) -> void:
	if list.has_meta("error_label"):
		var label: Label = list.get_meta("error_label")
		label.text = message
		label.show()
	else:
		problem.emit(message)

func _save_rows(key: String, kind: String, list: VBoxContainer) -> void:
	if list.has_meta("error_label"):
		(list.get_meta("error_label") as Label).hide()
	if list.has_meta("source") and row.doc.text != list.get_meta("source"):
		_rows_error(list, "This content changed while these entries were open. Reopen this section before applying them.")
		return
	var lines: Array[String] = []
	var names := {}
	for child: Node in list.get_children():
		if child.is_queued_for_deletion():
			continue
		if kind == "bonuses":
			var bonus := (child as AttributeBonusRow).declaration()
			if bonus.has("error"):
				_rows_error(list, bonus.error)
				return
			lines.append(bonus.spec)
			continue
		var name := (child.get_child(0) as LineEdit).text.strip_edges()
		var value := ""
		if kind == "values":
			var result: Dictionary = (child as SavedValueRow).declaration()
			if result.has("error"):
				_rows_error(list, "Value '%s': %s" % [name, result.error])
				return
			value = result.spec
		else:
			var editor := child.get_child(1)
			if editor is CheckButton:
				value = "yes" if editor.button_pressed else "no"
			else:
				value = (editor as LineEdit).text.strip_edges()
		if name.is_empty() or "\n" in name or "\r" in name or "\n" in value or ":" in name:
			_rows_error(list, "Each entry needs a name on one line without a colon.")
			return
		if kind == "values" and RegEx.create_from_string("^[a-z0-9_]+(?:\\.[a-z0-9_]+)*$").search(name) == null:
			_rows_error(list, "Use lowercase letters, numbers and underscores in value names, such as met_guide.")
			return
		if kind == "values" and names.has(name):
			_rows_error(list, "Each entry needs a different name: " + name)
			return
		names[name] = true
		lines.append(name if kind == "stages" and value.is_empty() else name + ": " + value)
	applying_rows = true
	var was_pending := pending_sections.has(key)
	pending_sections.erase(key)
	pending_rows = not pending_sections.is_empty()
	var saved := _set_value(key, "\n".join(lines), true)
	applying_rows = false
	if not saved and was_pending:
		_mark_rows(key)

func _open_reference(key: String) -> void:
	picker_field = key
	picker_rows.clear()
	for candidate: Dictionary in workspace.rows:
		if candidate.def.type in (["form"] if key == "infectious" and row.def.type == "item" else REFERENCES[key]) and candidate.def.mode == "define":
			picker_rows.append(candidate)
	picker_search.text = ""
	_filter_picker()
	picker.popup_centered()
	picker_search.grab_focus()

func _filter_picker() -> void:
	picker_list.clear()
	for candidate: Dictionary in picker_rows:
		var d: FscParser.Definition = candidate.def
		var display: String = d.fields["name"].value if d.fields.has("name") else d.id
		if not picker_search.text.is_empty() and picker_search.text.to_lower() not in (display + " " + d.id + " " + candidate.pack).to_lower():
			continue
		picker_list.add_item(display + " · " + d.id + " · " + candidate.pack)
		picker_list.set_item_metadata(picker_list.item_count - 1, candidate)
	picker.get_ok_button().disabled = true
	picker_hint.text = "No matching entries. Try another search or load a reference pack." if picker_list.item_count == 0 else "Choose an entry from the loaded packs."

func _apply_reference() -> void:
	var indexes := picker_list.get_selected_items()
	if indexes.is_empty():
		return
	var candidate: Dictionary = picker_list.get_item_metadata(indexes[0])
	var value: String = candidate.def.id
	var kind: String = ContentDB.SCHEMA.get(row.def.type, {}).get(picker_field, "")
	if kind == "list":
		var previous: String = row.doc.field_value(row.def, picker_field)
		if not previous.is_empty() and value not in previous.split(","):
			value = previous + ", " + value
	if not _set_value(picker_field, value):
		return
	if candidate.root != workspace.target:
		var error := workspace.add_requirement(candidate.pack)
		if not error.is_empty():
			problem.emit("Add the reference pack as a dependency: " + error)

func _mark_rows(section: String) -> void:
	pending_sections[section] = true
	pending_rows = true
