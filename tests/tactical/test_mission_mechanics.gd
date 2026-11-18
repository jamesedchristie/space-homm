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
	assert_eq(squad.size(), 4, "filled with marines")
	var e := BattleEngine.from_scenario(data, MissionFactory.scenario(data, mission, squad, 0), 9)
	assert_true(e.state.fog_enabled)
	var lockers := e.state.triggers.filter(func(t: Dictionary) -> bool: return t.get("marker", "") == "loot")
	assert_eq(e.state.triggers.size() - lockers.size(), 3, "story triggers")
	assert_eq(lockers.size(), 2, "random supply lockers")
	var result := AutoResolver.resolve(e)
	assert_true(e.state.is_over, "mission should finish (round %d)" % result["rounds"])


func test_timed_trigger_spawns_reinforcements() -> void:
	var trigger := {"id": "wave", "team": 0, "round": 2, "title": "Contact", "text": "More of them.",
		"effects": [{"type": "spawn", "units": [{"unit": "test_dummy", "at": [7, 5], "team": 1}]},
			{"type": "effect", "to": "squad", "effect": {"type": "heal", "amount": 5}}]}
	var e := _engine(_scenario([{"unit": "test_fast_dummy", "at": [0, 4]}],
			[{"unit": "test_dummy", "at": [7, 0]}], {"triggers": [trigger]}))
	assert_eq(e.state.units.size(), 2)
	var fired := false
	for i in 6:
		if e.state.round_number >= 2:
			break
		var result := e.submit(EndTurnCommand.new(e.state.active_unit_id))
		fired = fired or BattleEvents.TRIGGER_FIRED in _types(result.events)
	assert_eq(e.state.round_number, 2)
	assert_true(fired, "fires when round 2 starts")
	assert_eq(e.state.units.size(), 3, "the wave arrived")
	assert_true(e.state.active_unit() != null)


func test_pending_waves_keep_a_cleared_battle_going() -> void:
	var trigger := {"id": "wave", "team": 0, "round": 3,
		"effects": [{"type": "spawn", "units": [{"unit": "test_dummy", "at": [7, 5], "team": 1}]}]}
	var e := _engine(_scenario([{"unit": "test_fast_dummy", "at": [0, 4]}],
			[{"unit": "test_dummy", "at": [7, 0]}],
			{"triggers": [trigger], "objectives": [{"type": "survive_rounds", "team": 0, "rounds": 4}]}))
	for u in e.state.living_units(1):
		u.hull = 0
		u.alive = false
	e.state.version += 1
	e.submit(EndTurnCommand.new(e.state.active_unit_id))
	assert_false(e.state.is_over, "a wave is still coming")
	var guard := 0
	while e.state.round_number < 3 and guard < 20:
		guard += 1
		e.submit(EndTurnCommand.new(e.state.active_unit_id))
	assert_eq(e.state.living_units(1).size(), 1, "the wave spawned")


func test_directional_cover() -> void:
	var e := _engine(_scenario([{"unit": "test_fast_dummy", "at": [0, 5]}], [{"unit": "test_dummy", "at": [7, 0]}]))
	var s := e.state
	assert_eq(CoverRules.evaluate(s, Vector2i(0, 1), Vector2i(4, 1))["cover"], CoverRules.FULL, "wall between")
	var flank := CoverRules.evaluate(s, Vector2i(4, 5), Vector2i(4, 1))
	assert_eq(flank["cover"], "")
	assert_true(flank["flanked"], "wall beside but attacked from below")
	assert_eq(CoverRules.evaluate(s, Vector2i(7, 4), Vector2i(5, 5))["cover"], CoverRules.HALF, "crates toward a roughly diagonal attacker")
	var open := CoverRules.evaluate(s, Vector2i(1, 2), Vector2i(1, 5))
	assert_eq(open["cover"], "")
	assert_false(open["flanked"], "nothing nearby: neither covered nor flanked")


