extends TestCase
## Hand-to-hand abilities ("melee": true): they ignore cover, the AI uses them
## when adjacent, and the shipped melee content is well formed.
## Map: 8x6 "test_room" with a crate at (6, 5).


func _data() -> DataRegistry:
	var data := Fixtures.registry()
	data.abilities["test_stab"] = {
		"id": "test_stab", "name": "Stab", "ap_cost": 1, "target": "enemy", "range": [1, 1],
		"requires_los": true, "melee": true, "fx": "melee",
		"effects": [{"type": "damage", "amount": 10, "damage_type": "test_flat"}],
	}
	data.units["test_brawler"] = {
		"id": "test_brawler", "name": "Brawler",
		"stats": {"max_hull": 50, "max_shields": 20, "armor": 0, "initiative": 9, "max_ap": 4},
		"abilities": ["test_zap", "test_stab"],
	}
	data.units["test_stabber"] = {
		"id": "test_stabber", "name": "Stabber",
		"stats": {"max_hull": 50, "max_shields": 20, "armor": 0, "initiative": 9, "max_ap": 4},
		"abilities": ["test_stab"],
	}
	return data


func _engine(team0: Array, team1: Array) -> BattleEngine:
	var def := {"id": "t", "map": "test_room", "teams": [
		{"team": 0, "controller": "player", "units": team0},
		{"team": 1, "controller": "ai", "units": team1}]}
	var e := BattleEngine.from_scenario(_data(), def, 42)
	e.start()
	return e


func test_melee_ignores_cover_but_ranged_does_not() -> void:
	# The target stands at (5, 5) beside the crate (6, 5); the attacker at (6, 4)
	# is diagonal to it, on the crate's side, so the crate is half cover.
	var e := _engine([{"unit": "test_brawler", "at": [6, 4]}], [{"unit": "test_dummy", "at": [5, 5]}])
	var me := e.state.active_unit()
	var enemy := e.state.living_enemies_of(me)[0]
	assert_eq(CoverRules.evaluate(e.state, me.cell, enemy.cell)["cover"], CoverRules.HALF)
	var zap := e.preview_ability(me.id, "test_zap", enemy.cell)[0]
	var stab := e.preview_ability(me.id, "test_stab", enemy.cell)[0]
	assert_eq(zap["shield_damage"], 7, "ranged attack is reduced by half cover")
	assert_eq(stab["shield_damage"], 10, "melee ignores cover")
	assert_eq(stab["cover"]["cover"], "", "and the preview shows no cover")
	var result := e.submit(UseAbilityCommand.new(me.id, "test_stab", enemy.cell))
	assert_true(result.ok, result.error)
	assert_eq(enemy.shields, 10, "20 shields - 10 flat damage")


func test_melee_needs_an_adjacent_target() -> void:
	var e := _engine([{"unit": "test_stabber", "at": [4, 4]}], [{"unit": "test_dummy", "at": [6, 4]}])
	var me := e.state.active_unit()
	assert_eq(e.ability_targets(me.id, "test_stab").size(), 0, "two cells away")
	var e2 := _engine([{"unit": "test_stabber", "at": [4, 4]}], [{"unit": "test_dummy", "at": [5, 4]}])
	assert_eq(e2.ability_targets(e2.state.active_unit_id, "test_stab").size(), 1)


func test_ai_uses_melee_when_adjacent() -> void:
	var e := _engine([{"unit": "test_stabber", "at": [4, 4]}], [{"unit": "test_dummy", "at": [5, 4]}])
	var cmd := RuleBasedAI.new().decide(e)
	assert_true(cmd is UseAbilityCommand)
	assert_eq((cmd as UseAbilityCommand).ability_id, "test_stab")
	assert_eq((cmd as UseAbilityCommand).target, Vector2i(5, 4))


func test_ai_prefers_melee_against_covered_adjacent_target() -> void:
	# Zap does 7 through half cover for 2 AP; the stab does 10 for 1 AP.
	var e := _engine([{"unit": "test_brawler", "at": [6, 4]}], [{"unit": "test_dummy", "at": [5, 5]}])
	var cmd := RuleBasedAI.new().decide(e)
	assert_true(cmd is UseAbilityCommand)
	assert_eq((cmd as UseAbilityCommand).ability_id, "test_stab")


func test_ai_closes_in_to_use_a_melee_only_unit() -> void:
	var e := _engine([{"unit": "test_stabber", "at": [4, 4]}], [{"unit": "test_dummy", "at": [7, 4]}])
	var cmd := RuleBasedAI.new().decide(e)
	assert_true(cmd is MoveCommand, "walks up to its target")
	var dest: Vector2i = (cmd as MoveCommand).to
	assert_true(e.state.grid.distance(dest, Vector2i(7, 4)) <= 1, "ends adjacent: %s" % dest)


func test_shipped_melee_abilities_are_adjacent_and_flagged() -> void:
	var data := DataRegistry.get_default()
	var found := 0
	for id: String in data.abilities:
		var ability: Dictionary = data.abilities[id]
		if not ability.get("melee", false):
			continue
		found += 1
		assert_eq([int(ability["range"][0]), int(ability["range"][1])], [1, 1], "%s is adjacent-only" % id)
		assert_eq(ability.get("fx", ""), "melee", "%s plays the lunge" % id)
		assert_eq(int(ability.get("radius", 0)), 0, "%s hits one target" % id)
	assert_true(found >= 5, "marine, raider, infected and hero melee moves exist")
	assert_true("combat_knife" in data.units["marine"]["abilities"])
	assert_true("vibro_blade" in data.units["boarder"]["abilities"])
	assert_true("shield_bash" in HeroBuilder.skills_at(data.hero_classes["vanguard"], 1))


func test_real_marine_knife_ignores_cover() -> void:
	var def := {"id": "t", "map": "test_room", "teams": [
		{"team": 0, "controller": "player", "units": [{"unit": "marine", "at": [6, 4]}]},
		{"team": 1, "controller": "ai", "units": [{"unit": "boarder", "at": [5, 5]}]}]}
	var e := BattleEngine.from_scenario(Fixtures.registry(), def, 1)
	e.start()
	var me := e.state.living_units(0)[0]
	var enemy := e.state.living_units(1)[0]
	assert_eq(CoverRules.evaluate(e.state, me.cell, enemy.cell)["cover"], CoverRules.HALF)
	var burst := e.preview_ability(me.id, "rifle_burst", enemy.cell)[0]
	var knife := e.preview_ability(me.id, "combat_knife", enemy.cell)[0]
	var avg_burst := (12 + 16) / 2.0 * 0.7 * 0.5  # half cover, kinetic vs shields
	var avg_knife := (8 + 11) / 2.0 * 0.5
	assert_near(float(burst["shield_damage"]), avg_burst, 1.0)
	assert_near(float(knife["shield_damage"]), avg_knife, 1.0)
