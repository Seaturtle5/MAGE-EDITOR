class_name WritingWindow
extends Window
## A large window to write in: the words the player reads, with a toolbar for
## everything the game understands inside text and the words as a sample
## player reads them. One instance is opened again for each piece of text.

## The orders a variation can go through, in the author's words.
const ORDERS := [["at random", "A different one each time"], ["cycling", "One after the other, then from the start"], ["stopping", "One after the other, then the last one stays"], ["sticky", "One is picked the first time and kept"]]
## Words about the player's body: what the menu says, and what is inserted.
const BODY_WORDS := [["Kind of body (wolf, human…)", "[body type of player]"], ["A word for the body (sleek, burly…)", "[body descriptor of player]"], ["Species", "[species of player]"], ["Head", "[head of player]"], ["Cock", "[cock of player]"], ["Cock size", "[cock size of player]"], ["Balls", "[balls of player]"], ["Cunt size", "[cunt size of player]"], ["Breast size", "[breast size of player]"], ["Cup size", "[cup size]"]]
const WIDE := 860

var workspace: PackWorkspace
var input: TextEdit
var error: Label
var count: Label
var hint: Label
var toolbar: HFlowContainer
var markup_tools: Array[Control] = []
var preview: RichTextLabel
var preview_panel: PanelContainer
var preview_switch: Button
var preview_update: Button
var discard: ConfirmationDialog
var conditions: ConditionDialog
var original := ""
var seed_number := 1
var _apply: Callable
var _check: Callable
var _sample: Callable
var _context: Array = []
var _event := ""
var _then: Callable
var _timer: Timer
var _body: HBoxContainer
var _back: Panel

func _init() -> void:
	visible = false
	title = "Writing"
	transient = true
	exclusive = true
	min_size = Vector2i(520, 360)
	close_requested.connect(cancel)
	size_changed.connect(_fit)

