class_name PairRows
extends VBoxContainer
## Rows of two parts for fields the content format writes as "left: right"
## lines (a threshold and its words, a condition and what it adds) or as
## "item 80%, item 30%" on one line. What each part is comes from SPECS.

signal edited(text: String)

## "type/field" -> left and right captions and kinds (number, word, text,
## condition, or a content type to pick from), the add button's words, and
## `inline` for the one-line form "left right%".
const SPECS := {
	"survival_rules/hunger warnings": {"left": "From hunger", "left_kind": "number", "right": "The player reads", "right_kind": "text", "add": "+ Add a warning", "none": "No warnings yet."},
	"survival_rules/thirst warnings": {"left": "From thirst", "left_kind": "number", "right": "The player reads", "right_kind": "text", "add": "+ Add a warning", "none": "No warnings yet."},
	"survival_rules/humanity descriptions": {"left": "From humanity", "left_kind": "number", "right": "Described as", "right_kind": "text", "add": "+ Add a description", "none": "No descriptions yet."},
	"survival_rules/lust descriptions": {"left": "From libido", "left_kind": "number", "right": "Described as", "right_kind": "text", "add": "+ Add a description", "none": "No descriptions yet."},
	"rest_rules/statuses": {"left": "From tiredness", "left_kind": "number", "right": "Shown as", "right_kind": "text", "add": "+ Add a status", "none": "No statuses yet."},
	"rest_rules/warnings": {"left": "At tiredness", "left_kind": "number", "right": "The player reads", "right_kind": "text", "add": "+ Add a warning", "none": "No warnings yet."},
	"status_bar/details": {"left": "Line", "left_kind": "word", "right": "Shows", "right_kind": "text", "add": "+ Add a line", "none": "No lines yet."},
	"creation_rules/feats": {"left": "Group", "left_kind": "word", "right": "Feat given", "right_kind": "feat", "add": "+ Add a feat", "none": "No feats given at the start."},
	"location/instead of": {"left": "Instead of", "left_kind": "word", "right": "The player reads", "right_kind": "text", "add": "+ Add a refusal", "none": "Nothing is refused here.", "words": ["explore", "scavenge", "rest", "wait", "hunt"]},
	"pregnancy_rules/quickens": {"left": "When", "left_kind": "condition", "right": "Chance", "right_kind": "word", "add": "+ Add a rule…", "none": "No rules yet."},
	"pregnancy_rules/extra child bonus": {"left": "When", "left_kind": "condition", "right": "Adds", "right_kind": "word", "add": "+ Add a rule…", "none": "No rules yet."},
	"pregnancy_rules/child genders": {"left": "Gender", "left_kind": "word", "right": "Weight (and “if …”)", "right_kind": "text", "add": "+ Add a gender", "none": "No genders yet."},
	"pregnancy_rules/fathers": {"left": "Father (a form or creature)", "left_kind": "word", "right": "When", "right_kind": "text", "add": "+ Add a father", "none": "No fixed fathers."},
	"level/options": {"left": "Option", "left_kind": "word", "right": "What it means", "right_kind": "text", "add": "+ Add an option", "none": "No options yet."},
	"creature/trophies": {"left": "Item", "left_kind": "item", "right": "Chance %", "right_kind": "number", "add": "+ Add a trophy", "none": "No trophies to choose from.", "inline": true},
}

var workspace: PackWorkspace
var writable := true
var spec: Dictionary = {}
var context: Array = []
var _rows: Array = []
var _dialog: ConditionDialog
var _target := -1

static func has_rows(type: String, key: String) -> bool:
	return SPECS.has(type + "/" + key)

