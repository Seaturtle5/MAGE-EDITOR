class_name CommandPalette
extends ConfirmationDialog

signal chosen(entry: Dictionary)
var search: LineEdit
var list: ItemList
var entries: Array[Dictionary] = []
var filtered: Array[Dictionary] = []

func _ready() -> void:
	title = "Find anything"
	ok_button_text = "Open"
	var body := VBoxContainer.new()
	body.custom_minimum_size = Vector2(580, 390)
	add_child(body)
	search = LineEdit.new()
	search.placeholder_text = "Find content, prose, saved values or commands…"
	body.add_child(search)
	list = ItemList.new()
	list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_child(list)
	search.text_changed.connect(func(_value: String) -> void: _filter())
	search.text_submitted.connect(func(_value: String) -> void: _choose())
	search.gui_input.connect(func(event: InputEvent) -> void:
		if event.is_action_pressed("ui_down") and list.item_count > 0: list.grab_focus())
	list.item_activated.connect(func(_index: int) -> void: _choose())
	confirmed.connect(_choose)

func open(workspace: PackWorkspace) -> void:
	entries.clear()
	for row: Dictionary in workspace.rows:
		entries.append({"label": Wording.icon(row.def.type) + " " + Wording.title(row) + " · " + Wording.name(row.def.type) + " · " + row.pack, "search": row.doc.block(row.def).to_lower(), "row": row})
	for key: String in workspace.preview_content().values:
		entries.append({"label": "# " + key, "search": key.to_lower(), "value": key})
	for command: String in ["Home", "New content", "Check pack", "Save all", "Undo", "Redo", "Tour"]:
		entries.append({"label": command, "search": command.to_lower(), "command": command})
	search.text = ""
	_filter()
	popup_centered()
	search.grab_focus()

func _filter() -> void:
	list.clear()
	filtered.clear()
	for entry: Dictionary in entries:
		if not search.text.is_empty() and search.text.to_lower() not in entry.search and search.text.to_lower() not in str(entry.label).to_lower(): continue
		filtered.append(entry)
		list.add_item(entry.label)
		if filtered.size() == 200: break
	if list.item_count: list.select(0)

func _choose() -> void:
	if list.get_selected_items().is_empty(): return
	var entry: Dictionary = filtered[list.get_selected_items()[0]]
	hide()
	chosen.emit(entry)