func _ready() -> void:
	_back = Panel.new()
	_back.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(_back)
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side: String in ["margin_left", "margin_right", "margin_top", "margin_bottom"]: margin.add_theme_constant_override(side, 14)
	add_child(margin)
	var layout := VBoxContainer.new()
	layout.add_theme_constant_override("separation", 8)
	margin.add_child(layout)
	toolbar = HFlowContainer.new()
	toolbar.add_theme_constant_override("h_separation", 4)
	layout.add_child(toolbar)
	_build_toolbar()
	hint = AuthoringLayout.label("", 13, true)
	layout.add_child(hint)
	_body = HBoxContainer.new()
	_body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_body.add_theme_constant_override("separation", 14)
	_body.alignment = BoxContainer.ALIGNMENT_CENTER
	layout.add_child(_body)
	input = TextEdit.new()
	input.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
	input.size_flags_vertical = Control.SIZE_EXPAND_FILL
	input.theme_type_variation = "StoryBubble"
	input.add_theme_font_size_override("font_size", 18)
	input.add_theme_constant_override("line_spacing", 6)
	input.caret_blink = true
	input.syntax_highlighter = _highlighter()
	input.text_changed.connect(_changed)
	input.gui_input.connect(_key)
	_body.add_child(input)
	preview_panel = PanelContainer.new()
	preview_panel.custom_minimum_size.x = 340
	preview_panel.hide()
	_body.add_child(preview_panel)
	var side := VBoxContainer.new()
	preview_panel.add_child(side)
	var side_top := HBoxContainer.new()
	side.add_child(side_top)
	var side_title := AuthoringLayout.label("AS THE PLAYER READS IT", 12, true)
	side_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	side_title.autowrap_mode = TextServer.AUTOWRAP_OFF
	side_top.add_child(side_title)
	var again := Button.new()
	again.text = "🎲"
	again.tooltip_text = "Another reading: words that vary are picked again."
	again.focus_mode = Control.FOCUS_NONE
	again.pressed.connect(func() -> void:
		seed_number += 1
		_show_preview())
	side_top.add_child(again)
	preview_update = Button.new()
	preview_update.text = "↻ Update"
	preview_update.tooltip_text = "Many packs are loaded, so this is updated when you ask."
	preview_update.pressed.connect(_show_preview)
	preview_update.hide()
	side_top.add_child(preview_update)
	preview = RichTextLabel.new()
	preview.size_flags_vertical = Control.SIZE_EXPAND_FILL
	preview.bbcode_enabled = false
	preview.selection_enabled = true
	preview.add_theme_font_override("normal_font", EditorTheme.font("Literata.ttf"))
	preview.add_theme_font_override("italics_font", EditorTheme.font("Literata-Italic.ttf"))
	var strong := FontVariation.new()
	strong.base_font = EditorTheme.font("Literata.ttf")
	strong.variation_embolden = 0.7
	preview.add_theme_font_override("bold_font", strong)
	preview.add_theme_font_size_override("normal_font_size", 16)
	preview.add_theme_font_size_override("italics_font_size", 16)
	preview.add_theme_font_size_override("bold_font_size", 16)
	side.add_child(preview)
	error = AuthoringLayout.label("", 14)
	error.theme_type_variation = "ErrorLabel"
	layout.add_child(error)
	var footer := HBoxContainer.new()
	layout.add_child(footer)
	count = AuthoringLayout.label("", 13, true)
	count.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	count.autowrap_mode = TextServer.AUTOWRAP_OFF
	footer.add_child(count)
	var keys := AuthoringLayout.label("Ctrl+Enter keeps the text · Esc leaves it", 12, true)
	keys.autowrap_mode = TextServer.AUTOWRAP_OFF
	footer.add_child(keys)
	var leave := Button.new()
	leave.text = "Cancel"
	leave.pressed.connect(cancel)
	footer.add_child(leave)
	var keep := Button.new()
	keep.text = "Done"
	keep.theme_type_variation = "PrimaryButton"
	keep.tooltip_text = "Keep this text (Ctrl+Enter)."
	keep.pressed.connect(apply)
	footer.add_child(keep)
	discard = ConfirmationDialog.new()
	discard.title = "Leave without keeping?"
	discard.dialog_text = "What you wrote here has not been kept."
	discard.ok_button_text = "Leave it"
	discard.cancel_button_text = "Keep writing"
	discard.confirmed.connect(_close)
	add_child(discard)
	conditions = ConditionDialog.new()
	add_child(conditions)
	conditions.applied.connect(func(condition: String) -> void:
		if _then.is_valid(): _then.call(condition))
	_timer = Timer.new()
	_timer.one_shot = true
	_timer.wait_time = 0.35
	_timer.timeout.connect(_settled)
	add_child(_timer)

## Markup in another colour, so the words stand out from what the game fills in.
func _highlighter() -> CodeHighlighter:
	var colours := CodeHighlighter.new()
	var plain := EditorTheme.color("text")
	colours.number_color = plain
	colours.symbol_color = plain
	colours.function_color = plain
	colours.member_variable_color = plain
	colours.add_color_region("[", "]", EditorTheme.color("info"), false)
	return colours

func _tool(text: String, tip: String, action: Callable, markup: bool = false) -> Button:
	var button := Button.new()
	button.text = text
	button.tooltip_text = tip
	button.focus_mode = Control.FOCUS_NONE
	button.pressed.connect(action)
	toolbar.add_child(button)
	if markup: markup_tools.append(button)
	return button

func _menu(text: String, tip: String, entries: Array, markup: bool = true) -> MenuButton:
	var button := MenuButton.new()
	button.text = text
	button.flat = false
	button.tooltip_text = tip
	button.focus_mode = Control.FOCUS_NONE
	var popup := button.get_popup()
	for index in entries.size():
		var entry: Array = entries[index]
		if entry.is_empty(): popup.add_separator()
		else: popup.add_item(str(entry[0]), index)
	popup.id_pressed.connect(func(id: int) -> void:
		var entry: Array = entries[id]
		(entry[1] as Callable).call())
	toolbar.add_child(button)
	if markup: markup_tools.append(button)
	return button

