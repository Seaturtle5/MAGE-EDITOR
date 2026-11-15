class_name AuthoringCatalog
extends RefCounted
## Author-facing guidance over the shared schema and effect compiler.

const HELP := {
	"name": ["Name", "The name players see.", "Basics"],
	"description": ["Description", "What players see when examining this content.", "Basics"],
	"image": ["Picture", "Choose artwork from the loaded packs.", "Basics"],
	"source": ["Source attribution", "Keep the original author and source reference.", "Advanced"],
	"tags": ["Tags", "Labels used by content filters and game rules.", "Story rules"],
	"values": ["Saved values", "Remember flags, numbers and story progress belonging to this content.", "Story rules"],
	"requires": ["Requirements", "Conditions that must pass before this event is eligible.", "Story rules"],
	"found by": ["When & where", "Choose how and where an event is encountered.", "World & discovery"],
	"lives at": ["Home", "The place where this character appears.", "World & discovery"],
	"found in": ["Encounter zones", "Zones in which this creature can be encountered.", "World & discovery"],
	"zone": ["Encounter zone", "The pool of encounters used at this place.", "World & discovery"],
	"region": ["Map region", "The larger area this place or quest belongs to.", "World & discovery"],
	"exits": ["Paths to other places", "Directions and destinations connected to this place.", "World & discovery"],
	"items": ["Items on the ground", "Items players can find at this place.", "World & discovery"],
	"map": ["Map position", "The position of this place on its region map.", "World & discovery"],
	"start": ["Starting place", "Where the player begins this scenario.", "World & discovery"],
	"weight": ["Carry weight", "Weight in whole pounds; affects the player's carrying load.", "Basics"],
	"category": ["Item category", "Groups this item in the inventory.", "Basics"],
	"aliases": ["Other names", "Alternative names for this item.", "Basics"],
	"plural": ["Plural name", "Whether the item's name is already plural.", "Basics"],
	"icon": ["Inventory icon", "The inventory symbol used when there is no picture.", "Basics"],
	"consumed": ["Used up after use", "Remove one carried item when used. Default: yes. No extra take-item reaction is needed.", "Use & reactions"],
	"infectious": ["Food mutation", "A form this food or drink can mutate the player toward after its use story. Food-infection protections apply.", "Use & reactions"],
	"purified": ["Purified version", "The item produced when this item is purified.", "Use & reactions"],
	"use action": ["Built-in activity", "Use this item to rest, wait, explore or scavenge. Choose either an activity or a use story.", "Use & reactions"],
	"in combat": ["Usable in combat", "Allow this item to be used during a fight. Default: no.", "Use & reactions"],
	"keep": ["Keep when discarding junk", "Protect this item when the player discards junk.", "Use & reactions"],
	"trades for": ["Trade value", "The item this item trades for.", "Use & reactions"],
	"rest": ["Rest behavior", "How this place or carried item supports resting.", "World & discovery"],
	"carried rest text": ["Rest text when carried", "Text shown for resting with this item in the bag.", "World & discovery"],
	"ground rest text": ["Rest text on the ground", "Text shown for resting near this item.", "World & discovery"],
	"purify refusal": ["Purification refusal", "Explain why this item cannot be purified.", "Use & reactions"],
	"equipment": ["Wearable equipment", "Clothing slots, protection and bonuses. Nested rules may need a specialized editor.", "Body & combat"],
	"weapon": ["Weapon", "Damage, combat bonuses and attack wording. Nested rules may need a specialized editor.", "Body & combat"],
	"body": ["Body", "Body-part settings for this character.", "Body & combat"],
	"form": ["Mutation form", "The body form associated with this creature.", "Body & combat"],
	"hp": ["Health", "The creature's starting health points.", "Body & combat"],
	"damage": ["Attack damage", "The creature's base damage in combat.", "Body & combat"],
	"stats": ["Attributes", "Strength, dexterity and other attributes.", "Body & combat"],
	"level": ["Level", "The level used by encounter or combat rules.", "Body & combat"],
	"repeat": ["How often", "Run once, until resolved, or whenever eligible.", "Story rules"],
	"chance": ["Arrival chance", "The chance an eligible arrival event runs.", "Story rules"],
	"cooldown": ["Arrival cooldown", "Turns between eligible arrival checks.", "Story rules"],
	"priority": ["Arrival priority", "Lower values are checked first.", "Story rules"],
	"outcomes": ["Event outcomes", "Named results the event's story can record.", "Story rules"],
	"stages": ["Stages", "Named quest stages or thresholds for this content.", "Story rules"],
	"done at": ["Completed stages", "Quest stages that count as finished.", "Story rules"]
}
const INTERACTIONS := {
	"use": ["Use story", "When the player eats, drinks or uses this item. Restore health, satisfy hunger, quench thirst or add mutation and choices here."],
	"play": ["Event story", "What happens when this event starts."],
	"talk": ["Conversation", "What happens when the player talks to this character."],
	"enter": ["On entering", "Runs when the player enters this place."],
	"presence": ["While here", "Text shown while the character or place is present."],
	"actions": ["Player actions", "Choices the player can make here."],
	"observe": ["Things to examine", "Scenery the player can choose to examine."],
	"on wear": ["When worn", "Runs when the player puts on this item."],
	"on remove": ["When removed", "Runs when the player takes this item off."],
	"worn each turn": ["While worn", "Runs each turn while this item is worn."],
	"each turn": ["Every turn", "Runs on each game turn."],
	"encounter": ["Encounter opening", "Runs when the player meets this creature."],
	"victory": ["Creature wins", "Runs after this creature defeats the player."],
	"defeated": ["Creature defeated", "Runs after the player defeats this creature."],
	"scent": ["Scent", "What the player smells when examining this content."]
}

