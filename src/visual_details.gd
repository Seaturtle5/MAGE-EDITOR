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
	"trades for": ["item"], "generic": ["event"], "leads to zone": ["zone"], "milk item": ["item"], "cum item": ["item"],
	"cross infection": ["form"], "heat": ["heat"], "loading": ["image"], "condition": ["condition"], "sire anal tag": ["tag"]
}
const PRIMARY_FIELDS := ["name", "description", "pronouns", "image", "lives at", "found by", "repeat", "requires", "chance", "cooldown", "priority", "category", "weight", "level", "hp", "damage", "zone", "start"]
const SWITCH_FIELDS := {
	"item": ["consumed", "keep", "in combat", "plural"],
	"creature": ["unique", "group", "infectious", "research bypass", "magic", "seduction immune", "name known"],
	"event": ["active", "replaces trip"],
	"menu": ["pause after each"],
	"captivity": ["pause after each"],
	"condition": ["blocks rest"],
	"shop": ["trades"],
	"heat": ["female", "mpreg"],
	"interest": ["default"],
	"form": ["sex by preference"],
	"location": ["microwave"]
}
const CHOICE_FIELDS := {
	"event": {"repeat": ["once", "until resolved", "always"]},
	"form": {"sex": ["male", "female", "herm"]},
	"item": {"category": ["food", "drink", "medical", "weapon", "clothing", "collectible", "other"]},
	"creature": {"active": ["always", "day", "night"], "gender": Validator.CREATURE_GENDERS, "strike with": CombatSystem.ATTRIBUTES, "pick variant": ["random", "in order"]},
	"pack": {"art": ["replaces", "fallback"]},
	"menu": {"sort": ["by name"]},
	"character": {"pronouns": ["he", "she", "they", "it", "by body"]}
}
const NUMBER_FIELDS := {
	"item": ["weight"],
	"event": ["priority", "cooldown", "level", "min score"],
	"creature": ["level", "hp", "damage", "libido", "hit bonus", "dodge bonus", "mind bonus"],
	"feat": ["exploration bonus", "encounter bonus", "scavenge bonus", "loot bonus", "carry bonus"],
	"help": ["order"],
	"notes_rules": ["longest"],
	"pack": ["loading frames"],
	"region": ["travel order"],
	"game_mode": ["exploration bonus", "encounter bonus", "scavenge bonus", "carry bonus", "loot bonus"],
	"meter": ["decay", "limit"],
	"captivity": ["climax at"],
	"scavenge_rules": ["target"],
	"survival_rules": ["starving hint at", "journal hint below", "anticipation within", "rescue after"],
	"pregnancy_rules": ["most children"],
	"combat_rules": ["unarmed damage"],
	"heat": ["cycle", "duration"],
	"rest_rules": ["duration", "fresh below", "fresh fatigue", "exhausted recovery", "hammock fresh fatigue", "hammock recovery", "collapse at", "collapse fatigue", "collapse turns"],
	"ending": ["priority"],
	"form": ["libido", "scale"],
	"infection_rules": ["modest cock length", "modest ball size", "modest cunt depth", "modest cunt tightness"]
}
## Numbers that may also be a calculation (level * 2).
const FORMULA_FIELDS := {
	"captivity": ["escape at"],
	"companion_rules": ["party size", "companion xp", "player xp cost", "level up at", "damage every", "dexterity every", "hit bonus"],
	"vore_rules": ["vore chance", "vore chance out of", "unbirth chance", "unbirth chance out of", "absorb above"],
	"hunt_rules": ["target weight"],
	"level_rules": ["xp needed"],
	"combat_rules": ["level limit", "hump lust"]
}
## Chances written "N in M".
const CHANCE_FIELDS := {
	"shop": ["trade bonus chance"],
	"infection_rules": ["resist chance", "twice chance"],
	"combat_rules": ["creature chance"],
	"heat_rules": ["intense lengthens", "intense quickens"],
	"pregnancy_rules": ["odds", "self odds", "sire odds", "albino", "melanism"],
	"rest_rules": ["interruption chance"],
	"scavenge_rules": ["generic chance"]
}
## Spans written "N to M" (a number of turns somewhere between the two).
const RANGE_FIELDS := {
	"pregnancy_rules": ["gestation", "sire turns"],
	"vore_rules": ["unbirth gestation"]
}
## Words the player reads, written in a roomy text box (with markup).
const MESSAGE_FIELDS := {
	"collection": ["empty", "gained", "lost"],
	"combat_rules": ["unarmed attack", "player hits", "flee", "flee fails"],
	"notes_rules": ["missing", "write", "browse", "none", "date", "crossed out", "torn out"],
	"pack": ["start notice", "start notice title"],
	"scavenge_rules": ["found", "failure", "only at"],
	"storage": ["stash", "stash all", "retrieve", "retrieve all", "stash everything", "retrieve everything", "kept", "in use", "empty", "pack empty"],
	"survival_rules": ["morale normalized", "humanity loss", "rescue anticipation"]
}
## One word that groups or names a kind; the words other content uses are offered beside the box.
const WORD_FIELDS := {
	"feat": ["group"], "interest": ["group"], "ending": ["type"], "creature": ["special"],
	"item": ["rest", "icon"], "location": ["rest"], "collection": ["of"], "pack": ["feedback webhook"], "status_bar": ["start date", "sheet"],
	"event": ["blocks"], "level": ["default", "from"], "heat_rules": ["default"], "filter": ["group", "from"], "tag": ["group", "from"]
}
## A saved value, chosen from the values the packs declare.
const VALUE_FIELDS := {"meter": ["value"], "combat_rules": ["auto action"]}
## Two numbers with something between them: a place on the map ("5, 7"), a grid's size ("12 x 12").
const POINT_FIELDS := {"location": {"map": [", ", "Across", "Down"]}, "region": {"map grid": [" x ", "Wide", "High"]}}
## Lists of short words shown as chips; the value names where suggestions come from.
const CHIP_FIELDS := {"tags": "tag", "gift tags": "tag", "flags": "place_flag", "aliases": "", "outcomes": "", "personalities": "", "genders": "", "meters": "", "menu icons": "", "choices": "", "extra children": "", "currency names": ""}

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
var condition_editor: ConditionDialog
var condition_key := ""

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

