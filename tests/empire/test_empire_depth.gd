extends TestCase
## Empire depth: colony population and growth, ship upkeep and debt, tech eras,
## megaprojects, and the AI's use of them.
## Fixture galaxy (see test_empire.gd): home_a (terran colony, pop 1, cap 8: 3+2
## credits and 1 research at pop 1; a barren rock; a gas giant), home_b (desert
## colony; asteroid belt), middle (ice moon, arctic).


func _end_round(e: GalaxyEngine) -> void:
	var start := e.current_faction_id()
	e.submit(EndFactionTurnCommand.new(start))
	while e.current_faction_id() != start and not e.state.is_over:
		e.submit(EndFactionTurnCommand.new(e.current_faction_id()))


func _rich(extra: Dictionary = {}) -> Dictionary:
	var base := {"resources": {"a": {"credits": 2000, "alloys": 2000, "rare_elements": 100, "volatiles": 100, "exotic_matter": 50}, "b": {"credits": 2000, "alloys": 2000, "rare_elements": 100, "volatiles": 100, "exotic_matter": 50}}}
	base.merge(extra, true)
	return base


func _two(extra: Dictionary = {}) -> GalaxyEngine:
	return Fixtures.galaxy([["a", "test_dummy", 1, 2], ["b", "test_dummy", 8, 2]], extra)


func _home_body(e: GalaxyEngine, planet_id: String = "home_a") -> Dictionary:
	return e.state.planets[planet_id].bodies[0]


# --- Population ---------------------------------------------------------------

func test_colony_population_cap_comes_from_type_traits_buildings_and_techs() -> void:
	var e := _two({"techs": {"a": ["colonial_medicine"]}})
	var terran := _home_body(e)
	var desert := _home_body(e, "home_b")
	assert_eq(EmpireRules.pop_cap(e, terran), 8, "terran worlds are big")
	assert_eq(EmpireRules.pop_cap(e, desert), 6, "deserts are smaller")
	assert_eq(EmpireRules.pop_cap(e, terran, "a"), 9, "Colonial Medicine: +1")
	assert_eq(EmpireRules.pop_cap(e, terran, "b"), 8, "only the researcher benefits")
	terran["traits"].append("vast_continents")
	assert_eq(EmpireRules.pop_cap(e, terran, "a"), 12, "vast continents: +3")
	terran["buildings"].append("orbital_habitat")
	assert_eq(EmpireRules.pop_cap(e, terran, "a"), 16, "Orbital Habitat: +4")
	desert["traits"].append("hostile_biosphere")
	assert_eq(EmpireRules.pop_cap(e, desert), 4, "hostile biosphere: -2")


func test_yields_scale_with_population() -> void:
	var e := _two()
	var home: Planet = e.state.planets["home_a"]
	assert_eq(EmpireRules.planet_yields(e, home)["credits"], 5, "pop 1: 3 colony + 2 terran")
	_home_body(e)["pop"] = 5
	var y := EmpireRules.planet_yields(e, home)
	assert_eq(y["credits"], 7, "+0.5 credits per extra pop")
	assert_eq(y["research"], 2, "+0.25 research per extra pop (1 + 1.0)")
	assert_eq(y["alloys"], 1, "+0.15 alloys per extra pop, rounded")
	_home_body(e)["buildings"].append("academy")
	assert_eq(EmpireRules.planet_yields(e, home)["research"], 2 + 2 + 2, "Academy: 2 flat + 0.5 per extra pop")


func test_colonies_grow_slowly_and_stop_at_the_cap() -> void:
	var e := _two()
	var body := _home_body(e)
	assert_eq(EmpireRules.pop(body), 1, "new colonies start at pop 1")
	assert_near(EmpireRules.growth_rate(e, body, "a"), 1.0 * (1.0 - 0.5 / 8.0), 0.0001, "slows as it fills")
	assert_near(EmpireRules.growth_cost(e, 1), 6.5, 0.0001)
	for i in 4:
		_end_round(e)
	assert_eq(EmpireRules.pop(body), 1, "growth takes several turns")
	assert_true(float(body["growth"]) > 3.0)
	for i in 6:
		_end_round(e)
	assert_eq(EmpireRules.pop(body), 2, "a new pop after about seven turns")
	# Fuller colonies grow slower.
	body["pop"] = 7
	assert_true(EmpireRules.growth_rate(e, body, "a") < 0.7)
	body["pop"] = 8
	assert_eq(EmpireRules.growth_rate(e, body, "a"), 0.0, "no growth at the cap")
	for i in 3:
		_end_round(e)
	assert_eq(EmpireRules.pop(body), 8)


