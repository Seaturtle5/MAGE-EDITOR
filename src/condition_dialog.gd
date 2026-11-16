class_name ConditionDialog
extends ConfirmationDialog
## Builds one condition and hands it back as text the engine has checked.

signal applied(condition: String)
var builder: ConditionBuilder
var summary: Label
var raw: Label
var error: Label
var allow_empty := false

func _ready() -> void:
	title = "Only if…"
	ok_button_text = "Apply"
	dialog_hide_on_ok = false
	var body := VBoxContainer.new()
	body.custom_minimum_size = Vector2(600, 380)
	add_child(body)
	body.add_child(AuthoringLayout.label("This happens only when:", 16))
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_child(scroll)
	builder = ConditionBuilder.new()
	builder.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	builder.changed.connect(_refresh)
	scroll.add_child(builder)
	summary = AuthoringLayout.label("", 15)
	body.add_child(summary)
	raw = AuthoringLayout.label("", 12)
	raw.theme_type_variation = "CodeLabel"
	body.add_child(raw)
	error = AuthoringLayout.label("", 14)
	error.theme_type_variation = "ErrorLabel"
	body.add_child(error)
	get_ok_button().theme_type_variation = "PrimaryButton"
	confirmed.connect(_apply)

func open(workspace: PackWorkspace, text: String = "", context: Array = [], event: String = "", heading: String = "Only if…", may_be_empty: bool = false) -> void:
	title = heading
	allow_empty = may_be_empty
	builder.configure(workspace, text, context, event)
	error.text = ""
	_refresh()
	AuthoringLayout.popup(self, Vector2i(660, 520))
	if text.strip_edges().is_empty(): builder.add_to.call_deferred(builder.root)

func _refresh() -> void:
	var text := builder.line()
	summary.text = "In words:  " + BlockCatalog.condition_sentence(text, builder.workspace) if not text.is_empty() else "No condition yet."
	raw.text = "if " + text if not text.is_empty() and EditorPrefs.read("authoring", "show_line", false) else ""
	error.text = ""

func _apply() -> void:
	var text := builder.line()
	if text.is_empty() and not allow_empty:
		error.text = "Add at least one condition, or cancel."
		return
	if not text.is_empty() and Condition.compile(text).has("error"):
		error.text = "The engine cannot read this condition: " + str(Condition.compile(text).error)
		return
	hide()
	applied.emit(text)
