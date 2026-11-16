class_name BlockCatalog
extends RefCounted
## Author-facing sentences over the engine's compilers. Never a second grammar:
## an entry only reads a line when the engine's first matching rule is the
## entry's rule and rendering the read slots gives the same line back.
##
## Row: [id, category, sentence, pattern, search words, context, help].
## The rule is the id up to its first dot. In a pattern, {name:kind=default}
## is a slot (kind defaults to the name) and [ ... ] is an optional part, left
## out when its slots are empty. Slots named _x keep a spelling (turn / turns)
## and are not shown. Kinds: a content type, who, word.<list>, int, amount,
## expr, exprs, text, quoted, value[.flag|number|text|time|states|list],
## script, phrase.<list>, ids.<type>, stage, result, state, option,
## a|b|c (choice), @table (choice with labels) and ?words (a switch).

const CATEGORY_ICONS := {
	"Memory": "🔢", "Items": "🎒", "Places": "📍", "People": "👤", "Companions": "🐾", "Health": "❤",
	"Events": "⚡", "Quests": "🏁", "Body": "🧬", "Creatures": "♞", "Fights": "⚔", "Intimacy": "♥",
	"Pregnancy": "🍼", "Time": "⏳", "Lists": "☰", "Ask": "✎", "Endings": "✦", "Chance": "🎲", "World": "🧭",
}

const CONTEXT_REASONS := {
	"fight": "Fight actions only work in a creature's fight stories or inside a fight.",
	"item_use": "This only works in an item's use story.",
	"leaving": "This only works in an event found when leaving a place.",
	"encounter": "This only works in a creature's encounter story.",
	"event": "This only works in an event's story.",
	"companion": "This only works in a companion's summon or dismiss story.",
	"hidden": "Another spelling of an action offered above.",
}

const CHOICES := {
	"is": [["is", "is"], ["is not", "is not"]],
	"are": [["are", "are"], ["are not", "are not"]],
	"has": [["has", "has"], ["does not have", "does not have"]],
	"cmp": [[">=", "at least"], [">", "more than"], ["=", "exactly"], ["!=", "anything but"], ["<", "less than"], ["<=", "at most"]],
	"set_how": [["=", "becomes"], ["+", "goes up by"], ["-", "goes down by"]],
	"part": [["head", "head"], ["face", "face"], ["torso", "torso"], ["body", "body"], ["back", "back"], ["arms", "arms"], ["legs", "legs"], ["ass", "rear"], ["tail", "tail"], ["cock", "cock"], ["cunt", "cunt"], ["skin", "skin"]],
	"has_part": [["head", "head"], ["torso", "torso"], ["back", "back"], ["arms", "arms"], ["legs", "legs"], ["ass", "rear"], ["tail", "tail"], ["cock", "cock"], ["cunt", "cunt"], ["balls", "balls"], ["breasts", "breasts"]],
	"infect_part": [["head", "head"], ["torso", "torso"], ["body", "body"], ["skin", "skin"], ["tail", "tail"], ["cock", "cock"], ["cunt", "cunt"], ["face", "face"]],
	"wear_slot": [["head", "head"], ["hair", "hair"], ["eyes", "eyes"], ["face", "face"], ["neck", "neck"], ["back", "back"], ["body", "body"], ["chest", "chest"], ["breast", "breast"], ["stomach", "stomach"], ["arms", "arms"], ["hands", "hands"], ["legs", "legs"], ["waist", "waist"], ["crotch", "crotch"], ["feet", "feet"]],
	"attribute": [["strength", "strength"], ["dexterity", "dexterity"], ["stamina", "stamina"], ["perception", "perception"], ["intelligence", "intelligence"], ["charisma", "charisma"]],
	"creature_number": [["damage", "damage"], ["level", "level"], ["hp", "health"], ["libido", "libido"], ["hit bonus", "hit bonus"], ["dodge bonus", "dodge bonus"], ["scale", "size"], ["strength", "strength"], ["dexterity", "dexterity"], ["stamina", "stamina"], ["perception", "perception"], ["intelligence", "intelligence"], ["charisma", "charisma"]],
	"creature_field": [["found in", "is found in"], ["infectious", "is infectious"], ["gender", "has the gender"], ["variant", "uses the variant"], ["loot", "drops"], ["special", "has the special rule"], ["image", "uses the picture"], ["title", "is titled"], ["strike with", "strikes with"], ["name known", "has its name known"], ["unique", "is unique"]],
	"form_number": [["cock count", "number of cocks"], ["cock length", "cock length"], ["ball size", "ball size"], ["cunt count", "number of cunts"], ["cunt depth", "cunt depth"], ["cunt tightness", "cunt tightness"], ["breast size", "breast size"], ["male breast size", "male breast size"], ["nipple count", "number of nipples"]],
	"fight_result": [["won", "won"], ["lost", "lost"], ["fled", "fled from"], ["won by fighting", "won by fighting"], ["won by seduction", "won by seduction"], ["won by vore", "won by vore"], ["won by unbirth", "won by unbirth"], ["lost by injury", "lost by injury"], ["lost by lust", "lost by lust"], ["lost by submitting", "lost by submitting"]],
	"quest_rel": [["reached", "has reached"], ["is", "is exactly at"], ["is not", "is not at"], ["has not reached", "has not reached"], ["is before", "is before"]],
	"level_rel": [["is", "is"], ["is not", "is not"], ["is at least", "is at least"], ["is at most", "is at most"]],
	"wears": [["wears", "wears"], ["does not wear", "does not wear"], ["wields", "wields"], ["does not wield", "does not wield"]],
	"pregnancy": [["impregnation chance", "A chance of pregnancy"], ["impregnate", "A certain pregnancy"]],
	"end_state": [["dies", "dies"], ["is imprisoned", "is imprisoned"], ["leaves", "leaves the city"]],
	"captivity": [["end", "End"], ["escape", "Escape from"]],
	"vore": [["vore", "Swallow"], ["unbirth", "Unbirth"]],
	"armor": [["ignoring armor", "ignoring armor"], ["through half armor", "through half the armor"], ["without shield", "ignoring the shield"]],
	"player_move": [["attack enemy", "attacks the enemy"], ["try to flee", "tries to flee"]],
	"sort": [["random", "a shuffled"], ["reverse", "reverse"]],
}