func _gap() -> void:
	var gap := VSeparator.new()
	toolbar.add_child(gap)

func _build_toolbar() -> void:
	_tool("↶", "Undo (Ctrl+Z)", func() -> void:
		input.undo()
		input.grab_focus())
	_tool("↷", "Redo (Ctrl+Shift+Z)", func() -> void:
		input.redo()
		input.grab_focus())
	_gap()
	var bold := _tool("B", "Bold: strong words (Ctrl+B).", func() -> void: surround("**", "**", "words"), true)
	bold.add_theme_font_override("font", EditorTheme.font("Barlow-SemiBold.ttf"))
	var italic := _tool("I", "Italic: emphasis, thoughts (Ctrl+I).", func() -> void: surround("*", "*", "words"), true)
	italic.add_theme_font_override("font", EditorTheme.font("Literata-Italic.ttf"))
	_gap()
	var insert: Array = [
		["The player's name", func() -> void: put("[name of player]")],
		["A character's name…", func() -> void: _pick_who("name")],
		[],
		["He / she / they, for a character…", func() -> void: _pick_who("he")],
		["Him / her / them…", func() -> void: _pick_who("him")],
		["His / her / their…", func() -> void: _pick_who("his")],
		["Himself / herself / themselves…", func() -> void: _pick_who("himself")],
		[],
		["A counter's number…", func() -> void: _pick_counter()],
		["A text kept for reuse…", func() -> void: _pick_snippet()]]
	_menu("➕ Insert ▾", "Insert words the game fills in: a name, he or she, a counter's number, a text kept for reuse.", insert)
	var body: Array = []
	for pair: Array in BODY_WORDS: body.append([pair[0], put.bind(str(pair[1]))])
	_menu("🧬 Body ▾", "Insert words about the player's body as it is at that moment.", body)
	var vary: Array = []
	for pair: Array in ORDERS: vary.append([pair[1], _vary.bind(str(pair[0]))])
	_menu("🔀 Vary ▾", "Offer several versions of the selected words. Choose how the game goes through them.", vary)
	_tool("◇ Only if…", "Show the selected words only when a condition holds, and other words otherwise.", _only_if, true)
	var styles: Array = [
		["🎲 A roll: the numbers of a check", func() -> void: surround("[roll]", "[/roll]", "roll")],
		["⚠ A warning", func() -> void: surround("[warning]", "[/warning]", "warning")]]
	_menu("🖍 Style ▾", "Mark the selected words as a roll or a warning; the game shows them in their own colour.", styles)
	var spacer := Control.new()
	spacer.custom_minimum_size.x = 12
	toolbar.add_child(spacer)
	preview_switch = _tool("👁 As the player reads it", "Show the text beside your writing as a sample player reads it.", func() -> void:
		preview_panel.visible = not preview_panel.visible
		EditorPrefs.write("writing", "preview", preview_panel.visible)
		_fit()
		_show_preview())
	preview_switch.toggle_mode = true

## Opens the window on a piece of text. `options`: title, text, hint,
## placeholder, markup (false for words that take none), apply (func(text) ->
## problem, "" when kept), check (func(text) -> problem, asked while writing),
## sample (func() -> the sample player of the preview), context and event (for
## conditions).
func open(pack: PackWorkspace, options: Dictionary) -> void:
	workspace = pack
	# The colours of the theme as it is now: it may have been changed since the window was made.
	_back.add_theme_stylebox_override("panel", EditorTheme.box("surface", "", 0, 0))
	input.syntax_highlighter = _highlighter()
	title = str(options.get("title", "Writing"))
	original = str(options.get("text", ""))
	_apply = options.get("apply", Callable())
	_check = options.get("check", Callable())
	_sample = options.get("sample", Callable())
	_context = options.get("context", [])
	_event = str(options.get("event", ""))
	var markup: bool = options.get("markup", true)
	for control: Control in markup_tools: control.visible = markup
	preview_switch.visible = markup
	preview_panel.visible = markup and bool(EditorPrefs.read("writing", "preview", true))
	preview_switch.set_pressed_no_signal(preview_panel.visible)
	preview_update.visible = workspace != null and workspace.heavy()
	hint.text = str(options.get("hint", "An empty line starts a new paragraph. Select words, then choose a tool to change how they are shown."))
	input.placeholder_text = str(options.get("placeholder", "Write what the player reads."))
	input.text = original
	input.clear_undo_history()
	input.set_caret_line(input.get_line_count() - 1)
	input.set_caret_column(input.get_line(input.get_line_count() - 1).length())
	error.text = ""
	_count()
	AuthoringLayout.popup(self, Vector2i(4000, 4000))
	_fit()
	input.grab_focus()
	preview.clear()
	if preview_panel.visible and not preview_update.visible: _show_preview()

