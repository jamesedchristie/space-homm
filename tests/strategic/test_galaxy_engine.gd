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


func test_capture_planet() -> void:
	var e := Fixtures.galaxy([["a", "test_fast_dummy", 2, 3], ["b", "test_dummy", 9, 0]])
	var f := _fleet_of(e, "a")
	var result := e.submit(MoveFleetCommand.new("a", f.id, _cell(e, 5, 3)))
	assert_true(result.ok, result.error)
	assert_eq(e.state.planets["middle"].owner, "a")
	var types := result.events.map(func(ev: Dictionary) -> String: return ev["type"])
	assert_true(GalaxyEvents.PLANET_CAPTURED in types)


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


func test_ai_campaign_finishes_deterministically() -> void:
	var data := DataRegistry.get_default()
	var a := CampaignAutoRunner.run(GalaxyEngine.from_campaign(data, "the_drift", 2024))
	var b := CampaignAutoRunner.run(GalaxyEngine.from_campaign(data, "the_drift", 2024))
	assert_ne(a["winner"], "", "campaign should end with a winner (turns: %d)" % a["turns"])
	assert_true(a["battles"] > 0)
	assert_eq(a, b, "same seed, same campaign")