## Suggestions for open words. The engine accepts any word here.
const WORDS := {
	"direction": ["north", "northeast", "east", "southeast", "south", "southwest", "west", "northwest", "up", "down", "inside", "outside"],
	"act": ["vaginal", "anal", "oral_cock", "oral_pussy", "vaginal_toy", "anal_toy", "oral_toy", "stroking", "facial", "frottage", "grinding", "spanking", "other"],
	"stat": ["humanity", "libido", "morale", "score", "xp", "hunger", "thirst", "hp", "strength", "dexterity", "stamina", "charisma", "intelligence", "perception"],
	"time_slot": ["day", "night", "early morning", "morning", "midday", "afternoon", "evening", "early night", "night time", "late night"],
	"adjective": ["male", "female", "herm", "neuter", "naked", "pure", "companion", "tamed", "here", "resolved", "active", "pregnant", "captive", "fighting", "in an event", "male preferred", "female preferred", "herm preferred", "barecrotch", "barechest", "barefoot", "virgin", "anal virgin", "oral virgin", "explorable", "locked", "unlocked", "dead", "imprisoned", "gone"],
	"cause": ["dead", "imprisoned", "left"],
}

const ACTIONS := [
	# Memory: flags, counters, texts, times, stages.
	["set.yes", "Memory", "Remember: {value}", "{value:value.flag} = yes", "remember flag yes true set mark met", "", "Remember something as yes. Conditions can check it later."],
	["set.no", "Memory", "No longer remember: {value}", "{value:value.flag} = no", "forget flag no false clear unset", "", "Set something remembered back to no."],
	["set.true", "Memory", "Remember: {value}", "{value:value.flag} = true", "", "hidden"],
	["set.false", "Memory", "No longer remember: {value}", "{value:value.flag} = false", "", "hidden"],
	["set.now", "Time", "Remember the time now in {value}", "{value:value.time} = now", "time now record cooldown last visit", "", "Record the current moment. \"Turns have passed since\" conditions read it."],
	["set.ago", "Time", "Set the time {value} to {turns} turns ago", "{value:value.time} = {turns:expr=8} {_s:turns|turn} ago", "time ago earlier past"],
	["set.ahead", "Time", "Set the time {value} to {turns} turns from now", "{value:value.time} = in {turns:expr=8} {_s:turns|turn}", "time later future"],
	["child_random", "Pregnancy", "Draw the child's {what} at random", "child.{what:gender|personality} = random", "child random gender personality"],
	["set.range", "Memory", "Set {value} to a random number from {low} to {high}", "{value:value.number} = {low:expr=1} to {high:expr=6}", "random roll dice range counter", "", "Pick a whole number in the range, both ends included."],
	["set.text", "Memory", "Set {value} to the text \"{text}\"", "{value:value.text} = \"{text:quoted}\"", "text name word write"],
	["set.number", "Memory", "Set {value} to {number}", "{value:value.number} = {number:int=1}", "set counter number value exact"],
	["set.state", "Memory", "Set {value} to {state}", "{value:value.states} = {state:state}", "stage mood state step set"],
	["set.calc", "Memory", "Set {value} to {to}", "{value:value} = {to:expr}", "calculate formula copy value", "", "Set a value from another value or a calculation."],
	["change.add", "Memory", "{value} goes up by {amount}", "{value:value.number} + {amount:amount=1}", "raise add increase counter trust romance love relationship plus more"],
	["change.sub", "Memory", "{value} goes down by {amount}", "{value:value.number} - {amount:amount=1}", "lower subtract decrease counter minus less"],
	["stat.add", "Health", "The player's {stat} goes up by {amount}", "{stat:word.stat} + {amount:amount=1}", "humanity libido morale score xp experience raise"],
	["stat.sub", "Health", "The player's {stat} goes down by {amount}", "{stat:word.stat} - {amount:amount=1}", "humanity libido morale score lower"],
	["shift_time", "Time", "Move the time {value} {direction} by {turns} turns", "{value:value.time} {direction:earlier|later} by {turns:expr=2} {_s:turns|turn}", "time shift earlier later"],
	["spend", "Time", "{turns} turns pass", "spend {turns:int=1} {_s:turn|turns}", "time pass wait turns hours spend"],
	["schedule", "Time", "Play {scene} after {actions} more player actions", "schedule {scene:script} after {actions:int=3} {_s:actions|action}", "later delay schedule timer"],
	["extend_game", "Time", "Extend the game by {turns} turns", "extend game by {turns:expr=24} {_s:turns|turn}", "extend deadline game length"],
	# Lists.
	["list_add", "Lists", "Add {items} to the list {list}[ ({absent})]", "add {items:exprs=1} to {list:value.list}[ {absent:?if absent}]", "list add append collect"],
	["list_remove_entry", "Lists", "Remove entry number {index} from the list {list}", "remove entry {index:expr=1} from {list:value.list}", "list remove entry position"],
	["list_remove", "Lists", "Remove {items} from the list {list}", "remove {items:exprs=1} from {list:value.list}", "list remove delete"],
	["list_clear", "Lists", "Empty the list {list}", "clear {list:value.list}", "list clear empty reset"],
	["list_sort", "Lists", "Put the list {list} in[ {order}] order", "sort {list:value.list}[ in {order:@sort} order]", "list sort shuffle random reverse"],
	# Items.
	["give_one", "Items", "Give one of these at random: {items}", "give one of {items:ids.item}", "give random item one of loot"],
	["give", "Items", "Give {item}[ × {amount}]", "give {item:item}[ {amount:amount}]", "give item add inventory reward loot find", "", "Put an item in the player's inventory."],
	["give.held", "Items", "Give the item named in {value}[ × {amount}]", "give {value:value}[ {amount:amount}]", "give chosen item value"],
	["take_all", "Items", "Take away every {item}", "take all {item:item}", "take all remove every item"],
	["take", "Items", "Take away {item}[ × {amount}]", "take {item:item}[ {amount:amount}]", "take remove item lose pay cost inventory"],
	["take.held", "Items", "Take away the item named in {value}[ × {amount}]", "take {value:value}[ {amount:amount}]", "take chosen item value"],
	["use_item", "Items", "Use {item} right away", "use {item:item}", "use eat drink item now"],
	["remove_slot", "Items", "Take off whatever is worn on the {slot}", "remove whatever is worn on {slot:@wear_slot}", "undress take off clothing slot"],
	["gear.wear", "Items", "Put on {item}", "wear {item:item}", "wear put on clothing equip"],
	["gear.remove", "Items", "Take off {item}", "remove {item:item}", "remove take off clothing unequip"],
	["gear.wield", "Items", "Wield {item}", "wield {item:item}", "wield weapon equip"],
	["unwield", "Items", "Put away the wielded weapon", "unwield", "unwield weapon put away"],
	["put", "Items", "Leave {item}[ × {count}] lying in {place}", "put {item:item}[ {count:int}] in {place:location}", "put drop leave item place ground"],
	["remove_from", "Items", "Remove {item} lying in {place}", "remove {item:item} from {place:location}", "remove item from place ground"],
	["item_strain", "Items", "{item} now mutates toward {form}", "item {item:item} infects as {form:form}", "item infection strain food mutation"],
	["cancel_use", "Items", "Keep the item (it is not used up)", "cancel use", "keep item not consumed cancel use", "item_use", "The item stays in the inventory after this use."],
	# Places and the map.
	["go", "Places", "Move the player to {place}", "go to {place:location}", "teleport go move travel place send", "", "The player arrives at the place when this story ends."],
	["discover", "Places", "Discover {place} (it appears on the map)", "discover {place:location}", "discover reveal map travel unlock place"],
	["forget", "Places", "Forget {place} (it leaves the map)", "forget {place:location}", "forget hide map place"],
	["lock.unlock", "Places", "Unlock {door}", "unlock {door:door}", "unlock door open key"],
	["lock.lock", "Places", "Lock {door}", "lock {door:door}", "lock door close key"],
	["change_exit", "Places", "The {direction} exit of {place} now leads to {to}", "change {direction:word.direction} exit of {place:location} to {to:location}", "exit path change map connect block"],
	["continue_moving", "Places", "The player walks on (continue the move)", "continue moving", "leaving continue moving walk on", "leaving", "In an event found when leaving a place: let the player leave after all."],
	["move", "People", "Move {who} to {place}", "move {who:who} to {place:location}", "move person character place send"],
	["lives_at", "People", "{who} now lives at {place}", "{who:character} lives at {place:location}", "home lives move house character"],
	# People.
	["trait.add", "People", "{who} gains the trait {trait}", "{who:who} trait + {trait:word.trait}", "trait add personality mark character"],
	["trait.remove", "People", "{who} loses the trait {trait}", "{who:who} trait - {trait:word.trait}", "trait remove character"],
	["feat.add", "People", "The player gains the feat {feat}", "feat + {feat:feat}", "feat grant gain perk ability"],
	["feat.remove", "People", "The player loses the feat {feat}", "feat - {feat:feat}", "feat remove lose perk"],
	["choose_feat", "People", "The player chooses a feat from {group}", "choose feat {group:word.feat_group}", "feat choose pick perk"],
	["character_image", "People", "{who}'s picture becomes {image}", "character {who:character} image {image:image}", "portrait picture image change character"],
	["character_pronouns", "People", "Refer to {who} as {pronouns}", "character {who:character} pronouns {pronouns:he|she|they|it|by body|default}", "pronouns he she they character"],
	["check_level", "People", "Check for a level up now", "check level", "level up experience"],
	["set_level", "World", "Set the content level {level} to {option}", "level {level:level} = {option:option}", "content level setting preference"],
	# Companions.
	["companion.add", "Companions", "{who} joins the party", "companion + {who:character}", "companion join party follow recruit"],
	["companion.remove", "Companions", "{who} leaves the party", "companion - {who:character}", "companion leave party dismiss"],
	["tame.tame", "Companions", "{who} can now be summoned", "tame {who:character}", "tame pet summon companion"],
	["tame.untame", "Companions", "{who} can no longer be summoned", "untame {who:character}", "untame release pet"],
	["summon.summon", "Companions", "Summon {who}", "summon {who:character}", "summon call companion pet"],
	["summon.dismiss", "Companions", "Dismiss {who}", "dismiss {who:character}", "dismiss send away companion"],
	["cancel_companion", "Companions", "Cancel this {what}", "cancel {what:summon|dismiss}", "cancel summon dismiss", "companion"],
	["companion_level", "Companions", "{who} gains a level", "level up {who:character}", "companion level up"],
	["send_children", "Pregnancy", "Send the children at {from} to {to}", "send children from {from:word.home} to {to:word.home}", "children send move home"],
	# Health and needs.
	["survival.heal", "Health", "Restore health by {amount}", "heal {amount:amount=10}", "heal health hp cure restore", "", "Restore health, up to the maximum."],
	["survival.hurt", "Health", "Deal {amount} damage to the player", "hurt {amount:amount=5}", "damage hurt harm injure health hp"],
	["survival.eat", "Health", "Restore hunger by {amount}", "eat {amount:amount=10}", "food eat hunger feed"],
	["survival.drink", "Health", "Restore thirst by {amount}", "drink {amount:amount=10}", "drink thirst water"],
	["condition", "Health", "Apply {condition} for {turns} {unit}", "condition {condition:condition} for {turns:int=3} {unit:turns|turn|hours|hour}", "condition bonus buff effect temporary duration"],
	["meter.add", "Health", "The meter {meter} goes up by {amount}", "meter {meter:meter} + {amount:amount=1}", "meter raise gauge"],
	["meter.sub", "Health", "The meter {meter} goes down by {amount}", "meter {meter:meter} - {amount:amount=1}", "meter lower gauge"],
	["resize", "Body", "Resize the player to size {size}", "resize to {size:1|2|3|4|5}", "size scale grow shrink resize"],
	# Events and quests.
	["resolve", "Events", "Finish this event", "resolve", "finish resolve done event complete end", "event", "The event will not be found again."],
	["resolve.other", "Events", "Finish the event {event}", "resolve {event:event}", "finish resolve another event"],
	["unresolve", "Events", "Let the event {event} happen again", "unresolve {event:event}", "unresolve again repeat event reopen"],
	["outcome_of", "Events", "Record the result {result} for {event}", "outcome {result:result} of {event:event}", "outcome result record event"],
	["outcome", "Events", "Record the result {result}", "outcome {result:result}", "outcome result record this event", "event", "Later stories can check this event's result."],
	["activate.on", "Events", "Turn on the event {event}", "activate {event:event}", "activate enable turn on event"],
	["activate.off", "Events", "Turn off the event {event}", "deactivate {event:event}", "deactivate disable turn off event"],
	["quest", "Quests", "Set the quest {quest} to {stage}", "quest {quest:quest} = {stage:stage}", "quest stage progress advance journal"],
	# Body.
	["infect_part", "Body", "Spread the form of the player's {part}", "infect with player {part:@infect_part}", "infect spread own form part"],
	["infect_picked", "Body", "Mutate toward the picked creature[ ({keep})]", "infect picked creature[ {keep:?keeping sex}]", "infect mutate picked random creature"],
	["pick", "Body", "Pick a random creature[ tagged {tag}][ {where}][, favoring {favoring}]", "pick random creature[ tagged {tag:word.tag}][ {where:nearby or outside|nearby|anywhere}][ favoring {favoring:ids.creature}]", "pick random creature choose"],
	["pick.zone", "Body", "Pick a random creature[ tagged {tag}] found in {zone}[, favoring {favoring}]", "pick random creature[ tagged {tag:word.tag}] in {zone:zone}[ favoring {favoring:ids.creature}]", "pick random creature area zone"],
	["infect", "Body", "Mutate toward {form}[, {times} times][ ({keep})]", "infect {form:form}[ {times:amount} {_s:times|time}][ {keep:?keeping sex}]", "mutate infect transform body form change", "", "One step of gradual change toward a form."],
	["transform", "Body", "Transform completely into {form}", "transform into {form:form}", "transform full body form become"],
	["transform_part", "Body", "The player's {part} becomes {form}", "transform {part:@part} into {form:form}", "transform part head tail skin body"],
	["transform_part.held", "Body", "The player's {part} becomes the form named in {value}", "transform {part:@part} into {value:value}", "transform part saved form"],
	["reset_human", "Body", "Reset the body to human", "reset to human", "human reset cure restore body"],
	["grow", "Body", "The player's {part} grows by {amount}", "grow {part:cock|balls|breasts} by {amount:amount=1}", "grow bigger size"],
	["sex_change", "Body", "Run the {what} change[ toward {form}][ ({keep})]", "{what:sex|breast} change[ toward {form:form}][ {keep:?keeping cock}]", "sex change gender breast"],
	["form_number", "Body", "The form {form}'s {what} becomes {to}", "form {form:form} {what:@form_number} = {to:expr}", "form size count length"],
	["form_sex", "Body", "The form {form} now gives the sex {sex}", "form {form:form} sex {sex:male|female|herm|neuter|unchanged}", "form sex gender"],
	# Creatures.
	["creature_number", "Creatures", "{creature}'s {field} {how} {amount}", "creature {creature:creature} {field:@creature_number} {how:@set_how} {amount:amount=1}", "creature stronger weaker damage health level"],
	["creature_change", "Creatures", "{creature} now {field} {value}", "creature {creature:creature} {field:@creature_field} {value:plain}", "creature zone gender loot variant change"],
	# Intimacy and pregnancy.
	["sex", "Intimacy", "Record sex: {taker} receives {act} from {giver}", "sex {taker:who} receives {act:word.act} from {giver:who}", "sex intimacy virginity partner record", "", "Records the act for virginity, partners and pregnancy chances."],
	["impregnate", "Pregnancy", "{how}[ ({kind})][ by {father}][ ({eggs})]", "{how:@pregnancy}[ {kind:female|male|self}][ by {father:father}][ {eggs:?with eggs}]", "pregnancy impregnate chance father eggs"],
	["pregnancy_step", "Pregnancy", "Pregnancy step: {step}", "{step:accept pregnancy|give birth|record child}", "pregnancy birth child record"],
	["each_child", "Pregnancy", "For each child[ at {home}], play {scene}", "for each child[ at {home:word.home}] play {scene:script}", "children each play"],
	["new_child", "Pregnancy", "Start a new story child", "new child", "child new story"],
	["end_pregnancy", "Pregnancy", "End the pregnancy without a birth", "end pregnancy", "pregnancy end stop"],
	["pregnancy_faster", "Pregnancy", "Speed up the pregnancy by {turns}", "pregnancy faster by {turns:int=1}", "pregnancy faster speed"],
	["vore", "Fights", "{kind} the enemy", "{kind:@vore} enemy", "vore swallow unbirth enemy", "fight"],
	["unbirth_of", "Pregnancy", "Start an unbirth pregnancy of {creature}", "unbirth pregnancy {_s:of|with} {creature:creature}", "unbirth pregnancy creature"],
	["vore_step", "Fights", "Vore step: {step}", "{step:absorb enemy stat|infect enemy|unbirth pregnancy}", "vore absorb infect", "fight"],
	["end_heat", "Body", "End heat now", "end heat", "heat end stop"],
	["reset_heat", "Body", "Reset the heat cycle", "reset heat", "heat reset cycle"],
	["drive_heat", "Body", "Bring heat on[ ({now})]", "drive heat[ {now:?now}]", "heat start sooner"],
	["extend_heat", "Body", "Extend heat by {turns} turns", "extend heat by {turns:int=3} {_s:turns|turn}", "heat longer extend"],
	["end_captivity", "World", "{how} captivity", "{how:@captivity} captivity", "captivity escape end free prison"],
	# Fights.
	["no_fight", "Fights", "End this encounter without a fight", "no fight", "cancel fight peaceful encounter leave", "encounter", "In a creature's encounter story: no fight follows."],
	["enemy_attack", "Fights", "The enemy attacks[ with {percent}% of its damage]", "enemy attack[ {percent:int}%]", "enemy attack hit", "fight"],
	["enemy_strike", "Fights", "The enemy strikes[ at {percent}% of its damage][, {armor}]", "enemy strike[ {percent:int}%][ {armor:@armor}]", "enemy strike hit damage armor", "fight"],
	["enemy_strike.for", "Fights", "The enemy strikes for {amount} damage[, {armor}]", "enemy strike for {amount:amount=5}[ {armor:@armor}]", "enemy strike fixed damage armor", "fight"],
	["fight_result.lose", "Fights", "The player loses the fight[ by {how}]", "lose fight[ by {how:lust|injury|submitting}]", "lose fight end defeat", "fight"],
	["fight_result.win", "Fights", "The player wins the fight[ by {how}]", "win fight[ by {how:seduction|fighting}]", "win fight end victory", "fight"],
	["player_move", "Fights", "The player {move}", "{move:@player_move}", "player attack flee move", "fight"],
	["infects_as", "Fights", "This fight infects as {creature}", "this fight infects as {creature:creature}", "fight infection strain", "fight"],
	["no_infection", "Fights", "This fight does not infect", "this fight does not infect", "fight no infection safe", "fight"],
	# Endings.
	["trigger_ending", "Endings", "Mark the ending {ending} for the end of the game", "trigger ending {ending:ending}", "ending epilogue mark later"],
	["ending", "Endings", "End the game now with {ending}", "ending {ending:ending}", "ending game over finish epilogue"],
	["end_state", "Endings", "The player {state}", "player {state:@end_state}", "die death imprisoned leave game over"],
	["ending_reason", "Endings", "Give the reason for the ending: {reason}", "ending reason {reason:text}", "ending reason cause"],
	["ending_flag", "Endings", "Set the ending flag {flag}", "ending flag {flag:word.ending_flag}", "ending flag detail"],
	["exclude_endings", "Endings", "Skip the {type} endings", "exclude {type:word.ending_type} endings", "ending exclude skip"],
	# Ask the player.
	["ask_item", "Ask", "Ask the player to choose a carried item tagged {tag}, kept in {value}: {prompt}", "ask {value:value} as {_a:an item|a item|item} tagged {tag:word.tag}: {prompt:text}", "ask choose item gift"],
	["ask_number", "Ask", "Ask the player for a number[ from {low} to {high}], kept in {value}: {prompt}", "ask {value:value} as {_a:a number|number}[ from {low:expr} to {high:expr}]: {prompt:text}", "ask number type input"],
	["ask", "Ask", "Ask the player to type a text[ of up to {letters} letters], kept in {value}: {prompt}", "ask {value:value}[ up to {letters:int} letters]: {prompt:text}", "ask name type text input"],
]

