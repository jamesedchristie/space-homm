extends TestCase
## Strategic resources and deposits: rolls by body type, the Solar Age spread, extraction,
## strategic costs (paid, blocked, scaled), extractor developments, surveys, the AI and saves.
## Fixture galaxy (Fixtures.campaign): home_a (terran colony, barren rock, gas giant), home_b
## (desert colony, asteroid belt), middle (ice moon, arctic world; unclaimed).

var _data: DataRegistry


func before_each() -> void:
	_data = DataRegistry.get_default()


func _end_round(e: GalaxyEngine) -> void:
	var start := e.current_faction_id()
	e.submit(EndFactionTurnCommand.new(start))
	while e.current_faction_id() != start and not e.state.is_over:
		e.submit(EndFactionTurnCommand.new(e.current_faction_id()))


func _constructor(planet: Planet, owner: String, uid: String = "c1") -> Dictionary:
	var c := {"uid": uid, "unit": "constructor", "name": "Jack", "hull": 45, "owner": owner, "loc": "", "job": {}}
	planet.civilians.append(c)
	return c


# --- Rolls --------------------------------------------------------------------

func test_strategic_resources_are_data() -> void:
	assert_eq(DepositRules.strategic(_data), ["volatiles", "rare_elements", "exotic_matter"] as Array[String])
	assert_true("credits" in DepositRules.stockpiled(_data) and "exotic_matter" in DepositRules.stockpiled(_data))
	assert_false("research" in DepositRules.stockpiled(_data), "research flows, it isn't stockpiled")
	assert_true(DepositRules.uses(GalaxyEngine.from_campaign(_data, "solar_age", 1), "exotic_matter").has("Hyperdrive"))


func test_rolls_are_deterministic_and_follow_the_body_type() -> void:
	var counts := {}
	for type: String in ["gas_giant", "ice_moon", "volcanic", "terran"]:
		counts[type] = {}
		var a := RandomNumberGenerator.new()
		a.seed = 42
		var b := RandomNumberGenerator.new()
		b.seed = 42
		for i in 300:
			var d := DepositRules.roll(_data, type, a)
			assert_eq(d, DepositRules.roll(_data, type, b), "same dice, same deposits")
			assert_true(d.size() <= 2)
			for k: String in d:
				assert_true(int(d[k]) >= 1 and int(d[k]) <= 3, "richness 1-3")
				counts[type][k] = int(counts[type].get(k, 0)) + 1
	assert_false(counts["gas_giant"].has("rare_elements"), "gas giants hold no rare elements")
	assert_true(int(counts["gas_giant"].get("volatiles", 0)) > 200, "but nearly always volatiles")
	assert_true(int(counts["volcanic"].get("rare_elements", 0)) > 180, "volcanic worlds: rare elements")
	assert_false(counts["volcanic"].has("volatiles"))
	assert_true(int(counts["terran"].get("rare_elements", 0)) + int(counts["terran"].get("volatiles", 0)) < 80, "garden worlds seldom")
	# The engine rolls the same deposits for the same seed, and home systems stay fair.
	var e1 := GalaxyEngine.from_campaign(_data, "random_sector", 5)
	var e2 := GalaxyEngine.from_campaign(_data, "random_sector", 5)
	var any := false
	for id: String in e1.state.planets:
		var p1: Planet = e1.state.planets[id]
		for i in p1.bodies.size():
			assert_eq(DepositRules.of(p1.bodies[i]), DepositRules.of(e2.state.planets[id].bodies[i]))
			any = any or not DepositRules.of(p1.bodies[i]).is_empty()
		if not p1.capital.is_empty() or not p1.owner.is_empty():
			for b in p1.bodies:
				assert_false(DepositRules.of(b).has("exotic_matter"), "no jackpots at home")
				for k: String in DepositRules.of(b):
					assert_eq(int(DepositRules.of(b)[k]), 1, "a modest starter deposit")
	assert_true(any, "the sector has deposits")


func test_hand_placed_deposits_are_kept() -> void:
	var planets := [
		{"id": "home_a", "at": [0, 5], "owner": "a", "bodies": [{"type": "terran", "buildings": ["colony"]}]},
		{"id": "home_b", "at": [9, 5], "owner": "b", "bodies": [{"type": "desert", "buildings": ["colony"]}]},
		{"id": "middle", "at": [5, 3], "bodies": [{"type": "ice_moon", "deposits": {"exotic_matter": 3}}, {"type": "barren", "deposits": {}}]},
	]
	var e := Fixtures.galaxy([["a", "test_dummy", 1, 2], ["b", "test_dummy", 8, 2]], {"planets": planets})
	assert_eq(DepositRules.of(e.state.planets["middle"].bodies[0]), {"exotic_matter": 3})
	assert_eq(DepositRules.of(e.state.planets["middle"].bodies[1]), {})


