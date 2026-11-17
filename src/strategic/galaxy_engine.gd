class_name GalaxyEngine
extends RefCounted
## Strategic layer rules: factions take turns moving fleets on a hex galaxy,
## with fog of war, planet capture and battles. Same shape as BattleEngine:
## submit(command) -> CommandResult with events; queries never change state.
##
## Battles: when a move runs into an enemy fleet (or a defended enemy planet),
## the engine sets state.pending_battle and refuses further commands until the
## battle is resolved, either by playing it (pending_battle_scenario() ->
## BattleEngine -> resolve_pending_battle()) or by auto_resolve_pending_battle().
##
## Empire (step 4): each faction's turn starts with income, research and
## production (see src/empire/). Diplomacy decides who is at war: only
## factions at war fight or take each other's planets.

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
	var s := GalaxyState.new()
	engine.state = s
	s.seed_value = p_seed if p_seed != 0 else randi()
	s.rng.seed = s.seed_value
	if def.has("generate"):
		def = GalaxyGenerator.generate(p_data, def, s.seed_value)
	engine.campaign = def
	s.max_turns = int(def.get("max_turns", 200))
	s.grid = HexGrid.from_map(def.get("map", {}), p_data.galaxy_terrain)

	var team := 0
	for f: Dictionary in def.get("factions", []):
		s.factions.append({
			"id": f["id"],
			"name": f.get("name", f["id"]),
			"controller": f.get("controller", "ai"),
			"team": team,
			"always_hostile": f.get("always_hostile", false) or f.get("role", "") == "barbarian",
			## Barbarians: {"spawn_every": turns, "max_fleets": n, "fleet": [unit ids], "den_loot": {credits, alloys}}
			"barbarian": f.get("barbarian", {}),
			"ai": f.get("ai", {}),
			"species": f.get("species", ""),
			## major: plays to win; barbarian: raids, never negotiates or wins; minor: a neutral power.
			"role": f.get("role", "major"),
		})
		s.explored[f["id"]] = {}
		var stock: Dictionary = def.get("resources", {}).get(f["id"], {})
		s.resources[f["id"]] = {"credits": int(stock.get("credits", 0)), "alloys": int(stock.get("alloys", 0))}
		var known: Array[String] = []
		for tech_id: String in def.get("techs", {}).get(f["id"], []):
			known.append(tech_id)
		s.research[f["id"]] = {"current": "", "progress": 0, "known": known}
		s.opinions[f["id"]] = {}
		team += 1

	for p_def: Dictionary in def.get("planets", []):
		var p := Planet.new()
		p.id = p_def.get("id", s.make_uid("planet"))
		p.name = p_def.get("name", p.id)
		p.cell = s.grid.cell_from_layout(_layout(p_def.get("at", [0, 0])))
		p.owner = p_def.get("owner", "")
		p.sensor = int(p_def.get("sensor", DEFAULT_PLANET_SENSOR))
		p.star = p_def.get("star", SystemBuilder.random_star(p_data, s.rng))
		p.bodies = SystemBuilder.bodies_from_def(p_data, p_def, p.name, s.rng)
		p.description = p_def.get("description", "")
		s.planets[p.id] = p

	var fleet_by_name := {}
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
		fleet_by_name[fleet.name] = fleet.id

	for h_def: Dictionary in def.get("heroes", []):
		var h := Hero.new()
		h.id = h_def["id"]
		h.name = h_def.get("name", h.id)
		h.class_id = h_def["class"]
		h.owner = h_def["owner"]
		h.level = int(h_def.get("level", 1))
		h.xp = maxi(HeroProgression.xp_for_level(p_data, h.level), 0)
		for t: String in h_def.get("traits", []):
			h.traits.append(t)
		h.gear = h_def.get("gear", {}).duplicate()
		h.loyalty = int(h_def.get("loyalty", 50))
		if h_def.has("fleet"):
			h.fleet_id = fleet_by_name[h_def["fleet"]]
			s.fleets[h.fleet_id].hero_id = h.id
		else:
			h.planet_id = h_def.get("planet", "")
		s.heroes[h.id] = h
	for f in s.factions:
		var items: Array[String] = []
		for item_id: String in def.get("inventory", {}).get(f["id"], []):
			items.append(item_id)
		s.inventory[f["id"]] = items
	for a_def: Dictionary in def.get("anomalies", []):
		s.anomalies[a_def["id"]] = {"id": a_def["id"], "name": a_def.get("name", a_def["id"]),
				"cell": s.grid.cell_from_layout(_layout(a_def.get("at", [0, 0]))), "mission": a_def["mission"]}
	for d_def: Dictionary in def.get("discoveries", []):
		var d_id: String = d_def.get("id", s.make_uid("discovery"))
		s.discoveries[d_id] = {"id": d_id, "kind": d_def["kind"], "cell": s.grid.cell_from_layout(_layout(d_def.get("at", [0, 0])))}
	engine._roll_random_features(def.get("random", {}))
	s.permadeath = def.get("permadeath", false)
	for r: Dictionary in def.get("relations", []):
		var pair: Array = r["factions"]
		s.set_relation(pair[0], pair[1], r.get("status", "war"))
		DiplomacyRules.change_opinion(s, pair[0], pair[1], int(r.get("opinion", 0)))
		DiplomacyRules.change_opinion(s, pair[1], pair[0], int(r.get("opinion", 0)))
	return engine


## Seeded variety, so no two games of a campaign play the same:
##   "planet_traits": chance (0..1) that each unowned system's undeveloped bodies roll a trait
##                    (one that suits the body's category)
##   "discoveries": {"count", "kinds": [ids] (default all), "min_distance": from planets and fleets}
func _roll_random_features(random: Dictionary) -> void:
	var s := state
	var trait_ids := data.planet_traits.keys()
	trait_ids.sort()
	if not trait_ids.is_empty():
		var chance := float(random.get("planet_traits", 0.0))
		var ids := s.planets.keys()
		ids.sort()
		for id: String in ids:
			var p: Planet = s.planets[id]
			if not p.owner.is_empty():
				continue  # home systems stay fair
			for b: Dictionary in p.bodies:
				if not b["traits"].is_empty() or s.rng.randf() >= chance * 0.5:
					continue
				var category := EmpireRules.body_category(self, b)
				var fits: Array = trait_ids.filter(func(t: String) -> bool: return category in data.planet_traits[t].get("on", []))
				if not fits.is_empty():
					b["traits"].append(fits[s.rng.randi() % fits.size()])
	var spec: Dictionary = random.get("discoveries", {})
	var count := int(spec.get("count", 0))
	if count <= 0:
		return
	var kinds: Array = spec.get("kinds", data.discoveries.keys())
	kinds.sort()
	var min_d := int(spec.get("min_distance", 2))
	var free: Array[Vector2i] = []
	for c in s.grid.cells():
		if not s.grid.is_passable(c) or not s.anomaly_at(c).is_empty() or not s.discovery_at(c).is_empty():
			continue
		var clear := true
		for p: Planet in s.planets.values():
			if s.grid.distance(p.cell, c) < min_d:
				clear = false
				break
		for f: Fleet in s.fleets.values():
			if clear and s.grid.distance(f.cell, c) < min_d:
				clear = false
		if clear:
			free.append(c)
	for i in count:
		if free.is_empty() or kinds.is_empty():
			break
		var cell: Vector2i = free[s.rng.randi() % free.size()]
		# Keep finds spread out.
		free = free.filter(func(c: Vector2i) -> bool: return s.grid.distance(c, cell) >= 2)
		var d_id := s.make_uid("discovery")
		s.discoveries[d_id] = {"id": d_id, "kind": kinds[s.rng.randi() % kinds.size()], "cell": cell}


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
	elif cmd is AssignHeroCommand:
		_do_assign(cmd)
	elif cmd is UnassignHeroCommand:
		_do_unassign(cmd)
	elif cmd is EquipItemCommand:
		_do_equip(cmd)
	elif cmd is SetResearchCommand:
		state.research[cmd.faction_id]["current"] = cmd.tech_id
		emit({"type": GalaxyEvents.RESEARCH_SET, "faction": cmd.faction_id, "tech": cmd.tech_id})
	elif cmd is QueueBuildCommand:
		_do_queue(cmd)
	elif cmd is SplitFleetCommand:
		_do_split(cmd)
	elif cmd is DiplomacyCommand:
		_do_diplomacy(cmd)
	return CommandResult.success(_flush())


