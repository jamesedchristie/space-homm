extends TestCase
## Solar Age: the system-scale campaign (SystemLayout), surveys, the Hyperdrive victory,
## system-scale battles on local maps, saves and an AI autoplay.

var _data: DataRegistry


func before_each() -> void:
	_data = DataRegistry.get_default()


func _engine(seed_value: int = 3) -> GalaxyEngine:
	return GalaxyEngine.from_campaign(_data, "solar_age", seed_value)


func _layout_cell(e: GalaxyEngine, at: Array) -> Vector2i:
	return e.state.grid.cell_from_layout(Vector2i(int(at[0]), int(at[1])))


# --- Layout -------------------------------------------------------------------

func test_layout_is_deterministic_per_seed() -> void:
	var a := SystemLayout.generate(_data, _data.campaigns["solar_age"], 7)
	var b := SystemLayout.generate(_data, _data.campaigns["solar_age"], 7)
	assert_eq(var_to_str(a), var_to_str(b), "same seed, same system")
	var c := SystemLayout.generate(_data, _data.campaigns["solar_age"], 8)
	assert_ne(var_to_str(a["planets"]), var_to_str(c["planets"]), "another seed lays it out differently")
	assert_eq(a["scale"], "system")


func test_layout_constraints() -> void:
	for seed_value in [1, 2, 3, 4, 5, 6]:
		var e := _engine(seed_value)
		var s := e.state
		var grid: HexGrid = s.grid
		var center := grid.cell_from_layout(Vector2i(grid.width / 2, grid.height / 2))
		assert_eq(grid.terrain_at(center), "star", "the star burns in the centre (seed %d)" % seed_value)
		assert_false(grid.is_passable(center))
		for n in grid.neighbors(center):
			assert_eq(grid.terrain_at(n), "corona")
		# One body per Planet; no two bodies adjacent unless one is the other's moon.
		var moon_of := {}
		for p_def: Dictionary in e.campaign["planets"]:
			if p_def.has("moon_of"):
				moon_of[p_def["id"]] = p_def["moon_of"]
		var planets: Array = s.planets.values()
		for p: Planet in planets:
			assert_eq(p.bodies.size(), 1, "%s holds one body" % p.name)
			assert_ne(grid.terrain_at(p.cell), "corona")
		for i in planets.size():
			for j in range(i + 1, planets.size()):
				var p: Planet = planets[i]
				var q: Planet = planets[j]
				if grid.distance(p.cell, q.cell) <= 1:
					var family: bool = moon_of.get(p.id, "") == q.id or moon_of.get(q.id, "") == p.id \
							or (moon_of.has(p.id) and moon_of.get(p.id, "") == moon_of.get(q.id, ""))
					assert_true(family, "%s and %s are adjacent but not planet and moon (seed %d)" % [p.name, q.name, seed_value])
		# The homeworld is the player's, settled, with a shipyard.
		var home := s.home_planet("patrol")
		assert_true(home != null)
		assert_eq(home.bodies[0]["type"], "terran")
		assert_true("colony" in home.bodies[0]["buildings"] and "shipyard" in home.bodies[0]["buildings"])
		assert_eq(EmpireRules.pop(home.bodies[0]), 3)
		# A belt arc with belt bodies on it, gas giants, marginal worlds, dens, jump points.
		var types := {}
		for p: Planet in planets:
			types[p.bodies[0]["type"]] = int(types.get(p.bodies[0]["type"], 0)) + 1
			if p.bodies[0]["type"] == "asteroid_belt":
				assert_eq(grid.terrain_at(p.cell), "asteroid_belt", "a belt body sits on the belt")
		assert_true(int(types.get("asteroid_belt", 0)) >= 2, "belt bodies")
		assert_true(int(types.get("gas_giant", 0)) >= 1, "a gas giant")
		assert_true(int(types.get("desert", 0)) + int(types.get("arctic", 0)) >= 1, "a world to settle")
		assert_true(s.planets_of("separatists").size() == 1 and s.planets_of("scavengers").size() == 1, "two dens")
		var gates := 0
		for c in grid.cells():
			if grid.terrain_at(c) == "jump_point":
				gates += 1
				var l := grid.layout_from_cell(c)
				assert_true(l.x == 0 or l.y == 0 or l.x == grid.width - 1 or l.y == grid.height - 1, "jump points at the edge")
		assert_true(gates >= 2 and gates <= 3)
		# Every body, fleet and site can be reached from home.
		var field := Pathfinding.distance_field(grid, [home.cell])
		for p: Planet in planets:
			assert_true(field.has(p.cell), "%s is reachable" % p.name)
		for a: Dictionary in s.anomalies.values():
			assert_true(field.has(a["cell"]))
		for d: Dictionary in s.discoveries.values():
			assert_true(field.has(d["cell"]))
		# The sun and its corona are charted from the start.
		assert_true(e.explored_cells("patrol").has(center))


