class_name BlockChooser
extends ConfirmationDialog
## "What should happen?" and "When?": search the block catalog with everyday
## words, fill in the sentence, and add it. Nothing changes until Add.

signal chosen(line: String, keep_open: bool)
const COMMON := {
	"action": ["change.add", "set.yes", "give", "quest", "go", "survival.heal", "outcome", "resolve"],
	"condition": ["cmp", "truthy", "has_item", "quest", "is.sex", "chance", "since", "feat"],
}
var workspace: PackWorkspace
var kind := "action"
var context: Array = []
var event := ""
var search: LineEdit
var groups: ItemList
var results: ItemList
var show_all: CheckBox
var suggested: HFlowContainer
var form: VBoxContainer
var preview: Label
var line_label: Label
var error: Label
var quiet: CheckBox
var next_button: Button
var listed: Array[Dictionary] = []
var selected: Dictionary = {}
var controls: Dictionary = {}
var suggestions: Array = []
var typed := ""

func _ready() -> void:
	dialog_hide_on_ok = false
	var body := VBoxContainer.new()
	body.custom_minimum_size = Vector2(740, 480)
	add_child(body)
	search = LineEdit.new()
	search.clear_button_enabled = true
	search.text_changed.connect(func(_text: String) -> void: _list())
	search.gui_input.connect(func(input: InputEvent) -> void:
		if input.is_action_pressed("ui_down") and results.item_count > 0:
			results.grab_focus()
			if results.get_selected_items().is_empty(): _select_row(0))
	search.text_submitted.connect(func(_text: String) -> void:
		if selected.is_empty() and typed.is_empty() and results.item_count > 0: _select_row(0)
		else: _apply(false))
	body.add_child(search)
	suggested = HFlowContainer.new()
	body.add_child(suggested)
	var split := HBoxContainer.new()
	split.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_child(split)
	groups = ItemList.new()
	groups.custom_minimum_size = Vector2(170, 130)
	groups.item_selected.connect(func(_index: int) -> void: _list())
	split.add_child(groups)
	var right := VBoxContainer.new()
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	split.add_child(right)
	results = ItemList.new()
	results.size_flags_vertical = Control.SIZE_EXPAND_FILL
	results.custom_minimum_size.y = 130
	results.item_selected.connect(_select_row)
	results.item_activated.connect(func(index: int) -> void:
		_select_row(index)
		if selected.is_empty() or selected.slots.all(func(slot: Dictionary) -> bool: return slot.hidden or slot.optional): _apply(false))
	right.add_child(results)
	show_all = CheckBox.new()
	show_all.text = "Show all, also what does not work in this story"
	show_all.toggled.connect(func(_on: bool) -> void: _list())
	right.add_child(show_all)
	var panel := PanelContainer.new()
	panel.theme_type_variation = "Card"
	body.add_child(panel)
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.custom_minimum_size.y = 150
	panel.add_child(scroll)
	form = VBoxContainer.new()
	form.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(form)
	preview = AuthoringLayout.label("", 15)
	body.add_child(preview)
	line_label = AuthoringLayout.label("", 12)
	line_label.theme_type_variation = "CodeLabel"
	body.add_child(line_label)
	error = AuthoringLayout.label("", 14)
	error.theme_type_variation = "ErrorLabel"
	body.add_child(error)
	next_button = add_button("Add & next", true, "next")
	custom_action.connect(func(action: StringName) -> void:
		if action == "next": _apply(true))
	confirmed.connect(_apply.bind(false))
	get_ok_button().theme_type_variation = "PrimaryButton"

## `current` = {entry, slots, quiet} changes an existing block instead of adding one.
func open(pack: PackWorkspace, what: String = "action", where: Array = [], dropped: Array = [], current: Dictionary = {}, about_event: String = "") -> void:
	workspace = pack
	kind = what
	context = where
	event = about_event
	suggestions = dropped
	title = ("What should happen?" if kind == "action" else "When should this be true?") if current.is_empty() else "Change this block"
	ok_button_text = "Add" if current.is_empty() else "Apply"
	next_button.visible = current.is_empty() and kind == "action"
	search.placeholder_text = "Search with everyday words: heal, trust, teleport…" if kind == "action" else "Search with everyday words: trust, carries, quest, chance…"
	search.text = ""
	show_all.button_pressed = false
	error.text = ""
	groups.clear()
	groups.add_item("Everything")
	for category: String in BlockCatalog.categories(kind): groups.add_item(str(BlockCatalog.CATEGORY_ICONS.get(category, "◇")) + " " + category)
	groups.select(0)
	_suggest()
	_list()
	_show_form(current.get("entry", {}), current.get("slots", {}), current.get("quiet", false))
	AuthoringLayout.popup(self, Vector2i(800, 640))
	search.grab_focus()