func test_cover_changes_damage_and_preview() -> void:
	# Zap does a flat 10. Target next to the crates at (6, 5), shot from the crates' side.
	var e := _engine(_scenario([{"unit": "test_fast_dummy", "at": [7, 3]}], [{"unit": "test_dummy", "at": [5, 5]}]))
	var me := e.state.active_unit()
	var target := e.state.living_enemies_of(me)[0]
	var preview := e.preview_ability(me.id, "test_zap", target.cell)
	assert_eq(preview[0]["cover"]["cover"], CoverRules.HALF)
	assert_eq(preview[0]["shield_damage"] + preview[0]["hull_damage"], 7, "half cover: 30% less")
	# Same shot from the open side flanks it (crates beside, not between).
	var e2 := _engine(_scenario([{"unit": "test_fast_dummy", "at": [3, 5]}], [{"unit": "test_dummy", "at": [5, 5]}]))
	var me2 := e2.state.active_unit()
	var p2 := e2.preview_ability(me2.id, "test_zap", Vector2i(5, 5))
	assert_true(p2[0]["cover"]["flanked"])
	assert_eq(p2[0]["shield_damage"] + p2[0]["hull_damage"], 13, "flanked: 25% more (12.5 rounds up)")


func test_overwatch_reaction_shot() -> void:
	var data := Fixtures.registry()
	data.abilities["test_watch"] = {"id": "test_watch", "name": "Watch", "ap_cost": 1, "target": "self", "ends_turn": true,
		"effects": [{"type": "apply_status", "status": "overwatch", "duration": 1}]}
	data.units["test_watcher"] = data.units["test_dummy"].duplicate(true)
	data.units["test_watcher"]["id"] = "test_watcher"
	data.units["test_watcher"]["abilities"] = ["test_zap", "test_watch"]
	data.units["test_watcher"]["stats"]["initiative"] = 99
	var def := _scenario([{"unit": "test_watcher", "at": [0, 5]}], [{"unit": "test_fast_dummy", "at": [7, 5]}])
	var e := BattleEngine.from_scenario(data, def, 42)
	e.start()
	var watcher := e.state.active_unit()
	assert_eq(watcher.def_id, "test_watcher")
	var result := e.submit(UseAbilityCommand.new(watcher.id, "test_watch", watcher.cell))
	assert_true(result.ok, result.error)
	assert_eq(watcher.ap, 0, "overwatch ends the turn")
	assert_true(watcher.find_status("overwatch") != null)
	e.submit(EndTurnCommand.new(watcher.id))
	var mover := e.state.active_unit()
	var before := mover.shields + mover.hull
	# Walk into zap range (3): the watcher fires once, mid-move, at 75% damage.
	result = e.submit(MoveCommand.new(mover.id, Vector2i(3, 5)))
	assert_true(result.ok, result.error)
	var reactions := result.events.filter(func(ev: Dictionary) -> bool:
		return ev["type"] == BattleEvents.ABILITY_USED and ev.get("reaction", false))
	assert_eq(reactions.size(), 1)
	assert_eq(before - (mover.shields + mover.hull), 8, "10 * 0.75 rounds to 8")
	assert_true(watcher.find_status("overwatch") == null, "used up")
	assert_eq(mover.cell, Vector2i(3, 5), "the move finishes")
	var moves := result.events.filter(func(ev: Dictionary) -> bool: return ev["type"] == BattleEvents.UNIT_MOVED)
	assert_true(moves.size() >= 1, "the move is reported")


func test_skill_check_choices() -> void:
	var data := Fixtures.registry()
	data.units["test_techie"] = data.units["test_fast_dummy"].duplicate(true)
	data.units["test_techie"]["id"] = "test_techie"
	data.units["test_techie"]["aptitudes"] = {"tech": 4}
	var trigger := {"id": "lock", "team": 0, "cells": [[1, 4]], "text": "A lock.",
		"choices": [
			{"label": "Hack", "check": {"skill": "tech", "difficulty": 3},
				"effects": [{"type": "reward", "xp": 50}], "fail_effects": [{"type": "reward", "xp": 1}]},
			{"label": "Smash", "check": {"skill": "combat", "difficulty": 9}, "effects": [{"type": "reward", "xp": 50}]},
		]}
	var def := _scenario([{"unit": "test_techie", "at": [0, 4]}], [{"unit": "test_dummy", "at": [7, 0]}], {"triggers": [trigger]})
	var e := BattleEngine.from_scenario(data, def, 42)
	e.start()
	var me := e.state.active_unit()
	var result := e.submit(MoveCommand.new(me.id, Vector2i(1, 4)))
	var fired: Dictionary = result.events.filter(func(ev: Dictionary) -> bool: return ev["type"] == BattleEvents.TRIGGER_FIRED)[0]
	assert_near(fired["checks"][0]["chance"], 0.65, 0.001, "aptitude 4 vs difficulty 3")
	assert_near(fired["checks"][1]["chance"], 0.05, 0.001, "floor at 5%")
	assert_eq(fired["checks"][0]["by"], me.name)
	# Roll it: whichever way it goes, the matching effects apply.
	result = e.submit(ChooseOptionCommand.new(me.id, 0))
	var made: Dictionary = result.events.filter(func(ev: Dictionary) -> bool: return ev["type"] == BattleEvents.CHOICE_MADE)[0]
	assert_true(made["check"].has("success"))
	assert_eq(e.state.rewards[0]["xp"], 50 if made["check"]["success"] else 1)


