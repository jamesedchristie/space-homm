class_name GalaxyAI
extends RefCounted
## Rule-based strategic AI. Plays fair: it uses the same fog-of-war queries as
## the player, so it only reacts to enemy fleets it can see.
## Each turn it first answers any galactic event (scoring each choice), then
## runs its empire (one command at a time):
##   research along a priority road (growth and economy first, then the eras,
##   then the road to the Ascension Gate); give every idle planet something to
##   build (ships when outgunned and the upkeep is affordable, megaprojects when
##   unlocked, growth/academy/exchange buildings otherwise); then diplomacy
##   (make peace with AI factions that will accept, declare war on hated weak ones).
## Then per fleet, in order:
##   1. Attack a visible fleet it is at war with and strong enough to beat.
##   2. If badly damaged, go home to the nearest friendly planet to repair;
##      a small fleet without a commander joins a friendly fleet within reach.
##   3. With a ready commander, investigate the nearest known anomaly (mission).
##   3b. Pick up a known discovery within 4 systems.
##   4. Otherwise head for the nearest enemy system it can take, skipping systems whose
##      defenses are too strong for it. Colonies need a Troop Transport: fleets pick one up first.
## Civilian ships (major powers): colony ships found the capital at once and then settle the
## best habitable world in reach; constructors develop bodies in the systems it holds and claim
## nearby empty ones as outposts; troop transports go to systems its warfleets are blockading.
## Civilian-only fleets keep away from visible warships.
## One move per fleet per turn, then it ends the turn.
##
## Personality: a campaign faction's "ai" entry can override attack_ratio,
## hunt_range, retreat_hull_ratio and war_ratio (how much stronger than a peaceful
## neighbour it must be before declaring war), e.g. cautious traders, reckless raiders.

## Attack only if our strength is at least this multiple of theirs (default).
const ATTACK_RATIO := 0.9
const RETREAT_HULL_RATIO := 0.5
## Only hunt enemy fleets this close; further away, go take planets instead.
const HUNT_RANGE := 5
## Fleets smaller than this wait at their shipyard while a ship is being built
## there, instead of trickling out one ship at a time.
const MUSTER_SIZE := 3
## Build order for economy buildings.
const BUILD_PRIORITY := ["colony", "mining_base", "gas_refinery", "research_station", "hydroponic_farm", "trade_hub",
		"defense_platform", "academy", "planetary_shield", "commerce_exchange", "orbital_habitat", "fleet_academy",
		"sensor_array", "shipyard"]
## Buildings worth buying while saving up for a megaproject (they pay for themselves).
const SAVING_OK := ["colony", "mining_base", "gas_refinery", "research_station", "hydroponic_farm", "trade_hub",
		"academy", "commerce_exchange"]
## Megaprojects in the order the AI wants them.
const MEGAPROJECT_PRIORITY := ["ascension_gate", "grand_archive", "stellar_forge", "galactic_exchange", "fleet_command_nexus"]
## Techs in the order the AI likes them; anything not listed comes after, cheapest first.
const RESEARCH_PRIORITY := ["hydroponics", "automated_mining", "trade_protocols", "deep_space_sensors", "reinforced_hulls",
		"improved_drives", "colonial_medicine", "shield_harmonics", "terraforming", "orbital_defenses", "cryogenic_labs",
		"scientific_method", "arcology_planning", "heavy_hulls", "galactic_commerce", "asteroid_refining", "logistics_corps",
		"archival_science", "orbital_habitats", "targeting_computers", "stellar_engineering", "deflector_grids",
		"fleet_doctrine", "field_repairs", "deep_core_taps", "quantum_computing", "nanofabrication", "genetic_uplift",
		"interstellar_banking", "ascension_theory", "capital_ships", "command_doctrine"]
## Researched first while a stronger enemy is at war with the AI.
const MILITARY_TECHS := ["reinforced_hulls", "shield_harmonics", "targeting_computers", "heavy_hulls", "orbital_defenses"]
## Keep this much net credit income after paying for a new ship's upkeep.
const UPKEEP_MARGIN := 2
## A rich empire (this much in stock) builds ships up to FLEET_BASE + FLEET_PER_COLONY per colony.
const RICH_CREDITS := 140
const RICH_ALLOYS := 90
const FLEET_BASE := 5
const FLEET_PER_COLONY := 2
## Opportunistic war: the AI attacks a peaceful major power this much weaker than itself.
const WAR_STRENGTH_RATIO := 2.5
const WAR_MIN_TURN := 45
## Balance of power: from CONTAIN_MIN_TURN the runaway score leader (this many times
## the AI's own score) faces war from everyone who is not allied to it.
const CONTAIN_RATIO := 2.0
const CONTAIN_MIN_TURN := 60
## A rival this close to the Ascension Gate (science progress 0..1) gets everyone's attention.
const SCIENCE_ALARM := 0.7