func _suggest() -> void:
	AuthoringLayout.clear(suggested)
	var offered: Array = suggestions.duplicate()
	var seen: Dictionary = {}
	for id: String in EditorPrefs.read("recent_blocks", kind, []) + COMMON[kind]:
		var candidate := BlockCatalog.by_id(id, kind)
		if candidate.is_empty() or seen.has(id) or not BlockCatalog.applies(candidate, context): continue
		seen[id] = true
		offered.append({"entry": candidate, "slots": {}})
		if offered.size() >= suggestions.size() + 6: break
	if offered.is_empty(): return
	var caption := AuthoringLayout.label("Suggested here:", 13, true)
	caption.autowrap_mode = TextServer.AUTOWRAP_OFF
	suggested.add_child(caption)
	for offer: Dictionary in offered:
		var button := Button.new()
		button.theme_type_variation = "Chip"
		var filled: Dictionary = offer.get("slots", {})
		button.text = str(offer.entry.icon) + " " + (BlockCatalog.describe(offer.entry, _starting(offer.entry, filled), workspace) if not filled.is_empty() else BlockCatalog.plain(offer.entry))
		button.pressed.connect(func() -> void: _show_form(offer.entry, filled, false))
		suggested.add_child(button)

func _list() -> void:
	results.clear()
	listed.clear()
	typed = ""
	var query := search.text.strip_edges()
	if not query.is_empty():
		var readable: bool = not BlockCatalog.read_line(query.trim_prefix("~").strip_edges()).is_empty() if kind == "action" else (not Condition.compile(query).has("error") and BlockCatalog.condition_tree(query).op != "kept" and (" " in query or "." in query))
		if readable:
			typed = query.trim_prefix("~").strip_edges() if kind == "action" else query
			listed.append({})
			results.add_item("⌨  Add as typed: " + (BlockCatalog.sentence(typed, workspace) if kind == "action" else BlockCatalog.condition_sentence(typed, workspace)))
	var category := ""
	if not groups.get_selected_items().is_empty() and groups.get_selected_items()[0] > 0:
		category = BlockCatalog.categories(kind)[groups.get_selected_items()[0] - 1]
	for candidate: Dictionary in BlockCatalog.entries(query if typed.is_empty() else "", kind):
		if not category.is_empty() and candidate.category != category: continue
		var fits := BlockCatalog.applies(candidate, context)
		if not fits and not show_all.button_pressed: continue
		listed.append(candidate)
		results.add_item(str(candidate.icon) + "  " + BlockCatalog.plain(candidate))
		var at := results.item_count - 1
		results.set_item_tooltip(at, str(candidate.help) if fits else str(BlockCatalog.CONTEXT_REASONS.get(candidate.context, "")))
		if not fits:
			results.set_item_disabled(at, true)
			results.set_item_text(at, results.get_item_text(at) + "   ·   " + str(BlockCatalog.CONTEXT_REASONS.get(candidate.context, "")))
	if not typed.is_empty():
		results.select(0)
		_show_form({}, {}, false)

func _select_row(index: int) -> void:
	if index < 0 or index >= listed.size(): return
	results.select(index)
	_show_form(listed[index], {}, false)

## Slot values to start from: given ones, then the last amounts used, then defaults.
func _starting(candidate: Dictionary, given: Dictionary) -> Dictionary:
	var values: Dictionary = {}
	var remembered: Dictionary = EditorPrefs.read("block_values", str(candidate.id), {})
	for slot: Dictionary in candidate.slots:
		if given.has(slot.name): values[slot.name] = given[slot.name]
		elif remembered.has(slot.name) and slot.kind in ["int", "amount"] and not slot.optional: values[slot.name] = remembered[slot.name]
		elif not slot.optional or slot.hidden: values[slot.name] = slot.default
	return values