const CONDITIONS := [
	["since", "Time", "{cmp} {turns} turns have passed since {value}", "since {value:value.time} {cmp:@cmp} {turns:int=3} {_s:turns|turn}", "time since passed cooldown turns ago recently", "", "A time that was never recorded counts as long ago."],
	["truthy.not", "Memory", "{value} is not remembered", "not {value:value.flag}", "not remembered flag no false never"],
	["truthy", "Memory", "{value} is remembered", "{value:value.flag}", "remembered flag yes true met done"],
	["cmp", "Memory", "{counter} is {cmp} {number}", "{counter:expr} {cmp:@cmp} {number:expr=3}", "counter number compare at least more less equal trust level health"],
	["chance", "Chance", "With a {n} in {d} chance", "chance {n:int=1} in {d:int=3}", "chance random luck odds sometimes"],
	["percent", "Chance", "With a {percent}% chance", "chance {percent:int=50}%", "chance percent random luck"],
	["chance_expr", "Chance", "With a chance of {n} in {d}", "chance {n:expr} in {d:expr}", "chance calculated odds"],
	["check", "Chance", "A {stat} check against {target} succeeds", "check {stat:@attribute} vs {target:int=12}", "check roll skill attribute test dice"],
	["check_expr", "Chance", "A roll with the bonus {bonus} against {target} succeeds", "check {bonus:expr} vs {target:expr=12}", "check roll bonus calculated"],
	["quest", "Quests", "The quest {quest} {rel} {stage}", "quest {quest:quest} {rel:@quest_rel} {stage:stage}", "quest stage progress reached journal"],
	["outcome", "Events", "The result of {event} {is} {result}", "{event:event} outcome {is:@is} {result:result}", "outcome result event happened"],
	["time", "Time", "The time of day {is} {slot}", "time {is:@is} {slot:phrase.time_slot}", "time day night morning evening"],
	["filter", "World", "The content filter {filter} {is} {state}", "filter {filter:filter} {is:@is} {state:allowed|banned|warded}", "filter content banned warded allowed"],
	["level", "World", "The content level {level} {rel} {option}", "level {level:level} {rel:@level_rel} {option:option}", "content level setting preference"],
	["mode", "World", "The game mode {mode} is on", "mode {mode:word.mode}", "mode hard difficulty"],
	["scenario", "World", "The starting scenario {is} {scenario}", "scenario {is:@is} {scenario:scenario}", "scenario start"],
	["fight_result", "Fights", "The player {result} the last fight", "{result:@fight_result}", "fight won lost fled result victory defeat"],
	["can_vore", "Fights", "The player {can} {kind}", "player {can:can|cannot} {kind:vore|unbirth}", "vore unbirth can"],
	["enemy_tagged", "Fights", "The enemy {is} tagged {tag}", "{_the:enemy|the enemy} {is:@is} tagged {tag:word.tag}", "enemy tagged kind"],
	["listed", "Lists", "{item} {is} in the list {list}", "{item:expr} {is:@is} listed in {list:value.list}", "list contains listed in"],
	["empty", "Lists", "{list} {is} empty", "{list:value} {is:@is} empty", "list empty nothing"],
	["value_tagged", "Items", "The thing named in {value} {is} tagged {tag}", "{value:value} {is:@is} tagged {tag:word.tag}", "chosen item tagged"],
	["has_condition", "Health", "The player {has} the condition {condition}", "player {has:@has} condition {condition:condition}", "condition active bonus buff"],
	["feat", "People", "{who} {has} the feat {feat}", "{who:who} {has:@has} feat {feat:feat}", "feat perk ability has"],
	["trait", "People", "{who} {has} the trait {trait}", "{who:who} {has:@has} trait {trait:word.trait}", "trait personality has"],
	["had_sex", "Intimacy", "{who} {has} sex", "{who:who} {has:has had|has not had} sex", "sex had virgin"],
	["picked", "Body", "{any} creature is picked", "{any:a|no} creature is picked", "picked creature random"],
	["ending_triggered", "Endings", "The ending {ending} {is} marked", "ending {ending:ending} {is:@is} triggered", "ending marked triggered"],
	["ending_flag", "Endings", "The ending flag {flag} {is} set", "ending flag {flag:word.ending_flag} {is:@is} set", "ending flag"],
	["endings_excluded", "Endings", "The {type} endings {are} skipped", "{type:word.ending_type} endings {are:@are} excluded", "ending excluded skipped"],
	["ended_by", "Endings", "The game {ended} by {cause}", "the game {ended:ended|did not end} by {cause:word.cause}", "ending cause death"],
	["enemy_hits", "Fights", "The enemy {hits}[ using {stat}]", "{_the:enemy|the enemy} {hits:hits|misses}[ using {stat:@attribute}]", "enemy hits misses roll", "fight"],
	["arrived", "Places", "The player {arrived} by {how}", "player {arrived:arrived|did not arrive} by {how:walking|travelling}", "arrived walking travelling fast travel"],
	["has_part", "Body", "{who} {has} a {part}", "{who:who} {has:@has} {part:@has_part}", "body part has tail cock"],
	["wears", "Items", "The player {wears} {item}", "player {wears:@wears} {item:item}", "wears wields clothing weapon equipped"],
	["has_tagged", "Items", "The player {has} an item tagged {tag}", "player {has:@has} {_a:an item|a item|any item} tagged {tag:word.tag}", "has item tagged kind carry"],
	["has_item", "Items", "{who} {has} {item}[ × {count}]", "{who:holder} {has:@has} {item:item}[ {count:int}]", "has item carries inventory owns"],
	["lives_at", "People", "{who} {lives} at {place}", "{who:character} {lives:lives|does not live} at {place:location}", "lives home"],
	["is_at", "Places", "{who} {is} at {place}", "{who:who} {is:@is} at {place:location}", "is at place where character"],
	["in_heat", "Body", "{who} {is} in heat", "{who:who} {is:@is} in heat", "heat"],
	["in", "Places", "The player {is} in {place}", "player {is:@is} in {place:location}", "player in place here location"],
	["knows", "Places", "The player {knows} {place}", "player {knows:knows|does not know} {place:location}", "knows discovered map place"],
	["visited", "Places", "The player {has} {place}", "player {has:has visited|has not visited} {place:location}", "visited been place"],
	["at_flagged", "Places", "{who} {is} at a place flagged {flag}", "{who:who} {is:@is} at a place flagged {flag:phrase.place_flag}", "place flag flagged"],
	["parts_all", "Body", "{who}'s body parts {are} all one of: {forms}", "{who:who} parts {are:@are} all {forms:ids.form}", "body all parts pure form"],
	["species_same", "Body", "{who}'s {part} {is} the same species as {other}'s {other_part}", "{who:who} {part:@part} species {is:@is} {other:who} {other_part:@part} species", "species same part"],
	["species_contains", "Body", "The species name of {who}'s {part} {contains} {text}", "{who:who} {part:@part} species {contains:contains|does not contain} {text:phrase.species}", "species name contains"],
	["part_tagged", "Body", "{who}'s {part} {is} tagged {tag}", "{who:who} {part:@part} {is:@is} tagged {tag:word.tag}", "body part tagged kind"],
	["part_is", "Body", "{who}'s {part} {is} the form {form}", "{who:who} {part:@part} {is:@is} {form:form}", "body part form species is"],
	["parity", "Memory", "{value} {is} {parity}", "{value:value.number} {is:@is} {parity:odd|even}", "odd even"],
	["at_least", "Memory", "{value} is {rel} {state}", "{value:value.states} is {rel:at least|at most} {state:state}", "stage mood at least reached"],
	["name_known", "Creatures", "The name of {creature} {is} known", "{creature:creature} name {is:@is} known", "name known creature unique"],
	["is.sex", "Body", "{who} {is} {sex}", "{who:who} {is:@is} {sex:male|female|herm|neuter}", "sex gender male female herm neuter"],
	["is.interested", "Body", "The player {is} interested in {what}", "player {is:@is} interested in {what:phrase.interest}", "interested attracted preference"],
	["is.flagged", "Places", "This place {is} flagged {flag}", "here {is:@is} flagged {flag:phrase.place_flag}", "here place flag"],
	["is.variant", "Creatures", "{who} {is} the variant {variant}", "{who:creature} {is:@is} variant {variant:word.variant}", "creature variant"],
	["is", "People", "{who} {is} {what}", "{who:who} {is:@is} {what:phrase.adjective}", "is state naked pure companion tamed resolved active"],
	["value_is", "Memory", "{value} {is} {to}", "{value:value} {is:@is} {to:expr}", "value is equal text stage mood"],
]

