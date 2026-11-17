class_name SettingsSheet
extends VBoxContainer
## A field that holds named settings on indented lines (equipment:, weapon:,
## a body part of a form, a character's body:), shown as one control for each
## setting. A setting is written only when it is set; lines the sheet does not
## know stay as they are, in their place.

signal edited(text: String)

const SIZES := "Size 3 is a human's. 0 fits anyone."
const PART_TEXT := [
	["description", "Looks like", "text", "What the part looks like. The game puts these words into its sentence about the player's body."],
	["change", "When it changes", "text", "Told when the player's part turns into this form."]]
const PART_WORDS := [
	["color", "Colour", "word", "A colour stories can name."],
	["covering", "Covering", "word", "Fur, scales, latex, skin…"],
	["adjective", "Adjective", "word", "One word for the part."]]
const SHEETS := {
	# One variant of a creature (see VariantSheets).
	"creature/variant": [
		["gender", "Gender", "choice", "What this shape counts as for the player's content settings.", Validator.CREATURE_GENDERS],
		["filters", "Content filters", "text", "Filters, with commas between: a player who has banned one never meets this shape."],
		["when", "Only when", "condition", "This shape is met only while this is true."],
		["chance", "Weight", "number", "How often this shape is picked compared with the others. 1 when not set."],
		["title", "Called", "text", "The name shown for this shape, when it differs."],
		["image", "Picture", "text", "The picture of this shape (a picture's ID)."],
		["infection sex", "Infects toward", "choice", "The sex its infection pushes the player toward.", ["male", "female", "herm", "neuter"]],
		["level", "Level", "number", ""],
		["hp", "Health", "number", ""],
		["damage", "Damage", "number", ""],
		["libido", "Libido", "number", ""],
		["hit bonus", "Hit bonus", "number", ""],
		["dodge bonus", "Dodge bonus", "number", ""],
		["mind bonus", "Mind bonus", "number", ""],
		["stats", "Attributes", "text", "Such as: strength 12, dexterity 10."],
		["loot", "Drops", "text", "An item and how often, such as: wolf_fur 40%."],
		["special", "Special rule", "text", "A special rule of the fight, as the creature's own."],
		["seduction immune", "Cannot be seduced", "switch", ""],
	],
	"item/equipment": [
		["slot", "Worn on", "choice", "Where it is worn. One thing fits each place; “none” takes no place.", ItemSystem.SLOTS, "", true],
		["placement", "Described with", "choice", "Where its worn text goes in the player's description. Head, body and shield also decide where the armour protects.", ItemSystem.PLACEMENTS, "end"],
		["worn text", "Worn text", "text", "The sentence about it in the player's description while it is worn."],
		["armor", "Armour", "number", "How much of a blow it can take."],
		["effectiveness", "Effectiveness (%)", "number", "How well the armour takes a blow, in percent."],
		["size", "Size", "number", "Compared with the player's size: one off fits loosely, two do not fit. " + SIZES, [], "3"],
		["plural", "A pair", "switch", "For pairs such as boots or pants, so texts say “them”."],
		["cursed", "Cursed", "switch", "Cannot be taken off."],
		["taur compatible", "Fits four-legged bodies", "switch", "Feet, legs and waist gear does not fit a taur body unless this is on."],
		["gender look", "Gender look", "number", "Below zero looks feminine, above zero masculine. Everything worn adds up."],
		["style", "Styles", "words", "The styles it counts for. Everything worn adds up.", ItemSystem.STYLES],
		["dodge bonus", "Dodge bonus", "number", "Added in fights."],
		["damage bonus", "Damage bonus", "number", "Added in fights."],
		["flee bonus", "Flee bonus", "number", "Added in fights."],
		["carry bonus", "Carry bonus", "number", "Pounds more the player can carry."]],
	"item/weapon": [
		["damage", "Damage", "number", "The damage of a blow.", [], "", true],
		["type", "Kind", "choice", "Melee adds strength to damage; ranged adds perception.", ["melee", "ranged"], "melee"],
		["size", "Size", "number", "Compared with the player's size: one off costs 2 to hit, two cost 5, three cannot be wielded. " + SIZES, [], "3"],
		["hit bonus", "Hit bonus", "number", "Added to the chance to hit."],
		["attack text", "Attack text", "text", "Names the weapon in attack messages."]],
	"character/companion": [
		["attacks with", "Attacks with", "choice", "Fighting hurts the enemy; seduction raises its lust.", ["fighting", "seduction"], "fighting"],
		["hit bonus", "Hit bonus", "number", "Added to its chance to hit."],
		["tamed", "Can be called from the start", "switch", "Otherwise a story has to tame it first."],
		["stays when", "Stays only if", "condition", "Leaves the player when this stops being true."]],
	"form/cock": [["count", "How many", "number", ""], ["length", "Length", "number", "In inches."], ["girth", "Girth", "number", ""]],
	"form/cunt": [["count", "How many", "number", ""], ["depth", "Depth", "number", "In inches."], ["tightness", "Tightness", "number", ""]],
	"form/breasts": [["size", "Size", "number", "What a body with breasts grows toward."], ["nipples", "Nipples", "number", "How many."], ["male size", "Size on a male body", "number", ""]],
	"form/balls": [["size", "Size", "number", ""], ["count", "How many", "number", ""]],
}
## Sheets that take any other name too (a stat is any word a game uses).
const OPEN := ["character/stats"]

