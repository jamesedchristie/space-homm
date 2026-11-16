class_name GalaxyAI
extends RefCounted
## Rule-based strategic AI. Plays fair: it uses the same fog-of-war queries as
## the player, so it only reacts to enemy fleets it can see.
## Each turn it first runs its empire (one command at a time):
##   research the cheapest available tech; give every idle planet something to
##   build (ships when outgunned, otherwise economy buildings); then diplomacy
##   (make peace with AI factions that will accept, declare war on hated weak ones).
## Then per fleet, in order:
##   1. Attack a visible fleet it is at war with and strong enough to beat.
##   2. If badly damaged, go home to the nearest friendly planet to repair;
##      a small fleet without a commander joins a friendly fleet within reach.
##   3. With a ready commander, investigate the nearest known anomaly (mission).
##   3b. Pick up a known discovery within 4 systems.
##   4. Otherwise head for the nearest planet it can take (unowned or an enemy's),
##      skipping planets whose defenses are too strong for it.
## One move per fleet per turn, then it ends the turn.
##
## Personality: a campaign faction's "ai" entry can override attack_ratio,
## hunt_range and retreat_hull_ratio (e.g. cautious traders, reckless raiders).

## Attack only if our strength is at least this multiple of theirs (default).
const ATTACK_RATIO := 0.9
const RETREAT_HULL_RATIO := 0.5
## Only hunt enemy fleets this close; further away, go take planets instead.
const HUNT_RANGE := 5
## Fleets smaller than this wait at their shipyard while a ship is being built
## there, instead of trickling out one ship at a time.
const MUSTER_SIZE := 3
## Build order for economy buildings.
const BUILD_PRIORITY := ["colony", "mining_base", "gas_refinery", "research_station", "trade_hub", "defense_platform", "shipyard"]

var _turn_key := ""
var _done := {}
## "fleet:anomaly:mission" keys this AI has already sent a fleet to (so a
## declined or failed mission isn't retried forever).
var _tried := {}
var _planned := {}  # planet ids given a build order this turn
var _diplomacy_done := false


func decide(engine: GalaxyEngine) -> GalaxyCommand:
	var faction_id := engine.current_faction_id()
	var key := "%d:%s" % [engine.state.turn_number, faction_id]
	if key != _turn_key:
		_turn_key = key
		_done.clear()
		_planned.clear()
		_diplomacy_done = false
	var empire_cmd := _empire_command(engine, faction_id)
	if empire_cmd != null:
		return empire_cmd
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
	var attack_ratio := personality(engine, fleet.owner, "attack_ratio", ATTACK_RATIO)
	var hunt_range := int(personality(engine, fleet.owner, "hunt_range", HUNT_RANGE))
	for other: Fleet in s.fleets.values():
		if not s.at_war(fleet.owner, other.owner) or not vis.has(other.cell):
			continue
		# A fleet parked at its own planet fights alongside the planet's platforms.
		var their_strength := other.strength(data)
		var at := s.planet_at(other.cell)
		if at != null and at.owner == other.owner:
			their_strength += defense_strength(engine, at)
		if my_strength < their_strength * attack_ratio:
			continue
		var d := s.grid.distance(fleet.cell, other.cell)
		if d < best and d <= hunt_range:
			best = d
			target = other.cell

	# Muster: wait for the ship under construction here.
	var here := s.planet_at(fleet.cell)
	if target == null and here != null and here.owner == fleet.owner and fleet.ships.size() < MUSTER_SIZE \
			and here.queue.get("kind", "") == "unit":
		return fleet.cell

	# 2. Retreat to repair.
	if target == null and fleet.hull_ratio(data) < personality(engine, fleet.owner, "retreat_hull_ratio", RETREAT_HULL_RATIO):
		var home := _nearest(s, fleet.cell, s.planets_of(fleet.owner))
		if home != null:
			if home.cell == fleet.cell:
				return fleet.cell
			target = home.cell

	# 2b. Regroup: a small fleet with nothing to attack joins a friendly fleet
	# it can reach this turn (bigger fleets win more battles).
	if target == null and fleet.ships.size() < MUSTER_SIZE and fleet.hero_id.is_empty():
		var reach := engine.reachable_for(fleet.id)
		var best_join: Fleet = null
		for other: Fleet in s.fleets_of(fleet.owner):
			if other != fleet and reach.has(other.cell) and engine.can_merge(fleet, other) \
					and (best_join == null or other.ships.size() > best_join.ships.size()):
				best_join = other
		if best_join != null:
			return best_join.cell

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

	# 3b. Grab a discovery nearby (salvage, signals, caches): cheap, often rich.
	if target == null:
		var best_find := 5
		var explored_cells := engine.explored_cells(fleet.owner)
		for d: Dictionary in s.discoveries.values():
			var dist := s.grid.distance(fleet.cell, d["cell"])
			if dist < best_find and explored_cells.has(d["cell"]) and s.fleet_at(d["cell"]) == null \
					and not _dangerous(engine, fleet, d["cell"], vis, my_strength, attack_ratio):
				best_find = dist
				target = d["cell"]

	# 4. Expand.
	if target == null:
		var candidates: Array[Planet] = []
		for p: Planet in s.planets.values():
			if p.owner == fleet.owner or not (p.owner.is_empty() or s.at_war(fleet.owner, p.owner)):
				continue
			if defense_strength(engine, p) > my_strength * attack_ratio:
				continue
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