## Fleets of at most this many ships scout when they have nothing else to do.
const SCOUT_SIZE := 2
## They look for unexplored space within this many systems.
const EXPLORE_RANGE := 9
## Colony ships and constructors only target systems this close to a system the faction holds.
const CIVILIAN_RANGE := 7
## Unarmed fleets stay away from visible enemy warfleets this close.
const CIVILIAN_DANGER := 3
## Most constructors a faction keeps (1 + one per this many systems, at most the cap).
const CONSTRUCTORS_PER_SYSTEMS := 3
const MAX_CONSTRUCTORS := 4
## What a development is worth to the AI, per resource (research counts most).
const YIELD_WEIGHTS := {"credits": 1.0, "alloys": 1.2, "research": 1.5}

var _turn_key := ""
## fleet id -> system id a civilian fleet is heading for (so two don't pick the same one).
var _targets := {}
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
	if not engine.state.pending_event.is_empty() and engine.state.pending_event["faction"] == faction_id:
		return ResolveEventCommand.new(faction_id, choose_event_choice(engine))
	var empire_cmd := _empire_command(engine, faction_id)
	if empire_cmd != null:
		return empire_cmd
	for fleet in engine.state.fleets_of(faction_id):
		if _done.has(fleet.id) or fleet.moves_left <= 0:
			continue
		var detach := _detach_workers(engine, fleet)
		if detach != null:
			return detach
		_done[fleet.id] = true
		var dest := _civilian_destination(engine, fleet) if fleet.is_civilian_only(engine.data) \
				else choose_destination(engine, fleet)
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

	# 1b. A rival at war with us is building the Ascension Gate: everything that can goes there.
	# Even without troops, a blockade stops the build.
	if target == null and s.faction(fleet.owner).get("role", "major") == "major" and not fleet.has_workers(data):
		var best_gate := 1 << 30
		for p: Planet in s.planets.values():
			if p.owner.is_empty() or not s.at_war(fleet.owner, p.owner):
				continue
			if p.queue.get("kind", "") != "megaproject" or p.queue.get("item", "") != "ascension_gate":
				continue
			if p.blockade == fleet.owner:
				if p.cell == fleet.cell:
					return fleet.cell  # hold the blockade: the gate stays stalled while we're here
				continue
			var d := s.grid.distance(fleet.cell, p.cell)
			if d < best_gate and defense_strength(engine, p) <= my_strength * attack_ratio * 1.5:
				best_gate = d
				target = p.cell

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
	# (Barbarians don't: they raid in small packs.)
	var scouting: bool = s.faction(fleet.owner).get("role", "major") == "major" and fleet.ships.size() <= SCOUT_SIZE \
			and fleet.hero_id.is_empty() and _unexplored_target(engine, fleet, vis, my_strength, attack_ratio) != null
	if target == null and fleet.ships.size() < MUSTER_SIZE and fleet.hero_id.is_empty() and not scouting \
			and s.faction(fleet.owner).get("role", "major") != "barbarian":
		var reach := engine.reachable_for(fleet.id)
		var best_join: Fleet = null
		for other: Fleet in s.fleets_of(fleet.owner):
			if other != fleet and reach.has(other.cell) and engine.can_merge(fleet, other) and not other.has_workers(data) \
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

	# 4. Attack the nearest enemy system we can take. (Entering an empty system claims nothing now:
	# settlers do that.) Barbarians raid whatever others hold; minor powers stay close to home
	# (within 4 systems of their capital).
	var role: String = s.faction(fleet.owner).get("role", "major")
	if target == null:
		var candidates: Array[Planet] = []
		for p: Planet in s.planets.values():
			if p.owner == fleet.owner or not s.at_war(fleet.owner, p.owner):
				continue
			if defense_strength(engine, p) > my_strength * attack_ratio:
				continue
			if role == "minor":
				var capital := s.home_planet(fleet.owner)
				if capital != null and s.grid.distance(capital.cell, p.cell) > 4:
					continue
			candidates.append(p)
		# Barbarians strike within their hunting range; farther targets they leave alone.
		if role == "barbarian":
			candidates = candidates.filter(func(p: Planet) -> bool: return s.grid.distance(fleet.cell, p.cell) <= hunt_range + 2)
		var planet := _nearest(s, fleet.cell, candidates)
		if planet != null:
			target = planet.cell
			# A colony falls only to landing troops: collect a transport on the way if one is near.
			if not planet.colonies().is_empty() and not fleet.has_role(data, "transport") and planet.blockade != fleet.owner:
				var reach_t := engine.reachable_for(fleet.id)
				for other: Fleet in s.fleets_of(fleet.owner):
					if other != fleet and other.has_role(data, "transport") and reach_t.has(other.cell) and engine.can_merge(fleet, other):
						return other.cell

	# 4b. Nothing we can take alone: if an enemy system would fall to this fleet and our strongest
	# other fleet together, the weaker of the two goes to join the stronger (assaults need mass).
	if target == null and role == "major" and not fleet.has_workers(data):
		var partner: Fleet = null
		for other: Fleet in s.fleets_of(fleet.owner):
			if other == fleet or other.has_workers(data) or not engine.can_merge(fleet, other):
				continue
			if partner == null or other.strength(data) > partner.strength(data):
				partner = other
		if partner != null and my_strength <= partner.strength(data):
			var combined := my_strength + partner.strength(data)
			for p: Planet in s.planets.values():
				if p.owner.is_empty() or p.owner == fleet.owner or not s.at_war(fleet.owner, p.owner):
					continue
				if defense_strength(engine, p) <= combined * attack_ratio:
					target = partner.cell
					break

	# 5. Nothing to fight: small fleets scout the unexplored space around the empire (settlers need
	# to know where the worlds are, and finding them is how the map opens up).
	if target == null and role == "major" and fleet.ships.size() <= SCOUT_SIZE and fleet.hero_id.is_empty():
		target = _unexplored_target(engine, fleet, vis, my_strength, attack_ratio)
	if target == null:
		return fleet.cell
	var dest := _step_towards(engine, fleet, target)
	if not anomaly_key.is_empty() and dest == target:
		_tried[anomaly_key] = true
	return dest