var workspace: PackWorkspace
var writable := true
var context: Array = []
var _entries: Array[Dictionary] = []
var _values: Dictionary = {}
var _known: Array[Dictionary] = []
var _open := false
var _conditions: ConditionDialog
var _condition_name := ""

static func _row(source: Array) -> Dictionary:
	return {"name": source[0], "title": source[1], "kind": source[2], "help": source[3], "options": source[4] if source.size() > 4 else [], "default": source[5] if source.size() > 5 else "", "required": source.size() > 6 and source[6]}

## The settings a field of this type holds; empty when there is no sheet for it.
static func rows(type: String, key: String) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var name := type + "/" + key
	if SHEETS.has(name):
		for source: Array in SHEETS[name]: out.append(_row(source))
		if type == "form" and key in ["cock", "cunt"]:
			for source: Array in PART_TEXT: out.append(_row(source))
	elif type == "form" and key in BodySystem.PARTS:
		for source: Array in PART_TEXT + PART_WORDS: out.append(_row(source))
	elif name == "character/body":
		for setting: String in CharacterSystem.BODY:
			var kind: String = {"number": "number", "flag": "switch", "text": "form"}[CharacterSystem.BODY[setting][1]]
			out.append(_row([setting, setting.capitalize(), kind, "The body form the character has." if kind == "form" else ""]))
	elif name == "character/stats":
		for setting: String in CharacterSystem.STATS:
			out.append(_row([setting, setting.capitalize(), "number", "Fighting health; a character's story stage is a value of its own." if setting == "max hp" else ""]))
	elif name == "character/relationship":
		for setting: String in CharacterSystem.RELATIONSHIP:
			out.append(_row([setting, setting.capitalize(), "switch", "How the character starts out. Stories change it as they go.", [], "yes" if CharacterSystem.RELATIONSHIP[setting][1] else "no"]))
	return out

static func has_sheet(type: String, key: String) -> bool:
	return not rows(type, key).is_empty()

## The "name: value" lines of a field; empty with `ok` false when a line is
## something else (a note, a deeper level), which the sheet does not touch.
static func read(doc: PackDocument, field: FscParser.Field) -> Dictionary:
	var entries: Array[Dictionary] = []
	if field == null: return {"ok": true, "entries": entries}
	if not field.value.is_empty(): return {"ok": false, "entries": entries}
	var lines := doc.text.split("\n")
	if not field.children.is_empty():
		for index in range(field.line, field.children[-1].number):
			if index < lines.size() and lines[index].strip_edges().begins_with("//"): return {"ok": false, "entries": entries}
	for child: FscParser.Line in field.children:
		if child.is_blank(): continue
		var separator := child.text.find(":")
		if child.indent != 4 or separator < 1: return {"ok": false, "entries": entries}
		entries.append({"name": child.text.left(separator).strip_edges(), "value": child.text.substr(separator + 1).strip_edges()})
	return {"ok": true, "entries": entries}

func configure(pack: PackWorkspace, type: String, key: String, entries: Array[Dictionary], can_write: bool, where: Array = []) -> void:
	workspace = pack
	writable = can_write
	context = where
	_entries = entries
	_known = rows(type, key)
	_open = (type + "/" + key) in OPEN
	_values.clear()
	for entry: Dictionary in entries: _values[entry.name] = entry.value
	_build()