func validate(cmd: GalaxyCommand) -> String:
	if state.is_over:
		return "The campaign is over"
	if not state.pending_battle.is_empty():
		return "Resolve the battle first"
	if not state.pending_mission.is_empty():
		return "Decide on the mission first"
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
	elif cmd is AssignHeroCommand or cmd is UnassignHeroCommand or cmd is EquipItemCommand:
		return _validate_hero_command(cmd)
	elif cmd is SetResearchCommand:
		if not data.techs.has(cmd.tech_id):
			return "Unknown technology"
		if ResearchRules.status(self, cmd.faction_id, cmd.tech_id) != ResearchRules.AVAILABLE:
			return "Can't research that yet"
	elif cmd is QueueBuildCommand:
		var planet: Planet = state.planets.get(cmd.planet_id)
		if planet == null or planet.owner != cmd.faction_id:
			return "Not your planet"
		var refusal := "Can't build that here"
		for option in EmpireRules.build_options(self, planet):
			if option["kind"] == cmd.kind and option["id"] == cmd.item_id \
					and (cmd.kind != "building" or cmd.body_id.is_empty() or option["body"] == cmd.body_id):
				if option["ok"]:
					return ""
				# No body named: any body that fits will do, so report the first reason only if none does.
				if refusal == "Can't build that here":
					refusal = option["reason"]
		return refusal
	elif cmd is DiplomacyCommand:
		return _validate_diplomacy(cmd)
	elif cmd is SplitFleetCommand:
		var fleet: Fleet = state.fleets.get(cmd.fleet_id)
		if fleet == null or fleet.owner != cmd.faction_id:
			return "Not your fleet"
		if cmd.ship_uids.is_empty():
			return "Pick ships to detach"
		if cmd.ship_uids.size() >= fleet.ships.size():
			return "At least one ship must stay"
		for uid in cmd.ship_uids:
			if fleet.ships.filter(func(s: Dictionary) -> bool: return s["uid"] == uid).is_empty():
				return "That ship isn't in this fleet"
		if cmd.to not in split_targets(fleet.id):
			return "Detached ships need a free neighbouring system they can reach this turn"
	elif not cmd is EndFactionTurnCommand:
		return "Unknown command"
	return ""


func _validate_hero_command(cmd: GalaxyCommand) -> String:
	var hero: Hero = state.heroes.get(cmd.hero_id)
	if hero == null or hero.owner != cmd.faction_id:
		return "Not your hero"
	if not hero.can_be_managed():
		return "%s is unavailable" % hero.name
	if cmd is AssignHeroCommand:
		var fleet: Fleet = state.fleets.get(cmd.fleet_id)
		if fleet == null or fleet.owner != cmd.faction_id:
			return "Not your fleet"
		if not hero.fleet_id.is_empty():
			return "%s already commands a fleet" % hero.name
		if not fleet.hero_id.is_empty():
			return "%s already has a commander" % fleet.name
		var planet: Planet = state.planets.get(hero.planet_id)
		if planet == null or planet.cell != fleet.cell:
			return "The fleet must be at %s's planet to pick them up" % hero.name
	elif cmd is UnassignHeroCommand:
		var fleet: Fleet = state.fleets.get(hero.fleet_id)
		if fleet == null:
			return "%s has no fleet" % hero.name
		var planet := state.planet_at(fleet.cell)
		if planet == null or planet.owner != cmd.faction_id:
			return "The fleet must be at one of your planets"
	elif cmd is EquipItemCommand:
		if cmd.slot not in DataRegistry.ITEM_SLOTS:
			return "Unknown slot"
		if not cmd.item_id.is_empty():
			if cmd.item_id not in state.inventory.get(cmd.faction_id, []):
				return "Item not in inventory"
			if data.items.get(cmd.item_id, {}).get("slot", "") != cmd.slot:
				return "That item doesn't go in that slot"
		elif not hero.gear.has(cmd.slot):
			return "Nothing to unequip"
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
	var bonus := int(EmpireRules.modifier(self, faction_id, "sensor"))
	for f in state.fleets_of(faction_id):
		for c in state.grid.cells_within(f.cell, f.sensor(data) + bonus):
			vis[c] = true
	for p in state.planets_of(faction_id):
		for c in state.grid.cells_within(p.cell, p.sensor + bonus):
			vis[c] = true
	return vis


## Moves per turn: slowest ship, plus tech bonuses.
func fleet_speed(fleet: Fleet) -> int:
	return fleet.speed(data) + int(EmpireRules.modifier(self, fleet.owner, "fleet_speed"))


func fleet_sensor(fleet: Fleet) -> int:
	return fleet.sensor(data) + int(EmpireRules.modifier(self, fleet.owner, "sensor"))


## A planet that will fight `faction_id` if entered: owned by someone at war
## with them, with defense buildings and no fleet of theirs on it.
func is_defended_against(planet: Planet, faction_id: String) -> bool:
	return planet != null and state.at_war(faction_id, planet.owner) \
			and not EmpireRules.defense_units(self, planet).is_empty() and state.fleet_at(planet.cell) == null


func explored_cells(faction_id: String) -> Dictionary:
	return state.explored.get(faction_id, {})


func can_see_fleet(faction_id: String, fleet: Fleet, visible: Dictionary = {}) -> bool:
	if fleet.owner == faction_id:
		return true
	if visible.is_empty():
		visible = visible_cells(faction_id)
	return visible.has(fleet.cell)