func test_growth_techs_and_buildings_speed_colonies_up() -> void:
	var e := _two({"techs": {"a": ["hydroponics"]}})
	var body := _home_body(e)
	var base := EmpireRules.growth_rate(e, body, "b")
	assert_near(EmpireRules.growth_rate(e, body, "a") / base, 1.4, 0.01, "Hydroponics: +0.4 growth")
	body["buildings"].append("hydroponic_farm")
	assert_near(EmpireRules.growth_rate(e, body, "a") / base, 2.0, 0.01, "plus Hydroponic Farms: +0.6")
	assert_eq(EmpireRules.turns_to_grow(e, body, "a"),
			ceili((6.5 - float(body["growth"])) / EmpireRules.growth_rate(e, body, "a")))


func test_conquest_and_plunder_cost_population() -> void:
	var e := Fixtures.galaxy([["a", "test_dummy", 1, 2], ["b", "test_dummy", 8, 2]])
	_home_body(e, "home_b")["pop"] = 8
	e._capture_planet(e.state.planets["home_b"], e.state.fleets_of("a")[0])
	assert_eq(e.state.planets["home_b"].owner, "a")
	assert_eq(EmpireRules.pop(_home_body(e, "home_b")), 6, "a quarter of the people are lost (8 -> 6)")
	_home_body(e)["pop"] = 4
	e._lose_population(e.state.planets["home_a"], 0.0, 1)
	assert_eq(EmpireRules.pop(_home_body(e)), 3)
	e._lose_population(e.state.planets["home_a"], 0.9, 5)
	assert_eq(EmpireRules.pop(_home_body(e)), 1, "never below 1")


# --- Upkeep -------------------------------------------------------------------

func _navy() -> GalaxyEngine:
	return Fixtures.galaxy([["a", "frigate", 1, 2], ["a", "frigate", 1, 3], ["a", "frigate", 2, 2], ["a", "frigate", 2, 3],
			["a", "frigate", 3, 2], ["a", "frigate", 3, 3], ["b", "test_dummy", 8, 2]])


func test_ships_cost_upkeep_beyond_the_free_allowance() -> void:
	var e := _navy()
	var income := EmpireRules.income(e, "a")
	assert_eq(EmpireRules.fleet_upkeep(e, "a"), 12, "6 frigates at 2 credits each")
	assert_eq(EmpireRules.free_upkeep(e, "a"), 7, "4 base + 3 for the colony")
	assert_eq(income["upkeep"], 5)
	assert_eq(income["gross_credits"], 5)
	assert_eq(income["credits"], 0, "net income is after upkeep")
	assert_eq(e.state.resources["a"]["credits"], 0, "the first turn already paid")
	assert_eq(EmpireRules.upkeep(e, "b"), 0, "ships without a cost are free")
	var logistics := Fixtures.galaxy([["a", "frigate", 1, 2], ["a", "frigate", 1, 3], ["a", "frigate", 2, 2], ["a", "frigate", 2, 3],
			["a", "frigate", 3, 2], ["a", "frigate", 3, 3], ["b", "test_dummy", 8, 2]], {"techs": {"a": ["logistics_corps"]}})
	assert_eq(EmpireRules.upkeep(logistics, "a"), 3, "Logistics Corps: -20% (10 - 7)")
	_home_body(e)["pop"] = 3
	e.state.planets["home_a"].bodies[0]["buildings"].append("trade_hub")
	assert_true(EmpireRules.income(e, "a")["credits"] > income["credits"])
	# A second colony supports three more credits of ships.
	e.state.planets["home_a"].bodies.append({"id": "extra", "type": "ocean", "name": "Extra", "traits": [] as Array[String],
			"buildings": ["colony"] as Array[String], "pop": 1, "growth": 0.0})
	assert_eq(EmpireRules.free_upkeep(e, "a"), 10)