func test_solar_age_spreads_deposits_sensibly() -> void:
	for seed_value in [1, 2, 3, 4, 5, 6]:
		var e := GalaxyEngine.from_campaign(_data, "solar_age", seed_value)
		var s := e.state
		var home := s.home_planet("patrol")
		assert_true(DepositRules.of(home.bodies[0]).is_empty(), "seed %d: nothing on the homeworld" % seed_value)
		var exotic: Array[Planet] = []
		var volatiles_near := false
		var rare_out := 0
		for p: Planet in s.planets.values():
			var d := DepositRules.of(p.bodies[0])
			var dist := s.grid.distance(p.cell, home.cell)
			if d.has("exotic_matter"):
				exotic.append(p)
			if d.has("volatiles") and dist <= 5 and p != home:
				volatiles_near = true
			if d.has("rare_elements") and dist >= 3:
				rare_out += 1
		assert_eq(exotic.size(), 1, "seed %d: exotic matter in one place" % seed_value)
		var site: Planet = exotic[0]
		assert_true(s.grid.distance(site.cell, home.cell) >= 6, "seed %d: out in the contested dark" % seed_value)
		assert_true(site.owner.is_empty(), "seed %d: free to claim (once you get there)" % seed_value)
		assert_false(EmpireRules.is_habitable(e, site.bodies[0]), "seed %d: a containment can go there" % seed_value)
		assert_true(volatiles_near, "seed %d: volatiles near home" % seed_value)
		assert_true(rare_out >= 2, "seed %d: rare elements a bit farther out" % seed_value)


# --- Extraction ---------------------------------------------------------------

func test_developments_extract_their_bodys_deposits() -> void:
	var e := Fixtures.galaxy([["a", "test_dummy", 1, 2], ["b", "test_dummy", 8, 2]])
	var home: Planet = e.state.planets["home_a"]
	var rock: Dictionary = home.bodies[1]
	rock["deposits"] = {"rare_elements": 2}
	assert_true(EmpireRules.body_yields(e, rock, "a").is_empty(), "an untapped deposit yields nothing")
	rock["buildings"].assign(["mining_base"])
	var y := EmpireRules.body_yields(e, rock, "a")
	assert_eq(int(y.get("rare_elements", 0)), 2, "mining base on rare elements x2: +2 a turn")
	assert_eq(int(y.get("alloys", 0)), 4, "on top of its normal yield")
	rock["buildings"].assign(["research_station"])
	assert_false(EmpireRules.body_yields(e, rock, "a").has("rare_elements"), "a research station taps nothing")
	rock["buildings"].assign(["mining_base"])
	var gas: Dictionary = home.bodies[2]
	gas["deposits"] = {"volatiles": 3}
	gas["buildings"].assign(["gas_refinery"])
	var income := EmpireRules.income(e, "a")
	assert_eq(int(income["rare_elements"]), 2)
	assert_eq(int(income["volatiles"]), 3)
	var before: int = e.state.resources["a"]["rare_elements"]
	_end_round(e)
	assert_eq(int(e.state.resources["a"]["rare_elements"]), before + 2, "stockpiled each turn")
	# A blockade stops extraction too.
	home.blockade = "b"
	assert_eq(int(EmpireRules.income(e, "a")["rare_elements"]), 0)


func test_extractors_need_their_deposit_and_exotic_containment_replaces() -> void:
	var e := Fixtures.galaxy([["a", "test_dummy", 1, 2], ["b", "test_dummy", 8, 2]],
			{"resources": {"a": {"credits": 900, "alloys": 900}}})
	var middle: Planet = e.state.planets["middle"]
	var ice: Dictionary = middle.bodies[0]
	ice["deposits"] = {}
	var ids := func(b: Dictionary) -> Array: return EmpireRules.constructor_options(e, "a", b).map(func(o: Dictionary) -> String: return o["id"])
	assert_false("ice_mine" in ids.call(ice), "no deposit, no ice mine")
	ice["deposits"] = {"volatiles": 2, "exotic_matter": 1}
	assert_true("ice_mine" in ids.call(ice))
	assert_false("exotic_containment" in ids.call(ice), "needs Exotic Physics")
	assert_eq(SystemRules.default_job(e, "a", ice), "ice_mine", "the constructor taps the deposit by default")
	e.state.research["a"]["known"].append("exotic_physics")
	assert_eq(SystemRules.default_job(e, "a", ice), "exotic_containment", "the rarer deposit first")
	# Built over a research station: the station goes.
	ice["buildings"].assign(["research_station"])
	middle.owner = "a"
	assert_eq(ids.call(ice), ["exotic_containment"], "only a development that may replace it")
	var c := _constructor(middle, "a")
	assert_true(e.submit(CivilianCommand.new("a", "middle", c["uid"], CivilianCommand.JOB, ice["id"], "exotic_containment")).ok)
	for i in 4:
		_end_round(e)
	assert_eq(ice["buildings"], ["exotic_containment"] as Array[String])
	assert_eq(int(EmpireRules.body_yields(e, ice, "a").get("exotic_matter", 0)), 1)
	assert_true(DepositRules.is_tapped(_data, ice, "exotic_matter"))
	assert_false(DepositRules.is_tapped(_data, ice, "volatiles"))


