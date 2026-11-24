extends TestCase
## The system layer: civilian ships (colony ships, constructors, troop transports), claiming by
## colony or outpost, assaults that always fight, outposts vs colonies, blockades and the
## "colony_ship" start. Fixture galaxy (tests/fixtures.gd): home_a (terran colony, barren rock,
## gas giant) at [0, 5], home_b (desert colony, asteroid belt) at [9, 5], middle (ice moon,
## arctic world) at [5, 3]. test_dummy: speed 3, sensor 1; test_fast_dummy: speed 5, sensor 3.


func _cell(e: GalaxyEngine, col: int, row: int) -> Vector2i:
	return e.state.grid.cell_from_layout(Vector2i(col, row))


func _end_round(e: GalaxyEngine) -> void:
	var start := e.current_faction_id()
	e.submit(EndFactionTurnCommand.new(start))
	while e.current_faction_id() != start and not e.state.is_over:
		e.submit(EndFactionTurnCommand.new(e.current_faction_id()))


func _types(events: Array[Dictionary]) -> Array:
	return events.map(func(ev: Dictionary) -> String: return ev["type"])


func _ship(unit: String, owner: String, name: String = "") -> Dictionary:
	return {"unit": unit, "name": name if not name.is_empty() else unit, "owner": owner}


## A galaxy with plenty of money and civilians placed at systems:
## civilians: {system id: [ship defs]}; extra planets/fleets override the fixture's.
func _world(fleets: Array, civilians: Dictionary = {}, extra: Dictionary = {}) -> GalaxyEngine:
	var planets: Array = [
		{"id": "home_a", "at": [0, 5], "owner": "a", "star": "yellow",
			"bodies": [{"type": "terran", "buildings": ["colony", "shipyard"], "pop": 3}, {"type": "barren"}, {"type": "gas_giant"}]},
		{"id": "home_b", "at": [9, 5], "owner": "b", "star": "red",
			"bodies": [{"type": "desert", "buildings": ["colony"]}, {"type": "asteroid_belt"}]},
		{"id": "middle", "at": [5, 3], "star": "white", "bodies": [{"type": "ice_moon"}, {"type": "arctic"}]},
	]
	for p: Dictionary in planets:
		if civilians.has(p["id"]):
			p["civilians"] = civilians[p["id"]]
	var def := {"planets": planets, "resources": {"a": {"credits": 500, "alloys": 500, "volatiles": 50}, "b": {"credits": 500, "alloys": 500, "volatiles": 50}}}
	def.merge(extra, true)
	return Fixtures.galaxy(fleets, def)


func _fleet_of(e: GalaxyEngine, owner: String) -> Fleet:
	return e.state.fleets_of(owner)[0]


## Ends the pending battle with a win for team 0 (the attacker), everyone else dead.
func _win_battle(e: GalaxyEngine) -> void:
	var battle := BattleEngine.from_scenario(e.data, e.pending_battle_scenario(), 3)
	for u: BattleUnit in battle.state.units.values():
		if u.team != 0:
			u.alive = false
	battle.state.winner = 0
	battle.state.is_over = true
	e.resolve_pending_battle(battle)


# --- Claiming ---------------------------------------------------------------------

func test_entering_an_empty_system_claims_nothing() -> void:
	var e := _world([["a", "test_fast_dummy", 3, 3], ["b", "test_dummy", 9, 0]])
	var middle: Planet = e.state.planets["middle"]
	var result := e.submit(MoveFleetCommand.new("a", _fleet_of(e, "a").id, middle.cell))
	assert_true(result.ok, result.error)
	assert_eq(_fleet_of(e, "a").cell, middle.cell)
	assert_eq(middle.owner, "", "a fleet in orbit claims nothing")
	assert_false(GalaxyEvents.PLANET_CAPTURED in _types(result.events))
	assert_false(GalaxyEvents.SYSTEM_CLAIMED in _types(result.events))


