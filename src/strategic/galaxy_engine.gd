class_name GalaxyEngine
extends RefCounted
## Strategic layer rules: factions take turns moving fleets on a hex galaxy,
## with fog of war, planet capture and battles. Same shape as BattleEngine:
## submit(command) -> CommandResult with events; queries never change state.
##
## Battles: when a move runs into an enemy fleet, the engine sets
## state.pending_battle and refuses further commands until the battle is
## resolved, either by playing it (pending_battle_scenario() ->
## BattleEngine -> resolve_pending_battle()) or by auto_resolve_pending_battle().

## Fraction of max hull a ship repairs per turn at a friendly planet.
const REPAIR_RATE := 0.25
const DEFAULT_PLANET_SENSOR := 2

var state: GalaxyState
var data: DataRegistry
var campaign: Dictionary
var _events: Array[Dictionary] = []


static func from_campaign(p_data: DataRegistry, campaign_ref: Variant, p_seed: int = 0) -> GalaxyEngine:
	var def: Dictionary = campaign_ref if campaign_ref is Dictionary else p_data.campaigns.get(campaign_ref, {})
	if def.is_empty():
		push_error("GalaxyEngine: unknown campaign '%s'" % str(campaign_ref))
		return null
	var engine := GalaxyEngine.new()
	engine.data = p_data
	engine.campaign = def
	var s := GalaxyState.new()
	engine.state = s
	s.seed_value = p_seed if p_seed != 0 else randi()
	s.rng.seed = s.seed_value
	s.max_turns = int(def.get("max_turns", 200))
	s.grid = HexGrid.from_map(def.get("map", {}), p_data.galaxy_terrain)

	var team := 0
	for f: Dictionary in def.get("factions", []):
		s.factions.append({
			"id": f["id"],
			"name": f.get("name", f["id"]),
			"controller": f.get("controller", "ai"),
			"team": team,
		})
		s.explored[f["id"]] = {}
		team += 1

	for p_def: Dictionary in def.get("planets", []):
		var p := Planet.new()
		p.id = p_def.get("id", s.make_uid("planet"))
		p.name = p_def.get("name", p.id)
		p.type = p_def.get("type", "")
		p.cell = s.grid.cell_from_layout(_layout(p_def.get("at", [0, 0])))
		p.owner = p_def.get("owner", "")
		p.sensor = int(p_def.get("sensor", DEFAULT_PLANET_SENSOR))
		p.description = p_def.get("description", p_data.planet_types.get(p.type, {}).get("description", ""))
		s.planets[p.id] = p

	for f_def: Dictionary in def.get("fleets", []):
		var fleet := Fleet.new()
		fleet.id = s.make_uid("fleet")
		fleet.name = f_def.get("name", fleet.id)
		fleet.owner = f_def["owner"]
		fleet.cell = s.grid.cell_from_layout(_layout(f_def.get("at", [0, 0])))
		for ship_def: Dictionary in f_def.get("ships", []):
			var unit_def: Dictionary = p_data.units[ship_def["unit"]]
			fleet.ships.append({
				"uid": s.make_uid("ship"),
				"unit": ship_def["unit"],
				"name": ship_def.get("name", unit_def.get("name", ship_def["unit"])),
				"hull": int(ship_def.get("hull", unit_def["stats"]["max_hull"])),
			})
		s.fleets[fleet.id] = fleet
	return engine


static func _layout(at: Array) -> Vector2i:
	return Vector2i(int(at[0]), int(at[1]))


# =============================================================================
# Flow
# =============================================================================

func start() -> Array[Dictionary]:
	emit({"type": GalaxyEvents.CAMPAIGN_STARTED, "seed": state.seed_value})
	state.turn_number = 1
	state.current_faction_index = 0
	_begin_faction_turn()
	return _flush()


func submit(cmd: GalaxyCommand) -> CommandResult:
	var error := validate(cmd)
	if not error.is_empty():
		return CommandResult.failure(error)
	if cmd is MoveFleetCommand:
		_do_move(cmd)
	elif cmd is EndFactionTurnCommand:
		_end_faction_turn()
	return CommandResult.success(_flush())