## The text column stays a comfortable width however wide the window is.
func _fit() -> void:
	if input == null: return
	var room := float(size.x) - 28.0 - (preview_panel.custom_minimum_size.x + 14.0 if preview_panel.visible else 0.0)
	input.custom_minimum_size.x = clampf(room, 280.0, float(WIDE))
	input.size_flags_horizontal = Control.SIZE_SHRINK_CENTER if room > WIDE else Control.SIZE_EXPAND_FILL

func changed() -> bool:
	return input.text != original

## Keeps the text: asks the opener, and stays open with its answer when it refuses.
func apply() -> void:
	var problem := str(_apply.call(input.text)) if _apply.is_valid() else ""
	if not problem.is_empty():
		error.text = problem
		return
	_close()

func cancel() -> void:
	if changed(): discard.popup_centered()
	else: _close()

func _close() -> void:
	hide()
	_apply = Callable()
	_check = Callable()

func _key(event: InputEvent) -> void:
	if not (event is InputEventKey) or not event.pressed: return
	var key := event as InputEventKey
	var command := key.ctrl_pressed or key.meta_pressed
	if key.keycode == KEY_ESCAPE: cancel()
	elif command and key.keycode in [KEY_ENTER, KEY_KP_ENTER]: apply()
	elif command and key.keycode == KEY_B and markup_tools[0].visible: surround("**", "**", "words")
	elif command and key.keycode == KEY_I and markup_tools[0].visible: surround("*", "*", "words")
	else: return
	input.accept_event()

func _changed() -> void:
	_count()
	error.text = ""
	_timer.start()

func _count() -> void:
	var words := 0
	for piece: String in input.text.replace("\n", " ").replace("\t", " ").split(" ", false):
		if not piece.is_empty(): words += 1
	var paragraphs := paragraphs_of(input.text).size()
	count.text = "%d word%s · %d paragraph%s" % [words, "" if words == 1 else "s", paragraphs, "" if paragraphs == 1 else "s"] if words > 0 else "Nothing written yet"

## A pause in the typing: say what the game cannot read, and show the reading again.
func _settled() -> void:
	if not visible: return
	error.text = problem_in(input.text)
	if error.text.is_empty() and _check.is_valid(): error.text = str(_check.call(input.text))
	if preview_panel.visible and not preview_update.visible: _show_preview()

## The paragraphs of a text: an empty line parts them, and the lines of one are joined.
static func paragraphs_of(text: String) -> PackedStringArray:
	var result := PackedStringArray()
	var current := PackedStringArray()
	for line: String in (text.replace("\r\n", "\n") + "\n").split("\n"):
		if line.strip_edges().is_empty():
			if not current.is_empty(): result.append(" ".join(current))
			current.clear()
		else: current.append(line.strip_edges())
	return result

## What the game cannot read in a text's markup, in plain words; "" when it reads all of it.
static func problem_in(text: String) -> String:
	for paragraph: String in paragraphs_of(text):
		var compiled := TextTemplate.compile(paragraph)
		if compiled.has("error"): return "The game cannot read this yet: " + str(compiled.error) + "."
		# A bracket left open is shown to the player as it is: almost never what was meant.
		var open := paragraph.rfind("[")
		if open >= 0 and paragraph.find("]", open) < 0: return "A [ is never closed: “%s”." % paragraph.substr(open).left(30)
	return ""

