class_name ModifierRows
extends VBoxContainer
## A rule's adjustments: "condition: amount" lines (a feat that adds 1, a
## state that takes 3 off), each shown as a condition in words and its amount.

signal edited(text: String)
signal problem(message: String)

var workspace: PackWorkspace
var writable := true
var context: Array = []
var heading := "Adjust when…"
var _rules: Array[Dictionary] = []
var _dialog: ConditionDialog
var _target := -1

## The field's lines as {condition, amount}; `ok` is false when a line is
## something else (a note, a deeper level), which is then left alone.
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
		var separator := child.text.rfind(":")
		if child.indent != 4 or separator < 1: return {"ok": false, "entries": entries}
		var condition := child.text.left(separator).strip_edges()
		if Condition.compile(condition).has("error"): return {"ok": false, "entries": entries}
		entries.append({"condition": condition, "amount": child.text.substr(separator + 1).strip_edges()})
	return {"ok": true, "entries": entries}

## Why an amount cannot be used; empty when it can.
static func amount_problem(amount: String) -> String:
	if amount.strip_edges().is_empty(): return "Write how much is added: + 1, - 3 or a calculation."
	var parsed: Dictionary = Expr.parse(CompanionSystem.amount_text(amount))
	return str(parsed.error) if parsed.has("error") else ""

func configure(pack: PackWorkspace, entries: Array[Dictionary], can_write: bool, where: Array = [], title: String = "") -> void:
	workspace = pack
	writable = can_write
	context = where
	if not title.is_empty(): heading = title
	_rules = entries.duplicate(true)
	_build()

func text() -> String:
	var lines: Array[String] = []
	for rule: Dictionary in _rules: lines.append("%s: %s" % [rule.condition, rule.amount])
	return "\n".join(lines)

func count() -> int:
	return _rules.size()

func set_amount(index: int, amount: String) -> bool:
	amount = amount.strip_edges()
	if index < 0 or index >= _rules.size() or amount == _rules[index].amount: return true
	var wrong := amount_problem(amount)
	if not wrong.is_empty():
		problem.emit(wrong)
		return false
	_rules[index].amount = amount
	edited.emit(text())
	return true

func set_condition(index: int, condition: String) -> void:
	if condition.is_empty() or Condition.compile(condition).has("error"): return
	workspace.require_condition(Condition.compile(condition))
	if index < 0 or index >= _rules.size(): _rules.append({"condition": condition, "amount": "+ 1"})
	elif _rules[index].condition == condition: return
	else: _rules[index].condition = condition
	edited.emit(text())

func remove(index: int) -> void:
	if index < 0 or index >= _rules.size(): return
	_rules.remove_at(index)
	edited.emit(text())

func _ask(index: int) -> void:
	if _dialog == null:
		_dialog = ConditionDialog.new()
		add_child(_dialog)
		_dialog.applied.connect(func(condition: String) -> void: set_condition(_target, condition))
	_target = index
	_dialog.open(workspace, str(_rules[index].condition) if index >= 0 else "", context, "", heading, false)

func _build() -> void:
	for child: Node in get_children():
		if child != _dialog: child.queue_free()
	add_theme_constant_override("separation", 6)
	if _rules.is_empty(): add_child(AuthoringLayout.label("No adjustments.", 14, true))
	for index in _rules.size():
		var rule: Dictionary = _rules[index]
		var line := HBoxContainer.new()
		line.add_theme_constant_override("separation", 8)
		line.set_meta("rule", index)
		var words := AuthoringLayout.label("When " + BlockCatalog.condition_sentence(rule.condition, workspace), 14)
		words.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		words.theme_type_variation = "AccentLabel"
		line.add_child(words)
		var amount := LineEdit.new()
		amount.text = rule.amount
		amount.editable = writable
		amount.custom_minimum_size.x = 150
		amount.tooltip_text = "How much is added while that is true: + 1, - 3, or a calculation such as - player.level * 2."
		var keep := func() -> void:
			if not is_instance_valid(amount) or not amount.editable: return
			if not set_amount(index, amount.text): amount.text = rule.amount
		amount.text_submitted.connect(func(_text: String) -> void: keep.call())
		amount.focus_exited.connect(keep)
		line.add_child(amount)
		if writable:
			var change := Button.new()
			change.text = "Change…"
			change.tooltip_text = "Change the condition."
			change.pressed.connect(_ask.bind(index))
			line.add_child(change)
			var take := IconButton.new()
			take.text = "×"
			take.tooltip_text = "Remove this adjustment"
			take.pressed.connect(remove.bind(index))
			line.add_child(take)
		add_child(line)
	if writable:
		var add := Button.new()
		add.text = "+ Add an adjustment…"
		add.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
		add.tooltip_text = "Choose when it applies, then set how much it adds."
		add.pressed.connect(_ask.bind(-1))
		add_child(add)