func test_only_major_powers_pay_upkeep() -> void:
	var e := Fixtures.galaxy([["a", "frigate", 1, 2], ["b", "frigate", 8, 2], ["b", "frigate", 8, 3], ["b", "frigate", 7, 2],
			["b", "frigate", 7, 3], ["b", "frigate", 8, 4]], {"factions": [{"id": "a", "controller": "player"},
			{"id": "b", "controller": "ai", "role": "barbarian"}]})
	assert_eq(EmpireRules.upkeep(e, "b"), 0)


func test_debt_stops_growth_and_repairs_and_costs_hull() -> void:
	var e := _navy()
	var ship: Dictionary = e.state.fleets_of("a")[0].ships[0]
	ship["hull"] = 100
	e.state.resources["a"]["credits"] = -50
	var growth_before := float(_home_body(e)["growth"])
	_end_round(e)
	assert_true(int(e.state.resources["a"]["credits"]) < 0, "still in debt")
	assert_eq(ship["hull"], 100 - 6, "5% of 120 hull lost, and no repair")
	assert_eq(float(_home_body(e)["growth"]), growth_before, "no growth in debt")
	e.state.resources["a"]["credits"] = 200
	_end_round(e)
	assert_true(float(_home_body(e)["growth"]) > growth_before, "growth resumes")
	assert_eq(ship["hull"], 94, "and the attrition stops")


func test_budget_crisis_event() -> void:
	var e := _navy()
	e.state.resources["a"]["credits"] = -50
	e.submit(EndFactionTurnCommand.new("a"))
	var result := e.submit(EndFactionTurnCommand.new("b"))
	var types := result.events.map(func(ev: Dictionary) -> String: return ev["type"])
	assert_true(GalaxyEvents.BUDGET_CRISIS in types)


# --- Eras ---------------------------------------------------------------------

func test_eras_gate_research() -> void:
	var era1 := ["deep_space_sensors", "reinforced_hulls", "shield_harmonics", "improved_drives", "automated_mining"]
	var e := _two({"techs": {"a": era1.slice(0, 4), "b": era1}})
	assert_eq(ResearchRules.era_of(e, "scientific_method"), 2)
	assert_eq(ResearchRules.status(e, "a", "scientific_method"), ResearchRules.LOCKED, "prerequisite met, era still closed")
	assert_eq(ResearchRules.status(e, "b", "scientific_method"), ResearchRules.AVAILABLE, "five era 1 techs open era 2")
	assert_false(e.submit(SetResearchCommand.new("a", "scientific_method")).ok)
	assert_true("Expansion Era" in ResearchRules.lock_reason(e, "a", "scientific_method"))
	assert_eq(ResearchRules.current_era(e, "a"), 1)
	assert_eq(ResearchRules.current_era(e, "b"), 2)
	assert_eq(ResearchRules.known_in_era(e, "b", 1), 5)
	assert_eq(ResearchRules.cost(e, "scientific_method"), 160, "era 2 costs 1.6x")
	assert_eq(ResearchRules.cost(e, "reinforced_hulls"), 40)


func test_third_era_needs_six_second_era_techs() -> void:
	var era1 := ["deep_space_sensors", "reinforced_hulls", "shield_harmonics", "improved_drives", "automated_mining"]
	var era2 := ["heavy_hulls", "targeting_computers", "field_repairs", "asteroid_refining", "scientific_method", "logistics_corps"]
	var e := _two({"techs": {"a": era1 + era2.slice(0, 5), "b": era1 + era2}})
	assert_eq(ResearchRules.status(e, "a", "capital_ships"), ResearchRules.LOCKED)
	assert_eq(ResearchRules.status(e, "b", "capital_ships"), ResearchRules.AVAILABLE)
	assert_eq(ResearchRules.current_era(e, "b"), 3)
	assert_true(ResearchRules.available(e, "b").size() > ResearchRules.available(e, "a").size())


