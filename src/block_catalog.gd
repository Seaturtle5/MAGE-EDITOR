class_name BlockCatalog
extends RefCounted
## Author-facing sentences over engine compilers. Never a second grammar.

const ENTRIES := [
	["heal", "Health", "Restore health by {amount}", "heal {amount}", "amount", "10", "heal health hp cure"],
	["hurt", "Health", "Deal {amount} damage", "hurt {amount}", "amount", "5", "damage hurt health hp"],
	["eat", "Health", "Restore hunger by {amount}", "eat {amount}", "amount", "10", "food eat hunger"],
	["drink", "Health", "Restore thirst by {amount}", "drink {amount}", "amount", "10", "drink thirst water"],
	["give", "Items", "Give {item}, amount {amount}", "give {item} {amount}", "item,amount", "canteen,1", "give item inventory"],
	["take", "Items", "Take {item}, amount {amount}", "take {item} {amount}", "item,amount", "canteen,1", "take remove item inventory"],
	["go", "Places", "Move the player to {location}", "go to {location}", "location", "home", "teleport go move place"],
	["discover", "Places", "Discover {location}", "discover {location}", "location", "home", "discover travel place"],
	["move", "People", "Move {character} to {location}", "move {character} to {location}", "character,location", "friend,home", "person move place"],
	["resolve", "Events", "Finish {event}", "resolve {event}", "event", "discovery", "finish resolve event"],
	["outcome", "Events", "Record result {result} for {event}", "outcome {result} of {event}", "result,event", "taken,discovery", "record outcome result event"],
	["activate", "Events", "Turn on {event}", "activate {event}", "event", "discovery", "activate enable event"],
	["deactivate", "Events", "Turn off {event}", "deactivate {event}", "event", "discovery", "deactivate disable event"],
	["quest", "Quests", "Set {quest} to {stage}", "quest {quest} = {stage}", "quest,stage", "journey,complete", "quest stage progress"],
	["condition", "Health", "Apply {condition} for {turns} turns", "condition {condition} for {turns} turns", "condition,turns", "warmth,2", "condition bonus duration"],
	["infect", "Body", "Mutate toward {form}", "infect {form}", "form", "human", "mutate infect body form"],
	["transform", "Body", "Transform into {form}", "transform into {form}", "form", "human", "transform body form"],
	["remember", "Counters", "Remember {value}", "{value} = true", "value", "friend.met", "remember flag yes"],
	["set", "Counters", "Set {value} to {amount}", "{value} = {amount}", "value,amount", "friend.trust,1", "set counter value number"],
	["raise", "Counters", "Raise {value} by {amount}", "{value} + {amount}", "value,amount", "friend.trust,1", "raise add counter trust romance love"],
	["lower", "Counters", "Lower {value} by {amount}", "{value} - {amount}", "value,amount", "friend.trust,1", "lower subtract counter"],
	["spend", "Time", "Pass {turns} turns", "spend {turns} turns", "turns", "2", "time pass turns"],
	["record_time", "Time", "Remember the time in {value}", "{value} = now", "value", "friend.last_visit", "time now record cooldown"],
	["continue_moving", "Events", "Continue the move", "continue moving", "", "", "leaving continue moving"],
	["cancel_use", "Items", "Keep the item after using it", "cancel use", "", "", "keep consumed cancel use"],
	["no_fight", "Fights", "End this encounter without a fight", "no fight", "", "", "cancel fight encounter"],
	["unlock", "Places", "Unlock {door}", "unlock {door}", "door", "gate", "unlock door key"],
	["lock", "Places", "Lock {door}", "lock {door}", "door", "gate", "lock door key"],
	["feat", "People", "Grant {feat}", "feat + {feat}", "feat", "brave", "feat trait grant"],
	["companion", "People", "Invite {character} to the party", "companion + {character}", "character", "friend", "companion join party"],
]

static func entries(query: String = "") -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for raw: Array in ENTRIES:
		var entry := {"id": raw[0], "category": raw[1], "sentence": raw[2], "pattern": raw[3], "slots": str(raw[4]).split(",", false), "defaults": str(raw[5]).split(",", false), "synonyms": raw[6]}
		if query.is_empty() or query.to_lower() in (str(entry.sentence) + " " + str(entry.synonyms)).to_lower(): result.append(entry)
	return result

static func render(entry: Dictionary, slots: Dictionary) -> String:
	var line: String = entry.pattern
	for index in entry.slots.size():
		line = line.replace("{" + entry.slots[index] + "}", str(slots.get(entry.slots[index], entry.defaults[index])))
	return line

static func read_line(line: String) -> Dictionary:
	if Effect.compile(line).has("error"): return {}
	for entry: Dictionary in entries():
		var pattern: String = entry.pattern
		for slot: String in entry.slots: pattern = pattern.replace("{" + slot + "}", "(.+?)")
		pattern = pattern.replace(" + ", " \\+ ")
		var matched := RegEx.create_from_string("^" + pattern + "$").search(line)
		if matched == null: continue
		var slots: Dictionary = {}
		for index in entry.slots.size(): slots[entry.slots[index]] = matched.get_string(index + 1)
		if render(entry, slots) == line: return {"entry": entry, "slots": slots, "line": line, "compiled": Effect.compile(line)}
	return {}

static func sentence(line: String) -> String:
	var read := read_line(line)
	if read.is_empty(): return "Kept action · " + AuthoringCatalog.effect_label(line)
	var result: String = read.entry.sentence
	for slot: String in read.slots: result = result.replace("{" + slot + "}", str(read.slots[slot]).replace("_", " "))
	return result