## Where the fleet can go this turn, using only what its owner knows: own and
## friendly (at peace) fleets block; visible enemy fleets and defended enemy
## planets can be attacked but not passed; hidden enemies are unknown (and
## will intercept the move). Returns {cell: {"cost", "from"}}.
## Whether `fleet` may fly into `other` and join it: same owner, room for
## every ship, and at most one commander between them.
func can_merge(fleet: Fleet, other: Fleet) -> bool:
	return fleet != other and fleet.owner == other.owner \
			and fleet.ships.size() + other.ships.size() <= EmpireRules.MAX_FLEET_SIZE \
			and (fleet.hero_id.is_empty() or other.hero_id.is_empty())


## Free systems next to the fleet that detached ships could move to now.
func split_targets(fleet_id: String) -> Array[Vector2i]:
	var fleet: Fleet = state.fleets[fleet_id]
	var out: Array[Vector2i] = []
	if fleet.ships.size() < 2:
		return out
	for c in state.grid.neighbors(fleet.cell):
		if state.grid.is_passable(c) and state.fleet_at(c) == null and state.grid.move_cost(c) <= fleet.moves_left \
				and not is_defended_against(state.planet_at(c), fleet.owner):
			var planet := state.planet_at(c)
			if planet == null or planet.owner.is_empty() or planet.owner == fleet.owner:
				out.append(c)
	return out


func reachable_for(fleet_id: String) -> Dictionary:
	var fleet: Fleet = state.fleets[fleet_id]
	var vis := visible_cells(fleet.owner)
	return Pathfinding.reachable(state.grid, fleet.cell, fleet.moves_left,
		func(c: Vector2i) -> bool:
			var other := state.fleet_at(c)
			if other == null or other == fleet:
				return false
			if other.owner == fleet.owner:
				return not can_merge(fleet, other)
			return vis.has(c) and not state.at_war(fleet.owner, other.owner),
		func(c: Vector2i) -> bool:
			var other := state.fleet_at(c)
			if other != null and other != fleet and other.owner == fleet.owner:
				return true  # merging ends the move
			if other != null and vis.has(c) and state.at_war(fleet.owner, other.owner):
				return true
			return is_defended_against(state.planet_at(c), fleet.owner))


## Reachable cells holding a visible enemy fleet.
func attack_targets(fleet_id: String, reach: Dictionary = {}) -> Array[Vector2i]:
	var fleet: Fleet = state.fleets[fleet_id]
	if reach.is_empty():
		reach = reachable_for(fleet_id)
	var vis := visible_cells(fleet.owner)
	var out: Array[Vector2i] = []
	for c: Vector2i in reach:
		var other := state.fleet_at(c)
		if other != null and vis.has(c) and state.at_war(fleet.owner, other.owner):
			out.append(c)
		elif other == null and is_defended_against(state.planet_at(c), fleet.owner):
			out.append(c)
	return out


func has_pending_battle() -> bool:
	return not state.pending_battle.is_empty()


## Tactical map for a battle at `cell`: planet type, then terrain, then default.
func battle_map_for(cell: Vector2i) -> String:
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
	var attacker: Fleet = state.fleets[b["attacker"]]
	var defender: Fleet = state.fleets.get(b.get("defender", ""))
	var planet := state.planet_at(cell)
	var defending_faction: String = defender.owner if defender != null else planet.owner
	var defended_planet: Planet = planet if planet != null and planet.owner == defending_faction else null
	var teams: Array = [
		_battle_side(attacker, attacker.owner, deployment.get("west", []), null),
		_battle_side(defender, defending_faction, deployment.get("east", []), defended_planet),
	]
	return {
		"id": "galaxy_battle",
		"name": "Battle %s" % location_phrase(cell),
		"map": map_id,
		"max_rounds": int(campaign.get("battle_max_rounds", 30)),
		"teams": teams,
		"objectives": [{"type": "eliminate_all", "description": "Destroy the enemy fleet"}],
	}


## One side of a fleet battle: the fleet's ships (if any) plus, for the
## defender, the planet's defense platforms. Every unit starts with the
## faction's tech statuses and the commander's doctrine.
func _battle_side(fleet: Fleet, faction_id: String, slots: Array, planet: Planet) -> Dictionary:
	var faction := state.faction(faction_id)
	var status_ids := EmpireRules.ship_statuses(self, faction_id)
	var commander := state.active_commander(fleet) if fleet != null else null
	if commander != null:
		status_ids.append(HeroBuilder.command_status(commander, data))
	var statuses: Array = []
	for st in status_ids:
		statuses.append({"status": st, "duration": 1})
	var units: Array = []
	if fleet != null:
		for ship in fleet.ships:
			if units.size() >= slots.size():
				break
			units.append({"unit": ship["unit"], "name": ship["name"], "at": slots[units.size()],
					"hull": ship["hull"], "ref": ship["uid"], "statuses": statuses})
	var names := PackedStringArray()
	if fleet != null:
		names.append(fleet.name if commander == null else "%s (%s)" % [fleet.name, commander.name])
	if planet != null:
		var defenses := EmpireRules.defense_units(self, planet)
		for i in defenses.size():
			if units.size() >= slots.size():
				break
			units.append({"unit": defenses[i], "name": "%s Platform" % planet.name, "at": slots[units.size()],
					"ref": "platform:%s:%d" % [planet.id, i], "statuses": statuses})
		if not defenses.is_empty():
			names.append("%s defenses" % planet.name)
	return {"team": faction["team"], "name": " + ".join(names), "controller": faction["controller"], "units": units,
			"species": faction.get("species", "")}


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
	var fleet_ids: Array[String] = [b["attacker"]]
	if not b.get("defender", "").is_empty():
		fleet_ids.append(b["defender"])
	for fleet_id in fleet_ids:
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

	# Destroyed defense platforms are gone from the planet.
	var planet := state.planet_at(b["cell"])
	var platforms_lost := 0
	if planet != null:
		for u: BattleUnit in battle.state.units.values():
			if u.ref.begins_with("platform:%s:" % planet.id) and not u.alive:
				platforms_lost += 1
		for i in platforms_lost:
			for building_id in planet.buildings:
				if not data.buildings[building_id].get("defense_unit", "").is_empty():
					planet.remove_building(building_id)
					break

	var winner := ""
	if battle.state.winner >= 0:
		winner = state.faction_for_team(battle.state.winner).get("id", "")
	var attacker: Fleet = state.fleets[b["attacker"]]
	var defender_name: String = state.fleets[b["defender"]].name if fleet_ids.size() > 1 else "%s defenses" % planet.name
	emit({"type": GalaxyEvents.BATTLE_RESOLVED, "attacker": b["attacker"], "defender": b.get("defender", ""),
			"attacker_name": attacker.name, "defender_name": defender_name, "platforms_lost": platforms_lost,
			"cell": b["cell"], "winner": winner, "losses": losses, "rounds": battle.state.round_number})
	var battle_xp: Dictionary = data.progression.get("battle_xp", {})
	for fleet_id in fleet_ids:
		var fleet: Fleet = state.fleets[fleet_id]
		var commander := state.active_commander(fleet)
		if commander != null:
			_grant_xp(commander, int(battle_xp.get("win" if winner == fleet.owner else "loss", 0)))
		if fleet.ships.is_empty():
			var hero := state.commander_of(fleet)
			if hero != null:
				# Escape pod: the commander makes it home, hurt.
				hero.fleet_id = ""
				var home := state.home_planet(hero.owner)
				hero.planet_id = home.id if home != null else ""
				_injure(hero)
			state.fleets.erase(fleet_id)
			emit({"type": GalaxyEvents.FLEET_DESTROYED, "fleet": fleet_id, "owner": fleet.owner, "name": fleet.name})
	# Storming a defended planet: if the attacker won and nothing defends it
	# any more, the attacker moves in and takes it.
	if b.has("planet") and winner == attacker.owner and state.fleets.has(attacker.id) \
			and state.fleet_at(planet.cell) == null and EmpireRules.defense_units(self, planet).is_empty():
		emit({"type": GalaxyEvents.FLEET_MOVED, "fleet": attacker.id, "path": [attacker.cell, planet.cell] as Array[Vector2i],
				"moves_left": 0})
		attacker.cell = planet.cell
		_capture_planet(planet, attacker)
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
# Missions
# =============================================================================