## The nearest passable cell nobody of ours has seen yet, within EXPLORE_RANGE of the fleet and not
## next to a visible threat; null when the neighbourhood is charted.
func _unexplored_target(engine: GalaxyEngine, fleet: Fleet, vis: Dictionary, my_strength: float, attack_ratio: float) -> Variant:
	var s := engine.state
	var explored := engine.explored_cells(fleet.owner)
	var best: Variant = null
	var best_d := EXPLORE_RANGE + 1
	for c in s.grid.cells_within(fleet.cell, EXPLORE_RANGE):
		if explored.has(c) or not s.grid.is_passable(c):
			continue
		var d := s.grid.distance(fleet.cell, c)
		# Prefer frontier cells close to home, then close to the fleet.
		if d < best_d and s.fleet_at(c) == null and not _dangerous(engine, fleet, c, vis, my_strength, attack_ratio):
			best_d = d
			best = c
	return best


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
			var pressed := _outgunned(engine, faction_id)
			options.sort_custom(func(a: String, b: String) -> bool:
				var ra := RESEARCH_PRIORITY.find(a) if a in RESEARCH_PRIORITY else 999
				var rb := RESEARCH_PRIORITY.find(b) if b in RESEARCH_PRIORITY else 999
				if pressed:
					ra = MILITARY_TECHS.find(a) - 100 if a in MILITARY_TECHS else ra
					rb = MILITARY_TECHS.find(b) - 100 if b in MILITARY_TECHS else rb
				if ra != rb:
					return ra < rb
				return ResearchRules.cost(engine, a) < ResearchRules.cost(engine, b))
			return SetResearchCommand.new(faction_id, options[0])
	if s.faction(faction_id).get("role", "major") == "major":
		var civilian := _civilian_command(engine, faction_id)
		if civilian != null:
			return civilian
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


## What an idle planet should build: a megaproject when one is unlocked (and
## this is a good site), ships when outgunned by the factions we are at war
## with and the upkeep is affordable, otherwise economy buildings, otherwise more ships.
func choose_build(engine: GalaxyEngine, planet: Planet) -> Dictionary:
	var faction_id := planet.owner
	var ships: Array[Dictionary] = []
	var buildings := {}
	var megaprojects := {}
	var saving := false
	for option in EmpireRules.build_options(engine, planet):
		if option["kind"] == "megaproject":
			if option["ok"]:
				megaprojects[option["id"]] = option
			elif option["reason"] == "Can't afford it" or option["reason"] == "Already building something":
				saving = true
			continue
		if not option["ok"]:
			continue
		if option["kind"] == "unit":
			if not Fleet.is_civilian_unit(engine.data, option["id"]):
				ships.append(option)
		else:
			var keep: Dictionary = buildings.get(option["id"], {})
			if keep.is_empty() or _body_pop(planet, option["body"]) > _body_pop(planet, keep["body"]):
				if _building_sensible(engine, planet, option):
					buildings[option["id"]] = option
	ships.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return engine.data.units[a["id"]]["stats"]["max_hull"] > engine.data.units[b["id"]]["stats"]["max_hull"])
	var mine := DiplomacyRules.military_strength(engine, faction_id)
	var theirs := 0.0
	for f in engine.state.factions:
		if engine.state.at_war(faction_id, f["id"]) and not engine.state.is_eliminated(f["id"]):
			theirs = maxf(theirs, DiplomacyRules.military_strength(engine, f["id"]))
	var threatened := mine < theirs * 0.9
	# Megaprojects: the best site is one of the most populous systems.
	if not megaprojects.is_empty() and _good_megaproject_site(engine, planet):
		for mp_id in MEGAPROJECT_PRIORITY:
			if megaprojects.has(mp_id):
				return megaprojects[mp_id]
	var reserve := _megaproject_reserve(engine, faction_id)
	saving = saving or not reserve.is_empty()

	var affordable_ships: Array[Dictionary] = ships.filter(func(o: Dictionary) -> bool:
		return _can_support(engine, faction_id, o["id"], threatened))
	if not affordable_ships.is_empty() and mine < theirs * 0.9 and (not saving or threatened):
		return affordable_ships[0]
	var civilian_option := _choose_civilian_build(engine, planet, saving)
	if not civilian_option.is_empty():
		return civilian_option
	# A rich empire keeps a navy (as far as its upkeep allows) rather than hoarding.
	if not affordable_ships.is_empty() and _ship_count(engine, faction_id) < FLEET_BASE + FLEET_PER_COLONY * EmpireRules.colony_count(engine, faction_id):
		var stock: Dictionary = engine.state.resources[faction_id]
		if int(stock.get("credits", 0)) >= RICH_CREDITS + int(reserve.get("credits", 0)) \
				and int(stock.get("alloys", 0)) >= RICH_ALLOYS + int(reserve.get("alloys", 0)):
			return affordable_ships[0]
	# Without any shipyard a faction can never rebuild its fleet: fix that first.
	if buildings.has("shipyard"):
		var any_yard := false
		for p in engine.state.planets_of(faction_id):
			any_yard = any_yard or EmpireRules.has_shipyard(engine, p)
		if not any_yard:
			return buildings["shipyard"]
	for b_id in BUILD_PRIORITY:
		if buildings.has(b_id) and (not saving or b_id in SAVING_OK):
			return buildings[b_id]
	if not affordable_ships.is_empty() and mine < theirs * 1.5 and not saving:
		return affordable_ships[0]
	return {}