## The field as [[left, right]]; `ok` is false when it is written another
## way (deeper lines, notes between the lines), which is then left alone.
static func read(doc: PackDocument, field: FscParser.Field, rules: Dictionary) -> Dictionary:
	var entries: Array = []
	if field == null: return {"ok": true, "entries": entries}
	if rules.get("inline", false):
		if not field.children.is_empty(): return {"ok": false, "entries": entries}
		for part: String in field.value.split(",", false):
			var words := part.strip_edges().split(" ", false)
			if words.size() != 2 or not str(words[1]).trim_suffix("%").is_valid_int(): return {"ok": false, "entries": entries}
			entries.append([words[0], str(words[1]).trim_suffix("%")])
		return {"ok": true, "entries": entries}
	if not field.value.is_empty(): return {"ok": false, "entries": entries}
	var lines := doc.lines()
	if not field.children.is_empty():
		for index in range(field.line, field.children[-1].number):
			if index < lines.size() and lines[index].strip_edges().begins_with("//"): return {"ok": false, "entries": entries}
	for child: FscParser.Line in field.children:
		if child.is_blank(): continue
		var separator := child.text.find(":")
		if child.indent != 4 or separator < 1: return {"ok": false, "entries": entries}
		var left := child.text.left(separator).strip_edges()
		var right := child.text.substr(separator + 1).strip_edges()
		if rules.left_kind == "number" and not left.is_valid_int(): return {"ok": false, "entries": entries}
		if rules.left_kind == "condition" and Condition.compile(left).has("error"): return {"ok": false, "entries": entries}
		entries.append([left, right])
	return {"ok": true, "entries": entries}

func configure(pack: PackWorkspace, entries: Array, can_write: bool, rules: Dictionary, where: Array = []) -> void:
	workspace = pack
	writable = can_write
	spec = rules
	context = where
	_rows = entries.duplicate(true)
	_build()

func text() -> String:
	var out: Array[String] = []
	for pair: Array in _rows: out.append(("%s %s%%" if spec.get("inline", false) else "%s: %s") % [pair[0], pair[1]])
	return (", " if spec.get("inline", false) else "\n").join(out)

func count() -> int:
	return _rows.size()

func set_part(index: int, side: int, value: String) -> void:
	value = value.strip_edges()
	if index < 0 or index >= _rows.size() or value == _rows[index][side] or (value.is_empty() and side == 0): return
	_rows[index][side] = value
	edited.emit(text())

func add(left: String, right: String) -> void:
	_rows.append([left, right])
	edited.emit(text())

func remove(index: int) -> void:
	if index < 0 or index >= _rows.size(): return
	_rows.remove_at(index)
	edited.emit(text())

func move(index: int, by: int) -> void:
	var to := index + by
	if index < 0 or index >= _rows.size() or to < 0 or to >= _rows.size(): return
	var held: Array = _rows[index]
	_rows[index] = _rows[to]
	_rows[to] = held
	edited.emit(text())

func _ask(index: int) -> void:
	if _dialog == null:
		_dialog = ConditionDialog.new()
		add_child(_dialog)
		_dialog.applied.connect(func(condition: String) -> void:
			if condition.is_empty() or Condition.compile(condition).has("error"): return
			workspace.require_condition(Condition.compile(condition))
			if _target < 0: add(condition, "1 in 2" if "Chance" in str(spec.right) else "+1")
			else: set_part(_target, 0, condition))
	_target = index
	_dialog.open(workspace, str(_rows[index][0]) if index >= 0 else "", context, "", str(spec.left) + "…", false)