func has_pending_mission() -> bool:
	return not state.pending_mission.is_empty()


## Heroes from this fleet who would join an away team: its commander, if ready.
func mission_heroes(fleet: Fleet) -> Array[Hero]:
	var out: Array[Hero] = []
	var commander := state.active_commander(fleet)
	if commander != null:
		out.append(commander)
	return out


func pending_mission_def() -> Dictionary:
	var anomaly: Dictionary = state.anomalies[state.pending_mission["anomaly"]]
	return data.missions[anomaly["mission"]]


func pending_mission_fleet() -> Fleet:
	return state.fleets[state.pending_mission["fleet"]]


## Tactical scenario for the pending mission (away team vs the mission's hostiles).
func pending_mission_scenario() -> Dictionary:
	var fleet := pending_mission_fleet()
	var mission := pending_mission_def()
	var faction := state.faction(fleet.owner)
	var squad := MissionFactory.squad_for(data, mission, mission_heroes(fleet), faction.get("species", ""))
	var scenario := MissionFactory.scenario(data, mission, squad, faction["team"],
			"%s away team" % fleet.name, faction["controller"])
	scenario["teams"][0]["species"] = faction.get("species", "")
	return scenario


func decline_pending_mission() -> Array[Dictionary]:
	emit({"type": GalaxyEvents.MISSION_DECLINED, "anomaly": state.pending_mission["anomaly"],
			"fleet": state.pending_mission["fleet"]})
	state.pending_mission = {}
	return _flush()


func auto_resolve_pending_mission() -> Array[Dictionary]:
	var battle := BattleEngine.from_scenario(data, pending_mission_scenario(), next_battle_seed())
	AutoResolver.resolve(battle)
	return resolve_pending_mission(battle)


## Applies a finished mission battle: XP and level-ups, items, loyalty and
## traits from choices, injuries/captures/deaths. Success clears the anomaly;
## failure with captured heroes turns it into the follow-up rescue mission.
func resolve_pending_mission(battle: BattleEngine) -> Array[Dictionary]:
	var pm := state.pending_mission
	var anomaly: Dictionary = state.anomalies[pm["anomaly"]]
	var fleet: Fleet = state.fleets[pm["fleet"]]
	var mission: Dictionary = data.missions[anomaly["mission"]]
	var faction_id := fleet.owner
	var success: bool = battle.state.winner == state.faction(faction_id)["team"]

	var xp := 0
	var loyalty := 0
	var items: Array[String] = []
	var new_traits: Array[String] = []
	var rewards: Array[Dictionary] = battle.state.rewards.duplicate()
	var loot_text := ""
	if success:
		rewards.append(mission.get("rewards", {}))
		# Random bonus loot on success (a weighted table, rolled from the campaign seed).
		if not mission.get("loot", []).is_empty():
			var roll := BattleEngine.roll_weighted(mission["loot"], state.rng)
			rewards.append(roll.get("rewards", {}))
			loot_text = roll.get("text", "")
	var gains := {"credits": 0, "alloys": 0, "research": 0, "intel": 0}
	for r in rewards:
		for k: String in gains:
			gains[k] += int(r.get(k, 0))
		xp += int(r.get("xp", 0))
		loyalty += int(r.get("loyalty", 0))
		for item_id: String in r.get("items", []):
			items.append(item_id)
		if r.has("trait") and r["trait"] not in new_traits:
			new_traits.append(r["trait"])

	var outcomes := {}
	var injury_turns := int(data.progression.get("injury_turns", 3))
	for u: BattleUnit in battle.state.units.values():
		if not u.ref.begins_with("hero:"):
			continue
		var hero: Hero = state.heroes[u.ref.trim_prefix("hero:")]
		hero.loyalty = clampi(hero.loyalty + loyalty, 0, 100)
		for t in new_traits:
			if t not in hero.traits:
				hero.traits.append(t)
		if u.alive:
			hero.status = Hero.ON_MISSION
			hero.busy_until = state.turn_number + int(mission.get("duration", 2))
			outcomes[hero.id] = "returned"
		elif state.permadeath:
			_kill(hero)
			outcomes[hero.id] = "killed"
		elif success:
			hero.status = Hero.INJURED
			hero.busy_until = state.turn_number + injury_turns
			outcomes[hero.id] = "injured"
		else:
			_capture(hero)
			outcomes[hero.id] = "captured"
		if hero.status != Hero.DEAD:
			_grant_xp(hero, xp)

	for item_id in items:
		state.inventory[faction_id].append(item_id)
	var stock: Dictionary = state.resources[faction_id]
	stock["credits"] = int(stock["credits"]) + gains["credits"]
	stock["alloys"] = int(stock["alloys"]) + gains["alloys"]
	state.research[faction_id]["progress"] = int(state.research[faction_id]["progress"]) + gains["research"]
	var revealed := _reveal_enemy_planets(faction_id, gains["intel"])
	fleet.moves_left = 0

	emit({"type": GalaxyEvents.MISSION_RESOLVED, "anomaly": anomaly["id"], "mission": mission["id"],
			"fleet": fleet.id, "success": success, "heroes": outcomes, "xp": xp, "items": items,
			"loyalty": loyalty, "traits": new_traits, "credits": gains["credits"], "alloys": gains["alloys"],
			"research": gains["research"], "intel": revealed, "loot_text": loot_text})

	if success:
		if mission.get("rewards", {}).get("free_captives", false):
			for h in state.heroes_of(faction_id):
				if h.status == Hero.CAPTURED:
					var home := state.home_planet(faction_id)
					h.planet_id = home.id if home != null else ""
					h.status = Hero.INJURED
					h.busy_until = state.turn_number + injury_turns
					emit({"type": GalaxyEvents.HERO_FREED, "hero": h.id})
		state.anomalies.erase(anomaly["id"])
		emit({"type": GalaxyEvents.ANOMALY_REMOVED, "anomaly": anomaly["id"]})
	elif "captured" in outcomes.values() and mission.has("on_failure"):
		anomaly["mission"] = mission["on_failure"]["mission"]
		anomaly["name"] = mission["on_failure"].get("name", anomaly["name"])
		# Only the faction whose heroes are held there can mount the rescue.
		anomaly["faction"] = faction_id
		emit({"type": GalaxyEvents.ANOMALY_CHANGED, "anomaly": anomaly["id"], "mission": anomaly["mission"],
				"name": anomaly["name"]})
	state.pending_mission = {}
	return _flush()