# --- Costs --------------------------------------------------------------------

func test_strategic_costs_are_paid_or_name_whats_missing() -> void:
	var e := Fixtures.galaxy([["a", "test_dummy", 1, 2], ["b", "test_dummy", 8, 2]],
			{"resources": {"a": {"credits": 900, "alloys": 900, "rare_elements": 3}}, "techs": {"a": ["heavy_hulls"]}})
	var home: Planet = e.state.planets["home_a"]
	home.add_building(home.bodies[0]["id"], "shipyard")
	var destroyer: Dictionary = EmpireRules.build_options(e, home).filter(func(o: Dictionary) -> bool: return o["id"] == "destroyer")[0]
	var need := int(_data.units["destroyer"]["strategic"]["cost"]["rare_elements"])
	assert_eq(int(destroyer["cost"]["rare_elements"]), need)
	assert_false(destroyer["ok"])
	assert_eq(destroyer["reason"], "Not enough rare elements (%d needed, 3 in store)" % need)
	assert_true(EmpireRules.lacks_resources(destroyer["reason"]))
	var result := e.submit(QueueBuildCommand.new("a", "home_a", "unit", "destroyer"))
	assert_false(result.ok)
	assert_true(result.error.contains("rare elements"), result.error)
	e.state.resources["a"]["rare_elements"] = need + 2
	assert_true(e.submit(QueueBuildCommand.new("a", "home_a", "unit", "destroyer")).ok)
	assert_eq(int(e.state.resources["a"]["rare_elements"]), 2, "paid up front")
	# Galaxy-scale campaigns can ask less ("strategic_cost_mul"); basic costs are untouched.
	e.campaign["strategic_cost_mul"] = 0.5
	var scaled := EmpireRules.cost_of(e, _data.units["destroyer"]["strategic"]["cost"])
	assert_eq(int(scaled["rare_elements"]), roundi(need * 0.5))
	assert_eq(int(scaled["alloys"]), int(_data.units["destroyer"]["strategic"]["cost"]["alloys"]))
	assert_eq(_data.campaigns["random_sector"].get("strategic_cost_mul", 1.0), 0.5)


func test_major_powers_start_with_a_little() -> void:
	var e := GalaxyEngine.from_campaign(_data, "solar_age", 2)
	var start: Dictionary = _data.economy["deposits"]["start_stock"]
	assert_eq(int(e.state.resources["patrol"]["volatiles"]), int(start["volatiles"]))
	assert_eq(int(e.state.resources["patrol"]["exotic_matter"]), 0)
	assert_eq(int(e.state.resources["separatists"].get("volatiles", 0)), 0, "raiders don't stockpile")


# --- Surveys ------------------------------------------------------------------

func test_deposits_stay_hidden_until_surveyed() -> void:
	var e := GalaxyEngine.from_campaign(_data, "solar_age", 3)
	e.start()
	var s := e.state
	var site: Planet = null
	for p: Planet in s.planets.values():
		if DepositRules.of(p.bodies[0]).has("exotic_matter"):
			site = p
	assert_false(e.is_surveyed("patrol", site))
	assert_true(e.known_deposits("patrol", site, site.bodies[0]).is_empty(), "unsurveyed: nothing known")
	assert_true(e.known_deposits("patrol", s.home_planet("patrol"), s.home_planet("patrol").bodies[0]).is_empty())
	s.surveyed["patrol"][site.id] = true
	assert_eq(e.known_deposits("patrol", site, site.bodies[0]), DepositRules.of(site.bodies[0]))
	# Without surveys, everything is known.
	var drift := GalaxyEngine.from_campaign(_data, "the_drift", 3)
	for p: Planet in drift.state.planets.values():
		for b in p.bodies:
			assert_eq(drift.known_deposits("patrol", p, b), DepositRules.of(b))


# --- AI -----------------------------------------------------------------------