## Set when the page holds content it has not drawn yet (it was not in view).
var stale := false

## Takes the content to show. With `draw` off the page is only drawn when
## draw_if_stale() is called: filling a page nobody looks at costs time.
func show_definition(value: PackWorkspace, selected: Dictionary, draw: bool = true) -> void:
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
	stale = not draw
	if draw: _refresh()

func draw_if_stale() -> void:
	if stale and not pending_rows:
		stale = false
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
	stale = false
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
	if d.type == "item": sections.append_array([{"key": "use", "title": "Use & reactions"}, {"key": "gear", "title": "Wearing & fighting"}])
	if d.type == "form": sections.append({"key": "body", "title": "Body"})
	if d.type == "character": sections.append({"key": "body", "title": "Body & stats"})
	sections.append_array([{"key": "stories", "title": "Stories"}, {"key": "settings", "title": "Settings"}, {"key": "properties", "title": "Properties"}])
	layout.set_sections(sections, section)
	_build_summary()
	var titles := {"overview": "The essentials", "gear": "Wearing it and fighting with it", "body": "The body", "when": "When does it happen?", "conditions": "What needs to be true?", "stories": "Write what happens", "settings": "Other settings", "properties": "What can this content do?", "use": "When the player uses this item", "bonuses": "What changes while this is active?"}
	body.add_child(AuthoringLayout.label(titles.get(section, "Details"), 24))
	var hints := {"overview": "Start with the basics, then choose a section above.", "gear": "Dimmed settings are not written: the game uses what they show. Change one to set it; × takes it out again.", "body": "Dimmed settings are not written: the game uses what they show. Change one to set it; × takes it out again.", "when": "Choose how the player finds this event and where it can happen.", "conditions": "Choose requirements and how often this event can run.", "stories": "Choose an interaction to write. Existing passages stay connected to this content.", "settings": "Adjust the settings already used by this content.", "properties": "Browse every available property, including ones already in use. Choose one to see what it does.", "use": "Write the use story, choose reactions and decide whether the item is used up."}
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
				destinations.push_front(["Wearing & fighting", "Make it clothing, armour or a weapon.", "gear"])
				destinations.push_front(["Use & reactions", "Set healing, food effects, mutation and whether this item is used up.", "use"])
			if d.type == "form":
				destinations.push_front(["Body", "What each part looks like, the text when it changes, and sizes.", "body"])
			if d.type == "character":
				destinations.push_front(["Body & stats", "The character's body, numbers and standing with the player.", "body"])
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
		"gear": _add_sheets([["equipment", "Worn", "Set where it is worn to make this something the player can put on."], ["weapon", "Weapon", "Set its damage to make this something the player can fight with."]])
		"body":
			if d.type == "form":
				_add_section("", ["sex", "sex by preference", "scale", "body type", "descriptor"] as Array[String], schema)
				var parts: Array = []
				for part: String in BodySystem.PARTS + ["breasts", "balls"]: parts.append([part, part.capitalize(), ""])
				_add_sheets(parts)
			else:
				_add_sheets([["body", "Body", "The body the character has. What is not set starts at nothing."], ["stats", "Numbers", "Level, health and attributes, and any other number the game keeps for a character."], ["relationship", "With the player", "How things stand between the character and the player when the game starts."], ["companion", "Following the player", "Set one of these to let the character follow the player as a companion."]])

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
				var current := _current_row().duplicate()
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

## A field's name as a heading: "sex by preference" reads "Sex by preference".
static func _caption(key: String) -> String:
	return key.left(1).to_upper() + key.substr(1)

