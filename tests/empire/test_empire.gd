extends TestCase
## Economy, production, research, diplomacy and planet defenses.
## Fixture galaxy: home_a (terran: 6 credits, 2 research), home_b (barren:
## 5 alloys), middle (ice). test_dummy: speed 3, sensor 1.


func _cell(e: GalaxyEngine, col: int, row: int) -> Vector2i:
	return e.state.grid.cell_from_layout(Vector2i(col, row))


func _end_round(e: GalaxyEngine) -> void:
	var start := e.current_faction_id()
	e.submit(EndFactionTurnCommand.new(start))
	while e.current_faction_id() != start and not e.state.is_over:
		e.submit(EndFactionTurnCommand.new(e.current_faction_id()))


func _rich(extra: Dictionary = {}) -> Dictionary:
	var base := {"resources": {"a": {"credits": 500, "alloys": 500}, "b": {"credits": 500, "alloys": 500}}}
	base.merge(extra, true)
	return base


func _planets_with(buildings_a: Array, buildings_b: Array = []) -> Array:
	return [
		{"id": "home_a", "type": "terran", "at": [0, 5], "owner": "a", "buildings": buildings_a},
		{"id": "home_b", "type": "barren", "at": [9, 5], "owner": "b", "buildings": buildings_b},
		{"id": "middle", "type": "ice", "at": [5, 3]},
	]


func test_income_each_turn() -> void:
	var e := Fixtures.galaxy([["a", "test_dummy", 1, 2], ["b", "test_dummy", 8, 2]])
	assert_eq(e.state.resources["a"]["credits"], 6, "terran yields 6 credits")
	assert_eq(e.state.research["a"]["progress"], 2, "unassigned research is banked")
	_end_round(e)
	assert_eq(e.state.resources["a"]["credits"], 12)
	assert_eq(e.state.resources["b"]["alloys"], 5, "b has had one turn: barren yields 5 alloys")


func test_building_costs_and_completes() -> void:
	var e := Fixtures.galaxy([["a", "test_dummy", 1, 2], ["b", "test_dummy", 8, 2]], _rich())
	var credits: int = e.state.resources["a"]["credits"]
	assert_true(e.submit(QueueBuildCommand.new("a", "home_a", "building", "mine")).ok)
	assert_eq(e.state.resources["a"]["credits"], credits - 40, "paid up front")
	assert_false(e.submit(QueueBuildCommand.new("a", "home_a", "building", "trade_hub")).ok, "one build at a time")
	_end_round(e)
	_end_round(e)
	assert_true("mine" in e.state.planets["home_a"].buildings)
	assert_eq(EmpireRules.planet_yields(e, e.state.planets["home_a"])["alloys"], 4)


func test_cannot_afford_or_build_ships_without_shipyard() -> void:
	var e := Fixtures.galaxy([["a", "test_dummy", 1, 2], ["b", "test_dummy", 8, 2]])
	assert_eq(e.submit(QueueBuildCommand.new("a", "home_a", "building", "research_lab")).error, "Can't afford it")
	var rich := Fixtures.galaxy([["a", "test_dummy", 1, 2], ["b", "test_dummy", 8, 2]], _rich())
	assert_false(rich.submit(QueueBuildCommand.new("a", "home_a", "unit", "frigate")).ok, "needs a shipyard")


func test_ships_join_fleet_or_form_new_one() -> void:
	var e := Fixtures.galaxy([["a", "test_dummy", 0, 5], ["b", "test_dummy", 8, 2]],
			_rich({"planets": _planets_with(["shipyard"])}))
	var fleet := e.state.fleets_of("a")[0]
	assert_true(e.submit(QueueBuildCommand.new("a", "home_a", "unit", "interceptor")).ok)
	_end_round(e)
	_end_round(e)
	assert_eq(fleet.ships.size(), 2, "joined the fleet in orbit")
	e.submit(MoveFleetCommand.new("a", fleet.id, _cell(e, 1, 4)))
	e.submit(QueueBuildCommand.new("a", "home_a", "unit", "interceptor"))
	_end_round(e)
	_end_round(e)
	assert_eq(e.state.fleets_of("a").size(), 2, "no fleet in orbit: a new one forms")