## Whether an enemy the faction is at war with has a navy about as strong as its own or stronger.
static func _outgunned(engine: GalaxyEngine, faction_id: String) -> bool:
	var mine := DiplomacyRules.military_strength(engine, faction_id)
	for f in engine.state.factions:
		if engine.state.at_war(faction_id, f["id"]) and not engine.state.is_eliminated(f["id"]) \
				and DiplomacyRules.military_strength(engine, f["id"]) * 1.2 > mine:
			return true
	return false


## Population of a body of the planet (0 if none).
static func _body_pop(planet: Planet, body_id: String) -> int:
	return EmpireRules.pop(planet.body(body_id)) if not body_id.is_empty() else 0


## Extra rules so the AI doesn't waste slots on buildings that do nothing for it yet.
func _building_sensible(engine: GalaxyEngine, planet: Planet, option: Dictionary) -> bool:
	var b := planet.body(option["body"])
	var faction_id := planet.owner
	match option["id"]:
		"hydroponic_farm":
			return not b.is_empty() and EmpireRules.pop(b) < EmpireRules.pop_cap(engine, b, faction_id) - 1
		"orbital_habitat":
			return not b.is_empty() and EmpireRules.pop(b) >= EmpireRules.pop_cap(engine, b, faction_id) - 1 and EmpireRules.pop(b) >= 4
		"fleet_academy":
			if EmpireRules.hero_xp_per_turn(engine, faction_id) > 0:
				return false
			for h in engine.state.heroes_of(faction_id):
				if h.is_ready() and not h.fleet_id.is_empty():
					return true
			return false
		"academy":
			return EmpireRules.pop(b) >= 2
		"commerce_exchange":
			return EmpireRules.pop(b) >= 2
		"sensor_array":
			return engine.state.turn_number > 50 and int(engine.state.resources[faction_id].get("credits", 0)) > 250
		"planetary_shield":
			return int(engine.state.resources[faction_id].get("credits", 0)) > 200
		"defense_platform":
			return engine.state.turn_number > 15
	return true


## A system worth hosting a megaproject: among the faction's most populous idle systems.
func _good_megaproject_site(engine: GalaxyEngine, planet: Planet) -> bool:
	var best := 0
	for p in engine.state.planets_of(planet.owner):
		best = maxi(best, p.population())
	return planet.population() * 10 >= best * 6


## The cost of the megaproject the faction wants next (unlocked, not built or
## started, still available), or {} if none: other spending should hold back for it.
func _megaproject_reserve(engine: GalaxyEngine, faction_id: String) -> Dictionary:
	for mp_id in MEGAPROJECT_PRIORITY:
		if not engine.data.megaprojects.has(mp_id) or not EmpireRules.megaproject_unlocked(engine, faction_id, mp_id) \
				or EmpireRules.megaproject_hidden(engine, mp_id):
			continue
		if EmpireRules.megaproject_site(engine, mp_id, faction_id) != null \
				or EmpireRules.megaproject_under_construction(engine, mp_id, faction_id) != null:
			continue
		if engine.data.megaprojects[mp_id].get("scope", "empire") == "galaxy" \
				and (EmpireRules.megaproject_site(engine, mp_id) != null or EmpireRules.megaproject_under_construction(engine, mp_id) != null):
			continue
		return engine.data.megaprojects[mp_id].get("cost", {})
	return {}


static func _ship_count(engine: GalaxyEngine, faction_id: String) -> int:
	var n := 0
	for f in engine.state.fleets_of(faction_id):
		n += f.ships.size()
	return n