func test_starting_setup() -> void:
	var e := _engine(3)
	var s := e.state
	var home := s.home_planet("patrol")
	var guard := s.fleet_at(home.cell)
	assert_true(guard != null and guard.owner == "patrol")
	assert_eq(guard.ships.size(), 2)
	assert_true(not guard.hero_id.is_empty(), "a hero commands the patrol")
	var colony_ships := 0
	var constructors := 0
	for f in s.fleets_of("patrol"):
		for ship in f.ships:
			if Fleet.role_of(_data, ship["unit"]) == "colony":
				colony_ships += 1
	for p: Planet in s.planets.values():
		for c in p.civilians:
			if c["owner"] == "patrol" and Fleet.role_of(_data, c["unit"]) == "constructor":
				constructors += 1
				assert_true(p.owner.is_empty(), "the constructor starts beside a body it can develop")
	assert_eq(colony_ships, 1)
	assert_eq(constructors, 1)
	for id in ["separatists", "scavengers"]:
		assert_eq(s.faction(id)["role"], "barbarian")
		assert_true(s.at_war("patrol", id))
	assert_false(s.at_war("separatists", "scavengers"), "the hostiles leave each other alone")
	assert_eq(Fleet.model_variant(s.faction("scavengers")), "", "scavengers fly their species' ships")
	assert_eq(Fleet.model_variant(s.faction("separatists")), "raider")
	assert_true(ResearchRules.offered(e, "hyperdrive"))
	var drift := GalaxyEngine.from_campaign(_data, "the_drift", 3)
	assert_false(ResearchRules.offered(drift, "hyperdrive"), "Hyperdrive only exists in system-scale campaigns")
	assert_eq(ResearchRules.status(drift, "patrol", "hyperdrive"), ResearchRules.LOCKED)


func test_species_names_the_home_system() -> void:
	var def := SpeciesNaming.with_player_species(_data.campaigns["solar_age"], "kesh", _data)
	var e := GalaxyEngine.from_campaign(_data, def, 3)
	var home := e.state.home_planet("patrol")
	assert_eq(home.name, _data.species["kesh"]["names"]["homeworld"])
	var star: String = _data.species["kesh"]["names"]["home_star"]
	var named := 0
	for p: Planet in e.state.planets.values():
		if p.name.begins_with(star + " "):
			named += 1
	assert_true(named >= 5, "bodies carry the home star's name")


# --- Survey -------------------------------------------------------------------