static var _built: Dictionary = {}
static var _rule_cache: Dictionary = {}
static var _read_cache: Dictionary = {}

## Entries of one kind ("action" or "condition"), in reading order.
static func all(kind: String = "action") -> Array[Dictionary]:
	if _built.has(kind): return _built[kind]
	var result: Array[Dictionary] = []
	for raw: Array in (ACTIONS if kind == "action" else CONDITIONS):
		var row := {"id": raw[0], "rule": str(raw[0]).get_slice(".", 0), "kind": kind, "category": raw[1], "sentence": raw[2], "pattern": raw[3],
			"words": raw[4] if raw.size() > 4 else "", "context": raw[5] if raw.size() > 5 else "", "help": raw[6] if raw.size() > 6 else "", "slots": []}
		row.regex = _compile(row)
		row.icon = CATEGORY_ICONS.get(row.category, "◇")
		result.append(row)
	_built[kind] = result
	return result

static func by_id(id: String, kind: String = "action") -> Dictionary:
	for candidate: Dictionary in all(kind):
		if candidate.id == id: return candidate
	return {}

## Entries offered in a chooser; `query` matches everyday words.
static func entries(query: String = "", kind: String = "action") -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var words := query.to_lower().split(" ", false)
	for candidate: Dictionary in all(kind):
		if candidate.context == "hidden": continue
		var haystack := (plain(candidate) + " " + str(candidate.words) + " " + str(candidate.category)).to_lower()
		var found := true
		for word: String in words:
			if word not in haystack: found = false
		if found: result.append(candidate)
	return result