func test_colony_ship_founds_colony_and_claims_the_system() -> void:
	var e := _world([["a", "test_dummy", 1, 2], ["b", "test_dummy", 9, 0]], {"middle": [_ship("colony_ship", "a", "Ark")]})
	var middle: Planet = e.state.planets["middle"]
	var ship_uid: String = middle.civilians[0]["uid"]
	var arctic: Dictionary = middle.bodies[1]
	var result := e.submit(CivilianCommand.new("a", "middle", ship_uid, CivilianCommand.FOUND, arctic["id"]))
	assert_true(result.ok, result.error)
	assert_eq(middle.owner, "a")
	assert_true("colony" in arctic["buildings"])
	assert_eq(EmpireRules.pop(arctic), 1, "a new colony starts at 1 pop")
	assert_true(middle.civilians.is_empty(), "the colony ship is used up")
	var types := _types(result.events)
	assert_true(GalaxyEvents.COLONY_FOUNDED in types)
	assert_true(GalaxyEvents.SYSTEM_CLAIMED in types)
	assert_true(middle.cell in e.visible_cells("a"), "an owned system gives vision")


func test_colony_ship_in_a_fleet_can_found_from_orbit() -> void:
	var e := _world([["a", "test_dummy", 5, 3], ["b", "test_dummy", 9, 0]])
	var fleet := _fleet_of(e, "a")
	fleet.ships.append({"uid": "colony1", "unit": "colony_ship", "name": "Ark", "hull": 70})
	var middle: Planet = e.state.planets["middle"]
	var result := e.submit(CivilianCommand.new("a", "middle", "colony1", CivilianCommand.FOUND, middle.bodies[1]["id"]))
	assert_true(result.ok, result.error)
	assert_eq(middle.owner, "a")
	assert_eq(fleet.ships.size(), 1, "only the colony ship was used")


func test_founding_rules() -> void:
	var e := _world([["a", "test_dummy", 1, 2], ["b", "test_dummy", 9, 0]], {
		"middle": [_ship("colony_ship", "a", "Ark"), _ship("constructor", "a", "Jack")],
		"home_b": [_ship("colony_ship", "a", "Intruder")]})
	var middle: Planet = e.state.planets["middle"]
	var ark: String = middle.civilians[0]["uid"]
	var jack: String = middle.civilians[1]["uid"]
	assert_false(e.submit(CivilianCommand.new("a", "middle", ark, CivilianCommand.FOUND, middle.bodies[0]["id"])).ok, "an ice moon isn't habitable")
	assert_false(e.submit(CivilianCommand.new("a", "middle", jack, CivilianCommand.FOUND, middle.bodies[1]["id"])).ok, "only colony ships found colonies")
	assert_false(e.submit(CivilianCommand.new("b", "middle", ark, CivilianCommand.FOUND, middle.bodies[1]["id"])).ok, "not b's turn")
	var enemy_home: Planet = e.state.planets["home_b"]
	assert_false(e.submit(CivilianCommand.new("a", "home_b", enemy_home.civilians[0]["uid"], CivilianCommand.FOUND, enemy_home.bodies[0]["id"])).ok,
			"another power's system and an already settled world")
	assert_true(e.submit(CivilianCommand.new("a", "middle", ark, CivilianCommand.FOUND, middle.bodies[1]["id"])).ok)
	assert_false(e.submit(CivilianCommand.new("a", "middle", ark, CivilianCommand.FOUND, middle.bodies[1]["id"])).ok, "the ship is gone")


func test_constructor_claims_an_empty_system_as_an_outpost() -> void:
	var e := _world([["a", "test_dummy", 1, 2], ["b", "test_dummy", 9, 0]], {"middle": [_ship("constructor", "a", "Jack")]})
	var middle: Planet = e.state.planets["middle"]
	var jack: String = middle.civilians[0]["uid"]
	var credits: int = e.state.resources["a"]["credits"]
	var result := e.submit(CivilianCommand.new("a", "middle", jack, CivilianCommand.JOB, middle.bodies[0]["id"], "research_station"))
	assert_true(result.ok, result.error)
	assert_eq(e.state.resources["a"]["credits"], credits - 40, "paid up front")
	assert_eq(middle.owner, "", "not claimed until the job is done")
	assert_eq(int(middle.civilians[0]["job"]["turns_left"]), 3, "the building's build time")
	_end_round(e)
	_end_round(e)
	assert_eq(middle.owner, "", "still working")
	var start := e.current_faction_id()
	e.submit(EndFactionTurnCommand.new(start))
	e.submit(EndFactionTurnCommand.new("b"))
	assert_eq(middle.owner, "a", "finished: the system is an outpost of a")
	assert_true("research_station" in middle.bodies[0]["buildings"])
	assert_true(middle.civilians[0]["job"].is_empty(), "idle again")