# =============================================================================
# Mutation helpers
# =============================================================================

func _grant_xp(hero: Hero, amount: int) -> void:
	for level in HeroProgression.add_xp(hero, amount, data):
		emit({"type": GalaxyEvents.HERO_LEVELED, "hero": hero.id, "level": level,
				"skills": HeroProgression.skills_unlocked_at(hero, level, data)})


func _injure(hero: Hero) -> void:
	if hero.status == Hero.DEAD or hero.status == Hero.CAPTURED:
		return
	hero.status = Hero.INJURED
	hero.busy_until = state.turn_number + int(data.progression.get("injury_turns", 3))
	emit({"type": GalaxyEvents.HERO_INJURED, "hero": hero.id, "until": hero.busy_until})


func _release_command(hero: Hero) -> void:
	var fleet: Fleet = state.fleets.get(hero.fleet_id)
	if fleet != null and fleet.hero_id == hero.id:
		fleet.hero_id = ""
	hero.fleet_id = ""


func _capture(hero: Hero) -> void:
	_release_command(hero)
	hero.status = Hero.CAPTURED
	emit({"type": GalaxyEvents.HERO_CAPTURED, "hero": hero.id})


func _kill(hero: Hero) -> void:
	_release_command(hero)
	hero.status = Hero.DEAD
	emit({"type": GalaxyEvents.HERO_KILLED, "hero": hero.id})


func _do_assign(cmd: AssignHeroCommand) -> void:
	var hero: Hero = state.heroes[cmd.hero_id]
	var fleet: Fleet = state.fleets[cmd.fleet_id]
	hero.fleet_id = fleet.id
	hero.planet_id = ""
	fleet.hero_id = hero.id
	emit({"type": GalaxyEvents.HERO_ASSIGNED, "hero": hero.id, "fleet": fleet.id})


func _do_unassign(cmd: UnassignHeroCommand) -> void:
	var hero: Hero = state.heroes[cmd.hero_id]
	var planet := state.planet_at(state.fleets[hero.fleet_id].cell)
	_release_command(hero)
	hero.planet_id = planet.id
	emit({"type": GalaxyEvents.HERO_UNASSIGNED, "hero": hero.id, "planet": planet.id})


func _do_equip(cmd: EquipItemCommand) -> void:
	var hero: Hero = state.heroes[cmd.hero_id]
	var inv: Array = state.inventory[cmd.faction_id]
	var previous: String = hero.gear.get(cmd.slot, "")
	if not previous.is_empty():
		inv.append(previous)
	if cmd.item_id.is_empty():
		hero.gear.erase(cmd.slot)
	else:
		inv.erase(cmd.item_id)
		hero.gear[cmd.slot] = cmd.item_id
	emit({"type": GalaxyEvents.ITEM_EQUIPPED, "hero": hero.id, "slot": cmd.slot, "item": cmd.item_id,
			"previous": previous})

func emit(event: Dictionary) -> void:
	_events.append(event)


func _do_move(cmd: MoveFleetCommand) -> void:
	var fleet: Fleet = state.fleets[cmd.fleet_id]
	var reach := reachable_for(fleet.id)
	var planned := Pathfinding.path_to(reach, cmd.to)
	var walked: Array[Vector2i] = [fleet.cell]
	var enemy: Fleet = null
	var defended: Planet = null
	var ambush := false
	for i in range(1, planned.size()):
		var next := planned[i]
		var occupant := state.fleet_at(next)
		if occupant != null and occupant.owner == fleet.owner and next == cmd.to and can_merge(fleet, occupant):
			fleet.moves_left -= state.grid.move_cost(next)
			walked.append(next)
			emit({"type": GalaxyEvents.FLEET_MOVED, "fleet": fleet.id, "path": walked, "moves_left": fleet.moves_left})
			_merge(fleet, occupant)
			return
		if occupant != null and occupant.owner != fleet.owner:
			if state.at_war(fleet.owner, occupant.owner):
				enemy = occupant
				ambush = next != cmd.to
			break  # a fleet we're at peace with blocks the way
		if occupant != null and occupant != fleet:
			break  # own fleet that can no longer be joined (e.g. a find filled the fleet): stop short
		if is_defended_against(state.planet_at(next), fleet.owner):
			defended = state.planet_at(next)
			break
		fleet.moves_left -= state.grid.move_cost(next)
		fleet.cell = next
		walked.append(next)
		_reveal_around(fleet)
		var find := state.discovery_at(next)
		if not find.is_empty():
			# Report the move so far first, so the find happens where the fleet is.
			emit({"type": GalaxyEvents.FLEET_MOVED, "fleet": fleet.id, "path": walked.duplicate(), "moves_left": fleet.moves_left})
			walked = [next]
			_claim_discovery(fleet, find)
	if walked.size() > 1:
		emit({"type": GalaxyEvents.FLEET_MOVED, "fleet": fleet.id, "path": walked, "moves_left": fleet.moves_left})

	if enemy != null:
		fleet.moves_left = 0
		state.pending_battle = {"attacker": fleet.id, "defender": enemy.id, "cell": enemy.cell, "ambush": ambush}
		DiplomacyRules.change_opinion(state, enemy.owner, fleet.owner, DiplomacyRules.ATTACKED_OPINION)
		emit({"type": GalaxyEvents.BATTLE_TRIGGERED, "attacker": fleet.id, "defender": enemy.id,
				"cell": enemy.cell, "ambush": ambush})
		return
	if defended != null:
		fleet.moves_left = 0
		state.pending_battle = {"attacker": fleet.id, "defender": "", "planet": defended.id,
				"cell": defended.cell, "ambush": false}
		DiplomacyRules.change_opinion(state, defended.owner, fleet.owner, DiplomacyRules.ATTACKED_OPINION)
		emit({"type": GalaxyEvents.BATTLE_TRIGGERED, "attacker": fleet.id, "defender": "", "planet": defended.id,
				"cell": defended.cell, "ambush": false})
		return

	var planet := state.planet_at(fleet.cell)
	if planet != null and planet.owner != fleet.owner and (planet.owner.is_empty() or state.at_war(fleet.owner, planet.owner)):
		_capture_planet(planet, fleet)

	# Ending a move on an anomaly offers its mission (if the fleet can field an away team).
	var anomaly := state.anomaly_at(fleet.cell)
	if not anomaly.is_empty() and fleet.cell == cmd.to and not state.is_over \
			and anomaly.get("faction", "") in ["", fleet.owner]:
		var mission: Dictionary = data.missions[anomaly["mission"]]
		if not mission_heroes(fleet).is_empty() or not mission.get("requires_hero", true):
			state.pending_mission = {"anomaly": anomaly["id"], "fleet": fleet.id}
			emit({"type": GalaxyEvents.MISSION_OFFERED, "anomaly": anomaly["id"], "fleet": fleet.id,
					"mission": anomaly["mission"]})