func test_bodies_are_surveyed_by_ships_close_by() -> void:
	var e := _engine(3)
	e.start()
	var s := e.state
	var home := s.home_planet("patrol")
	assert_true(e.is_surveyed("patrol", home), "your own body is surveyed")
	# Something far from every ship of ours: unsurveyed, its traits unknown.
	var far: Planet = null
	for p: Planet in s.planets.values():
		var near := false
		for f in s.fleets_of("patrol"):
			near = near or s.grid.distance(f.cell, p.cell) <= 1
		if not near and p.owner.is_empty() and p.civilians.is_empty():
			far = p
			break
	assert_true(far != null)
	far.bodies[0]["traits"].assign(["rich_deposits"])
	assert_false(e.is_surveyed("patrol", far))
	assert_eq(e.known_traits("patrol", far, far.bodies[0]).size(), 0, "traits hidden until surveyed")
	# Park a ship next to it: surveyed, traits known, an event reported.
	var fleet := s.fleets_of("patrol")[0]
	var next := far.cell
	for n in s.grid.neighbors(far.cell):
		if s.grid.is_passable(n) and s.fleet_at(n) == null and s.planet_at(n) == null:
			next = n
	fleet.cell = next
	fleet.moves_left = 0
	e._reveal_around(fleet)
	var events := e._flush()
	assert_true(e.is_surveyed("patrol", far))
	assert_eq(e.known_traits("patrol", far, far.bodies[0]), ["rich_deposits"] as Array[String])
	assert_true(events.any(func(ev: Dictionary) -> bool:
		return ev["type"] == GalaxyEvents.BODY_SURVEYED and ev["planet"] == far.id))
	# Campaigns without surveys show everything.
	var drift := GalaxyEngine.from_campaign(_data, "the_drift", 3)
	for p: Planet in drift.state.planets.values():
		assert_true(drift.is_surveyed("patrol", p))


# --- Victory ------------------------------------------------------------------

func test_hyperdrive_wins_act_one() -> void:
	var e := _engine(3)
	e.start()
	var r: Dictionary = e.state.research["patrol"]
	r["current"] = "hyperdrive"
	r["progress"] = ResearchRules.cost(e, "hyperdrive") - 1  # crosses the line this turn
	var stock: Dictionary = e.state.resources["patrol"]
	stock["exotic_matter"] = 0
	var events := e._flush()
	events.clear()
	# The first jump burns exotic matter: without it in store, the research waits (points bank).
	e._run_economy("patrol")
	events = e._flush()
	assert_false(e.state.is_over, "no exotic matter, no hyperdrive")
	assert_true("hyperdrive" not in e.state.known_techs("patrol"))
	assert_true(events.any(func(ev: Dictionary) -> bool:
		return ev["type"] == GalaxyEvents.RESEARCH_WAITING and ev["reason"].contains("exotic matter")))
	var needs := ResearchRules.resource_cost(e, "hyperdrive")
	assert_true(int(needs.get("exotic_matter", 0)) > 0)
	stock["exotic_matter"] = int(needs["exotic_matter"]) + 1
	stock["volatiles"] = int(needs.get("volatiles", 0)) + 2
	e._run_economy("patrol")
	events = e._flush()
	assert_eq(int(stock["exotic_matter"]), 1, "paid on completion")
	assert_true(e.state.is_over)
	assert_eq(e.state.winner, "patrol")
	assert_eq(e.state.victory_reason, "act1")
	assert_true(events.any(func(ev: Dictionary) -> bool: return ev["type"] == GalaxyEvents.CAMPAIGN_ENDED))
	assert_true(VictoryRules.enabled(e, "tech"))
	assert_eq(VictoryRules.progress(e)[0]["id"], "tech")


func test_lone_major_power_does_not_win_by_default() -> void:
	var e := _engine(3)
	e.start()
	e._check_eliminations()
	assert_false(e.state.is_over, "being the only major power isn't a win here")
	# Losing everything is.
	for f in e.state.fleets_of("patrol"):
		e.state.fleets.erase(f.id)
	for p in e.state.planets_of("patrol"):
		p.owner = ""
	for p: Planet in e.state.planets.values():
		p.civilians.assign(p.civilians.filter(func(c: Dictionary) -> bool: return c["owner"] != "patrol"))
	e._check_eliminations()
	assert_true(e.state.is_over)
	assert_eq(e.state.winner, "")
	assert_eq(e.state.victory_reason, "elimination")


func test_research_costs_scale_per_campaign() -> void:
	var solar := _engine(3)
	var drift := GalaxyEngine.from_campaign(_data, "the_drift", 3)
	var mul := float(_data.campaigns["solar_age"]["research_cost_mul"])
	assert_eq(ResearchRules.cost(solar, "scientific_method"), roundi(ResearchRules.cost(drift, "scientific_method") * mul))


# --- Battles ------------------------------------------------------------------

