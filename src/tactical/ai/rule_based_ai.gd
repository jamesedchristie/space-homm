class_name RuleBasedAI
extends RefCounted
## Simple utility AI for the active unit. It submits the same commands a human
## does, one per decide() call:
##   1. Use the best-scoring ability from where it stands.
##   2. Otherwise (once per turn) move to the cell that enables the best
##      ability, or approach the nearest enemy around obstacles.
##   3. Otherwise end the turn.
## Scores come from BattleEngine.preview_ability(), so new abilities are
## understood automatically. Statuses carry an "ai_value" in their JSON: how
## good the status is for whoever has it (negative for debuffs).

const KILL_BONUS := 40.0
const SHIELD_WEIGHT := 0.5
const HEAL_WEIGHT := 0.6
const FRIENDLY_FIRE_WEIGHT := 1.5
const SELF_IN_BLAST_PENALTY := 30.0
const THREAT_RANGE := 7
const MIN_SCORE := 1.0

var _moved_turn_key := ""


func decide(engine: BattleEngine) -> BattleCommand:
	var unit := engine.state.active_unit()
	if unit == null:
		return null
	var best := best_action(engine, unit, unit.cell, unit.ap)
	if best["score"] >= MIN_SCORE:
		return UseAbilityCommand.new(unit.id, best["ability"], best["target"])

	var turn_key := "%d:%s" % [engine.state.round_number, unit.id]
	if _moved_turn_key != turn_key:
		_moved_turn_key = turn_key
		var dest := _choose_move(engine, unit)
		if dest != unit.cell:
			return MoveCommand.new(unit.id, dest)
	return EndTurnCommand.new(unit.id)


## Best ability use if `unit` stood on from_cell with ap_budget AP.
## Returns {"score": float, "ability": String, "target": Vector2i}.
func best_action(engine: BattleEngine, unit: BattleUnit, from_cell: Vector2i, ap_budget: int) -> Dictionary:
	var best := {"score": 0.0, "ability": "", "target": from_cell}
	var enemies := engine.state.living_enemies_of(unit)
	var threatened := false
	for e in enemies:
		if engine.state.grid.distance(e.cell, from_cell) <= THREAT_RANGE:
			threatened = true
			break

	for ability_id in unit.abilities:
		var ability: Dictionary = engine.data.abilities[ability_id]
		if int(ability.get("ap_cost", 0)) > ap_budget or unit.cooldown_of(ability_id) > 0:
			continue
		if ability.get("target", "enemy") == "self" and not threatened:
			continue
		for target in _candidate_targets(engine, unit, ability_id, ability, from_cell, enemies):
			var s := score_action(engine, unit, ability_id, ability, target, from_cell)
			if s > best["score"]:
				best = {"score": s, "ability": ability_id, "target": target}
	return best


func score_action(engine: BattleEngine, unit: BattleUnit, ability_id: String, ability: Dictionary,
		target: Vector2i, from_cell: Vector2i) -> float:
	var score := 0.0
	for p in engine.preview_ability(unit.id, ability_id, target):
		var other := engine.state.get_unit(p["unit"])
		# Hypothetical position: the unit will not be on its current cell.
		if other == unit and from_cell != unit.cell and ability.get("target", "") != "self":
			continue
		var harm: float = p["shield_damage"] * SHIELD_WEIGHT + p["hull_damage"]
		if p["lethal"] and p["hull_damage"] > 0:
			harm += KILL_BONUS
		var help: float = p["heal"] * HEAL_WEIGHT
		for st: Dictionary in p["statuses"]:
			if other.find_status(st["status"]) == null:
				help += float(engine.data.statuses[st["status"]].get("ai_value", 0.0)) * st["chance"]
		var net := help - harm  # how good this is for `other`
		if other.team != unit.team:
			score -= net
		else:
			score += net * (FRIENDLY_FIRE_WEIGHT if net < 0.0 else 1.0)

	var radius := int(ability.get("radius", 0))
	var affects: String = ability.get("affects", AbilityRules.default_affects(ability.get("target", "enemy")))
	if from_cell != unit.cell and radius > 0 and affects != "enemies" \
			and engine.state.grid.distance(from_cell, target) <= radius:
		score -= SELF_IN_BLAST_PENALTY
	return score


## Cell-targeted (area) abilities could aim anywhere; only consider cells
## whose blast would touch an enemy.
func _candidate_targets(engine: BattleEngine, unit: BattleUnit, ability_id: String, ability: Dictionary,
		from_cell: Vector2i, enemies: Array[BattleUnit]) -> Array[Vector2i]:
	var cells := engine.ability_targets(unit.id, ability_id, from_cell)
	if ability.get("target", "enemy") != "cell":
		return cells
	var radius := int(ability.get("radius", 0))
	var out: Array[Vector2i] = []
	for c in cells:
		for e in enemies:
			if engine.state.grid.distance(c, e.cell) <= radius:
				out.append(c)
				break
	return out


func _choose_move(engine: BattleEngine, unit: BattleUnit) -> Vector2i:
	var reach := engine.reachable_cells(unit.id)
	var best_cell := unit.cell
	var best_score := MIN_SCORE
	for cell: Vector2i in reach:
		if cell == unit.cell:
			continue
		var cost: int = reach[cell]["cost"]
		var s: float = best_action(engine, unit, cell, unit.ap - cost)["score"] - 0.01 * cost
		if s > best_score:
			best_score = s
			best_cell = cell
	if best_cell != unit.cell:
		return best_cell

	# Nothing to shoot from anywhere reachable: close in on the nearest enemy.
	var sources: Array[Vector2i] = []
	for e in engine.state.living_enemies_of(unit):
		sources.append(e.cell)
	if sources.is_empty():
		return unit.cell
	var field := Pathfinding.distance_field(engine.state.grid, sources)
	var best_dist: int = field.get(unit.cell, 1 << 30)
	for cell: Vector2i in reach:
		var d: int = field.get(cell, 1 << 30)
		if d < best_dist or (d == best_dist and cell != unit.cell and best_cell != unit.cell
				and reach[cell]["cost"] < reach[best_cell]["cost"]):
			best_dist = d
			best_cell = cell
	return best_cell
