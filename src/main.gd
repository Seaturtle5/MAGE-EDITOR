extends Control

const GROUPS := {
	"All": [], "Events": ["event", "hook"], "Stories": ["scene", "menu", "text", "epilogue"],
	"Items": ["item"], "Characters": ["character"], "Creatures": ["creature", "form"],
	"Places": ["location", "zone", "region", "door"], "Quests": ["quest"],
	"Rules": ["values", "condition", "meter", "heat", "captivity", "feat", "ending", "tag", "filter", "level", "interest"],
	"Other": [], "Pack": ["pack"], "Files": []
}

var workspace := PackWorkspace.new()
var selected: Dictionary = {}
var group := "All"
var updating := false
var pending_action := ""
var pending_path := ""
var source: StoryWriter
var writing: StoryWriter
var field_editor: TextEdit
var field_picker: OptionButton
var script_picker: OptionButton
var browser: Tree
var references: ReferenceList
var values_list: ItemList
var values_search: LineEdit
var diagnostics_list: ItemList
var tabs: TabContainer
var status: Label
var heading: Label
var detail: Label
var pack_label: Label
var search: LineEdit
var reference_search: LineEdit
var dialog: FileDialog
var confirm: ConfirmationDialog
var message: AcceptDialog
var new_dialog: ConfirmationDialog
var new_layout: AuthoringLayout
var new_validation_error := ""
var new_step := 0
var new_pages: Array[Control] = []
var new_back: Button
var new_review: VBoxContainer
var new_story_text: TextEdit
var new_story_caption: Label
var new_link: Dictionary = {}
var new_type: OptionButton
var new_id: LineEdit
var new_name: LineEdit
var new_help: Label
var new_mode: OptionButton
var new_advanced: VBoxContainer
var new_id_edited := false
var new_type_buttons: Dictionary = {}
var story_canvas: StoryCanvas
var visual_details: VisualDetails
var world_canvas: WorldCanvas
var viewing_world_heading := false
var pack_dialog: ConfirmationDialog
var pack_id: LineEdit
var pack_name: LineEdit
var pack_parent := ""
var image_file_dialog: FileDialog
var image_info_dialog: ConfirmationDialog
var image_source := ""
var image_id: LineEdit
var image_artist: LineEdit
var image_link: LineEdit
var side_panel: VBoxContainer
var side_tabs: TabContainer
var side_toggle: Button
var reference_scope := "all"
var reference_count: Label
var background: ColorRect
var theme_picker: OptionButton
var new_triggers: EventTriggers

var story_editor: StoryEditor
var home: PackHome
var wizard: TaskWizard
var palette: CommandPalette
var drafts := DraftAutosave.new()
var recovery_dialog: ConfirmationDialog
var recovery_pending := false
var undo_button: Button
var redo_button: Button
var save_state: Button
var tour: AcceptDialog
var tour_step := 0
var tour_text: Label
var import_queue: Array[String] = []
var drops: ContentDropMenu
var navigation: HBoxContainer
var nav_buttons: Dictionary = {}
var category_buttons: Dictionary = {}
var check_state: Button
var settings_panel: PopupPanel
var toast_undo: Button
var crumbs: Label
var actions: ContentActions
var content_tools: HBoxContainer
var value_title: Label
var history_dialog: AcceptDialog
var history_list: ItemList
var visited: Array[Dictionary] = []
var visit_at := -1
var visiting := false
var back_button: Button
var forward_button: Button
var value_uses: ItemList
var playtest := Playtest.new()
var play_menu: MenuButton
var find_button: Button
var help_button: Button
var compact := false
var create_button: Button
const SCALES := [90, 100, 110, 125, 150]
const GROUP_ICONS := {"Events": "⚡", "Stories": "💬", "Items": "🎒", "Characters": "👤", "Creatures": "⚔", "Places": "📍", "Quests": "🏁", "Rules": "🔢", "Other": "…", "Pack": "📦", "Files": "🗎"}

func _ready() -> void:
	get_window().title = "MAGE:EDITOR"
	get_tree().auto_accept_quit = false
	_build_theme()
	_apply_scale()
	_build_ui()
	_build_workflow()
	workspace.history.changed.connect(_history_changed)
	workspace.checked.connect(_on_checked)
	workspace.packs_loaded.connect(_on_packs_loaded)
	get_window().files_dropped.connect(_files_dropped)
	var timer := Timer.new()
	timer.wait_time = 30
	timer.timeout.connect(_autosave)
	add_child(timer)
	timer.start()
	var saved_pack := str(_preference("workspace", "last_pack", ""))
	if not saved_pack.is_empty() and FileAccess.file_exists(saved_pack.path_join("pack.fsc")):
		_open_target(saved_pack)
		return
	var example := ProjectSettings.globalize_path("res://example-pack")
	if FileAccess.file_exists(example.path_join("pack.fsc")):
		var working := OS.get_user_data_dir().path_join("packs/example-adventure")
		if not FileAccess.file_exists(working.path_join("pack.fsc")):
			PackWorkspace._copy_folder(example, working)
		_open_target(working)
	else:
		_set_status("Open a pack to start writing.")

func _process(_delta: float) -> void:
	workspace.poll()

## A check on another thread has brought its result.
func _on_checked() -> void:
	_refresh_diagnostics()
	if story_editor != null: story_editor.problems_changed()
	if home != null and tabs.current_tab == 6: home.refresh(workspace)
	if check_wanted:
		check_wanted = false
		_report_check()

## The packs beside the working pack are in.
func _on_packs_loaded(count: int, refused: Dictionary) -> void:
	_refresh_all()
	_set_status("%d pack%s loaded to use %s content%s. They cannot be changed here." % [count, "" if count == 1 else "s", "its" if count == 1 else "their", " (%d could not be added)" % refused.size() if not refused.is_empty() else ""])
	workspace.request_check()
	_refresh_diagnostics()

var check_wanted := false

func _build_theme() -> void:
	var preferences := ConfigFile.new()
	if preferences.load(OS.get_user_data_dir().path_join("preferences.cfg")) == OK:
		EditorTheme.light = preferences.get_value("appearance", "cream", false) == true
	theme = EditorTheme.build()

func _change_theme(index: int) -> void:
	EditorTheme.light = index == 1
	theme = EditorTheme.build()
	background.color = EditorTheme.color("bg")
	_refresh_all()
	var preferences := ConfigFile.new()
	var path := OS.get_user_data_dir().path_join("preferences.cfg")
	preferences.load(path)
	preferences.set_value("appearance", "cream", EditorTheme.light)
	if preferences.save(path) != OK:
		_set_status("Theme changed for this session; the preference could not be saved.")

func _label(text: String, size: int = 15) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", size)
	return label

func _button(text: String, callback: Callable, tooltip: String = "") -> Button:
	var button := Button.new()
	button.text = text
	button.tooltip_text = tooltip
	button.pressed.connect(callback)
	return button

func _spacer() -> Control:
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return spacer

