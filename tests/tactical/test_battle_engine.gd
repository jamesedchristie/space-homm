extends TestCase
## Rules tests using Fixtures' fixed-number test units. Layout coords are
## [col, row]; test_open is a 10x6 empty hex field.


func _engine(units: Array, objectives: Array = []) -> BattleEngine:
	var e := Fixtures.engine("test_open", units, 12345, objectives)
	e.start()
	return e


func _cell(e: BattleEngine, col: int, row: int) -> Vector2i:
	return e.state.grid.cell_from_layout(Vector2i(col, row))


func test_initiative_order() -> void:
	var e := _engine([[0, "test_dummy", 0, 0], [1, "test_fast_dummy", 5, 0]])
	assert_eq(e.state.active_unit().def_id, "test_fast_dummy", "higher initiative acts first")
	assert_eq(e.state.round_number, 1)


func test_turn_rotation_and_rounds() -> void:
	var e := _engine([[0, "test_dummy", 0, 0], [1, "test_fast_dummy", 5, 0]])
	var first := e.state.active_unit_id
	assert_true(e.submit(EndTurnCommand.new(first)).ok)
	assert_ne(e.state.active_unit_id, first)
	assert_true(e.submit(EndTurnCommand.new(e.state.active_unit_id)).ok)
	assert_eq(e.state.round_number, 2)
	assert_eq(e.state.active_unit_id, first)


func test_move_spends_ap() -> void:
	var e := _engine([[0, "test_fast_dummy", 0, 0], [1, "test_dummy", 9, 5]])
	var u := e.state.active_unit()
	var dest := _cell(e, 2, 0)
	var result := e.submit(MoveCommand.new(u.id, dest))
	assert_true(result.ok, result.error)
	assert_eq(u.cell, dest)
	assert_eq(u.ap, 2)
	assert_eq(result.events[0]["type"], BattleEvents.UNIT_MOVED)


func test_rejects_illegal_commands() -> void:
	var e := _engine([[0, "test_fast_dummy", 0, 0], [1, "test_dummy", 9, 5]])
	var u := e.state.active_unit()
	var other := e.state.living_enemies_of(u)[0]
	assert_false(e.submit(EndTurnCommand.new(other.id)).ok, "not their turn")
	assert_false(e.submit(MoveCommand.new(u.id, _cell(e, 6, 0))).ok, "too far")
	assert_false(e.submit(UseAbilityCommand.new(u.id, "test_zap", other.cell)).ok, "out of range")
	assert_false(e.submit(UseAbilityCommand.new(u.id, "railgun", other.cell)).ok, "ability not owned")


func test_zap_damages_shields_then_hull() -> void:
	var e := _engine([[0, "test_fast_dummy", 0, 0], [1, "test_dummy", 2, 0]])
	var u := e.state.active_unit()
	var target := e.state.living_enemies_of(u)[0]
	assert_true(e.submit(UseAbilityCommand.new(u.id, "test_zap", target.cell)).ok)
	assert_eq(target.shields, 10)
	assert_eq(target.hull, 50)
	assert_true(e.submit(UseAbilityCommand.new(u.id, "test_zap", target.cell)).ok)
	assert_eq(target.shields, 0)
	assert_eq(u.ap, 0)
	assert_false(e.submit(UseAbilityCommand.new(u.id, "test_zap", target.cell)).ok, "out of AP")


func test_preview_matches_fixed_damage() -> void:
	var e := _engine([[0, "test_fast_dummy", 0, 0], [1, "test_dummy", 2, 0]])
	var u := e.state.active_unit()
	var target := e.state.living_enemies_of(u)[0]
	var preview := e.preview_ability(u.id, "test_zap", target.cell)
	assert_eq(preview.size(), 1)
	assert_eq(preview[0]["shield_damage"], 10)
	assert_eq(preview[0]["hull_damage"], 0)
	assert_false(preview[0]["lethal"])


func test_skip_turn_status_and_cooldown() -> void:
	var e := _engine([[0, "test_dummy", 0, 0], [1, "test_fast_dummy", 3, 0]])
	# Fast dummy (team 1) acts first; pass so the dummy can stun it.
	e.submit(EndTurnCommand.new(e.state.active_unit_id))
	var stunner := e.state.active_unit()
	var victim := e.state.living_enemies_of(stunner)[0]
	assert_true(e.submit(UseAbilityCommand.new(stunner.id, "test_stun", victim.cell)).ok)
	assert_true(victim.has_flag("skip_turn"))
	assert_eq(stunner.cooldown_of("test_stun"), 2)
	var events := e.submit(EndTurnCommand.new(stunner.id)).events
	var types := events.map(func(ev: Dictionary) -> String: return ev["type"])
	assert_true(BattleEvents.TURN_SKIPPED in types, "victim should lose its turn")
	assert_false(victim.has_flag("skip_turn"), "disabled lasts exactly one turn")
	assert_eq(e.state.active_unit_id, stunner.id, "stunner acts again")
	assert_eq(stunner.cooldown_of("test_stun"), 1)
	assert_false(e.submit(UseAbilityCommand.new(stunner.id, "test_stun", victim.cell)).ok, "on cooldown")


func test_braced_lasts_until_own_next_turn() -> void:
	var e := _engine([[0, "test_dummy", 0, 0], [1, "test_fast_dummy", 3, 0]])
	e.submit(EndTurnCommand.new(e.state.active_unit_id))
	var u := e.state.active_unit()
	assert_true(e.submit(UseAbilityCommand.new(u.id, "brace_shields", u.cell)).ok)
	assert_true(u.find_status("braced") != null)
	e.submit(EndTurnCommand.new(u.id))
	assert_true(u.find_status("braced") != null, "still braced during enemy turn")
	e.submit(EndTurnCommand.new(e.state.active_unit_id))
	assert_eq(e.state.active_unit_id, u.id)
	assert_true(u.find_status("braced") == null, "expires at start of own next turn")


func test_area_damage_hits_friends_and_ends_battle() -> void:
	var e := _engine([[0, "test_dummy", 0, 0], [0, "test_dummy", 4, 3], [1, "test_fast_dummy", 5, 3]])
	e.submit(EndTurnCommand.new(e.state.active_unit_id))  # fast enemy passes
	var bomber := e.state.active_unit()
	var target_cell := _cell(e, 5, 3)
	var preview := e.preview_ability(bomber.id, "test_bomb", target_cell)
	assert_eq(preview.size(), 2, "enemy and adjacent ally are both in the blast")
	var result := e.submit(UseAbilityCommand.new(bomber.id, "test_bomb", target_cell))
	assert_true(result.ok, result.error)
	assert_true(e.state.is_over)
	assert_eq(e.state.winner, 0)
	assert_eq(result.events[result.events.size() - 1]["type"], BattleEvents.BATTLE_ENDED)
	assert_eq(e.state.living_units().size(), 1)


func test_survive_rounds_objective() -> void:
	var e := _engine([[0, "test_dummy", 0, 0], [1, "test_dummy", 9, 5]],
			[{"type": "survive_rounds", "team": 1, "rounds": 2}])
	for i in 4:
		e.submit(EndTurnCommand.new(e.state.active_unit_id))
	assert_true(e.state.is_over)
	assert_eq(e.state.winner, 1)
