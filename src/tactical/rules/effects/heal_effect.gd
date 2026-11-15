class_name HealEffect
extends BattleEffect
## {"type": "heal", "stat": "hull" | "shields", "amount": 20 | [min, max]}


func apply(engine: BattleEngine, _source: BattleUnit, target: BattleUnit, params: Dictionary) -> void:
	var amount := roundi(CombatMath.roll_amount(params.get("amount", 0), engine.state.rng))
	engine.heal(target, params.get("stat", "hull"), amount)


func preview(_engine: BattleEngine, _source: BattleUnit, target: BattleUnit, params: Dictionary, p: Dictionary) -> void:
	var stat: String = params.get("stat", "hull")
	var missing := target.max_shields() - target.shields if stat == "shields" else target.max_hull() - target.hull
	p["heal"] += mini(missing, roundi(CombatMath.average_amount(params.get("amount", 0))))
