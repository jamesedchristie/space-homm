extends TestCase
## Strategic rules. Fixtures.galaxy() builds a 10x6 map; test_dummy has
## speed 3 / sensor 1, test_fast_dummy speed 5 / sensor 3.


func _cell(e: GalaxyEngine, col: int, row: int) -> Vector2i:
	return e.state.grid.cell_from_layout(Vector2i(col, row))


func _fleet_of(e: GalaxyEngine, owner: String) -> Fleet:
	return e.state.fleets_of(owner)[0]


func test_start_state() -> void:
	var e := Fixtures.galaxy([["a", "test_dummy", 1, 2], ["b", "test_dummy", 8, 2]])
	assert_eq(e.state.turn_number, 1)
	assert_eq(e.current_faction_id(), "a")
	assert_eq(_fleet_of(e, "a").moves_left, 3)
	assert_eq(e.state.planets["home_a"].owner, "a")


func test_fog_of_war() -> void:
	var e := Fixtures.galaxy([["a", "test_fast_dummy", 1, 2], ["b", "test_dummy", 8, 2]])
	var vis := e.visible_cells("a")
	assert_true(vis.has(_cell(e, 3, 2)), "within sensor 3")
	assert_false(vis.has(_cell(e, 8, 2)), "enemy fleet is out of sight")
	assert_false(e.can_see_fleet("a", _fleet_of(e, "b")))
	assert_true(e.explored_cells("a").has(_cell(e, 4, 2)))
	assert_false(e.explored_cells("a").has(_cell(e, 9, 0)))


func test_move_spends_moves_and_reveals() -> void:
	var e := Fixtures.galaxy([["a", "test_fast_dummy", 1, 2], ["b", "test_dummy", 9, 0]])
	var f := _fleet_of(e, "a")
	var result := e.submit(MoveFleetCommand.new("a", f.id, _cell(e, 4, 2)))
	assert_true(result.ok, result.error)
	assert_eq(f.cell, _cell(e, 4, 2))
	assert_eq(f.moves_left, 2)
	assert_eq(result.events[0]["type"], GalaxyEvents.FLEET_MOVED)
	assert_true(e.explored_cells("a").has(_cell(e, 7, 2)), "moving reveals new space")


func test_illegal_moves_rejected() -> void:
	var e := Fixtures.galaxy([["a", "test_dummy", 1, 2], ["b", "test_dummy", 8, 2]])
	var mine := _fleet_of(e, "a")
	var theirs := _fleet_of(e, "b")
	assert_false(e.submit(MoveFleetCommand.new("a", theirs.id, _cell(e, 7, 2))).ok, "not my fleet")
	assert_false(e.submit(MoveFleetCommand.new("b", theirs.id, _cell(e, 7, 2))).ok, "not b's turn")
	assert_false(e.submit(MoveFleetCommand.new("a", mine.id, _cell(e, 6, 2))).ok, "too far")


func test_nebula_costs_two() -> void:
	var e := Fixtures.galaxy([["a", "test_dummy", 4, 0], ["b", "test_dummy", 9, 4]])
	var reach := e.reachable_for(_fleet_of(e, "a").id)
	assert_eq(reach[_cell(e, 5, 0)]["cost"], 2)


func test_turns_rotate_and_moves_reset() -> void:
	var e := Fixtures.galaxy([["a", "test_dummy", 1, 2], ["b", "test_dummy", 8, 2]])
	var f := _fleet_of(e, "a")
	e.submit(MoveFleetCommand.new("a", f.id, _cell(e, 2, 2)))
	assert_true(e.submit(EndFactionTurnCommand.new("a")).ok)
	assert_eq(e.current_faction_id(), "b")
	assert_eq(e.state.turn_number, 1)
	assert_true(e.submit(EndFactionTurnCommand.new("b")).ok)
	assert_eq(e.current_faction_id(), "a")
	assert_eq(e.state.turn_number, 2)
	assert_eq(f.moves_left, 3)


func test_entering_an_unclaimed_system_does_not_claim_it() -> void:
	var e := Fixtures.galaxy([["a", "test_fast_dummy", 2, 3], ["b", "test_dummy", 9, 0]])
	var f := _fleet_of(e, "a")
	var result := e.submit(MoveFleetCommand.new("a", f.id, _cell(e, 5, 3)))
	assert_true(result.ok, result.error)
	assert_eq(f.cell, _cell(e, 5, 3))
	assert_eq(e.state.planets["middle"].owner, "", "settlers and workers claim systems, not warships")
	var types := result.events.map(func(ev: Dictionary) -> String: return ev["type"])
	assert_false(GalaxyEvents.PLANET_CAPTURED in types)