func _build_ui() -> void:
	background = ColorRect.new()
	background.color = EditorTheme.color("bg")
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(background)
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side in ["margin_left", "margin_right", "margin_top", "margin_bottom"]:
		margin.add_theme_constant_override(side, 10)
	add_child(margin)
	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 8)
	margin.add_child(root)
	# One line on top: the pack, undo, find, create, and whether all is well.
	var bar := HBoxContainer.new()
	bar.add_theme_constant_override("separation", 6)
	root.add_child(bar)
	var logo := _label("MAGE", 19)
	bar.add_child(logo)
	var subtitle := _label(":EDITOR", 19)
	subtitle.theme_type_variation = "AccentLabel"
	bar.add_child(subtitle)
	var fit := func() -> void:
		# A narrow window keeps every button, with fewer words.
		logo.visible = size.x >= 1240
		subtitle.visible = logo.visible
		compact = size.x < 1100
		find_button.text = "🔍" if compact else "🔍 Find anything"
		create_button.text = "+" if compact else "+ Create"
		play_menu.text = "▶" if compact else "▶ Play"
		if back_button != null:
			back_button.visible = not compact
			forward_button.visible = not compact
			help_button.text = "?" if compact else "? Help"
		_refresh_diagnostics()
		_history_changed()
	resized.connect(fit)
	fit.call_deferred()
	var file_menu := MenuButton.new()
	file_menu.text = "Pack ▾"
	file_menu.flat = false
	file_menu.tooltip_text = "Create or open a pack, add other packs to use their content, import pictures."
	var popup := file_menu.get_popup()
	for entry: Array in [["New pack…", 0], ["Open pack…", 1], ["Add another pack to use its content…", 2], ["Import a picture…", 3], ["", -1], ["Check pack", 5], ["Save all      Ctrl+S", 6], ["History of changes…", 7], ["Find and replace in story text…      Ctrl+H", 8], ["How the packs depend on each other…", 9], ["", -1], ["Delete the selected content…", 4]]:
		if entry[1] < 0: popup.add_separator()
		else: popup.add_item(entry[0], entry[1])
	popup.id_pressed.connect(_on_pack_menu)
	bar.add_child(file_menu)
	pack_label = _label("No pack open", 16)
	pack_label.clip_text = true
	pack_label.custom_minimum_size.x = 90
	pack_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bar.add_child(pack_label)
	undo_button = _button("⟲", _undo, "Undo the last change (Ctrl+Z).")
	bar.add_child(undo_button)
	redo_button = _button("⟳", _redo, "Redo (Ctrl+Shift+Z).")
	bar.add_child(redo_button)
	find_button = _button("🔍 Find anything", _find_anything, "Find anything: jump to any content, story text or value, or run a command (Ctrl+K).")
	bar.add_child(find_button)
	create_button = _button("+ Create", _show_new, "Create a story, character, item or other content.")
	create_button.theme_type_variation = "PrimaryButton"
	bar.add_child(create_button)
	play_menu = MenuButton.new()
	play_menu.text = "▶ Play"
	play_menu.flat = false
	play_menu.tooltip_text = "Try your pack in the real game, in its own window with its own saves."
	play_menu.about_to_popup.connect(_fill_play_menu)
	play_menu.get_popup().id_pressed.connect(_play_chosen)
	bar.add_child(play_menu)
	check_state = _button("✓ Check", _validate, "Check the pack with the game engine and list any problems.")
	bar.add_child(check_state)
	save_state = _button("💾 Saved", _save_all, "Write your changes to the pack's files (Ctrl+S).")
	bar.add_child(save_state)
	side_toggle = _button("☰", _toggle_side_panel, "Show or hide the lists of saved values and problems.")
	bar.add_child(side_toggle)
	var settings := _button("⚙", func() -> void: settings_panel.popup(Rect2i(Vector2i(get_window().size.x - 330, 52), Vector2i(310, 0))), "Appearance, interface size and technical views.")
	bar.add_child(settings)
	settings_panel = PopupPanel.new()
	add_child(settings_panel)
	var settings_body := VBoxContainer.new()
	settings_body.custom_minimum_size.x = 290
	settings_panel.add_child(settings_body)
	settings_body.add_child(_label("Appearance", 13))
	theme_picker = OptionButton.new()
	theme_picker.add_item("MAGE Dark")
	theme_picker.add_item("Cream Light")
	theme_picker.select(1 if EditorTheme.light else 0)
	theme_picker.tooltip_text = "Choose the editor appearance. Your choice is remembered."
	theme_picker.item_selected.connect(_change_theme)
	settings_body.add_child(theme_picker)
	settings_body.add_child(_label("Interface size", 13))
	var scale_picker := OptionButton.new()
	for percent: int in SCALES: scale_picker.add_item("%d%%" % percent)
	scale_picker.select(maxi(0, SCALES.find(int(_preference("appearance", "scale", 100)))))
	scale_picker.item_selected.connect(func(index: int) -> void:
		_set_preference("appearance", "scale", SCALES[index])
		_apply_scale())
	settings_body.add_child(scale_picker)
	var motion := CheckButton.new()
	motion.text = "Reduce motion"
	motion.tooltip_text = "Switch off fades and other movement."
	motion.button_pressed = bool(_preference("appearance", "reduce_motion", false))
	motion.toggled.connect(func(enabled: bool) -> void:
		_set_preference("appearance", "reduce_motion", enabled)
		if story_canvas != null and story_canvas.bubbles != null:
			story_canvas.bubbles.still = enabled
			story_canvas.bubbles.queue_redraw())
	settings_body.add_child(motion)
	var advanced := CheckButton.new()
	advanced.text = "Technical views"
	advanced.tooltip_text = "Show the content format's text views. Not needed for writing."
	advanced.toggled.connect(_toggle_advanced)
	settings_body.add_child(advanced)
	var split := HSplitContainer.new()
	split.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_child(split)
	# Left: everything in the working pack and the other packs, to choose or drag.
	var left := VBoxContainer.new()
	left.custom_minimum_size.x = 236
	split.add_child(left)
	var library_title := _label("LIBRARY", 13)
	library_title.theme_type_variation = "MutedLabel"
	library_title.tooltip_text = "Choose an entry to open it, or drag it into a story, onto the map or onto a matching picker."
	left.add_child(library_title)
	search = LineEdit.new()
	search.placeholder_text = "Search the library…"
	search.clear_button_enabled = true
	search.text_changed.connect(func(_text: String) -> void: _refresh_browser())
	left.add_child(search)
	var kinds := HFlowContainer.new()
	kinds.add_theme_constant_override("h_separation", 2)
	kinds.add_theme_constant_override("v_separation", 2)
	left.add_child(kinds)
	var kind_group := ButtonGroup.new()
	for category: String in GROUPS:
		var button := Button.new()
		button.text = "All" if category == "All" else str(GROUP_ICONS.get(category, category))
		button.tooltip_text = "Show everything" if category == "All" else "Show only: " + category
		button.toggle_mode = true
		button.button_group = kind_group
		button.button_pressed = category == "All"
		button.theme_type_variation = "Ghost"
		button.pressed.connect(func() -> void:
			group = category
			_refresh_browser()
			if group == "Places" and world_canvas != null: _navigate(5))
		kinds.add_child(button)
		category_buttons[category] = button
	browser = ContentLibrary.new()
	browser.hide_root = true
	browser.size_flags_vertical = Control.SIZE_EXPAND_FILL
	browser.open_requested.connect(_on_browser_selected)
	browser.item_collapsed.connect(_fill_library_section)
	left.add_child(browser)
	var hint := _label("Drag entries into a story or onto the map.", 12)
	hint.theme_type_variation = "MutedLabel"
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	left.add_child(hint)
	var center_split := HSplitContainer.new()
	center_split.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	split.add_child(center_split)
	# Centre: the four places.
	var center := VBoxContainer.new()
	center.custom_minimum_size.x = 300
	center.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	center_split.add_child(center)
	navigation = HBoxContainer.new()
	navigation.add_theme_constant_override("separation", 2)
	center.add_child(navigation)
	back_button = _button("‹", _go_back, "Back to what you looked at before (Alt+←).")
	back_button.theme_type_variation = "Ghost"
	navigation.add_child(back_button)
	forward_button = _button("›", _go_forward, "Forward again (Alt+→).")
	forward_button.theme_type_variation = "Ghost"
	navigation.add_child(forward_button)
	var nav_group := ButtonGroup.new()
	for place: Array in [["🏠 Home", 6, "Start here: tasks, recent work and problems."], ["💬 Stories", 3, "The board of stories and how they connect."], ["🧭 Map", 5, "Places, the paths between them and what happens there."], ["📋 Details", 4, "Everything about the selected content."]]:
		var button := _button(place[0], _navigate.bind(place[1]), place[2])
		button.toggle_mode = true
		button.button_group = nav_group
		button.theme_type_variation = "StepButton"
		navigation.add_child(button)
		nav_buttons[place[1]] = button
	help_button = _button("? Help", _show_tour, "A short tour of the editor.")
	help_button.theme_type_variation = "Ghost"
	navigation.add_child(help_button)
	var context := HBoxContainer.new()
	center.add_child(context)
	heading = _label("Choose something to edit", 20)
	heading.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	heading.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	heading.size_flags_stretch_ratio = 2.0
	context.add_child(heading)
	detail = _label("Select an entry in the library.", 13)
	detail.theme_type_variation = "MutedLabel"
	detail.clip_text = true
	detail.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	context.add_child(detail)
	content_tools = HBoxContainer.new()
	content_tools.add_theme_constant_override("separation", 2)
	context.add_child(content_tools)
	tabs = TabContainer.new()
	tabs.tab_changed.connect(_on_tab_changed)
	tabs.size_flags_vertical = Control.SIZE_EXPAND_FILL
	center.add_child(tabs)
	_build_writing_tab()
	_build_fields_tab()
	_build_source_tab()
	_build_graph_tab()
	_build_visual_details()
	_build_world_tab()
	home = PackHome.new()
	home.name = "Home"
	tabs.add_child(home)
	home.task_requested.connect(_start_task)
	home.open_requested.connect(_open_world_content)
	home.check_requested.connect(_validate)
	home.create_requested.connect(_show_new)
	home.problem_requested.connect(_open_problem)
	tabs.tabs_visible = false
	tabs.current_tab = 3
	tabs.set_tab_title(0, "Advanced story")
	tabs.set_tab_title(1, "Advanced fields")
	tabs.set_tab_title(2, "Advanced file")
	for i in 3:
		tabs.set_tab_hidden(i, true)
	category_buttons["Files"].hide()
	# Right: the selected story as blocks, with its preview.
	story_editor = StoryEditor.new()
	center_split.add_child(story_editor)
	story_editor.hide()
	story_editor.changed.connect(_on_canvas_changed)
	story_editor.problem.connect(_show_error)
	story_editor.try_requested.connect(func(row: Dictionary) -> void: _play({"start": Playtest.place_for(workspace, row)}, Playtest.story_id(row)))
	story_editor.open_requested.connect(func(type: String, id: String) -> void:
		for row: Dictionary in workspace.rows:
			if row.def.id == id and row.def.type in ([type, "menu"] if type == "scene" else [type]) and row.def.mode != "extend":
				_open_world_content(row)
				return)
	story_editor.validated.connect(func() -> void:
		_refresh_diagnostics()
		_history_changed())
	story_editor.blocks_chosen.connect(story_canvas.show_blocks)
	story_canvas.graph.node_selected.connect(func(node: Node) -> void:
		if story_canvas.graph_rows.has(node.name):
			story_editor.show_story(workspace, story_canvas.graph_rows[node.name])
			story_editor.visible = tabs.current_tab == 3
			_refresh_crumbs())
	side_panel = VBoxContainer.new()
	side_panel.custom_minimum_size.x = 270
	center_split.add_child(side_panel)
	side_panel.hide()
	side_tabs = TabContainer.new()
	side_tabs.size_flags_vertical = Control.SIZE_EXPAND_FILL
	side_panel.add_child(side_tabs)
	var ref_box := VBoxContainer.new()
	ref_box.name = "Packs"
	side_tabs.add_child(ref_box)
	ref_box.add_child(_label("Find content in your loaded packs", 13))
	var scope := HBoxContainer.new()
	var scope_group := ButtonGroup.new()
	for filter in ["All", "My pack", "Other packs"]:
		var scope_button := Button.new()
		scope_button.text = filter
		scope_button.toggle_mode = true
		scope_button.button_group = scope_group
		scope_button.button_pressed = filter == "All"
		scope_button.pressed.connect(_set_reference_scope.bind(filter))
		scope.add_child(scope_button)
	ref_box.add_child(scope)
	reference_search = LineEdit.new()
	reference_search.placeholder_text = "Search names, kinds and packs…"
	reference_search.text_changed.connect(func(_text: String) -> void: _refresh_references())
	ref_box.add_child(reference_search)
	references = ReferenceList.new()
	references.size_flags_vertical = Control.SIZE_EXPAND_FILL
	references.item_activated.connect(_open_reference_definition)
	ref_box.add_child(references)
	reference_count = _label("", 12)
	ref_box.add_child(reference_count)
	ref_box.add_child(_button("Require the selected entry's pack", _declare_selected_dependency, "Adds the pack to the packs your pack needs."))
	var values_box := VBoxContainer.new()
	values_box.name = "Values"
	side_tabs.add_child(values_box)
	values_box.add_child(_label("COUNTERS, THINGS TO REMEMBER AND STAGES", 13))
	values_box.add_child(_label("What the game remembers. Conditions check these; actions change them.", 12))
	values_search = LineEdit.new()
	values_search.placeholder_text = "Search saved values…"
	values_search.text_changed.connect(func(_text: String) -> void: _refresh_values())
	values_box.add_child(values_search)
	values_list = ItemList.new()
	values_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	values_list.item_selected.connect(_inspect_value)
	values_box.add_child(values_list)
	value_title = _label("Choose a value to see where it is changed and read.", 13)
	value_title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	values_box.add_child(value_title)
	value_uses = ItemList.new()
	value_uses.size_flags_vertical = Control.SIZE_EXPAND_FILL
	value_uses.item_activated.connect(func(index: int) -> void:
		var use: Variant = value_uses.get_item_metadata(index)
		if use is Dictionary: _open_line(use.row.doc.path, int(use.line)))
	values_box.add_child(value_uses)
	var diag_box := VBoxContainer.new()
	diag_box.name = "Problems"
	side_tabs.add_child(diag_box)
	diag_box.add_child(_label("PROBLEMS FOUND BY THE GAME ENGINE", 13))
	diag_box.add_child(_label("Double-click a problem to open the place it is in.", 12))
	diagnostics_list = ItemList.new()
	diagnostics_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	diagnostics_list.item_activated.connect(_open_diagnostic)
	diag_box.add_child(diagnostics_list)
	# Bottom: what just happened, with Undo, and where you are.
	var foot := HBoxContainer.new()
	root.add_child(foot)
	status = _label("", 13)
	status.clip_text = true
	status.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	foot.add_child(status)
	toast_undo = _button("Undo", _undo, "Undo what just happened.")
	toast_undo.theme_type_variation = "Ghost"
	toast_undo.hide()
	foot.add_child(toast_undo)
	crumbs = _label("", 13)
	crumbs.theme_type_variation = "MutedLabel"
	crumbs.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	crumbs.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	crumbs.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	foot.add_child(crumbs)
	_build_dialogs()

func _apply_scale() -> void:
	get_window().content_scale_factor = float(_preference("appearance", "scale", 100)) / 100.0

func _toggle_side_panel() -> void:
	_set_side_panel(not side_panel.visible)

func _on_pack_menu(id: int) -> void:
	match id:
		0: _choose_new_pack()
		1: _choose_target()
		2: _choose_reference()
		3: _choose_image()
		4: _ask_delete()
		5: _validate()
		6: _save_all()
		7: _show_history()
		8: actions.find_and_replace()
		9: actions.show_dependencies()

func _set_side_panel(open: bool) -> void:
	side_panel.visible = open
	side_toggle.button_pressed = open
	if open:
		_refresh_references()
		_refresh_values()

func _set_reference_scope(scope: String) -> void:
	reference_scope = scope
	_refresh_references()

func _build_writing_tab() -> void:
	var box := VBoxContainer.new()
	box.name = "Writing"
	tabs.add_child(box)
	box.add_child(_label("STORY", 13))
	var tools := HBoxContainer.new()
	box.add_child(tools)
	script_picker = OptionButton.new()
	script_picker.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	script_picker.item_selected.connect(_select_script)
	tools.add_child(script_picker)
	tools.add_child(_button("+ Choice", func() -> void: _insert_at_writer("\n* Choice\n    What happens next.\n")))
	tools.add_child(_button("+ If", func() -> void: _insert_at_writer("\nif player.hp > 0:\n    What happens when true.\nelse:\n    What happens otherwise.\n")))
	tools.add_child(_button("+ Page", func() -> void: _insert_at_writer("\n---\n")))
	tools.add_child(_button("+ Link", func() -> void: _insert_at_writer("-> ")))
	box.add_child(_label("Write prose and choices here. Search for an ID or value on the right and drag or double-click to insert it.", 12))
	writing = StoryWriter.new()
	writing.size_flags_vertical = Control.SIZE_EXPAND_FILL
	writing.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
	writing.text_changed.connect(_writing_changed)
	box.add_child(writing)

func _build_fields_tab() -> void:
	var box := VBoxContainer.new()
	box.name = "Fields"
	tabs.add_child(box)
	box.add_child(_label("DEFINITION FIELDS", 13))
	box.add_child(_label("Fields come from the current MAGE engine. Choose a field to edit it.", 12))
	field_picker = OptionButton.new()
	field_picker.item_selected.connect(_select_field)
	box.add_child(field_picker)
	field_editor = TextEdit.new()
	field_editor.size_flags_vertical = Control.SIZE_EXPAND_FILL
	field_editor.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
	field_editor.text_changed.connect(_field_changed)
	box.add_child(field_editor)
	box.add_child(_label("Indented blocks and unfamiliar fields are also available in Source.", 12))

func _build_source_tab() -> void:
	var box := VBoxContainer.new()
	box.name = "Source"
	tabs.add_child(box)
	box.add_child(_label("COMPLETE CONTENT FILE", 13))
	box.add_child(_label("The whole .fsc file is editable, including comments and fields not represented by the forms. IDs are used by saved games.", 12))
	source = StoryWriter.new()
	source.size_flags_vertical = Control.SIZE_EXPAND_FILL
	source.gutters_draw_line_numbers = true
	source.text_changed.connect(_source_changed)
	box.add_child(source)