## `fleet` joins `into` (which keeps its name and position) and disappears.
func _merge(fleet: Fleet, into: Fleet) -> void:
	into.ships.append_array(fleet.ships)
	into.moves_left = mini(into.moves_left, fleet.moves_left)
	if into.hero_id.is_empty() and not fleet.hero_id.is_empty():
		into.hero_id = fleet.hero_id
		state.heroes[fleet.hero_id].fleet_id = into.id
	state.fleets.erase(fleet.id)
	emit({"type": GalaxyEvents.FLEETS_MERGED, "fleet": fleet.id, "into": into.id, "name": fleet.name,
			"into_name": into.name})


## Intel: charts the surroundings of up to `count` enemy planets the faction
## hasn't explored yet (nearest first). Returns the planet names.
func _reveal_enemy_planets(faction_id: String, count: int) -> Array[String]:
	var names: Array[String] = []
	if count <= 0:
		return names
	var explored: Dictionary = state.explored[faction_id]
	var home := state.home_planet(faction_id)
	var targets: Array[Planet] = []
	for p: Planet in state.planets.values():
		if not p.owner.is_empty() and p.owner != faction_id and not explored.has(p.cell):
			targets.append(p)
	if home != null:
		targets.sort_custom(func(a: Planet, b: Planet) -> bool:
			return state.grid.distance(home.cell, a.cell) < state.grid.distance(home.cell, b.cell))
	for p in targets.slice(0, count):
		for c in state.grid.cells_within(p.cell, 2):
			explored[c] = true
		names.append(p.name)
	return names


## The first fleet into a discovery rolls on its outcome table and gets the rewards:
## credits, alloys, research (progress on the current project), ship (joins the
## fleet if there's room, else becomes alloys), item, intel (reveals a radius),
## xp (commander), damage (fraction of every ship's hull).
func _claim_discovery(fleet: Fleet, find: Dictionary) -> void:
	state.discoveries.erase(find["id"])
	var def: Dictionary = data.discoveries.get(find["kind"], {})
	var outcomes: Array = def.get("outcomes", [])
	var total := 0
	for o: Dictionary in outcomes:
		total += int(o.get("weight", 1))
	var roll := state.rng.randi_range(1, maxi(total, 1))
	var outcome: Dictionary = outcomes[0] if not outcomes.is_empty() else {}
	for o: Dictionary in outcomes:
		roll -= int(o.get("weight", 1))
		if roll <= 0:
			outcome = o
			break
	var rewards: Dictionary = outcome.get("rewards", {}).duplicate()
	var faction := fleet.owner
	var stock: Dictionary = state.resources[faction]
	for k in ["credits", "alloys"]:
		if rewards.has(k):
			stock[k] = int(stock[k]) + int(rewards[k])
	if rewards.has("research"):
		var r: Dictionary = state.research[faction]
		r["progress"] = int(r["progress"]) + int(rewards["research"])
	if rewards.has("ship"):
		var unit_def: Dictionary = data.units[rewards["ship"]]
		if fleet.ships.size() < EmpireRules.MAX_FLEET_SIZE:
			fleet.ships.append({"uid": state.make_uid("ship"), "unit": rewards["ship"],
					"name": "%s %d" % [unit_def.get("name", rewards["ship"]), state.next_uid],
					"hull": int(unit_def["stats"]["max_hull"])})
		else:
			rewards.erase("ship")
			rewards["alloys"] = int(rewards.get("alloys", 0)) + 40
			stock["alloys"] = int(stock["alloys"]) + 40
	if rewards.has("item"):
		state.inventory[faction].append(rewards["item"])
	if rewards.has("intel"):
		var explored: Dictionary = state.explored[faction]
		for c in state.grid.cells_within(find["cell"], int(rewards["intel"])):
			explored[c] = true
	if rewards.has("xp"):
		var commander := state.commander_of(fleet)
		if commander != null:
			_grant_xp(commander, int(rewards["xp"]))
		else:
			rewards.erase("xp")
	if rewards.has("damage"):
		for ship in fleet.ships:
			ship["hull"] = maxi(1, int(ship["hull"]) - ceili(int(ship["hull"]) * float(rewards["damage"])))
	emit({"type": GalaxyEvents.DISCOVERY_FOUND, "discovery": find["id"], "kind": find["kind"],
			"name": def.get("name", find["kind"]), "fleet": fleet.id, "faction": faction,
			"text": outcome.get("text", ""), "rewards": rewards})


func _do_split(cmd: SplitFleetCommand) -> void:
	var fleet: Fleet = state.fleets[cmd.fleet_id]
	var detached := Fleet.new()
	detached.id = state.make_uid("fleet")
	detached.owner = fleet.owner
	detached.cell = cmd.to
	detached.name = "Detachment %d" % state.next_uid
	detached.moves_left = fleet.moves_left - state.grid.move_cost(cmd.to)
	var names: Array[String] = []
	for ship in fleet.ships.duplicate():
		if ship["uid"] in cmd.ship_uids:
			fleet.ships.erase(ship)
			detached.ships.append(ship)
			names.append(ship["name"])
	state.fleets[detached.id] = detached
	emit({"type": GalaxyEvents.FLEET_SPLIT, "fleet": fleet.id, "new_fleet": detached.id, "ships": names})
	emit({"type": GalaxyEvents.FLEET_MOVED, "fleet": detached.id, "path": [fleet.cell, cmd.to] as Array[Vector2i],
			"moves_left": detached.moves_left})
	_reveal_around(detached)
	var find := state.discovery_at(detached.cell)
	if not find.is_empty():
		_claim_discovery(detached, find)
	var planet := state.planet_at(detached.cell)
	if planet != null and planet.owner.is_empty():
		_capture_planet(planet, detached)


