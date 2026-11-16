class_name PackHome
extends ScrollContainer

signal task_requested(template: Dictionary)
signal open_requested(row: Dictionary)
signal check_requested
var body: VBoxContainer

func _ready() -> void:
	horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	body = VBoxContainer.new()
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation", 12)
	add_child(body)

func refresh(workspace: PackWorkspace) -> void:
	if body == null: return
	for child: Node in body.get_children():
		body.remove_child(child)
		child.queue_free()
	body.add_child(AuthoringLayout.label("What would you like to make?", 24))
	if workspace.target.is_empty():
		body.add_child(AuthoringLayout.label("Open or create a pack from the Pack menu to start writing.", 16, true))
		return
	var counts: Dictionary = {}
	for row: Dictionary in workspace.rows:
		if row.doc.writable: counts[Wording.name(row.def.type)] = int(counts.get(Wording.name(row.def.type), 0)) + 1
	var facts: Array[String] = []
	for kind: String in counts: facts.append("%d %s" % [counts[kind], kind])
	body.add_child(AuthoringLayout.label(" · ".join(facts), 13, true))
	var tasks := GridContainer.new()
	tasks.columns = 2
	body.add_child(tasks)
	for template: Dictionary in AuthorTemplates.available(workspace):
		var button := Button.new()
		button.text = ("Flexible Survival · " if template.family == "flexible_survival" else "") + str(template.title)
		button.custom_minimum_size.y = 42
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.pressed.connect(func() -> void: task_requested.emit(template))
		tasks.add_child(button)
	body.add_child(AuthoringLayout.label("Continue writing", 20))
	var found := 0
	var recent := workspace.rows.duplicate()
	recent.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a.doc.dirty() and not b.doc.dirty())
	for row: Dictionary in recent:
		if not row.doc.writable or row.def.type == "pack": continue
		var button := Button.new()
		button.alignment = HORIZONTAL_ALIGNMENT_LEFT
		button.text = Wording.icon(row.def.type) + " " + Wording.title(row) + " · " + Wording.name(row.def.type) + (" · unsaved" if row.doc.dirty() else "")
		button.pressed.connect(func() -> void: open_requested.emit(row))
		body.add_child(button)
		found += 1
		if found == 8: break
	if found == 0: body.add_child(AuthoringLayout.label("No stories yet. Choose a task above to create your first one.", 15, true))
	var errors := workspace.diagnostics.filter(func(item: Dictionary) -> bool: return item.severity == "error").size()
	var check := Button.new()
	check.text = "Check pack · %d problems · %d unsaved files" % [errors, workspace.dirty_count()]
	check.pressed.connect(func() -> void: check_requested.emit())
	body.add_child(check)
