class_name SentenceView
extends HFlowContainer
## A block's sentence: plain words, with chips where the author can change something.

signal slot_changed(name: String, value: String)
var workspace: PackWorkspace
var candidate: Dictionary = {}
var slots: Dictionary = {}
var editable := true
## The event whose results a "result" chip offers when the sentence names none.
var event := ""
var size_override := 15

func _init() -> void:
	add_theme_constant_override("h_separation", 4)
	add_theme_constant_override("v_separation", 3)
	size_flags_horizontal = Control.SIZE_EXPAND_FILL

func words(text: String, variation: String = "") -> void:
	for word: String in text.split(" ", false):
		var label := Label.new()
		label.text = word
		label.add_theme_font_size_override("font_size", size_override)
		label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		if not variation.is_empty(): label.theme_type_variation = variation
		add_child(label)

func chip(text: String, tooltip: String = "") -> Button:
	var button := Button.new()
	button.theme_type_variation = "Chip"
	button.text = text if text.length() <= 46 else text.left(44) + "…"
	button.tooltip_text = tooltip if not tooltip.is_empty() else text
	button.add_theme_font_size_override("font_size", size_override)
	button.focus_mode = Control.FOCUS_NONE
	add_child(button)
	return button

func show_sentence(pack: PackWorkspace, entry: Dictionary, values: Dictionary, can_edit: bool = true) -> void:
	workspace = pack
	candidate = entry
	slots = values.duplicate()
	editable = can_edit
	for child: Node in get_children():
		remove_child(child)
		child.queue_free()
	var first := true
	for piece: Dictionary in BlockCatalog.pieces(entry, slots, workspace):
		if piece.has("text"):
			var text: String = piece.text
			if first: text = text.left(1).to_upper() + text.substr(1)
			words(text)
		else: _slot(piece, first)
		first = false

func _peer(name: String) -> String:
	return event if name == "@event" else str(slots.get(name, ""))

func _slot(piece: Dictionary, first: bool) -> void:
	var spec: Dictionary = piece.spec
	var kind: String = spec.kind
	var label: String = piece.label
	if first: label = label.left(1).to_upper() + label.substr(1)
	if not editable:
		chip(label).disabled = true
		return
	if kind in ["choice", "switch", "int", "amount", "expr", "exprs", "text", "quoted", "plain", "token"] or kind.begins_with("ids"):
		var button := chip(label, "Change " + BlockCatalog.slot_title(spec))
		button.pressed.connect(_edit.bind(spec, button))
		return
	var control := SlotControl.make(workspace, spec, str(piece.value), _peer)
	control.picker.add_theme_font_size_override("font_size", size_override)
	control.picker.focus_mode = Control.FOCUS_NONE
	control.picker.tooltip_text = "Change " + BlockCatalog.slot_title(spec) + ", or drop one here from the library"
	if first and not control.picker.text.is_empty(): control.picker.text = control.picker.text.left(1).to_upper() + control.picker.text.substr(1)
	control.edited.connect(func() -> void: slot_changed.emit(str(spec.name), control.value()))
	add_child(control)

func _edit(spec: Dictionary, anchor: Button) -> void:
	if spec.kind == "choice" and not spec.get("optional", false):
		var menu := PopupMenu.new()
		for index in spec.options.size(): menu.add_item(str(spec.labels[index]), index)
		menu.id_pressed.connect(func(id: int) -> void: slot_changed.emit(str(spec.name), str(spec.options[id])))
		menu.popup_hide.connect(menu.queue_free)
		add_child(menu)
		menu.popup(Rect2i(Vector2i(anchor.get_screen_position()) + Vector2i(0, int(anchor.size.y)), Vector2i.ZERO))
		return
	var panel := PopupPanel.new()
	var body := VBoxContainer.new()
	panel.add_child(body)
	body.add_child(AuthoringLayout.label(BlockCatalog.slot_title(spec).capitalize(), 13, true))
	var control := SlotControl.make(workspace, spec, str(slots.get(spec.name, "")), _peer)
	body.add_child(control)
	var apply := Button.new()
	apply.text = "Apply"
	apply.theme_type_variation = "PrimaryButton"
	body.add_child(apply)
	var done := func() -> void:
		var next := control.value()
		panel.hide()
		slot_changed.emit(str(spec.name), next)
	apply.pressed.connect(done)
	for input: Node in control.find_children("*", "LineEdit", true, false):
		(input as LineEdit).text_submitted.connect(func(_text: String) -> void: done.call())
	panel.popup_hide.connect(panel.queue_free)
	add_child(panel)
	panel.popup(Rect2i(Vector2i(anchor.get_screen_position()) + Vector2i(0, int(anchor.size.y) + 2), Vector2i.ZERO))
	var focus := control.find_children("*", "LineEdit", true, false)
	if not focus.is_empty(): (focus[0] as LineEdit).grab_focus()