func test_constructor_takes_job_after_job_and_stays() -> void:
	var e := _world([["a", "test_dummy", 1, 2], ["b", "test_dummy", 9, 0]], {"home_a": [_ship("constructor", "a", "Jack")]})
	var home: Planet = e.state.planets["home_a"]
	var jack: String = home.civilians[0]["uid"]
	assert_true(e.submit(CivilianCommand.new("a", "home_a", jack, CivilianCommand.JOB, home.bodies[1]["id"], "mining_base")).ok)
	assert_false(e.submit(CivilianCommand.new("a", "home_a", jack, CivilianCommand.JOB, home.bodies[2]["id"], "gas_refinery")).ok,
			"one job at a time")
	_end_round(e)
	_end_round(e)
	assert_true("mining_base" in home.bodies[1]["buildings"])
	assert_eq(home.civilians.size(), 1, "the constructor is still there")
	assert_true(e.submit(CivilianCommand.new("a", "home_a", jack, CivilianCommand.JOB, home.bodies[2]["id"], "gas_refinery")).ok,
			"and takes another job")


func test_job_validation() -> void:
	var e := _world([["a", "test_dummy", 1, 2], ["b", "test_dummy", 9, 0]], {
		"home_a": [_ship("constructor", "a", "Jack"), _ship("colony_ship", "a", "Ark")],
		"home_b": [_ship("constructor", "a", "Spy")]})
	var home: Planet = e.state.planets["home_a"]
	var jack: String = home.civilians[0]["uid"]
	var ark: String = home.civilians[1]["uid"]
	assert_false(e.submit(CivilianCommand.new("a", "home_a", jack, CivilianCommand.JOB, home.bodies[0]["id"], "mining_base")).ok, "a colony world isn't mined")
	assert_false(e.submit(CivilianCommand.new("a", "home_a", jack, CivilianCommand.JOB, home.bodies[1]["id"], "colony")).ok, "colonies come from colony ships")
	assert_false(e.submit(CivilianCommand.new("a", "home_a", jack, CivilianCommand.JOB, home.bodies[1]["id"], "trade_hub")).ok, "colony buildings are queued")
	assert_false(e.submit(CivilianCommand.new("a", "home_a", ark, CivilianCommand.JOB, home.bodies[1]["id"], "mining_base")).ok, "colony ships don't build")
	var enemy: Planet = e.state.planets["home_b"]
	assert_false(e.submit(CivilianCommand.new("a", "home_b", enemy.civilians[0]["uid"], CivilianCommand.JOB, enemy.bodies[1]["id"], "mining_base")).ok, "not in another power's system")
	e.state.resources["a"]["credits"] = 5
	assert_false(e.submit(CivilianCommand.new("a", "home_a", jack, CivilianCommand.JOB, home.bodies[1]["id"], "mining_base")).ok, "can't afford it")


func test_developments_are_no_longer_queued() -> void:
	var e := _world([["a", "test_dummy", 1, 2], ["b", "test_dummy", 9, 0]])
	var home: Planet = e.state.planets["home_a"]
	assert_false(e.submit(QueueBuildCommand.new("a", "home_a", "building", "mining_base", home.bodies[1]["id"])).ok)
	assert_false(e.submit(QueueBuildCommand.new("a", "home_a", "building", "colony", home.bodies[0]["id"])).ok)
	assert_true(e.submit(QueueBuildCommand.new("a", "home_a", "building", "trade_hub", home.bodies[0]["id"])).ok, "colony buildings still queue")