func test_tech_tree_content() -> void:
	var data := DataRegistry.get_default()
	assert_eq(data.errors.size(), 0, "\n".join(data.errors))
	assert_true(data.techs.size() >= 28 and data.techs.size() <= 40, "28-40 techs (%d)" % data.techs.size())
	assert_eq(data.eras.size(), 3)
	var per_era := {1: 0, 2: 0, 3: 0}
	for id: String in data.techs:
		per_era[int(data.techs[id].get("era", 1))] += 1
	assert_true(per_era[1] >= 8 and per_era[2] >= 8 and per_era[3] >= 5, str(per_era))
	for id in ["reinforced_hulls", "shield_harmonics", "improved_drives", "deep_space_sensors", "automated_mining",
			"orbital_defenses", "heavy_hulls", "targeting_computers", "field_repairs", "terraforming", "orbital_habitats",
			"asteroid_refining", "deep_core_taps", "cryogenic_labs"]:
		assert_true(data.techs.has(id), "existing tech %s stays" % id)
	assert_true(data.units.has("cruiser") and data.units["cruiser"]["strategic"]["requires_tech"] == "capital_ships")
	assert_true(data.models.has(data.units["cruiser"]["visual"]["model"]))
	assert_true(data.units["cruiser"]["visual"].has("attack_style"))


func test_cruiser_and_new_buildings_unlock_with_techs() -> void:
	var e := _two(_rich({"techs": {"a": ["capital_ships", "scientific_method", "hydroponics"]},
			"planets": [{"id": "home_a", "at": [0, 5], "owner": "a", "bodies": [{"type": "terran", "buildings": ["colony", "shipyard"]}]},
				{"id": "home_b", "at": [9, 5], "owner": "b", "bodies": [{"type": "desert", "buildings": ["colony"]}]}]}))
	var ids := EmpireRules.build_options(e, e.state.planets["home_a"]).map(func(o: Dictionary) -> String: return o["id"])
	for id in ["cruiser", "academy", "hydroponic_farm"]:
		assert_true(id in ids, id)
	assert_false("commerce_exchange" in ids, "needs Galactic Commerce")
	assert_false("planetary_shield" in ids)


func test_sensor_array_and_fleet_academy() -> void:
	var e := _two()
	var home: Planet = e.state.planets["home_a"]
	var base := EmpireRules.planet_sensor(e, home)
	home.bodies[0]["buildings"].append("sensor_array")
	assert_eq(EmpireRules.planet_sensor(e, home), base + 2)
	assert_eq(EmpireRules.hero_xp_per_turn(e, "a"), 0)
	home.bodies[0]["buildings"].append("fleet_academy")
	assert_eq(EmpireRules.hero_xp_per_turn(e, "a"), 12)


# --- Megaprojects -------------------------------------------------------------

func _wonder_planets() -> Array:
	return [
		{"id": "home_a", "at": [0, 5], "owner": "a", "bodies": [{"type": "terran", "buildings": ["colony"]}]},
		{"id": "second_a", "at": [1, 4], "owner": "a", "bodies": [{"type": "ocean", "buildings": ["colony"]}]},
		{"id": "home_b", "at": [9, 5], "owner": "b", "bodies": [{"type": "desert", "buildings": ["colony"]}]},
	]


func _wonders(techs_a: Array, techs_b: Array = []) -> GalaxyEngine:
	return _two(_rich({"techs": {"a": techs_a, "b": techs_b}, "planets": _wonder_planets()}))


func _option(e: GalaxyEngine, planet_id: String, mp_id: String) -> Dictionary:
	for o in EmpireRules.build_options(e, e.state.planets[planet_id]):
		if o["kind"] == "megaproject" and o["id"] == mp_id:
			return o
	return {}