func test_attack_visible_enemy_starts_battle() -> void:
	var e := Fixtures.galaxy([["a", "test_fast_dummy", 2, 2], ["b", "test_dummy", 4, 2]])
	var attacker := _fleet_of(e, "a")
	var defender := _fleet_of(e, "b")
	assert_true(defender.cell in e.attack_targets(attacker.id))
	var result := e.submit(MoveFleetCommand.new("a", attacker.id, defender.cell))
	assert_true(result.ok, result.error)
	assert_true(e.has_pending_battle())
	assert_eq(attacker.cell, _cell(e, 3, 2), "attacker stops next to the defender")
	assert_eq(attacker.moves_left, 0)
	assert_false(e.submit(EndFactionTurnCommand.new("a")).ok, "must resolve battle first")

	var scenario := e.pending_battle_scenario()
	assert_eq(scenario["teams"][0]["units"][0]["ref"], attacker.ships[0]["uid"])
	assert_eq(scenario["map"], "open_space")
	var events := e.auto_resolve_pending_battle()
	assert_false(e.has_pending_battle())
	assert_eq(events[0]["type"], GalaxyEvents.BATTLE_RESOLVED)
	assert_eq(e.state.fleets.size(), 1, "one side was destroyed")


func test_hidden_enemy_intercepts_move() -> void:
	# Sensor 1: the enemy two cells away is hidden until we bump into it.
	var e := Fixtures.galaxy([["a", "test_dummy", 0, 2], ["b", "test_dummy", 2, 2]])
	var f := _fleet_of(e, "a")
	assert_false(e.can_see_fleet("a", _fleet_of(e, "b")))
	var result := e.submit(MoveFleetCommand.new("a", f.id, _cell(e, 3, 2)))
	assert_true(result.ok, result.error)
	assert_eq(f.cell, _cell(e, 1, 2))
	assert_true(e.has_pending_battle())
	assert_true(result.events[result.events.size() - 1]["ambush"])


func test_battle_results_written_back() -> void:
	var e := Fixtures.galaxy([["a", "test_fast_dummy", 2, 2], ["b", "test_dummy", 4, 2]],
			{"planets": []})
	var attacker := _fleet_of(e, "a")
	e.submit(MoveFleetCommand.new("a", attacker.id, _fleet_of(e, "b").cell))
	var battle := BattleEngine.from_scenario(e.data, e.pending_battle_scenario(), 5)
	battle.start()
	for u: BattleUnit in battle.state.units.values():
		if u.team == 0:
			u.hull = 17
		else:
			u.alive = false
	battle.state.winner = 0
	battle.state.is_over = true
	var events := e.resolve_pending_battle(battle)
	assert_eq(attacker.ships[0]["hull"], 17, "damage carries over")
	assert_eq(e.state.fleets_of("b").size(), 0)
	var types := events.map(func(ev: Dictionary) -> String: return ev["type"])
	assert_true(GalaxyEvents.FLEET_DESTROYED in types)
	assert_true(e.state.is_over, "b has no fleets and no planets")
	assert_eq(e.state.winner, "a")


func test_damaged_ships_carry_hull_into_battle() -> void:
	var e := Fixtures.galaxy([["a", "test_fast_dummy", 2, 2], ["b", "test_dummy", 4, 2]])
	var attacker := _fleet_of(e, "a")
	attacker.ships[0]["hull"] = 9
	e.submit(MoveFleetCommand.new("a", attacker.id, _fleet_of(e, "b").cell))
	var battle := BattleEngine.from_scenario(e.data, e.pending_battle_scenario(), 5)
	for u: BattleUnit in battle.state.units.values():
		if u.ref == attacker.ships[0]["uid"]:
			assert_eq(u.hull, 9)
			assert_eq(u.shields, u.max_shields(), "shields recharge between battles")


func test_repair_at_friendly_planet() -> void:
	var e := Fixtures.galaxy([["a", "test_dummy", 1, 4], ["b", "test_dummy", 9, 0]])
	var f := _fleet_of(e, "a")
	e.submit(MoveFleetCommand.new("a", f.id, _cell(e, 0, 5)))
	f.ships[0]["hull"] = 10
	e.submit(EndFactionTurnCommand.new("a"))
	var result := e.submit(EndFactionTurnCommand.new("b"))
	assert_eq(f.ships[0]["hull"], 10 + ceili(50 * GalaxyEngine.REPAIR_RATE))
	var types := result.events.map(func(ev: Dictionary) -> String: return ev["type"])
	assert_true(GalaxyEvents.FLEET_REPAIRED in types)


func test_battle_map_follows_location() -> void:
	var e := Fixtures.galaxy([["a", "test_dummy", 1, 2], ["b", "test_dummy", 8, 2]])
	assert_eq(e.battle_map_for(_cell(e, 5, 0)), "nebula_cloud")
	assert_eq(e.battle_map_for(_cell(e, 3, 3)), "open_space")


