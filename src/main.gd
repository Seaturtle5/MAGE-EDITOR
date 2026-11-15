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
var category_bar: TabBar
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

func _ready() -> void:
	get_window().title = "MAGE:EDITOR"
	get_tree().auto_accept_quit = false
	_build_theme()
	_build_ui()
	var example := ProjectSettings.globalize_path("res://example-pack")
	if FileAccess.file_exists(example.path_join("pack.fsc")):
		var working := OS.get_user_data_dir().path_join("packs/example-adventure")
		if not FileAccess.file_exists(working.path_join("pack.fsc")):
			PackWorkspace._copy_folder(example, working)
		_open_target(working)
	else:
		_set_status("Open a pack to start writing.")

func _build_theme() -> void:
	var preferences := ConfigFile.new()
	if preferences.load(OS.get_user_data_dir().path_join("preferences.cfg")) == OK:
		EditorTheme.light = preferences.get_value("appearance", "cream", false) == true
	theme = EditorTheme.build()

func _change_theme(index: int) -> void:
	EditorTheme.light = index == 1
	theme = EditorTheme.build()
	background.color = EditorTheme.color("bg")
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
		margin.add_theme_constant_override(side, 14)
	add_child(margin)
	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 10)
	margin.add_child(root)
	var bar := HBoxContainer.new()
	bar.add_theme_constant_override("separation", 8)
	root.add_child(bar)
	bar.add_child(_label("MAGE", 23))
	var subtitle := _label(":EDITOR", 23)
	subtitle.theme_type_variation = "AccentLabel"
	bar.add_child(subtitle)
	bar.add_child(_spacer())
	bar.add_child(_button("+ Create", _show_new, "Create a story, character, item or other content."))
	bar.add_child(_button("Check pack", _validate, "Find problems before playing."))
	bar.add_child(_button("Save all", _save_all))
	side_toggle = Button.new()
	side_toggle.text = "Show library"
	side_toggle.tooltip_text = "Show or hide references, saved values and problems."
	side_toggle.pressed.connect(_toggle_side_panel)
	bar.add_child(side_toggle)
	var file_menu := MenuButton.new()
	file_menu.text = "Pack ▾"
	var popup := file_menu.get_popup()
	for label in ["New pack", "Open pack", "Add reference pack", "Import image", "Delete selected content"]:
		popup.add_item(label)
	popup.id_pressed.connect(_on_pack_menu)
	bar.add_child(file_menu)
	theme_picker = OptionButton.new()
	theme_picker.add_item("MAGE Dark")
	theme_picker.add_item("Cream Light")
	theme_picker.select(1 if EditorTheme.light else 0)
	theme_picker.tooltip_text = "Choose the editor appearance. Your choice is remembered."
	theme_picker.item_selected.connect(_change_theme)
	bar.add_child(theme_picker)
	var advanced := CheckButton.new()
	advanced.text = "Advanced"
	advanced.tooltip_text = "Show the technical views."
	advanced.toggled.connect(_toggle_advanced)
	bar.add_child(advanced)
	pack_label = _label("No pack open", 13)
	pack_label.clip_text = true
	root.add_child(pack_label)
	category_bar = TabBar.new()
	category_bar.tab_alignment = TabBar.ALIGNMENT_LEFT
	for category: String in GROUPS:
		category_bar.add_tab(category)
	category_bar.tab_changed.connect(func(index: int) -> void:
		group = category_bar.get_tab_title(index)
		_refresh_browser()
		if group == "Places" and world_canvas != null:
			tabs.current_tab = 5)
	root.add_child(category_bar)
	var split := HSplitContainer.new()
	split.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_child(split)
	var left := VBoxContainer.new()
	left.custom_minimum_size.x = 215
	split.add_child(left)
	left.add_child(_label("YOUR CONTENT", 13))
	search = LineEdit.new()
	search.placeholder_text = "Search content…"
	search.text_changed.connect(func(_text: String) -> void: _refresh_browser())
	left.add_child(search)
	browser = Tree.new()
	browser.hide_root = true
	browser.size_flags_vertical = Control.SIZE_EXPAND_FILL
	browser.item_selected.connect(_on_browser_selected)
	left.add_child(browser)
	var center_split := HSplitContainer.new()
	center_split.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	split.add_child(center_split)
	var center := VBoxContainer.new()
	center.custom_minimum_size.x = 350
	center.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	center_split.add_child(center)
	heading = _label("Choose something to edit", 22)
	heading.clip_text = true
	center.add_child(heading)
	detail = _label("Select a definition from the content browser.", 13)
	detail.clip_text = true
	center.add_child(detail)
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
	tabs.current_tab = 3
	tabs.set_tab_title(0, "Advanced story")
	tabs.set_tab_title(1, "Advanced fields")
	tabs.set_tab_title(2, "Advanced file")
	for i in 3:
		tabs.set_tab_hidden(i, true)
	category_bar.set_tab_hidden(category_bar.tab_count - 1, true)
	side_panel = VBoxContainer.new()
	side_panel.custom_minimum_size.x = 270
	center_split.add_child(side_panel)
	side_panel.hide()
	side_tabs = TabContainer.new()
	side_tabs.size_flags_vertical = Control.SIZE_EXPAND_FILL
	side_panel.add_child(side_tabs)
	var ref_box := VBoxContainer.new()
	ref_box.name = "References"
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
	reference_search.placeholder_text = "Search IDs, types and packs…"
	reference_search.text_changed.connect(func(_text: String) -> void: _refresh_references())
	ref_box.add_child(reference_search)
	references = ReferenceList.new()
	references.size_flags_vertical = Control.SIZE_EXPAND_FILL
	references.item_activated.connect(_open_reference_definition)
	ref_box.add_child(references)
	reference_count = _label("", 12)
	ref_box.add_child(reference_count)
	ref_box.add_child(_button("Add selected pack as dependency", _declare_selected_dependency))
	var values_box := VBoxContainer.new()
	values_box.name = "Values"
	side_tabs.add_child(values_box)
	values_box.add_child(_label("FLAGS, VALUES AND QUEST STAGES", 13))
	values_box.add_child(_label("Use these saved values in story conditions and actions.", 12))
	values_search = LineEdit.new()
	values_search.placeholder_text = "Search values and flags…"
	values_search.text_changed.connect(func(_text: String) -> void: _refresh_values())
	values_box.add_child(values_search)
	values_list = ItemList.new()
	values_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	values_box.add_child(values_list)
	var diag_box := VBoxContainer.new()
	diag_box.name = "Problems"
	side_tabs.add_child(diag_box)
	diag_box.add_child(_label("ENGINE VALIDATION", 13))
	diag_box.add_child(_label("Double-click a problem to open its source.", 12))
	diagnostics_list = ItemList.new()
	diagnostics_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	diagnostics_list.item_activated.connect(_open_diagnostic)
	diag_box.add_child(diagnostics_list)
	status = _label("", 13)
	status.clip_text = true
	root.add_child(status)
	_build_dialogs()

