class_name ContentActions
extends Node
## What an author can do with a whole piece of content: see where it is used,
## rename it everywhere, duplicate it, delete it knowing the consequences,
## and wire a quest's stages to stories.

signal changed(row: Dictionary)
signal removed
signal open_line(path: String, line: int)
signal problem(message: String)
var workspace: PackWorkspace
var uses_dialog: AcceptDialog
var uses_list: ItemList
var uses_title: Label
var rename_dialog: ConfirmationDialog
var rename_name: LineEdit
var rename_id: LineEdit
var rename_list: Tree
var rename_note: Label
var rename_row: Dictionary = {}
var rename_plan: Array[Dictionary] = []
var delete_dialog: ConfirmationDialog
var delete_text: Label
var delete_uses: CheckBox
var delete_list: ItemList
var delete_row: Dictionary = {}
var quest_dialog: AcceptDialog
var quest_body: VBoxContainer
var quest_row: Dictionary = {}
var replace_dialog: ConfirmationDialog
var replace_find: LineEdit
var replace_with: LineEdit
var replace_words: CheckBox
var replace_case: CheckBox
var replace_list: Tree
var replace_note: Label

func _ready() -> void:
	uses_dialog = AcceptDialog.new()
	uses_dialog.title = "Where is this used?"
	uses_dialog.ok_button_text = "Close"
	var uses_body := VBoxContainer.new()
	uses_body.custom_minimum_size = Vector2(620, 380)
	uses_dialog.add_child(uses_body)
	uses_title = AuthoringLayout.label("", 15)
	uses_body.add_child(uses_title)
	uses_list = ItemList.new()
	uses_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	uses_list.item_activated.connect(func(index: int) -> void:
		var use: Dictionary = uses_list.get_item_metadata(index)
		uses_dialog.hide()
		open_line.emit(use.row.doc.path, int(use.line)))
	uses_body.add_child(uses_list)
	uses_body.add_child(AuthoringLayout.label("Double-click a line to open it.", 12, true))
	add_child(uses_dialog)
	rename_dialog = ConfirmationDialog.new()
	rename_dialog.title = "Rename"
	rename_dialog.ok_button_text = "Rename everywhere"
	rename_dialog.dialog_hide_on_ok = false
	var rename_body := VBoxContainer.new()
	rename_body.custom_minimum_size = Vector2(680, 440)
	rename_dialog.add_child(rename_body)
	rename_body.add_child(AuthoringLayout.label("Name the players see", 13, true))
	rename_name = LineEdit.new()
	rename_name.text_changed.connect(func(text: String) -> void:
		if rename_id.editable and not rename_id.has_meta("typed"): rename_id.text = workspace.unique_id(text, rename_row.def.type)
		_refresh_rename())
	rename_body.add_child(rename_name)
	rename_body.add_child(AuthoringLayout.label("Technical ID (stories and saved games refer to it)", 13, true))
	rename_id = LineEdit.new()
	rename_id.text_changed.connect(func(_text: String) -> void:
		rename_id.set_meta("typed", true)
		_refresh_rename())
	rename_body.add_child(rename_id)
	rename_note = AuthoringLayout.label("", 14)
	rename_body.add_child(rename_note)
	rename_list = Tree.new()
	rename_list.hide_root = true
	rename_list.columns = 1
	rename_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	rename_body.add_child(rename_list)
	rename_dialog.confirmed.connect(_apply_rename)
	add_child(rename_dialog)
	delete_dialog = ConfirmationDialog.new()
	delete_dialog.title = "Delete"
	delete_dialog.ok_button_text = "Delete"
	var delete_body := VBoxContainer.new()
	delete_body.custom_minimum_size = Vector2(600, 320)
	delete_dialog.add_child(delete_body)
	delete_text = AuthoringLayout.label("", 15)
	delete_body.add_child(delete_text)
	delete_list = ItemList.new()
	delete_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	delete_body.add_child(delete_list)
	delete_uses = CheckBox.new()
	delete_uses.text = "Remove the uses too"
	delete_body.add_child(delete_uses)
	delete_body.add_child(AuthoringLayout.label("Deleting can be undone until you close the editor. Saved games that hold this content may no longer load it.", 12, true))
	delete_dialog.confirmed.connect(func() -> void:
		var error := ContentTools.delete(workspace, delete_row, delete_uses.button_pressed)
		if not error.is_empty(): problem.emit(error)
		else: removed.emit())
	add_child(delete_dialog)
	quest_dialog = AcceptDialog.new()
	quest_dialog.title = "What moves this quest?"
	quest_dialog.ok_button_text = "Close"
	var quest_scroll := ScrollContainer.new()
	quest_scroll.custom_minimum_size = Vector2(640, 440)
	quest_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	quest_dialog.add_child(quest_scroll)
	quest_body = VBoxContainer.new()
	quest_body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	quest_scroll.add_child(quest_body)
	add_child(quest_dialog)

