class_name EditorTheme
extends RefCounted
## MAGE's ink and lantern palette, with a warm paper alternative.

static var light := false

static func color(key: String) -> Color:
	var dark := {"bg": "0f0e0c", "surface": "191714", "raised": "221f1b", "hover": "2d2924", "border": "38322b", "text": "ece5d8", "muted": "a9a092", "accent": "e3a04f", "selected": "5e4224", "bad": "dc735f", "info": "86aecd", "good": "93c08a"}
	var cream := {"bg": "f3ecde", "surface": "fff9ee", "raised": "ede2ce", "hover": "e5d6bc", "border": "c9b99d", "text": "332b22", "muted": "70604c", "accent": "87501d", "selected": "ead3ad", "bad": "a63b2d", "info": "3c677e", "good": "486b38"}
	return Color((cream if light else dark)[key])

## Category colours are chosen to stay apart for colour-blind readers
## (after Okabe and Ito); every category also has its own icon.
const CATEGORY := {
	"character": ["👤", "5aa9e6", "1f6fb2"], "item": ["🎒", "e6a23c", "9a5a00"], "location": ["📍", "4cc9a4", "0f7a5c"],
	"scene": ["💬", "c9b6f2", "6a4bb5"], "menu": ["💬", "c9b6f2", "6a4bb5"], "text": ["💬", "c9b6f2", "6a4bb5"], "event": ["⚡", "f2e05a", "8a7400"],
	"quest": ["🏁", "f08a6b", "b0431f"], "values": ["🔢", "9fb4c7", "4d6478"], "image": ["🖼", "d7a6c8", "8c4a78"],
	"form": ["🧬", "8fd3f4", "2a7da3"], "creature": ["⚔", "e07a7a", "a23333"], "zone": ["🧭", "4cc9a4", "0f7a5c"], "region": ["🧭", "4cc9a4", "0f7a5c"],
	"door": ["🚪", "4cc9a4", "0f7a5c"], "condition": ["❤", "e07a7a", "a23333"], "feat": ["★", "f2e05a", "8a7400"], "ending": ["✦", "f08a6b", "b0431f"],
	"scenario": ["▶", "f08a6b", "b0431f"], "pack": ["📦", "9fb4c7", "4d6478"], "hook": ["⚡", "f2e05a", "8a7400"],
	"shop": ["🛒", "e6a23c", "9a5a00"], "meter": ["📊", "9fb4c7", "4d6478"], "tag": ["🏷", "9fb4c7", "4d6478"], "filter": ["🚫", "9fb4c7", "4d6478"], "level": ["🎚", "9fb4c7", "4d6478"],
}

static func icon(kind: String) -> String:
	return CATEGORY[kind][0] if CATEGORY.has(kind) else "◇"

static func category_color(kind: String) -> Color:
	return Color(CATEGORY[kind][2 if light else 1]) if CATEGORY.has(kind) else color("muted")

static func box(fill: String, border: String = "", padding: int = 8, radius: int = 4) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = color(fill)
	style.set_corner_radius_all(radius)
	style.set_content_margin_all(padding)
	if not border.is_empty():
		style.border_color = color(border)
		style.set_border_width_all(1)
	return style

static var _symbols: Array[Font] = []

## Fonts for the symbols and icons the interface fonts lack. Naming them here
## spares a search through the system's fonts for every label that shows one.
static func symbol_fonts() -> Array[Font]:
	if _symbols.is_empty():
		for names: Array in [["DejaVu Sans", "Segoe UI Symbol", "Apple Symbols", "Arial Unicode MS"], ["Noto Sans Symbols2", "Noto Sans Symbols", "Symbola", "Segoe UI Symbol"], ["Noto Color Emoji", "Segoe UI Emoji", "Apple Color Emoji", "Noto Emoji"]]:
			var system := SystemFont.new()
			system.font_names = PackedStringArray(names)
			system.allow_system_fallback = false
			_symbols.append(system)
	return _symbols