func _toggle_side_panel() -> void:
	_set_side_panel(not side_panel.visible)

func _on_pack_menu(id: int) -> void:
	match id:
		0: _choose_new_pack()
		1: _choose_target()
		2: _choose_reference()
		3: _choose_image()
		4: _ask_delete()

func _set_side_panel(open: bool) -> void:
	side_panel.visible = open
	side_toggle.text = "Hide library" if open else "Show library"

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
	image_info_dialog.confirmed.connect(_import_image)
	add_child(image_info_dialog)

func _set_status(text: String) -> void:
	status.text = text
	if workspace.dirty_count() > 0:
		status.text += "   •   %d unsaved file(s)" % workspace.dirty_count()

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
	dialog.title = "Add a read-only reference pack"
	dialog.popup_centered_ratio(0.75)

func _directory_selected(path: String) -> void:
	if pending_action == "new_pack":
		pack_parent = path
		pack_id.text = ""
		pack_name.text = ""
		pack_dialog.popup_centered()
		pack_id.grab_focus()
	elif pending_action == "reference":
		var error := workspace.add_reference(path)
		if not error.is_empty():
			_show_error(error)
			return
		_refresh_all()
		_set_status("Reference pack loaded read-only. Add its ID to requires in your pack manifest when you use it.")
	elif workspace.dirty_count() > 0:
		pending_action = "replace_target"
		pending_path = path
		confirm.dialog_text = "Discard unsaved edits and open another pack? Save first to keep your work."
		confirm.popup_centered()
	else:
		_open_target(path)

func _confirmed() -> void:
	if pending_action == "replace_target":
		_open_target(pending_path)
	elif pending_action == "quit":
		get_tree().quit()
	elif pending_action == "delete":
		_delete_selected()