## The field's lines as they stand: lines that were there keep their place,
## new ones follow in the sheet's order, and emptied ones are left out.
func text() -> String:
	var lines: Array[String] = []
	var written := {}
	for entry: Dictionary in _entries:
		written[entry.name] = true
		if _values.has(entry.name): lines.append("%s: %s" % [entry.name, _values[entry.name]])
	for setting: Dictionary in _known:
		if not written.has(setting.name) and _values.has(setting.name):
			written[setting.name] = true
			lines.append("%s: %s" % [setting.name, _values[setting.name]])
	for name: String in _values:
		if not written.has(name): lines.append("%s: %s" % [name, _values[name]])
	return "\n".join(lines)

func value(name: String) -> String:
	return str(_values.get(name, ""))

## Sets one setting (empty takes it out) and reports the field's new lines.
func set_setting(name: String, next: String) -> void:
	next = next.replace("\r", " ").replace("\n", " ").strip_edges()
	if next == value(name) and (_values.has(name) or next.is_empty()): return
	if next.is_empty(): _values.erase(name)
	else: _values[name] = next
	edited.emit(text())

func _build() -> void:
	for child: Node in get_children(): child.queue_free()
	add_theme_constant_override("separation", 6)
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 12)
	grid.add_theme_constant_override("v_separation", 6)
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	add_child(grid)
	var shown := {}
	for setting: Dictionary in _known:
		shown[setting.name] = true
		_add_setting(grid, setting)
	# What the file holds beyond the sheet: kept, and changeable as it is written.
	for entry: Dictionary in _entries:
		if shown.has(entry.name): continue
		shown[entry.name] = true
		_add_setting(grid, {"name": entry.name, "title": str(entry.name).capitalize(), "kind": "number" if _open and str(entry.value).is_valid_int() else "word", "help": "", "options": [], "default": "", "required": false, "extra": true})
	if _open and writable:
		var line := HBoxContainer.new()
		var name_input := LineEdit.new()
		name_input.placeholder_text = "Another number, such as loyalty"
		name_input.custom_minimum_size.x = 240
		line.add_child(name_input)
		var add := Button.new()
		add.text = "+ Add"
		var submit := func() -> void:
			var name := name_input.text.strip_edges().to_lower()
			if name.is_empty() or RegEx.create_from_string("^[a-z][a-z ]*$").search(name) == null or _values.has(name):
				name_input.placeholder_text = "A new name in lowercase words"
				name_input.text = ""
				return
			set_setting(name, "0")
		add.pressed.connect(submit)
		name_input.text_submitted.connect(func(_text: String) -> void: submit.call())
		line.add_child(add)
		add_child(line)

