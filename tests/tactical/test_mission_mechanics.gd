extends TestCase
## Fog of war, dormant groups, triggers and choices, reach objectives, cover,
## friendly targeting and permanent statuses, on the 8x6 "test_room" square map.


func _engine(def: Dictionary) -> BattleEngine:
	var e := BattleEngine.from_scenario(Fixtures.registry(), def, 42)
	e.start()
	return e


func _scenario(team0: Array, team1: Array, extra: Dictionary = {}) -> Dictionary:
	var def := {
		"id": "t", "map": "test_room",
		"teams": [
			{"team": 0, "controller": "player", "units": team0},
			{"team": 1, "controller": "ai", "units": team1},
		],
	}
	def.merge(extra, true)
	return def


func _types(events: Array[Dictionary]) -> Array:
	return events.map(func(ev: Dictionary) -> String: return ev["type"])


func test_fog_hides_and_untargets_enemies() -> void:
	var e := _engine(_scenario([{"unit": "test_fast_dummy", "at": [4, 4]}],
			[{"unit": "test_dummy", "at": [6, 4]}], {"fog": true}))
	var me := e.state.active_unit()
	var enemy := e.state.living_enemies_of(me)[0]
	assert_true(e.state.is_visible(0, enemy.cell))
	assert_true(enemy.cell in e.ability_targets(me.id, "test_zap"))
	me.base_stats["sight"] = 1.0
	e.state.version += 1
	assert_false(e.state.is_visible(0, enemy.cell), "out of sight range")
	assert_false(enemy.cell in e.ability_targets(me.id, "test_zap"), "can't shoot what you can't see")


func test_dormant_units_wait_then_wake_on_sight() -> void:
	var e := _engine(_scenario([{"unit": "test_fast_dummy", "at": [0, 5]}],
			[{"unit": "test_dummy", "at": [7, 0], "dormant": true, "group": "g"},
			 {"unit": "test_dummy", "at": [7, 1], "dormant": true, "group": "g"}], {"fog": true}))
	var me := e.state.active_unit()
	var result := e.submit(EndTurnCommand.new(me.id))
	assert_eq(e.state.active_unit_id, me.id, "dormant enemies skip their turns")
	assert_false(BattleEvents.TURN_STARTED in _types(result.events.slice(1)) and e.state.active_unit_id != me.id)
	# (2, 5) is within 6 of the group and below the wall, so they can see it.
	result = e.submit(MoveCommand.new(me.id, Vector2i(2, 5)))
	assert_true(result.ok, result.error)
	var alerts := result.events.filter(func(ev: Dictionary) -> bool: return ev["type"] == BattleEvents.UNIT_ALERTED)
	assert_eq(alerts.size(), 2, "spotting one wakes its whole group")


func test_damage_wakes_dormant_unit() -> void:
	var e := _engine(_scenario([{"unit": "test_fast_dummy", "at": [4, 4]}],
			[{"unit": "test_dummy", "at": [6, 4], "dormant": true}]))
	var me := e.state.active_unit()
	var enemy := e.state.living_enemies_of(me)[0]
	enemy.base_stats["sight"] = 0.0
	e.submit(UseAbilityCommand.new(me.id, "test_zap", enemy.cell))
	assert_true(enemy.alert)


func test_trigger_choice_blocks_until_answered() -> void:
	var trigger := {"id": "console", "team": 0, "cells": [[1, 4]], "text": "A console.",
		"choices": [
			{"label": "Hack", "effects": [{"type": "reward", "xp": 25, "items": ["medkit"]}]},
			{"label": "Leave", "effects": [{"type": "spawn", "units": [{"unit": "test_dummy", "at": [7, 5], "team": 1}]}]},
		]}
	var e := _engine(_scenario([{"unit": "test_fast_dummy", "at": [0, 4]}],
			[{"unit": "test_dummy", "at": [7, 0]}], {"triggers": [trigger]}))
	var me := e.state.active_unit()
	var result := e.submit(MoveCommand.new(me.id, Vector2i(1, 4)))
	assert_true(BattleEvents.TRIGGER_FIRED in _types(result.events))
	assert_false(e.state.pending_choice.is_empty())
	assert_false(e.submit(EndTurnCommand.new(me.id)).ok, "must choose first")
	var units_before := e.state.units.size()
	result = e.submit(ChooseOptionCommand.new(me.id, 1))
	assert_true(result.ok, result.error)
	assert_eq(e.state.units.size(), units_before + 1, "spawn effect adds a unit")
	assert_true(BattleEvents.UNIT_SPAWNED in _types(result.events))
	# Fired triggers don't fire again.
	e.submit(MoveCommand.new(me.id, Vector2i(0, 4)))
	result = e.submit(MoveCommand.new(me.id, Vector2i(1, 4)))
	assert_false(BattleEvents.TRIGGER_FIRED in _types(result.events))


