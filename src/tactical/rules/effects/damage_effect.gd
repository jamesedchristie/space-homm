class_name DamageEffect
extends BattleEffect
## {"type": "damage", "amount": 10 | [min, max], "damage_type": "kinetic",
##  "bypass_shields": false, "ignore_armor": false}


func apply(engine: BattleEngine, source: BattleUnit, target: BattleUnit, params: Dictionary) -> void:
	var raw := CombatMath.roll_amount(params.get("amount", 0), engine.state.rng)
	engine.deal_damage(source, target, _scale(raw, source, target, engine), params)


func preview(engine: BattleEngine, source: BattleUnit, target: BattleUnit, params: Dictionary, p: Dictionary) -> void:
	var raw := _scale(CombatMath.average_amount(params.get("amount", 0)), source, target, engine)
	var dtype: Dictionary = engine.data.damage_types.get(params.get("damage_type", ""), {})
	var shields_left: int = p["shields"]
	var result := CombatMath.resolve(raw, shields_left, target.stat_i("armor"), dtype,
			params.get("bypass_shields", false), params.get("ignore_armor", false))
	p["shield_damage"] += result["shield_damage"]
	p["hull_damage"] += result["hull_damage"]
	p["shields"] = shields_left - int(result["shield_damage"])


func _scale(raw: float, source: BattleUnit, target: BattleUnit, engine: BattleEngine) -> float:
	var dealt := source.get_stat("damage_dealt") if source != null else 1.0
	# Cover: terrain like crates reduces damage to whoever stands in it.
	var cover: float = engine.state.grid.terrain_def(target.cell).get("damage_taken", 1.0)
	return raw * dealt * target.get_stat("damage_taken") * cover