func test_job_cancel_refunds_half() -> void:
	var e := _world([["a", "test_dummy", 1, 2], ["b", "test_dummy", 9, 0]], {"home_a": [_ship("constructor", "a", "Jack")]})
	var home: Planet = e.state.planets["home_a"]
	var jack: String = home.civilians[0]["uid"]
	e.submit(CivilianCommand.new("a", "home_a", jack, CivilianCommand.JOB, home.bodies[1]["id"], "mining_base"))
	var credits: int = e.state.resources["a"]["credits"]
	assert_true(e.submit(CivilianCommand.new("a", "home_a", jack, CivilianCommand.CANCEL)).ok)
	assert_eq(e.state.resources["a"]["credits"], credits + 17, "half of 35, rounded down")
	assert_true(home.civilians[0]["job"].is_empty())


# --- Building civilian ships --------------------------------------------------------

func test_colony_builds_settlers_for_a_pop_and_workers_for_free() -> void:
	var e := _world([["a", "test_dummy", 1, 2], ["b", "test_dummy", 9, 0]])
	var home: Planet = e.state.planets["home_a"]
	var colony: Dictionary = home.bodies[0]
	colony["pop"] = 1
	assert_false(e.submit(QueueBuildCommand.new("a", "home_a", "unit", "colony_ship")).ok, "needs 2+ pop")
	assert_true(e.submit(QueueBuildCommand.new("a", "home_a", "unit", "constructor")).ok, "workers need only a colony")
	for i in 3:
		_end_round(e)
	assert_eq(home.civilians.size(), 1, "the constructor waits in the system")
	assert_eq(home.civilians[0]["unit"], "constructor")
	assert_eq(e.state.fleets_of("a").size(), 1, "no new fleet: it is deployed")
	colony["pop"] = 3
	assert_true(e.submit(QueueBuildCommand.new("a", "home_a", "unit", "colony_ship")).ok)
	assert_eq(EmpireRules.pop(colony), 2, "the settlers came out of the colony")
	for i in 5:
		_end_round(e)
	assert_eq(home.civilians.size(), 2)
	assert_eq(home.civilians[1]["unit"], "colony_ship")


func test_depart_forms_a_fleet_or_joins_the_one_in_orbit() -> void:
	var e := _world([["a", "test_dummy", 1, 2], ["b", "test_dummy", 9, 0]], {"home_a": [_ship("constructor", "a", "Jack")]})
	var home: Planet = e.state.planets["home_a"]
	var jack: String = home.civilians[0]["uid"]
	var result := e.submit(CivilianCommand.new("a", "home_a", jack, CivilianCommand.DEPART))
	assert_true(result.ok, result.error)
	assert_true(home.civilians.is_empty())
	var fleet := e.state.fleet_at(home.cell)
	assert_true(fleet != null and fleet.is_civilian_only(e.data), "a convoy of one forms in orbit")
	assert_eq(fleet.ships[0]["uid"], jack)
	assert_true(fleet.moves_left > 0)


# --- Convoys and warships -------------------------------------------------------------

func test_warships_destroy_an_unescorted_convoy_without_a_battle() -> void:
	var e := _world([["a", "test_fast_dummy", 2, 2], ["b", "constructor", 4, 2]])
	var attacker := _fleet_of(e, "a")
	var convoy := _fleet_of(e, "b")
	assert_true(convoy.cell in e.attack_targets(attacker.id), "it shows as a target")
	var result := e.submit(MoveFleetCommand.new("a", attacker.id, convoy.cell))
	assert_true(result.ok, result.error)
	assert_false(e.has_pending_battle(), "no battle")
	assert_false(e.state.fleets.has(convoy.id), "the convoy is gone")
	assert_eq(attacker.cell, convoy.cell, "the warships take its place")
	assert_true(GalaxyEvents.FLEET_DESTROYED in _types(result.events))