func test_megaprojects_are_tech_gated_and_expensive() -> void:
	var data := DataRegistry.get_default()
	assert_true(data.megaprojects.size() >= 5)
	for id: String in ["stellar_forge", "grand_archive", "galactic_exchange", "fleet_command_nexus", "ascension_gate"]:
		assert_true(data.megaprojects.has(id), id)
		assert_true(int(data.megaprojects[id]["turns"]) >= 8)
		assert_true(int(data.megaprojects[id]["cost"].get("credits", 0)) + int(data.megaprojects[id]["cost"].get("alloys", 0)) >= 300)
	var e := _wonders([])
	assert_true(_option(e, "home_a", "stellar_forge").is_empty(), "locked until Stellar Engineering")
	var e2 := _wonders(["stellar_engineering"])
	var o := _option(e2, "home_a", "stellar_forge")
	assert_false(o.is_empty())
	assert_true(o["ok"])
	assert_eq(o["turns"], 8)


func test_megaproject_builds_over_turns_and_pays_off() -> void:
	var e := _wonders(["stellar_engineering"])
	var home: Planet = e.state.planets["home_a"]
	var before := EmpireRules.planet_yields(e, home)
	var credits: int = e.state.resources["a"]["credits"]
	var queued := e.submit(QueueBuildCommand.new("a", "home_a", "megaproject", "stellar_forge"))
	assert_true(queued.ok, queued.error)
	var types := queued.events.map(func(ev: Dictionary) -> String: return ev["type"])
	assert_true(GalaxyEvents.MEGAPROJECT_STARTED in types)
	assert_eq(e.state.resources["a"]["credits"], credits - 120, "paid up front")
	assert_false(e.submit(QueueBuildCommand.new("a", "home_a", "building", "trade_hub")).ok, "the system is busy")
	var completed := false
	for i in 8:
		e.submit(EndFactionTurnCommand.new("a"))
		var r := e.submit(EndFactionTurnCommand.new("b"))
		for ev in r.events:
			completed = completed or ev["type"] == GalaxyEvents.MEGAPROJECT_COMPLETED
		if i < 6:
			assert_true(home.megaprojects.is_empty(), "not done after %d turns" % (i + 1))
	assert_true("stellar_forge" in home.megaprojects)
	assert_true(completed, "a completion event announces it")
	assert_true(home.queue.is_empty())
	var after := EmpireRules.planet_yields(e, home)
	assert_true(int(after["alloys"]) >= int(before.get("alloys", 0)) + 8, "+8 alloys here (and +10% on top)")
	assert_true(_option(e, "second_a", "stellar_forge").is_empty(), "one per empire")


func test_megaprojects_are_unique() -> void:
	var e := _wonders(["stellar_engineering", "interstellar_banking"], ["interstellar_banking"])
	assert_true(e.submit(QueueBuildCommand.new("a", "home_a", "megaproject", "stellar_forge")).ok)
	var dup := e.submit(QueueBuildCommand.new("a", "second_a", "megaproject", "stellar_forge"))
	assert_false(dup.ok, "already being built in another system")
	assert_true("home_a" in dup.error or "Already being built" in dup.error, dup.error)
	# A one-per-galaxy project: the first to start blocks everyone else.
	assert_true(e.submit(QueueBuildCommand.new("a", "second_a", "megaproject", "galactic_exchange")).ok)
	e.submit(EndFactionTurnCommand.new("a"))
	var rival := _option(e, "home_b", "galactic_exchange")
	assert_false(rival.is_empty())
	assert_false(rival["ok"], "someone is already building it")
	assert_false(e.submit(QueueBuildCommand.new("b", "home_b", "megaproject", "galactic_exchange")).ok)
	# Finished: nobody can start a second one, even in another empire.
	e.state.planets["second_a"].queue = {}
	e.state.planets["second_a"].megaprojects.append("galactic_exchange")
	assert_eq(EmpireRules.megaproject_error(e, e.state.planets["home_b"], "galactic_exchange"), "Already built at %s" % e.state.planets["second_a"].name)
	assert_true(_option(e, "home_b", "galactic_exchange").is_empty() or not _option(e, "home_b", "galactic_exchange")["ok"])