func test_ai_sends_constructors_to_extract_what_hyperdrive_needs() -> void:
	var e := GalaxyEngine.from_campaign(_data, "solar_age", 3)
	e.start()
	var s := e.state
	var site: Planet = null
	for p: Planet in s.planets.values():
		if DepositRules.of(p.bodies[0]).has("exotic_matter"):
			site = p
	s.research["patrol"]["known"].append_array(["scientific_method", "exotic_physics"])
	s.surveyed["patrol"][site.id] = true
	s.resources["patrol"]["credits"] = 500
	s.resources["patrol"]["alloys"] = 500
	assert_eq(GalaxyAI.strategic_need(e, "patrol").get("exotic_matter", 0.0), GalaxyAI.NEED_WEIGHT,
			"Hyperdrive needs exotic matter the AI doesn't have")
	# Clear the way: no raiders about, the site and its den out of the picture.
	for f in s.fleets.values():
		if f.owner != "patrol":
			s.fleets.erase(f.id)
	var ctor := _constructor(site, "patrol", "worker")
	s.research["patrol"]["current"] = "hydroponics"
	var ai := GalaxyAI.new()
	var chosen: CivilianCommand = null
	for i in 30:
		var cmd := ai.decide(e)
		if cmd is CivilianCommand and (cmd as CivilianCommand).ship_uid == "worker":
			chosen = cmd
			break
		if cmd is EndFactionTurnCommand:
			break
		assert_true(e.submit(cmd).ok)
	assert_true(chosen != null, "the constructor at the site gets an order")
	assert_eq(chosen.action, CivilianCommand.JOB)
	assert_eq(chosen.item_id, "exotic_containment")
	assert_eq(ctor["uid"], "worker")
	# And once Hyperdrive's era is open, it holds back what Hyperdrive will burn.
	assert_true(GalaxyAI.strategic_reserve(e, "patrol").is_empty(), "not in sight yet: colony ships may use volatiles")
	for tech_id: String in _data.techs:
		if ResearchRules.era_of(e, tech_id) < 3 and tech_id not in s.known_techs("patrol"):
			s.research["patrol"]["known"].append(tech_id)
	s.resources["patrol"]["volatiles"] = 10
	var reserve := GalaxyAI.strategic_reserve(e, "patrol")
	assert_true(int(reserve.get("volatiles", 0)) > 10)
	assert_true(GalaxyAI._spends_reserve(e, "patrol", {"volatiles": 8}), "a colony ship would eat the hyperdrive fuel")


func test_ai_taps_deposits_in_solar_age() -> void:
	var e := GalaxyEngine.from_campaign(_data, "solar_age", 2)
	CampaignAutoRunner.run(e, 500)
	var tapped := 0
	for p in e.state.planets_of("patrol"):
		for b in p.bodies:
			for k: String in DepositRules.of(b):
				if DepositRules.is_tapped(_data, b, k):
					tapped += 1
	assert_true(tapped >= 1, "constructors build extractors (turn %d, %d tapped)" % [e.state.turn_number, tapped])
	var income := EmpireRules.income(e, "patrol")
	assert_true(int(income["volatiles"]) + int(income["rare_elements"]) > 0)


# --- Saves --------------------------------------------------------------------

func test_deposits_and_stockpiles_survive_a_save() -> void:
	var e := GalaxyEngine.from_campaign(_data, "solar_age", 4)
	e.start()
	e.state.resources["patrol"]["exotic_matter"] = 7
	var save := GalaxySave.to_dict(e, "solar_age")
	assert_eq(int(save["version"]), 6)
	var loaded: Dictionary = GalaxySave.from_dict(_data, save)
	var e2: GalaxyEngine = loaded["engine"]
	assert_eq(int(e2.state.resources["patrol"]["exotic_matter"]), 7)
	for id: String in e.state.planets:
		assert_eq(DepositRules.of(e2.state.planets[id].bodies[0]), DepositRules.of(e.state.planets[id].bodies[0]))
	# A version 5 save (before strategic resources) loads with none.
	var old := save.duplicate(true)
	old["version"] = 5
	for p_d: Dictionary in old["state"]["planets"]:
		for b: Dictionary in p_d["bodies"]:
			b.erase("deposits")
	for f: String in old["state"]["resources"]:
		for k in DepositRules.strategic(_data):
			old["state"]["resources"][f].erase(k)
	var e3: GalaxyEngine = GalaxySave.from_dict(_data, old)["engine"]
	assert_eq(int(e3.state.resources["patrol"]["exotic_matter"]), 0)
	assert_eq(DepositRules.of(e3.state.home_planet("patrol").bodies[0]), {})
