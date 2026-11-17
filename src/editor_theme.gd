class_name EditorTheme
extends RefCounted
## MAGE's ink and lantern palette, with a warm paper alternative.

static var light := false

## The palette, in layers from the back to the front: `bg` behind everything,
## `well` for what is typed or listed in, `surface` for pages and panels,
## `raised` for buttons and cards, `popup` for what floats over the rest
## (menus, dropdowns, pickers, tooltips, the title bars of dialogs). Each layer
## is told from the next by its fill and by a line: `border` around what lies on
## a page, the stronger `edge` around what floats. `muted` is second-rank text,
## `faint` is text that cannot be used now. The dark theme's background and
## text are the game's own; `theme_test.gd` keeps the layers apart and the
## text readable in both themes.
static func color(key: String) -> Color:
	var dark := {"bg": "0f0e0c", "well": "090807", "surface": "1b1916", "raised": "2a2621", "hover": "3b352d", "border": "4b4339", "edge": "7a6e5b", "popup": "342f28", "text": "ece5d8", "muted": "b5ac9d", "faint": "857c6e", "accent": "e8a655", "selected": "553a1c", "bad": "e27a66", "info": "8db4d2", "good": "9bc791", "on_accent": "1a1208"}
	var cream := {"bg": "e9dfcc", "well": "fffefb", "surface": "fbf6ea", "raised": "f0e5cf", "hover": "e4d3b3", "border": "bfaa85", "edge": "8c7955", "popup": "fffdf7", "text": "2b241b", "muted": "64553e", "faint": "8b7d66", "accent": "8a4f17", "selected": "ecd2a4", "bad": "a63b2d", "info": "2f6480", "good": "436b34", "on_accent": "fff8ea"}
	return Color((cream if light else dark)[key])

## The colours of the board's dots and lines: "in" where a story is entered,
## "link" for a way the author can lead elsewhere, "flow" for a way that
## follows from the blocks, "play" for a story that is played and returned from.
static func wire(kind: String) -> Color:
	var dark := {"in": "d6a86b", "link": "e8a660", "flow": "8fb9cf", "play": "a4c9a2"}
	var cream := {"in": "9a6a2c", "link": "b3621a", "flow": "3c7594", "play": "4d7a48"}
	return Color((cream if light else dark)[kind])

## The shadow under what floats: it lifts a dialog off the page behind it.
static func shade() -> Color:
	return Color(0.2, 0.14, 0.05, 0.3) if light else Color(0, 0, 0, 0.6)

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

## A small picture drawn from SVG, for the marks the interface needs in the
## theme's own colours (the built-in ones are made for a dark background only).
static func mark(body: String, size: int = 16) -> ImageTexture:
	var image := Image.new()
	image.load_svg_from_string('<svg xmlns="http://www.w3.org/2000/svg" width="%d" height="%d" viewBox="0 0 16 16">%s</svg>' % [size, size, body])
	return ImageTexture.create_from_image(image)

## A box that floats: the popup fill, the strong line around it and a shadow.
static func floating(padding: int = 6, radius: int = 6) -> StyleBoxFlat:
	var style := box("popup", "edge", padding, radius)
	style.shadow_color = shade()
	style.shadow_size = 10
	style.shadow_offset = Vector2(0, 3)
	return style

