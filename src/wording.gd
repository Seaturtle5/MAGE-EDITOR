class_name Wording
extends RefCounted

const NAMES := {"scene": "story", "menu": "conversation", "choice": "response", "flag": "something to remember", "number": "counter", "states": "stages / moods", "location": "place", "zone": "area", "image": "picture", "resolve": "finish this event", "outcome": "result", "infect": "mutate toward"}
const SYMBOLS := {"character": "◉", "item": "▣", "location": "⌖", "scene": "☏", "menu": "☏", "event": "ϟ", "quest": "⚑", "values": "#", "image": "▧", "creature": "♞", "form": "♞"}

static func name(kind: String) -> String:
	return NAMES.get(kind, kind.replace("_", " "))

static func title(row: Dictionary) -> String:
	var definition: FscParser.Definition = row.def
	return definition.fields.name.value if definition.fields.has("name") else definition.id.replace("_", " ").capitalize()

static func icon(kind: String) -> String:
	return SYMBOLS.get(kind, "◇")

static func prose(text: String) -> String:
	var result := text
	for matched: RegExMatch in RegEx.create_from_string("\\[([^\\[\\]]+)\\]").search_all(text):
		result = result.replace(matched.get_string(), "‹" + matched.get_string(1).replace("_", " ").replace(".", " · ") + "›")
	return result
