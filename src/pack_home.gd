class_name PackHome
extends ScrollContainer
## Start here: guided tasks, what was worked on, and what needs attention.

signal task_requested(template: Dictionary)
signal open_requested(row: Dictionary)
signal check_requested
signal create_requested
signal problem_requested(diagnostic: Dictionary)
var body: VBoxContainer

func _ready() -> void:
	horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	var margin := MarginContainer.new()
	margin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for side: String in ["margin_left", "margin_right", "margin_top", "margin_bottom"]: margin.add_theme_constant_override(side, 6)
	add_child(margin)
	body = VBoxContainer.new()
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation", 10)
	margin.add_child(body)
	resized.connect(_fit)

func _fit() -> void:
	for grid: Node in body.find_children("*", "GridContainer", true, false):
		(grid as GridContainer).columns = clampi(int(size.x / 280.0), 1, 4)

func _card(icon: String, title: String, about: String, color: Color, action: Callable) -> Button:
	var button := Button.new()
	button.theme_type_variation = "ChoiceCard"
	button.custom_minimum_size = Vector2(240, 76)
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	button.tooltip_text = about
	button.pressed.connect(action)
	var row := HBoxContainer.new()
	row.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT, Control.PRESET_MODE_MINSIZE, 10)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_theme_constant_override("separation", 10)
	button.add_child(row)
	var symbol := Label.new()
	symbol.text = icon
	symbol.add_theme_font_size_override("font_size", 26)
	symbol.add_theme_color_override("font_color", color)
	symbol.custom_minimum_size.x = 38
	symbol.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	symbol.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	symbol.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(symbol)
	var words := VBoxContainer.new()
	words.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	words.alignment = BoxContainer.ALIGNMENT_CENTER
	words.add_theme_constant_override("separation", 1)
	words.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(words)
	var heading := AuthoringLayout.label(title, 16)
	heading.mouse_filter = Control.MOUSE_FILTER_IGNORE
	words.add_child(heading)
	var note := AuthoringLayout.label(about, 12, true)
	note.mouse_filter = Control.MOUSE_FILTER_IGNORE
	note.max_lines_visible = 2
	words.add_child(note)
	return button

func _section(title: String, note: String = "") -> void:
	var row := HBoxContainer.new()
	body.add_child(row)
	var heading := AuthoringLayout.label(title, 19)
	heading.autowrap_mode = TextServer.AUTOWRAP_OFF
	row.add_child(heading)
	if not note.is_empty():
		var extra := AuthoringLayout.label(note, 13, true)
		extra.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(extra)

func refresh(workspace: PackWorkspace) -> void:
	if body == null: return
	AuthoringLayout.clear(body)
	if workspace.target.is_empty():
		_section("Welcome")
		body.add_child(AuthoringLayout.label("Open or create a pack from the Pack menu to start writing.", 16, true))
		return
	var counts: Dictionary = {}
	for row: Dictionary in workspace.rows:
		if row.doc.writable and row.def.type != "pack": counts[row.def.type] = int(counts.get(row.def.type, 0)) + 1
	var kinds: Array = counts.keys()
	kinds.sort_custom(func(a: String, b: String) -> bool: return Wording.order(a) < Wording.order(b))
	var facts: Array[String] = []
	for kind: String in kinds: facts.append("%s %d %s" % [Wording.icon(kind), counts[kind], Wording.plural(kind).to_lower() if counts[kind] != 1 else Wording.name(kind)])
	_section("What would you like to make?")
	body.add_child(AuthoringLayout.label("Your pack so far:  " + "   ".join(facts) if not facts.is_empty() else "Your pack is empty. Choose a task below: each asks a few questions and builds the pieces for you.", 13, true))
	var tasks := GridContainer.new()
	tasks.add_theme_constant_override("h_separation", 8)
	tasks.add_theme_constant_override("v_separation", 8)
	body.add_child(tasks)
	var game: Array[Dictionary] = []
	for template: Dictionary in AuthorTemplates.available(workspace):
		if template.family == "flexible_survival":
			game.append(template)
			continue
		tasks.add_child(_card(Wording.icon(template.kind), template.title, template.about, EditorTheme.category_color(template.kind), func() -> void: task_requested.emit(template)))
	tasks.add_child(_card("+", "Something else…", "Any other kind of content, with its own form.", EditorTheme.color("muted"), func() -> void: create_requested.emit()))
	if not game.is_empty():
		_section("For Flexible Survival", "Shapes this game uses often.")
		var special := GridContainer.new()
		special.add_theme_constant_override("h_separation", 8)
		special.add_theme_constant_override("v_separation", 8)
		body.add_child(special)
		for template: Dictionary in game:
			special.add_child(_card(Wording.icon(template.kind), template.title, template.about, EditorTheme.category_color(template.kind), func() -> void: task_requested.emit(template)))
	_section("Continue writing")
	var recent: Array = workspace.rows.filter(func(row: Dictionary) -> bool: return row.doc.writable and row.def.type not in ["pack", "image", "values"])
	recent.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		if a.doc.dirty() != b.doc.dirty(): return a.doc.dirty()
		return Wording.order(a.def.type) < Wording.order(b.def.type))
	if recent.is_empty(): body.add_child(AuthoringLayout.label("Nothing yet. What you make appears here, with hints about what it still needs.", 14, true))
	for index in mini(recent.size(), 8):
		var row: Dictionary = recent[index]
		var button := Button.new()
		button.alignment = HORIZONTAL_ALIGNMENT_LEFT
		button.theme_type_variation = "Ghost"
		button.text = "%s  %s   ·   %s%s" % [Wording.icon(row.def.type), Wording.title(row), "   ".join(workspace.hints(row)), "   ● unsaved" if row.doc.dirty() else ""]
		button.tooltip_text = "Open " + Wording.title(row)
		button.clip_text = true
		button.pressed.connect(func() -> void: open_requested.emit(row))
		body.add_child(button)
	if recent.size() > 8: body.add_child(AuthoringLayout.label("… and %d more in the library on the left." % (recent.size() - 8), 13, true))
	var errors: Array = workspace.diagnostics.filter(func(item: Dictionary) -> bool: return item.severity == "error")
	_section("Check your work", "The game engine checks the pack, unsaved changes included.")
	for index in mini(errors.size(), 5):
		var diagnostic: Dictionary = errors[index]
		var button := Button.new()
		button.alignment = HORIZONTAL_ALIGNMENT_LEFT
		button.theme_type_variation = "Ghost"
		button.text = "⚠  " + str(diagnostic.message)
		button.clip_text = true
		button.tooltip_text = "%s, line %d. Choose to open it." % [str(diagnostic.path).get_file(), int(diagnostic.line)]
		button.add_theme_color_override("font_color", EditorTheme.color("bad"))
		button.pressed.connect(func() -> void: problem_requested.emit(diagnostic))
		body.add_child(button)
	var check := Button.new()
	var unsaved := workspace.dirty_count()
	check.text = ("✓ No problems found" if errors.is_empty() else "⚠ %d problem%s" % [errors.size(), "" if errors.size() == 1 else "s"]) + "   ·   Check again" + ("   ·   %d unsaved file%s" % [unsaved, "" if unsaved == 1 else "s"] if unsaved > 0 else "")
	check.pressed.connect(func() -> void: check_requested.emit())
	body.add_child(check)
	_fit()