## Whether the faction can pay upkeep for another ship of this class (queued ships count).
func _can_support(engine: GalaxyEngine, faction_id: String, unit_id: String, desperate: bool) -> bool:
	if engine.state.faction(faction_id).get("role", "major") != "major":
		return true
	var queued := 0
	for p in engine.state.planets_of(faction_id):
		if p.queue.get("kind", "") == "unit":
			queued += EmpireRules.ship_upkeep(engine, p.queue["item"])
	var gross_after := EmpireRules.fleet_upkeep(engine, faction_id) + queued + EmpireRules.ship_upkeep(engine, unit_id)
	var income := EmpireRules.income(engine, faction_id)
	var net_after := int(income["gross_credits"]) - EmpireRules.upkeep_for(engine, faction_id, gross_after)
	var credits := int(engine.state.resources[faction_id].get("credits", 0))
	if desperate:
		return net_after >= -2 and credits >= 40
	return net_after >= UPKEEP_MARGIN and credits >= 0


# --- Civilian ships -----------------------------------------------------------

## Colony ships, constructors and troop transports the faction owns or is building: deployed, in fleets, queued.
func _civilian_count(engine: GalaxyEngine, faction_id: String, role: String) -> int:
	var n := 0
	for f in engine.state.fleets_of(faction_id):
		for ship in f.ships:
			if Fleet.role_of(engine.data, ship["unit"]) == role:
				n += 1
	for p: Planet in engine.state.planets.values():
		for c in p.civilians:
			if c["owner"] == faction_id and Fleet.role_of(engine.data, c["unit"]) == role:
				n += 1
		if p.owner == faction_id and p.queue.get("kind", "") == "unit" and Fleet.role_of(engine.data, p.queue["item"]) == role:
			n += 1
	return n


## A civilian build for an idle system, or {}: constructors while there is work for them,
## a colony ship while there is a world to settle, a transport once we are fighting for colonies.
func _choose_civilian_build(engine: GalaxyEngine, planet: Planet, saving: bool) -> Dictionary:
	var faction_id := planet.owner
	if planet.colonies().is_empty() or planet.is_blockaded() or engine.state.faction(faction_id).get("role", "major") != "major":
		return {}
	var options := {}
	for o in EmpireRules.build_options(engine, planet):
		if o["kind"] == "unit" and o["ok"] and Fleet.is_civilian_unit(engine.data, o["id"]):
			options[Fleet.role_of(engine.data, o["id"])] = o
	if options.is_empty():
		return {}
	var turn := engine.state.turn_number
	var systems := engine.state.planets_of(faction_id).size()
	var stock: Dictionary = engine.state.resources[faction_id]
	var rich := int(stock.get("credits", 0)) >= RICH_CREDITS
	# Work for constructors: undeveloped bodies in our systems and empty systems worth an outpost.
	if options.has("constructor") and not (saving and not rich):
		var want := mini(1 + systems / CONSTRUCTORS_PER_SYSTEMS + (1 if rich else 0), MAX_CONSTRUCTORS)
		var have := _civilian_count(engine, faction_id, "constructor")
		if have < want and _development_work(engine, faction_id) > have:
			return options["constructor"]
	if options.has("colony") and _civilian_count(engine, faction_id, "colony") == 0 and not (saving and not rich):
		if not _colony_targets(engine, faction_id).is_empty() and _net_income_ok(engine, faction_id):
			return options["colony"]
	if options.has("transport") and turn >= 15 and _civilian_count(engine, faction_id, "transport") < 1 + _blockades_of(engine, faction_id):
		if _wants_troops(engine, faction_id):
			return options["transport"]
	return {}


func _net_income_ok(engine: GalaxyEngine, faction_id: String) -> bool:
	return int(EmpireRules.income(engine, faction_id)["credits"]) >= 0


func _blockades_of(engine: GalaxyEngine, faction_id: String) -> int:
	var n := 0
	for p: Planet in engine.state.planets.values():
		if p.blockade == faction_id:
			n += 1
	return n


## Whether the faction is fighting a power that holds colonies (or already blockades one): troops are worth having.
func _wants_troops(engine: GalaxyEngine, faction_id: String) -> bool:
	var s := engine.state
	for p: Planet in s.planets.values():
		if not p.owner.is_empty() and s.at_war(faction_id, p.owner) and not p.colonies().is_empty() \
				and s.faction(p.owner).get("role", "major") == "major" and s.faction(faction_id).get("role", "major") == "major":
			return true
	return false


## How many bodies could use a constructor right now (in own systems, or empty systems near them).
func _development_work(engine: GalaxyEngine, faction_id: String) -> int:
	var n := 0
	for p: Planet in _work_systems(engine, faction_id):
		n += SystemRules.development_targets(engine, p, faction_id).size()
	return n


## Own systems and the explored empty ones within CIVILIAN_RANGE of them.
func _work_systems(engine: GalaxyEngine, faction_id: String) -> Array[Planet]:
	var s := engine.state
	var own := s.planets_of(faction_id)
	var explored := engine.explored_cells(faction_id)
	var out: Array[Planet] = []
	for p: Planet in s.planets.values():
		if p.owner == faction_id or (p.owner.is_empty() and explored.has(p.cell) and _near_any(s, p.cell, own, CIVILIAN_RANGE)):
			out.append(p)
	return out


func _near_any(s: GalaxyState, cell: Vector2i, planets: Array[Planet], radius: int) -> bool:
	for q in planets:
		if s.grid.distance(cell, q.cell) <= radius:
			return true
	return false