func validate(cmd: GalaxyCommand) -> String:
	if state.is_over:
		return "The campaign is over"
	if not state.pending_battle.is_empty():
		return "Resolve the battle first"
	if cmd == null or cmd.faction_id != current_faction_id():
		return "It is not that faction's turn"
	if cmd is MoveFleetCommand:
		var fleet: Fleet = state.fleets.get(cmd.fleet_id)
		if fleet == null or fleet.owner != cmd.faction_id:
			return "Not your fleet"
		if cmd.to == fleet.cell:
			return "Already there"
		if not reachable_for(fleet.id).has(cmd.to):
			return "Cannot reach that system this turn"
	elif not cmd is EndFactionTurnCommand:
		return "Unknown command"
	return ""


# =============================================================================
# Queries
# =============================================================================

func current_faction_id() -> String:
	return state.current_faction()["id"]


func controller_of(faction_id: String) -> String:
	return state.faction(faction_id).get("controller", "ai")


## Cells the faction can see right now (around its fleets and planets).
func visible_cells(faction_id: String) -> Dictionary:
	var vis := {}
	for f in state.fleets_of(faction_id):
		for c in state.grid.cells_within(f.cell, f.sensor(data)):
			vis[c] = true
	for p in state.planets_of(faction_id):
		for c in state.grid.cells_within(p.cell, p.sensor):
			vis[c] = true
	return vis


func explored_cells(faction_id: String) -> Dictionary:
	return state.explored.get(faction_id, {})


func can_see_fleet(faction_id: String, fleet: Fleet, visible: Dictionary = {}) -> bool:
	if fleet.owner == faction_id:
		return true
	if visible.is_empty():
		visible = visible_cells(faction_id)
	return visible.has(fleet.cell)


## Where the fleet can go this turn, using only what its owner knows: own
## fleets block, visible enemy fleets can be attacked but not passed, hidden
## enemies are unknown (and will intercept the move).
## Returns {cell: {"cost", "from"}}.
func reachable_for(fleet_id: String) -> Dictionary:
	var fleet: Fleet = state.fleets[fleet_id]
	var vis := visible_cells(fleet.owner)
	return Pathfinding.reachable(state.grid, fleet.cell, fleet.moves_left,
		func(c: Vector2i) -> bool:
			var other := state.fleet_at(c)
			return other != null and other.owner == fleet.owner,
		func(c: Vector2i) -> bool:
			var other := state.fleet_at(c)
			return other != null and other.owner != fleet.owner and vis.has(c))


## Reachable cells holding a visible enemy fleet.
func attack_targets(fleet_id: String, reach: Dictionary = {}) -> Array[Vector2i]:
	var fleet: Fleet = state.fleets[fleet_id]
	if reach.is_empty():
		reach = reachable_for(fleet_id)
	var vis := visible_cells(fleet.owner)
	var out: Array[Vector2i] = []
	for c: Vector2i in reach:
		var other := state.fleet_at(c)
		if other != null and other.owner != fleet.owner and vis.has(c):
			out.append(c)
	return out


func has_pending_battle() -> bool:
	return not state.pending_battle.is_empty()


## Tactical map for a battle at `cell`: planet type, then terrain, then default.
func battle_map_for(cell: Vector2i) -> String:
	var planet := state.planet_at(cell)
	if planet != null and data.planet_types.get(planet.type, {}).has("battle_map"):
		return data.planet_types[planet.type]["battle_map"]
	var terrain := state.grid.terrain_def(cell)
	if terrain.has("battle_map"):
		return terrain["battle_map"]
	return campaign.get("default_battle_map", "open_space")


func location_name(cell: Vector2i) -> String:
	var planet := state.planet_at(cell)
	if planet != null:
		return planet.name
	var terrain := state.grid.terrain_def(cell)
	return "deep space" if terrain.is_empty() else "the %s" % terrain.get("name", "void").to_lower()


## "at Haven", "in deep space", "in the nebula": for sentences and titles.
func location_phrase(cell: Vector2i) -> String:
	return ("at %s" if state.planet_at(cell) != null else "in %s") % location_name(cell)


