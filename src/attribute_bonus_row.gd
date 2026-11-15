class_name AttributeBonusRow
extends VBoxContainer
## Named controls for the reversible attribute changes supported by conditions.

signal edited

var attribute: OptionButton
var amount: SpinBox
var original := ""
var touched := false

func configure(source: String, writable: bool) -> void:
	original = source
	var effect := Effect.compile(source) if not source.is_empty() else {}
	var value: Dictionary = effect.get("amount", {})
	var simple: bool = source.is_empty() or (effect.get("op", "") == "change" and str(effect.get("path", "")).trim_prefix("player.") in Game.ATTRIBUTES and str(effect.get("path", "")).begins_with("player.") and value.size() == 1 and value.get("value", {}).get("op", "") == "num")
	if simple and not source.is_empty():
		simple = absf(float(value.value.v)) <= 1000000 and float(value.value.v) == int(value.value.v)
	if not simple:
		add_child(AuthoringLayout.label(AuthoringCatalog.effect_label(source), 16))
		add_child(AuthoringLayout.label("Existing advanced effect · preserved unchanged", 13, true))
		return
	add_child(AuthoringLayout.label("Player attribute", 13, true))
	attribute = OptionButton.new()
	for stat: String in Game.ATTRIBUTES: attribute.add_item(stat.capitalize())
	attribute.select(Game.ATTRIBUTES.find(str(effect.path).trim_prefix("player.")) if not effect.is_empty() else 0)
	attribute.disabled = not writable
	add_child(attribute)
	add_child(AuthoringLayout.label("Change while active (negative numbers reduce it)", 13, true))
	amount = SpinBox.new()
	amount.min_value = -1000000
	amount.max_value = 1000000
	amount.value = int(effect.sign) * int(value.value.v) if not effect.is_empty() else 1
	amount.editable = writable
	add_child(amount)
	attribute.item_selected.connect(func(_index: int) -> void: touched = true; edited.emit())
	amount.value_changed.connect(func(_value: float) -> void: touched = true; edited.emit())
	var hint := AuthoringLayout.label("Stamina also changes health according to the game’s level and stamina rules.", 13, true)
	add_child(hint)
	hint.visible = Game.ATTRIBUTES[attribute.selected] == "stamina"
	attribute.item_selected.connect(func(index: int) -> void: hint.visible = Game.ATTRIBUTES[index] == "stamina")

func declaration() -> Dictionary:
	if not touched and not original.is_empty(): return {"spec": original}
	if amount == null: return {"spec": original}
	if int(amount.value) == 0: return {"error": "Choose a nonzero attribute change."}
	var result := "player.%s %s %d" % [Game.ATTRIBUTES[attribute.selected], "+" if amount.value > 0 else "-", absi(int(amount.value))]
	if Effect.compile(original).get("quiet", false): result += " quietly"
	return {"spec": result}