func _capture_planet(planet: Planet, fleet: Fleet) -> void:
	var previous := planet.owner
	if state.faction(fleet.owner).get("role", "") == "barbarian":
		_plunder(planet, fleet)
		return
	var loot: Dictionary = state.faction(previous).get("barbarian", {}).get("den_loot", {}) if not previous.is_empty() else {}
	if not loot.is_empty():
		var stock: Dictionary = state.resources[fleet.owner]
		for k in ["credits", "alloys"]:
			stock[k] = int(stock.get(k, 0)) + int(loot.get(k, 0))
		emit({"type": GalaxyEvents.DEN_CLEARED, "planet": planet.id, "faction": fleet.owner, "loot": loot})
	planet.owner = fleet.owner
	planet.queue = {}
	_evacuate_heroes(planet, previous)
	DiplomacyRules.change_opinion(state, previous, fleet.owner, DiplomacyRules.PLANET_TAKEN_OPINION)
	emit({"type": GalaxyEvents.PLANET_CAPTURED, "planet": planet.id, "faction": fleet.owner,
			"previous_owner": previous, "fleet": fleet.id})
	_update_explored()
	_check_eliminations()


## Heroes waiting at a system its owner just lost fall back to the owner's
## first remaining planet (with none left they stay put, ready for a recapture).
func _evacuate_heroes(planet: Planet, previous: String) -> void:
	var home := state.home_planet(previous) if not previous.is_empty() else null
	if home == null:
		return
	for h in state.heroes_of(previous):
		if h.planet_id == planet.id:
			h.planet_id = home.id


func _begin_faction_turn() -> void:
	var faction_id := current_faction_id()
	_run_economy(faction_id)
	_barbarian_spawns(faction_id)
	for h in state.heroes_of(faction_id):
		if (h.status == Hero.ON_MISSION or h.status == Hero.INJURED) and state.turn_number >= h.busy_until:
			h.status = Hero.READY
			emit({"type": GalaxyEvents.HERO_RETURNED, "hero": h.id})
	var field_repair := EmpireRules.modifier(self, faction_id, "field_repair")
	for fleet in state.fleets_of(faction_id):
		fleet.moves_left = fleet_speed(fleet)
		var planet := state.planet_at(fleet.cell)
		var at_home := planet != null and planet.owner == faction_id
		var rate := REPAIR_RATE if at_home else field_repair
		if rate > 0.0:
			var repaired := 0
			for ship in fleet.ships:
				var max_hull := int(data.units[ship["unit"]]["stats"]["max_hull"])
				var amount := mini(max_hull - int(ship["hull"]), ceili(max_hull * rate))
				ship["hull"] = int(ship["hull"]) + amount
				repaired += amount
			if repaired > 0:
				emit({"type": GalaxyEvents.FLEET_REPAIRED, "fleet": fleet.id, "amount": repaired,
						"planet": planet.id if at_home else ""})
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


## Income, research and production at the start of a faction's turn.
func _run_economy(faction_id: String) -> void:
	var gained := EmpireRules.income(self, faction_id)
	var stock: Dictionary = state.resources[faction_id]
	stock["credits"] = int(stock.get("credits", 0)) + int(gained["credits"])
	stock["alloys"] = int(stock.get("alloys", 0)) + int(gained["alloys"])
	emit({"type": GalaxyEvents.INCOME, "faction": faction_id, "income": gained})

	# Research points flow into the current tech; unspent points carry over.
	var r: Dictionary = state.research[faction_id]
	r["progress"] = int(r["progress"]) + int(gained["research"])
	var current: String = r["current"]
	if not current.is_empty() and r["progress"] >= ResearchRules.cost(self, current):
		r["progress"] = int(r["progress"]) - ResearchRules.cost(self, current)
		r["known"].append(current)
		r["current"] = ""
		emit({"type": GalaxyEvents.TECH_RESEARCHED, "faction": faction_id, "tech": current})

	for planet in state.planets_of(faction_id):
		if planet.queue.is_empty():
			continue
		planet.queue["progress"] = mini(int(planet.queue["progress"]) + 1, int(planet.queue["turns"]))
		if planet.queue["progress"] < planet.queue["turns"]:
			continue
		if planet.queue["kind"] == "building":
			planet.add_building(planet.queue.get("body", ""), planet.queue["item"])
			emit({"type": GalaxyEvents.BUILDING_COMPLETED, "planet": planet.id, "building": planet.queue["item"],
					"body": planet.queue.get("body", "")})
			planet.queue = {}
		elif _launch_ship(planet, planet.queue["item"]):
			planet.queue = {}
		# else: no room to launch (orbit full); it waits, finished, for next turn

	# Time at peace slowly builds trust.
	for f in state.factions:
		if f["id"] != faction_id and not state.is_eliminated(f["id"]) and not state.at_war(faction_id, f["id"]):
			DiplomacyRules.change_opinion(state, faction_id, f["id"], DiplomacyRules.PEACE_DRIFT)


## Barbarians don't hold what they take: they strip a system (credits from
## its owner, one building wrecked, the build queue lost) and leave it
## unclaimed.
func _plunder(planet: Planet, fleet: Fleet) -> void:
	var previous := planet.owner
	var stolen := 0
	if not previous.is_empty():
		var stock: Dictionary = state.resources[previous]
		stolen = mini(int(stock.get("credits", 0)), 40)
		stock["credits"] = int(stock["credits"]) - stolen
		state.resources[fleet.owner]["credits"] = int(state.resources[fleet.owner].get("credits", 0)) + stolen
	var wrecked := ""
	for b_id: String in planet.buildings:
		if b_id != "colony":
			wrecked = b_id
	if not wrecked.is_empty():
		planet.remove_building(wrecked)
	planet.queue = {}
	planet.owner = ""
	_evacuate_heroes(planet, previous)
	DiplomacyRules.change_opinion(state, previous, fleet.owner, DiplomacyRules.PLANET_TAKEN_OPINION)
	emit({"type": GalaxyEvents.SYSTEM_PLUNDERED, "planet": planet.id, "faction": fleet.owner, "previous_owner": previous,
			"credits": stolen, "building": wrecked})
	_update_explored()
	_check_eliminations()


## Barbarian dens (systems a barbarian faction holds) launch a new raider
## fleet every `spawn_every` turns while the faction has fewer than
## `max_fleets` fleets.
func _barbarian_spawns(faction_id: String) -> void:
	var f := state.faction(faction_id)
	var spec: Dictionary = f.get("barbarian", {})
	if f.get("role", "") != "barbarian" or spec.is_empty():
		return
	var every := int(spec.get("spawn_every", 4))
	if state.turn_number % every != 0:
		return
	for den in state.planets_of(faction_id):
		if state.fleets_of(faction_id).size() >= int(spec.get("max_fleets", 4)):
			return
		if state.fleet_at(den.cell) != null:
			continue
		var fleet := Fleet.new()
		fleet.id = state.make_uid("fleet")
		fleet.owner = faction_id
		fleet.cell = den.cell
		fleet.name = "%s Raiders %d" % [den.name, state.next_uid]
		for unit_id: String in spec.get("fleet", ["interceptor", "interceptor"]):
			var def: Dictionary = data.units[unit_id]
			fleet.ships.append({"uid": state.make_uid("ship"), "unit": unit_id,
					"name": "%s %d" % [def.get("name", unit_id), state.next_uid], "hull": int(def["stats"]["max_hull"])})
		fleet.moves_left = 0
		state.fleets[fleet.id] = fleet
		emit({"type": GalaxyEvents.FLEET_CREATED, "fleet": fleet.id, "planet": den.id})