func _add_field(key: String, kind: String) -> void:
	var d: FscParser.Definition = row.def
	var doc: PackDocument = row.doc
	var caption := Label.new()
	caption.text = {"play": "Story", "requires": "Only if", "repeat": "Can happen", "chance": "Arrival chance (%)", "cooldown": "Arrival cooldown (turns)", "priority": "Priority (lower first)"}.get(key, _caption(key)) if d.type == "event" else _caption(key)
	if d.type == "item": caption.text = AuthoringCatalog.property(d.type, key, kind).title
	caption.add_theme_font_size_override("font_size", 13)
	body.add_child(caption)
	var field: FscParser.Field = d.fields.get(key)
	var value := doc.field_value(d, key)
	if d.type == "item" and key == "infectious":
		_add_item_form()
		return
	if d.type == "hook" and key == "on":
		_add_hook_moment(value)
		return
	if d.type == "hook" and key == "while incapacitated" and value in ["", "skip"]:
		var skip := CheckButton.new()
		skip.text = "Skip this hook while the player is in a fight"
		skip.button_pressed = value == "skip"
		skip.disabled = not doc.writable
		skip.toggled.connect(func(on: bool) -> void:
			if on: _set_value(key, "skip")
			else: _clear_item_field(key))
		body.add_child(skip)
		return
	if is_condition_field(d.type, key) and (field == null or field.children.is_empty()) and (value.is_empty() or not Condition.compile(value).has("error")):
		_add_condition_field(key, value)
		return
	if CHIP_FIELDS.has(key) and (field == null or field.children.is_empty()):
		_add_chip_field(key, value)
		return
	if d.type == "quest" and key == "done at":
		# The stage that finishes the quest, chosen from its own stages.
		var stage := PickerButton.new()
		stage.placeholder = "Choose the stage that finishes the quest…"
		stage.alignment = HORIZONTAL_ALIGNMENT_LEFT
		stage.disabled = not doc.writable
		stage.options = func() -> Array:
			var result: Array = []
			for name: String in workspace.preview_content().quests.get(d.id, {}).get("stages", []): result.append({"value": name, "label": name.replace("_", " ")})
			return result
		stage.set_value(value)
		stage.picked.connect(func(name: String) -> void:
			if not name.is_empty(): _set_value(key, name))
		body.add_child(stage)
		return
	if d.type == "creature" and key == "loot" and (value.is_empty() or _read_loot(value).size() == 2):
		_add_loot_field(key, value)
		return
	if d.type == "door" and key == "locked" and (field == null or field.children.is_empty()) and (value in ["", "yes", "no"] or not Condition.compile(value).has("error")):
		_add_lock_field(key, value)
		return
	if key == "stages" and d.type in ["quest", "meter"]:
		var steps := StageRows.read(doc, field, d.type == "meter")
		if steps.ok:
			var stages := StageRows.new()
			stages.configure(workspace, steps.entries, doc.writable, d.type == "meter")
			stages.problem.connect(func(message: String) -> void: problem.emit(message))
			stages.edited.connect(func(text: String) -> void:
				if text.is_empty(): _clear_nested(key)
				else: _set_value(key, text, true))
			body.add_child(stages)
			return
	if key in FORMULA_FIELDS.get(d.type, []) and (field == null or field.children.is_empty()):
		_add_formula_field(key, value)
		return
	if key in CHANCE_FIELDS.get(d.type, []) and (value.is_empty() or _read_chance(value).size() == 2):
		_add_chance_field(key, value)
		return
	if d.type == "shop" and key in ["stock", "buys"]:
		var listed := PriceRows.read(doc, field)
		if listed.ok:
			var prices := PriceRows.new()
			prices.configure(workspace, listed.entries, doc.writable, StoryBlocks.contexts(row))
			prices.edited.connect(func(text: String) -> void:
				if text.is_empty(): _clear_nested(key)
				else: _set_value(key, text, true))
			body.add_child(prices)
			return
	if d.type in ["shop", "status_bar"] and key == "currency" and (value.is_empty() or not value.begins_with("item ") or workspace.preview_content().has(value.trim_prefix("item ").strip_edges(), "item")):
		_add_currency_field(key, value)
		return
	if PairRows.has_rows(d.type, key):
		var rules: Dictionary = PairRows.SPECS[d.type + "/" + key]
		var pairs := PairRows.read(doc, field, rules)
		if pairs.ok:
			var table := PairRows.new()
			table.configure(workspace, pairs.entries, doc.writable, rules, StoryBlocks.contexts(row))
			table.edited.connect(func(text: String) -> void:
				if text.is_empty(): _clear_nested(key)
				else: _set_value(key, text, not rules.get("inline", false)))
			body.add_child(table)
			return
	if key in VALUE_FIELDS.get(d.type, []) and (field == null or field.children.is_empty()):
		var held := SlotControl.make(workspace, {"name": key, "kind": "value", "default": "", "hidden": false, "optional": false}, value)
		held.picker.disabled = not doc.writable
		held.edited.connect(func() -> void:
			if not held.value().is_empty(): _set_value(key, held.value()))
		body.add_child(held)
		return
	if POINT_FIELDS.get(d.type, {}).has(key):
		var shape: Array = POINT_FIELDS[d.type][key]
		var parts := value.split(str(shape[0]))
		if value.is_empty() or (parts.size() == 2 and parts[0].strip_edges().is_valid_int() and parts[1].strip_edges().is_valid_int()):
			var line := HBoxContainer.new()
			line.add_theme_constant_override("separation", 8)
			body.add_child(line)
			var boxes: Array[SpinBox] = []
			for index in 2:
				line.add_child(AuthoringLayout.label(str(shape[index + 1]), 13, true))
				var box := SpinBox.new()
				box.min_value = -1000
				box.max_value = 1000
				box.value = float(parts[index]) if parts.size() == 2 else 0.0
				box.editable = doc.writable
				line.get_child(-1).autowrap_mode = TextServer.AUTOWRAP_OFF
				line.add_child(box)
				boxes.append(box)
			for box: SpinBox in boxes: box.value_changed.connect(func(_number: float) -> void: _set_value(key, "%d%s%d" % [int(boxes[0].value), shape[0], int(boxes[1].value)]))
			if value.is_empty(): line.add_child(AuthoringLayout.label("Not set: the game places it by itself.", 13, true))
			return
	if key in RANGE_FIELDS.get(d.type, []) and (value.is_empty() or _read_range(value).size() == 2):
		_add_range_field(key, value)
		return
	if kind == "fields" and key.ends_with(" modifiers"):
		var adjustments := ModifierRows.read(doc, field)
		if adjustments.ok:
			var rules := ModifierRows.new()
			rules.configure(workspace, adjustments.entries, doc.writable, StoryBlocks.contexts(row), caption.text)
			rules.problem.connect(func(message: String) -> void: problem.emit(message))
			rules.edited.connect(func(text: String) -> void:
				if text.is_empty(): _clear_nested(key)
				else: _set_value(key, text, true))
			body.add_child(rules)
			return
	if kind == "fields" and SettingsSheet.has_sheet(d.type, key):
		var held := SettingsSheet.read(doc, field)
		if held.ok:
			_add_sheet(key, held.entries)
			return
	if key == "stats" and (field == null or field.children.is_empty()) and (value.is_empty() or not _read_stats(value).is_empty()):
		_add_stats_field(key, value)
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
	if (field != null and not field.children.is_empty()) or (kind == "text" and key in ["description", "about"]) or key in MESSAGE_FIELDS.get(d.type, []):
		var long_text := TextEdit.new()
		long_text.custom_minimum_size.y = 85
		long_text.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
		long_text.text = doc.field_value(d, key)
		long_text.editable = doc.writable and (field == null or not _field_has_comments(doc, field))
		long_text.focus_exited.connect(_save_text.bind(key, long_text))
		body.add_child(long_text)
		return
	if REFERENCES.has(key) and kind in ["text", "list"] and (field == null or field.children.is_empty()) and RegEx.create_from_string("^[a-z0-9_.-]+(, ?[a-z0-9_.-]+)*$|^$").search(value) != null:
		_add_reference_field(key, kind == "list", value)
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
	if kind == "text" and not REFERENCES.has(key) and doc.writable:
		# What other content of this kind has here: a word to pick instead of remembering it.
		var used := PickerButton.new()
		used.placeholder = "▾"
		used.text = "▾"
		used.theme_type_variation = "Ghost"
		used.tooltip_text = "Pick a value that other %s use here." % Wording.plural(d.type).to_lower()
		used.options = func() -> Array:
			var counts: Dictionary = {}
			for other: Dictionary in workspace.rows:
				if other.def.type != d.type or not other.def.fields.has(key): continue
				var seen: String = other.def.fields[key].value
				if seen.is_empty() or seen.length() > 40 or not other.def.fields[key].children.is_empty(): continue
				counts[seen] = int(counts.get(seen, 0)) + 1
			var values: Array = counts.keys()
			values.sort_custom(func(a: String, b: String) -> bool: return counts[a] > counts[b])
			var result: Array = []
			for seen: String in values.slice(0, 60): result.append({"value": seen, "label": seen, "detail": "used %d time%s" % [counts[seen], "" if counts[seen] == 1 else "s"]})
			return result
		used.label_for = func(_value: String) -> String: return "▾"
		used.picked.connect(func(chosen: String) -> void:
			if not chosen.is_empty(): _set_value(key, chosen))
		line.add_child(used)
	if REFERENCES.has(key) or (d.type == "item" and key == "infectious"):
		var choose := ReferenceButton.new()
		choose.workspace = workspace
		choose.kinds = ["form"] if key == "infectious" else REFERENCES[key]
		var original := doc.text
		choose.content_dropped.connect(func(data: Dictionary) -> void:
			var candidate := DragPayload.resolve(workspace, data)
			if candidate.is_empty(): return
			_assign_reference(key, candidate, original))
		choose.text = "Choose…"
		choose.disabled = not doc.writable
		choose.pressed.connect(_open_reference.bind(key))
		line.add_child(choose)