func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		if not _entries_ready():
			return
		if workspace.dirty_count() == 0:
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
	_set_status("Working pack opened. Other loaded packs are read-only.")

func _refresh_all() -> void:
	var info := workspace.manifest(workspace.target)
	pack_label.text = "WORKING PACK  %s     •     %d reference pack(s)     •     %s" % [info.get("id", "invalid manifest"), maxi(0, workspace.pack_paths.size() - 1), workspace.target]
	_refresh_browser()
	_refresh_references()
	_refresh_values()
	_refresh_diagnostics()
	_refresh_selection()
	_refresh_graph()
	if world_canvas != null and tabs.current_tab == 5:
		world_canvas.refresh()

func _matches_group(type: String) -> bool:
	if group == "All":
		return true
	if group == "Other":
		for category: String in GROUPS:
			if type in GROUPS[category]:
				return false
		return true
	return type in GROUPS[group] or (group == "Rules" and type.ends_with("_rules"))

func _refresh_browser() -> void:
	if browser == null:
		return
	browser.clear()
	var root := browser.create_item()
	var sections: Dictionary = {}
	var query := search.text.to_lower()
	if group == "Files":
		for path: String in workspace.documents:
			var doc: PackDocument = workspace.documents[path]
			if not doc.writable:
				continue
			if not query.is_empty() and query not in path.to_lower():
				continue
			var folder := workspace.owner(path)
			var info := workspace.manifest(folder)
			var section := "Working pack" if doc.writable else "Reference: " + str(info.get("id", folder.get_file()))
			if not sections.has(section):
				var parent := browser.create_item(root)
				parent.set_text(0, section)
				parent.set_selectable(0, false)
				sections[section] = parent
			var file_item := browser.create_item(sections[section])
			file_item.set_text(0, path.trim_prefix(folder + "/"))
			var placeholder := FscParser.Definition.new()
			placeholder.type = "file"
			placeholder.id = path.get_file()
			placeholder.path = path
			placeholder.line = 1
			file_item.set_metadata(0, {"def": placeholder, "doc": doc, "pack": info.get("id", folder.get_file()), "root": folder})
		return
	for row: Dictionary in workspace.rows:
		var definition: FscParser.Definition = row.def
		if not row.doc.writable:
			continue
		if not _matches_group(definition.type):
			continue
		var display: String = definition.fields["name"].value if definition.fields.has("name") else definition.id
		if not query.is_empty() and query not in (display + " " + definition.id + " " + definition.type + " " + row.pack).to_lower():
			continue
		var section: String = ("Working pack" if row.doc.writable else "Reference: " + row.pack) + " / " + definition.type.capitalize()
		if not sections.has(section):
			var parent := browser.create_item(root)
			parent.set_text(0, section)
			parent.set_selectable(0, false)
			sections[section] = parent
		var item := browser.create_item(sections[section])
		item.set_text(0, display + ("  [" + definition.mode + "]" if definition.mode != "define" else ""))
		item.set_metadata(0, row)
		item.set_tooltip_text(0, row.doc.path + ":" + str(definition.line))

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
	if visual_details != null:
		visual_details.show_definition(workspace, selected)
	updating = true
	script_picker.clear()
	field_picker.clear()
	if selected.is_empty():
		heading.text = "Choose something to edit"
		detail.text = "Select a definition from the content browser."
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
	heading.text = d.fields["name"].value if d.fields.has("name") and not d.fields["name"].value.is_empty() else d.id
	detail.text = "%s   ·   %s   ·   ID: %s%s" % [d.type.capitalize(), selected.pack, d.id, "   ·   Read-only" if not doc.writable else ""]
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
	if workspace.db == null:
		return
	var keys: Array = workspace.db.values.keys()
	keys.sort()
	for key: String in keys:
		var declaration: Dictionary = workspace.db.values[key]
		if not values_search.text.is_empty() and values_search.text.to_lower() not in (key + " " + str(declaration.get("kind", ""))).to_lower():
			continue
		var states: String = ", ".join(declaration.get("states", []))
		values_list.add_item(key + "  ·  " + str(declaration.get("kind", "value")) + ("  ·  " + states if not states.is_empty() else ""))
		values_list.set_item_metadata(values_list.item_count - 1, key)
	for key: String in Validator.PLAYER_VALUES:
		if not values_search.text.is_empty() and values_search.text.to_lower() not in ("player." + key).to_lower():
			continue
		values_list.add_item("player." + key + "  ·  player value")
		values_list.set_item_metadata(values_list.item_count - 1, "player." + key)

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
	workspace.validate()
	_refresh_values()
	_refresh_diagnostics()
	_set_side_panel(true)
	side_tabs.current_tab = 2
	_set_status("Validated the current workspace, including unsaved edits: %d problem(s)." % workspace.diagnostics.size())

