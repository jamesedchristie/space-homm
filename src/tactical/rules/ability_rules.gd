class_name AbilityRules
extends RefCounted
## Targeting rules for data-defined abilities.
##
## Ability fields used here (see docs/architecture.md for the full schema):
##   target:       "self" | "enemy" | "ally" | "friendly" (ally or self) | "any_unit" | "cell"
##   range:        [min, max] in grid steps
##   radius:       area around the target cell (0 = single target)
##   affects:      "enemies" | "allies" | "all" (default depends on target)
##   requires_los: bool
##   ap_cost, cooldown


## Why the unit can't use the ability right now, or "" if it can.
static func usable_error(unit: BattleUnit, ability_id: String, ability: Dictionary) -> String:
	if not unit.abilities.has(ability_id):
		return "%s does not have %s" % [unit.name, ability_id]
	if unit.ap < int(ability.get("ap_cost", 0)):
		return "Not enough AP"
	if unit.cooldown_of(ability_id) > 0:
		return "On cooldown (%d)" % unit.cooldown_of(ability_id)
	return ""


## Cells the ability may target if the unit stood on `from_cell`.
static func target_cells(state: BattleState, unit: BattleUnit, ability: Dictionary, from_cell: Vector2i) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	var target: String = ability.get("target", "enemy")
	if target == "self":
		out.append(from_cell)
		return out
	var range_def: Array = ability.get("range", [1, 1])
	var min_range := int(range_def[0])
	var max_range := int(range_def[1])
	var needs_los: bool = ability.get("requires_los", false)
	for cell in state.grid.cells_within(from_cell, max_range):
		if state.grid.distance(from_cell, cell) < min_range:
			continue
		if needs_los and not state.grid.has_line_of_sight(from_cell, cell):
			continue
		if target == "cell":
			out.append(cell)
			continue
		var occupant := state.unit_at(cell)
		if occupant == null or (occupant == unit and target != "friendly"):
			continue
		# Under fog of war you can't target what your side can't see.
		if occupant.team != unit.team and not state.is_visible(unit.team, cell):
			continue
		if _matches(target, unit, occupant):
			out.append(cell)
	return out


## Cells covered by the ability's area if aimed at target_cell.
static func area_cells(state: BattleState, unit: BattleUnit, ability: Dictionary, target_cell: Vector2i) -> Array[Vector2i]:
	if ability.get("target", "enemy") == "self":
		return [unit.cell]
	return state.grid.cells_within(target_cell, int(ability.get("radius", 0)))


## Living units an ability aimed at target_cell would hit.
static func affected_units(state: BattleState, unit: BattleUnit, ability: Dictionary, target_cell: Vector2i) -> Array[BattleUnit]:
	var out: Array[BattleUnit] = []
	var target: String = ability.get("target", "enemy")
	if target == "self":
		out.append(unit)
		return out
	var radius := int(ability.get("radius", 0))
	var affects: String = ability.get("affects", default_affects(target))
	for u in state.living_units():
		if state.grid.distance(u.cell, target_cell) <= radius and _affects(affects, unit, u):
			out.append(u)
	return out


static func default_affects(target: String) -> String:
	match target:
		"enemy":
			return "enemies"
		"ally", "self", "friendly":
			return "allies"
	return "all"


static func _matches(target: String, user: BattleUnit, other: BattleUnit) -> bool:
	match target:
		"enemy":
			return other.team != user.team
		"ally", "friendly":
			return other.team == user.team
		"any_unit":
			return true
	return false


static func _affects(affects: String, user: BattleUnit, other: BattleUnit) -> bool:
	match affects:
		"enemies":
			return other.team != user.team
		"allies":
			return other.team == user.team
	return true