func test_research_completes_and_applies() -> void:
	var e := Fixtures.galaxy([["a", "test_fast_dummy", 2, 2], ["b", "test_dummy", 4, 2]])
	assert_false(e.submit(SetResearchCommand.new("a", "heavy_hulls")).ok, "needs Reinforced Hulls first")
	assert_true(e.submit(SetResearchCommand.new("a", "reinforced_hulls")).ok)
	e.state.research["a"]["progress"] = 39
	_end_round(e)
	assert_true("reinforced_hulls" in e.state.known_techs("a"))
	assert_eq(e.state.research["a"]["current"], "")
	var f := e.state.fleets_of("a")[0]
	e.submit(MoveFleetCommand.new("a", f.id, e.state.fleets_of("b")[0].cell))
	var statuses: Array = e.pending_battle_scenario()["teams"][0]["units"][0]["statuses"]
	assert_eq(statuses[0]["status"], "tech_reinforced_hulls")


func test_tech_modifiers_and_unlocks() -> void:
	var e := Fixtures.galaxy([["a", "test_dummy", 0, 5], ["b", "test_dummy", 8, 2]],
			_rich({"techs": {"a": ["improved_drives", "heavy_hulls"]}, "planets": _planets_with(["shipyard"])}))
	assert_eq(e.state.fleets_of("a")[0].moves_left, 4, "speed 3 + Improved Drives")
	var ids := EmpireRules.build_options(e, e.state.planets["home_a"]).map(func(o: Dictionary) -> String: return o["id"])
	assert_true("destroyer" in ids)
	var poor := Fixtures.galaxy([["a", "test_dummy", 0, 5], ["b", "test_dummy", 8, 2]],
			_rich({"planets": _planets_with(["shipyard"])}))
	ids = EmpireRules.build_options(poor, poor.state.planets["home_a"]).map(func(o: Dictionary) -> String: return o["id"])
	assert_false("destroyer" in ids)
	assert_false("defense_platform" in ids, "needs Orbital Defenses")


func _three(relations: Array, extra: Dictionary = {}) -> GalaxyEngine:
	var base := {
		"factions": [{"id": "a", "controller": "player"}, {"id": "b", "controller": "ai"},
				{"id": "c", "name": "Traders", "controller": "ai"}],
		"relations": relations,
		"resources": {"a": {"credits": 200}},
	}
	base.merge(extra, true)
	return Fixtures.galaxy([["a", "test_fast_dummy", 2, 2], ["b", "test_dummy", 9, 0], ["c", "test_dummy", 4, 2]], base)


func test_peace_blocks_attacks_and_captures() -> void:
	var e := _three([{"factions": ["a", "c"], "status": "peace", "opinion": 20}],
			{"planets": [{"id": "home_a", "type": "terran", "at": [0, 5], "owner": "a"},
				{"id": "port_c", "type": "ice", "at": [2, 4], "owner": "c"}]})
	var f := e.state.fleets_of("a")[0]
	var c_fleet := e.state.fleets_of("c")[0]
	assert_false(c_fleet.cell in e.attack_targets(f.id))
	assert_false(e.reachable_for(f.id).has(c_fleet.cell), "can't fly through friendly fleets")
	e.submit(MoveFleetCommand.new("a", f.id, e.state.planets["port_c"].cell))
	assert_eq(e.state.planets["port_c"].owner, "c", "no capturing a friend's planet")
	assert_true(e.submit(DiplomacyCommand.new("a", "c", "declare_war")).ok)
	assert_true(e.state.at_war("a", "c"))
	assert_eq(e.state.opinion("c", "a"), -10, "20 - 30 for declaring war")