func test_hero_aptitudes_grow_with_level() -> void:
	var data := DataRegistry.get_default()
	var h := Hero.new()
	h.class_id = "technician"
	h.level = 1
	assert_eq(HeroBuilder.aptitudes(h, data)["tech"], 4)
	h.level = 5
	assert_eq(HeroBuilder.aptitudes(h, data)["tech"], 6)
	assert_eq(HeroBuilder.unit_def(h, data)["aptitudes"]["tech"], 6)


func test_random_caches_are_placed_and_pay_out() -> void:
	var loot := [{"weight": 1, "text": "Crates.", "rewards": {"credits": 30}}]
	var def := _scenario([{"unit": "test_fast_dummy", "at": [0, 5]}], [{"unit": "test_dummy", "at": [7, 0]}],
			{"caches": {"count": 2, "team": 0, "loot": loot}})
	var a := BattleEngine.from_scenario(Fixtures.registry(), def, 7)
	var b := BattleEngine.from_scenario(Fixtures.registry(), def, 7)
	var cache_cells := func(e: BattleEngine) -> Array:
		return e.state.triggers.filter(func(t: Dictionary) -> bool: return t.get("marker", "") == "loot").map(
				func(t: Dictionary) -> Vector2i: return t["_cells"][0])
	var cells: Array = cache_cells.call(a)
	assert_eq(cells.size(), 2)
	assert_eq(cells, cache_cells.call(b), "seeded")
	for c: Vector2i in cells:
		assert_true(a.state.grid.distance(c, Vector2i(0, 5)) >= 3, "not on top of the squad")
	# Walk onto one: the reward is recorded for the campaign.
	a.start()
	var me := a.state.active_unit()
	if me.team != 0:
		return
	me.cell = cells[0] + Vector2i(1, 0) if a.state.grid.has_cell(cells[0] + Vector2i(1, 0)) and a.state.grid.is_passable(cells[0] + Vector2i(1, 0)) else cells[0] - Vector2i(1, 0)
	a.state.version += 1
	a.submit(MoveCommand.new(me.id, cells[0]))
	assert_eq(a.state.rewards.size(), 1)
	assert_eq(a.state.rewards[0]["credits"], 30)


func test_damage_over_time_ignores_cover_and_flanking() -> void:
	# Source stands where the half cover at (6, 5) would shield the target from an attack.
	var e := _engine(_scenario([{"unit": "test_fast_dummy", "at": [7, 3]}], [{"unit": "test_dummy", "at": [5, 5]}]))
	var source := e.state.active_unit()
	var target := e.state.living_enemies_of(source)[0]
	var before := target.hull
	for effect_def: Dictionary in e.data.statuses["hull_breach"]["on_turn_start"]:
		e._apply_effect(effect_def, source, target)
	assert_eq(before - target.hull, 6, "5 kinetic vs hull (x1.2), whatever the attacker's angle was")


func test_wiped_squad_loses_even_with_waves_pending() -> void:
	var trigger := {"id": "wave", "team": 0, "round": 3,
		"effects": [{"type": "spawn", "units": [{"unit": "test_dummy", "at": [7, 5], "team": 1}]}]}
	var e := _engine(_scenario([{"unit": "test_fast_dummy", "at": [0, 4]}],
			[{"unit": "test_dummy", "at": [7, 0]}],
			{"triggers": [trigger], "objectives": [{"type": "survive_rounds", "team": 0, "rounds": 4}]}))
	for u in e.state.living_units(0):
		u.hull = 0
		u.alive = false
	e.state.version += 1
	e.submit(EndTurnCommand.new(e.state.active_unit_id))
	assert_true(e.state.is_over, "nobody is left to reinforce")
	assert_eq(e.state.winner, 1)
