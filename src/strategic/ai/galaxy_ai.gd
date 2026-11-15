class_name GalaxyAI
extends RefCounted
## Rule-based strategic AI. Plays fair: it uses the same fog-of-war queries as
## the player, so it only reacts to enemy fleets it can see. Per fleet, in order:
##   1. Attack a visible enemy fleet it is strong enough to beat.
##   2. If badly damaged, go home to the nearest friendly planet to repair.
##   3. With a ready commander, investigate the nearest known anomaly (mission).
##   4. Otherwise head for the nearest planet it doesn't own.
## One move per fleet per turn, then it ends the turn.

## Attack only if our strength is at least this multiple of theirs.
const ATTACK_RATIO := 0.9
const RETREAT_HULL_RATIO := 0.5

var _turn_key := ""
var _done := {}
## "fleet:anomaly:mission" keys this AI has already sent a fleet to (so a
## declined or failed mission isn't retried forever).
var _tried := {}


func decide(engine: GalaxyEngine) -> GalaxyCommand:
	var faction_id := engine.current_faction_id()
	var key := "%d:%s" % [engine.state.turn_number, faction_id]
	if key != _turn_key:
		_turn_key = key
		_done.clear()
	for fleet in engine.state.fleets_of(faction_id):
		if _done.has(fleet.id) or fleet.moves_left <= 0:
			continue
		_done[fleet.id] = true
		var dest := choose_destination(engine, fleet)
		if dest != fleet.cell:
			return MoveFleetCommand.new(faction_id, fleet.id, dest)
	return EndFactionTurnCommand.new(faction_id)


func choose_destination(engine: GalaxyEngine, fleet: Fleet) -> Vector2i:
	var s := engine.state
	var data := engine.data
	var vis := engine.visible_cells(fleet.owner)
	var target: Variant = null

	# 1. Attack something we can beat.
	var best := 1 << 30
	var my_strength := fleet.strength(data)
	for other: Fleet in s.fleets.values():
		if other.owner == fleet.owner or not vis.has(other.cell):
			continue
		if my_strength < other.strength(data) * ATTACK_RATIO:
			continue
		var d := s.grid.distance(fleet.cell, other.cell)
		if d < best:
			best = d
			target = other.cell

	# 2. Retreat to repair.
	if target == null and fleet.hull_ratio(data) < RETREAT_HULL_RATIO:
		var home := _nearest(s, fleet.cell, s.planets_of(fleet.owner))
		if home != null:
			if home.cell == fleet.cell:
				return fleet.cell
			target = home.cell

	# 3. Investigate anomalies the fleet is ready for.
	var anomaly_key := ""
	if target == null:
		var best_a := 1 << 30
		var explored := engine.explored_cells(fleet.owner)
		for a: Dictionary in s.anomalies.values():
			var key := "%s:%s:%s" % [fleet.id, a["id"], a["mission"]]
			if _tried.has(key) or a.get("faction", "") not in ["", fleet.owner] or not explored.has(a["cell"]):
				continue
			if not _ready_for(engine, fleet, data.missions[a["mission"]]):
				continue
			var d := s.grid.distance(fleet.cell, a["cell"])
			if d < best_a and s.fleet_at(a["cell"]) == null:
				best_a = d
				target = a["cell"]
				anomaly_key = key

	# 4. Expand.
	if target == null:
		var candidates: Array[Planet] = []
		for p: Planet in s.planets.values():
			if p.owner != fleet.owner:
				candidates.append(p)
		var planet := _nearest(s, fleet.cell, candidates)
		if planet != null:
			target = planet.cell

	if target == null:
		return fleet.cell
	var dest := _step_towards(engine, fleet, target)
	if not anomaly_key.is_empty() and dest == target:
		_tried[anomaly_key] = true
	return dest


## The AI only takes missions its away team is ready for: a ready commander
## of at least the recommended level (or none needed, e.g. rescues).
func _ready_for(engine: GalaxyEngine, fleet: Fleet, mission: Dictionary) -> bool:
	if not mission.get("requires_hero", true):
		return true
	var commander := engine.state.active_commander(fleet)
	return commander != null and commander.level >= int(mission.get("recommended_level", 1))


## Furthest useful cell this turn on the way to target.
func _step_towards(engine: GalaxyEngine, fleet: Fleet, target: Vector2i) -> Vector2i:
	var reach := engine.reachable_for(fleet.id)
	if reach.has(target):
		return target
	var attackable := engine.attack_targets(fleet.id, reach)
	var field := Pathfinding.distance_field(engine.state.grid, [target])
	var best_cell := fleet.cell
	var best_dist: int = field.get(fleet.cell, 1 << 30)
	for c: Vector2i in reach:
		if c in attackable:
			continue  # don't blunder into fleets we decided not to fight
		var d: int = field.get(c, 1 << 30)
		if d < best_dist:
			best_dist = d
			best_cell = c
	return best_cell


func _nearest(s: GalaxyState, from: Vector2i, planets: Array[Planet]) -> Planet:
	var best: Planet = null
	var best_d := 1 << 30
	for p in planets:
		var d := s.grid.distance(from, p.cell)
		if d < best_d:
			best_d = d
			best = p
	return best