func test_system_scale_battle_uses_the_local_map() -> void:
	var e := _engine(3)
	e.start()
	var s := e.state
	var home := s.home_planet("patrol")
	# A raider pack next to the homeworld attacks it.
	var raiders := s.fleets_of("separatists")[0]
	var from := Vector2i.ZERO
	for n in s.grid.neighbors(home.cell):
		if s.grid.is_passable(n) and s.fleet_at(n) == null and s.planet_at(n) == null:
			from = n
			break
	raiders.cell = from
	s.pending_battle = {"attacker": raiders.id, "defender": s.fleet_at(home.cell).id, "cell": home.cell, "ambush": false,
			"planet": home.id}
	var scenario := e.pending_battle_scenario()
	var map: Dictionary = scenario["map_def"]
	assert_true(map.get("local", false), "fought on the local area")
	assert_eq(SystemBattleMap.check(map, _data.terrain, LocalBattleMap.MIN_OPEN), "")
	assert_true(map["bodies"].any(func(b: Dictionary) -> bool: return b["id"] == home.bodies[0]["id"] and b["colony"]))
	var battle := BattleEngine.from_scenario(_data, scenario, 11)
	AutoResolver.resolve(battle)
	assert_true(battle.state.is_over)
	# Other campaigns keep their maps: a battle at a star system is fought inside it.
	var drift := GalaxyEngine.from_campaign(_data, "the_drift", 3)
	drift.start()
	var haven: Planet = drift.state.home_planet("patrol")
	var enemy := drift.state.fleets_of("raiders")[0]
	enemy.cell = drift.state.grid.neighbors(haven.cell)[0]
	drift.state.pending_battle = {"attacker": enemy.id, "defender": "", "cell": haven.cell, "ambush": false, "planet": haven.id}
	var drift_map: Dictionary = drift.pending_battle_scenario()["map_def"]
	assert_false(drift_map.get("local", false))
	assert_eq(drift_map["id"], "system_%s" % haven.id)


# --- Saves and autoplay -------------------------------------------------------

func test_save_round_trip() -> void:
	var e := _engine(5)
	e.start()
	var ai := GalaxyAI.new()
	var guard := 0
	while guard < 400 and e.state.turn_number < 6:
		guard += 1
		if e.has_pending_battle():
			e.auto_resolve_pending_battle()
		elif e.has_pending_mission():
			e.auto_resolve_pending_mission()
		elif not e.submit(ai.decide(e)).ok:
			e.submit(EndFactionTurnCommand.new(e.current_faction_id()))
	while e.has_pending_battle() or e.has_pending_mission():
		if e.has_pending_battle():
			e.auto_resolve_pending_battle()
		else:
			e.decline_pending_mission()
	var save := GalaxySave.to_dict(e, "solar_age")
	assert_eq(save["version"], GalaxySave.VERSION)
	assert_false(save["campaign_def"].is_empty(), "the generated system is kept")
	var loaded := GalaxySave.from_dict(_data, save)
	assert_true(loaded.has("engine"), str(loaded.get("error", "")))
	var e2: GalaxyEngine = loaded["engine"]
	assert_eq(var_to_str(GalaxySave.to_dict(e2, "solar_age")["state"]), var_to_str(save["state"]))
	assert_true(e2.is_system_scale())
	assert_eq(e2.state.surveyed, e.state.surveyed)
	assert_eq(e2.campaign["system"], e.campaign["system"])


func test_autoplay_runs_without_errors() -> void:
	var e := _engine(6)
	var result := CampaignAutoRunner.run(e, 450)
	assert_true(result["commands"] > 100)
	assert_true(e.state.turn_number >= 15, "the AI plays turns (reached %d)" % e.state.turn_number)
	assert_true(e.state.planets_of("patrol").size() >= 3, "and claims bodies (%d)" % e.state.planets_of("patrol").size())
	assert_true(e.state.known_techs("patrol").size() >= 2)
	assert_true(int(result["events"].get(GalaxyEvents.JOB_COMPLETED, 0)) >= 2, "constructors work")