func _build_dialogs() -> void:
	dialog = FileDialog.new()
	dialog.access = FileDialog.ACCESS_FILESYSTEM
	dialog.file_mode = FileDialog.FILE_MODE_OPEN_DIR
	dialog.dir_selected.connect(_directory_selected)
	add_child(dialog)
	confirm = ConfirmationDialog.new()
	confirm.confirmed.connect(_confirmed)
	add_child(confirm)
	message = AcceptDialog.new()
	add_child(message)
	new_dialog = ConfirmationDialog.new()
	new_dialog.title = "Create content"
	new_dialog.dialog_hide_on_ok = false
	new_layout = AuthoringLayout.new()
	new_layout.custom_minimum_size = Vector2(720, 380)
	new_dialog.add_child(new_layout)
	add_child(new_dialog)
	new_layout.footer.hide()
	new_layout.section_requested.connect(func(key: String) -> void: _go_new_step(int(key)))
	var type_page := VBoxContainer.new()
	new_layout.page.add_child(type_page)
	new_pages.append(type_page)
	type_page.add_child(AuthoringLayout.label("What would you like to create?", 24))
	type_page.add_child(AuthoringLayout.label("Choose a starting point. You can write the opening in the next step.", 15, true))
	var choices := GridContainer.new()
	choices.columns = 2
	var type_group := ButtonGroup.new()
	for entry: Array in [["Story", "scene", "A passage with choices and a next step."], ["Conversation", "menu", "A set of responses the player can choose."], ["Event", "event", "Something that happens at a place or in a zone."], ["Character", "character", "Someone to meet and talk to."], ["Creature", "creature", "An encounter in the game world."], ["Item", "item", "Something to find, carry or use."], ["Place", "location", "A room or destination to visit."], ["Quest", "quest", "Progress through an ongoing story."], ["Saved values", "values", "Flags and values that remember progress."]]:
		var button := AuthoringLayout.choice(entry[0], entry[2])
		button.toggle_mode = true
		button.button_group = type_group
		button.pressed.connect(_set_new_type.bind(entry[1]))
		new_type_buttons[entry[1]] = button
		choices.add_child(button)
	type_page.add_child(choices)
	var form := VBoxContainer.new()
	new_layout.page.add_child(form)
	new_pages.append(form)
	form.add_child(AuthoringLayout.label("Give it a name and a beginning", 24))
	new_help = AuthoringLayout.label("", 15, true)
	form.add_child(new_help)
	form.add_child(_label("Name", 14))
	new_name = LineEdit.new()
	new_name.placeholder_text = "For example, An unexpected visitor"
	new_name.text_changed.connect(_new_name_changed)
	form.add_child(new_name)
	new_triggers = EventTriggers.new()
	form.add_child(new_triggers)
	new_triggers.hide()
	new_triggers.edited.connect(_refresh_new_summary)
	new_story_caption = _label("Opening passage (optional)", 14)
	form.add_child(new_story_caption)
	new_story_text = TextEdit.new()
	new_story_text.custom_minimum_size.y = 130
	new_story_text.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
	new_story_text.placeholder_text = "Write what the player sees or hears. Add responses and actions on the story board afterwards."
	new_story_text.text_changed.connect(_refresh_new_summary)
	form.add_child(new_story_text)
	var options := CheckButton.new()
	options.text = "More types and ID options"
	form.add_child(options)
	new_advanced = VBoxContainer.new()
	form.add_child(new_advanced)
	new_advanced.hide()
	options.toggled.connect(func(enabled: bool) -> void: new_advanced.visible = enabled)
	new_advanced.add_child(_label("Content type"))
	new_type = OptionButton.new()
	for type: String in PackWorkspace.types():
		if type != "pack": new_type.add_item(type)
	new_type.item_selected.connect(func(_index: int) -> void: _set_new_type(new_type.get_item_text(new_type.selected)))
	new_advanced.add_child(new_type)
	new_advanced.add_child(_label("Stable ID (used by saved games and links)"))
	new_id = LineEdit.new()
	new_id.text_changed.connect(func(_text: String) -> void:
		if new_id.has_focus(): new_id_edited = true
		_refresh_new_summary())
	new_advanced.add_child(new_id)
	new_advanced.add_child(_label("Definition mode"))
	new_mode = OptionButton.new()
	for title: String in ["New definition", "Extend reference content", "Replace reference content"]: new_mode.add_item(title)
	new_mode.item_selected.connect(func(_index: int) -> void: _refresh_new_summary())
	new_advanced.add_child(new_mode)
	new_review = VBoxContainer.new()
	new_layout.page.add_child(new_review)
	new_pages.append(new_review)
	new_back = new_dialog.add_button("‹ Back", false)
	new_back.pressed.connect(func() -> void: _go_new_step(new_step - 1))
	new_dialog.get_ok_button().theme_type_variation = "PrimaryButton"
	new_dialog.confirmed.connect(_advance_new)
	pack_dialog = ConfirmationDialog.new()
	pack_dialog.title = "Create a pack"
	pack_dialog.ok_button_text = "Create pack"
	var pack_form := VBoxContainer.new()
	pack_form.custom_minimum_size = Vector2(420, 0)
	pack_dialog.add_child(pack_form)
	pack_form.add_child(_label("Pack ID (lowercase letters, numbers, underscores or hyphens)"))
	pack_id = LineEdit.new()
	pack_id.placeholder_text = "my-adventure"
	pack_form.add_child(pack_id)
	pack_form.add_child(_label("Name"))
	pack_name = LineEdit.new()
	pack_name.placeholder_text = "My Adventure"
	pack_form.add_child(pack_name)
	pack_dialog.confirmed.connect(_create_pack)
	add_child(pack_dialog)
	image_file_dialog = FileDialog.new()
	image_file_dialog.access = FileDialog.ACCESS_FILESYSTEM
	image_file_dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILE
	image_file_dialog.title = "Choose an image"
	image_file_dialog.filters = PackedStringArray(["*.png, *.jpg, *.jpeg, *.webp ; Images"])
	image_file_dialog.file_selected.connect(_image_selected)
	add_child(image_file_dialog)
	image_info_dialog = ConfirmationDialog.new()
	image_info_dialog.title = "Import image and credit"
	image_info_dialog.ok_button_text = "Import"
	var image_form := VBoxContainer.new()
	image_form.custom_minimum_size = Vector2(420, 0)
	image_info_dialog.add_child(image_form)
	image_form.add_child(_label("Image ID"))
	image_id = LineEdit.new()
	image_form.add_child(image_id)
	image_form.add_child(_label("Artist"))
	image_artist = LineEdit.new()
	image_form.add_child(image_artist)
	image_form.add_child(_label("Credit link (optional)"))
	image_link = LineEdit.new()
	image_form.add_child(image_link)
	image_form.add_child(_label("The image is copied immediately; save the credit with Save all.", 12))
	image_info_dialog.dialog_hide_on_ok = false
	image_info_dialog.confirmed.connect(_import_image)
	image_info_dialog.canceled.connect(func() -> void: _next_import.call_deferred())
	add_child(image_info_dialog)

func _set_status(text: String, undoable: bool = false) -> void:
	status.text = text
	toast_undo.visible = undoable and workspace.history.cursor > 0

var play_choices: Array[Dictionary] = []

func _fill_play_menu() -> void:
	var popup := play_menu.get_popup()
	popup.clear()
	play_choices.clear()
	var add := func(label: String, begin: Dictionary, play: String) -> void:
		popup.add_item(label, play_choices.size())
		play_choices.append({"begin": begin, "play": play})
	var story: Dictionary = story_editor.row if tabs.current_tab == 3 and story_editor != null else {}
	if not story.is_empty() and not Playtest.story_id(story).is_empty():
		add.call("Try this story: " + Wording.title(story) + " › " + StoryEditor.story_name(story), {"start": Playtest.place_for(workspace, story)}, Playtest.story_id(story))
	if not selected.is_empty() and selected.has("def") and selected.def.type == "location":
		add.call("Start at this place: " + Wording.title(selected), {"start": selected.def.id}, "")
	var scenarios := Playtest.scenarios(workspace)
	for index in mini(scenarios.size(), 6):
		add.call("Play from the start: " + Wording.title(scenarios[index]), {"scenario": scenarios[index].def.id}, "")
	if scenarios.is_empty() and play_choices.is_empty():
		add.call("Start in a place of your pack", {"start": Playtest.place_for(workspace, {})}, "")
	if playtest.running():
		popup.add_separator()
		popup.add_item("Stop the game", 1000)
	popup.add_separator()
	popup.add_item("The game opens in its own window, with its own saves.", 1001)
	popup.set_item_disabled(popup.item_count - 1, true)

func _play_chosen(id: int) -> void:
	if id == 1000:
		playtest.stop()
		_set_status("The game was stopped.")
		return
	if id < 0 or id >= play_choices.size(): return
	_play(play_choices[id].begin, str(play_choices[id].play))

## Starts the real game on the pack as it is now, for the preview's sample player.
func _play(begin: Dictionary, play: String = "") -> void:
	if not _entries_ready(): return
	var preview := story_editor.preview
	var sample := {"sex": ["female", "male", "herm", "neuter"][preview.sample.selected], "level": preview.sample_level, "values": preview.overrides} if not play.is_empty() else {}
	var error := playtest.run(workspace, begin, play, sample)
	_refresh_diagnostics()
	if not error.is_empty():
		_show_error(error)
		return
	_set_status("The game is starting in its own window" + (", with your unsaved changes" if workspace.dirty_count() > 0 else "") + ". It uses its own saves; nothing here changes.")

## Every change so far, newest first. Choosing one undoes or redoes up to it.
func _show_history() -> void:
	if history_dialog == null:
		history_dialog = AcceptDialog.new()
		history_dialog.title = "History of changes"
		history_dialog.ok_button_text = "Close"
		var body := VBoxContainer.new()
		history_dialog.add_child(body)
		body.add_child(AuthoringLayout.label("Double-click a change to go back to just after it. Later changes can be brought back with Redo.", 13, true))
		history_list = ItemList.new()
		history_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
		history_list.custom_minimum_size = Vector2(480, 300)
		history_list.item_activated.connect(func(index: int) -> void:
			var wanted: int = history_list.get_item_metadata(index)
			if not _entries_ready(): return
			while workspace.history.cursor > wanted: workspace.undo()
			while workspace.history.cursor < wanted: workspace.redo()
			_after_history("Went back in the history")
			_fill_history())
		body.add_child(history_list)
		add_child(history_dialog)
	_fill_history()
	AuthoringLayout.popup(history_dialog, Vector2i(540, 440))

func _fill_history() -> void:
	history_list.clear()
	var steps := workspace.history.steps
	for index in range(steps.size() - 1, -1, -1):
		var undone: bool = index >= workspace.history.cursor
		history_list.add_item(("↶ " if undone else ("➤ " if index == workspace.history.cursor - 1 else "    ")) + str(steps[index].label) + ("   (undone)" if undone else ""))
		history_list.set_item_metadata(history_list.item_count - 1, index + 1)
	history_list.add_item("    The pack as it was opened")
	history_list.set_item_metadata(history_list.item_count - 1, 0)

## Remembers what is being looked at, for Back and Forward.
func _remember_visit() -> void:
	if visiting or back_button == null: return
	var entry := {"tab": tabs.current_tab}
	if not selected.is_empty() and selected.has("def") and tabs.current_tab != 6:
		entry.merge({"path": selected.doc.path, "type": selected.def.type, "id": selected.def.id, "mode": selected.def.mode, "ordinal": selected.get("ordinal", 0)})
		if tabs.current_tab == 3 and not story_editor.row.is_empty(): entry.story = story_editor.row.get("script_field", "")
	if visit_at >= 0 and visited[visit_at] == entry: return
	visited.resize(visit_at + 1)
	visited.append(entry)
	if visited.size() > 60: visited.pop_front()
	visit_at = visited.size() - 1
	back_button.disabled = visit_at <= 0
	forward_button.disabled = true

func _go_back() -> void:
	_go_visit(visit_at - 1)

func _go_forward() -> void:
	_go_visit(visit_at + 1)

func _go_visit(index: int) -> void:
	if index < 0 or index >= visited.size() or not _entries_ready(): return
	var entry: Dictionary = visited[index]
	visiting = true
	if entry.has("path"):
		var row := workspace.find_row(entry.path, entry.type, entry.id, entry.mode, entry.ordinal)
		if not row.is_empty():
			if str(entry.get("story", "")).is_empty(): _open_world_content(row)
			else: _open_visual_script(row, str(entry.story))
	_navigate(int(entry.tab))
	visiting = false
	visit_at = index
	back_button.disabled = visit_at <= 0
	forward_button.disabled = visit_at >= visited.size() - 1

## Where the author is: pack, kind, content and story.
func _refresh_crumbs() -> void:
	if crumbs == null: return
	var parts: Array[String] = [str(workspace.manifest(workspace.target).get("id", "No pack"))]
	if tabs.current_tab == 6: parts.append("Home")
	elif tabs.current_tab == 5: parts.append("Map")
	if not selected.is_empty() and selected.has("def") and tabs.current_tab != 6:
		parts.append(Wording.plural(selected.def.type))
		parts.append(Wording.title(selected))
	if tabs.current_tab == 3 and story_editor != null and not story_editor.row.is_empty():
		if selected.is_empty() or story_editor.row.def.id != selected.def.id: parts.append(Wording.title(story_editor.row))
		parts.append(StoryEditor.story_name(story_editor.row))
	crumbs.text = " › ".join(parts)
	crumbs.tooltip_text = crumbs.text
	_remember_visit()

func _show_error(text: String) -> void:
	if text.is_empty():
		return
	message.dialog_text = text
	message.popup_centered()

func _choose_new_pack() -> void:
	if not _entries_ready():
		return
	if workspace.dirty_count() > 0:
		_show_error("Save your current changes before creating another pack.")
		return
	pending_action = "new_pack"
	dialog.title = "Choose a folder for your new pack"
	dialog.popup_centered_ratio(0.75)

func _choose_target() -> void:
	if not _entries_ready():
		return
	pending_action = "open"
	dialog.title = "Open working pack folder"
	dialog.popup_centered_ratio(0.75)