## Find and replace in the words players read. IDs, actions and conditions are never touched.
func find_and_replace() -> void:
	if replace_dialog == null:
		replace_dialog = ConfirmationDialog.new()
		replace_dialog.title = "Find and replace in story text"
		replace_dialog.ok_button_text = "Replace in the ticked lines"
		replace_dialog.dialog_hide_on_ok = false
		var body := VBoxContainer.new()
		replace_dialog.add_child(body)
		body.add_child(AuthoringLayout.label("Only the words players read are searched: story text, names, descriptions and responses. Actions, conditions and IDs stay as they are.", 13, true))
		var grid := GridContainer.new()
		grid.columns = 2
		body.add_child(grid)
		grid.add_child(AuthoringLayout.label("Find", 14))
		replace_find = LineEdit.new()
		replace_find.custom_minimum_size.x = 420
		replace_find.text_changed.connect(func(_text: String) -> void: _refresh_replace())
		grid.add_child(replace_find)
		grid.add_child(AuthoringLayout.label("Replace with", 14))
		replace_with = LineEdit.new()
		replace_with.text_changed.connect(func(_text: String) -> void: _refresh_replace())
		grid.add_child(replace_with)
		var options := HBoxContainer.new()
		body.add_child(options)
		replace_words = CheckBox.new()
		replace_words.text = "Whole words only"
		replace_words.toggled.connect(func(_on: bool) -> void: _refresh_replace())
		options.add_child(replace_words)
		replace_case = CheckBox.new()
		replace_case.text = "Match capital letters"
		replace_case.button_pressed = true
		replace_case.toggled.connect(func(_on: bool) -> void: _refresh_replace())
		options.add_child(replace_case)
		replace_note = AuthoringLayout.label("", 14)
		body.add_child(replace_note)
		replace_list = Tree.new()
		replace_list.hide_root = true
		replace_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
		replace_list.item_activated.connect(func() -> void:
			var entry: Variant = replace_list.get_selected().get_metadata(0) if replace_list.get_selected() != null else null
			if entry is Dictionary:
				replace_dialog.hide()
				open_line.emit(entry.doc.path, int(entry.line)))
		body.add_child(replace_list)
		replace_dialog.confirmed.connect(func() -> void:
			var chosen: Array = []
			var item := replace_list.get_root().get_first_child() if replace_list.get_root() != null else null
			while item != null:
				if item.is_checked(0): chosen.append(item.get_metadata(0))
				item = item.get_next()
			var error := ContentTools.replace(workspace, replace_find.text, replace_with.text, chosen)
			if not error.is_empty():
				replace_note.text = error
				replace_note.theme_type_variation = "ErrorLabel"
				return
			replace_dialog.hide()
			changed.emit({}))
		add_child(replace_dialog)
	_refresh_replace()
	AuthoringLayout.popup(replace_dialog, Vector2i(760, 540))
	replace_find.grab_focus()

func _refresh_replace() -> void:
	replace_list.clear()
	var root := replace_list.create_item()
	var plan := ContentTools.replace_plan(workspace, replace_find.text, replace_with.text, replace_words.button_pressed, replace_case.button_pressed)
	replace_note.theme_type_variation = "MutedLabel"
	replace_note.text = "Write what to find." if replace_find.text.is_empty() else ("Found in %d line%s. Untick any line to leave it; double-click to open it." % [plan.size(), "" if plan.size() == 1 else "s"] if not plan.is_empty() else "Not found in the story text of your pack.")
	replace_dialog.get_ok_button().disabled = plan.is_empty()
	for index in mini(plan.size(), 500):
		var entry: Dictionary = plan[index]
		var item := replace_list.create_item(root)
		item.set_cell_mode(0, TreeItem.CELL_MODE_CHECK)
		item.set_checked(0, true)
		item.set_editable(0, true)
		item.set_text(0, "%s:   %s   →   %s" % [entry.where, entry.before, entry.after])
		item.set_metadata(0, entry)