## Systems with a habitable body a colony ship could settle: [{"planet", "body", "score"}], best first.
func _colony_targets(engine: GalaxyEngine, faction_id: String) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for p in _work_systems(engine, faction_id):
		var best := _best_colony_body(engine, p, faction_id)
		if not best.is_empty():
			out.append({"planet": p, "body": best["body"], "score": best["score"]})
	out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a["score"] > b["score"])
	return out


## The habitable body worth settling in a system: {"body", "score"} or {}.
func _best_colony_body(engine: GalaxyEngine, planet: Planet, faction_id: String) -> Dictionary:
	var best: Dictionary = {}
	for b in SystemRules.colony_targets(engine, planet, faction_id):
		var score := float(EmpireRules.pop_cap(engine, b, faction_id)) + float(EmpireRules.colony_slots(engine, b, faction_id))
		for t: String in b["traits"]:
			var def: Dictionary = engine.data.planet_traits.get(t, {})
			score += float(def.get("pop_cap", 0)) + float(def.get("slots", 0)) + 2.0 * _yield_value(def.get("yields", {}))
		score += _yield_value(engine.data.body_types.get(b["type"], {}).get("bonus", {}))
		if best.is_empty() or score > float(best["score"]):
			best = {"body": b, "score": score}
	return best


## Worth of a yield bundle; `scarcity` (resource -> multiplier) lifts what the faction is short of.
static func _yield_value(yields: Dictionary, scarcity: Dictionary = {}) -> float:
	var v := 0.0
	for k: String in yields:
		v += float(yields[k]) * float(YIELD_WEIGHTS.get(k, 1.0)) * float(scarcity.get(k, 1.0))
	return v


## Alloys are what builds ships and settlers: when credits pile up beyond them, alloys count for more.
func _scarcity(engine: GalaxyEngine, faction_id: String) -> Dictionary:
	var stock: Dictionary = engine.state.resources[faction_id]
	var out := {}
	if int(stock.get("alloys", 0)) < 120 and int(stock.get("credits", 0)) > int(stock.get("alloys", 0)) * 2:
		out["alloys"] = 2.2
	return out


## The best development a constructor could start in this system: {"body", "building", "value"} or {}.
func _best_job(engine: GalaxyEngine, planet: Planet, faction_id: String) -> Dictionary:
	var best: Dictionary = {}
	for target in SystemRules.development_targets(engine, planet, faction_id):
		var b: Dictionary = target["body"]
		for o: Dictionary in target["options"]:
			if not o["ok"]:
				continue
			var def: Dictionary = engine.data.buildings[o["id"]]
			var scarcity := _scarcity(engine, faction_id)
			var value := _yield_value(def.get("yields", {}), scarcity) + _yield_value(engine.data.body_types.get(b["type"], {}).get("bonus", {}), scarcity) \
					+ _yield_value_traits(engine, b)
			if o["id"] == "outpost":
				value = 0.5 if planet.owner.is_empty() else 0.0  # only worth it to claim an empty system
			if value <= 0.0:
				continue
			if best.is_empty() or value > float(best["value"]):
				best = {"body": b["id"], "building": o["id"], "value": value}
	return best


func _yield_value_traits(engine: GalaxyEngine, b: Dictionary) -> float:
	var v := 0.0
	for t: String in b["traits"]:
		v += _yield_value(engine.data.planet_traits.get(t, {}).get("yields", {}))
	return v


## One order for a settler or worker standing in a system, or null. Every command is checked
## with the engine first, so the AI never submits something it would reject.
func _civilian_command(engine: GalaxyEngine, faction_id: String) -> GalaxyCommand:
	var s := engine.state
	var has_colony := EmpireRules.colony_count(engine, faction_id) > 0
	for planet: Planet in s.planets.values():
		var here := SystemRules.ships_here(engine, planet, faction_id)
		if here.is_empty():
			continue
		for entry in here:
			var ship: Dictionary = entry["ship"]
			if entry["role"] == "colony":
				var best := _best_colony_body(engine, planet, faction_id)
				if best.is_empty():
					if entry["deployed"] and not _colony_targets(engine, faction_id).is_empty():
						return _checked(engine, CivilianCommand.new(faction_id, planet.id, ship["uid"], CivilianCommand.DEPART))
					continue
				# The first colony founds the capital wherever we stand; later ones settle good worlds only.
				if not has_colony or float(best["score"]) >= 9.0 or planet.owner == faction_id:
					return _checked(engine, CivilianCommand.new(faction_id, planet.id, ship["uid"], CivilianCommand.FOUND, best["body"]["id"]))
			elif entry["role"] == "constructor":
				if not ship.get("job", {}).is_empty():
					continue
				var job := _best_job(engine, planet, faction_id)
				if not job.is_empty():
					return _checked(engine, CivilianCommand.new(faction_id, planet.id, ship["uid"], CivilianCommand.JOB, job["body"], job["building"]))
				if entry["deployed"] and _development_work(engine, faction_id) > 0:
					return _checked(engine, CivilianCommand.new(faction_id, planet.id, ship["uid"], CivilianCommand.DEPART))
	return null