func _choose_reference() -> void:
	if not _entries_ready():
		return
	if workspace.target.is_empty():
		_show_error("Open a working pack first.")
		return
	pending_action = "reference"
	dialog.title = "Add another pack, or a folder of packs, to use their content"
	dialog.popup_centered_ratio(0.75)

func _directory_selected(path: String) -> void:
	if pending_action == "new_pack":
		pack_parent = path
		pack_id.text = ""
		pack_name.text = ""
		pack_dialog.popup_centered()
		pack_id.grab_focus()
	elif pending_action == "reference":
		if not FileAccess.file_exists(path.path_join("pack.fsc")):
			# A folder of packs: add every pack inside it.
			var inside: Array = []
			for name: String in DirAccess.get_directories_at(path):
				if FileAccess.file_exists(path.path_join(name).path_join("pack.fsc")) and path.path_join(name) != workspace.target and path.path_join(name) not in workspace.pack_paths: inside.append(path.path_join(name))
			if inside.is_empty():
				_show_error("This folder holds no pack that is not loaded yet. Choose a pack's own folder (the one with pack.fsc), or a folder of packs.")
				return
			_load_packs(inside)
			return
		if path == workspace.target or path in workspace.pack_paths:
			_show_error("This pack is already loaded.")
			return
		if PackWorkspace.read_manifest(path).is_empty():
			_show_error("Choose a folder with a valid pack.fsc.")
			return
		_load_packs([path])
	elif workspace.dirty_count() > 0:
		pending_action = "replace_target"
		pending_path = path
		confirm.dialog_text = "Discard unsaved edits and open another pack? Save first to keep your work."
		confirm.popup_centered()
	else:
		_open_target(path)

## Loads packs to use their content, without holding up the window.
func _load_packs(folders: Array) -> void:
	if workspace.loading:
		_show_error("Packs are still being loaded. Add more when they are in.")
		return
	workspace.load_packs(folders)
	_set_status("Loading %d pack%s to use %s content…" % [folders.size(), "" if folders.size() == 1 else "s", "its" if folders.size() == 1 else "their"])
	_refresh_diagnostics()

func _confirmed() -> void:
	if pending_action == "replace_target":
		if not recovery_pending: drafts.discard(workspace.target)
		_open_target(pending_path)
	elif pending_action == "quit":
		if not recovery_pending: drafts.discard(workspace.target)
		playtest.stop()
		playtest.clear()
		get_window().hide()
		workspace.settle()
		get_tree().quit()
	elif pending_action == "delete":
		_delete_selected()

func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		if not _entries_ready():
			return
		if workspace.dirty_count() == 0:
			playtest.stop()
			playtest.clear()
			get_window().hide()
			workspace.settle()
			get_tree().quit()
		else:
			pending_action = "quit"
			confirm.dialog_text = "Discard unsaved edits and close? Save first to keep your work."
			confirm.popup_centered()

func _open_target(path: String) -> void:
	var error := workspace.open_pack(path)
	if not error.is_empty():
		_show_error(error)
		return
	selected.clear()
	for row: Dictionary in workspace.rows:
		if row.doc.writable and row.def.type == "scene":
			selected = row
			break
	if selected.is_empty() and not workspace.rows.is_empty():
		selected = workspace.rows[0]
	story_canvas.focus_definition(selected)
	var has_story: bool = not selected.is_empty() and selected.def.type in ["scene", "menu", "event", "character"]
	tabs.set_tab_hidden(3, not has_story)
	tabs.current_tab = 3 if has_story else 4
	_refresh_all()
	_set_status("Working pack opened.")
	_set_preference("workspace", "last_pack", workspace.target)
	# The packs that belong with it are loaded behind the scenes; the check follows them.
	var beside: Array = workspace.packs_beside() if bool(_preference("workspace", "load_beside", true)) else []
	if not beside.is_empty(): _load_packs(beside)
	elif workspace.rows.size() > PackWorkspace.LIGHT:
		workspace.request_check()
		_refresh_diagnostics()
	_navigate(6)
	_offer_recovery()
	if DisplayServer.get_name() != "headless" and "--script" not in OS.get_cmdline_args() and not bool(_preference("help", "tour_seen", false)):
		_set_preference("help", "tour_seen", true)
		_show_tour()

func _refresh_all() -> void:
	var timing := Perf.start()
	var info := workspace.manifest(workspace.target)
	var others := maxi(0, workspace.pack_paths.size() - 1)
	pack_label.text = str(workspace.title_of("pack", str(info.get("id", ""))) if not workspace.title_of("pack", str(info.get("id", ""))).is_empty() else info.get("id", "Open a pack")) + ("  ·  uses %d other pack%s" % [others, "" if others == 1 else "s"] if others > 0 else "")
	pack_label.tooltip_text = workspace.target
	_refresh_crumbs()
	_refresh_browser()
	Perf.stop("window: library", timing)
	timing = Perf.start()
	_refresh_references()
	_refresh_values()
	_refresh_diagnostics()
	Perf.stop("window: lists", timing)
	timing = Perf.start()
	_refresh_selection()
	Perf.stop("window: selection", timing)
	timing = Perf.start()
	_refresh_graph()
	Perf.stop("window: board and blocks", timing)
	timing = Perf.start()
	if home != null and tabs.current_tab == 6: home.refresh(workspace)
	_history_changed()
	if world_canvas != null and tabs.current_tab == 5:
		world_canvas.refresh()
	Perf.stop("window: home, history, map", timing)

func _matches_group(type: String) -> bool:
	if group == "All":
		return true
	if group == "Other":
		for category: String in GROUPS:
			if type in GROUPS[category]:
				return false
		return true
	return type in GROUPS[group] or (group == "Rules" and type.ends_with("_rules"))

var library_mark := ""

## What the library lists, as text: it is filled again only when this changes.
func _library_mark() -> String:
	var parts: PackedStringArray = [group, search.text, workspace._reference_cache_key, str(workspace.rows.size())]
	for path: String in workspace._own_rows:
		for row: Dictionary in workspace._own_rows[path].rows:
			parts.append(str(row.sort) + "=" + (str(row.def.fields.name.value) if row.def.fields.has("name") else "") + str(row.def.mode))
	return str("\n".join(parts).hash()) + ":" + str(parts.size())

func _refresh_browser() -> void:
	if browser == null:
		return
	var mark := _library_mark()
	if mark == library_mark and browser.get_root() != null:
		# The same entries: they only need the rows as they are now.
		_renew_library(browser.get_root())
		return
	library_mark = mark
	browser.clear()
	var root := browser.create_item()
	var query := search.text.to_lower()
	if group == "Files":
		var files := browser.create_item(root)
		files.set_text(0, "Files of my pack")
		files.set_selectable(0, false)
		for path: String in workspace.documents:
			var doc: PackDocument = workspace.documents[path]
			if not doc.writable or (not query.is_empty() and query not in path.to_lower()): continue
			var folder := workspace.owner(path)
			var file_item := browser.create_item(files)
			file_item.set_text(0, path.trim_prefix(folder + "/"))
			var placeholder := FscParser.Definition.new()
			placeholder.type = "file"
			placeholder.id = path.get_file()
			placeholder.path = path
			placeholder.line = 1
			file_item.set_metadata(0, {"def": placeholder, "doc": doc, "pack": workspace.manifest(folder).get("id", folder.get_file()), "root": folder})
		return
	# My pack by kind; other packs fold away and fill in when opened.
	var mine: Dictionary = {}
	var others: Dictionary = {}
	for row: Dictionary in workspace.rows:
		var definition: FscParser.Definition = row.def
		if not _matches_group(definition.type): continue
		if not query.is_empty():
			# The words a row is found by are put together once and kept on the row.
			if not row.has("find"): row.find = (Wording.title(row) + " " + definition.id + " " + Wording.name(definition.type) + " " + definition.type + " " + row.pack).to_lower()
			if query not in row.find: continue
		var table: Dictionary = mine if row.doc.writable else others
		var key: String = definition.type if row.doc.writable else row.pack
		if not table.has(key): table[key] = []
		table[key].append(row)
	var own := browser.create_item(root)
	own.set_text(0, "My pack")
	own.set_selectable(0, false)
	var kinds: Array = mine.keys()
	kinds.sort_custom(func(a: String, b: String) -> bool: return Wording.order(a) < Wording.order(b))
	for kind: String in kinds:
		var section := browser.create_item(own)
		section.set_text(0, "%s  %s  (%d)" % [Wording.icon(kind), Wording.plural(kind), mine[kind].size()])
		section.set_selectable(0, false)
		section.set_custom_color(0, EditorTheme.category_color(kind))
		section.collapsed = query.is_empty() and kind in ["pack", "image", "values"] and mine[kind].size() > 6
		for row: Dictionary in mine[kind]: _library_item(section, row, false)
	if mine.is_empty():
		var empty := browser.create_item(own)
		empty.set_text(0, "Nothing matches." if not query.is_empty() or group != "All" else "Nothing yet. Start on Home.")
		empty.set_selectable(0, false)
	var packs: Array = others.keys()
	packs.sort()
	for pack: String in packs:
		var section := browser.create_item(root)
		section.set_text(0, "📦  %s  (%d)" % [pack, others[pack].size()])
		section.set_tooltip_text(0, "Content of another pack: use it in your stories, but it cannot be changed here.")
		section.set_selectable(0, false)
		section.set_metadata(0, {"lazy": others[pack]})
		var waiting := browser.create_item(section)
		waiting.set_text(0, "…")
		waiting.set_selectable(0, false)
		section.collapsed = true
		if not query.is_empty() and others[pack].size() <= 40:
			section.collapsed = false
			_fill_library_section(section)

## Gives every listed entry its row as it is after a change.
func _renew_library(item: TreeItem) -> void:
	while item != null:
		var data: Variant = item.get_metadata(0)
		if data is Dictionary and data.has("def") and data.has("doc") and data.doc.writable and data.def.type != "file":
			var fresh := workspace.find_row(data.doc.path, data.def.type, data.def.id, data.def.mode, data.get("ordinal", 0))
			if not fresh.is_empty(): item.set_metadata(0, fresh)
		if item.get_first_child() != null: _renew_library(item.get_first_child())
		item = item.get_next()

func _library_item(parent: TreeItem, row: Dictionary, with_kind: bool) -> void:
	var item := browser.create_item(parent)
	item.set_text(0, (Wording.icon(row.def.type) + " " if with_kind else "") + Wording.title(row) + ("  [" + str(row.def.mode) + "]" if row.def.mode != "define" else ""))
	item.set_metadata(0, row)
	item.set_tooltip_text(0, Wording.name(row.def.type).capitalize() + " · " + str(row.pack) + "\nDrag into a story or onto the map, or choose to open.")

func _fill_library_section(section: TreeItem) -> void:
	var data: Variant = section.get_metadata(0)
	if section.collapsed or not data is Dictionary or not data.has("lazy"): return
	var rows: Array = data.lazy
	section.set_metadata(0, {})
	for child: TreeItem in section.get_children(): child.free()
	for index in mini(rows.size(), 400): _library_item(section, rows[index], true)
	if rows.size() > 400:
		var more := browser.create_item(section)
		more.set_text(0, "… %d more. Search to find them." % (rows.size() - 400))
		more.set_selectable(0, false)

func _on_browser_selected() -> void:
	if not _entries_ready():
		return
	var item := browser.get_selected()
	if item == null:
		return
	var row: Variant = item.get_metadata(0)
	if row is Dictionary:
		selected = row
		_refresh_selection()
		tabs.set_tab_hidden(3, row.def.type not in ["scene", "menu", "event", "character"])
		if row.def.type == "file":
			tabs.current_tab = 2
		elif row.def.type == "event":
			story_canvas.focus_definition(row)
			tabs.current_tab = 4
		elif row.def.type in ["scene", "menu", "character"]:
			story_canvas.focus_definition(row)
			tabs.current_tab = 3
		elif row.def.type == "location":
			tabs.current_tab = 5
			world_canvas._show_contents(row)
		else:
			tabs.current_tab = 4

func _refresh_selection() -> void:
	# The Details page is drawn when it is looked at.
	if visual_details != null: visual_details.show_definition(workspace, selected, tabs == null or tabs.current_tab == 4)
	if selected.is_empty():
		heading.text = "Choose something to edit"
		detail.text = "Select a definition from the content browser."
	else:
		var d: FscParser.Definition = selected.def
		var doc: PackDocument = selected.doc
		heading.text = Wording.icon(d.type) + " " + Wording.title(selected)
		detail.text = Wording.name(d.type).capitalize() + ("   ·   from the pack “%s”, read-only" % selected.pack if not doc.writable else "")
		detail.tooltip_text = "Technical ID: %s\n%s, line %d" % [d.id, doc.path, d.line]
		_refresh_crumbs()
		_refresh_content_tools()
	# The technical views hold whole files: they are filled when looked at.
	technical_stale = true
	if tabs != null and tabs.current_tab <= 2: _refresh_technical()

var technical_stale := false

