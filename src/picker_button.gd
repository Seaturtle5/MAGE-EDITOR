class_name PickerButton
extends Button
## A button that opens a searchable list. Typing filters; Enter takes the
## first match. Library content of a matching kind can be dropped on it.

signal picked(value: String)
## Returns the choices: [{value, label, detail}].
var options: Callable
## Extra rows under the list: [{label, action: Callable}].
var commands: Array[Dictionary] = []
var value := ""
var placeholder := "Choose…"
## Offer the typed words themselves when nothing in the list matches.
var allow_typing := false
var workspace: PackWorkspace
var drop_kinds: Array = []
var panel: PopupPanel
var search: LineEdit
var list: ItemList
var shown: Array[Dictionary] = []

func _init() -> void:
	theme_type_variation = "Chip"
	text = placeholder
	pressed.connect(func() -> void: open())

func choices() -> Array:
	return options.call() if options.is_valid() else []

func set_value(next: String) -> void:
	value = next
	text = placeholder
	if value.is_empty(): return
	text = value.replace("_", " ")
	for option: Dictionary in choices():
		if option.value == value:
			text = option.label
			break

func choose(next: String) -> void:
	set_value(next)
	if panel != null: panel.hide()
	picked.emit(value)

## Opens the list under the button, or at a screen position when one is given.
func open(at: Vector2i = Vector2i(-1, -1)) -> void:
	if panel == null:
		panel = PopupPanel.new()
		var body := VBoxContainer.new()
		body.custom_minimum_size = Vector2(320, 320)
		panel.add_child(body)
		search = LineEdit.new()
		search.placeholder_text = "Type to search…"
		search.clear_button_enabled = true
		search.text_changed.connect(func(_text: String) -> void: fill())
		search.text_submitted.connect(func(_text: String) -> void:
			if not shown.is_empty(): _take(0))
		search.gui_input.connect(func(event: InputEvent) -> void:
			if event.is_action_pressed("ui_down") and list.item_count > 0:
				list.grab_focus()
				list.select(0))
		body.add_child(search)
		list = ItemList.new()
		list.size_flags_vertical = Control.SIZE_EXPAND_FILL
		list.item_clicked.connect(func(index: int, _position: Vector2, button: int) -> void:
			if button == MOUSE_BUTTON_LEFT: _take(index))
		list.item_activated.connect(_take)
		body.add_child(list)
		add_child(panel)
	search.text = ""
	fill()
	var origin := at if at.x >= 0 else Vector2i(get_screen_position()) + Vector2i(0, int(size.y) + 2)
	panel.popup(Rect2i(origin, Vector2i(maxi(int(size.x), 340), 340)))
	search.grab_focus()

func fill() -> void:
	list.clear()
	shown.clear()
	var query := search.text.strip_edges().to_lower()
	var total := 0
	for option: Dictionary in choices():
		if not query.is_empty() and query not in (str(option.label) + " " + str(option.value) + " " + str(option.get("detail", ""))).to_lower(): continue
		total += 1
		if shown.size() >= 150: continue
		shown.append(option)
		list.add_item(str(option.label) + ("   ·   " + str(option.detail) if not str(option.get("detail", "")).is_empty() else ""))
	if total > shown.size():
		list.add_item("… %d more. Type to narrow the list." % (total - shown.size()))
		list.set_item_disabled(list.item_count - 1, true)
	if allow_typing and not query.is_empty() and not shown.any(func(option: Dictionary) -> bool: return str(option.value) == search.text.strip_edges()):
		shown.append({"value": search.text.strip_edges(), "label": search.text.strip_edges()})
		list.add_item("Use “" + search.text.strip_edges() + "” as written")
		if list.item_count > 1 and total > 0: list.move_item(list.item_count - 1, mini(total, 150))
	for command: Dictionary in commands:
		shown.append({"command": command})
		list.add_item(str(command.label))
	if list.item_count > 0 and not list.is_item_disabled(0): list.select(0)

func _take(index: int) -> void:
	# The "more" row sits between matches and the typed entry; skip it.
	var rows: Array[Dictionary] = []
	for at in list.item_count:
		if not list.is_item_disabled(at): rows.append({"at": at})
	var position := -1
	for at in rows.size():
		if rows[at].at == index: position = at
	if position < 0 or position >= shown.size(): return
	var option: Dictionary = shown[position]
	if option.has("command"):
		panel.hide()
		option.command.action.call()
		return
	choose(str(option.value))

func _can_drop_data(_position: Vector2, data: Variant) -> bool:
	return not disabled and workspace != null and not drop_kinds.is_empty() and not DragPayload.resolve(workspace, data).is_empty() and data.get("type") in drop_kinds

func _drop_data(position: Vector2, data: Variant) -> void:
	if _can_drop_data(position, data): choose(str(data.id))