func test_megaproject_effects_and_capture() -> void:
	var e := _wonders([])
	var home: Planet = e.state.planets["home_a"]
	home.megaprojects.append("fleet_command_nexus")
	assert_eq(int(EmpireRules.modifier(e, "a", "fleet_speed")), 1)
	assert_near(EmpireRules.modifier(e, "a", "field_repair"), 0.1, 0.0001)
	assert_eq(EmpireRules.hero_xp_per_turn(e, "a"), 10)
	assert_eq(EmpireRules.modifier(e, "b", "fleet_speed"), 0.0)
	var score_with := EmpireRules.score(e, "a")
	home.megaprojects.clear()
	assert_eq(score_with - EmpireRules.score(e, "a"), 150, "a wonder is worth 150 score")
	# Standing megaprojects pass to the conqueror.
	home.megaprojects.append("fleet_command_nexus")
	e._capture_planet(home, e.state.fleets_of("b")[0])
	assert_eq(home.owner, "b")
	assert_true("fleet_command_nexus" in home.megaprojects)
	assert_eq(int(EmpireRules.modifier(e, "b", "fleet_speed")), 1)
	assert_eq(int(EmpireRules.modifier(e, "a", "fleet_speed")), 0)


func test_galactic_exchange_boosts_trade_and_relations() -> void:
	var e := _wonders([])
	e.state.planets["home_a"].megaprojects.append("galactic_exchange")
	assert_eq(int(EmpireRules.modifier(e, "a", "trade_income")), 3)
	assert_eq(int(EmpireRules.modifier(e, "a", "opinion_drift")), 1)
	assert_eq(EmpireRules.planet_yields(e, e.state.planets["home_a"])["credits"], 5 + 10)


# --- AI -----------------------------------------------------------------------

func test_ai_builds_unlocked_megaprojects() -> void:
	var e := _wonders(["archival_science"])
	var choice := GalaxyAI.new().choose_build(e, e.state.planets["home_a"])
	assert_eq(choice.get("kind", ""), "megaproject")
	assert_eq(choice.get("id", ""), "grand_archive")


func test_ai_saves_up_for_a_megaproject() -> void:
	var poor := _two({"techs": {"a": ["stellar_engineering"]}, "planets": _wonder_planets(),
			"resources": {"a": {"credits": 100, "alloys": 100}}})
	var choice := GalaxyAI.new().choose_build(poor, poor.state.planets["home_a"])
	assert_ne(choice.get("kind", ""), "unit", "no ships while saving")
	assert_ne(choice.get("kind", ""), "megaproject", "can't pay for it yet")


func test_ai_researches_growth_before_military() -> void:
	var e := _two({"relations": [{"factions": ["a", "b"], "status": "peace", "opinion": 20}]})
	var cmd := GalaxyAI.new().decide(e)
	assert_true(cmd is SetResearchCommand)
	assert_eq((cmd as SetResearchCommand).tech_id, "hydroponics", "at peace: growth first")


func test_ai_researches_weapons_when_outgunned() -> void:
	var e := Fixtures.galaxy([["a", "test_dummy", 1, 2], ["b", "frigate", 8, 2], ["b", "frigate", 8, 3]])
	var cmd := GalaxyAI.new().decide(e)
	assert_true(cmd is SetResearchCommand)
	assert_eq((cmd as SetResearchCommand).tech_id, "reinforced_hulls", "at war with a stronger enemy: military first")


func test_ai_does_not_build_ships_it_cannot_afford_to_keep() -> void:
	var fleets: Array = [["b", "test_dummy", 8, 2]]
	for i in 8:
		fleets.append(["a", "frigate", 0 + i % 3, 2 + i / 3])
	var e := Fixtures.galaxy(fleets, _rich({"planets": [
		{"id": "home_a", "at": [0, 5], "owner": "a", "bodies": [{"type": "terran", "buildings": ["colony", "shipyard"]}]},
		{"id": "home_b", "at": [9, 5], "owner": "b", "bodies": [{"type": "desert", "buildings": ["colony"]}]}]}))
	# 16 credits of upkeep against a 5-credit allowance and 5 credits of taxes.
	assert_true(int(EmpireRules.income(e, "a")["credits"]) < 0)
	var ai := GalaxyAI.new()
	assert_false(ai._can_support(e, "a", "frigate", false))
	assert_false(ai._can_support(e, "a", "interceptor", false))