## Fills the Writing, Fields and Source views for the selected content.
func _refresh_technical() -> void:
	technical_stale = false
	updating = true
	script_picker.clear()
	field_picker.clear()
	if selected.is_empty():
		writing.text = ""
		field_editor.text = ""
		source.text = ""
		writing.editable = false
		field_editor.editable = false
		source.editable = false
		updating = false
		return
	var d: FscParser.Definition = selected.def
	var doc: PackDocument = selected.doc
	source.text = doc.text
	source.editable = doc.writable
	if d.type in ["scene", "text", "menu"]:
		script_picker.add_item("Story / menu body")
		script_picker.set_item_metadata(0, "@body")
	var schema: Dictionary = ContentDB.SCHEMA.get(d.type, {})
	var keys: Array = schema.keys()
	keys.sort()
	for key: String in keys:
		field_picker.add_item(key + "  ·  " + str(schema[key]))
		field_picker.set_item_metadata(field_picker.item_count - 1, key)
		if schema[key] == "script":
			script_picker.add_item(key.capitalize())
			script_picker.set_item_metadata(script_picker.item_count - 1, key)
	for key: String in d.field_order:
		if not schema.has(key):
			field_picker.add_item(key + "  ·  unrecognized")
			field_picker.set_item_metadata(field_picker.item_count - 1, key)
	updating = false
	_select_script(0)
	_select_field(0)

func _script_body(doc: PackDocument, d: FscParser.Definition) -> String:
	var block := doc.block(d)
	var pos := block.find("\n")
	return block.substr(pos + 1) if pos >= 0 else ""

func _has_field_comments(doc: PackDocument, d: FscParser.Definition, name: String) -> bool:
	if not d.fields.has(name):
		return false
	var field: FscParser.Field = d.fields[name]
	if field.children.is_empty():
		return false
	var lines := doc.text.split("\n")
	for i in range(field.line, field.children[-1].number):
		if i < lines.size() and lines[i].strip_edges().begins_with("//"):
			return true
	return false

func _select_script(index: int) -> void:
	if updating:
		return
	updating = true
	if selected.is_empty() or index >= script_picker.item_count:
		writing.text = ""
		writing.editable = false
	else:
		var key: String = script_picker.get_item_metadata(index)
		var d: FscParser.Definition = selected.def
		var doc: PackDocument = selected.doc
		writing.text = _script_body(doc, d) if key == "@body" else doc.field_value(d, key)
		writing.editable = doc.writable and (key == "@body" or not _has_field_comments(doc, d, key))
		if doc.writable and not writing.editable:
			_set_status("This field contains comments; edit it in Source to preserve them.")
	updating = false

func _select_field(index: int) -> void:
	if updating:
		return
	updating = true
	if selected.is_empty() or index >= field_picker.item_count:
		field_editor.text = ""
		field_editor.editable = false
	else:
		var key: String = field_picker.get_item_metadata(index)
		var doc: PackDocument = selected.doc
		var d: FscParser.Definition = selected.def
		field_editor.text = doc.field_value(d, key)
		field_editor.editable = doc.writable and not _has_field_comments(doc, d, key)
		if doc.writable and not field_editor.editable:
			_set_status("This field contains comments; edit it in Source to preserve them.")
	updating = false

func _current_selection_after_edit() -> void:
	var previous := selected
	workspace.reindex()
	if not previous.is_empty():
		selected = workspace.find_row(previous.doc.path, previous.def.type, previous.def.id, previous.def.mode, previous.get("ordinal", 0))
	_set_status("Editing. Save all to write changes to the working pack.")

func _writing_changed() -> void:
	if updating or selected.is_empty() or not writing.editable or script_picker.selected < 0:
		return
	var key: String = script_picker.get_item_metadata(script_picker.selected)
	var doc: PackDocument = selected.doc
	var d: FscParser.Definition = selected.def
	var previous := _script_body(doc, d) if key == "@body" else doc.field_value(d, key)
	if writing.text == previous:
		return
	var error := ""
	if key == "@body":
		var block := doc.block(d)
		var pos := block.find("\n")
		var header := (block.left(pos) if pos >= 0 else block).trim_suffix("\r")
		var eol := "\r\n" if "\r\n" in doc.text else "\n"
		var body := writing.text.replace("\r\n", "\n").replace("\r", "\n").replace("\n", eol)
		doc.replace_block(d, header + eol + body)
	else:
		error = doc.set_field(d, key, writing.text)
	if not error.is_empty():
		_show_error(error)
		return
	_current_selection_after_edit()
	updating = true
	source.text = doc.text
	updating = false

func _field_changed() -> void:
	if updating or selected.is_empty() or not field_editor.editable or field_picker.selected < 0:
		return
	var key: String = field_picker.get_item_metadata(field_picker.selected)
	var doc: PackDocument = selected.doc
	if field_editor.text == doc.field_value(selected.def, key):
		return
	var error := doc.set_field(selected.def, key, field_editor.text)
	if not error.is_empty():
		_show_error(error)
		return
	_current_selection_after_edit()
	updating = true
	source.text = doc.text
	updating = false

func _source_changed() -> void:
	if updating or selected.is_empty() or not source.editable:
		return
	var doc: PackDocument = selected.doc
	if source.text == doc.text:
		return
	doc.change(source.text)
	_current_selection_after_edit()
	# A temporarily incomplete header remains editable in this file.
	if selected.is_empty():
		selected = {"doc": doc, "def": FscParser.Definition.new(), "pack": "", "root": workspace.owner(doc.path)}

func _refresh_references() -> void:
	if not side_panel.visible: return
	references.clear()
	var query := reference_search.text.to_lower()
	var count := 0
	for row: Dictionary in workspace.rows:
		var d: FscParser.Definition = row.def
		if reference_scope == "My pack" and not row.doc.writable:
			continue
		if reference_scope == "Other packs" and row.doc.writable:
			continue
		var display: String = d.fields["name"].value if d.fields.has("name") else d.id
		if not query.is_empty() and query not in (display + " " + d.id + " " + d.type + " " + row.pack).to_lower():
			continue
		count += 1
		if count > 300:
			continue
		references.add_item("%s  ·  %s  ·  %s" % [display, d.type.capitalize(), row.pack])
		references.set_item_metadata(references.item_count - 1, {"id": d.id, "row": row})
		references.set_item_tooltip(references.item_count - 1, row.doc.path + ":" + str(d.line))
	reference_count.text = "%d matches · showing first 300; search to narrow" % count if count > 300 else "%d matches · double-click to open" % count

func _refresh_values() -> void:
	values_list.clear()
	if not side_panel.visible or workspace.target.is_empty():
		return
	var declared: Dictionary = workspace.preview_content().values
	var keys: Array = declared.keys()
	keys.sort()
	for key: String in keys:
		var declaration: Dictionary = declared[key]
		if not values_search.text.is_empty() and values_search.text.to_lower() not in (key + " " + BlockCatalog.value_label(key, workspace) + " " + str(declaration.get("kind", ""))).to_lower():
			continue
		var states: String = ", ".join(declaration.get("states", []))
		values_list.add_item(BlockCatalog.value_label(key, workspace) + "  ·  " + str(SlotControl.VALUE_WORDS.get(str(declaration.get("kind", "")), "value")) + ("  ·  " + states.replace("_", " ") if not states.is_empty() else ""))
		values_list.set_item_tooltip(values_list.item_count - 1, key)
		values_list.set_item_metadata(values_list.item_count - 1, key)
	for key: String in Validator.PLAYER_VALUES:
		if not values_search.text.is_empty() and values_search.text.to_lower() not in ("player." + key).to_lower():
			continue
		values_list.add_item("the player's " + key.replace("_", " ").replace(".", " ") + "  ·  player")
		values_list.set_item_metadata(values_list.item_count - 1, "player." + key)

## Lists where a saved value is changed and where it is read, in your pack.
func _inspect_value(index: int) -> void:
	var path := str(values_list.get_item_metadata(index))
	var uses := workspace.value_uses(path)
	var changed := uses.filter(func(use: Dictionary) -> bool: return use.changes)
	var read := uses.filter(func(use: Dictionary) -> bool: return not use.changes)
	value_title.text = "%s: changed in %d place%s, read in %d. Double-click to open." % [BlockCatalog.value_label(path, workspace), changed.size(), "" if changed.size() == 1 else "s", read.size()]
	value_uses.clear()
	for group: Array in [["Changed by", changed], ["Read by", read]]:
		if group[1].is_empty(): continue
		value_uses.add_item(group[0])
		value_uses.set_item_disabled(value_uses.item_count - 1, true)
		for use: Dictionary in group[1]:
			var words: String = BlockCatalog.sentence(str(use.text).trim_prefix("~").strip_edges(), workspace) if str(use.text).begins_with("~") else str(use.text)
			value_uses.add_item("   %s %s   ·   %s" % [Wording.icon(use.row.def.type), Wording.title(use.row), words])
			value_uses.set_item_metadata(value_uses.item_count - 1, use)
			value_uses.set_item_tooltip(value_uses.item_count - 1, str(use.text))

func _insert_reference(index: int) -> void:
	var data: Dictionary = references.get_item_metadata(index)
	_insert_at_writer(data.id)

func _insert_at_writer(text: String) -> void:
	if not writing.editable:
		_set_status("Select a writable story field first.")
		return
	writing.insert_text_at_caret(text)
	writing.grab_focus()

func _validate() -> void:
	if workspace.target.is_empty(): return
	if workspace.rows.size() <= PackWorkspace.LIGHT:
		workspace.validate(true)
		_refresh_values()
		_refresh_diagnostics()
		if home != null: home.refresh(workspace)
		_report_check()
		return
	# Every pack's stories are checked again, on another thread.
	check_wanted = true
	workspace.request_check(true)
	_set_status("Checking every loaded pack with the game engine. You can keep working; the result appears here.")
	_refresh_diagnostics()

func _report_check() -> void:
	var errors := workspace.diagnostics.filter(func(item: Dictionary) -> bool: return item.severity == "error").size()
	if not workspace.diagnostics.is_empty():
		_set_side_panel(true)
		side_tabs.current_tab = 2
	_set_status("Checked with the game engine, unsaved changes included: " + ("no problems." if workspace.diagnostics.is_empty() else "%d problem%s, %d note%s." % [errors, "" if errors == 1 else "s", workspace.diagnostics.size() - errors, "" if workspace.diagnostics.size() - errors == 1 else "s"]))

## Notes about other packs (a missing picture in someone else's pack) are counted, not listed.
var show_other_notes := false

func _refresh_diagnostics() -> void:
	if diagnostics_list == null: return
	diagnostics_list.clear()
	var errors := 0
	var mine: Array = []
	var theirs: Array = []
	var notes := 0
	for item: Dictionary in workspace.diagnostics:
		var own: bool = str(item.path).begins_with(workspace.target + "/")
		if item.severity == "error":
			errors += 1
			if own: mine.push_front(item)
			else: theirs.push_front(item)
		elif own: mine.append(item)
		elif show_other_notes: theirs.append(item)
		else: notes += 1
	for item: Dictionary in mine + theirs:
		diagnostics_list.add_item("%s %s\n      %s, line %d%s" % ["⚠" if item.severity == "error" else "ℹ", item.message, str(item.path).get_file(), int(item.line), "" if str(item.path).begins_with(workspace.target + "/") else "  ·  in another pack"])
		diagnostics_list.set_item_metadata(diagnostics_list.item_count - 1, item)
		if item.severity == "error": diagnostics_list.set_item_custom_fg_color(diagnostics_list.item_count - 1, EditorTheme.color("bad"))
	if notes > 0:
		diagnostics_list.add_item("… and %d note%s about other packs. Double-click to list them." % [notes, "" if notes == 1 else "s"])
		diagnostics_list.set_item_metadata(diagnostics_list.item_count - 1, {"more": true})
	if diagnostics_list.item_count == 0: diagnostics_list.add_item("✓ Nothing to report.")
	if check_state != null and (workspace.loading or workspace.checking):
		check_state.text = "⏳" if compact else ("⏳ Loading packs…" if workspace.loading else "⏳ Checking…")
		check_state.tooltip_text = "The packs beside yours are being loaded. You can already work." if workspace.loading else "The game engine is checking your pack against the others. You can keep working."
		check_state.add_theme_color_override("font_color", EditorTheme.color("muted"))
	elif check_state != null:
		var fresh: bool = workspace.validation_revision == workspace.revision
		check_state.text = ("⚠ %d" % errors if compact else "⚠ %d problem%s" % [errors, "" if errors == 1 else "s"]) if errors > 0 else ("✓" if compact else "✓ No problems" if fresh else "✓ Check")
		check_state.tooltip_text = ("%d problem%s found. Choose to check again and list them." % [errors, "" if errors == 1 else "s"]) if errors > 0 else ("No problems found by the game engine." if fresh else "Check the pack with the game engine and list any problems.")
		check_state.add_theme_color_override("font_color", EditorTheme.color("bad") if errors > 0 else EditorTheme.color("good") if fresh else EditorTheme.color("text"))

## Opens the place a problem is in: the block of a story, or the content's details.
func _open_problem(diagnostic: Dictionary) -> void:
	for index in diagnostics_list.item_count:
		if not diagnostics_list.get_item_metadata(index) is Dictionary or diagnostics_list.get_item_metadata(index).has("more"): continue
		var listed: Dictionary = diagnostics_list.get_item_metadata(index)
		if listed.path == diagnostic.path and int(listed.line) == int(diagnostic.line) and listed.message == diagnostic.message:
			_open_diagnostic(index)
			return