func test_trigger_reward_recorded() -> void:
	var trigger := {"id": "cache", "team": 0, "cells": [[1, 4]],
		"effects": [{"type": "reward", "xp": 10, "trait": "survivor"}]}
	var e := _engine(_scenario([{"unit": "test_fast_dummy", "at": [0, 4]}],
			[{"unit": "test_dummy", "at": [7, 0]}], {"triggers": [trigger]}))
	e.submit(MoveCommand.new(e.state.active_unit_id, Vector2i(1, 4)))
	assert_eq(e.state.rewards.size(), 1)
	assert_eq(e.state.rewards[0]["xp"], 10)
	assert_true(e.state.pending_choice.is_empty(), "no choices, no wait")


func test_reach_cells_objective() -> void:
	var e := _engine(_scenario([{"unit": "test_fast_dummy", "at": [0, 4]}],
			[{"unit": "test_dummy", "at": [7, 0]}],
			{"objectives": [{"type": "reach_cells", "team": 0, "cells": [[2, 5]]}, {"type": "eliminate_all"}]}))
	assert_eq(e.state.objectives[0].marked_cells(), [Vector2i(2, 5)] as Array[Vector2i])
	e.submit(MoveCommand.new(e.state.active_unit_id, Vector2i(2, 5)))
	assert_true(e.state.is_over)
	assert_eq(e.state.winner, 0)


func test_cover_reduces_damage() -> void:
	var e := _engine(_scenario([{"unit": "test_fast_dummy", "at": [4, 5]}],
			[{"unit": "test_dummy", "at": [6, 5]}, {"unit": "test_dummy", "at": [6, 3]}]))
	var me := e.state.active_unit()
	var in_cover := e.preview_ability(me.id, "test_zap", Vector2i(6, 5))[0]
	var exposed := e.preview_ability(me.id, "test_zap", Vector2i(6, 3))[0]
	assert_eq(exposed["shield_damage"], 10)
	assert_eq(in_cover["shield_damage"], 7)


func test_friendly_targeting_includes_self() -> void:
	var data := Fixtures.registry()
	data.units["medic"] = {"id": "medic", "stats": {"max_hull": 50, "max_shields": 0, "armor": 0,
			"initiative": 9, "max_ap": 4}, "abilities": ["field_medic"]}
	var e := BattleEngine.from_scenario(data, _scenario([{"unit": "medic", "at": [0, 4]},
			{"unit": "test_dummy", "at": [1, 4]}], [{"unit": "test_dummy", "at": [7, 0]}]), 1)
	e.start()
	var me := e.state.active_unit()
	var targets := e.ability_targets(me.id, "field_medic")
	assert_true(me.cell in targets, "can heal self")
	assert_true(Vector2i(1, 4) in targets, "can heal adjacent ally")
	assert_false(Vector2i(7, 0) in targets)


func test_starting_and_permanent_statuses() -> void:
	var e := _engine(_scenario(
			[{"unit": "test_fast_dummy", "at": [0, 4], "statuses": [{"status": "cmd_vanguard", "duration": 1}]}],
			[{"unit": "test_dummy", "at": [7, 0]}]))
	var me := e.state.active_unit()
	assert_near(me.get_stat("damage_taken"), 0.9)
	for i in 3:
		e.submit(EndTurnCommand.new(e.state.active_unit_id))
	assert_true(me.find_status("cmd_vanguard") != null, "permanent statuses never expire")


func test_inline_unit_def() -> void:
	var def := {"id": "custom", "name": "Custom", "stats": {"max_hull": 33, "max_shields": 0, "armor": 0,
			"initiative": 9, "max_ap": 3}, "abilities": ["test_zap"]}
	var e := _engine(_scenario([{"unit_def": def, "at": [0, 4], "ref": "hero:x"}],
			[{"unit": "test_dummy", "at": [7, 0]}]))
	var me := e.state.active_unit()
	assert_eq(me.max_hull(), 33)
	assert_eq(me.ref, "hero:x")
	assert_eq(me.def["name"], "Custom")


func test_real_mission_auto_resolves() -> void:
	var data := DataRegistry.get_default()
	var mission: Dictionary = data.missions["derelict_station"]
	var squad := MissionFactory.squad_for(data, mission, [] as Array[Hero])
	assert_eq(squad.size(), 3, "filled with marines")
	var e := BattleEngine.from_scenario(data, MissionFactory.scenario(data, mission, squad, 0), 9)
	assert_true(e.state.fog_enabled)
	assert_eq(e.state.triggers.size(), 3)
	var result := AutoResolver.resolve(e)
	assert_true(e.state.is_over, "mission should finish (round %d)" % result["rounds"])