## Scenario dictionary for BattleEngine.from_scenario() describing the
## pending battle. Attacker deploys west, defender east.
func pending_battle_scenario() -> Dictionary:
	var b := state.pending_battle
	var cell: Vector2i = b["cell"]
	var map_id := battle_map_for(cell)
	var deployment: Dictionary = data.maps[map_id].get("deployment", {})
	var teams: Array = []
	for side: Array in [[b["attacker"], "west"], [b["defender"], "east"]]:
		var fleet: Fleet = state.fleets[side[0]]
		var faction := state.faction(fleet.owner)
		var slots: Array = deployment.get(side[1], [])
		var units: Array = []
		for i in mini(fleet.ships.size(), slots.size()):
			var ship := fleet.ships[i]
			units.append({"unit": ship["unit"], "name": ship["name"], "at": slots[i],
					"hull": ship["hull"], "ref": ship["uid"]})
		teams.append({"team": faction["team"], "name": fleet.name,
				"controller": faction["controller"], "units": units})
	return {
		"id": "galaxy_battle",
		"name": "Battle %s" % location_phrase(cell),
		"map": map_id,
		"max_rounds": int(campaign.get("battle_max_rounds", 30)),
		"teams": teams,
		"objectives": [{"type": "eliminate_all", "description": "Destroy the enemy fleet"}],
	}


## Deterministic seed for the next battle (so campaigns replay exactly).
func next_battle_seed() -> int:
	return int(state.rng.randi() | 1)


# =============================================================================
# Battle resolution
# =============================================================================

## Writes a finished tactical battle back into the galaxy: surviving ships
## keep their hull damage, destroyed ships are removed, empty fleets vanish.
func resolve_pending_battle(battle: BattleEngine) -> Array[Dictionary]:
	var b := state.pending_battle
	var by_ref := {}
	for u: BattleUnit in battle.state.units.values():
		if not u.ref.is_empty():
			by_ref[u.ref] = u
	var losses := {}
	for fleet_id: String in [b["attacker"], b["defender"]]:
		var fleet: Fleet = state.fleets[fleet_id]
		var survivors: Array[Dictionary] = []
		var lost: Array[String] = []
		for ship in fleet.ships:
			var u: BattleUnit = by_ref.get(ship["uid"])
			if u == null:
				survivors.append(ship)  # held in reserve, didn't fight
			elif u.alive:
				ship["hull"] = u.hull
				survivors.append(ship)
			else:
				lost.append(ship["name"])
		fleet.ships = survivors
		losses[fleet_id] = lost

	var winner := ""
	if battle.state.winner >= 0:
		winner = state.faction_for_team(battle.state.winner).get("id", "")
	emit({"type": GalaxyEvents.BATTLE_RESOLVED, "attacker": b["attacker"], "defender": b["defender"],
			"attacker_name": state.fleets[b["attacker"]].name, "defender_name": state.fleets[b["defender"]].name,
			"cell": b["cell"], "winner": winner, "losses": losses, "rounds": battle.state.round_number})
	for fleet_id: String in [b["attacker"], b["defender"]]:
		var fleet: Fleet = state.fleets[fleet_id]
		if fleet.ships.is_empty():
			state.fleets.erase(fleet_id)
			emit({"type": GalaxyEvents.FLEET_DESTROYED, "fleet": fleet_id, "owner": fleet.owner, "name": fleet.name})
	state.pending_battle = {}
	_update_explored()
	_check_eliminations()
	return _flush()


## Fights the pending battle with AI on both sides and applies the result.
func auto_resolve_pending_battle() -> Array[Dictionary]:
	var battle := BattleEngine.from_scenario(data, pending_battle_scenario(), next_battle_seed())
	AutoResolver.resolve(battle)
	return resolve_pending_battle(battle)


# =============================================================================
# Mutation helpers
# =============================================================================

func emit(event: Dictionary) -> void:
	_events.append(event)