## Other content this content names (its picture, its home, the areas it is
## found in): chosen by name from the loaded packs, or dropped from the library.
func _add_reference_field(key: String, several: bool, value: String) -> void:
	var types: Array = REFERENCES[key]
	if not row.doc.writable:
		var names: Array[String] = []
		for id: String in value.split(",", false): names.append(BlockCatalog.content_label(str(types[0]), id.strip_edges(), workspace))
		body.add_child(AuthoringLayout.label(", ".join(names) if not names.is_empty() else "Not set", 15, names.is_empty()))
		return
	var spec := {"name": key, "kind": ("ids." if several else "") + str(types[0]), "default": "", "hidden": false, "optional": true, "types": types}
	var chosen := SlotControl.make(workspace, spec, value)
	chosen.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	chosen.edited.connect(func() -> void:
		var next := chosen.value()
		if next == value: return
		if next.is_empty():
			_clear_item_field(key)
			return
		if _set_value(key, next):
			for id: String in next.split(",", false):
				for type: String in types: workspace.require_content(type, id.strip_edges()))
	body.add_child(chosen)

const MOMENT_WORDS := {"each turn": "Every turn", "day starts": "When day starts", "night starts": "When night starts", "captivity starts": "When a captivity starts", "captivity round": "Each round of a captivity", "after sex": "After sex", "player hits": "When the player hits in a fight", "after resting": "After resting", "instead of resting": "Instead of resting", "game starts": "When the game starts", "while travelling": "While travelling", "instead of talking to ": "Instead of talking to…", "instead of sex with ": "Instead of sex with…", "after using ": "After using the item…",
	"infection": "Whenever the player is infected", "player's turn": "At the player's turn in a fight", "after import": "After earlier progress is imported", "arriving": "When the player arrives at a place",
	"after taking trophy ": "After taking the trophy…", "after picking up ": "After picking up the item…", "instead of using ": "Instead of using the item…", "before picking up ": "Before picking up the item…"}