func _checked(engine: GalaxyEngine, cmd: GalaxyCommand) -> GalaxyCommand:
	return cmd if engine.validate(cmd).is_empty() else null


## Whether a visible enemy warfleet is close enough to `cell` to threaten unarmed ships there.
func _warships_near(engine: GalaxyEngine, faction_id: String, cell: Vector2i) -> bool:
	var vis := engine.visible_cells(faction_id)
	for other: Fleet in engine.state.fleets.values():
		if engine.state.at_war(faction_id, other.owner) and vis.has(other.cell) and not other.is_civilian_only(engine.data) \
				and engine.state.grid.distance(other.cell, cell) <= CIVILIAN_DANGER:
			return true
	return false


## The system a settler or worker should head for, or null: colony ships to the best world to
## settle, constructors to a system with work, transports to a system we blockade.
## `skip_fleet` is the fleet asking (other civilian fleets' targets are taken).
func _civilian_goal(engine: GalaxyEngine, faction_id: String, role: String, from: Vector2i, skip_fleet: String) -> Planet:
	var s := engine.state
	var taken := {}
	for id: String in _targets:
		if id != skip_fleet:
			taken[_targets[id]] = true
	var target: Planet = null
	if role == "transport":
		var blockaded: Array[Planet] = []
		for p: Planet in s.planets.values():
			if p.blockade == faction_id:
				blockaded.append(p)
		return _nearest(s, from, blockaded)
	var best := -1.0e9
	if role == "colony":
		for t in _colony_targets(engine, faction_id):
			var p: Planet = t["planet"]
			if taken.has(p.id) or _warships_near(engine, faction_id, p.cell):
				continue
			var score := float(t["score"]) - 0.8 * float(s.grid.distance(from, p.cell))
			if score > best:
				best = score
				target = p
	elif role == "constructor":
		for p in _work_systems(engine, faction_id):
			if taken.has(p.id) or _warships_near(engine, faction_id, p.cell):
				continue
			var job := _best_job(engine, p, faction_id)
			if job.is_empty():
				continue
			var score := float(job["value"]) - 1.0 * float(s.grid.distance(from, p.cell)) + (2.0 if p.owner.is_empty() else 0.0)
			if score > best:
				best = score
				target = p
	return target


## Where a civilian-only fleet goes. Anything threatened by warships falls back to the nearest system of ours.
func _civilian_destination(engine: GalaxyEngine, fleet: Fleet) -> Vector2i:
	var s := engine.state
	var data := engine.data
	for id: String in _targets.keys():
		if not s.fleets.has(id):
			_targets.erase(id)
	if s.faction(fleet.owner).get("role", "major") != "major":
		return fleet.cell
	if _warships_near(engine, fleet.owner, fleet.cell):
		var home := _nearest(s, fleet.cell, s.planets_of(fleet.owner))
		return _step_towards(engine, fleet, home.cell) if home != null else fleet.cell
	var role := "transport" if fleet.has_role(data, "transport") else ("colony" if fleet.has_role(data, "colony") else "constructor")
	var target := _civilian_goal(engine, fleet.owner, role, fleet.cell, fleet.id)
	if target == null:
		_targets.erase(fleet.id)
		return fleet.cell
	_targets[fleet.id] = target.id
	return _step_towards(engine, fleet, target.cell)


## A warfleet carrying settlers or workers (they joined it when departing a system it was
## guarding) sets them off towards their goal: they split off to a free neighbouring system.
func _detach_workers(engine: GalaxyEngine, fleet: Fleet) -> GalaxyCommand:
	var data := engine.data
	if not fleet.has_workers(data) or fleet.is_civilian_only(data) or engine.state.faction(fleet.owner).get("role", "major") != "major":
		return null
	var uids: Array[String] = []
	var role := ""
	for ship in fleet.ships:
		if Fleet.role_of(data, ship["unit"]) in ["colony", "constructor"]:
			uids.append(ship["uid"])
			role = Fleet.role_of(data, ship["unit"])
	var goal := _civilian_goal(engine, fleet.owner, role, fleet.cell, "")
	if goal == null or uids.size() >= fleet.ships.size():
		return null
	var best: Variant = null
	var best_d := engine.state.grid.distance(fleet.cell, goal.cell)
	for c in engine.split_targets(fleet.id):
		var d := engine.state.grid.distance(c, goal.cell)
		if d < best_d:
			best_d = d
			best = c
	if best == null:
		return null
	return _checked(engine, SplitFleetCommand.new(fleet.owner, fleet.id, uids, best))


# --- Events -------------------------------------------------------------------

## Index of the event choice the AI takes: the one with the best estimated value.
func choose_event_choice(engine: GalaxyEngine) -> int:
	var pending := engine.state.pending_event
	var faction_id: String = pending["faction"]
	var def: Dictionary = engine.data.events[pending["event"]]
	var offered := EventRules.choices(engine, faction_id, pending)
	var best := 0
	var best_value := -1.0e9
	for o in offered:
		if not o["ok"]:
			continue
		var c: Dictionary = def["choices"][o["index"]]
		var chance := float(c.get("chance", 1.0))
		var value := chance * _effects_value(engine, faction_id, c.get("effects", []), pending)
		if chance < 1.0:
			value += (1.0 - chance) * _effects_value(engine, faction_id, c.get("fail_effects", []), pending)
		for k: String in c.get("cost", {}):
			value -= float(c["cost"][k])
		if value > best_value:
			best_value = value
			best = o["index"]
	return best