func test_peace_proposals() -> void:
	var e := _three([])
	var early := e.submit(DiplomacyCommand.new("a", "c", "propose_peace"))
	assert_true(early.ok, early.error)
	assert_eq(early.events[0]["type"], GalaxyEvents.PEACE_REFUSED, "too soon after the war began")
	assert_true(e.state.at_war("a", "c"))
	for i in 3:
		_end_round(e)
	e.state.opinions["c"]["a"] = 15
	var result := e.submit(DiplomacyCommand.new("a", "c", "propose_peace"))
	var types := result.events.map(func(ev: Dictionary) -> String: return ev["type"])
	assert_true(GalaxyEvents.PEACE_SIGNED in types)
	assert_false(e.state.at_war("a", "c"))


func test_always_hostile_never_makes_peace() -> void:
	var e := _three([], {"factions": [{"id": "a", "controller": "player"},
			{"id": "b", "controller": "ai", "always_hostile": true}, {"id": "c", "controller": "ai"}]})
	for i in 4:
		_end_round(e)
	e.state.opinions["b"]["a"] = 100
	e.submit(DiplomacyCommand.new("a", "b", "propose_peace"))
	assert_true(e.state.at_war("a", "b"))


func test_gift() -> void:
	var e := _three([])
	var before: int = e.state.resources["c"]["credits"]
	assert_true(e.submit(DiplomacyCommand.new("a", "c", "gift")).ok)
	assert_eq(e.state.resources["c"]["credits"], before + DiplomacyRules.GIFT_CREDITS)
	assert_eq(e.state.opinion("c", "a"), DiplomacyRules.GIFT_OPINION)


func test_peace_with_everyone_ends_the_war() -> void:
	var e := Fixtures.galaxy([["a", "test_dummy", 1, 2], ["b", "test_dummy", 8, 2]])
	for i in 3:
		_end_round(e)
	e.state.opinions["b"]["a"] = 50
	e.submit(DiplomacyCommand.new("a", "b", "propose_peace"))
	assert_true(e.state.is_over, "nobody left at war")
	assert_ne(e.state.winner, "", "highest score wins")


func test_defended_planet_fights_and_falls() -> void:
	var e := Fixtures.galaxy([["a", "test_fast_dummy", 8, 4], ["b", "test_dummy", 1, 0]],
			{"planets": _planets_with([], ["defense_platform"])})
	var f := e.state.fleets_of("a")[0]
	var home_b: Planet = e.state.planets["home_b"]
	assert_true(home_b.cell in e.attack_targets(f.id))
	e.submit(MoveFleetCommand.new("a", f.id, home_b.cell))
	assert_true(e.has_pending_battle())
	assert_eq(e.state.pending_battle["planet"], "home_b")
	var scenario := e.pending_battle_scenario()
	assert_eq(scenario["teams"][1]["units"][0]["unit"], "defense_platform")
	var battle := BattleEngine.from_scenario(e.data, scenario, 3)
	for u: BattleUnit in battle.state.units.values():
		if u.team == 1:
			u.alive = false
	battle.state.winner = 0
	battle.state.is_over = true
	e.resolve_pending_battle(battle)
	assert_false("defense_platform" in home_b.buildings, "platform destroyed")
	assert_eq(home_b.owner, "a", "attacker storms the planet")
	assert_eq(f.cell, home_b.cell)


func test_immobile_units_cannot_move() -> void:
	var e := Fixtures.engine("test_open", [[0, "defense_platform", 0, 0], [1, "test_dummy", 9, 5]])
	e.start()
	var platform: BattleUnit
	for u: BattleUnit in e.state.units.values():
		if u.def_id == "defense_platform":
			platform = u
	assert_eq(e.reachable_cells(platform.id).size(), 1)


func test_ai_runs_the_economy() -> void:
	var data := DataRegistry.get_default()
	var e := GalaxyEngine.from_campaign(data, "the_drift", 8)
	CampaignAutoRunner.run(e, 400)
	var built := 0
	for p: Planet in e.state.planets.values():
		built += p.buildings.size()
	assert_true(built > 4, "AI should have built things (found %d buildings)" % built)
	var techs := 0
	for f in e.state.factions:
		techs += e.state.known_techs(f["id"]).size()
	assert_true(techs > 0, "AI should research")
