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