## Rough worth of event effects to the faction, in "credits".
func _effects_value(engine: GalaxyEngine, faction_id: String, effects: Array, pending: Dictionary) -> float:
	var total := 0.0
	var income := EmpireRules.income(engine, faction_id)
	var colonies := maxi(EmpireRules.colony_count(engine, faction_id), 1)
	for fx: Dictionary in effects:
		match fx["type"]:
			"resources":
				total += float(fx.get("credits", 0)) + float(fx.get("alloys", 0))
			"research":
				total += float(fx.get("amount", 0)) * 1.2
			"pop":
				var n := float(colonies) if fx.get("target", "context") == "all" else 1.0
				total += float(fx.get("amount", 0)) * 25.0 * n
			"damage_building":
				total -= 45.0
			"free_building":
				total += 50.0
			"repair_fleets":
				total += 20.0
			"damage_fleets":
				total -= float(fx.get("amount", 0.2)) * 150.0
			"opinion":
				var weight := 1.5 if fx.get("with", "") == "minor" else (2.0 if fx.get("with", "") == "war_target" else 1.0)
				total += float(fx.get("amount", 0)) * weight
			"raiders":
				total -= 70.0 * int(fx.get("count", 1))
			"free_ship":
				total += 70.0
			"free_hero":
				total += 90.0
			"item":
				total += 30.0
			"modifier":
				var per_turn := 0.0
				for e: Dictionary in fx.get("effects", []):
					match e.get("type", ""):
						"yield":
							per_turn += (float(e.get("mul", 1.0)) - 1.0) * float(income.get(e.get("resource", ""), 0)) * 1.2
						"empire_modifier":
							match e.get("stat", ""):
								"growth":
									per_turn += float(e.get("add", 0.0)) * 10.0 * colonies
								"field_repair":
									per_turn += float(e.get("add", 0.0)) * 30.0
								_:
									per_turn += 5.0
				total += per_turn * int(fx.get("turns", 0))
	return total


func _diplomacy(engine: GalaxyEngine, faction_id: String) -> GalaxyCommand:
	var s := engine.state
	if s.faction(faction_id).get("always_hostile", false):
		return null
	var mine := DiplomacyRules.military_strength(engine, faction_id)
	var leader := VictoryRules.score_leader(engine)
	var my_score := EmpireRules.score(engine, faction_id)
	for f in s.factions:
		var other: String = f["id"]
		if other == faction_id or s.is_eliminated(other):
			continue
		var theirs := DiplomacyRules.military_strength(engine, other)
		var rival_major: bool = f.get("role", "major") == "major"
		var racing := rival_major and VictoryRules.enabled(engine, "science") \
				and VictoryRules.science_progress(engine, other) >= SCIENCE_ALARM
		var runaway: bool = rival_major and other == leader and s.turn_number >= CONTAIN_MIN_TURN \
				and float(EmpireRules.score(engine, other)) > float(my_score) * CONTAIN_RATIO
		# A peace offer waiting for us (we are AI-driven, e.g. autoplay): take it unless crushing them.
		if not DiplomacyRules.pending_offer(s, other, faction_id).is_empty():
			var take := mine < theirs * 1.5 and not racing and not runaway
			return DiplomacyCommand.new(faction_id, other, "accept_peace" if take else "refuse_peace")
		if s.at_war(faction_id, other):
			# Make peace with AI factions that would accept, unless we're crushing them
			# or they are about to win by science.
			if f["controller"] != "player" and mine < theirs * 1.5 and not racing and not runaway \
					and DiplomacyRules.peace_refusal(engine, other, faction_id).is_empty():
				return DiplomacyCommand.new(faction_id, other, "propose_peace")
			# Player-run factions can't be proposed to: offer them peace when losing or war-weary.
			if f["controller"] == "player" and not racing and not runaway \
					and DiplomacyRules.wants_to_offer_peace(engine, faction_id, other):
				return DiplomacyCommand.new(faction_id, other, "offer_peace")
		elif s.opinion(faction_id, other) <= -40 and mine > theirs * 1.5:
			return DiplomacyCommand.new(faction_id, other, "declare_war")
		elif runaway and mine > theirs * 0.6 and s.turn_number - int(s.relation(faction_id, other)["since"]) >= 10:
			return DiplomacyCommand.new(faction_id, other, "declare_war")
		elif rival_major and racing and mine > theirs * 0.5 and VictoryRules.science_progress(engine, faction_id) < SCIENCE_ALARM:
			return DiplomacyCommand.new(faction_id, other, "declare_war")
		elif rival_major and s.turn_number >= WAR_MIN_TURN and mine > theirs * personality(engine, faction_id, "war_ratio", WAR_STRENGTH_RATIO) \
				and s.turn_number - int(s.relation(faction_id, other)["since"]) >= 20:
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