func test_ai_campaign_is_deterministic() -> void:
	# The first ~1500 AI commands of a Random Sector game (a full game on the
	# big map takes minutes; tools/simulate_campaign.gd and the campaign smoke
	# test play whole games). Same seed, same game.
	var data := DataRegistry.get_default()
	var a := CampaignAutoRunner.run(GalaxyEngine.from_campaign(data, "random_sector", 2024), 1500)
	var b := CampaignAutoRunner.run(GalaxyEngine.from_campaign(data, "random_sector", 2024), 1500)
	assert_true(a["turns"] > 10, "the AI plays turns (got %d)" % a["turns"])
	assert_eq(a, b, "same seed, same campaign")


func test_moving_onto_own_fleet_merges() -> void:
	var e := Fixtures.galaxy([["a", "test_dummy", 1, 2], ["a", "test_fast_dummy", 3, 2], ["b", "test_dummy", 9, 0]])
	var fleets := e.state.fleets_of("a")
	var mover := fleets[0]
	var target := fleets[1]
	assert_true(e.reachable_for(mover.id).has(target.cell), "own fleet is a valid destination")
	var result := e.submit(MoveFleetCommand.new("a", mover.id, target.cell))
	assert_true(result.ok, result.error)
	assert_false(e.state.fleets.has(mover.id), "the mover is absorbed")
	assert_eq(target.ships.size(), 2)
	assert_true(GalaxyEvents.FLEETS_MERGED in result.events.map(func(ev: Dictionary) -> String: return ev["type"]))
	assert_true(target.moves_left <= 1, "merged fleet keeps the lower moves left")


func test_merge_limits() -> void:
	var e := Fixtures.galaxy([["a", "test_dummy", 1, 2], ["a", "test_dummy", 2, 2], ["b", "test_dummy", 9, 0]])
	var fleets := e.state.fleets_of("a")
	for i in EmpireRules.MAX_FLEET_SIZE - 1:
		fleets[1].ships.append(fleets[1].ships[0].duplicate())
	assert_false(e.reachable_for(fleets[0].id).has(fleets[1].cell), "no room: the fleet blocks instead")
	fleets[1].ships.resize(1)
	fleets[0].hero_id = "x"
	fleets[1].hero_id = "y"
	assert_false(e.can_merge(fleets[0], fleets[1]), "two commanders can't share a fleet")


func test_split_fleet() -> void:
	var e := Fixtures.galaxy([["a", "test_dummy", 1, 2], ["b", "test_dummy", 9, 0]])
	var fleet := _fleet_of(e, "a")
	fleet.ships.append({"uid": "extra", "unit": "test_fast_dummy", "name": "Extra", "hull": 10})
	var targets := e.split_targets(fleet.id)
	assert_false(targets.is_empty())
	var to: Vector2i = targets[0]
	assert_false(e.submit(SplitFleetCommand.new("a", fleet.id, [fleet.ships[0]["uid"], "extra"] as Array[String], to)).ok,
			"someone has to stay")
	var result := e.submit(SplitFleetCommand.new("a", fleet.id, ["extra"] as Array[String], to))
	assert_true(result.ok, result.error)
	assert_eq(fleet.ships.size(), 1)
	var detached := e.state.fleet_at(to)
	assert_true(detached != null and detached != fleet)
	assert_eq(detached.ships[0]["uid"], "extra")
	assert_eq(detached.moves_left, fleet.moves_left - e.state.grid.move_cost(to))
	assert_true(e.split_targets(fleet.id).is_empty(), "a one-ship fleet can't split")


func test_discovery_claimed_on_entry() -> void:
	var e := Fixtures.galaxy([["a", "test_fast_dummy", 1, 2], ["b", "test_dummy", 9, 0]])
	var f := _fleet_of(e, "a")
	var cell := _cell(e, 3, 2)
	e.state.discoveries["d1"] = {"id": "d1", "kind": "supply_cache", "cell": cell}
	var credits: int = e.state.resources["a"]["credits"]
	var result := e.submit(MoveFleetCommand.new("a", f.id, _cell(e, 4, 2)))
	assert_true(result.ok, result.error)
	var found := result.events.filter(func(ev: Dictionary) -> bool: return ev["type"] == GalaxyEvents.DISCOVERY_FOUND)
	assert_eq(found.size(), 1, "flying through claims it")
	assert_false(e.state.discoveries.has("d1"), "one-time")
	var r: Dictionary = found[0]["rewards"]
	assert_eq(e.state.resources["a"]["credits"], credits + int(r.get("credits", 0)))
	if r.has("item"):
		assert_true(r["item"] in e.state.inventory["a"])
	assert_eq(f.cell, _cell(e, 4, 2), "the move carries on")