func test_convoys_cannot_attack_or_fly_through_enemies() -> void:
	var e := _world([["a", "constructor", 3, 2], ["b", "test_dummy", 4, 2]])
	var convoy := _fleet_of(e, "a")
	var enemy := _fleet_of(e, "b")
	e.state.set_relation("a", "b", "war")
	assert_true(e.attack_targets(convoy.id).is_empty(), "unarmed")
	var reach := e.reachable_for(convoy.id)
	assert_false(reach.has(enemy.cell), "an enemy fleet is a wall to a convoy")
	# A convoy can't fly into an enemy system either.
	var e2 := _world([["a", "constructor", 8, 5], ["b", "test_dummy", 1, 0]])
	assert_false(e2.reachable_for(_fleet_of(e2, "a").id).has(e2.state.planets["home_b"].cell))


func test_hidden_warfleet_kills_a_convoy_that_flies_into_it() -> void:
	var e := _world([["a", "constructor", 0, 2], ["b", "test_dummy", 2, 2]])
	var convoy := _fleet_of(e, "a")
	var result := e.submit(MoveFleetCommand.new("a", convoy.id, _cell(e, 3, 2)))
	assert_true(result.ok, result.error)
	assert_false(e.has_pending_battle())
	assert_false(e.state.fleets.has(convoy.id), "ambushed without a chance to fight")


# --- Conquest ---------------------------------------------------------------------------

func test_every_owned_system_fields_a_garrison_and_an_assault_always_battles() -> void:
	var e := _world([["a", "test_fast_dummy", 8, 4], ["b", "test_dummy", 1, 0]])
	var home_b: Planet = e.state.planets["home_b"]
	assert_eq(EmpireRules.building_defense_units(e, home_b).size(), 0, "no defense buildings")
	assert_eq(EmpireRules.garrison_units(e, home_b).size(), 1, "but a base garrison")
	var fleet := _fleet_of(e, "a")
	assert_true(home_b.cell in e.attack_targets(fleet.id))
	e.submit(MoveFleetCommand.new("a", fleet.id, home_b.cell))
	assert_true(e.has_pending_battle(), "entering an enemy system is always a battle")
	assert_eq(home_b.owner, "b")
	var scenario := e.pending_battle_scenario()
	assert_eq(scenario["teams"][1]["units"][0]["unit"], "orbital_battery")


func test_garrison_scales_with_population() -> void:
	var e := _world([["a", "test_dummy", 1, 2], ["b", "test_dummy", 9, 0]])
	var home_b: Planet = e.state.planets["home_b"]
	home_b.bodies[0]["pop"] = 8
	assert_eq(EmpireRules.garrison_units(e, home_b).size(), 3, "1 + 8 / 4, capped at 3")
	home_b.bodies[0]["buildings"].append("defense_platform")
	assert_eq(EmpireRules.defense_units(e, home_b).size(), 4, "platforms come on top")
	assert_eq(EmpireRules.garrison_units(e, e.state.planets["middle"]).size(), 0, "unclaimed systems have none")


func test_outpost_is_captured_after_winning_the_battle() -> void:
	var e := _world([["a", "test_fast_dummy", 3, 3], ["b", "test_dummy", 9, 0]])
	var middle: Planet = e.state.planets["middle"]
	middle.owner = "b"
	middle.bodies[0]["buildings"].append("research_station")
	var fleet := _fleet_of(e, "a")
	e.submit(MoveFleetCommand.new("a", fleet.id, middle.cell))
	assert_true(e.has_pending_battle(), "even an outpost fights")
	_win_battle(e)
	assert_eq(middle.owner, "a", "an outpost needs no troops")
	assert_eq(fleet.cell, middle.cell)
	assert_false(middle.is_blockaded())


func test_colony_needs_troops_else_it_is_blockaded() -> void:
	var e := _world([["a", "test_fast_dummy", 8, 4], ["b", "test_dummy", 1, 0]])
	var home_b: Planet = e.state.planets["home_b"]
	var fleet := _fleet_of(e, "a")
	e.submit(MoveFleetCommand.new("a", fleet.id, home_b.cell))
	_win_battle(e)
	assert_eq(home_b.owner, "b", "a colony doesn't fall to warships alone")
	assert_eq(home_b.blockade, "a", "it is blockaded instead")
	assert_eq(fleet.cell, home_b.cell)
	assert_true(EmpireRules.planet_yields(e, home_b).is_empty(), "no production under blockade")
	assert_true(EmpireRules.garrison_units(e, home_b).is_empty(), "the garrison is beaten")