## A finished ship joins the faction's fleet in orbit, or forms a new fleet.
func _launch_ship(planet: Planet, unit_id: String) -> bool:
	var fleet := state.fleet_at(planet.cell)
	if fleet != null and (fleet.owner != planet.owner or fleet.ships.size() >= EmpireRules.MAX_FLEET_SIZE):
		return false
	var unit_def: Dictionary = data.units[unit_id]
	if fleet == null:
		fleet = Fleet.new()
		fleet.id = state.make_uid("fleet")
		fleet.owner = planet.owner
		fleet.cell = planet.cell
		fleet.name = "%s Squadron %d" % [planet.name, state.next_uid]
		state.fleets[fleet.id] = fleet
		emit({"type": GalaxyEvents.FLEET_CREATED, "fleet": fleet.id, "planet": planet.id})
	var ship := {"uid": state.make_uid("ship"), "unit": unit_id,
			"name": "%s %d" % [unit_def.get("name", unit_id), state.next_uid],
			"hull": int(unit_def["stats"]["max_hull"])}
	fleet.ships.append(ship)
	emit({"type": GalaxyEvents.SHIP_COMPLETED, "planet": planet.id, "unit": unit_id, "fleet": fleet.id,
			"ship": ship["name"]})
	return true


func _do_queue(cmd: QueueBuildCommand) -> void:
	var planet: Planet = state.planets[cmd.planet_id]
	var source: Dictionary = data.buildings[cmd.item_id] if cmd.kind == "building" \
			else data.units[cmd.item_id].get("strategic", {})
	var cost: Dictionary = source.get("cost", {})
	EmpireRules.pay(self, cmd.faction_id, cost)
	var turns := int(source.get("turns", source.get("build_turns", 1)))
	var body_id := cmd.body_id
	if cmd.kind == "building" and body_id.is_empty():
		for option in EmpireRules.build_options(self, planet):
			if option["kind"] == "building" and option["id"] == cmd.item_id and option["ok"]:
				body_id = option["body"]
				break
	planet.queue = {"kind": cmd.kind, "item": cmd.item_id, "body": body_id, "progress": 0, "turns": turns}
	emit({"type": GalaxyEvents.BUILD_QUEUED, "planet": planet.id, "kind": cmd.kind, "item": cmd.item_id,
			"turns": turns})


func _validate_diplomacy(cmd: DiplomacyCommand) -> String:
	var target := state.faction(cmd.target)
	if target.is_empty() or cmd.target == cmd.faction_id or state.is_eliminated(cmd.target):
		return "No such faction"
	match cmd.action:
		"propose_peace":
			if not state.at_war(cmd.faction_id, cmd.target):
				return "You are already at peace"
			if target["controller"] == "player":
				return "%s are run by a player: they decide for themselves" % target["name"]
		"declare_war":
			if state.at_war(cmd.faction_id, cmd.target):
				return "You are already at war"
		"gift":
			if int(state.resources[cmd.faction_id].get("credits", 0)) < DiplomacyRules.GIFT_CREDITS:
				return "Not enough credits (need %d)" % DiplomacyRules.GIFT_CREDITS
		_:
			return "Unknown diplomatic action"
	return ""


func _do_diplomacy(cmd: DiplomacyCommand) -> void:
	match cmd.action:
		"propose_peace":
			var refusal := DiplomacyRules.peace_refusal(self, cmd.target, cmd.faction_id)
			if refusal.is_empty():
				state.set_relation(cmd.faction_id, cmd.target, "peace")
				emit({"type": GalaxyEvents.PEACE_SIGNED, "factions": [cmd.faction_id, cmd.target]})
				_check_eliminations()
			else:
				emit({"type": GalaxyEvents.PEACE_REFUSED, "faction": cmd.faction_id, "target": cmd.target,
						"reason": refusal})
		"declare_war":
			state.set_relation(cmd.faction_id, cmd.target, "war")
			DiplomacyRules.change_opinion(state, cmd.target, cmd.faction_id, DiplomacyRules.WAR_DECLARED_OPINION)
			emit({"type": GalaxyEvents.WAR_DECLARED, "faction": cmd.faction_id, "target": cmd.target})
		"gift":
			state.resources[cmd.faction_id]["credits"] -= DiplomacyRules.GIFT_CREDITS
			state.resources[cmd.target]["credits"] += DiplomacyRules.GIFT_CREDITS
			DiplomacyRules.change_opinion(state, cmd.target, cmd.faction_id, DiplomacyRules.GIFT_OPINION)
			emit({"type": GalaxyEvents.GIFT_SENT, "faction": cmd.faction_id, "target": cmd.target,
					"credits": DiplomacyRules.GIFT_CREDITS})


func _reveal_around(fleet: Fleet) -> void:
	var explored: Dictionary = state.explored[fleet.owner]
	for c in state.grid.cells_within(fleet.cell, fleet_sensor(fleet)):
		explored[c] = true


func _update_explored() -> void:
	for f in state.factions:
		var explored: Dictionary = state.explored[f["id"]]
		for c: Vector2i in visible_cells(f["id"]):
			explored[c] = true


## A faction with no fleets and no planets is out; last one standing wins.
## If the survivors are all at peace with each other, the war is over and the
## highest score wins.
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
	# Only major powers play to win: barbarians and minor powers neither win
	# nor keep the game going.
	var remaining: Array[String] = []
	for f in state.factions:
		if f["id"] not in state.eliminated and f.get("role", "major") == "major":
			remaining.append(f["id"])
	# Scenario goal: {"victory": {"eliminate": faction id}} ends the game, won by
	# the strongest surviving major power, once that faction is gone.
	var target: String = campaign.get("victory", {}).get("eliminate", "")
	if not target.is_empty():
		if target in state.eliminated:
			var winner := ""
			for f in remaining:
				if winner.is_empty() or EmpireRules.score(self, f) > EmpireRules.score(self, winner):
					winner = f
			_finish(winner, "objective")
		elif remaining.is_empty():
			_finish("", "elimination")
		return
	if remaining.size() <= 1:
		_finish(remaining[0] if remaining.size() == 1 else "", "elimination")
		return
	for a in remaining:
		for b in remaining:
			if state.at_war(a, b):
				return
	var best := ""
	for f in remaining:
		if best.is_empty() or EmpireRules.score(self, f) > EmpireRules.score(self, best):
			best = f
	_finish(best, "peace")


func _finish(winner: String, reason: String) -> void:
	state.is_over = true
	state.winner = winner
	emit({"type": GalaxyEvents.CAMPAIGN_ENDED, "winner": winner, "reason": reason})


func _flush() -> Array[Dictionary]:
	var out := _events
	_events = []
	return out
