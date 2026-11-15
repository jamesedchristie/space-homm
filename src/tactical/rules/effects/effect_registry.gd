class_name EffectRegistry
extends RefCounted
## Maps effect "type" strings used in JSON to the code that runs them.

static var _effects: Dictionary = {}


static func get_effect(type: String) -> BattleEffect:
	_ensure_registered()
	return _effects.get(type)


static func register(type: String, effect: BattleEffect) -> void:
	_ensure_registered()
	_effects[type] = effect


static func known_types() -> Array:
	_ensure_registered()
	return _effects.keys()


## Content check: every effect type referenced in data has an implementation.
static func validate_content(data: DataRegistry) -> PackedStringArray:
	var problems := PackedStringArray()
	for id: String in data.abilities:
		for effect: Dictionary in data.abilities[id].get("effects", []):
			if get_effect(effect.get("type", "")) == null:
				problems.append("ability '%s': unknown effect type '%s'" % [id, effect.get("type", "")])
	for id: String in data.statuses:
		for effect: Dictionary in data.statuses[id].get("on_turn_start", []):
			if get_effect(effect.get("type", "")) == null:
				problems.append("status '%s': unknown effect type '%s'" % [id, effect.get("type", "")])
	return problems


static func _ensure_registered() -> void:
	if not _effects.is_empty():
		return
	_effects["damage"] = DamageEffect.new()
	_effects["heal"] = HealEffect.new()
	_effects["apply_status"] = ApplyStatusEffect.new()