static func categories(kind: String = "action") -> Array[String]:
	var result: Array[String] = []
	for candidate: Dictionary in all(kind):
		if candidate.category not in result: result.append(candidate.category)
	return result

## The sentence with slot names in place of values, for lists and search.
static func plain(candidate: Dictionary) -> String:
	return _fill(candidate, candidate.sentence, {}, func(spec: Dictionary, _value: String) -> String:
		if spec.has("options") and not str(spec.default).is_empty(): return str(spec.labels[spec.options.find(spec.default)])
		if spec.kind in ["int", "amount"] and not str(spec.default).is_empty(): return str(spec.default)
		return "[" + slot_title(spec) + "]")

static func slot_title(slot: Dictionary) -> String:
	var kind: String = slot.kind
	if kind.begins_with("value"): return {"value.flag": "something to remember", "value.number": "counter", "value.time": "time", "value.list": "list", "value.text": "text value", "value.states": "stage or mood"}.get(kind, "value")
	if kind == "script": return "story"
	if kind in ["amount", "int", "expr", "exprs", "text", "quoted", "stage", "result", "state", "option", "plain"] or kind.begins_with("word") or kind.begins_with("phrase") or kind.begins_with("ids") or slot.has("options"):
		return str(slot.name).replace("_", " ")
	return Wording.name(kind) if kind not in ["who", "holder", "father"] else "who"