func test_random_features_are_seeded() -> void:
	var data := DataRegistry.get_default()
	var a := GalaxyEngine.from_campaign(data, "the_drift", 77)
	var b := GalaxyEngine.from_campaign(data, "the_drift", 77)
	var c := GalaxyEngine.from_campaign(data, "the_drift", 78)
	var layout := func(e: GalaxyEngine) -> String:
		var cells := e.state.discoveries.values().map(func(d: Dictionary) -> String: return "%s@%s" % [d["kind"], d["cell"]])
		var traits := e.state.planets.values().map(func(p: Planet) -> String: return "%s:%s" % [p.id, p.bodies])
		return str(cells) + str(traits)
	assert_eq(a.state.discoveries.size(), 7)
	assert_eq(layout.call(a), layout.call(b), "same seed, same sector")
	assert_ne(layout.call(a), layout.call(c), "different seed, different finds")
	for p: Planet in a.state.planets.values():
		if not p.owner.is_empty():
			for body in p.bodies:
				assert_true(body["traits"].is_empty(), "home worlds stay fair")


func test_body_traits_change_yields_and_slots() -> void:
	var e := Fixtures.galaxy([["a", "test_dummy", 1, 2], ["b", "test_dummy", 9, 0]])
	var home: Planet = e.state.planets["home_a"]
	var colony: Dictionary = home.bodies[0]
	var rock: Dictionary = home.bodies[1]
	var base := EmpireRules.planet_yields(e, home)
	var slots := EmpireRules.colony_slots(e, colony)
	rock["traits"].append("rich_deposits")
	assert_eq(EmpireRules.planet_yields(e, home), base, "traits only pay once the body is developed")
	rock["buildings"].append("mining_base")
	assert_eq(EmpireRules.planet_yields(e, home).get("alloys", 0), int(base.get("alloys", 0)) + 4 + 2)
	colony["traits"].append("vast_continents")
	assert_eq(EmpireRules.colony_slots(e, colony), slots + 1)


func test_queue_without_body_accepts_any_body_that_fits() -> void:
	var e := Fixtures.galaxy([["a", "test_dummy", 1, 2], ["b", "test_dummy", 9, 0]], {"planets": [
		{"id": "home_a", "at": [0, 5], "owner": "a", "bodies": [
			{"type": "desert", "buildings": ["colony", "shipyard", "defense_platform"]},
			{"type": "terran", "buildings": ["colony"]}]},
		{"id": "home_b", "at": [9, 5], "owner": "b", "bodies": [{"type": "desert", "buildings": ["colony"]}]}]})
	e.state.resources["a"]["alloys"] = 100
	e.state.research["a"]["known"].append("orbital_defenses")
	var planet: Planet = e.state.planets["home_a"]
	var cmd := QueueBuildCommand.new("a", "home_a", "building", "trade_hub")
	assert_eq(e.validate(cmd), "", "the second colony has a free slot")
	assert_true(e.submit(cmd).ok)
	assert_eq(planet.queue.get("body", ""), planet.bodies[1]["id"])


func test_merge_target_filled_by_discovery_ship_blocks_instead_of_stacking() -> void:
	var e := Fixtures.galaxy([["a", "test_fast_dummy", 1, 2], ["a", "test_dummy", 4, 2], ["b", "test_dummy", 9, 0]])
	e.data.discoveries["test_ship"] = {"name": "Hulk", "outcomes": [{"weight": 1, "rewards": {"ship": "interceptor"}}]}
	var mover := e.state.fleets_of("a")[0]
	var other := e.state.fleets_of("a")[1]
	for i in EmpireRules.MAX_FLEET_SIZE - 2:
		mover.ships.append(mover.ships[0].duplicate())
	e.state.discoveries["d1"] = {"id": "d1", "kind": "test_ship", "cell": _cell(e, 3, 2)}
	assert_true(e.reachable_for(mover.id).has(other.cell), "merge looks possible before the find")
	var result := e.submit(MoveFleetCommand.new("a", mover.id, other.cell))
	assert_true(result.ok, result.error)
	assert_ne(mover.cell, other.cell, "two fleets must never share a cell")
	assert_true(e.state.fleets.has(mover.id), "no merge: it would exceed the fleet size")


func test_heroes_leave_a_lost_system() -> void:
	var e := Fixtures.galaxy([["a", "test_dummy", 1, 2], ["b", "test_dummy", 9, 0]], {"heroes": [
		{"id": "h", "class": "technician", "owner": "a", "planet": "home_a"}]})
	e.state.planets["middle"].owner = "a"
	e._capture_planet(e.state.planets["home_a"], _fleet_of(e, "b"))
	assert_eq(e.state.planets["home_a"].owner, "b")
	assert_eq(e.state.heroes["h"].planet_id, "middle", "the hero falls back to a system their faction still holds")