func _open_diagnostic(index: int) -> void:
	if not diagnostics_list.get_item_metadata(index) is Dictionary: return
	var diagnostic: Dictionary = diagnostics_list.get_item_metadata(index)
	if diagnostic.has("more"):
		show_other_notes = true
		_refresh_diagnostics()
		return
	var opened := _open_line(str(diagnostic.path), int(diagnostic.line))
	if not opened.is_empty(): _set_status("Problem in %s: %s" % [Wording.title(opened), diagnostic.message])

## Opens the content that holds a line of a file: its block when the line is
## in a story, else its details. Returns the content, or nothing.
func _open_line(path: String, line: int) -> Dictionary:
	if not _entries_ready(): return {}
	var closest: Dictionary = {}
	for row: Dictionary in workspace.rows:
		if row.doc.path == path and row.def.line <= line:
			if closest.is_empty() or row.def.line > closest.def.line:
				closest = row
	if closest.is_empty():
		_show_error("This line is no longer there: " + path.get_file())
		return {}
	selected = closest
	_refresh_selection()
	var definition: FscParser.Definition = closest.def
	var story := definition.type in ["scene", "menu", "text"]
	for key: String in definition.fields:
		var field: FscParser.Field = definition.fields[key]
		var last: int = field.children[-1].number if not field.children.is_empty() else field.line
		if ContentDB.SCHEMA.get(definition.type, {}).get(key, "") in ["script", "menu"] and line >= field.line and line <= last:
			story = true
			if definition.type not in ["scene", "menu"]:
				_open_visual_script(closest, key)
				story_editor.focus_source_line(line)
				return closest
	tabs.set_tab_hidden(3, not story)
	if story:
		story_canvas.focus_definition(closest)
		story_canvas.refresh()
		tabs.current_tab = 3
		story_editor.show_story(workspace, story_canvas.context_row)
		story_editor.visible = true
		story_editor.focus_source_line(line)
	else:
		tabs.current_tab = 4
	return closest

func _save_all() -> void:
	if not _entries_ready():
		return
	var error := workspace.save_all()
	if not error.is_empty():
		_show_error(error)
		return
	if not recovery_pending: drafts.discard(workspace.target)
	workspace.reindex()
	_refresh_all()
	_set_status("Saved changes to the working pack.")

func _show_new() -> void:
	if not _entries_ready():
		return
	if workspace.target.is_empty():
		_show_error("Open a working pack first.")
		return
	new_validation_error = ""
	new_link.clear()
	new_story_text.text = ""
	new_step = 0
	new_id_edited = false
	new_name.text = ""
	new_id.text = ""
	new_mode.select(0)
	new_triggers.configure(workspace, "walking into ")
	_set_new_type("scene")
	var relevant: Array = GROUPS.get(group, [])
	if not relevant.is_empty():
		_set_new_type(relevant[0])
	_go_new_step(0)
	AuthoringLayout.popup(new_dialog, Vector2i(840, 620))

func _set_new_type(type: String) -> void:
	var found := false
	for i in new_type.item_count:
		if new_type.get_item_text(i) == type:
			new_type.select(i)
			found = true
			break
	if not found:
		return
	for key: String in new_type_buttons:
		new_type_buttons[key].set_pressed_no_signal(key == type)
	var descriptions := {
		"scene": "Write a story passage and connect it to other passages.",
		"menu": "Create a conversation or a set of player responses.",
		"event": "Choose when it starts, then write what happens.",
		"character": "Create someone the player can meet and talk to.",
		"creature": "Create a creature the player can encounter.",
		"item": "Create an object the player can find or use.",
		"location": "Create a place the player can visit.",
		"quest": "Track the stages of an ongoing story.",
		"condition": "Create temporary attribute bonuses, then apply them from a story or item for a chosen number of turns.",
		"values": "Create flags and values to remember story progress."
	}
	new_help.text = descriptions.get(type, "Create content in your working pack.")
	_refresh_new_summary()

func _new_name_changed(value: String) -> void:
	new_validation_error = ""
	if not new_id_edited:
		var slug := workspace.unique_id(value, new_type.get_item_text(new_type.selected))
		new_id.text = slug
	_refresh_new_summary()

func _new_error() -> String:
	if new_name.text.strip_edges().is_empty(): return "Name: give this content a name first."
	if RegEx.create_from_string("^[a-z0-9_][a-z0-9_.-]*$").search(new_id.text.strip_edges()) == null: return "ID: use lowercase letters, numbers, underscores, dots or hyphens."
	var type := new_type.get_item_text(new_type.selected)
	if type == "event" and new_mode.selected == 0:
		var error := new_triggers.validation_error()
		if not error.is_empty(): return error
	if type in ["scene", "menu", "event"] and new_mode.selected == 0:
		for line: String in new_story_text.text.split("\n"):
			if StoryGraph._is_statement(line.strip_edges()) or "[" in line or "]" in line:
				return "Opening passage: use ordinary prose here. Add choices, actions and variations on the story board."
	return ""

func _go_new_step(index: int) -> void:
	if index == 2:
		var error := _new_error()
		if not error.is_empty(): _creation_error(error); return
	new_validation_error = ""
	new_step = clampi(index, 0, 2)
	for at in new_pages.size(): new_pages[at].visible = at == new_step
	new_layout.set_sections([{"key": "0", "title": "Starting point"}, {"key": "1", "title": "Name & opening"}, {"key": "2", "title": "Review"}], str(new_step))
	new_layout.page_scroll.scroll_vertical = 0
	new_back.visible = new_step > 0
	new_dialog.ok_button_text = ["Next: Name & opening ›", "Next: Review ›", "Create & open"][new_step]
	_refresh_new_summary()
	if new_step == 1: new_name.grab_focus.call_deferred()

func _creation_error(text: String) -> void:
	new_validation_error = text
	_refresh_new_summary()

func _advance_new() -> void:
	if new_step < 2: _go_new_step(new_step + 1)
	else: _create_definition()

func _refresh_new_summary() -> void:
	if new_layout == null or new_type == null or new_mode == null: return
	var type := new_type.get_item_text(new_type.selected)
	for key: String in new_type_buttons:
		new_type_buttons[key].disabled = not new_link.is_empty() and key != "scene"
	new_type.disabled = not new_link.is_empty()
	new_mode.disabled = not new_link.is_empty()
	new_triggers.visible = type == "event" and new_mode.selected == 0
	new_story_text.visible = type in ["scene", "menu", "event"] and new_mode.selected == 0
	new_story_caption.visible = new_story_text.visible
	AuthoringLayout.clear(new_layout.sheet)
	new_layout.sheet.add_child(AuthoringLayout.label("YOU ARE CREATING", 13, true))
	new_layout.sheet.add_child(AuthoringLayout.label(new_name.text if not new_name.text.is_empty() else "Untitled " + AuthoringLayout.type_name(type).to_lower(), 22))
	new_layout.sheet.add_child(AuthoringLayout.label(AuthoringLayout.type_name(type), 16, true))
	if type == "event": new_layout.sheet.add_child(AuthoringLayout.label(EventTriggers.describe(workspace, new_triggers.value()), 15))
	if not new_link.is_empty(): new_layout.sheet.add_child(AuthoringLayout.label("Follows the response: “" + str(new_link.option.label) + "”", 15))
	if new_story_text.visible and not new_story_text.text.strip_edges().is_empty(): new_layout.sheet.add_child(AuthoringLayout.label("Opening passage ready", 14))
	new_layout.sheet.add_child(AuthoringLayout.label("Created in your working pack. Save all writes it to disk.", 14, true))
	if not new_validation_error.is_empty():
		var error := AuthoringLayout.label(new_validation_error, 15)
		error.theme_type_variation = "ErrorLabel"
		new_layout.sheet.add_child(error)
	AuthoringLayout.clear(new_review)
	new_review.add_child(AuthoringLayout.label("Ready to create", 24))
	new_review.add_child(AuthoringLayout.label(new_name.text, 22))
	new_review.add_child(AuthoringLayout.label(new_help.text, 16, true))
	if type == "event": new_review.add_child(AuthoringLayout.label(EventTriggers.describe(workspace, new_triggers.value()), 16))
	if new_story_text.visible and not new_story_text.text.strip_edges().is_empty(): new_review.add_child(AuthoringLayout.label(new_story_text.text, 17))
	new_review.add_child(AuthoringLayout.label("You can add responses, actions and connections after creating it.", 15, true))

func _create_definition() -> void:
	new_validation_error = ""
	var error := workspace.transaction("Create " + new_name.text, func() -> String:
		_create_definition_impl()
		return new_validation_error)
	if not error.is_empty(): _creation_error(error)
	_history_changed()

func _create_definition_impl() -> void:
	var type := new_type.get_item_text(new_type.selected)
	var id := new_id.text.strip_edges()
	var display_name := new_name.text.strip_edges()
	var validation_error := _new_error()
	if not validation_error.is_empty():
		_creation_error(validation_error)
		return
	var mode: String = ["define", "extend", "replace"][new_mode.selected]
	var previous_selection := selected
	var link_source: Dictionary = {}
	var link_option: Dictionary = {}
	if not new_link.is_empty():
		link_source = workspace.find_row(new_link.row.doc.path, new_link.row.def.type, new_link.row.def.id, new_link.row.def.mode, new_link.row.get("ordinal", 0))
		if link_source.is_empty() or link_source.doc.text != new_link.source_text or not link_source.doc.writable:
			_creation_error("The response changed. Copy your opening passage and reopen Choose next story.")
			return
		if new_link.row.has("script_field"):
			link_source = link_source.duplicate()
			link_source.script_field = new_link.row.script_field
		for candidate: Dictionary in StoryGraph.choices(link_source):
			if candidate.line == new_link.option.line: link_option = candidate
		if link_option.is_empty() or not StoryGraph.transition(link_option).editable or type != "scene" or mode != "define":
			_creation_error("Create a new story here to connect this response.")
			return
	var initial := ""
	var opening := new_story_text.text.strip_edges()
	if mode == "define" and not opening.is_empty():
		match type:
			"scene": initial = opening
			"event": initial = PackWorkspace.template(type, id).replace("    Write what happens here.", "    " + opening.replace("\n", "\n    "))
			"menu": initial = "title: What would you like to do?\nleave: Leave\nintro:\n    " + opening.replace("\n", "\n    ") + "\n* Look closer\n    You take a closer look."
	if type == "event" and mode == "define":
		if initial.is_empty(): initial = PackWorkspace.template(type, id)
		initial += "\nfound by: " + new_triggers.value()
	var error := workspace.create_definition(type, id, mode, initial)
	if not error.is_empty():
		_creation_error(error)
		return
	for row: Dictionary in workspace.rows:
		if row.doc.writable and row.def.type == type and row.def.id == id and row.def.mode == mode:
			if mode == "define" and ContentDB.SCHEMA.get(type, {}).has("name"):
				row.doc.set_field(row.def, "name", display_name)
				workspace.reindex()
				row = workspace.find_row(row.doc.path, type, id, mode)
			selected = row
			break
	if type == "event" and mode == "define":
		var trigger_error := EventTriggers.apply_to(workspace, selected, new_triggers.value())
		if not trigger_error.is_empty():
			workspace.documents.erase(selected.doc.path)
			workspace.reindex()
			selected = previous_selection
			_creation_error(trigger_error)
			return
		selected = workspace.find_row(selected.doc.path, type, id, mode)
	if not link_source.is_empty():
		var link_error := StoryGraph.set_transition(link_source, link_option, id)
		if not link_error.is_empty():
			workspace.documents.erase(selected.doc.path)
			workspace.reindex()
			selected = previous_selection
			_creation_error(link_error)
			return
		workspace.reindex()
		selected = workspace.find_row(selected.doc.path, type, id, mode)
	new_dialog.hide()
	_refresh_all()
	if type == "event":
		tabs.current_tab = 4
	elif type in ["scene", "menu", "character"]:
		tabs.set_tab_hidden(3, false)
		story_canvas.focus_definition(selected)
		tabs.current_tab = 3
	else:
		tabs.current_tab = 4
		tabs.set_tab_hidden(3, true)
	_set_status("Created %s %s. Save all to write it to the pack." % [type, id])

func _build_graph_tab() -> void:
	story_canvas = StoryCanvas.new()
	story_canvas.name = "Story board"
	tabs.add_child(story_canvas)
	story_canvas.configure(workspace)
	story_canvas.details_requested.connect(func(row: Dictionary) -> void:
		if not _entries_ready(): return
		selected = row
		_refresh_selection()
		tabs.current_tab = 4)
	story_canvas.changed.connect(_on_canvas_changed)
	story_canvas.context_changed.connect(func(row: Dictionary) -> void:
		if story_editor == null: return
		story_editor.show_story(workspace, row)
		story_editor.visible = tabs.current_tab == 3
		_refresh_crumbs())
	story_canvas.problem.connect(_show_error)
	story_canvas.block_requested.connect(func(_line: int, keys: Array) -> void:
		if story_editor != null and story_editor.visible: story_editor.select_blocks(keys))
	story_canvas.new_story_requested.connect(_new_story_node)
	story_canvas.next_story_requested.connect(_new_next_story)

func _new_next_story(row: Dictionary, option: Dictionary) -> void:
	_show_new()
	if not new_dialog.visible: return
	new_link = {"row": row, "option": option, "source_text": row.doc.text}
	_set_new_type("scene")
	_go_new_step(1)