static func _slot(spec: String) -> Dictionary:
	var default := ""
	var at := spec.find("=")
	# A choice may list "=" itself; only @tables do, and they never carry "=" in the spec.
	if at > 0:
		default = spec.substr(at + 1)
		spec = spec.left(at)
	var name := spec.get_slice(":", 0)
	var kind := spec.substr(name.length() + 1) if ":" in spec else name
	var slot := {"name": name, "kind": kind, "default": default, "hidden": name.begins_with("_")}
	if kind.begins_with("@"):
		slot.options = []
		slot.labels = []
		for pair: Array in CHOICES[kind.substr(1)]:
			slot.options.append(pair[0])
			slot.labels.append(pair[1])
		slot.kind = "choice"
	elif kind.begins_with("?"):
		slot.options = ["", kind.substr(1)]
		slot.labels = ["", kind.substr(1)]
		slot.kind = "switch"
	elif "|" in kind:
		slot.options = Array(kind.split("|"))
		slot.labels = slot.options.map(func(option: String) -> String: return option.replace("_", " "))
		slot.kind = "choice"
	return slot

static func _slot_regex(slot: Dictionary) -> String:
	var kind: String = slot.kind
	if kind == "switch": return _escape(slot.options[1])
	if kind == "choice":
		var options: Array = slot.options.duplicate()
		options.sort_custom(func(a: String, b: String) -> bool: return a.length() > b.length())
		return "|".join(options.map(func(option: String) -> String: return _escape(option)))
	if kind.begins_with("value"): return "[a-z0-9_]+\\.[a-z0-9_.]+"
	if kind.begins_with("phrase"): return "[a-z][a-z0-9_ ]*?"
	if kind.begins_with("ids"): return "[a-z0-9_]+(?:, ?[a-z0-9_]+)*"
	match kind:
		"int": return "-?\\d+"
		"amount", "expr", "exprs": return ".+?"
		"text": return ".+"
		"quoted": return "[^\"]*"
		"script": return "[a-z0-9_.]+"
		"father": return "random creature|\\w+"
		"plain": return "[a-z0-9_,% ]+"
		"word.stat": return "[a-z_]+"
	return "\\w+"

static func _escape(text: String) -> String:
	var result := ""
	for character: String in text:
		result += ("\\" + character) if character in "\\^$.|?*+()[]{}" else character
	return result

