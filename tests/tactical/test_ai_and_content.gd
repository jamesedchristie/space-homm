extends TestCase
## Whole-system checks against the real content in res://data.


func test_content_is_valid() -> void:
	var data := DataRegistry.new()
	data.load_from(DataRegistry.DEFAULT_ROOT)
	assert_eq(data.errors.size(), 0, "\n".join(data.errors))
	var effect_problems := EffectRegistry.validate_content(data)
	assert_eq(effect_problems.size(), 0, "\n".join(effect_problems))
	assert_true(data.units.has("frigate") and data.units.has("interceptor"))
	assert_true(data.scenarios.has("first_skirmish"))


func test_ai_battle_finishes() -> void:
	var data := DataRegistry.get_default()
	var engine := BattleEngine.from_scenario(data, "first_skirmish", 777)
	var result := AutoResolver.resolve(engine)
	assert_true(engine.state.is_over, "battle should end (rounds: %d)" % result["rounds"])
	assert_true(result["winner"] != BattleState.NO_WINNER)
	assert_true(result["rounds"] < 40, "should end by elimination, took %d rounds" % result["rounds"])


func test_same_seed_same_battle() -> void:
	var data := DataRegistry.get_default()
	var a := AutoResolver.resolve(BattleEngine.from_scenario(data, "first_skirmish", 4242))
	var b := AutoResolver.resolve(BattleEngine.from_scenario(data, "first_skirmish", 4242))
	assert_eq(a["winner"], b["winner"])
	assert_eq(a["rounds"], b["rounds"])
	assert_eq(a["history"], b["history"], "replays must be deterministic")


func test_ai_closes_distance_when_nothing_in_range() -> void:
	var e := Fixtures.engine("test_wall", [[0, "test_fast_dummy", 0, 2], [1, "test_dummy", 8, 2]])
	e.start()
	var u := e.state.active_unit()
	var enemy := e.state.living_enemies_of(u)[0]
	var before := e.state.grid.distance(u.cell, enemy.cell)
	var cmd := RuleBasedAI.new().decide(e)
	assert_true(cmd is MoveCommand, "should move, got %s" % cmd.type_name())
	e.submit(cmd)
	assert_true(e.state.grid.distance(u.cell, enemy.cell) < before)


func test_ai_attacks_when_in_range() -> void:
	var e := Fixtures.engine("test_open", [[0, "test_fast_dummy", 0, 0], [1, "test_dummy", 2, 0]])
	e.start()
	var cmd := RuleBasedAI.new().decide(e)
	assert_true(cmd is UseAbilityCommand)
	assert_eq((cmd as UseAbilityCommand).ability_id, "test_zap")