## When a hook runs: one of the engine's moments, some about one character or item.
func _add_hook_moment(value: String) -> void:
	var writable: bool = row.doc.writable
	var line := HBoxContainer.new()
	body.add_child(line)
	var moments: Array = Game.HOOK_MOMENTS + Game.HOOK_CHARACTER_MOMENTS + Game.HOOK_ITEM_MOMENTS
	var current := ""
	for moment: String in moments:
		if value == moment or (moment.ends_with(" ") and value.begins_with(moment)): current = moment
	var list := OptionButton.new()
	list.add_item("Choose when this happens…")
	list.set_item_disabled(0, true)
	for moment: String in moments: list.add_item(MOMENT_WORDS.get(moment, moment.capitalize()))
	# Two more, not in the engine's list: a share of the enemy's health, and a moment a story raises.
	var below: String = FightActionSystem.BELOW_MOMENT
	list.add_item("When the enemy's health falls below…")
	list.add_item("At a moment a story raises…")
	var own_moment: bool = current.is_empty() and not value.is_empty() and not value.begins_with(below)
	list.select(moments.size() + 1 if value.begins_with(below) else moments.size() + 2 if own_moment else moments.find(current) + 1)
	list.disabled = not writable
	line.add_child(list)
	var share := SpinBox.new()
	share.min_value = 1
	share.max_value = 99
	share.suffix = "%"
	share.value = float(value.substr(below.length()).trim_suffix("%")) if value.begins_with(below) else 50.0
	share.visible = value.begins_with(below)
	share.editable = writable
	share.tooltip_text = "The hook plays once in a fight, when the enemy's health first falls below this share."
	share.value_changed.connect(func(number: float) -> void: _set_value("on", below + str(int(number)) + "%"))
	line.add_child(share)
	var raised := PickerButton.new()
	raised.placeholder = "Choose or name the moment…"
	raised.text = raised.placeholder
	raised.workspace = workspace
	raised.allow_typing = true
	raised.visible = own_moment
	raised.disabled = not writable
	raised.tooltip_text = "A story raises a moment with the action “Raise the moment…”. This hook then plays right there."
	raised.options = func() -> Array:
		var result: Array = []
		for word: String in workspace.known_words("moment"):
			if word not in moments: result.append({"value": word, "label": word.replace("_", " ")})
		return result
	if own_moment: raised.set_value(value)
	raised.picked.connect(func(name: String) -> void:
		if not name.strip_edges().is_empty(): _set_value("on", name.strip_edges().to_lower()))
	line.add_child(raised)
	var about := value.substr(current.length()) if current.ends_with(" ") else ""
	# Shared by the two controls: a lambda keeps its own copy of plain values.
	var state := {"moment": current, "kind": "item" if current in Game.HOOK_ITEM_MOMENTS else "character"}
	var target := PickerButton.new()
	target.placeholder = "Choose the " + str(state.kind) + "…"
	target.text = target.placeholder
	target.workspace = workspace
	target.drop_kinds = [state.kind]
	target.visible = current.ends_with(" ")
	target.disabled = not writable
	target.options = func() -> Array:
		var result: Array = []
		for other: Dictionary in workspace.rows:
			if other.def.type == state.kind and other.def.mode != "extend": result.append({"value": other.def.id, "label": Wording.title(other), "detail": "" if other.doc.writable else str(other.pack)})
		return result
	target.set_value(about)
	line.add_child(target)
	line.move_child(share, -1)
	line.move_child(raised, -1)
	list.item_selected.connect(func(index: int) -> void:
		share.visible = index == moments.size() + 1
		raised.visible = index == moments.size() + 2
		if index > moments.size():
			target.hide()
			if index == moments.size() + 1: _set_value("on", below + str(int(share.value)) + "%")
			else: raised.open()
			return
		var moment: String = moments[index - 1]
		if not moment.ends_with(" "): _set_value("on", moment)
		else:
			# A moment about one character or item is written once that is chosen.
			state.kind = "item" if moment in Game.HOOK_ITEM_MOMENTS else "character"
			state.moment = moment
			target.placeholder = "Choose the " + str(state.kind) + "…"
			target.drop_kinds = [state.kind]
			target.set_value("")
			target.show()
			target.open())
	target.picked.connect(func(id: String) -> void:
		if id.is_empty(): return
		if _set_value("on", str(state.moment) + id): workspace.require_content(str(state.kind), id))
	if value.is_empty(): _event_note("Choose when this hook runs.")

## "strength 12, dexterity 10" as {strength: 12, dexterity: 10}; empty when it is written another way.
static func _read_stats(value: String) -> Dictionary:
	var stats: Dictionary = {}
	for part: String in value.split(",", false):
		var words := part.strip_edges().split(" ", false)
		if words.size() != 2 or words[0] not in CombatSystem.ATTRIBUTES or not words[1].is_valid_int(): return {}
		stats[words[0]] = int(words[1])
	return stats

## The six attributes as number boxes.
func _add_stats_field(key: String, value: String) -> void:
	var stats := _read_stats(value)
	var grid := GridContainer.new()
	grid.columns = 6
	body.add_child(grid)
	var boxes: Dictionary = {}
	var save := func() -> void:
		var parts: Array[String] = []
		for name: String in CombatSystem.ATTRIBUTES: parts.append("%s %d" % [name, int(boxes[name].value)])
		_set_value(key, ", ".join(parts))
	for name: String in CombatSystem.ATTRIBUTES:
		var cell := VBoxContainer.new()
		grid.add_child(cell)
		var caption := AuthoringLayout.label(str(name).capitalize(), 12, true)
		caption.autowrap_mode = TextServer.AUTOWRAP_OFF
		cell.add_child(caption)
		var box := SpinBox.new()
		box.min_value = 0
		box.max_value = 999
		box.value = int(stats.get(name, 10))
		box.editable = row.doc.writable
		box.value_changed.connect(func(_number: float) -> void: save.call())
		boxes[name] = box
		cell.add_child(box)
	if value.is_empty(): _event_note("Not set yet: changing a number sets all six.")

## Fields that hold a condition: "when", "requires" and everything ending in "when".
static func is_condition_field(type: String, key: String) -> bool:
	return key == "when" or key.ends_with(" when") or key.ends_with(" while") or key.ends_with(" requires") or (key == "requires" and type != "event")