func test_troop_transport_takes_the_colony() -> void:
	var fleets := [{"name": "a fleet", "owner": "a", "at": [8, 4], "ships": [{"unit": "test_fast_dummy", "name": "Gun"}, {"unit": "troop_transport", "name": "Lander"}]},
			{"name": "b fleet", "owner": "b", "at": [1, 0], "ships": [{"unit": "test_dummy", "name": "Far"}]}]
	var e := GalaxyEngine.from_campaign(Fixtures.registry(), Fixtures.campaign([], {"fleets": fleets}), 99)
	e.start()
	var home_b: Planet = e.state.planets["home_b"]
	var fleet := _fleet_of(e, "a")
	e.submit(MoveFleetCommand.new("a", fleet.id, home_b.cell))
	_win_battle(e)
	assert_eq(home_b.owner, "a", "troops land and the system changes hands")
	assert_false(home_b.is_blockaded())
	assert_eq(fleet.ships.size(), 1, "the transport was used up")
	assert_eq(fleet.ships[0]["name"], "Gun")


func test_transport_joining_a_blockade_invades() -> void:
	var e := _world([["a", "test_fast_dummy", 8, 4], ["b", "test_dummy", 1, 0]])
	var home_b: Planet = e.state.planets["home_b"]
	var fleet := _fleet_of(e, "a")
	e.submit(MoveFleetCommand.new("a", fleet.id, home_b.cell))
	_win_battle(e)
	assert_eq(home_b.blockade, "a")
	# A transport arrives later as its own convoy and merges into the blockading fleet.
	e.submit(EndFactionTurnCommand.new("a"))
	e.submit(EndFactionTurnCommand.new("b"))
	var convoy := Fleet.new()
	convoy.id = "convoy"
	convoy.owner = "a"
	convoy.cell = e.state.grid.neighbors(home_b.cell)[0]
	convoy.name = "Landers"
	convoy.ships.append({"uid": "t1", "unit": "troop_transport", "name": "Lander", "hull": 80})
	convoy.moves_left = 3
	e.state.fleets["convoy"] = convoy
	assert_true(e.reachable_for("convoy").has(home_b.cell), "a convoy may join its own blockading fleet")
	var result := e.submit(MoveFleetCommand.new("a", "convoy", home_b.cell))
	assert_true(result.ok, result.error)
	assert_true(GalaxyEvents.SYSTEM_INVADED in _types(result.events))
	assert_eq(home_b.owner, "a")
	assert_eq(fleet.ships.size(), 1)


func test_blockade_halts_production_and_growth_and_lifts_when_the_fleet_leaves() -> void:
	var e := _world([["a", "test_fast_dummy", 8, 4], ["b", "test_dummy", 1, 0]])
	var home_b: Planet = e.state.planets["home_b"]
	var colony: Dictionary = home_b.bodies[0]
	colony["pop"] = 1
	e.state.resources["b"]["credits"] = 500
	e.state.resources["b"]["alloys"] = 500
	var fleet := _fleet_of(e, "a")
	e.submit(MoveFleetCommand.new("a", fleet.id, home_b.cell))
	_win_battle(e)
	home_b.queue = {"kind": "building", "item": "trade_hub", "body": colony["id"], "progress": 0, "turns": 2}
	var before_income := int(EmpireRules.income(e, "b")["credits"])
	e.submit(EndFactionTurnCommand.new("a"))
	assert_eq(home_b.queue["progress"], 0, "the queue is paused")
	assert_eq(float(colony.get("growth", 0.0)), 0.0, "no growth")
	assert_eq(before_income, 0, "and no income from the system")
	# The fleet leaves: production resumes.
	e.submit(EndFactionTurnCommand.new("b"))
	assert_eq(home_b.blockade, "a", "still blockaded while the fleet stays")
	var neighbour := e.state.grid.neighbors(home_b.cell)[0]
	assert_true(e.submit(MoveFleetCommand.new("a", fleet.id, neighbour)).ok)
	assert_eq(home_b.blockade, "", "lifted as soon as the fleet leaves")
	assert_false(EmpireRules.planet_yields(e, home_b).is_empty())