## Whether a visible enemy fleet that would beat us sits within 3 of `cell`
## (don't wander off for salvage into the jaws of a raider pack).
func _dangerous(engine: GalaxyEngine, fleet: Fleet, cell: Vector2i, vis: Dictionary, my_strength: float,
		attack_ratio: float) -> bool:
	for other: Fleet in engine.state.fleets.values():
		if engine.state.at_war(fleet.owner, other.owner) and vis.has(other.cell) \
				and engine.state.grid.distance(other.cell, cell) <= 3 \
				and other.strength(engine.data) * attack_ratio > my_strength:
			return true
	return false


## A faction's AI setting from its campaign "ai" entry, or the default.
static func personality(engine: GalaxyEngine, faction_id: String, key: String, default: float) -> float:
	return float(engine.state.faction(faction_id).get("ai", {}).get(key, default))


## Effective hit points of a planet's defense platforms.
func defense_strength(engine: GalaxyEngine, planet: Planet) -> float:
	var total := 0.0
	for unit_id in EmpireRules.defense_units(engine, planet):
		var stats: Dictionary = engine.data.units[unit_id]["stats"]
		total += float(stats["max_hull"]) + float(stats["max_shields"]) * 0.5
	return total


# --- Empire management --------------------------------------------------------

## Next research/production/diplomacy command for this turn, or null when done.
func _empire_command(engine: GalaxyEngine, faction_id: String) -> GalaxyCommand:
	var s := engine.state
	if s.research[faction_id]["current"] == "":
		var options := ResearchRules.available(engine, faction_id)
		if not options.is_empty():
			options.sort_custom(func(a: String, b: String) -> bool:
				return ResearchRules.cost(engine, a) < ResearchRules.cost(engine, b))
			return SetResearchCommand.new(faction_id, options[0])
	for planet in s.planets_of(faction_id):
		if not planet.queue.is_empty() or _planned.has(planet.id):
			continue
		_planned[planet.id] = true
		var choice := choose_build(engine, planet)
		if not choice.is_empty():
			return QueueBuildCommand.new(faction_id, planet.id, choice["kind"], choice["id"], choice.get("body", ""))
	if not _diplomacy_done:
		_diplomacy_done = true
		return _diplomacy(engine, faction_id)
	return null


## What an idle planet should build: ships when outgunned by the factions we
## are at war with, otherwise economy buildings, otherwise more ships.
func choose_build(engine: GalaxyEngine, planet: Planet) -> Dictionary:
	var ships: Array[Dictionary] = []
	var buildings := {}
	for option in EmpireRules.build_options(engine, planet):
		if not option["ok"]:
			continue
		if option["kind"] == "unit":
			ships.append(option)
		elif not buildings.has(option["id"]):
			buildings[option["id"]] = option
	ships.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return engine.data.units[a["id"]]["stats"]["max_hull"] > engine.data.units[b["id"]]["stats"]["max_hull"])
	var mine := DiplomacyRules.military_strength(engine, planet.owner)
	var theirs := 0.0
	for f in engine.state.factions:
		if engine.state.at_war(planet.owner, f["id"]) and not engine.state.is_eliminated(f["id"]):
			theirs = maxf(theirs, DiplomacyRules.military_strength(engine, f["id"]))
	if not ships.is_empty() and mine < theirs * 0.9:
		return ships[0]
	# Without any shipyard a faction can never rebuild its fleet: fix that first.
	if buildings.has("shipyard"):
		var any_yard := false
		for p in engine.state.planets_of(planet.owner):
			any_yard = any_yard or EmpireRules.has_shipyard(engine, p)
		if not any_yard:
			return buildings["shipyard"]
	for b_id in BUILD_PRIORITY:
		if buildings.has(b_id):
			return buildings[b_id]
	if not ships.is_empty() and mine < theirs * 1.5:
		return ships[0]
	return {}


func _diplomacy(engine: GalaxyEngine, faction_id: String) -> GalaxyCommand:
	var s := engine.state
	if s.faction(faction_id).get("always_hostile", false):
		return null
	var mine := DiplomacyRules.military_strength(engine, faction_id)
	for f in s.factions:
		var other: String = f["id"]
		if other == faction_id or s.is_eliminated(other):
			continue
		var theirs := DiplomacyRules.military_strength(engine, other)
		if s.at_war(faction_id, other):
			# Make peace with AI factions that would accept, unless we're crushing them.
			if f["controller"] != "player" and mine < theirs * 1.5 \
					and DiplomacyRules.peace_refusal(engine, other, faction_id).is_empty():
				return DiplomacyCommand.new(faction_id, other, "propose_peace")
		elif s.opinion(faction_id, other) <= -40 and mine > theirs * 1.5:
			return DiplomacyCommand.new(faction_id, other, "declare_war")
	return null


func _nearest(s: GalaxyState, from: Vector2i, planets: Array[Planet]) -> Planet:
	var best: Planet = null
	var best_d := 1 << 30
	for p in planets:
		var d := s.grid.distance(from, p.cell)
		if d < best_d:
			best_d = d
			best = p
	return best