## Opens the condition builder for a field; what is built is written to it.
func _ask_condition(key: String, value: String, heading: String, may_be_empty: bool) -> void:
	if condition_editor == null:
		condition_editor = ConditionDialog.new()
		add_child(condition_editor)
		condition_editor.applied.connect(func(text: String) -> void:
			if text.is_empty(): _clear_item_field(condition_key)
			else:
				_set_value(condition_key, text)
				var current := _current_row()
				if not current.is_empty(): workspace.require_condition(Condition.compile(text)))
	condition_key = key
	condition_editor.open(workspace, value, StoryBlocks.contexts(row), row.def.id if row.def.type == "event" else "", heading, may_be_empty)

## A condition shown in words, changed with the condition builder.
func _add_condition_field(key: String, value: String) -> void:
	var writable: bool = row.doc.writable
	var line := HBoxContainer.new()
	body.add_child(line)
	var words := AuthoringLayout.label(BlockCatalog.condition_sentence(value, workspace) if not value.is_empty() else "Not set: no condition.", 15, value.is_empty())
	words.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	if not value.is_empty(): words.theme_type_variation = "AccentLabel"
	line.add_child(words)
	var change := Button.new()
	change.text = "Change…" if not value.is_empty() else "Set a condition…"
	change.disabled = not writable
	change.pressed.connect(func() -> void:
		_ask_condition(key, value, AuthoringCatalog.property(row.def.type, key, "text").title, true))
	line.add_child(change)
	if not value.is_empty():
		var clear := Button.new()
		clear.text = "Clear"
		clear.disabled = not writable
		clear.pressed.connect(func() -> void: _clear_item_field(key))
		line.add_child(clear)

## Named settings on indented lines (equipment, a weapon, a body part), each
## with its own control. Every change is saved at once, as one undo step.
func _add_sheet(key: String, entries: Array[Dictionary]) -> void:
	var sheet := SettingsSheet.new()
	sheet.configure(workspace, row.def.type, key, entries, row.doc.writable, StoryBlocks.contexts(row))
	sheet.edited.connect(func(text: String) -> void:
		if text.is_empty(): _clear_nested(key)
		else: _set_value(key, text, true))
	body.add_child(sheet)

## "item 70%": what a creature drops, and how often.
static func _read_loot(value: String) -> Array:
	var found := RegEx.create_from_string("^([a-z0-9_]+) (\\d{1,3})%$").search(value.strip_edges())
	return [found.get_string(1), int(found.get_string(2))] if found != null else []

func _add_loot_field(key: String, value: String) -> void:
	var loot := _read_loot(value)
	var line := HBoxContainer.new()
	line.add_theme_constant_override("separation", 8)
	body.add_child(line)
	var item := SlotControl.make(workspace, {"name": "item", "kind": "item", "optional": true}, loot[0] if not loot.is_empty() else "")
	line.add_child(item)
	line.add_child(AuthoringLayout.label("in", 14, true))
	var chance := SpinBox.new()
	chance.min_value = 1
	chance.max_value = 100
	chance.suffix = "% of wins"
	chance.set_value_no_signal(int(loot[1]) if not loot.is_empty() else 50)
	chance.editable = row.doc.writable and not loot.is_empty()
	chance.tooltip_text = "How often the creature drops it when the player wins."
	line.add_child(chance)
	if not row.doc.writable:
		for button: Node in item.find_children("*", "BaseButton", true, false): (button as BaseButton).disabled = true
		return
	item.edited.connect(func() -> void:
		if item.value().is_empty(): _clear_item_field(key)
		else: _set_value(key, "%s %d%%" % [item.value(), int(chance.value)]))
	chance.value_changed.connect(func(next: float) -> void:
		if not item.value().is_empty(): _set_value(key, "%s %d%%" % [item.value(), int(next)]))
	if not loot.is_empty():
		var clear := IconButton.new()
		clear.text = "×"
		clear.tooltip_text = "No loot"
		clear.pressed.connect(func() -> void: _clear_item_field(key))
		line.add_child(clear)

## A number box for a plain number; a calculation is written out and checked
## by the engine before it is kept.
func _add_formula_field(key: String, value: String) -> void:
	var writable: bool = row.doc.writable
	var line := HBoxContainer.new()
	line.add_theme_constant_override("separation", 8)
	body.add_child(line)
	var plain := value.is_empty() or value.is_valid_int()
	var number := SpinBox.new()
	number.min_value = -1000000
	number.max_value = 1000000
	number.set_value_no_signal(int(value))
	number.editable = writable
	number.visible = plain
	if value.is_empty(): number.modulate.a = 0.6
	number.value_changed.connect(func(next: float) -> void: _set_value(key, str(int(next))))
	line.add_child(number)
	var formula := LineEdit.new()
	formula.text = value
	formula.editable = writable
	formula.visible = not plain
	formula.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	formula.placeholder_text = "A calculation, such as player.level * 2"
	formula.tooltip_text = "A calculation with numbers, + - * / and values such as player.level."
	var keep := func() -> void:
		if not is_instance_valid(formula) or not formula.editable or not formula.visible: return
		var next := formula.text.strip_edges()
		if next.is_empty() or next == value: return
		var parsed: Dictionary = Expr.parse(next)
		if parsed.has("error"):
			problem.emit("That calculation cannot be read: %s" % parsed.error)
			formula.text = value
		else: _set_value(key, next)
	formula.text_submitted.connect(func(_text: String) -> void: keep.call())
	formula.focus_exited.connect(keep)
	line.add_child(formula)
	if value.is_empty(): line.add_child(AuthoringLayout.label("not set", 13, true))
	if writable and plain:
		var calculate := Button.new()
		calculate.text = "Calculate…"
		calculate.tooltip_text = "Write a calculation in place of a plain number."
		calculate.pressed.connect(func() -> void:
			number.hide()
			calculate.hide()
			formula.show()
			formula.grab_focus())
		line.add_child(calculate)

