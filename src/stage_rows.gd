class_name StageRows
extends VBoxContainer
## Steps in order: a quest's stages (one name on each line), or a meter's
## stages ("2: tipsy": from which number a condition applies).

signal edited(text: String)
signal problem(message: String)

var workspace: PackWorkspace
var writable := true
## True for a meter: every step is a number and the condition it starts.
var thresholds := false
var _steps: Array[Dictionary] = []

## The field's lines as {name, at}; `ok` is false when a line is written
## another way, which is then left alone.
static func read(doc: PackDocument, field: FscParser.Field, with_numbers: bool) -> Dictionary:
	var entries: Array[Dictionary] = []
	if field == null: return {"ok": true, "entries": entries}
	if not field.value.is_empty(): return {"ok": false, "entries": entries}
	var lines := doc.text.split("\n")
	if not field.children.is_empty():
		for index in range(field.line, field.children[-1].number):
			if index < lines.size() and lines[index].strip_edges().begins_with("//"): return {"ok": false, "entries": entries}
	var pattern := RegEx.create_from_string("^(\\d+)\\s*:\\s*([a-z0-9_]+)$" if with_numbers else "^([a-z0-9_]+)$")
	for child: FscParser.Line in field.children:
		if child.is_blank(): continue
		var found := pattern.search(child.text.strip_edges())
		if child.indent != 4 or found == null: return {"ok": false, "entries": entries}
		entries.append({"name": found.get_string(2), "at": int(found.get_string(1))} if with_numbers else {"name": found.get_string(1), "at": 0})
	return {"ok": true, "entries": entries}

func configure(pack: PackWorkspace, entries: Array[Dictionary], can_write: bool, with_numbers: bool) -> void:
	workspace = pack
	writable = can_write
	thresholds = with_numbers
	_steps = entries.duplicate(true)
	_build()

func text() -> String:
	var lines: Array[String] = []
	for step: Dictionary in _steps: lines.append("%d: %s" % [int(step.at), step.name] if thresholds else str(step.name))
	return "\n".join(lines)

func count() -> int:
	return _steps.size()

func names() -> Array:
	return _steps.map(func(step: Dictionary) -> String: return step.name)

## A name as the content format writes it: "Found the key" becomes found_the_key.
static func word(name: String) -> String:
	var out := ""
	for letter: String in name.strip_edges().to_lower():
		if (letter >= "a" and letter <= "z") or (letter >= "0" and letter <= "9"): out += letter
		elif not out.is_empty() and not out.ends_with("_"): out += "_"
	return out.trim_suffix("_")

func add(name: String, at: int = -1) -> bool:
	name = word(name)
	if name.is_empty() or (not thresholds and name in names()):
		problem.emit("Give the step a name of its own.")
		return false
	if at < 0: at = int(_steps[-1].at) + 1 if not _steps.is_empty() else 1
	_steps.append({"name": name, "at": at})
	if thresholds: _steps.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return int(a.at) < int(b.at))
	edited.emit(text())
	return true

func rename(index: int, name: String) -> bool:
	name = word(name)
	if index < 0 or index >= _steps.size() or name == _steps[index].name: return true
	if name.is_empty() or (not thresholds and name in names()):
		problem.emit("Give the step a name of its own.")
		return false
	_steps[index].name = name
	edited.emit(text())
	return true

func set_at(index: int, at: int) -> void:
	if index < 0 or index >= _steps.size() or int(_steps[index].at) == at: return
	_steps[index].at = at
	_steps.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return int(a.at) < int(b.at))
	edited.emit(text())

func move(index: int, by: int) -> void:
	var goal := index + by
	if thresholds or index < 0 or index >= _steps.size() or goal < 0 or goal >= _steps.size(): return
	var step: Dictionary = _steps[index]
	_steps.remove_at(index)
	_steps.insert(goal, step)
	edited.emit(text())

func remove(index: int) -> void:
	if index < 0 or index >= _steps.size(): return
	_steps.remove_at(index)
	edited.emit(text())

func _build() -> void:
	for child: Node in get_children(): child.queue_free()
	add_theme_constant_override("separation", 6)
	if _steps.is_empty(): add_child(AuthoringLayout.label("No steps yet.", 14, true))
	for index in _steps.size():
		var step: Dictionary = _steps[index]
		var line := HBoxContainer.new()
		line.add_theme_constant_override("separation", 8)
		line.set_meta("step", index)
		if thresholds:
			line.add_child(AuthoringLayout.label("From", 14, true))
			var at := SpinBox.new()
			at.max_value = 1000000
			at.set_value_no_signal(int(step.at))
			at.editable = writable
			at.tooltip_text = "The meter's number from which this applies."
			at.value_changed.connect(func(next: float) -> void: set_at(index, int(next)))
			line.add_child(at)
			var state := SlotControl.make(workspace, {"name": "condition", "kind": "condition", "optional": false}, step.name)
			state.edited.connect(func() -> void:
				if not state.value().is_empty(): rename(index, state.value()))
			if not writable:
				for button: Node in state.find_children("*", "BaseButton", true, false): (button as BaseButton).disabled = true
			line.add_child(state)
		else:
			line.add_child(AuthoringLayout.label("%d." % (index + 1), 14, true))
			var name := LineEdit.new()
			name.text = str(step.name).replace("_", " ")
			name.editable = writable
			name.custom_minimum_size.x = 220
			name.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			name.tooltip_text = "The step's name. Stories that set or check this step name it, so change them too when it is renamed."
			var keep := func() -> void:
				if is_instance_valid(name) and name.editable and not rename(index, name.text): name.text = str(step.name).replace("_", " ")
			name.text_submitted.connect(func(_text: String) -> void: keep.call())
			name.focus_exited.connect(keep)
			line.add_child(name)
		if writable:
			if not thresholds:
				for direction: Array in [["↑", -1, "Earlier"], ["↓", 1, "Later"]]:
					var shift := IconButton.new()
					shift.text = direction[0]
					shift.tooltip_text = direction[2]
					shift.disabled = index + int(direction[1]) < 0 or index + int(direction[1]) >= _steps.size()
					shift.pressed.connect(move.bind(index, int(direction[1])))
					line.add_child(shift)
			var take := IconButton.new()
			take.text = "×"
			take.tooltip_text = "Remove this step"
			take.pressed.connect(remove.bind(index))
			line.add_child(take)
		add_child(line)
	if not writable: return
	if thresholds:
		var more := SlotControl.make(workspace, {"name": "condition", "kind": "condition", "optional": false}, "")
		more.picker.placeholder = "+ Add a stage: choose its condition…"
		more.picker.text = more.picker.placeholder
		more.edited.connect(func() -> void: add(more.value()))
		add_child(more)
	else:
		var line := HBoxContainer.new()
		var name := LineEdit.new()
		name.placeholder_text = "A new step, such as Found the key"
		name.custom_minimum_size.x = 260
		line.add_child(name)
		var more := Button.new()
		more.text = "+ Add"
		more.pressed.connect(func() -> void: add(name.text))
		name.text_submitted.connect(func(next: String) -> void: add(next))
		line.add_child(more)
		add_child(line)