func test_barbarian_den_falls_to_warships_alone() -> void:
	var e := _world([["a", "test_fast_dummy", 8, 4], ["b", "test_dummy", 1, 0]])
	e.state.faction("b")["role"] = "barbarian"
	var home_b: Planet = e.state.planets["home_b"]
	home_b.bodies[0]["buildings"].append("defense_platform")  # dens field only their own platforms, no base garrison
	var fleet := _fleet_of(e, "a")
	e.submit(MoveFleetCommand.new("a", fleet.id, home_b.cell))
	_win_battle(e)
	assert_eq(home_b.owner, "a", "a raider den is cleared by winning the battle")


func test_plunder_keeps_the_owner_unless_nothing_is_left() -> void:
	var e := _world([["a", "test_dummy", 1, 2], ["b", "test_fast_dummy", 3, 3]])
	e.state.faction("b")["role"] = "barbarian"
	var colony_system: Planet = e.state.planets["home_a"]
	colony_system.bodies[0]["pop"] = 3
	var raider := _fleet_of(e, "b")
	e.state.planets["middle"].owner = "a"
	e.state.planets["middle"].bodies[0]["buildings"].append("outpost")
	e._plunder(e.state.planets["middle"], raider)
	assert_eq(e.state.planets["middle"].owner, "", "a razed outpost is unclaimed again")
	e._plunder(colony_system, raider)
	assert_eq(colony_system.owner, "a", "a colony stays with its owner")
	assert_eq(colony_system.bodies[0]["pop"], 2, "but loses a pop")


# --- Starts and the AI ----------------------------------------------------------------------

func test_colony_ship_start_in_random_sector() -> void:
	var e := GalaxyEngine.from_campaign(DataRegistry.get_default(), "random_sector", 4)
	e.start()
	var majors := 0
	for f in e.state.factions:
		if f.get("role", "major") != "major":
			continue
		majors += 1
		assert_true(e.state.planets_of(f["id"]).is_empty(), "%s owns nothing yet" % f["id"])
		var capital: Planet = null
		for p: Planet in e.state.planets.values():
			if p.capital.get("faction", "") == f["id"]:
				capital = p
		assert_true(capital != null, "%s has a home system waiting" % f["id"])
		assert_eq(capital.owner, "")
		var roles := capital.civilians.map(func(c: Dictionary) -> String: return Fleet.role_of(e.data, c["unit"]))
		assert_true("colony" in roles and "constructor" in roles, "a colony ship and a constructor")
		assert_true(e.state.fleet_at(capital.cell) != null and e.state.fleet_at(capital.cell).owner == f["id"], "the warfleet is in the home system")
	assert_eq(majors, 3)
	for p: Planet in e.state.planets.values():
		if p.owner == "raiders" or p.owner == "traders":
			assert_false(p.colonies().is_empty(), "minor powers and raiders start owned")


func test_the_drift_keeps_its_owned_start() -> void:
	var e := GalaxyEngine.from_campaign(DataRegistry.get_default(), "the_drift", 2)
	e.start()
	assert_eq(e.state.planets_of("patrol").size(), 1)
	assert_true(e.state.planets["haven"].civilians.is_empty())


func test_the_player_founds_the_capital_with_the_colony_ship() -> void:
	var e := GalaxyEngine.from_campaign(DataRegistry.get_default(), "random_sector", 4)
	e.start()
	var home: Planet = null
	for p: Planet in e.state.planets.values():
		if p.capital.get("faction", "") == "patrol":
			home = p
	var ship := ""
	for c in home.civilians:
		if Fleet.role_of(e.data, c["unit"]) == "colony":
			ship = c["uid"]
	var target := SystemRules.colony_targets(e, home, "patrol")[0]
	var result := e.submit(CivilianCommand.new("patrol", home.id, ship, CivilianCommand.FOUND, target["id"]))
	assert_true(result.ok, result.error)
	assert_eq(home.owner, "patrol")
	assert_true(EmpireRules.has_shipyard(e, home), "the capital gets the campaign's capital buildings")
	assert_eq(EmpireRules.pop(target), 3)
	var events := _types(result.events)
	assert_true(GalaxyEvents.COLONY_FOUNDED in events)