## "1 in 3": how many times out of how many.
## "24 to 48" as [24, 48], a single number as twice itself; empty when it is written another way.
static func _read_range(value: String) -> Array:
	var parts := value.split(" to ")
	if parts.size() == 1 and value.strip_edges().is_valid_int(): return [int(value), int(value)]
	if parts.size() != 2 or not parts[0].strip_edges().is_valid_int() or not parts[1].strip_edges().is_valid_int(): return []
	return [int(parts[0]), int(parts[1])]

## A span as two number boxes: somewhere from the first to the second.
func _add_range_field(key: String, value: String) -> void:
	var span := _read_range(value)
	var line := HBoxContainer.new()
	line.add_theme_constant_override("separation", 8)
	body.add_child(line)
	var boxes: Array[SpinBox] = []
	for index in 2:
		var words := Label.new()
		words.text = "From" if index == 0 else "to"
		line.add_child(words)
		var box := SpinBox.new()
		box.min_value = 0
		box.max_value = 1000000
		box.value = float(span[index]) if span.size() == 2 else 0.0
		box.editable = row.doc.writable
		box.custom_minimum_size.x = 96
		line.add_child(box)
		boxes.append(box)
	var keep := func(_number: float) -> void:
		var low := int(boxes[0].value)
		var high := maxi(low, int(boxes[1].value))
		_set_value(key, str(low) if low == high else "%d to %d" % [low, high])
	for box: SpinBox in boxes: box.value_changed.connect(keep)
	if value.is_empty(): line.add_child(AuthoringLayout.label("Not set: the game uses its own span.", 13, true))

static func _read_chance(value: String) -> Array:
	var found := RegEx.create_from_string("^(\\d+) in ([1-9]\\d*)$").search(value.strip_edges())
	return [int(found.get_string(1)), int(found.get_string(2))] if found != null else []

func _add_chance_field(key: String, value: String) -> void:
	var chance := _read_chance(value)
	var line := HBoxContainer.new()
	line.add_theme_constant_override("separation", 8)
	body.add_child(line)
	var times := SpinBox.new()
	var out_of := SpinBox.new()
	for box: SpinBox in [times, out_of]:
		box.max_value = 100000
		box.editable = row.doc.writable
		if chance.is_empty(): box.modulate.a = 0.6
	out_of.min_value = 1
	times.set_value_no_signal(chance[0] if not chance.is_empty() else 1)
	out_of.set_value_no_signal(chance[1] if not chance.is_empty() else 2)
	times.tooltip_text = "How many times…"
	out_of.tooltip_text = "…out of this many."
	var write := func(_next: float) -> void: _set_value(key, "%d in %d" % [int(times.value), int(out_of.value)])
	times.value_changed.connect(write)
	out_of.value_changed.connect(write)
	line.add_child(times)
	line.add_child(AuthoringLayout.label("in", 14, true))
	line.add_child(out_of)
	if chance.is_empty(): line.add_child(AuthoringLayout.label("not set", 13, true))
	elif row.doc.writable:
		var clear := IconButton.new()
		clear.text = "×"
		clear.tooltip_text = "Take this chance out"
		clear.pressed.connect(func() -> void: _clear_item_field(key))
		line.add_child(clear)

## What a shop is paid in: one of the player's numbers, or an item.
func _add_currency_field(key: String, value: String) -> void:
	var writable: bool = row.doc.writable
	var with_item := value.begins_with("item ")
	var line := HBoxContainer.new()
	line.add_theme_constant_override("separation", 8)
	body.add_child(line)
	var kind := OptionButton.new()
	for words: String in ["The game's own money" if row.def.type == "shop" else "No money", "A number the player has", "An item"]: kind.add_item(words)
	kind.select(2 if with_item else 1 if not value.is_empty() else 0)
	kind.disabled = not writable
	line.add_child(kind)
	if with_item:
		var item := SlotControl.make(workspace, {"name": "item", "kind": "item", "optional": false}, value.trim_prefix("item ").strip_edges())
		item.edited.connect(func() -> void:
			if not item.value().is_empty(): _set_value(key, "item " + item.value()))
		if not writable:
			for button: Node in item.find_children("*", "BaseButton", true, false): (button as BaseButton).disabled = true
		line.add_child(item)
	var number := LineEdit.new()
	number.text = value if not with_item else ""
	number.editable = writable
	number.visible = not with_item and not value.is_empty()
	number.custom_minimum_size.x = 200
	number.placeholder_text = "Its name, such as coins"
	number.tooltip_text = "The name of a number the player has, without “player.” in front."
	number.text_submitted.connect(func(next: String) -> void:
		if not next.strip_edges().is_empty(): _set_value(key, next.strip_edges()))
	number.focus_exited.connect(func() -> void:
		if is_instance_valid(number) and number.editable and not number.text.strip_edges().is_empty(): _set_value(key, number.text.strip_edges()))
	line.add_child(number)
	kind.item_selected.connect(func(index: int) -> void:
		if index == 0: _clear_item_field(key)
		elif index == 1:
			# Nothing is written until the number is named.
			number.show()
			number.grab_focus()
		elif not with_item:
			var items: Array = workspace.rows.filter(func(candidate: Dictionary) -> bool: return candidate.def.type == "item" and candidate.def.mode != "extend")
			if items.is_empty(): problem.emit("Make an item first: there is none to pay with yet.")
			else: _set_value(key, "item " + str(items[0].def.id)))