func _part(index: int, side: int, kind: String) -> Control:
	var value: String = _rows[index][side]
	if kind == "number":
		var number := SpinBox.new()
		number.min_value = -1000000
		number.max_value = 1000000
		number.value = float(value) if value.is_valid_int() else 0.0
		number.editable = writable
		number.custom_minimum_size.x = 96
		number.value_changed.connect(func(next: float) -> void: set_part(index, side, str(int(next))))
		return number
	if kind == "condition":
		var words := AuthoringLayout.label(BlockCatalog.condition_sentence(value, workspace), 14)
		words.theme_type_variation = "AccentLabel"
		words.custom_minimum_size.x = 260
		words.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		words.mouse_filter = Control.MOUSE_FILTER_STOP
		words.tooltip_text = "Choose to change the condition."
		words.gui_input.connect(func(input: InputEvent) -> void:
			if writable and input is InputEventMouseButton and input.pressed and input.button_index == MOUSE_BUTTON_LEFT: _ask(index))
		return words
	if kind in PackWorkspace.types():
		var picker := PickerButton.new()
		picker.placeholder = "Choose…"
		picker.workspace = workspace
		picker.drop_kinds = [kind]
		picker.disabled = not writable
		picker.custom_minimum_size.x = 200
		picker.label_for = func(id: String) -> String: return BlockCatalog.content_label(kind, id, workspace)
		picker.options = func() -> Array:
			var result: Array = []
			var seen: Dictionary = {}
			for other: Dictionary in workspace.rows:
				if other.def.type != kind or other.def.mode == "extend" or seen.has(other.def.id): continue
				seen[other.def.id] = true
				result.append({"value": other.def.id, "label": Wording.title(other), "detail": "" if other.doc.writable else str(other.pack)})
			return result
		picker.set_value(value)
		picker.picked.connect(func(id: String) -> void:
			if id.is_empty(): return
			workspace.require_content(kind, id)
			set_part(index, side, id))
		return picker
	var input := LineEdit.new()
	input.text = value
	input.editable = writable
	if kind == "text": input.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	else: input.custom_minimum_size.x = 150
	var keep := func() -> void:
		if is_instance_valid(input) and input.editable: set_part(index, side, input.text)
	input.text_submitted.connect(func(_text: String) -> void: keep.call())
	input.focus_exited.connect(keep)
	return input

func _build() -> void:
	for child: Node in get_children():
		if child != _dialog: child.queue_free()
	add_theme_constant_override("separation", 6)
	if _rows.is_empty(): add_child(AuthoringLayout.label(str(spec.get("none", "Nothing yet.")), 14, true))
	else:
		var head := HBoxContainer.new()
		head.add_theme_constant_override("separation", 8)
		var left_title := AuthoringLayout.label(str(spec.left), 12, true)
		left_title.autowrap_mode = TextServer.AUTOWRAP_OFF
		left_title.custom_minimum_size.x = 260 if spec.left_kind == "condition" else 200 if spec.left_kind in PackWorkspace.types() else 150 if spec.left_kind == "word" else 96
		head.add_child(left_title)
		var right_title := AuthoringLayout.label(str(spec.right), 12, true)
		right_title.autowrap_mode = TextServer.AUTOWRAP_OFF
		head.add_child(right_title)
		add_child(head)
	for index in _rows.size():
		var line := HBoxContainer.new()
		line.add_theme_constant_override("separation", 8)
		line.set_meta("pair", index)
		line.add_child(_part(index, 0, str(spec.left_kind)))
		line.add_child(_part(index, 1, str(spec.right_kind)))
		if writable:
			for step: Array in [["▲", -1, "Move up"], ["▼", 1, "Move down"]]:
				var mover := IconButton.new()
				mover.text = step[0]
				mover.tooltip_text = step[2]
				mover.disabled = index + int(step[1]) < 0 or index + int(step[1]) >= _rows.size()
				mover.pressed.connect(move.bind(index, int(step[1])))
				line.add_child(mover)
			var take := IconButton.new()
			take.text = "×"
			take.tooltip_text = "Remove this row"
			take.pressed.connect(remove.bind(index))
			line.add_child(take)
		add_child(line)
	if writable:
		var more := Button.new()
		more.text = str(spec.get("add", "+ Add a row"))
		more.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
		more.pressed.connect(func() -> void:
			if spec.left_kind == "condition": _ask(-1)
			elif spec.left_kind == "number": add(str(int(_rows[-1][0]) + 10) if not _rows.is_empty() and str(_rows[-1][0]).is_valid_int() else "0", "50" if spec.right_kind == "number" else "Write the words here.")
			else:
				var words: Array = spec.get("words", [])
				var used: Array = _rows.map(func(pair: Array) -> String: return pair[0])
				var free: Array = words.filter(func(word: String) -> bool: return word not in used)
				add(str(free[0]) if not free.is_empty() else ("" if spec.left_kind in PackWorkspace.types() else "name"), "50" if spec.right_kind == "number" else "" if spec.right_kind in PackWorkspace.types() else "Write the words here."))
		add_child(more)