static func _compile(candidate: Dictionary) -> RegEx:
	var pattern: String = candidate.pattern
	var source := "^"
	var index := 0
	var group := -1
	var groups: Array = []
	while index < pattern.length():
		var character := pattern[index]
		if character == "{":
			var close := pattern.find("}", index)
			var slot := _slot(pattern.substr(index + 1, close - index - 1))
			slot.optional = group >= 0
			if slot.kind == "choice" and str(slot.default).is_empty() and (group < 0 or slot.hidden): slot.default = slot.options[0]
			candidate.slots.append(slot)
			source += "(" + _slot_regex(slot) + ")"
			index = close + 1
			continue
		if character == "[":
			group = groups.size()
			groups.append(true)
			source += "(?:"
		elif character == "]":
			group = -1
			source += ")?"
		else: source += _escape(character)
		index += 1
	return RegEx.create_from_string(source + "$")

## The line for an entry and slot values; missing slots use their defaults.
static func render(candidate: Dictionary, slots: Dictionary) -> String:
	return _fill(candidate, candidate.pattern, slots, func(_slot_spec: Dictionary, value: String) -> String: return value)

static func _fill(candidate: Dictionary, template: String, slots: Dictionary, show: Callable) -> String:
	var result := ""
	var index := 0
	var optional_start := -1
	var optional_filled := false
	while index < template.length():
		var character := template[index]
		if character == "{":
			var close := template.find("}", index)
			var name := template.substr(index + 1, close - index - 1).get_slice(":", 0).get_slice("=", 0)
			var spec := slot_spec(candidate, name)
			var inside := optional_start >= 0
			var value := str(slots.get(name, "" if inside and not spec.get("hidden", false) else spec.get("default", "")))
			if value.is_empty() and spec.get("hidden", false): value = spec.get("default", "")
			if not value.is_empty() and not spec.get("hidden", false): optional_filled = true
			result += str(show.call(spec, value))
			index = close + 1
			continue
		if character == "[":
			optional_start = result.length()
			optional_filled = false
		elif character == "]":
			if not optional_filled: result = result.left(optional_start)
			optional_start = -1
		else: result += character
		index += 1
	return result

static func slot_spec(candidate: Dictionary, name: String) -> Dictionary:
	for slot: Dictionary in candidate.slots:
		if slot.name == name: return slot
	return {}

## The engine rule that reads an action line (without `~` and `quietly`).
static func action_rule(text: String) -> String:
	if _rule_cache.has(text): return _rule_cache[text]
	var name := ""
	for rule: Array in Effect._rules:
		if rule[1].search(text) != null:
			name = rule[0]
			break
	_rule_cache[text] = name
	return name

## The engine rule that reads one condition part, given as spaced words.
static func condition_rule(text: String) -> String:
	var words := Condition._words(text)
	if words.is_empty(): return ""
	if words[0] != "since":
		for word: String in words:
			if word in Condition.COMPARATORS: return "cmp"
	for rule: Array in Condition._rules:
		if rule[1].search(text) != null: return rule[0]
	return "truthy" if words.size() == 1 and "." in words[0] else ""

static func _read(text: String, kind: String) -> Dictionary:
	var rule := action_rule(text) if kind == "action" else condition_rule(text.trim_prefix("not ")) if text.begins_with("not ") else condition_rule(text)
	if rule.is_empty(): return {}
	for candidate: Dictionary in all(kind):
		if candidate.rule != rule: continue
		var matched: RegExMatch = candidate.regex.search(text)
		if matched == null: continue
		var slots: Dictionary = {}
		for index in candidate.slots.size(): slots[candidate.slots[index].name] = matched.get_string(index + 1)
		if render(candidate, slots) == text: return {"entry": candidate, "slots": slots}
	return {}

## Reads an action line (without `~`). Empty when no entry describes it.
static func read_line(line: String) -> Dictionary:
	var key := line.strip_edges()
	if _read_cache.has(key): return _read_cache[key]
	var text := key
	var quiet := text.ends_with(" quietly")
	if quiet: text = text.left(-8).strip_edges()
	var result: Dictionary = {}
	if not Effect.compile(key).has("error"):
		result = _read(text, "action")
		if not result.is_empty():
			result.quiet = quiet
			result.line = key
	_read_cache[key] = result
	return result

static func action_line(candidate: Dictionary, slots: Dictionary, quiet: bool = false) -> String:
	return render(candidate, slots) + (" quietly" if quiet else "")

## Reads one condition part ("player has feat brave", "not adam.met").
static func read_predicate(text: String) -> Dictionary:
	var normal := " ".join(Condition._words(text))
	if normal.begins_with("not ") and condition_rule(normal.trim_prefix("not ")) != "truthy": return {}
	var result := _read(normal, "condition")
	if not result.is_empty(): result.line = normal
	return result

## A condition as a tree: {op: all|any, items} · {op: not, item} · {op: is, text}.
static func condition_tree(text: String) -> Dictionary:
	if Condition.compile(text).has("error"): return {"op": "kept", "text": text}
	var parser := _ConditionReader.new()
	parser.words = Condition._words(text)
	var tree := parser.any_of()
	return tree if parser.ok and parser.index >= parser.words.size() else {"op": "kept", "text": text}

class _ConditionReader:
	var words: PackedStringArray
	var index := 0
	var ok := true

	func any_of() -> Dictionary:
		var items: Array = [all_of()]
		while ok and index < words.size() and words[index] == "or":
			index += 1
			items.append(all_of())
		return items[0] if items.size() == 1 else {"op": "any", "items": items}

	func all_of() -> Dictionary:
		var items: Array = [negation()]
		while ok and index < words.size() and words[index] == "and":
			index += 1
			items.append(negation())
		return items[0] if items.size() == 1 else {"op": "all", "items": items}

	func negation() -> Dictionary:
		if index < words.size() and words[index] == "not":
			index += 1
			var inner := negation()
			if inner.op == "is" and BlockCatalog.condition_rule(inner.text) == "truthy": return {"op": "is", "text": "not " + str(inner.text)}
			return {"op": "not", "item": inner}
		if index < words.size() and words[index] == "(":
			var close := _matching(index)
			if close > 0 and (close + 1 >= words.size() or words[close + 1] in ["and", "or", ")"]):
				index += 1
				var inner := any_of()
				if index >= words.size() or words[index] != ")":
					ok = false
					return {"op": "is", "text": ""}
				index += 1
				return inner
		return predicate()

	func _matching(open: int) -> int:
		var depth := 0
		for at in range(open, words.size()):
			if words[at] == "(": depth += 1
			elif words[at] == ")":
				depth -= 1
				if depth == 0: return at
		return -1

	func predicate() -> Dictionary:
		var start := index
		var depth := 0
		while index < words.size():
			if words[index] == "(": depth += 1
			elif words[index] == ")":
				if depth == 0: break
				depth -= 1
			elif depth == 0 and words[index] in ["and", "or"]: break
			index += 1
		if index == start: ok = false
		return {"op": "is", "text": " ".join(words.slice(start, index))}

