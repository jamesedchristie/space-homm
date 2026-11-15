extends TestCase
## Hero building/progression and the galaxy-side hero and mission flow.


func _hero(cls: String = "vanguard", level: int = 1) -> Hero:
	var h := Hero.new()
	h.id = "h"
	h.name = "Test Hero"
	h.class_id = cls
	h.owner = "a"
	h.level = level
	return h


func test_unit_def_combines_class_level_gear_traits() -> void:
	var data := DataRegistry.get_default()
	var h := _hero("vanguard", 2)
	h.gear = {"weapon": "shotgun", "armor": "light_plating"}
	h.traits = ["veteran"]
	var def := HeroBuilder.unit_def(h, data)
	# 80 base + 8 growth + 15 veteran
	assert_eq(int(def["stats"]["max_hull"]), 103)
	# 35 base + 4 growth + 10 plating
	assert_eq(int(def["stats"]["max_shields"]), 49)
	assert_eq(int(def["stats"]["armor"]), 3)
	assert_eq(def["abilities"][0], "shotgun_blast", "weapon first")
	assert_true("bulwark" in def["abilities"] and "shockwave" in def["abilities"])
	assert_false("rally" in def["abilities"], "level 4 skill still locked")


func test_xp_levels_up() -> void:
	var data := DataRegistry.get_default()
	var h := _hero()
	assert_eq(HeroProgression.add_xp(h, 90, data), [] as Array[int])
	assert_eq(HeroProgression.add_xp(h, 200, data), [2, 3] as Array[int])
	assert_eq(h.level, 3)


func _drift() -> GalaxyEngine:
	var e := GalaxyEngine.from_campaign(DataRegistry.get_default(), "the_drift", 5)
	e.start()
	return e


func _fleet_named(e: GalaxyEngine, fleet_name: String) -> Fleet:
	for f: Fleet in e.state.fleets.values():
		if f.name == fleet_name:
			return f
	return null


func test_campaign_heroes_loaded() -> void:
	var e := _drift()
	var reyes: Hero = e.state.heroes["reyes"]
	assert_eq(reyes.fleet_id, _fleet_named(e, "1st Patrol").id)
	assert_eq(_fleet_named(e, "1st Patrol").hero_id, "reyes")
	assert_eq(e.state.heroes["okafor"].planet_id, "haven")
	assert_eq(e.state.heroes["vorn"].level, 3)
	assert_true("frag_grenade" in e.state.inventory["patrol"])


func test_commander_doctrine_in_fleet_battles() -> void:
	var g := Fixtures.galaxy([["a", "test_fast_dummy", 2, 2], ["b", "test_dummy", 4, 2]],
			{"heroes": [{"id": "cmd", "class": "marksman", "owner": "a", "fleet": "a fleet 0"}]})
	var f := g.state.fleets_of("a")[0]
	g.submit(MoveFleetCommand.new("a", f.id, g.state.fleets_of("b")[0].cell))
	var scenario := g.pending_battle_scenario()
	var entry: Dictionary = scenario["teams"][0]["units"][0]
	assert_eq(entry["statuses"][0]["status"], "cmd_marksman")
	assert_true(scenario["teams"][1]["units"][0].get("statuses", []).is_empty())
	g.auto_resolve_pending_battle()
	assert_true(g.state.heroes["cmd"].xp > 0, "commanders earn battle XP")


func test_assign_and_unassign() -> void:
	var g := Fixtures.galaxy([["a", "test_fast_dummy", 1, 4], ["b", "test_dummy", 9, 0]],
			{"heroes": [{"id": "h", "class": "technician", "owner": "a", "planet": "home_a"}]})
	var f := g.state.fleets_of("a")[0]
	assert_false(g.submit(AssignHeroCommand.new("a", "h", f.id)).ok, "fleet not at the hero's planet")
	g.submit(MoveFleetCommand.new("a", f.id, g.state.planets["home_a"].cell))
	assert_true(g.submit(AssignHeroCommand.new("a", "h", f.id)).ok)
	assert_eq(f.hero_id, "h")
	assert_true(g.submit(UnassignHeroCommand.new("a", "h")).ok)
	assert_eq(f.hero_id, "")
	assert_eq(g.state.heroes["h"].planet_id, "home_a")


