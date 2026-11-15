class_name CombatMath
extends RefCounted
## Pure damage formulas, shared by real resolution, UI previews and AI scoring.
##
## Damage pipeline:
##   raw = roll * attacker.damage_dealt * defender.damage_taken
##   shields absorb first, scaled by damage_type.vs_shields
##   overflow hits hull, scaled by damage_type.vs_hull, minus armor (min 1)


## Rolls an "amount" field: either a number or [min, max].
static func roll_amount(amount: Variant, rng: RandomNumberGenerator) -> float:
	if amount is Array:
		return float(rng.randi_range(int(amount[0]), int(amount[1])))
	return float(amount)


static func average_amount(amount: Variant) -> float:
	if amount is Array:
		return (float(amount[0]) + float(amount[1])) / 2.0
	return float(amount)


## Splits raw damage into shield and hull damage.
## Returns {"shield_damage": int, "hull_damage": int}.
static func resolve(raw: float, shields: int, armor: int, damage_type: Dictionary,
		bypass_shields: bool = false, ignore_armor: bool = false) -> Dictionary:
	var vs_shields: float = damage_type.get("vs_shields", 1.0)
	var vs_hull: float = damage_type.get("vs_hull", 1.0)
	var remaining := maxf(raw, 0.0)
	var shield_damage := 0

	if not bypass_shields and shields > 0 and vs_shields > 0.0:
		var raw_to_deplete := shields / vs_shields
		if remaining < raw_to_deplete:
			shield_damage = mini(shields, roundi(remaining * vs_shields))
			remaining = 0.0
		else:
			shield_damage = shields
			remaining -= raw_to_deplete

	var hull_damage := 0
	if remaining >= 0.5:
		var h := remaining * vs_hull
		if not ignore_armor and not damage_type.get("ignores_armor", false):
			h -= armor
		hull_damage = maxi(1, roundi(h))
	return {"shield_damage": shield_damage, "hull_damage": hull_damage}
