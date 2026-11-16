class_name TaskWizard
extends ConfirmationDialog

signal created(result: Dictionary)
var workspace: PackWorkspace
var template: Dictionary = {}
var fields: Dictionary = {}
var form: VBoxContainer
var error: Label
var questions_page: ScrollContainer
var review: Label
var reviewing := false
var back: Button

func _ready() -> void:
	exclusive = true
	dialog_hide_on_ok = false
	var body := VBoxContainer.new()
	body.custom_minimum_size = Vector2(630, 460)
	add_child(body)
	questions_page = ScrollContainer.new()
	questions_page.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	questions_page.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_child(questions_page)
	form = VBoxContainer.new()
	form.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	questions_page.add_child(form)
	review = Label.new()
	review.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	review.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_child(review)
	error = Label.new()
	error.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	error.add_theme_color_override("font_color", EditorTheme.color("bad"))
	body.add_child(error)
	back = add_button("Back", true)
	back.pressed.connect(func() -> void: _page(false))
	confirmed.connect(_advance)

func open(value: PackWorkspace, data: Dictionary) -> void:
	workspace = value
	template = data
	title = data.title
	fields.clear()
	for child: Node in form.get_children():
		form.remove_child(child)
		child.queue_free()
	for question: Dictionary in data.questions:
		form.add_child(AuthoringLayout.label(question.label, 15))
		var control: Control
		if str(question.kind).trim_suffix("?") in ["location", "zone", "form", "item", "image"]:
			var slot := ContentSlot.new()
			slot.configure(workspace, str(question.kind).trim_suffix("?"))
			control = slot
		elif question.kind.begins_with("choice:"):
			var picker := OptionButton.new()
			for option: String in str(question.kind).trim_prefix("choice:").split(","):
				picker.add_item(option)
				if option == question.default: picker.select(picker.item_count - 1)
			control = picker
		elif question.kind == "number":
			var amount := SpinBox.new()
			amount.max_value = 100000
			amount.value = float(question.default)
			control = amount
		elif question.kind in ["prose", "stages"]:
			var text := TextEdit.new()
			text.text = str(question.default).replace(";", "\n") if question.kind == "stages" else str(question.default)
			text.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
			text.custom_minimum_size.y = 95
			control = text
		else:
			var input := LineEdit.new()
			input.text = question.default
			input.placeholder_text = "Name your content"
			control = input
		control.custom_minimum_size.x = 530
		fields[question.key] = control
		form.add_child(control)
	_page(false)
	popup_centered()
	if fields.has("name"): fields.name.grab_focus()

func answers() -> Dictionary:
	var result: Dictionary = {}
	for key: String in fields:
		var control: Control = fields[key]
		if control is ContentSlot: result[key] = control.value()
		elif control is OptionButton: result[key] = control.get_item_text(control.selected)
		elif control is SpinBox: result[key] = str(int(control.value))
		else: result[key] = control.text
	return result

func _page(is_review: bool) -> void:
	reviewing = is_review
	questions_page.visible = not reviewing
	review.visible = reviewing
	back.visible = reviewing
	ok_button_text = "Create" if reviewing else "Review"
	error.text = ""

func _advance() -> void:
	var result := AuthorTemplates.fill(template, answers(), workspace)
	if result.has("error"):
		error.text = result.error
		return
	if not reviewing:
		_page(true)
		var parsed := FscParser.parse(result.text, "")
		var descriptions: Array[String] = []
		for definition: FscParser.Definition in parsed.definitions: descriptions.append(Wording.name(definition.type) + " · " + definition.id.replace("_", " ").capitalize())
		review.text = "Ready to create\n\n" + "\n".join(descriptions) + "\n\nStories and references are connected automatically. You can undo this whole task in one step. Files are written when you choose Save all."
		return
	result = AuthorTemplates.create(template, answers(), workspace)
	if result.has("error"):
		error.text = result.error
		return
	hide()
	created.emit(result)