## Which packs need which: what each loaded pack requires, and what your
## pack uses of the others.
func show_dependencies() -> void:
	var dialog := AcceptDialog.new()
	dialog.title = "How the packs depend on each other"
	dialog.ok_button_text = "Close"
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	dialog.add_child(scroll)
	var body := VBoxContainer.new()
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(body)
	var mine := workspace.manifest(workspace.target)
	var loaded: Dictionary = {}
	for folder: String in workspace.pack_paths:
		var info := workspace.manifest(folder)
		if not info.is_empty(): loaded[info.id] = info
	# What your pack uses of each other pack, counted from the places IDs are meant.
	var owners: Dictionary = {}
	for row: Dictionary in workspace.rows:
		if not row.doc.writable and row.def.mode != "extend" and row.def.type != "pack" and not owners.has(row.def.id): owners[row.def.id] = row.pack
	var used: Dictionary = {}
	var index := workspace.uses_index()
	for id: String in index:
		if owners.has(id): used[owners[id]] = int(used.get(owners[id], 0)) + index[id].size()
	body.add_child(AuthoringLayout.label("Your pack: " + workspace.title_of("pack", str(mine.get("id", ""))), 18))
	var needs: Array = mine.get("requires", [])
	if needs.is_empty() and used.is_empty(): body.add_child(AuthoringLayout.label("It stands on its own: it needs no other pack.", 14, true))
	for id: String in needs:
		var note := "used in %d place%s" % [int(used.get(id, 0)), "" if int(used.get(id, 0)) == 1 else "s"] if used.has(id) else "not used yet by anything in your pack"
		var line := AuthoringLayout.label("needs  📦 %s   ·   %s%s" % [id, note, "" if loaded.has(id) else "   ·   ⚠ not loaded here"], 14)
		if not loaded.has(id): line.theme_type_variation = "ErrorLabel"
		body.add_child(line)
	for id: String in used:
		if id in needs: continue
		var missing := AuthoringLayout.label("⚠ uses  📦 %s in %d place%s without naming it as needed. Using its content from a picker adds it." % [id, int(used[id]), "" if int(used[id]) == 1 else "s"], 14)
		missing.theme_type_variation = "ErrorLabel"
		body.add_child(missing)
	body.add_child(AuthoringLayout.label("The other packs", 18))
	var ids: Array = loaded.keys()
	ids.sort()
	for id: String in ids:
		if id == mine.get("id", ""): continue
		var requires: Array = loaded[id].requires
		var needed_by: Array = ids.filter(func(other: String) -> bool: return id in loaded[other].requires)
		body.add_child(AuthoringLayout.label("📦 %s   ·   needs: %s   ·   needed by: %s" % [id, ", ".join(requires) if not requires.is_empty() else "nothing", ", ".join(needed_by) if not needed_by.is_empty() else "nothing"], 13, true))
	dialog.confirmed.connect(dialog.queue_free)
	dialog.canceled.connect(dialog.queue_free)
	add_child(dialog)
	AuthoringLayout.popup(dialog, Vector2i(720, 520))

static func use_label(use: Dictionary) -> String:
	return "%s  %s   ·   %s" % [Wording.icon(use.row.def.type), Wording.title(use.row), str(use.text).trim_prefix("~ ")]

func show_uses(row: Dictionary) -> void:
	var found := workspace.uses(row.def.id)
	uses_title.text = "“%s” is used in %d place%s in your pack." % [Wording.title(row), found.size(), "" if found.size() == 1 else "s"] if not found.is_empty() else "Nothing in your pack uses “%s” yet." % Wording.title(row)
	uses_list.clear()
	for use: Dictionary in found:
		uses_list.add_item(use_label(use))
		uses_list.set_item_metadata(uses_list.item_count - 1, use)
		uses_list.set_item_tooltip(uses_list.item_count - 1, "%s, line %d" % [str(use.row.doc.path).get_file(), int(use.line)])
	AuthoringLayout.popup(uses_dialog, Vector2i(660, 460))

func rename(row: Dictionary) -> void:
	rename_row = row
	rename_name.text = Wording.title(row)
	rename_name.editable = row.def.fields.has("name")
	rename_id.remove_meta("typed")
	rename_id.text = row.def.id
	rename_id.editable = row.doc.writable
	rename_dialog.title = "Rename " + Wording.title(row)
	_refresh_rename()
	AuthoringLayout.popup(rename_dialog, Vector2i(720, 520))
	rename_name.grab_focus()
	rename_name.select_all()