static func property(type: String, key: String, kind: String) -> Dictionary:
	var info: Array = HELP.get(key, [key.capitalize(), "", "Advanced"])
	if kind in ["script", "menu"] and key != "description":
		info = INTERACTIONS.get(key, [key.capitalize(), "Write the story for this interaction."])
		info = [info[0], info[1], "Interactions"]
	if type == "creature" and key == "infectious":
		info = ["Infectious in combat", "Whether this creature's attacks can cause infection.", "Body & combat"]
	if type == "form" and key in BodySystem.PARTS + ["breasts", "balls"]:
		info = [key.capitalize(), "Body-part appearance, change text and targets for this mutation form.", "Body & combat"]
	if type == "pack" and key == "requires":
		info = ["Required packs", "Other packs that must be loaded before this pack.", "Story rules"]
	var help: String = info[1]
	if help.is_empty():
		help = {"list": "Choose several entries, separated by commas.", "fields": "Structured entries; complex nested rules are preserved.", "meta": "Attribution and metadata for this content."}.get(kind, "An advanced setting for this content. Check existing content for examples.")
	return {"key": key, "title": info[0], "help": help, "category": info[2], "kind": kind,
		"search": (key + " " + str(info[0]) + " " + help + " " + str(info[2])).to_lower()}

static func basic_reactions() -> Array[Dictionary]:
	return [
		{"label": "Restore health", "value": "heal 1", "template": "heal {amount}", "help": "Restore health points, up to the player's maximum health.", "keywords": "healing hp", "category": "Health & needs"},
		{"label": "Deal damage", "value": "hurt 1", "template": "hurt {amount}", "help": "Remove health points from the player.", "keywords": "hurt hp", "category": "Health & needs"},
		{"label": "Satisfy hunger", "value": "eat 1", "template": "eat {amount}", "help": "Reduce hunger by this amount. This does not consume an item by itself.", "keywords": "food berry", "category": "Health & needs"},
		{"label": "Quench thirst", "value": "drink 1", "template": "drink {amount}", "help": "Reduce thirst by this amount.", "keywords": "water drink", "category": "Health & needs"}
	]

static func effect_label(text: String) -> String:
	var effect := Effect.compile(text)
	var amount := amount_label(effect.get("amount", effect.get("times", {})))
	match str(effect.get("op", "")):
		"survival": return str({"heal": "Restore health", "hurt": "Deal damage", "eat": "Satisfy hunger", "drink": "Quench thirst"}.get(effect.kind, effect.kind)) + " · " + amount
		"infect":
			var target: String = "the picked creature" if effect.get("form", "") == "@picked" else str(effect.get("form", "")).capitalize()
			if effect.has("part"): target = "the player's " + str(effect.part) + " form"
			return "Attempt mutation toward " + target + " · " + amount + " attempt(s)" + (" · keeping sex" if effect.get("keep_sex", false) else "")
		"transform": return "Transform " + str(effect.get("part", "all parts")) + " into " + str(effect.form).capitalize()
		"give", "take": return ("Give " if effect.op == "give" else "Take ") + str(effect.item if not str(effect.get("item", "")).is_empty() else effect.get("item_path", "item")) + " · " + amount
		"change": return ("Increase " if int(effect.sign) > 0 else "Decrease ") + str(effect.path).trim_prefix("player.").capitalize() + " · " + amount
		"resolve": return "Finish event · " + str(effect.event if not str(effect.event).is_empty() else "current event")
		"outcome": return "Record outcome · " + str(effect.outcome) + (" for " + str(effect.event) if not str(effect.get("event", "")).is_empty() else "")
		"activate", "deactivate": return ("Enable event · " if effect.op == "activate" else "Disable event · ") + str(effect.event)
		"sex": return "Record " + str(effect.act).replace("_", " ") + " · " + str(effect.taker) + " receives from " + str(effect.giver)
		"trait": return ("Add trait · " if effect.add else "Remove trait · ") + str(effect.trait) + " for " + str(effect.who)
		"feat": return ("Grant feat · " if effect.add else "Remove feat · ") + str(effect.feat)
		"impregnate": return "Pregnancy · " + str(effect.kind) + (" by " + str(effect.father) if not str(effect.father).is_empty() else "")
		"move": return "Move " + str(effect.who) + " to " + str(effect.place)
		"go": return "Take the player to " + str(effect.place)
		"discover", "forget": return ("Discover place · " if effect.op == "discover" else "Forget place · ") + str(effect.place)
		"condition": return "Apply condition · " + str(effect.condition) + " for %d turns" % int(effect.turns)
		"spend": return "Pass %d turns" % int(effect.turns)
		"cancel_use": return "Cancel item use"
	return text

static func amount_label(amount: Dictionary) -> String:
	if amount.has("min"): return "%s–%s" % [amount.min, amount.max]
	if amount.has("percent"): return str(amount.percent) + "%"
	var value: Dictionary = amount.get("value", {})
	var label := str(value.v) if value.get("op", "") == "num" else "calculated amount"
	if amount.has("limit"): label += (" up to " if amount.limit == "up" else " down to ") + str(amount.limit_value)
	return label