func test_equip_swaps_with_inventory() -> void:
	var g := Fixtures.galaxy([["a", "test_fast_dummy", 1, 4], ["b", "test_dummy", 9, 0]],
			{"heroes": [{"id": "h", "class": "vanguard", "owner": "a", "planet": "home_a",
					"gear": {"armor": "light_plating"}}],
			 "inventory": {"a": ["heavy_plating", "medkit"]}})
	assert_false(g.submit(EquipItemCommand.new("a", "h", "armor", "medkit")).ok, "wrong slot")
	assert_true(g.submit(EquipItemCommand.new("a", "h", "armor", "heavy_plating")).ok)
	assert_eq(g.state.heroes["h"].gear["armor"], "heavy_plating")
	assert_true("light_plating" in g.state.inventory["a"])
	assert_false("heavy_plating" in g.state.inventory["a"])


func _mission_galaxy(extra: Dictionary = {}) -> GalaxyEngine:
	var base := {
		"heroes": [{"id": "h", "class": "vanguard", "owner": "a", "fleet": "a fleet 0"}],
		"anomalies": [{"id": "wreck", "name": "Wreck", "at": [3, 2], "mission": "derelict_station"}],
	}
	base.merge(extra, true)
	return Fixtures.galaxy([["a", "test_fast_dummy", 1, 2], ["b", "test_dummy", 9, 0]], base)


func _finish_battle(e: BattleEngine, winner: int, kill_heroes: bool = false) -> void:
	for u: BattleUnit in e.state.units.values():
		if u.team != winner or (kill_heroes and u.ref.begins_with("hero:")):
			u.alive = false
	e.state.winner = winner
	e.state.is_over = true


func test_mission_offered_and_success_rewards() -> void:
	var g := _mission_galaxy()
	var f := g.state.fleets_of("a")[0]
	var result := g.submit(MoveFleetCommand.new("a", f.id, g.state.anomalies["wreck"]["cell"]))
	assert_true(g.has_pending_mission())
	assert_false(g.submit(EndFactionTurnCommand.new("a")).ok, "decide first")
	var scenario := g.pending_mission_scenario()
	assert_eq(scenario["teams"][0]["units"][0]["ref"], "hero:h")
	assert_eq(scenario["teams"][0]["units"].size(), 3)

	var battle := BattleEngine.from_scenario(g.data, scenario, 3)
	battle.state.rewards.append({"loyalty": 10, "xp": 20})
	_finish_battle(battle, 0)
	var events := g.resolve_pending_mission(battle)
	var hero: Hero = g.state.heroes["h"]
	assert_eq(hero.xp, 140, "mission 120 + choice 20")
	assert_eq(hero.level, 2)
	assert_eq(hero.loyalty, 60)
	assert_eq(hero.status, Hero.ON_MISSION)
	assert_true("plasma_rifle" in g.state.inventory["a"])
	assert_false(g.state.anomalies.has("wreck"))
	var types := events.map(func(ev: Dictionary) -> String: return ev["type"])
	assert_true(GalaxyEvents.HERO_LEVELED in types)
	# Away: the fleet loses its doctrine until the hero is back.
	assert_true(g.state.active_commander(f) == null)
	for i in 4:
		g.submit(EndFactionTurnCommand.new(g.current_faction_id()))
	assert_eq(hero.status, Hero.READY, "back after the mission's duration")
	assert_true(g.state.active_commander(f) != null)