func _refresh_rename() -> void:
	rename_list.clear()
	rename_plan.clear()
	var root := rename_list.create_item()
	var new_id := rename_id.text.strip_edges()
	if new_id == rename_row.def.id:
		rename_note.text = "The ID stays as it is; only the name changes." if rename_name.text.strip_edges() != Wording.title(rename_row) else "Write a new name."
		rename_note.theme_type_variation = "MutedLabel"
		return
	var issue := ContentTools.rename_problem(workspace, rename_row, new_id)
	if not issue.is_empty():
		rename_note.text = issue
		rename_note.theme_type_variation = "ErrorLabel"
		return
	rename_plan = ContentTools.rename_plan(workspace, rename_row, new_id)
	var twin := workspace.rows.any(func(other: Dictionary) -> bool: return other.def.id == rename_row.def.id and other.def.type != rename_row.def.type)
	rename_note.text = "%d line%s will change. Untick any line that means something else%s." % [rename_plan.size(), "" if rename_plan.size() == 1 else "s", (": another kind of content shares the ID “%s”" % rename_row.def.id) if twin else ""]
	rename_note.theme_type_variation = "MutedLabel"
	for entry: Dictionary in rename_plan:
		var item := rename_list.create_item(root)
		item.set_cell_mode(0, TreeItem.CELL_MODE_CHECK)
		item.set_checked(0, true)
		item.set_editable(0, true)
		item.set_text(0, "%s:   %s   →   %s" % [entry.where, entry.before, entry.after])
		item.set_metadata(0, entry)

func _apply_rename() -> void:
	var new_id := rename_id.text.strip_edges()
	var new_name := rename_name.text.strip_edges()
	var row := rename_row
	var error := ""
	if new_id != row.def.id:
		var chosen: Array = []
		var item := rename_list.get_root().get_first_child() if rename_list.get_root() != null else null
		while item != null:
			if item.is_checked(0): chosen.append(item.get_metadata(0))
			item = item.get_next()
		error = ContentTools.rename(workspace, row, new_id, chosen)
		if error.is_empty(): row = workspace.find_row(row.doc.path, row.def.type, new_id, row.def.mode, row.get("ordinal", 0))
	if error.is_empty() and not row.is_empty() and rename_name.editable and new_name != Wording.title(row) and not new_name.is_empty():
		error = workspace.transaction("Rename to " + new_name, func() -> String: return row.doc.set_field(row.def, "name", new_name))
		row = workspace.find_row(row.doc.path, row.def.type, row.def.id, row.def.mode, row.get("ordinal", 0))
	if not error.is_empty():
		rename_note.text = error
		rename_note.theme_type_variation = "ErrorLabel"
		return
	rename_dialog.hide()
	changed.emit(row)

func make_copy(row: Dictionary) -> void:
	var result := ContentTools.make_copy(workspace, row)
	if result.has("error"):
		problem.emit(result.error)
		return
	for other: Dictionary in workspace.rows:
		if other.doc.writable and other.def.type == result.type and other.def.id == result.id: changed.emit(other)

func delete(row: Dictionary) -> void:
	if not row.doc.writable or row.def.type in ["pack", "file"]:
		problem.emit("Choose content of your own pack to delete.")
		return
	delete_row = row
	var found := workspace.uses(row.def.id)
	var removable := ContentTools.removable_uses(workspace, row)
	delete_text.text = "Delete “%s”?" % Wording.title(row) + ("\nNothing else in your pack uses it." if found.is_empty() else "\nIt is used in %d place%s:" % [found.size(), "" if found.size() == 1 else "s"])
	delete_list.clear()
	delete_list.visible = not found.is_empty()
	for use: Dictionary in found:
		delete_list.add_item(("✂ " if use in removable else "⚠ ") + use_label(use))
		delete_list.set_item_tooltip(delete_list.item_count - 1, "This line can be removed with it." if use in removable else "This line stays and will need changing; the check will point to it.")
	delete_uses.visible = not removable.is_empty()
	delete_uses.button_pressed = not removable.is_empty()
	delete_uses.text = "Remove the %d action%s and link%s that use it too (marked ✂)" % [removable.size(), "" if removable.size() == 1 else "s", "" if removable.size() == 1 else "s"]
	delete_dialog.title = "Delete " + Wording.title(row)
	AuthoringLayout.popup(delete_dialog, Vector2i(640, 400))