func _do_move(cmd: MoveFleetCommand) -> void:
	var fleet: Fleet = state.fleets[cmd.fleet_id]
	var reach := reachable_for(fleet.id)
	var planned := Pathfinding.path_to(reach, cmd.to)
	var walked: Array[Vector2i] = [fleet.cell]
	var enemy: Fleet = null
	var ambush := false
	for i in range(1, planned.size()):
		var next := planned[i]
		var occupant := state.fleet_at(next)
		if occupant != null and occupant.owner != fleet.owner:
			enemy = occupant
			ambush = next != cmd.to
			break
		fleet.moves_left -= state.grid.move_cost(next)
		fleet.cell = next
		walked.append(next)
		_reveal_around(fleet)
	if walked.size() > 1:
		emit({"type": GalaxyEvents.FLEET_MOVED, "fleet": fleet.id, "path": walked, "moves_left": fleet.moves_left})

	if enemy != null:
		fleet.moves_left = 0
		state.pending_battle = {"attacker": fleet.id, "defender": enemy.id, "cell": enemy.cell, "ambush": ambush}
		emit({"type": GalaxyEvents.BATTLE_TRIGGERED, "attacker": fleet.id, "defender": enemy.id,
				"cell": enemy.cell, "ambush": ambush})
		return

	var planet := state.planet_at(fleet.cell)
	if planet != null and planet.owner != fleet.owner:
		var previous := planet.owner
		planet.owner = fleet.owner
		emit({"type": GalaxyEvents.PLANET_CAPTURED, "planet": planet.id, "faction": fleet.owner,
				"previous_owner": previous, "fleet": fleet.id})
		_update_explored()
		_check_eliminations()


func _begin_faction_turn() -> void:
	var faction_id := current_faction_id()
	for fleet in state.fleets_of(faction_id):
		fleet.moves_left = fleet.speed(data)
		var planet := state.planet_at(fleet.cell)
		if planet != null and planet.owner == faction_id:
			var repaired := 0
			for ship in fleet.ships:
				var max_hull := int(data.units[ship["unit"]]["stats"]["max_hull"])
				var amount := mini(max_hull - int(ship["hull"]), ceili(max_hull * REPAIR_RATE))
				ship["hull"] = int(ship["hull"]) + amount
				repaired += amount
			if repaired > 0:
				emit({"type": GalaxyEvents.FLEET_REPAIRED, "fleet": fleet.id, "amount": repaired, "planet": planet.id})
	_update_explored()
	emit({"type": GalaxyEvents.TURN_STARTED, "turn": state.turn_number, "faction": faction_id})


func _end_faction_turn() -> void:
	emit({"type": GalaxyEvents.TURN_ENDED, "turn": state.turn_number, "faction": current_faction_id()})
	for i in state.factions.size():
		state.current_faction_index = (state.current_faction_index + 1) % state.factions.size()
		if state.current_faction_index == 0:
			state.turn_number += 1
		if current_faction_id() not in state.eliminated:
			break
	if state.turn_number > state.max_turns:
		_finish("", "max_turns")
		return
	_begin_faction_turn()


func _reveal_around(fleet: Fleet) -> void:
	var explored: Dictionary = state.explored[fleet.owner]
	for c in state.grid.cells_within(fleet.cell, fleet.sensor(data)):
		explored[c] = true


func _update_explored() -> void:
	for f in state.factions:
		var explored: Dictionary = state.explored[f["id"]]
		for c: Vector2i in visible_cells(f["id"]):
			explored[c] = true


## A faction with no fleets and no planets is out; last one standing wins.
func _check_eliminations() -> void:
	if state.is_over:
		return
	for f in state.factions:
		var fid: String = f["id"]
		if fid in state.eliminated:
			continue
		if state.fleets_of(fid).is_empty() and state.planets_of(fid).is_empty():
			state.eliminated.append(fid)
			emit({"type": GalaxyEvents.FACTION_ELIMINATED, "faction": fid})
	var remaining: Array[String] = []
	for f in state.factions:
		if f["id"] not in state.eliminated:
			remaining.append(f["id"])
	if remaining.size() <= 1:
		_finish(remaining[0] if remaining.size() == 1 else "", "elimination")


func _finish(winner: String, reason: String) -> void:
	state.is_over = true
	state.winner = winner
	emit({"type": GalaxyEvents.CAMPAIGN_ENDED, "winner": winner, "reason": reason})


func _flush() -> Array[Dictionary]:
	var out := _events
	_events = []
	return out