func test_mission_failure_captures_and_rescue_frees() -> void:
	var g := _mission_galaxy()
	var f := g.state.fleets_of("a")[0]
	g.submit(MoveFleetCommand.new("a", f.id, g.state.anomalies["wreck"]["cell"]))
	var battle := BattleEngine.from_scenario(g.data, g.pending_mission_scenario(), 3)
	_finish_battle(battle, MissionFactory.HOSTILE_TEAM)
	g.resolve_pending_mission(battle)
	var hero: Hero = g.state.heroes["h"]
	assert_eq(hero.status, Hero.CAPTURED)
	assert_eq(f.hero_id, "", "captured heroes lose their command")
	assert_eq(g.state.anomalies["wreck"]["mission"], "derelict_rescue", "failure creates a rescue mission")

	# Next turn: the now commander-less fleet leaves and comes back.
	# The rescue mission doesn't need a hero.
	g.submit(EndFactionTurnCommand.new("a"))
	g.submit(EndFactionTurnCommand.new("b"))
	var wreck_cell: Vector2i = g.state.anomalies["wreck"]["cell"]
	g.submit(MoveFleetCommand.new("a", f.id, g.state.grid.neighbors(wreck_cell)[0]))
	g.submit(MoveFleetCommand.new("a", f.id, wreck_cell))
	assert_true(g.has_pending_mission(), "rescue offered to a fleet without a hero")
	battle = BattleEngine.from_scenario(g.data, g.pending_mission_scenario(), 4)
	_finish_battle(battle, 0)
	g.resolve_pending_mission(battle)
	assert_eq(hero.status, Hero.INJURED, "freed, recovering")
	assert_eq(hero.planet_id, "home_a")


func test_rescue_belongs_to_the_captives_faction() -> void:
	var g := _mission_galaxy({"fleets": [
		{"name": "a fleet 0", "owner": "a", "at": [1, 2], "ships": [{"unit": "test_fast_dummy"}]},
		{"name": "b fleet", "owner": "b", "at": [5, 2], "ships": [{"unit": "test_fast_dummy"}]}]})
	var f := g.state.fleets_of("a")[0]
	var wreck_cell: Vector2i = g.state.anomalies["wreck"]["cell"]
	g.submit(MoveFleetCommand.new("a", f.id, wreck_cell))
	var battle := BattleEngine.from_scenario(g.data, g.pending_mission_scenario(), 3)
	_finish_battle(battle, MissionFactory.HOSTILE_TEAM)
	g.resolve_pending_mission(battle)
	assert_eq(g.state.anomalies["wreck"]["faction"], "a")
	# Clear the anomaly cell, then let b's fleet onto it: no mission for b.
	g.submit(EndFactionTurnCommand.new("a"))
	var b_fleet := g.state.fleets_of("b")[0]
	f.cell = g.state.grid.cell_from_layout(Vector2i(0, 0))
	g.submit(MoveFleetCommand.new("b", b_fleet.id, wreck_cell))
	assert_false(g.has_pending_mission(), "only the captives' faction can launch the rescue")


func test_permadeath() -> void:
	var g := _mission_galaxy({"permadeath": true})
	var f := g.state.fleets_of("a")[0]
	g.submit(MoveFleetCommand.new("a", f.id, g.state.anomalies["wreck"]["cell"]))
	var battle := BattleEngine.from_scenario(g.data, g.pending_mission_scenario(), 3)
	_finish_battle(battle, 0, true)
	g.resolve_pending_mission(battle)
	assert_eq(g.state.heroes["h"].status, Hero.DEAD)


func test_decline_mission() -> void:
	var g := _mission_galaxy()
	var f := g.state.fleets_of("a")[0]
	g.submit(MoveFleetCommand.new("a", f.id, g.state.anomalies["wreck"]["cell"]))
	g.decline_pending_mission()
	assert_false(g.has_pending_mission())
	assert_true(g.state.anomalies.has("wreck"))
	assert_true(g.submit(EndFactionTurnCommand.new("a")).ok)


func test_commander_survives_fleet_loss() -> void:
	var g := Fixtures.galaxy([["a", "test_fast_dummy", 2, 2], ["b", "test_dummy", 4, 2]],
			{"heroes": [{"id": "cmd", "class": "vanguard", "owner": "a", "fleet": "a fleet 0"}]})
	var f := g.state.fleets_of("a")[0]
	g.submit(MoveFleetCommand.new("a", f.id, g.state.fleets_of("b")[0].cell))
	var battle := BattleEngine.from_scenario(g.data, g.pending_battle_scenario(), 3)
	_finish_battle(battle, 1)
	g.resolve_pending_battle(battle)
	var hero: Hero = g.state.heroes["cmd"]
	assert_eq(hero.status, Hero.INJURED)
	assert_eq(hero.planet_id, "home_a")
	assert_eq(hero.fleet_id, "")