## A quest's stages, with the stories that set each one.
func quest_flow(row: Dictionary) -> void:
	quest_row = row
	AuthoringLayout.clear(quest_body)
	var id: String = row.def.id
	var quest: Dictionary = workspace.preview_content().quests.get(id, {})
	var stages: Array = quest.get("stages", [])
	quest_dialog.title = "What moves the quest “%s”?" % Wording.title(row)
	quest_body.add_child(AuthoringLayout.label("A quest moves when a story sets its stage. Add that step to a story here; it goes to the end of the story, where you can move it.", 14, true))
	var done: Array = Array(str(row.doc.field_value(row.def, "done at")).split(",")).map(func(stage: String) -> String: return stage.strip_edges())
	var setting := RegEx.create_from_string("^~ quest " + id + " = (\\w+)")
	var by_stage: Dictionary = {}
	var reads: Array = []
	for use: Dictionary in workspace.uses(id):
		var matched := setting.search(str(use.text))
		if matched == null:
			if "quest " + id in str(use.text): reads.append(use)
			continue
		if not by_stage.has(matched.get_string(1)): by_stage[matched.get_string(1)] = []
		by_stage[matched.get_string(1)].append(use)
	for index in stages.size():
		var stage: String = stages[index]
		var panel := PanelContainer.new()
		panel.theme_type_variation = "Block"
		quest_body.add_child(panel)
		var box := VBoxContainer.new()
		panel.add_child(box)
		var note := "where the quest starts" if index == 0 else ("finishes the quest" if stage in done else "")
		box.add_child(AuthoringLayout.label("🏁  " + stage.replace("_", " ").capitalize() + ("   ·   " + note if not note.is_empty() else ""), 16))
		for use: Dictionary in by_stage.get(stage, []):
			var jump := Button.new()
			jump.theme_type_variation = "Ghost"
			jump.alignment = HORIZONTAL_ALIGNMENT_LEFT
			jump.text = "✓ Set in  %s  %s" % [Wording.icon(use.row.def.type), Wording.title(use.row)]
			jump.tooltip_text = "Open that story"
			jump.pressed.connect(func() -> void:
				quest_dialog.hide()
				open_line.emit(use.row.doc.path, int(use.line)))
			box.add_child(jump)
		if not by_stage.has(stage) and index > 0:
			var missing := AuthoringLayout.label("⚠ Nothing sets this stage yet.", 13)
			missing.theme_type_variation = "ErrorLabel"
			box.add_child(missing)
		if index == 0: continue
		var picker := PickerButton.new()
		picker.placeholder = "+ Set this stage from a story…"
		picker.text = picker.placeholder
		picker.theme_type_variation = "AddRow"
		picker.options = func() -> Array:
			var result: Array = []
			for story: Dictionary in workspace.rows:
				if story.doc.writable and story.def.mode == "define" and story.def.type in ["scene", "menu", "event", "character"]:
					result.append({"value": story.def.type + ":" + story.def.id, "label": Wording.title(story), "detail": StoryEditor.story_name(story)})
			return result
		picker.picked.connect(func(value: String) -> void: _set_stage_from(value, stage))
		box.add_child(picker)
	if not reads.is_empty():
		quest_body.add_child(AuthoringLayout.label("Stories that check this quest:", 15))
		for use: Dictionary in reads: quest_body.add_child(AuthoringLayout.label("%s  %s   ·   %s" % [Wording.icon(use.row.def.type), Wording.title(use.row), use.text], 13, true))
	if not quest_dialog.visible: AuthoringLayout.popup(quest_dialog, Vector2i(680, 540))

func _set_stage_from(value: String, stage: String) -> void:
	var parts := value.split(":")
	for story: Dictionary in workspace.rows:
		if not story.doc.writable or story.def.type != parts[0] or story.def.id != parts[1] or story.def.mode != "define": continue
		var line := "~ quest %s = %s" % [quest_row.def.id, stage]
		var error := workspace.transaction("Set “%s” to %s from %s" % [Wording.title(quest_row), stage.replace("_", " "), Wording.title(story)], func() -> String:
			return StoryBlocks.insert(story, StoryBlocks.end_spot(story, StoryGraph.structure(story)), line, story.doc.text))
		if not error.is_empty():
			problem.emit(error)
			return
		quest_row = workspace.find_row(quest_row.doc.path, quest_row.def.type, quest_row.def.id, quest_row.def.mode, quest_row.get("ordinal", 0))
		changed.emit(quest_row)
		quest_flow(quest_row)
		return