## A door: open, locked, or locked while a condition holds.
func _add_lock_field(key: String, value: String) -> void:
	var writable: bool = row.doc.writable
	var line := HBoxContainer.new()
	line.add_theme_constant_override("separation", 8)
	body.add_child(line)
	var state := OptionButton.new()
	for words: String in ["Not locked", "Locked", "Locked while…"]: state.add_item(words)
	var conditional: bool = value not in ["", "yes", "no"]
	state.select(2 if conditional else 1 if value == "yes" else 0)
	state.disabled = not writable
	line.add_child(state)
	var ask := func() -> void:
		_ask_condition(key, value if conditional else "", "Locked while…", false)
	state.item_selected.connect(func(index: int) -> void:
		if index == 2: ask.call()
		elif index == 1: _set_value(key, "yes")
		elif value == "no" or value.is_empty(): return
		else: _set_value(key, "no"))
	if conditional:
		var words := AuthoringLayout.label(BlockCatalog.condition_sentence(value, workspace), 14)
		words.theme_type_variation = "AccentLabel"
		words.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		line.add_child(words)
		var change := Button.new()
		change.text = "Change…"
		change.disabled = not writable
		change.pressed.connect(ask)
		line.add_child(change)

## Several fields of named settings under each other, each with a heading.
func _add_sheets(fields: Array) -> void:
	var schema: Dictionary = ContentDB.SCHEMA.get(row.def.type, {})
	for entry: Array in fields:
		if not schema.has(entry[0]): continue
		body.add_child(HSeparator.new())
		body.add_child(AuthoringLayout.label(entry[1], 18))
		if not str(entry[2]).is_empty(): _event_note(entry[2])
		var from := body.get_child_count()
		_add_field(entry[0], "fields")
		# The heading above says what it is: the field's own small caption is not needed.
		if body.get_child_count() > from and body.get_child(from) is Label: body.get_child(from).hide()

## Takes out a field together with its indented lines.
func _clear_nested(key: String) -> void:
	var current := _current_row()
	if current.is_empty() or not current.doc.writable: return
	var field: FscParser.Field = current.def.fields.get(key)
	if field == null: return
	var doc: PackDocument = current.doc
	var offsets := doc.offsets()
	var last: int = field.line
	for child: FscParser.Line in field.children:
		if not child.is_blank(): last = child.number
	var begin: int = offsets[field.line - 1]
	var end: int = offsets[last] if last < offsets.size() else doc.text.length()
	doc.change(doc.text.left(begin) + doc.text.substr(end))
	workspace.reindex()
	changed.emit(_current_row())

## A list of short words as chips, with suggestions from the loaded packs.
func _add_chip_field(key: String, value: String) -> void:
	var writable: bool = row.doc.writable
	var entries: Array[String] = []
	for part: String in value.split(",", false):
		if not part.strip_edges().is_empty(): entries.append(part.strip_edges())
	var flow := HFlowContainer.new()
	body.add_child(flow)
	for entry: String in entries:
		var chip := Button.new()
		chip.theme_type_variation = "Chip"
		chip.text = entry.replace("_", " ") + "  ✕"
		chip.tooltip_text = "Remove “" + entry + "”"
		chip.disabled = not writable
		chip.pressed.connect(func() -> void:
			var rest := entries.filter(func(other: String) -> bool: return other != entry)
			if rest.is_empty(): _clear_item_field(key)
			else: _set_value(key, ", ".join(rest)))
		flow.add_child(chip)
	var add := PickerButton.new()
	add.placeholder = "+ Add…"
	add.text = add.placeholder
	add.theme_type_variation = "AddRow"
	add.allow_typing = true
	add.disabled = not writable
	var source: String = CHIP_FIELDS[key]
	add.options = func() -> Array:
		var result: Array = []
		if source.is_empty(): return result
		for word: String in workspace.known_words(source):
			if word not in entries: result.append({"value": word, "label": word.replace("_", " ")})
		return result
	add.picked.connect(func(word: String) -> void:
		var clean := word.strip_edges().to_lower().replace(" ", "_") if key in ["outcomes", "tags", "gift tags"] else word.strip_edges().to_lower()
		if clean.is_empty() or clean in entries or "," in clean: return
		_set_value(key, ", ".join(entries + [clean])))
	flow.add_child(add)

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
	_assign_reference(picker_field, candidate, row.doc.text)

func _assign_reference(key: String, candidate: Dictionary, expected: String) -> void:
	if pending_rows:
		problem.emit("Apply or discard your edited entries first.")
		return
	var current := _current_row()
	if current.is_empty() or current.doc.text != expected:
		problem.emit("This content changed. Choose its reference again.")
		return
	var value: String = candidate.def.id
	var kind: String = ContentDB.SCHEMA.get(current.def.type, {}).get(key, "")
	if kind == "list":
		var previous: String = current.doc.field_value(current.def, key)
		if "\n" in previous:
			problem.emit("This reference list has nested source which is kept.")
			return
		var ids: Array[String] = []
		for id: String in previous.split(",", false): ids.append(id.strip_edges())
		if value not in ids: ids.append(value)
		value = ", ".join(ids)
	var error := workspace.transaction("Choose " + key + " for " + Wording.title(current), func() -> String:
		var issue: String = current.doc.set_field(current.def, key, value)
		if not issue.is_empty(): return issue
		if current.def.type == "item" and key == "infectious" and not current.def.fields.has("use") and not current.def.fields.has("use action"):
			workspace.reindex()
			var fresh := workspace.find_row(current.doc.path, current.def.type, current.def.id, current.def.mode)
			issue = fresh.doc.set_field(fresh.def, "use", "", true)
			if not issue.is_empty(): return issue
		if candidate.root != workspace.target: return workspace.add_requirement(candidate.pack)
		return "")
	if not error.is_empty():
		problem.emit(error)
		return
	changed.emit(workspace.find_row(current.doc.path, current.def.type, current.def.id, current.def.mode, current.get("ordinal", 0)))

func _mark_rows(section: String) -> void:
	pending_sections[section] = true
	pending_rows = true
