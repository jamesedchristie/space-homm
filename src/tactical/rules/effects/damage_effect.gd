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
	# Ship class counters (RoleRules): shown in the attack preview ("x1.5 vs capital ships").
	p["role_mul"] = RoleRules.unit_multiplier(engine.data, source, target)


func _scale(raw: float, source: BattleUnit, target: BattleUnit, engine: BattleEngine) -> float:
	var dealt := source.get_stat("damage_dealt") if source != null else 1.0
	# Standing in terrain like crates reduces damage from every direction.
	var cover: float = engine.state.grid.terrain_def(target.cell).get("damage_taken", 1.0)
	# Directional cover / flanking (see CoverRules); area attacks ignore it, and so
	# does damage over time (no ability in progress, e.g. a status ticking) and
	# melee ("melee": true abilities hit adjacent targets, cover or not).
	if source != null and not engine.current_ability.is_empty() and int(engine.current_ability.get("radius", 0)) == 0 \
			and not engine.current_ability.get("melee", false):
		var from: Vector2i = source.cell if engine.preview_from_cell == null else engine.preview_from_cell
		cover *= CoverRules.evaluate(engine.state, from, target.cell)["multiplier"]
	# Ship class counters (strike > capital > escort > strike), x1.0 for units without a class.
	var role := RoleRules.unit_multiplier(engine.data, source, target)
	return raw * dealt * target.get_stat("damage_taken") * cover * role * engine.damage_scale