## The condition text for a tree, with brackets only where they are needed.
static func condition_text(tree: Dictionary) -> String:
	match str(tree.op):
		"all":
			return " and ".join(tree.items.map(func(item: Dictionary) -> String: return "(" + condition_text(item) + ")" if item.op == "any" else condition_text(item)))
		"any": return " or ".join(tree.items.map(func(item: Dictionary) -> String: return condition_text(item)))
		"not": return "not " + condition_text(tree.item) if tree.item.op == "is" else "not (" + condition_text(tree.item) + ")"
	return str(tree.text)

## Sentence pieces for display: {text} and {slot, value, label, spec}.
static func pieces(candidate: Dictionary, slots: Dictionary, workspace: PackWorkspace = null) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var marked := _fill(candidate, candidate.sentence, slots, func(spec: Dictionary, value: String) -> String:
		return "\u0001" + str(spec.name) + "\u0002" + value + "\u0003")
	for part: String in marked.split("\u0001"):
		if "\u0003" not in part:
			if not part.is_empty(): result.append({"text": part})
			continue
		var name := part.get_slice("\u0002", 0)
		var value := part.get_slice("\u0002", 1).get_slice("\u0003", 0)
		var spec := slot_spec(candidate, name)
		result.append({"slot": name, "value": value, "label": label(spec, value, workspace), "spec": spec})
		var rest := part.get_slice("\u0003", 1)
		if not rest.is_empty(): result.append({"text": rest})
	return result

static func describe(candidate: Dictionary, slots: Dictionary, workspace: PackWorkspace = null) -> String:
	var text := ""
	for piece: Dictionary in pieces(candidate, slots, workspace): text += str(piece.get("text", piece.get("label", "")))
	return text.left(1).to_upper() + text.substr(1)

## An action line (without `~`) in plain words.
static func sentence(line: String, workspace: PackWorkspace = null) -> String:
	var read := read_line(line)
	if read.is_empty(): return "Kept action · " + AuthoringCatalog.effect_label(line)
	return describe(read.entry, read.slots, workspace) + (" (without telling the player)" if read.quiet else "")

## A whole condition in plain words.
static func condition_sentence(text: String, workspace: PackWorkspace = null) -> String:
	return _tree_sentence(condition_tree(text), workspace, true)

static func _tree_sentence(tree: Dictionary, workspace: PackWorkspace, top: bool) -> String:
	match str(tree.op):
		"all", "any":
			var joined := (" and " if tree.op == "all" else " or ").join(tree.items.map(func(item: Dictionary) -> String: return _tree_sentence(item, workspace, false)))
			return joined.left(1).to_upper() + joined.substr(1) if top else "(" + joined + ")"
		"not": return "not (" + _tree_sentence(tree.item, workspace, true) + ")"
		"kept": return str(tree.text)
	var read := read_predicate(tree.text)
	if read.is_empty(): return str(tree.text)
	var text := describe(read.entry, read.slots, workspace)
	return text if top else text.left(1).to_lower() + text.substr(1)

## How a slot value reads to an author.
static func label(spec: Dictionary, value: String, workspace: PackWorkspace = null) -> String:
	if spec.is_empty(): return value
	var kind: String = spec.kind
	if value.is_empty(): return "…" if kind != "switch" else ""
	if spec.has("options"):
		var at: int = spec.options.find(value)
		return str(spec.labels[at]) if at >= 0 else value
	if kind.begins_with("value"): return value_label(value, workspace)
	if kind in ["amount", "expr", "exprs"]: return amount_label(value, workspace)
	if kind in ["int", "text", "quoted", "script", "plain"] or kind.begins_with("phrase"): return value
	if kind.begins_with("ids"):
		var names: Array[String] = []
		for id: String in value.split(","): names.append(content_label(kind.get_slice(".", 1), id.strip_edges(), workspace))
		return ", ".join(names)
	if kind.begins_with("word") or kind in ["stage", "result", "state", "option"]: return value.replace("_", " ")
	return content_label(kind, value, workspace)

static func content_label(kind: String, id: String, workspace: PackWorkspace = null) -> String:
	if id in ["player", "enemy", "here", "nothing", "anything", "default", "outside", "nowhere"]:
		return {"player": "the player", "enemy": "the enemy", "here": "this place"}.get(id, id)
	if workspace != null:
		var title := workspace.title_of(kind, id)
		if not title.is_empty(): return title
	return id.replace("_", " ").capitalize()

## "adam.trust" reads "Adam's trust"; "player.hp" reads "the player's hp".
static func value_label(path: String, workspace: PackWorkspace = null) -> String:
	var owner := path.get_slice(".", 0)
	var key := path.substr(owner.length() + 1).replace("_", " ").replace(".", " ")
	if owner == "player": return "the player's " + key
	if owner in ["event", "child", "fights", "picked", "enemy", "here", "quest"]: return ("the " if owner != "here" else "") + owner.replace("here", "this place's") + ("'s " if owner != "here" else " ") + key
	return content_label("", owner, workspace) + "'s " + key

static func amount_label(value: String, workspace: PackWorkspace = null) -> String:
	var limit := Effect._limit_re.search(value)
	if limit != null: return amount_label(limit.get_string(1), workspace) + (", up to " if limit.get_string(2) == "up to" else ", down to ") + limit.get_string(3)
	var bounds := Effect._range_re.search(value)
	if bounds != null: return bounds.get_string(1) + " to " + bounds.get_string(2) + " (random)"
	var result := value
	for matched: RegExMatch in RegEx.create_from_string("[a-z0-9_]+\\.[a-z0-9_.]+").search_all(value):
		result = result.replace(matched.get_string(), value_label(matched.get_string(), workspace))
	return result

## Slot values for a test or a preview: every slot filled.
static func sample(candidate: Dictionary) -> Dictionary:
	var slots: Dictionary = {}
	for slot: Dictionary in candidate.slots:
		var value: String = slot.default
		if value.is_empty():
			var kind: String = slot.kind
			if slot.has("options"): value = slot.options[-1]
			elif kind.begins_with("value"): value = "friend.trust"
			elif kind.begins_with("ids"): value = "first, second"
			elif kind in ["int", "amount"]: value = "2"
			elif kind == "expr": value = "player.level + 1"
			elif kind == "exprs": value = "1, 2"
			elif kind == "father": value = "wolf"
			elif kind == "text": value = "Which one?"
			elif kind == "quoted": value = "hello"
			else: value = "sample"
		slots[slot.name] = value
	return slots

## Whether an entry fits the story being edited. `context` lists what applies
## here ("fight", "item_use", "leaving", "encounter", "event", "companion").
static func applies(candidate: Dictionary, context: Array) -> bool:
	return str(candidate.context).is_empty() or candidate.context in context