func _add_setting(grid: GridContainer, setting: Dictionary) -> void:
	var name: String = setting.name
	var is_set: bool = _values.has(name)
	var current: String = value(name) if is_set else str(setting.default)
	var caption := Label.new()
	caption.text = setting.title
	caption.tooltip_text = setting.help
	caption.mouse_filter = Control.MOUSE_FILTER_PASS
	caption.add_theme_font_size_override("font_size", 14)
	caption.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	if not is_set and not setting.required: caption.theme_type_variation = "MutedLabel"
	grid.add_child(caption)
	var line := HBoxContainer.new()
	line.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	line.set_meta("setting", name)
	grid.add_child(line)
	var kind: String = setting.kind
	if kind == "number" and (current.is_empty() or current.is_valid_int()):
		var number := SpinBox.new()
		number.min_value = -1000000
		number.max_value = 1000000
		number.step = 1
		number.set_value_no_signal(int(current))
		number.editable = writable
		number.tooltip_text = setting.help
		if not is_set: number.modulate.a = 0.6
		number.value_changed.connect(func(next: float) -> void: set_setting(name, str(int(next))))
		line.add_child(number)
	elif kind == "switch" and current in ["", "yes", "no"]:
		var toggle := CheckButton.new()
		toggle.set_pressed_no_signal(current == "yes")
		toggle.text = "Yes" if current == "yes" else "No"
		toggle.disabled = not writable
		toggle.tooltip_text = setting.help
		if not is_set: toggle.modulate.a = 0.6
		toggle.toggled.connect(func(on: bool) -> void: set_setting(name, "yes" if on else "no"))
		line.add_child(toggle)
	elif kind == "choice" and (current.is_empty() or current in setting.options):
		var choice := OptionButton.new()
		var options: Array = setting.options
		if current.is_empty():
			choice.add_item("Choose…")
			choice.set_item_disabled(0, true)
		for option: String in options: choice.add_item(option.capitalize())
		choice.select(options.find(current) if not current.is_empty() else 0)
		choice.disabled = not writable
		choice.tooltip_text = setting.help
		if not is_set and not current.is_empty(): choice.modulate.a = 0.6
		var offset := 1 if current.is_empty() else 0
		choice.item_selected.connect(func(index: int) -> void:
			if index >= offset: set_setting(name, options[index - offset]))
		line.add_child(choice)
	elif kind == "words":
		_add_words(line, setting, current)
	elif kind == "form":
		var picker := SlotControl.make(workspace, {"name": name, "kind": "form", "types": ["form"], "optional": true}, current)
		picker.edited.connect(func() -> void: set_setting(name, picker.value()))
		_disable(picker, not writable)
		line.add_child(picker)
	elif kind == "condition" and (current.is_empty() or not Condition.compile(current).has("error")):
		var words := AuthoringLayout.label(BlockCatalog.condition_sentence(current, workspace) if not current.is_empty() else "Not set", 14, current.is_empty())
		words.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		line.add_child(words)
		var change := Button.new()
		change.text = "Change…" if not current.is_empty() else "Set…"
		change.disabled = not writable
		change.pressed.connect(func() -> void:
			if _conditions == null:
				_conditions = ConditionDialog.new()
				add_child(_conditions)
				_conditions.applied.connect(func(condition: String) -> void:
					if not condition.is_empty(): workspace.require_condition(Condition.compile(condition))
					set_setting(_condition_name, condition))
			_condition_name = name
			_conditions.open(workspace, current, context, "", setting.title, true))
		line.add_child(change)
	elif kind == "text":
		var input := TextEdit.new()
		input.text = current
		input.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
		input.scroll_fit_content_height = true
		input.custom_minimum_size = Vector2(260, 34)
		input.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		input.editable = writable
		input.tooltip_text = setting.help
		input.placeholder_text = "Not set"
		input.focus_exited.connect(func() -> void:
			if is_instance_valid(input) and input.editable: set_setting(name, input.text))
		line.add_child(input)
	else:
		var input := LineEdit.new()
		input.text = current
		input.editable = writable
		input.tooltip_text = setting.help
		input.placeholder_text = "Not set"
		input.custom_minimum_size.x = 200
		input.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		input.text_submitted.connect(func(next: String) -> void: set_setting(name, next))
		input.focus_exited.connect(func() -> void:
			if is_instance_valid(input) and input.editable: set_setting(name, input.text))
		line.add_child(input)
	if is_set and writable and not setting.required:
		var reset := IconButton.new()
		reset.text = "×"
		reset.tooltip_text = "Take this setting out" + (" (the game then uses %s)" % setting.default if not str(setting.default).is_empty() else "")
		reset.pressed.connect(func() -> void: set_setting(name, ""))
		line.add_child(reset)

func _add_words(line: HBoxContainer, setting: Dictionary, current: String) -> void:
	var chosen: Array[String] = []
	for word: String in current.split(",", false):
		if not word.strip_edges().is_empty(): chosen.append(word.strip_edges())
	var name: String = setting.name
	var button := MenuButton.new()
	button.flat = false
	button.text = ", ".join(chosen) if not chosen.is_empty() else "None"
	button.disabled = not writable
	button.tooltip_text = setting.help
	var menu := button.get_popup()
	menu.hide_on_checkable_item_selection = false
	var options: Array = setting.options.duplicate()
	for word: String in chosen:
		if word not in options: options.append(word)
	for option: String in options:
		menu.add_check_item(option.capitalize())
		menu.set_item_checked(menu.item_count - 1, option in chosen)
	menu.index_pressed.connect(func(index: int) -> void: menu.set_item_checked(index, not menu.is_item_checked(index)))
	menu.popup_hide.connect(func() -> void:
		var next: Array[String] = []
		for index in menu.item_count:
			if menu.is_item_checked(index): next.append(options[index])
		set_setting(name, ", ".join(next)))
	line.add_child(button)

func _disable(control: Control, off: bool) -> void:
	if not off: return
	for button: Node in control.find_children("*", "BaseButton", true, false): (button as BaseButton).disabled = true
