class_name Wording
extends RefCounted

const NAMES := {"scene": "story", "menu": "conversation", "choice": "response", "flag": "something to remember", "number": "counter", "states": "stages / moods", "location": "place", "zone": "area", "image": "picture", "resolve": "finish this event", "outcome": "result", "infect": "mutate toward"}
const SYMBOLS := {"character": "◉", "item": "▣", "location": "⌖", "scene": "☏", "menu": "☏", "event": "ϟ", "quest": "⚑", "values": "#", "image": "▧", "creature": "♞", "form": "♞"}

const PLURALS := {"character": "Characters", "item": "Items", "location": "Places", "scene": "Stories", "menu": "Conversations", "text": "Text snippets", "event": "Events", "quest": "Quests", "values": "Saved values", "image": "Pictures", "creature": "Creatures", "form": "Body forms", "zone": "Areas", "region": "Regions", "door": "Doors", "condition": "Conditions", "feat": "Feats", "ending": "Endings", "scenario": "Starting points", "pack": "Pack", "hook": "Hooks", "shop": "Shops", "meter": "Meters", "tag": "Tags", "filter": "Content filters", "level": "Content levels"}
const ORDER := ["character", "creature", "form", "item", "location", "zone", "region", "door", "scene", "menu", "event", "quest", "ending", "scenario", "shop", "values", "condition", "feat", "image"]

static func name(kind: String) -> String:
	return NAMES.get(kind, kind.replace("_", " "))

static func plural(kind: String) -> String:
	return PLURALS.get(kind, name(kind).capitalize() + ("" if name(kind).ends_with("s") else "s"))

## Where a kind stands in lists: people, things and places first, rules last.
static func order(kind: String) -> int:
	return ORDER.find(kind) if kind in ORDER else 50 + (0 if not kind.ends_with("_rules") else 10)

static func title(row: Dictionary) -> String:
	var definition: FscParser.Definition = row.def
	for key: String in ["name", "title"]:
		if definition.fields.has(key) and not str(definition.fields[key].value).is_empty(): return definition.fields[key].value
	return readable(definition.id)

## "wren.about_woods" reads "Wren · About woods".
static func readable(id: String) -> String:
	var parts: Array[String] = []
	for part: String in id.split("."):
		var words := part.replace("_", " ").strip_edges()
		parts.append(words.left(1).to_upper() + words.substr(1))
	return " · ".join(parts)

static func icon(kind: String) -> String:
	return EditorTheme.icon(kind)

static func prose(text: String) -> String:
	var result := text
	for matched: RegExMatch in RegEx.create_from_string("\\[([^\\[\\]]+)\\]").search_all(text):
		result = result.replace(matched.get_string(), "‹" + matched.get_string(1).replace("_", " ").replace(".", " · ") + "›")
	return result

const ORDERS := {"at random": "at random", "purely at random": "at random, repeats allowed", "cycling": "in turn", "stopping": "in turn, then the last", "sticky": "the same every time", "sticky random": "the same every time", "in random order": "shuffled", "as decreasingly likely outcomes": "earlier ones more often"}
const PRONOUNS := ["he", "him", "his", "hers", "He", "Him", "His", "Hers"]

## What a piece of text markup means, in a few words: "[name of adam]" is "Adam's name".
static func markup_words(tag: String, workspace: PackWorkspace = null) -> String:
	if tag.begins_with("if "): return "if " + _lower(BlockCatalog.condition_sentence(tag.substr(3), workspace)) + ":"
	if tag.begins_with("else if "): return "otherwise, if " + _lower(BlockCatalog.condition_sentence(tag.substr(8), workspace)) + ":"
	if tag == "else": return "otherwise:"
	if tag == "end if": return "·"
	if tag == "one of": return "one of:"
	if tag == "or": return "or"
	if ORDERS.has(tag): return "(" + str(ORDERS[tag]) + ")"
	if " of " in tag:
		var what := tag.get_slice(" of ", 0)
		var whom := BlockCatalog.value_label(tag.get_slice(" of ", 1), workspace) if "." in tag.get_slice(" of ", 1) else BlockCatalog.content_label("who", tag.get_slice(" of ", 1), workspace)
		if what == "name": return whom + "'s name"
		if what in PRONOUNS: return what + " (" + whom + ")"
		return whom + "'s " + what.replace("_", " ")
	if RegEx.create_from_string("^[a-z0-9_]+\\.[a-z0-9_.]+$").search(tag) != null: return BlockCatalog.value_label(tag, workspace)
	return tag.replace("_", " ")

static func _lower(text: String) -> String:
	return text.left(1).to_lower() + text.substr(1)

## Story text on one plain line: markup as short words in angle marks.
static func words(text: String, workspace: PackWorkspace = null) -> String:
	var out := ""
	var last := 0
	for matched: RegExMatch in RegEx.create_from_string("\\[([^\\[\\]]+)\\]").search_all(text):
		out += text.substr(last, matched.get_start() - last) + "‹" + markup_words(matched.get_string(1), workspace) + "›"
		last = matched.get_end()
	return out + text.substr(last)

## Story text for a RichTextLabel: markup as short coloured words, *emphasis* shown as such.
static func marked(text: String, workspace: PackWorkspace = null) -> String:
	var colour := EditorTheme.color("accent").to_html(false)
	var out := ""
	var last := 0
	for matched: RegExMatch in RegEx.create_from_string("\\[([^\\[\\]]+)\\]").search_all(text):
		out += _styled(text.substr(last, matched.get_start() - last))
		out += "[color=#%s]‹%s›[/color]" % [colour, markup_words(matched.get_string(1), workspace).replace("[", "[lb]")]
		last = matched.get_end()
	return out + _styled(text.substr(last))

static func _styled(text: String) -> String:
	var safe := text.replace("[", "[lb]")
	safe = RegEx.create_from_string("\\*\\*(.+?)\\*\\*").sub(safe, "[b]$1[/b]", true)
	return RegEx.create_from_string("\\*(.+?)\\*").sub(safe, "[i]$1[/i]", true)