func _build_visual_details() -> void:
	visual_details = VisualDetails.new()
	visual_details.name = "Details"
	tabs.add_child(visual_details)
	visual_details.changed.connect(_on_canvas_changed)
	visual_details.problem.connect(_show_error)
	visual_details.story_requested.connect(_open_visual_script)

func _build_world_tab() -> void:
	world_canvas = WorldCanvas.new()
	world_canvas.name = "World map"
	tabs.add_child(world_canvas)
	world_canvas.configure(workspace)
	world_canvas.problem.connect(_show_error)
	world_canvas.changed.connect(_on_canvas_changed)
	world_canvas.selected.connect(_select_world_place)
	world_canvas.open_requested.connect(_open_world_content)
	world_canvas.event_requested.connect(_create_world_event)
	world_canvas.place_requested.connect(func() -> void:
		for template: Dictionary in AuthorTemplates.available(workspace):
			if template.id == "place":
				_start_task(template)
				return)

func _create_world_event(place: Dictionary) -> void:
	_show_new()
	if not new_dialog.visible:
		return
	_set_new_type("event")
	new_triggers.configure(workspace, "walking into " + str(place.def.id))
	_go_new_step(1)

func _select_world_place(row: Dictionary) -> void:
	if not _entries_ready():
		return
	selected = row
	viewing_world_heading = false
	_refresh_selection()
	tabs.set_tab_hidden(3, true)

func _open_world_content(row: Dictionary) -> void:
	if not _entries_ready():
		return
	selected = row
	_refresh_selection()
	var has_story: bool = row.def.type in ["scene", "menu", "character"]
	tabs.set_tab_hidden(3, not has_story)
	if has_story:
		story_canvas.focus_definition(row)
		tabs.current_tab = 3
	else:
		tabs.current_tab = 4

func _open_visual_script(row: Dictionary, field: String) -> void:
	if field == "@body":
		story_canvas.focus_definition(row)
	else:
		story_canvas.focus_script(row, field)
	tabs.set_tab_hidden(3, false)
	tabs.current_tab = 3
	if not row.def.fields.has(field) and ContentDB.SCHEMA.get(row.def.type, {}).get(field, "") == "script" and row.doc.writable:
		story_canvas.start_writing(row, field)

## The board waits to be looked at when no story is in focus: a pack's first
## hundred stories are not drawn behind another page.
var board_stale := false

func _refresh_graph() -> void:
	if story_canvas != null:
		if tabs.current_tab != 3 and story_canvas.focused_id.is_empty() and not story_canvas.show_everything:
			board_stale = true
			return
		board_stale = false
		var timing := Perf.start()
		story_canvas.refresh()
		Perf.stop("window: board", timing)
		timing = Perf.start()
		if story_editor != null and not story_canvas.context_row.is_empty():
			story_editor.show_story(workspace, story_canvas.context_row)
			story_editor.visible = tabs.current_tab == 3
		Perf.stop("window: blocks", timing)

func _on_canvas_changed(row: Dictionary) -> void:
	selected = row
	_refresh_all()
	var last: String = str(workspace.history.steps[workspace.history.cursor - 1].label) if workspace.history.cursor > 0 else "Changed"
	_set_status(last + ".", true)

func _create_pack() -> void:
	var id := pack_id.text.strip_edges()
	var display_name := pack_name.text.strip_edges()
	if RegEx.create_from_string("^[a-z0-9][a-z0-9_-]*$").search(id) == null or display_name.is_empty() or "\n" in display_name:
		_show_error("Enter a pack name and a lowercase ID using letters, numbers, underscores or hyphens.")
		return
	var folder := pack_parent.path_join(id)
	if DirAccess.dir_exists_absolute(folder) or FileAccess.file_exists(folder):
		_show_error("That folder already exists; choose a different ID.")
		return
	if DirAccess.make_dir_absolute(folder) != OK:
		_show_error("Could not create the pack folder.")
		return
	var file := FileAccess.open(folder.path_join("pack.fsc"), FileAccess.WRITE)
	if file == null:
		DirAccess.remove_absolute(folder)
		_show_error("Could not create the pack manifest.")
		return
	file.store_string("== pack " + id + "\nname: " + display_name + "\nversion: 0.1.0\nauthors: \nrequires: (none)\n")
	file.close()
	_open_target(folder)
	_set_status("Pack created. Edit the manifest to add your author name and dependencies.")

func _selected_value() -> String:
	var indexes := values_list.get_selected_items()
	if indexes.is_empty():
		_set_status("Select a value first.")
		return ""
	return str(values_list.get_item_metadata(indexes[0]))

func _value_example(key: String) -> String:
	if workspace.db == null or not workspace.db.values.has(key):
		return "1"
	var declaration: Dictionary = workspace.db.values[key]
	match str(declaration.get("kind", "")):
		"flag": return "yes"
		"states":
			var states: Array = declaration.get("states", [])
			return str(states[-1]) if not states.is_empty() else "yes"
		_: return "1"

func _insert_value_check() -> void:
	var key := _selected_value()
	if key.is_empty():
		return
	var value := _value_example(key)
	var condition := ""
	if key.begins_with("quest."):
		condition = "quest " + key.trim_prefix("quest.") + " is " + value
	elif workspace.db != null and workspace.db.values.has(key) and workspace.db.values[key].get("kind") == "flag":
		condition = key
	elif workspace.db != null and workspace.db.values.has(key) and workspace.db.values[key].get("kind") == "states":
		condition = key + " is " + value
	else:
		condition = key + " > 0"
	_insert_at_writer("if " + condition + ":\n    Write what happens.\n")

func _insert_value_set() -> void:
	var key := _selected_value()
	if key.is_empty():
		return
	var value := _value_example(key)
	if key.begins_with("quest."):
		_insert_at_writer("~ quest " + key.trim_prefix("quest.") + " = " + value)
	else:
		_insert_at_writer("~ " + key + " = " + value)

func _choose_image() -> void:
	if not _entries_ready():
		return
	if workspace.target.is_empty():
		_show_error("Open a working pack first.")
		return
	image_file_dialog.popup_centered_ratio(0.75)

func _image_selected(path: String) -> void:
	image_source = path
	image_id.text = path.get_file().get_basename().to_lower().replace(" ", "_")
	image_artist.text = str(_preference("images", "artist", ""))
	image_link.text = ""
	image_info_dialog.popup_centered()

func _import_image() -> void:
	var id := image_id.text.strip_edges()
	var artist := image_artist.text.strip_edges()
	var link := image_link.text.strip_edges()
	var ext := image_source.get_extension().to_lower()
	if RegEx.create_from_string("^[a-z0-9_][a-z0-9_.-]*$").search(id) == null or artist.is_empty() or "\n" in artist or "\n" in link or ext not in ["png", "jpg", "jpeg", "webp"]:
		_show_error("Enter a lowercase image ID and an artist, and choose a PNG, JPEG or WebP image.")
		return
	for folder: String in workspace.pack_paths:
		for extension in ["png", "jpg", "jpeg", "webp"]:
			if FileAccess.file_exists(folder.path_join("images").path_join(id + "." + extension)):
				_show_error("An image with that ID already exists in a loaded pack.")
				return
	for row: Dictionary in workspace.rows:
		if row.def.type == "image" and row.def.id == id:
			_show_error("Image credits with that ID already exist.")
			return
	var images := workspace.target.path_join("images")
	var target_dir := DirAccess.open(workspace.target)
	if target_dir != null and target_dir.is_link("images"):
		_show_error("The images folder must be inside the working pack, not a link.")
		return
	if DirAccess.make_dir_recursive_absolute(images) != OK:
		_show_error("Could not create the images folder.")
		return
	var image_dir := DirAccess.open(images)
	if image_dir == null or image_dir.is_link("credits.fsc"):
		_show_error("The image credits file must be inside the working pack, not a link.")
		return
	var destination := images.path_join(id + "." + ext)
	if DirAccess.copy_absolute(image_source, destination) != OK:
		_show_error("Could not copy the image into the pack.")
		return
	var credit_path := images.path_join("credits.fsc")
	var credit_doc: PackDocument
	if workspace.documents.has(credit_path):
		credit_doc = workspace.documents[credit_path]
	else:
		credit_doc = PackDocument.new(credit_path, true)
		workspace.documents[credit_path] = credit_doc
	var eol := "\r\n" if "\r\n" in credit_doc.text else "\n"
	var separator := "" if credit_doc.text.is_empty() else (eol if credit_doc.text.ends_with("\n") else eol + eol)
	var credit := "== image " + id + eol + "artist: " + artist + (eol + "link: " + link if not link.is_empty() else "") + eol
	credit_doc.change(credit_doc.text + separator + credit)
	_set_preference("images", "artist", artist)
	workspace.reindex()
	_refresh_all()
	image_info_dialog.hide()
	_next_import.call_deferred()
	_set_status("Image copied. Save all to write its artist credit.")

func _declare_selected_dependency() -> void:
	var indexes := references.get_selected_items()
	if indexes.is_empty():
		_set_status("Select reference content first.")
		return
	var data: Dictionary = references.get_item_metadata(indexes[0])
	var row: Dictionary = data.row
	if row.root == workspace.target:
		_set_status("That content is already in the working pack.")
		return
	var error := workspace.add_requirement(row.pack)
	if not error.is_empty():
		_show_error(error)
		return
	_refresh_all()
	_set_status("Dependency added to the working pack manifest. Save all to keep it.")

func _ask_delete() -> void:
	if not _entries_ready():
		return
	if selected.is_empty() or not selected.has("def"):
		_show_error("Choose content in the library first.")
		return
	actions.delete(selected)

## The row of buttons for the selected content: uses, rename, duplicate, delete.
func _refresh_content_tools() -> void:
	if content_tools == null: return
	AuthoringLayout.clear(content_tools)
	if selected.is_empty() or not selected.has("def") or selected.def.type in ["file", "pack"] or tabs.current_tab in [5, 6]: return
	var row := selected
	var used := workspace.uses(row.def.id).size()
	var add := func(text: String, tooltip: String, action: Callable, enabled: bool = true) -> void:
		var button := _button(text, action, tooltip)
		button.theme_type_variation = "Ghost"
		button.disabled = not enabled
		content_tools.add_child(button)
	if row.def.type == "quest": add.call("🏁 What moves it?", "See which stories set each stage of this quest, and add more.", func() -> void: actions.quest_flow(row), row.doc.writable)
	add.call("🔗 %d" % used, "Where is this used? %d place%s in your pack." % [used, "" if used == 1 else "s"], func() -> void: actions.show_uses(row))
	if not row.doc.writable and row.def.mode != "extend" and ContentDB.SCHEMA.get(row.def.type, {}).has("image") and row.def.type != "image":
		# Another pack's content can be given a picture of yours: your pack then adds it to that content.
		var picture := PickerButton.new()
		picture.placeholder = "🖼"
		picture.text = "🖼"
		picture.theme_type_variation = "Ghost"
		picture.workspace = workspace
		picture.drop_kinds = ["image"]
		picture.tooltip_text = "Give it a picture from your pack. Your pack then adds the picture to this content of “%s”." % row.pack
		picture.label_for = func(_value: String) -> String: return "🖼"
		picture.options = func() -> Array:
			var result: Array = []
			for other: Dictionary in workspace.rows:
				if other.def.type == "image" and other.doc.writable: result.append({"value": other.def.id, "label": Wording.title(other), "detail": str(other.def.fields.artist.value) if other.def.fields.has("artist") else ""})
			if result.is_empty(): result.append({"value": "", "label": "Your pack has no pictures yet. Import one from the Pack menu."})
			return result
		picture.picked.connect(func(image: String) -> void:
			if image.is_empty(): return
			var error := give_picture(row, image)
			if not error.is_empty(): _show_error(error)
			else:
				_refresh_all()
				_set_status("“%s” now shows your picture." % Wording.title(row), true))
		content_tools.add_child(picture)
	add.call("✎", "Rename everywhere it is used.", func() -> void: actions.rename(row), row.doc.writable)
	add.call("⧉", "Duplicate" if row.doc.writable else "Copy into my pack", func() -> void: actions.make_copy(row))
	add.call("🗑", "Delete, after showing what uses it.", func() -> void: actions.delete(row), row.doc.writable)

## Gives another pack's content a picture of the working pack: an addition
## to that content in the working pack, which then needs the other pack.
func give_picture(row: Dictionary, image: String) -> String:
	if row.is_empty() or row.doc.writable: return "Choose content of another pack. Your own content takes its picture in Details."
	return workspace.transaction("Give %s a picture" % Wording.title(row), func() -> String:
		for own: Dictionary in workspace.rows_with_id(row.def.id):
			if own.doc.writable and own.def.type == row.def.type and own.def.mode == "extend":
				var changed: String = own.doc.set_field(own.def, "image", image)
				return changed if not changed.is_empty() else workspace.add_requirement(row.pack)
		var made := workspace.create_definition(row.def.type, row.def.id, "extend", "image: " + image)
		return made if not made.is_empty() else workspace.add_requirement(row.pack))

func _delete_selected() -> void:
	if selected.is_empty() or not selected.doc.writable:
		return
	var doc: PackDocument = selected.doc
	var span := doc.block_range(selected.def)
	doc.change(doc.text.left(span.x) + doc.text.substr(span.y))
	selected.clear()
	workspace.reindex()
	_refresh_all()
	_set_status("Definition removed from the working buffer. Save all to keep the change.")