func _refresh_diagnostics() -> void:
	diagnostics_list.clear()
	for item: Dictionary in workspace.diagnostics:
		diagnostics_list.add_item("%s  %s:%d\n%s" % [str(item.severity).to_upper(), str(item.path).get_file(), int(item.line), item.message])
		diagnostics_list.set_item_metadata(diagnostics_list.item_count - 1, item)

func _open_diagnostic(index: int) -> void:
	var diagnostic: Dictionary = diagnostics_list.get_item_metadata(index)
	var closest: Dictionary = {}
	for row: Dictionary in workspace.rows:
		if row.doc.path == diagnostic.path and row.def.line <= diagnostic.line:
			if closest.is_empty() or row.def.line > closest.def.line:
				closest = row
	if closest.is_empty():
		_show_error("Open the source file to inspect: " + str(diagnostic.path))
		return
	selected = closest
	_refresh_selection()
	tabs.set_tab_hidden(3, closest.def.type not in ["scene", "menu", "event", "character"])
	if closest.def.type in ["scene", "menu", "event", "character"]:
		story_canvas.focus_definition(closest)
		story_canvas.refresh()
		tabs.current_tab = 3
	else:
		tabs.current_tab = 4
	_set_status("Problem in %s, line %d: %s" % [str(diagnostic.path).get_file(), int(diagnostic.line), diagnostic.message])

func _save_all() -> void:
	if not _entries_ready():
		return
	var error := workspace.save_all()
	if not error.is_empty():
		_show_error(error)
		return
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
	new_dialog.popup_centered_clamped(Vector2i(840, 650), 0.9)

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
		"values": "Create flags and values to remember story progress."
	}
	new_help.text = descriptions.get(type, "Create content in your working pack.")
	_refresh_new_summary()

func _new_name_changed(value: String) -> void:
	new_validation_error = ""
	if not new_id_edited:
		var slug := RegEx.create_from_string("[^a-z0-9]+").sub(value.to_lower(), "_", true).trim_prefix("_").trim_suffix("_")
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
	story_canvas.changed.connect(_on_canvas_changed)
	story_canvas.problem.connect(_show_error)
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
	visual_details.condition_requested.connect(func(row: Dictionary) -> void: story_canvas._open_picker(row, {}, "event_condition"))
	visual_details.reaction_requested.connect(func(row: Dictionary, action: Dictionary, category: String) -> void:
		if action.is_empty(): story_canvas._open_picker(row, {}, "effect", category)
		else: story_canvas._open_existing_effect(row, {}, action))

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

func _refresh_graph() -> void:
	if story_canvas != null:
		story_canvas.refresh()

func _on_canvas_changed(row: Dictionary) -> void:
	selected = row
	_refresh_all()
	_set_status("Changes made. Select Save all to keep them.")

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
	image_artist.text = ""
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
	workspace.reindex()
	_refresh_all()
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
	if selected.is_empty() or not selected.doc.writable:
		_show_error("Choose a definition in the working pack to delete.")
		return
	if selected.def.type in ["pack", "file"]:
		_show_error("Select an individual definition. The pack manifest and whole files cannot be deleted here.")
		return
	pending_action = "delete"
	var mentions := workspace.mentions(selected).size()
	confirm.dialog_text = "Delete %s %s? %d possible reference(s) mention this ID. Saved games may also use it. The change takes effect when you save." % [selected.def.type, selected.def.id, mentions]
	confirm.popup_centered()

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
	category_bar.set_tab_hidden(category_bar.tab_count - 1, not enabled)
	if not enabled and tabs.current_tab < 3:
		tabs.current_tab = 4 if tabs.is_tab_hidden(3) else 3

func _entries_ready() -> bool:
	if visual_details != null and visual_details.pending_rows:
		_show_error("Apply your edited entries before leaving this section.")
		return false
	return true

func _on_tab_changed(index: int) -> void:
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