func test_ai_founds_its_capital_on_turn_one_and_expands() -> void:
	var e := GalaxyEngine.from_campaign(DataRegistry.get_default(), "random_sector", 7)
	e.start()
	var ai := GalaxyAI.new()
	var guard := 0
	var counts := {}
	while e.state.turn_number < 31 and not e.state.is_over and guard < 20000:
		guard += 1
		if e.has_pending_battle():
			e.auto_resolve_pending_battle()
			continue
		if e.has_pending_mission():
			e.auto_resolve_pending_mission()
			continue
		var result := e.submit(ai.decide(e))
		if not result.ok:
			result = e.submit(EndFactionTurnCommand.new(e.current_faction_id()))
		for ev in result.events:
			counts[ev["type"]] = int(counts.get(ev["type"], 0)) + 1
		if e.state.turn_number == 2 and e.state.current_faction_index == 0 and not counts.has("checked"):
			counts["checked"] = 1
			for f in e.state.factions:
				if f.get("role", "major") == "major":
					assert_eq(e.state.planets_of(f["id"]).size(), 1, "%s founded its capital on turn 1" % f["id"])
	assert_true(int(counts.get(GalaxyEvents.JOB_COMPLETED, 0)) >= 6, "constructors develop bodies")
	assert_true(int(counts.get(GalaxyEvents.COLONY_FOUNDED, 0)) >= 5, "colony ships settle new worlds")
	var total := 0
	for f in e.state.factions:
		if f.get("role", "major") == "major":
			total += e.state.planets_of(f["id"]).size()
	assert_true(total >= 6, "the majors hold more than their capitals (%d systems)" % total)


# --- Saving ---------------------------------------------------------------------------------

func test_save_round_trip_keeps_civilians_jobs_blockades_and_capitals() -> void:
	var e := _world([["a", "test_fast_dummy", 8, 4], ["b", "test_dummy", 1, 0]], {"middle": [_ship("constructor", "a", "Jack")]})
	var middle: Planet = e.state.planets["middle"]
	e.submit(CivilianCommand.new("a", "middle", middle.civilians[0]["uid"], CivilianCommand.JOB, middle.bodies[0]["id"], "research_station"))
	var home_b: Planet = e.state.planets["home_b"]
	e.submit(MoveFleetCommand.new("a", _fleet_of(e, "a").id, home_b.cell))
	_win_battle(e)
	home_b.capital = {"faction": "b", "buildings": ["shipyard"], "pop": 3}
	var save := GalaxySave.to_dict(e, "the_drift")
	assert_false(save.is_empty())
	assert_eq(save["version"], GalaxySave.VERSION)
	assert_true(GalaxySave.VERSION >= 4)
	var loaded := GalaxySave.from_dict(e.data, save)
	assert_true(loaded.has("engine"), str(loaded.get("error", "")))
	var e2: GalaxyEngine = loaded["engine"]
	assert_eq(var_to_str(GalaxySave.to_dict(e2, "the_drift")["state"]), var_to_str(save["state"]))
	assert_eq(e2.state.planets["middle"].civilians[0]["job"]["building"], "research_station")
	assert_eq(e2.state.planets["home_b"].blockade, "a")
	assert_eq(e2.state.planets["home_b"].capital["faction"], "b")
	# The loaded game keeps working: the job finishes.
	for i in 3:
		_end_round(e2)
	assert_eq(e2.state.planets["middle"].owner, "a")


func test_old_saves_are_refused() -> void:
	var e := _world([["a", "test_dummy", 1, 2], ["b", "test_dummy", 9, 0]])
	var save := GalaxySave.to_dict(e, "the_drift")
	save["version"] = 3
	assert_true(GalaxySave.from_dict(e.data, save).has("error"), "saves from before the system layer can't be loaded")