static func build() -> Theme:
	var theme := Theme.new()
	theme.default_font = font("Barlow-Medium.ttf")
	# A control that holds its text before it joins the window is measured once
	# with the built-in theme. Its font searches the system's fonts for every
	# symbol, which makes a long list of blocks slow to build: give it this font.
	ThemeDB.get_default_theme().default_font = theme.default_font
	ThemeDB.fallback_font = theme.default_font
	theme.default_font_size = 16
	var text := color("text").to_html(false)
	var faint := color("faint").to_html(false)
	var muted := color("muted").to_html(false)
	var accent := color("accent").to_html(false)
	for type in ["Label", "Button", "OptionButton", "MenuButton", "CheckButton", "CheckBox", "LineEdit", "TextEdit", "CodeEdit", "Tree", "ItemList", "PopupMenu", "TabBar", "TabContainer", "SpinBox", "GraphNode", "Window", "TooltipLabel", "RichTextLabel"]:
		for name in ["font_color", "font_hover_color", "font_pressed_color", "font_hover_pressed_color", "font_focus_color", "font_selected_color", "font_unselected_color", "font_outline_color", "default_color"]:
			theme.set_color(name, type, color("text") if name != "font_outline_color" else Color.TRANSPARENT)
		theme.set_color("font_disabled_color", type, color("faint"))
		theme.set_color("font_placeholder_color", type, color("faint"))
	# Pages and panels lie on the background with a line around them.
	for type in ["Panel", "PanelContainer", "Tree", "TabContainer"]:
		theme.set_stylebox("panel", type, box("surface", "border"))
	# Lists to choose from are wells, like the boxes that are typed in.
	theme.set_stylebox("panel", "ItemList", box("well", "border", 6))
	theme.set_stylebox("focus", "ItemList", StyleBoxEmpty.new())
	# What floats over the page: its own lighter fill, a strong line and a shadow.
	theme.set_stylebox("panel", "PopupMenu", floating(6))
	theme.set_stylebox("panel", "PopupPanel", floating(8))
	theme.set_stylebox("panel", "TooltipPanel", floating(7, 5))
	theme.set_font_size("font_size", "TooltipLabel", 14)
	# A dialog: a page of its own under a title bar in the floating fill.
	for type in ["AcceptDialog", "ConfirmationDialog", "Window"]:
		theme.set_stylebox("panel", type, box("surface", "", 12, 0))
	var window_frame := box("popup", "edge", 10, 6)
	window_frame.expand_margin_top = 30
	window_frame.shadow_color = shade()
	window_frame.shadow_size = 26
	window_frame.shadow_offset = Vector2(0, 8)
	theme.set_stylebox("embedded_border", "Window", window_frame)
	var window_behind := window_frame.duplicate() as StyleBoxFlat
	window_behind.border_color = color("border")
	window_behind.shadow_size = 12
	theme.set_stylebox("embedded_unfocused_border", "Window", window_behind)
	theme.set_color("title_color", "Window", color("text"))
	theme.set_font("title_font", "Window", font("Barlow-SemiBold.ttf"))
	var close_mark := mark('<path d="M4 4L12 12M12 4L4 12" stroke="#%s" stroke-width="2" stroke-linecap="round"/>' % text)
	for state in ["close", "close_pressed"]:
		theme.set_icon(state, "Window", close_mark)
	# Buttons: a fill of their own and a line, so they are told from the page they lie on.
	for type in ["Button", "OptionButton", "MenuButton"]:
		for name in ["icon_normal_color", "icon_hover_color", "icon_pressed_color", "icon_hover_pressed_color", "icon_focus_color"]:
			theme.set_color(name, type, color("text"))
		theme.set_color("icon_disabled_color", type, color("faint"))
		theme.set_stylebox("normal", type, box("raised", "border", 8, 5))
		theme.set_stylebox("hover", type, box("hover", "accent", 8, 5))
		theme.set_stylebox("pressed", type, box("selected", "accent", 8, 5))
		theme.set_stylebox("hover_pressed", type, box("selected", "accent", 8, 5))
		var off := box("surface", "border", 8, 5)
		off.border_color = Color(color("border"), 0.55)
		off.bg_color = Color(color("raised"), 0.35)
		theme.set_stylebox("disabled", type, off)
		var focus := box("raised", "accent", 8, 5)
		focus.set_border_width_all(2)
		focus.draw_center = false
		theme.set_stylebox("focus", type, focus)
	theme.set_icon("arrow", "OptionButton", mark('<path d="M4 6.5L8 10.5L12 6.5" fill="none" stroke="#%s" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round"/>' % text))
	theme.set_constant("arrow_margin", "OptionButton", 8)
	# Boxes that are typed in: the lightest (or darkest) fill there is, a line, and the accent while typing.
	for type in ["LineEdit", "TextEdit", "CodeEdit"]:
		theme.set_stylebox("normal", type, box("well", "border", 8, 5))
		theme.set_stylebox("read_only", type, box("surface", "border", 8, 5))
		var focus := box("well", "accent", 8, 5)
		focus.set_border_width_all(2)
		focus.draw_center = false
		theme.set_stylebox("focus", type, focus)
		theme.set_color("caret_color", type, color("accent"))
		theme.set_color("selection_color", type, Color(color("accent"), 0.38))
		theme.set_color("font_readonly_color", type, color("muted"))
		theme.set_color("font_uneditable_color", type, color("muted"))
		theme.set_color("background_color", type, Color.TRANSPARENT)
		theme.set_color("clear_button_color", type, color("muted"))
		theme.set_color("clear_button_color_pressed", type, color("accent"))
	var up := mark('<path d="M4.5 10L8 6.5L11.5 10" fill="none" stroke="#%s" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round"/>' % text)
	var down := mark('<path d="M4.5 6.5L8 10L11.5 6.5" fill="none" stroke="#%s" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round"/>' % text)
	var up_off := mark('<path d="M4.5 10L8 6.5L11.5 10" fill="none" stroke="#%s" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round"/>' % faint)
	var down_off := mark('<path d="M4.5 6.5L8 10L11.5 6.5" fill="none" stroke="#%s" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round"/>' % faint)
	theme.set_icon("updown", "SpinBox", mark('<path d="M4.5 6.5L8 3L11.5 6.5M4.5 9.5L8 13L11.5 9.5" fill="none" stroke="#%s" stroke-width="1.6" stroke-linecap="round" stroke-linejoin="round"/>' % text))
	for state in ["up", "up_hover", "up_pressed"]: theme.set_icon(state, "SpinBox", up)
	for state in ["down", "down_hover", "down_pressed"]: theme.set_icon(state, "SpinBox", down)
	theme.set_icon("up_disabled", "SpinBox", up_off)
	theme.set_icon("down_disabled", "SpinBox", down_off)
	for type in ["TabBar", "TabContainer"]:
		var chosen_tab := box("surface", "", 10, 5)
		chosen_tab.border_color = color("accent")
		chosen_tab.border_width_bottom = 3
		theme.set_stylebox("tab_selected", type, chosen_tab)
		theme.set_stylebox("tab_unselected", type, box("raised", "border", 10, 5))
		theme.set_stylebox("tab_hovered", type, box("hover", "accent", 10, 5))
		theme.set_stylebox("tab_disabled", type, box("surface", "", 10, 5))
		theme.set_color("font_unselected_color", type, color("muted"))
	for type in ["Tree", "ItemList"]:
		theme.set_stylebox("selected", type, box("selected", "", 4))
		theme.set_stylebox("selected_focus", type, box("selected", "accent", 4))
		theme.set_stylebox("hovered", type, box("hover", "", 4))
		theme.set_stylebox("hovered_selected", type, box("selected", "accent", 4))
		theme.set_stylebox("hovered_selected_focus", type, box("selected", "accent", 4))
		theme.set_stylebox("cursor", type, StyleBoxEmpty.new())
		theme.set_stylebox("cursor_unfocused", type, StyleBoxEmpty.new())
		theme.set_color("guide_color", type, Color(color("border"), 0.7))
		theme.set_color("font_hovered_color", type, color("text"))
		theme.set_constant("v_separation", type, 7)
	var branch := '<path d="%s" fill="none" stroke="#%s" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round"/>'
	theme.set_icon("arrow", "Tree", mark(branch % ["M4 6.5L8 10.5L12 6.5", muted]))
	theme.set_icon("arrow_collapsed", "Tree", mark(branch % ["M6.5 4L10.5 8L6.5 12", muted]))
	theme.set_icon("arrow_collapsed_mirrored", "Tree", mark(branch % ["M9.5 4L5.5 8L9.5 12", muted]))
	# Menus and dropdowns: room around each entry, a clear bar under the pointer, marks in the theme's colours.
	theme.set_stylebox("hover", "PopupMenu", box("selected", "", 4, 4))
	var rule := StyleBoxLine.new()
	rule.color = color("border")
	rule.thickness = 1
	rule.grow_begin = -4
	rule.grow_end = -4
	for name in ["separator", "labeled_separator_left", "labeled_separator_right"]:
		theme.set_stylebox(name, "PopupMenu", rule)
	theme.set_color("font_accelerator_color", "PopupMenu", color("muted"))
	theme.set_color("font_separator_color", "PopupMenu", color("muted"))
	theme.set_constant("v_separation", "PopupMenu", 8)
	theme.set_constant("h_separation", "PopupMenu", 8)
	theme.set_constant("item_start_padding", "PopupMenu", 8)
	theme.set_constant("item_end_padding", "PopupMenu", 12)
	var ring := '<circle cx="8" cy="8" r="6" fill="none" stroke="#%s" stroke-width="1.6"/>'
	var square := '<rect x="2" y="2" width="12" height="12" rx="3" fill="none" stroke="#%s" stroke-width="1.6"/>'
	var tick := '<path d="M4.8 8.3L7.2 10.7L11.4 5.6" fill="none" stroke="#%s" stroke-width="1.9" stroke-linecap="round" stroke-linejoin="round"/>'
	theme.set_icon("radio_unchecked", "PopupMenu", mark(ring % muted))
	theme.set_icon("radio_checked", "PopupMenu", mark(ring % accent + '<circle cx="8" cy="8" r="3.2" fill="#%s"/>' % accent))
	theme.set_icon("radio_unchecked_disabled", "PopupMenu", mark(ring % faint))
	theme.set_icon("radio_checked_disabled", "PopupMenu", mark(ring % faint + '<circle cx="8" cy="8" r="3.2" fill="#%s"/>' % faint))
	theme.set_icon("unchecked", "PopupMenu", mark(square % muted))
	theme.set_icon("checked", "PopupMenu", mark(square % accent + tick % accent))
	theme.set_icon("unchecked_disabled", "PopupMenu", mark(square % faint))
	theme.set_icon("checked_disabled", "PopupMenu", mark(square % faint + tick % faint))
	theme.set_icon("submenu", "PopupMenu", mark(branch % ["M6.5 4L10.5 8L6.5 12", text]))
	theme.set_icon("submenu_mirrored", "PopupMenu", mark(branch % ["M9.5 4L5.5 8L9.5 12", text]))
	theme.set_icon("unchecked", "CheckBox", mark(square % muted))
	theme.set_icon("checked", "CheckBox", mark(square % accent + tick % accent))
	theme.set_icon("unchecked_disabled", "CheckBox", mark(square % faint))
	theme.set_icon("checked_disabled", "CheckBox", mark(square % faint + tick % faint))
	theme.set_icon("radio_unchecked", "CheckBox", mark(ring % muted))
	theme.set_icon("radio_checked", "CheckBox", mark(ring % accent + '<circle cx="8" cy="8" r="3.2" fill="#%s"/>' % accent))
	var switch_off := '<rect x="1" y="3" width="26" height="14" rx="7" fill="#%s" stroke="#%s" stroke-width="1.4"/><circle cx="8" cy="10" r="4.4" fill="#%s"/>'
	var switch_on := '<rect x="1" y="3" width="26" height="14" rx="7" fill="#%s"/><circle cx="20" cy="10" r="4.6" fill="#%s"/>'
	var switch_shape := func(body: String) -> ImageTexture:
		var image := Image.new()
		image.load_svg_from_string('<svg xmlns="http://www.w3.org/2000/svg" width="28" height="20">%s</svg>' % body)
		return ImageTexture.create_from_image(image)
	theme.set_icon("unchecked", "CheckButton", switch_shape.call(switch_off % [color("well").to_html(false), color("edge").to_html(false), muted]))
	theme.set_icon("checked", "CheckButton", switch_shape.call(switch_on % [accent, color("on_accent").to_html(false)]))
	theme.set_icon("unchecked_disabled", "CheckButton", switch_shape.call(switch_off % [color("surface").to_html(false), color("border").to_html(false), faint]))
	theme.set_icon("checked_disabled", "CheckButton", switch_shape.call(switch_on % [faint, color("surface").to_html(false)]))
	for entry: Array in [["CheckBox", "checkbox"], ["CheckButton", "button"]]:
		theme.set_color(str(entry[1]) + "_checked_color", str(entry[0]), Color.WHITE)
		theme.set_color(str(entry[1]) + "_unchecked_color", str(entry[0]), Color.WHITE)
	for type in ["CheckBox", "CheckButton"]:
		for state in ["normal", "pressed", "disabled", "hover_pressed"]:
			theme.set_stylebox(state, type, StyleBoxEmpty.new())
		var over := box("hover", "", 4, 4)
		over.draw_center = true
		theme.set_stylebox("hover", type, over)
		for state in ["normal", "pressed", "disabled", "hover_pressed"]:
			var pad := StyleBoxEmpty.new()
			pad.set_content_margin_all(4)
			theme.set_stylebox(state, type, pad)
	theme.set_stylebox("panel", "GraphEdit", box("bg", "", 0))
	theme.set_stylebox("menu_panel", "GraphEdit", box("popup", "edge", 4))
	theme.set_color("grid_minor", "GraphEdit", Color(color("border"), 0.3))
	theme.set_color("grid_major", "GraphEdit", Color(color("border"), 0.6))
	theme.set_color("connection_rim_color", "GraphEdit", color("bg"))
	theme.set_color("selection_fill", "GraphEdit", Color(color("accent"), 0.12))
	theme.set_color("selection_stroke", "GraphEdit", Color(color("accent"), 0.8))
	# The small overview of the board: a floating sheet with the cards as quiet marks.
	var overview := box("popup", "edge", 0, 4)
	overview.bg_color = Color(color("popup"), 0.92)
	theme.set_stylebox("panel", "GraphEditMinimap", overview)
	var overview_card := box("muted", "", 0, 2)
	overview_card.bg_color = Color(color("muted"), 0.65)
	theme.set_stylebox("node", "GraphEditMinimap", overview_card)
	var overview_view := box("accent", "accent", 0, 2)
	overview_view.bg_color = Color(color("accent"), 0.14)
	theme.set_stylebox("camera", "GraphEditMinimap", overview_view)
	theme.set_color("resizer_color", "GraphEditMinimap", color("muted"))
	theme.set_stylebox("panel", "GraphNode", box("surface", "border", 12))
	# A chosen node and the blocks it stands for in the side editor (BlockSelected) wear the same outline.
	var node_chosen := box("surface", "accent", 12)
	node_chosen.set_border_width_all(2)
	theme.set_stylebox("panel_selected", "GraphNode", node_chosen)
	var bar := box("raised", "border", 10)
	bar.border_width_bottom = 0
	theme.set_stylebox("titlebar", "GraphNode", bar)
	var bar_chosen := box("selected", "accent", 10)
	bar_chosen.set_border_width_all(2)
	theme.set_stylebox("titlebar_selected", "GraphNode", bar_chosen)
	theme.set_font("title_font", "GraphNode", font("Barlow-SemiBold.ttf"))
	theme.set_color("title_color", "GraphNode", color("text"))
	theme.set_type_variation("StoryBubble", "TextEdit")
	# The one button that finishes what a dialog or page is for: filled with the accent.
	theme.set_type_variation("PrimaryButton", "Button")
	theme.set_stylebox("normal", "PrimaryButton", box("accent", "accent", 8, 5))
	var primary_over := box("accent", "text", 8, 5)
	primary_over.bg_color = color("accent").lightened(0.14) if not light else color("accent").darkened(0.14)
	theme.set_stylebox("hover", "PrimaryButton", primary_over)
	var primary_down := box("accent", "text", 8, 5)
	primary_down.bg_color = color("accent").darkened(0.12) if not light else color("accent").darkened(0.25)
	theme.set_stylebox("pressed", "PrimaryButton", primary_down)
	for name in ["font_color", "font_hover_color", "font_pressed_color", "font_hover_pressed_color", "font_focus_color"]:
		theme.set_color(name, "PrimaryButton", color("on_accent"))
	theme.set_font("font", "PrimaryButton", font("Barlow-SemiBold.ttf"))
	theme.set_type_variation("ChoiceCard", "Button")
	theme.set_stylebox("normal", "ChoiceCard", box("raised", "border", 14, 7))
	theme.set_stylebox("hover", "ChoiceCard", box("hover", "accent", 14, 7))
	theme.set_stylebox("pressed", "ChoiceCard", box("selected", "accent", 14, 7))
	theme.set_type_variation("StepButton", "Button")
	var step := box("raised", "border", 9, 5)
	step.border_width_bottom = 2
	theme.set_stylebox("normal", "StepButton", step)
	var step_over := box("hover", "accent", 9, 5)
	step_over.border_width_bottom = 2
	theme.set_stylebox("hover", "StepButton", step_over)
	var selected_step := box("surface", "border", 9, 5)
	selected_step.border_color = color("accent")
	selected_step.border_width_bottom = 3
	theme.set_stylebox("pressed", "StepButton", selected_step)
	theme.set_stylebox("hover_pressed", "StepButton", selected_step)
	theme.set_color("font_color", "StepButton", color("muted"))
	theme.set_stylebox("normal", "StoryBubble", box("well", "border", 10, 9))
	theme.set_stylebox("read_only", "StoryBubble", box("raised", "", 10, 9))
	theme.set_font("font", "StoryBubble", font("Literata.ttf"))
	theme.set_type_variation("MutedLabel", "Label")
	theme.set_color("font_color", "MutedLabel", color("muted"))
	theme.set_type_variation("AccentLabel", "Label")
	theme.set_color("font_color", "AccentLabel", color("accent"))
	theme.set_type_variation("ErrorLabel", "Label")
	theme.set_color("font_color", "ErrorLabel", color("bad"))
	for type in ["HScrollBar", "VScrollBar"]:
		var track := box("border", "", 3, 4)
		track.bg_color = Color(color("border"), 0.28)
		theme.set_stylebox("scroll", type, track)
		theme.set_stylebox("scroll_focus", type, track)
		for state in ["grabber", "grabber_highlight", "grabber_pressed"]:
			theme.set_stylebox(state, type, box("edge" if state == "grabber" else "accent", "", 4, 4))
	theme.set_stylebox("slider", "HSlider", box("border", "", 2))
	theme.set_stylebox("grabber_area", "HSlider", box("accent", "", 2))
	theme.set_stylebox("grabber_area_highlight", "HSlider", box("accent", "", 2))
	for type in ["HSeparator", "VSeparator"]:
		var line := StyleBoxLine.new()
		line.color = color("border")
		line.thickness = 1
		line.vertical = type == "VSeparator"
		theme.set_stylebox("separator", type, line)
	for type in ["HSplitContainer", "VSplitContainer"]:
		theme.set_constant("separation", type, 10)
	for type in ["VBoxContainer", "HBoxContainer"]:
		theme.set_constant("separation", type, 8)
	# Story blocks: quiet cards, chips for the parts an author can change.
	theme.set_type_variation("Block", "PanelContainer")
	theme.set_stylebox("panel", "Block", box("surface", "border", 6, 6))
	theme.set_type_variation("BlockSelected", "PanelContainer")
	var chosen := box("surface", "accent", 6, 6)
	chosen.set_border_width_all(2)
	theme.set_stylebox("panel", "BlockSelected", chosen)
	theme.set_type_variation("BlockProblem", "PanelContainer")
	var problem := box("surface", "bad", 6, 6)
	problem.border_width_left = 4
	theme.set_stylebox("panel", "BlockProblem", problem)
	theme.set_type_variation("Toast", "PanelContainer")
	theme.set_stylebox("panel", "Toast", box("popup", "accent", 8, 6))
	theme.set_type_variation("Card", "PanelContainer")
	theme.set_stylebox("panel", "Card", box("raised", "border", 12, 8))
	theme.set_type_variation("Chip", "Button")
	for state in ["normal", "hover", "pressed", "focus", "disabled"]:
		var chip := box("raised" if state in ["normal", "disabled"] else "hover", "accent" if state in ["hover", "pressed", "focus"] else "edge", 3, 10)
		chip.content_margin_left = 8
		chip.content_margin_right = 8
		if state == "focus": chip.draw_center = false
		if state == "disabled": chip.border_color = color("border")
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
