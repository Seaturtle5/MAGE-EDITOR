class_name AuthoringLayout
extends VBoxContainer
## A section bar, focused page and persistent overview, as on MAGE's New Game screen.

signal section_requested(key: String)

var navigation: HFlowContainer
var page: VBoxContainer
var sheet: VBoxContainer
var page_scroll: ScrollContainer
var sheet_scroll: ScrollContainer
var columns: BoxContainer
var footer: HBoxContainer
var back: Button
var next: Button
var counter: Label
var sections: Array[Dictionary] = []
var active := ""
var numbered := true

func _ready() -> void:
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_theme_constant_override("separation", 12)
	navigation = HFlowContainer.new()
	add_child(navigation)
	columns = BoxContainer.new()
	columns.size_flags_vertical = Control.SIZE_EXPAND_FILL
	columns.add_theme_constant_override("separation", 16)
	add_child(columns)
	page_scroll = ScrollContainer.new()
	page_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	page_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	page_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	columns.add_child(page_scroll)
	page = VBoxContainer.new()
	page.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	page.add_theme_constant_override("separation", 12)
	page_scroll.add_child(page)
	var summary_panel := PanelContainer.new()
	summary_panel.name = "Overview"
	columns.add_child(summary_panel)
	sheet_scroll = ScrollContainer.new()
	sheet_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	sheet_scroll.custom_minimum_size.x = 205
	sheet_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	summary_panel.add_child(sheet_scroll)
	sheet = VBoxContainer.new()
	sheet.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sheet_scroll.add_child(sheet)
	footer = HBoxContainer.new()
	add_child(footer)
	back = Button.new()
	back.text = "‹ Back"
	back.pressed.connect(_relative.bind(-1))
	footer.add_child(back)
	counter = Label.new()
	counter.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	counter.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	counter.theme_type_variation = "MutedLabel"
	footer.add_child(counter)
	next = Button.new()
	next.theme_type_variation = "PrimaryButton"
	next.pressed.connect(_relative.bind(1))
	footer.add_child(next)
	resized.connect(_adapt)

func _adapt() -> void:
	var stacked := size.x < 620
	columns.vertical = stacked
	sheet_scroll.custom_minimum_size = Vector2(0, 125) if stacked else Vector2(205, 0)
	columns.get_child(1).size_flags_horizontal = Control.SIZE_EXPAND_FILL if stacked else Control.SIZE_FILL

static func clear(parent: Node) -> void:
	for child: Node in parent.get_children():
		parent.remove_child(child)
		child.queue_free()

static func label(text: String, size: int = 16, muted: bool = false) -> Label:
	var result := Label.new()
	result.text = text
	result.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	result.add_theme_font_size_override("font_size", size)
	if muted: result.theme_type_variation = "MutedLabel"
	return result

static func type_name(type: String) -> String:
	return {"scene": "Story", "menu": "Conversation", "location": "Place", "values": "Saved values"}.get(type, type.capitalize())

static func choice(title: String, description: String) -> Button:
	var button := Button.new()
	button.text = title + ("\n" + description if not description.is_empty() else "")
	button.alignment = HORIZONTAL_ALIGNMENT_LEFT
	button.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	button.custom_minimum_size.y = 68
	button.theme_type_variation = "ChoiceCard"
	return button

func set_sections(values: Array[Dictionary], selected: String) -> void:
	sections = values
	active = selected
	clear(navigation)
	var index := 0
	for entry: Dictionary in sections:
		var button := Button.new()
		button.text = "%d  %s" % [index + 1, entry.title] if numbered else str(entry.title)
		button.toggle_mode = true
		button.button_pressed = entry.key == active
		button.theme_type_variation = "StepButton"
		button.pressed.connect(func() -> void: section_requested.emit(entry.key))
		navigation.add_child(button)
		index += 1
	var at := _index()
	back.disabled = at <= 0
	counter.text = "%d of %d" % [at + 1, sections.size()]
	next.text = "Next: " + str(sections[at + 1].title) + " ›" if at + 1 < sections.size() else "Overview"
	_adapt()

func _index() -> int:
	for index in sections.size():
		if sections[index].key == active: return index
	return 0

func _relative(offset: int) -> void:
	var index := _index() + offset
	if index >= sections.size(): index = 0
	if index >= 0: section_requested.emit(sections[index].key)