func _show_form(candidate: Dictionary, given: Dictionary, is_quiet: bool) -> void:
	selected = candidate
	controls.clear()
	AuthoringLayout.clear(form)
	quiet = null
	if candidate.is_empty():
		form.add_child(AuthoringLayout.label("Choose from the list above." if typed.is_empty() else "Your typed line is ready to add.", 15, true))
		_refresh_preview()
		return
	form.add_child(AuthoringLayout.label(str(candidate.icon) + "  " + BlockCatalog.plain(candidate), 17))
	if not str(candidate.help).is_empty(): form.add_child(AuthoringLayout.label(str(candidate.help), 13, true))
	var values := _starting(candidate, given)
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 12)
	form.add_child(grid)
	for slot: Dictionary in candidate.slots:
		if slot.hidden:
			controls[slot.name] = str(values.get(slot.name, slot.default))
			continue
		var caption := AuthoringLayout.label(BlockCatalog.slot_title(slot).capitalize() + (" (optional)" if slot.optional and slot.kind != "switch" else ""), 14, true)
		caption.autowrap_mode = TextServer.AUTOWRAP_OFF
		grid.add_child(caption)
		var control := SlotControl.make(workspace, slot, str(values.get(slot.name, "")), _peer)
		control.edited.connect(_refresh_preview)
		controls[slot.name] = control
		grid.add_child(control)
	if kind == "action":
		quiet = CheckBox.new()
		quiet.text = "Do it without telling the player"
		quiet.tooltip_text = "The game normally shows a short note such as “+1 trust”. Tick this to stay silent."
		quiet.button_pressed = is_quiet
		quiet.toggled.connect(func(_on: bool) -> void: _refresh_preview())
		form.add_child(quiet)
	_refresh_preview()

func _peer(name: String) -> String:
	if name == "@event": return event
	var control: Variant = controls.get(name, "")
	return control.value() if control is SlotControl else str(control)

func values() -> Dictionary:
	var result: Dictionary = {}
	for name: String in controls: result[name] = _peer(name)
	return result

func line() -> String:
	if selected.is_empty(): return typed
	return BlockCatalog.action_line(selected, values(), quiet != null and quiet.button_pressed) if kind == "action" else BlockCatalog.render(selected, values())

func _refresh_preview() -> void:
	error.text = ""
	var text := line()
	preview.text = ""
	line_label.text = ""
	if text.is_empty(): return
	if not selected.is_empty():
		for slot: Dictionary in selected.slots:
			if not slot.hidden and not slot.optional and _peer(slot.name).is_empty():
				preview.text = "Still to fill in:  " + BlockCatalog.slot_title(slot)
				return
	preview.text = "Preview:  " + (BlockCatalog.sentence(text, workspace) if kind == "action" else BlockCatalog.condition_sentence(text, workspace))
	if EditorPrefs.read("authoring", "show_line", false): line_label.text = ("~ " if kind == "action" else "if ") + text

func _problem() -> String:
	if selected.is_empty(): return "" if not typed.is_empty() else "Choose what should happen first." if kind == "action" else "Choose a condition first."
	for slot: Dictionary in selected.slots:
		if slot.hidden or slot.optional: continue
		if _peer(slot.name).is_empty(): return "Fill in: " + BlockCatalog.slot_title(slot) + "."
	var compiled := Effect.compile(line()) if kind == "action" else Condition.compile(line())
	if compiled.has("error"): return "The engine cannot read this yet: " + str(compiled.error)
	return ""

func _apply(keep_open: bool) -> void:
	var problem := _problem()
	if not problem.is_empty():
		error.text = problem
		return
	var text := line()
	if not selected.is_empty():
		var recent: Array = EditorPrefs.read("recent_blocks", kind, [])
		recent.erase(selected.id)
		recent.push_front(selected.id)
		EditorPrefs.write("recent_blocks", kind, recent.slice(0, 8))
		var amounts: Dictionary = {}
		for slot: Dictionary in selected.slots:
			if slot.kind in ["int", "amount"] and not slot.optional: amounts[slot.name] = _peer(slot.name)
		if not amounts.is_empty(): EditorPrefs.write("block_values", str(selected.id), amounts)
	if not keep_open: hide()
	chosen.emit(text, keep_open)
	if keep_open:
		search.text = ""
		_suggest()
		_list()
		_show_form({}, {}, false)
		search.grab_focus()