static var _fonts: Dictionary = {}

## An interface font with the symbol fonts behind it. Symbol fonts are often
## taller than the text font, and a line is as tall as its tallest font: the
## extra is taken off again, so text keeps the spacing of its own font.
static func font(file: String) -> Font:
	if _fonts.has(file): return _fonts[file]
	var path := "res://fonts/" + file
	var base: Font
	if ResourceLoader.exists(path): base = load(path) as Font
	else:
		var named := SystemFont.new()
		named.font_names = PackedStringArray(["Barlow", "Noto Sans", "DejaVu Sans"])
		base = named
	# Measured at the smallest size in use, so small text is never squeezed;
	# headings come out a little airier.
	var ascent := base.get_ascent(13)
	var descent := base.get_descent(13)
	if base.fallbacks.is_empty(): base.fallbacks = symbol_fonts()
	var result := FontVariation.new()
	result.base_font = base
	result.set_spacing(TextServer.SPACING_TOP, -int(round(base.get_ascent(13) - ascent)))
	result.set_spacing(TextServer.SPACING_BOTTOM, -int(round(base.get_descent(13) - descent)))
	_fonts[file] = result
	return result

static func build() -> Theme:
	var theme := Theme.new()
	theme.default_font = font("Barlow-Medium.ttf")
	theme.default_font_size = 16
	for type in ["Label", "Button", "OptionButton", "MenuButton", "CheckButton", "CheckBox", "LineEdit", "TextEdit", "CodeEdit", "Tree", "ItemList", "PopupMenu", "TabBar", "TabContainer", "SpinBox", "GraphNode", "Window", "TooltipLabel"]:
		for name in ["font_color", "font_hover_color", "font_pressed_color", "font_hover_pressed_color", "font_focus_color", "font_selected_color", "font_unselected_color", "font_outline_color"]:
			theme.set_color(name, type, color("text") if name != "font_outline_color" else Color.TRANSPARENT)
		theme.set_color("font_disabled_color", type, color("muted"))
		theme.set_color("font_placeholder_color", type, color("muted"))
	for type in ["Panel", "PanelContainer", "AcceptDialog", "ConfirmationDialog", "PopupPanel", "PopupMenu", "Window", "TooltipPanel", "Tree", "ItemList", "TabContainer"]:
		theme.set_stylebox("panel", type, box("surface", "border"))
	for type in ["Button", "OptionButton", "MenuButton"]:
		for name in ["icon_normal_color", "icon_hover_color", "icon_pressed_color", "icon_hover_pressed_color", "icon_focus_color"]:
			theme.set_color(name, type, color("text"))
		theme.set_color("icon_disabled_color", type, color("muted"))
		theme.set_stylebox("normal", type, box("raised"))
		theme.set_stylebox("hover", type, box("hover", "accent"))
		theme.set_stylebox("pressed", type, box("selected", "accent"))
		theme.set_stylebox("hover_pressed", type, box("selected", "accent"))
		theme.set_stylebox("disabled", type, box("surface"))
		var focus := box("raised", "accent")
		focus.draw_center = false
		theme.set_stylebox("focus", type, focus)
	for type in ["LineEdit", "TextEdit", "CodeEdit"]:
		theme.set_stylebox("normal", type, box("bg", "border"))
		theme.set_stylebox("read_only", type, box("surface", "border"))
		var focus := box("bg", "accent")
		focus.draw_center = false
		theme.set_stylebox("focus", type, focus)
		theme.set_color("caret_color", type, color("accent"))
		theme.set_color("selection_color", type, color("selected"))
		theme.set_color("font_readonly_color", type, color("muted"))
		theme.set_color("background_color", type, Color.TRANSPARENT)
	for type in ["TabBar", "TabContainer"]:
		theme.set_stylebox("tab_selected", type, box("selected", "accent", 10))
		theme.set_stylebox("tab_unselected", type, box("raised", "", 10))
		theme.set_stylebox("tab_hovered", type, box("hover", "", 10))
		theme.set_stylebox("tab_disabled", type, box("surface", "", 10))
	for type in ["Tree", "ItemList"]:
		theme.set_stylebox("selected", type, box("selected", "", 4))
		theme.set_stylebox("selected_focus", type, box("selected", "accent", 4))
		theme.set_stylebox("hovered", type, box("hover", "", 4))
		theme.set_color("guide_color", type, color("border"))
		theme.set_constant("v_separation", type, 7)
	theme.set_stylebox("hover", "PopupMenu", box("selected"))
	theme.set_stylebox("panel", "GraphEdit", box("bg", "", 0))
	theme.set_stylebox("menu_panel", "GraphEdit", box("raised", "border", 4))
	theme.set_color("grid_minor", "GraphEdit", Color(color("border"), 0.45))
	theme.set_color("grid_major", "GraphEdit", color("border"))
	theme.set_stylebox("panel", "GraphNode", box("surface", "border", 12))
	theme.set_stylebox("panel_selected", "GraphNode", box("surface", "accent", 12))
	theme.set_stylebox("titlebar", "GraphNode", box("raised", "", 10))
	theme.set_stylebox("titlebar_selected", "GraphNode", box("selected", "accent", 10))
	theme.set_font("title_font", "GraphNode", font("Barlow-SemiBold.ttf"))
	theme.set_color("title_color", "GraphNode", color("text"))
	theme.set_color("title_color", "Window", color("text"))
	var window_frame := box("raised", "border", 10)
	window_frame.expand_margin_top = 30
	theme.set_stylebox("embedded_border", "Window", window_frame)
	theme.set_stylebox("embedded_unfocused_border", "Window", window_frame)
	var close_icon := Image.new()
	close_icon.load_svg_from_string('<svg xmlns="http://www.w3.org/2000/svg" width="16" height="16"><path d="M4 4L12 12M12 4L4 12" stroke="#%s" stroke-width="2" stroke-linecap="round"/></svg>' % color("text").to_html(false))
	for state in ["close", "close_pressed"]:
		theme.set_icon(state, "Window", ImageTexture.create_from_image(close_icon))
	for entry: Array in [["CheckBox", "checkbox"], ["CheckButton", "button"]]:
		theme.set_color(str(entry[1]) + "_checked_color", str(entry[0]), color("accent"))
		theme.set_color(str(entry[1]) + "_unchecked_color", str(entry[0]), color("muted"))
	theme.set_type_variation("StoryBubble", "TextEdit")
	theme.set_type_variation("PrimaryButton", "Button")
	theme.set_stylebox("normal", "PrimaryButton", box("selected", "accent", 10))
	theme.set_type_variation("ChoiceCard", "Button")
	theme.set_stylebox("normal", "ChoiceCard", box("raised", "border", 14))
	theme.set_type_variation("StepButton", "Button")
	var step := box("surface", "", 9)
	step.border_color = color("border")
	step.border_width_bottom = 2
	theme.set_stylebox("normal", "StepButton", step)
	var selected_step := box("surface", "", 9)
	selected_step.border_color = color("accent")
	selected_step.border_width_bottom = 3
	theme.set_stylebox("pressed", "StepButton", selected_step)
	theme.set_stylebox("hover_pressed", "StepButton", selected_step)
	theme.set_stylebox("normal", "StoryBubble", box("raised", "", 10, 9))
	theme.set_stylebox("read_only", "StoryBubble", box("raised", "", 10, 9))
	theme.set_font("font", "StoryBubble", font("Literata.ttf"))
	theme.set_type_variation("MutedLabel", "Label")
	theme.set_color("font_color", "MutedLabel", color("muted"))
	theme.set_type_variation("AccentLabel", "Label")
	theme.set_color("font_color", "AccentLabel", color("accent"))
	theme.set_type_variation("ErrorLabel", "Label")
	theme.set_color("font_color", "ErrorLabel", color("bad"))
	for type in ["HScrollBar", "VScrollBar"]:
		theme.set_stylebox("scroll", type, box("bg", "", 3))
		for state in ["grabber", "grabber_highlight", "grabber_pressed"]:
			theme.set_stylebox(state, type, box("border" if state == "grabber" else "accent", "", 4))
	theme.set_stylebox("slider", "HSlider", box("border", "", 2))
	theme.set_stylebox("grabber_area", "HSlider", box("accent", "", 2))
	for type in ["VBoxContainer", "HBoxContainer"]:
		theme.set_constant("separation", type, 8)
	# Story blocks: quiet cards, chips for the parts an author can change.
	theme.set_type_variation("Block", "PanelContainer")
	theme.set_stylebox("panel", "Block", box("surface", "border", 6, 6))
	theme.set_type_variation("BlockSelected", "PanelContainer")
	var chosen := box("selected", "accent", 6, 6)
	chosen.set_border_width_all(2)
	theme.set_stylebox("panel", "BlockSelected", chosen)
	theme.set_type_variation("BlockProblem", "PanelContainer")
	var problem := box("surface", "bad", 6, 6)
	problem.border_width_left = 4
	theme.set_stylebox("panel", "BlockProblem", problem)
	theme.set_type_variation("Toast", "PanelContainer")
	theme.set_stylebox("panel", "Toast", box("raised", "accent", 8, 6))
	theme.set_type_variation("Card", "PanelContainer")
	theme.set_stylebox("panel", "Card", box("surface", "border", 12, 8))
	theme.set_type_variation("Chip", "Button")
	for state in ["normal", "hover", "pressed", "focus", "disabled"]:
		var chip := box("raised" if state in ["normal", "disabled"] else "hover", "accent" if state in ["hover", "pressed", "focus"] else "border", 3, 10)
		chip.content_margin_left = 8
		chip.content_margin_right = 8
		if state == "focus": chip.draw_center = false
		theme.set_stylebox(state, "Chip", chip)
	theme.set_color("font_color", "Chip", color("accent"))
	theme.set_color("font_hover_color", "Chip", color("text"))
	theme.set_color("font_disabled_color", "Chip", color("text"))
	theme.set_type_variation("Ghost", "Button")
	for state in ["normal", "disabled"]:
		theme.set_stylebox(state, "Ghost", box("surface", "", 4, 4))
	theme.set_stylebox("hover", "Ghost", box("hover", "", 4, 4))
	theme.set_stylebox("pressed", "Ghost", box("selected", "", 4, 4))
	theme.get_stylebox("normal", "Ghost").draw_center = false
	theme.get_stylebox("disabled", "Ghost").draw_center = false
	theme.set_color("font_color", "Ghost", color("muted"))
	theme.set_type_variation("AddRow", "Button")
	var add := box("bg", "border", 5, 6)
	add.draw_center = false
	theme.set_stylebox("normal", "AddRow", add)
	theme.set_stylebox("hover", "AddRow", box("hover", "accent", 5, 6))
	theme.set_stylebox("pressed", "AddRow", box("selected", "accent", 5, 6))
	theme.set_color("font_color", "AddRow", color("muted"))
	theme.set_type_variation("StoryLabel", "Label")
	theme.set_font("font", "StoryLabel", font("Literata.ttf"))
	theme.set_type_variation("CodeLabel", "Label")
	theme.set_color("font_color", "CodeLabel", color("muted"))
	var mono := SystemFont.new()
	mono.font_names = PackedStringArray(["DejaVu Sans Mono", "Noto Sans Mono", "Liberation Mono", "monospace"])
	mono.fallbacks = symbol_fonts()
	theme.set_font("font", "CodeLabel", mono)
	theme.set_font_size("font_size", "CodeLabel", 12)
	theme.set_type_variation("GoodLabel", "Label")
	theme.set_color("font_color", "GoodLabel", color("good"))
	return theme
