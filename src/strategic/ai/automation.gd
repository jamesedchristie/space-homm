class_name Automation
extends RefCounted
## Player automation (Phase 7): the AI's judgement applied to things the player has handed over.
## - **Automated civilian ships** (`ship["auto"] = true` on a Constructor or Colony Ship): they pick
##   their next job and fly to it on their own, like the AI's workers and settlers.
## - **Auto-explore** (`Fleet.auto == "explore"`): a fleet flies to the nearest uncharted space (on
##   system maps: the nearest unsurveyed body), avoiding visible threats it can't beat.
## - **Governors** (`Planet.auto_build`): an idle colony queues what the AI would build there.
## The galaxy screen asks next_command() at the start of the player's turn until it returns null;
## each fleet and planet is handled once per turn.

var _ai := GalaxyAI.new()
var _turn := -1
var _done := {}


static func is_automated_ship(ship: Dictionary) -> bool:
	return bool(ship.get("auto", false))


## Whether the fleet runs itself (all its civilian ships automated, or auto-exploring).
static func is_automated(engine: GalaxyEngine, fleet: Fleet) -> bool:
	if fleet.auto == "explore":
		return true
	if not fleet.is_civilian_only(engine.data):
		return false
	for ship in fleet.ships:
		if not is_automated_ship(ship):
			return false
	return not fleet.ships.is_empty()


func next_command(engine: GalaxyEngine, faction_id: String) -> GalaxyCommand:
	var s := engine.state
	if s.turn_number != _turn:
		_turn = s.turn_number
		_done.clear()
	for planet: Planet in s.planets_of(faction_id):
		var key := "planet:" + planet.id
		if not planet.auto_build or not planet.queue.is_empty() or _done.has(key):
			continue
		_done[key] = true
		var choice := _ai.choose_build(engine, planet)
		if choice.is_empty():
			choice = _fallback_build(engine, planet)  # the AI may be saving up; a governor keeps building
		if not choice.is_empty():
			var cmd := QueueBuildCommand.new(faction_id, planet.id, choice["kind"], choice["id"], choice.get("body", ""))
			if engine.validate(cmd).is_empty():
				return cmd
	for fleet: Fleet in s.fleets_of(faction_id):
		if _done.has(fleet.id) or fleet.moves_left <= 0 or not fleet.order.is_empty():
			continue
		if fleet.auto == "explore":
			_done[fleet.id] = true
			var dest := explore_destination(engine, fleet)
			if dest != fleet.cell:
				return MoveFleetCommand.new(faction_id, fleet.id, dest)
			continue
		if not is_automated(engine, fleet):
			continue
		var work := _work_here(engine, fleet)
		if work != null:
			return work  # the fleet may still move afterwards (another ship, or the rest of the convoy)
		_done[fleet.id] = true
		var to := _ai._civilian_destination(engine, fleet)
		if to != fleet.cell:
			return MoveFleetCommand.new(faction_id, fleet.id, to)
	return null


## A job or colony for an automated ship of this fleet where it stands, or null.
func _work_here(engine: GalaxyEngine, fleet: Fleet) -> GalaxyCommand:
	var planet := engine.state.planet_at(fleet.cell)
	if planet == null:
		return null
	for ship in fleet.ships:
		if not is_automated_ship(ship):
			continue
		var role := Fleet.role_of(engine.data, ship["unit"])
		var cmd: GalaxyCommand = null
		if role == "constructor":
			var job := _ai._best_job(engine, planet, fleet.owner)
			if not job.is_empty():
				cmd = CivilianCommand.new(fleet.owner, planet.id, ship["uid"], CivilianCommand.JOB, job["body"], job["building"])
		elif role == "colony":
			var best := _ai._best_colony_body(engine, planet, fleet.owner)
			var good := GalaxyAI.SYSTEM_COLONY_SCORE if engine.is_system_scale() else GalaxyAI.COLONY_SCORE
			if not best.is_empty() and float(best["score"]) >= good:
				cmd = CivilianCommand.new(fleet.owner, planet.id, ship["uid"], CivilianCommand.FOUND, best["body"]["id"])
		if cmd != null and engine.validate(cmd).is_empty():
			return cmd
	return null


## Where an exploring fleet goes this turn: towards the nearest reachable uncharted cell (system
## maps: unsurveyed body) that no stronger visible enemy guards. Its own cell when nothing is left.
func explore_destination(engine: GalaxyEngine, fleet: Fleet) -> Vector2i:
	var s := engine.state
	var vis := engine.visible_cells(fleet.owner)
	var strength := fleet.strength(engine.data)
	var field := Pathfinding.distance_field(s.grid, [fleet.cell] as Array[Vector2i])
	var explored := engine.explored_cells(fleet.owner)
	var best: Variant = null
	var best_d := 1 << 30
	var candidates: Array[Vector2i] = []
	if engine.is_system_scale() and engine.campaign.get("survey", false):
		for p: Planet in s.planets.values():
			if not engine.is_surveyed(fleet.owner, p) and (p.owner.is_empty() or not s.at_war(fleet.owner, p.owner)):
				candidates.append(p.cell)
	for c: Vector2i in field:
		if not explored.has(c):
			candidates.append(c)
	for c in candidates:
		var d: int = field.get(c, 1 << 30)
		if d < best_d and (s.fleet_at(c) == null or c == fleet.cell) \
				and not _ai._dangerous(engine, fleet, c, vis, strength, GalaxyAI.ATTACK_RATIO):
			best_d = d
			best = c
	if best == null:
		return fleet.cell
	return _ai._step_towards(engine, fleet, best)


## The first affordable building in the AI's priority order, for a governor whose AI would rather
## save up. {} if nothing fits.
func _fallback_build(engine: GalaxyEngine, planet: Planet) -> Dictionary:
	var options := EmpireRules.build_options(engine, planet).filter(func(o: Dictionary) -> bool:
		return o.get("ok", false) and o.get("kind", "") == "building")
	for b_id: String in GalaxyAI.BUILD_PRIORITY:
		for o: Dictionary in options:
			if o["id"] == b_id and _ai._building_sensible(engine, planet, o):
				return o
	return {}