func _new_story_node() -> void:
	_show_new()
	_set_new_type("scene")
	_go_new_step(1)


func _toggle_advanced(enabled: bool) -> void:
	for i in 3:
		tabs.set_tab_hidden(i, not enabled)
	tabs.tabs_visible = enabled
	category_buttons["Files"].visible = enabled
	if not enabled and tabs.current_tab < 3:
		tabs.current_tab = 4 if tabs.is_tab_hidden(3) else 3

func _entries_ready() -> bool:
	if visual_details != null and visual_details.pending_rows:
		_show_error("Apply your edited entries before leaving this section.")
		return false
	return true

func _on_tab_changed(index: int) -> void:
	if index <= 2 and technical_stale: _refresh_technical()
	if index == 4 and visual_details != null: visual_details.draw_if_stale()
	if index == 3 and board_stale: _refresh_graph()
	if story_editor != null: story_editor.visible = index == 3 and not story_editor.row.is_empty()
	for key: int in nav_buttons: nav_buttons[key].set_pressed_no_signal(key == index)
	_refresh_content_tools()
	_refresh_crumbs.call_deferred()
	if visual_details != null and visual_details.pending_rows and index != 4:
		tabs.current_tab = 4
		_show_error("Apply your edited entries before leaving this section.")
	elif index == 5 and world_canvas != null:
		viewing_world_heading = selected.is_empty() or selected.def.type != "location"
		if viewing_world_heading:
			heading.text = "World map"
			detail.text = "Select a place to see its details and connections."
		world_canvas.refresh()
	elif viewing_world_heading:
		viewing_world_heading = false
		_refresh_selection()

func _open_reference_definition(index: int) -> void:
	if not _entries_ready():
		return
	var data: Dictionary = references.get_item_metadata(index)
	var ref: Dictionary = data.row
	var fresh := workspace.find_row(ref.doc.path, ref.def.type, ref.def.id, ref.def.mode, ref.get("ordinal", 0))
	if fresh.is_empty():
		return
	selected = fresh
	_refresh_selection()
	tabs.set_tab_hidden(3, fresh.def.type not in ["scene", "menu", "event", "character"])
	if fresh.def.type in ["scene", "menu", "event", "character"]:
		story_canvas.focus_definition(fresh)
		tabs.current_tab = 3
	else:
		tabs.current_tab = 4


func _build_workflow() -> void:
	actions = ContentActions.new()
	actions.workspace = workspace
	add_child(actions)
	actions.problem.connect(_show_error)
	actions.open_line.connect(func(path: String, line: int) -> void: _open_line(path, line))
	actions.changed.connect(func(row: Dictionary) -> void:
		if row.is_empty():
			# A change across the pack, such as find and replace: stay where the author is.
			if not selected.is_empty() and selected.has("def"): selected = workspace.find_row(selected.doc.path, selected.def.type, selected.def.id, selected.def.mode, selected.get("ordinal", 0))
			_refresh_all()
			_set_status(str(workspace.history.steps[workspace.history.cursor - 1].label) + ".", true)
			return
		_on_canvas_changed(row)
		if tabs.current_tab != 3 or row.def.type not in ["scene", "menu", "character"]: _open_world_content(row))
	actions.removed.connect(func() -> void:
		selected.clear()
		_refresh_all()
		_navigate(6)
		_set_status(str(workspace.history.steps[workspace.history.cursor - 1].label) + ".", true))
	drops = ContentDropMenu.new()
	add_child(drops)
	drops.applied.connect(_on_canvas_changed)
	drops.open_requested.connect(_open_world_content)
	story_canvas.graph.content_dropped.connect(_story_drop)
	world_canvas.surface.content_dropped.connect(_map_drop)
	wizard = TaskWizard.new()
	add_child(wizard)
	wizard.created.connect(func(result: Dictionary) -> void:
		_refresh_all()
		for row: Dictionary in workspace.rows:
			if row.doc.writable and row.def.id == result.id and row.def.type == result.type:
				_open_world_content(row)
				break
		_set_status("Created “" + str(result.get("name", str(result.id).replace("_", " "))) + "”.", true)
		if result.type == "quest": actions.quest_flow(selected))
	palette = CommandPalette.new()
	add_child(palette)
	palette.chosen.connect(_palette_chosen)
	recovery_dialog = ConfirmationDialog.new()
	recovery_dialog.title = "Restore unsaved changes?"
	recovery_dialog.ok_button_text = "Restore draft"
	recovery_dialog.cancel_button_text = "Keep for later"
	recovery_dialog.add_button("Discard draft", true, "discard")
	recovery_dialog.confirmed.connect(func() -> void:
		var error := drafts.restore(workspace)
		if not error.is_empty():
			_show_error(error)
			return
		recovery_pending = false
		_refresh_all()
		_set_status("Unsaved draft restored. Save all when ready."))
	recovery_dialog.custom_action.connect(func(action: StringName) -> void:
		if action == "discard":
			drafts.discard(workspace.target)
			recovery_pending = false
			recovery_dialog.hide())
	add_child(recovery_dialog)
	tour = AcceptDialog.new()
	tour.title = "A quick tour"
	tour.ok_button_text = "Skip / close"
	var tour_body := VBoxContainer.new()
	tour_body.custom_minimum_size = Vector2(460, 140)
	tour_text = AuthoringLayout.label("", 18, true)
	tour_body.add_child(tour_text)
	tour.add_child(tour_body)
	var next := tour.add_button("Next", false)
	next.pressed.connect(func() -> void:
		tour_step = (tour_step + 1) % 5
		_update_tour())
	add_child(tour)
	_history_changed()

func _preference(section: String, key: String, fallback: Variant) -> Variant:
	var config := ConfigFile.new()
	config.load(OS.get_user_data_dir().path_join("preferences.cfg"))
	return config.get_value(section, key, fallback)

func _set_preference(section: String, key: String, value: Variant) -> void:
	var config := ConfigFile.new()
	var path := OS.get_user_data_dir().path_join("preferences.cfg")
	config.load(path)
	config.set_value(section, key, value)
	if config.save(path) != OK: _set_status("Could not remember this setting.")

func _history_changed() -> void:
	if undo_button == null: return
	undo_button.disabled = workspace.history.cursor == 0
	redo_button.disabled = workspace.history.cursor >= workspace.history.steps.size()
	undo_button.tooltip_text = "Undo " + (str(workspace.history.steps[workspace.history.cursor - 1].label) if workspace.history.cursor > 0 else "(no changes)")
	redo_button.tooltip_text = "Redo " + (str(workspace.history.steps[workspace.history.cursor].label) if workspace.history.cursor < workspace.history.steps.size() else "(nothing to redo)")
	if save_state != null:
		var unsaved := workspace.dirty_count()
		save_state.text = ("💾" if compact else "💾 Saved") if unsaved == 0 else ("● %d" % unsaved if compact else "● Save %d" % unsaved)
		save_state.tooltip_text = "Everything is saved." if unsaved == 0 else "%d file%s changed. Choose to write them to the pack (Ctrl+S)." % [unsaved, "" if unsaved == 1 else "s"]
		save_state.theme_type_variation = "" if unsaved == 0 else "PrimaryButton"
	if toast_undo != null and workspace.history.cursor == 0: toast_undo.hide()

func _undo() -> void:
	if not _entries_ready(): return
	var label := workspace.undo()
	_after_history("Undid " + label)

func _redo() -> void:
	if not _entries_ready(): return
	var label := workspace.redo()
	_after_history("Redid " + label)

func _after_history(label: String) -> void:
	if not selected.is_empty(): selected = workspace.find_row(selected.doc.path, selected.def.type, selected.def.id, selected.def.mode, selected.get("ordinal", 0))
	_refresh_all()
	_set_status(label + ".", label.begins_with("Redid"))

func _navigate(index: int) -> void:
	if not _entries_ready(): return
	if index == 3: tabs.set_tab_hidden(3, false)
	tabs.current_tab = index
	if index == 6:
		home.refresh(workspace)
		heading.text = "Home"
		detail.text = "Start a task, continue writing, or check your work."
	_refresh_crumbs()

func _start_task(template: Dictionary) -> void:
	if _entries_ready(): wizard.open(workspace, template)

func _find_anything() -> void:
	if _entries_ready(): palette.open(workspace)

func _palette_chosen(entry: Dictionary) -> void:
	if entry.has("row"):
		var row: Dictionary = entry.row
		_open_world_content(workspace.find_row(row.doc.path, row.def.type, row.def.id, row.def.mode, row.get("ordinal", 0)))
	elif entry.has("value"):
		_set_side_panel(true)
		side_tabs.current_tab = 1
		values_search.text = entry.value
		_refresh_values()
	else:
		match entry.command:
			"Home": _navigate(6)
			"New content": _show_new()
			"Check pack": _validate()
			"Save all": _save_all()
			"Undo": _undo()
			"Redo": _redo()
			"Tour": _show_tour()

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index in [MOUSE_BUTTON_XBUTTON1, MOUSE_BUTTON_XBUTTON2]:
		if event.button_index == MOUSE_BUTTON_XBUTTON1: _go_back()
		else: _go_forward()
		get_viewport().set_input_as_handled()

func _unhandled_key_input(event: InputEvent) -> void:
	if not event is InputEventKey or not event.pressed or event.echo: return
	if event.alt_pressed and event.keycode in [KEY_LEFT, KEY_RIGHT]:
		if event.keycode == KEY_LEFT: _go_back()
		else: _go_forward()
		get_viewport().set_input_as_handled()
		return
	if event.ctrl_pressed or event.meta_pressed:
		match event.keycode:
			KEY_K: _find_anything()
			KEY_H: actions.find_and_replace()
			KEY_S: _save_all()
			KEY_Z:
				# Text controls retain their own draft undo until focus leaves.
				var focus := get_viewport().gui_get_focus_owner()
				if focus is TextEdit or focus is LineEdit: return
				if event.shift_pressed: _redo()
				else: _undo()
			KEY_Y: _redo()
			_: return
		get_viewport().set_input_as_handled()

func _autosave() -> void:
	if recovery_pending: return
	var error := drafts.save(workspace)
	if not error.is_empty(): _set_status(error)

func _offer_recovery() -> void:
	var draft := drafts.read_draft(workspace.target)
	recovery_pending = FileAccess.file_exists(drafts.path_for(workspace.target))
	if not recovery_pending: return
	if draft.is_empty():
		_show_error("A recovery draft could not be read. It is kept at " + drafts.path_for(workspace.target) + ". New autosaves will wait until it is recovered or moved aside.")
		return
	for path: Variant in draft.get("references", []):
		if path is String: workspace.add_reference(path)
	_refresh_all()
	recovery_dialog.dialog_text = "A previous session left %d unsaved files. Restore them without changing the files on disk?" % draft.get("documents", []).size()
	AuthoringLayout.popup(recovery_dialog, Vector2i(520, 200))

func _files_dropped(files: PackedStringArray) -> void:
	if workspace.target.is_empty():
		_show_error("Open a working pack before dropping pictures.")
		return
	for path: String in files:
		if path.get_extension().to_lower() in ["png", "jpg", "jpeg", "webp"]: import_queue.append(path)
	_next_import()

func _next_import() -> void:
	if import_queue.is_empty(): return
	_image_selected(import_queue.pop_front())

func _show_tour() -> void:
	if tour == null: return
	tour_step = 0
	_update_tour()
	AuthoringLayout.popup(tour, Vector2i(520, 260))

func _update_tour() -> void:
	var steps := ["1 / 5 · The library\nOn the left is everything in your pack, by kind, and the other packs you loaded. Choose an entry to open it, or drag it into a story or onto the map.", "2 / 5 · Home\nChoose a task on Home: talk to a character, make an item, start a quest. A task asks a few questions and builds the pieces, connected. One Undo takes it all back.", "3 / 5 · Stories and blocks\nOn Stories, each card is a story. Select one to see its blocks on the right. Every block is a sentence; the coloured parts can be changed. Add with + Text, + Action or + More.", "4 / 5 · Preview and Play\nUnder the blocks you read the story as a sample player would. Play, in the top bar, starts the real game on your pack with its own saves.", "5 / 5 · Check and save\nThe tick in the top bar checks your pack with the game engine. Save writes your changes. Every change can be undone, and unsaved work is kept for you if something goes wrong."]
	tour_text.text = steps[tour_step]


func _story_drop(data: Dictionary, position: Vector2) -> void:
	var content := DragPayload.resolve(workspace, data)
	var target: Dictionary = story_canvas.context_row
	for name: StringName in story_canvas.graph_rows:
		var card := story_canvas.graph.get_node(NodePath(name)) as Control
		if card != null and Rect2(card.position, card.size * story_canvas.graph.zoom).has_point(position):
			target = story_canvas.graph_rows[name]
			break
	if content.is_empty(): return
	drops.open(workspace, content, target)

func _map_drop(data: Dictionary, position: Vector2) -> void:
	var content := DragPayload.resolve(workspace, data)
	if content.is_empty(): return
	var target: Dictionary = world_canvas.places_by_id.get(world_canvas.surface.place_at(position), {})
	drops.open(workspace, content, target)
