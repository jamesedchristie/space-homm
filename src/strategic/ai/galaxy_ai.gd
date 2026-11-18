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
##   4. Otherwise head for the nearest planet it can take (unowned or an enemy's),
##      skipping planets whose defenses are too strong for it.
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
	if not engine.state.pending_event.is_empty() and engine.state.pending_event["faction"] == faction_id:
		return ResolveEventCommand.new(faction_id, choose_event_choice(engine))
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
	# (Barbarians don't: they raid in small packs.)
	if target == null and fleet.ships.size() < MUSTER_SIZE and fleet.hero_id.is_empty() \
			and s.faction(fleet.owner).get("role", "major") != "barbarian":
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

	# 4. Expand. Barbarians only raid what others hold; minor powers stay
	# close to home (within 4 systems of their capital).
	var role: String = s.faction(fleet.owner).get("role", "major")
	if target == null:
		var candidates: Array[Planet] = []
		for p: Planet in s.planets.values():
			if p.owner == fleet.owner or not (p.owner.is_empty() or s.at_war(fleet.owner, p.owner)):
				continue
			if defense_strength(engine, p) > my_strength * attack_ratio:
				continue
			if role == "barbarian" and p.owner.is_empty():
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