func _show_preview() -> void:
	if preview == null or workspace == null or not preview_panel.visible: return
	preview.clear()
	var preset: Dictionary = _sample.call() if _sample.is_valid() else {}
	var game := StoryPreview.sample_game(workspace.preview_content(), preset, seed_number)
	var first := true
	for paragraph: String in paragraphs_of(input.text):
		if not first: preview.add_text("\n\n")
		first = false
		var compiled := TextTemplate.compile(paragraph)
		if compiled.has("error"):
			preview.push_color(EditorTheme.color("bad"))
			preview.add_text(paragraph)
			preview.pop()
			continue
		for span: Dictionary in game.render(compiled):
			var pushed := 0
			if span.get("bold", false):
				preview.push_bold()
				pushed += 1
			if span.get("italic", false):
				preview.push_italics()
				pushed += 1
			if str(span.get("class", "")) in ["roll", "warning"]:
				preview.push_color(EditorTheme.color("info" if span["class"] == "roll" else "bad"))
				pushed += 1
			preview.add_text(str(span.text))
			for _index in pushed: preview.pop()
	game.dispose()
	if first:
		preview.push_color(EditorTheme.color("muted"))
		preview.add_text("What you write shows here as a player reads it: names filled in, one version of words that vary.")
		preview.pop()

# ------------------------------------------------------------------ tools

## Puts words in at the caret, in place of what is selected.
func put(words: String) -> void:
	input.insert_text_at_caret(words)
	input.grab_focus()

## Puts `before` and `after` around the selected words, or around `sample`
## when nothing is selected; the words inside stay selected.
func surround(before: String, after: String, sample: String) -> void:
	var inner := input.get_selected_text() if input.has_selection() else sample
	input.begin_complex_operation()
	input.insert_text_at_caret(before + inner + after)
	input.end_complex_operation()
	if "\n" not in inner:
		var line := input.get_caret_line()
		var end := input.get_caret_column() - after.length()
		input.select(line, end - inner.length(), line, end)
	input.grab_focus()

func _vary(order: String) -> void:
	var inner := input.get_selected_text() if input.has_selection() else "one version"
	put("[one of]" + inner + "[or]another version[" + order + "]")

func _only_if() -> void:
	var inner := input.get_selected_text() if input.has_selection() else "these words"
	_then = func(condition: String) -> void: put("[if " + condition + "]" + inner + "[else]other words[end if]")
	conditions.open(workspace, "", _context, _event, "Show these words only if…")

func _below_toolbar() -> Vector2i:
	return Vector2i(toolbar.get_screen_position()) + Vector2i(0, int(toolbar.size.y) + 2)

func _pick(kind: String, then: Callable) -> void:
	var control := SlotControl.make(workspace, {"name": "pick", "kind": kind, "default": "", "hidden": false, "optional": false}, "")
	control.hide()
	toolbar.add_child(control)
	control.edited.connect(func() -> void:
		then.call(control.value())
		control.queue_free())
	control.picker.open(_below_toolbar())

func _pick_who(word: String) -> void:
	_pick("who", func(who: String) -> void: put("[%s of %s]" % [word, who]))

func _pick_counter() -> void:
	_pick("value.number", func(counter: String) -> void: put("[" + counter + "]"))

func _pick_snippet() -> void:
	var picker := PickerButton.new()
	picker.workspace = workspace
	picker.hide()
	picker.options = func() -> Array:
		var result: Array = []
		var seen: Dictionary = {}
		for row: Dictionary in workspace.rows:
			if row.def.type != "text" or seen.has(row.def.id): continue
			seen[row.def.id] = true
			result.append({"value": row.def.id, "label": str(row.def.id).replace("_", " "), "detail": "" if row.doc.writable else str(row.pack)})
		return result
	picker.picked.connect(func(id: String) -> void:
		put("[" + id + "]")
		picker.queue_free())
	toolbar.add_child(picker)
	picker.open(_below_toolbar())
