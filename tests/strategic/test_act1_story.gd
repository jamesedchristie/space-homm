extends TestCase
## Act 1 content for Solar Age: story milestones (StoryRules), story mission sites, raids that steal
## strategic resources and knock developments offline, the raiders' hoard, Act 1 events and missions.

var _data: DataRegistry


func before_each() -> void:
	_data = DataRegistry.get_default()


func _engine(seed_value: int = 3) -> GalaxyEngine:
	return GalaxyEngine.from_campaign(_data, "solar_age", seed_value)


func _has(events: Array[Dictionary], type: String) -> bool:
	return events.any(func(ev: Dictionary) -> bool: return ev["type"] == type)


## Puts the faction at milestone `step_id`, not yet started.
func _jump_to(e: GalaxyEngine, step_id: String) -> void:
	var st := StoryRules.state_of(e, "patrol")
	st["step"] = StoryRules.step_index(e, step_id)
	st["active"] = false


# --- Milestones ---------------------------------------------------------------

func test_story_content_is_valid() -> void:
	assert_eq(_data.errors.size(), 0, "\n".join(_data.errors))
	var steps: Array = _data.campaigns["solar_age"]["story"]["steps"]
	assert_true(steps.size() >= 6, "six Act 1 milestones")
	assert_eq(steps[steps.size() - 1]["goal"], {"type": "tech", "tech": "hyperdrive"}, "the last one is Hyperdrive")
	# A broken story is reported.
	var bad := DataRegistry.new()
	bad.load_from("res://data")
	StoryRules.validate(bad, "x", {"story": {"steps": [{"id": "a", "title": "A", "objective": "o",
			"goal": {"type": "nonsense"}, "reward": {"gold": 3}}]},
			"story_anomalies": [{"id": "s", "mission": "nope", "story": "b"}]})
	assert_true(bad.errors.size() >= 4, str(bad.errors))


func test_first_milestone_starts_with_the_campaign() -> void:
	var e := _engine()
	var events := e.start()
	assert_true(_has(events, GalaxyEvents.STORY_STEP_STARTED))
	assert_true(StoryRules.is_active(e, "patrol"))
	assert_eq(StoryRules.current(e, "patrol")["id"], "chart_the_system")
	var started: Dictionary = events.filter(func(ev: Dictionary) -> bool: return ev["type"] == GalaxyEvents.STORY_STEP_STARTED)[0]
	assert_true(started["first"], "the first briefing is part of the campaign briefing")
	# Barbarians have no story.
	assert_false(e.state.story.has("separatists"))
	# Campaigns without a story are untouched.
	var drift := GalaxyEngine.from_campaign(_data, "the_drift", 3)
	drift.start()
	assert_true(drift.state.story.is_empty())


func test_survey_milestone_completes_pays_and_moves_on() -> void:
	var e := _engine()
	e.start()
	var credits := int(e.state.resources["patrol"]["credits"])
	var progress := int(e.state.research["patrol"]["progress"])
	var p := StoryRules.progress(e, "patrol", StoryRules.current(e, "patrol")["goal"])
	assert_true(int(p["have"]) < int(p["need"]), "not surveyed yet (%s)" % p)
	assert_true(StoryRules.objective_text(e, "patrol", StoryRules.current(e, "patrol")).contains("/7)"))
	for planet: Planet in e.state.planets.values():
		e.state.surveyed["patrol"][planet.id] = true
	var events := e._flush()
	assert_true(_has(events, GalaxyEvents.STORY_STEP_COMPLETED))
	var done: Dictionary = events.filter(func(ev: Dictionary) -> bool: return ev["type"] == GalaxyEvents.STORY_STEP_COMPLETED)[0]
	assert_eq(done["step"], "chart_the_system")
	assert_eq(done["next"], "industry")
	assert_eq(int(e.state.resources["patrol"]["credits"]), credits + 30, "reward paid")
	assert_eq(int(e.state.research["patrol"]["progress"]), progress + 30)
	assert_eq(StoryRules.current(e, "patrol")["id"], "industry", "on to the next milestone")
	assert_true(StoryRules.is_active(e, "patrol"))
	assert_true(StoryRules.state_of(e, "patrol")["done"].has("chart_the_system"))
	# One completion per update: the next goal is checked on the next call.
	var home := e.state.home_planet("patrol")
	for planet: Planet in e.state.planets.values():
		if planet != home and planet.owner.is_empty() and e.state.planets_of("patrol").size() < 3:
			planet.owner = "patrol"
			planet.bodies[0]["buildings"].append("outpost")
	events = e._flush()
	assert_true(_has(events, GalaxyEvents.STORY_STEP_COMPLETED), "two bodies held: industry done")
	assert_eq(StoryRules.current(e, "patrol")["id"], "the_front_strikes")
	assert_false(StoryRules.is_active(e, "patrol"), "the Front waits for its turn (min_turn)")


func test_front_strikes_raids_reveals_the_listening_post_and_completes() -> void:
	var e := _engine()
	e.start()
	_jump_to(e, "the_front_strikes")
	e.state.turn_number = 12
	var raiders_before := e.state.fleets_of("separatists").size()
	assert_false(e.state.anomalies.has("listening_post"), "hidden until its milestone")
	var events := e._flush()
	assert_true(_has(events, GalaxyEvents.STORY_STEP_STARTED))
	assert_true(_has(events, GalaxyEvents.ANOMALY_ADDED))
	assert_true(e.state.anomalies.has("listening_post"), "the mission site appears")
	assert_eq(e.state.anomalies["listening_post"]["mission"], "listening_post")
	assert_eq(e.state.fleets_of("separatists").size(), raiders_before + 1, "the Front sends a raid")
	assert_true(e.explored_cells("patrol").has(e.state.anomalies["listening_post"]["cell"]), "and you know where the site is")
	# Raiding the listening post completes it (any of its goals would).
	var stock := int(e.state.resources["patrol"]["rare_elements"])
	var fleet := e.state.fleets_of("patrol")[0]
	e.emit({"type": GalaxyEvents.MISSION_RESOLVED, "fleet": fleet.id, "mission": "listening_post", "success": true})
	events = e._flush()
	assert_true(_has(events, GalaxyEvents.STORY_STEP_COMPLETED))
	assert_eq(int(e.state.resources["patrol"]["rare_elements"]), stock + 4)
	assert_eq(StoryRules.flag_count(e, "patrol", "mission:listening_post"), 1)


func test_flags_from_battles_and_dens() -> void:
	var e := _engine()
	e.start()
	var mine := e.state.fleets_of("patrol")[0]
	var theirs := e.state.fleets_of("scavengers")[0]
	e.emit({"type": GalaxyEvents.BATTLE_RESOLVED, "attacker": mine.id, "defender": theirs.id, "cell": theirs.cell, "winner": "patrol"})
	assert_eq(StoryRules.flag_count(e, "patrol", "beat:scavengers"), 1)
	e.emit({"type": GalaxyEvents.BATTLE_RESOLVED, "attacker": theirs.id, "defender": mine.id, "cell": mine.cell, "winner": "patrol"})
	assert_eq(StoryRules.flag_count(e, "patrol", "beat:scavengers"), 2, "defending counts too")
	var den := e.state.planets_of("separatists")[0]
	e.emit({"type": GalaxyEvents.DEN_CLEARED, "planet": den.id, "faction": "patrol", "loot": {}})
	assert_eq(StoryRules.flag_count(e, "patrol", "den:separatists"), 1)
	assert_eq(StoryRules.flag_count(e, "scavengers", "beat:patrol"), 0, "barbarians keep no story")
	# A goal with "n" needs that many.
	assert_true(StoryRules.goal_met(e, "patrol", {"type": "flag", "flag": "beat:scavengers", "n": 2}))
	assert_false(StoryRules.goal_met(e, "patrol", {"type": "flag", "flag": "beat:scavengers", "n": 3}))
	assert_true(StoryRules.goal_met(e, "patrol", {"type": "any", "goals": [{"type": "flag", "flag": "nope"},
			{"type": "flag", "flag": "den:separatists"}]}))
	assert_false(StoryRules.goal_met(e, "patrol", {"type": "all", "goals": [{"type": "flag", "flag": "nope"},
			{"type": "flag", "flag": "den:separatists"}]}))


func test_exotic_matter_milestone_and_its_goals() -> void:
	var e := _engine()
	e.start()
	_jump_to(e, "exotic_matter")
	e._flush()
	assert_true(e.state.anomalies.has("ice_cave"), "the ice cave appears with the exotic matter milestone")
	var goal: Dictionary = StoryRules.current(e, "patrol")["goal"]
	assert_false(StoryRules.goal_met(e, "patrol", goal))
	e.state.resources["patrol"]["exotic_matter"] = 8
	assert_true(StoryRules.goal_met(e, "patrol", goal), "a stock of 8 is enough")
	e.state.resources["patrol"]["exotic_matter"] = 0
	for p: Planet in e.state.planets.values():
		if DepositRules.of(p.bodies[0]).has("exotic_matter"):
			p.owner = "patrol"
			p.bodies[0]["buildings"].assign(["exotic_containment"])
	assert_true(StoryRules.goal_met(e, "patrol", goal), "so is tapping the deposit")
	var events := e._flush()
	assert_true(_has(events, GalaxyEvents.STORY_STEP_COMPLETED))
	assert_eq(StoryRules.current(e, "patrol")["id"], "hyperdrive")
	var overview := StoryRules.overview(e, "patrol")
	assert_eq(overview[0]["state"], "later", "skipped milestones are not marked done")
	assert_eq(overview[4]["state"], "done")
	assert_eq(overview[5]["state"], "active")


func test_story_survives_a_save() -> void:
	var e := _engine()
	e.start()
	_jump_to(e, "strange_signals")
	e.state.turn_number = 25
	e._flush()
	assert_true(e.state.anomalies.has("scavenger_nest"))
	var save := GalaxySave.to_dict(e, "solar_age")
	assert_eq(int(save["version"]), GalaxySave.VERSION)
	var loaded: Dictionary = GalaxySave.from_dict(_data, save)
	assert_true(loaded.has("engine"), str(loaded.get("error", "")))
	var e2: GalaxyEngine = loaded["engine"]
	assert_eq(var_to_str(e2.state.story), var_to_str(e.state.story))
	assert_eq(StoryRules.current(e2, "patrol")["id"], "strange_signals")
	assert_true(e2.state.anomalies.has("scavenger_nest"))
	# Older saves (no story) start the story from the beginning.
	save["state"].erase("story")
	var old: GalaxyEngine = GalaxySave.from_dict(_data, save)["engine"]
	old._flush()
	assert_eq(StoryRules.current(old, "patrol")["id"], "chart_the_system")


# --- Story mission sites ---------------------------------------------------------

func test_story_sites_sit_on_free_bodies() -> void:
	var ices := 0
	for seed_value in [1, 2, 3, 4, 5, 6, 7, 8]:
		var def := SystemLayout.generate(_data, _data.campaigns["solar_age"], seed_value)
		var sites: Array = def.get("story_anomalies", [])
		assert_eq(sites.size(), 3, "three story sites (seed %d)" % seed_value)
		var by_id := {}
		for p: Dictionary in def["planets"]:
			by_id[p["id"]] = p
		var used := {}
		for a: Dictionary in def.get("anomalies", []):
			used[str(a["at"])] = true
		for site: Dictionary in sites:
			var body: Dictionary = by_id[site["body"]]
			assert_eq(body["at"], site["at"])
			assert_eq(body.get("owner", ""), "", "%s is not on a den or the homeworld (seed %d)" % [site["id"], seed_value])
			assert_ne(_data.body_types[body["bodies"][0]["type"]]["category"], "habitable", "worlds are for colonies")
			assert_false(used.has(str(site["at"])), "one site per body (seed %d)" % seed_value)
			used[str(site["at"])] = true
			assert_true(_data.missions.has(site["mission"]))
		var ice: Dictionary = sites.filter(func(a: Dictionary) -> bool: return a["id"] == "ice_cave")[0]
		ices += 1 if _data.body_types[by_id[ice["body"]]["bodies"][0]["type"]]["category"] == "ice" else 0
		assert_true(_data.body_types[by_id[ice["body"]]["bodies"][0]["type"]]["category"] in ["ice", "rock"], "the ice cave is under ice (or an icy rock)")
	assert_true(ices >= 6, "the ice cave is under an ice moon in most systems (%d of 8)" % ices)
	# Same seed, same sites (they have their own dice).
	var a := SystemLayout.generate(_data, _data.campaigns["solar_age"], 5)
	var b := SystemLayout.generate(_data, _data.campaigns["solar_age"], 5)
	assert_eq(var_to_str(a["story_anomalies"]), var_to_str(b["story_anomalies"]))


# --- Raids ------------------------------------------------------------------------

func _outpost(e: GalaxyEngine) -> Planet:
	var home := e.state.home_planet("patrol")
	for p: Planet in e.state.planets.values():
		if p != home and p.owner.is_empty() and _data.body_types[p.bodies[0]["type"]]["category"] in ["rock", "belt"]:
			p.owner = "patrol"
			p.bodies[0]["buildings"].assign(["mining_base"])
			p.bodies[0]["deposits"] = {"rare_elements": 2}
			return p
	return null


func test_raids_steal_strategic_resources_and_knock_developments_offline() -> void:
	var e := _engine()
	e.start()
	var target := _outpost(e)
	assert_true(target != null)
	var raider := e.state.fleets_of("separatists")[0]
	var stock: Dictionary = e.state.resources["patrol"]
	stock["credits"] = 100
	stock["volatiles"] = 20
	stock["rare_elements"] = 3
	stock["exotic_matter"] = 0
	var hoard: Dictionary = e.state.resources["separatists"]
	var hoard_volatiles := int(hoard["volatiles"])
	assert_true(EmpireRules.body_yields(e, target.bodies[0], "patrol").get("rare_elements", 0) > 0)
	e._plunder(target, raider)
	var events := e._flush()
	var raid: Dictionary = events.filter(func(ev: Dictionary) -> bool: return ev["type"] == GalaxyEvents.SYSTEM_PLUNDERED)[0]
	assert_eq(int(raid["credits"]), 35, "the Front takes up to 35 credits")
	assert_eq(int(raid["stolen"]["volatiles"]), 4, "a fifth of the volatiles")
	assert_eq(int(raid["stolen"]["rare_elements"]), 1, "at least one of a small stock")
	assert_false(raid["stolen"].has("exotic_matter"), "nothing to take")
	assert_eq(int(stock["volatiles"]), 16)
	assert_eq(int(hoard["volatiles"]), hoard_volatiles + 4, "into the raiders' hoard")
	assert_eq(int(raid["offline"]), 4)
	assert_eq(raid["building"], "", "nothing wrecked")
	assert_eq(target.owner, "patrol", "the outpost stays yours")
	assert_true(EmpireRules.is_offline(e, target.bodies[0]))
	assert_eq(EmpireRules.offline_turns(e, target.bodies[0]), 4)
	assert_true(EmpireRules.body_yields(e, target.bodies[0], "patrol").is_empty(), "no yields while offline")
	assert_true(StoryRules.flag_count(e, "patrol", "plundered") >= 1)
	# Hit again while still down: wrecked (and an outpost with nothing left is lost).
	e._plunder(target, raider)
	raid = e._flush().filter(func(ev: Dictionary) -> bool: return ev["type"] == GalaxyEvents.SYSTEM_PLUNDERED)[0]
	assert_eq(raid["building"], "mining_base")
	assert_true(raid["razed"])
	# Back in business after the offline turns.
	var other := _outpost(e)
	e._plunder(other, raider)
	e.state.turn_number += 4
	assert_false(EmpireRules.is_offline(e, other.bodies[0]))
	assert_false(EmpireRules.body_yields(e, other.bodies[0], "patrol").is_empty())


func test_plunder_without_a_spec_works_as_before() -> void:
	var e := GalaxyEngine.from_campaign(_data, "the_drift", 3)
	e.start()
	var target: Planet = null
	for p in e.state.planets_of("patrol"):
		target = p
	var raider := e.state.fleets_of("raiders")[0]
	var before := target.buildings.size()
	e._plunder(target, raider)
	var raid: Dictionary = e._flush().filter(func(ev: Dictionary) -> bool: return ev["type"] == GalaxyEvents.SYSTEM_PLUNDERED)[0]
	assert_true(raid["stolen"].is_empty())
	assert_eq(int(raid["offline"]), 0)
	assert_eq(target.buildings.size(), before - (0 if raid["building"] == "" else 1))


func test_storming_a_den_recovers_the_hoard() -> void:
	var e := _engine()
	e.start()
	var den := e.state.planets_of("scavengers")[0]
	var hoard: Dictionary = e.state.resources["scavengers"]
	hoard["volatiles"] = 30
	hoard["rare_elements"] = 10
	var mine := e.state.fleets_of("patrol")[0]
	var before := int(e.state.resources["patrol"]["volatiles"])
	e._capture_planet(den, mine)
	var events := e._flush()
	var cleared: Dictionary = events.filter(func(ev: Dictionary) -> bool: return ev["type"] == GalaxyEvents.DEN_CLEARED)[0]
	assert_eq(int(cleared["loot"]["volatiles"]), 6 + 30, "den loot plus the hoard (its only base)")
	assert_eq(int(cleared["loot"]["rare_elements"]), 10)
	assert_eq(int(e.state.resources["patrol"]["volatiles"]), before + 36)
	assert_eq(int(hoard["volatiles"]), 0)
	assert_eq(den.owner, "patrol")
	assert_eq(StoryRules.flag_count(e, "patrol", "den:scavengers"), 1)


# --- Events -------------------------------------------------------------------------

const ACT1_EVENTS := ["front_sympathisers", "scavenger_trade", "coronal_mass_ejection", "mining_accident",
		"comet_flyby", "brood_message", "ice_echo", "front_defector"]


func test_act1_events_exist_and_only_happen_in_a_home_system() -> void:
	for id in ACT1_EVENTS:
		assert_true(_data.events.has(id), id)
		assert_true(_data.events[id]["conditions"].has({"type": "scale", "scale": "system"}), "%s is Act 1 only" % id)
	var sector := GalaxyEngine.from_campaign(_data, "the_drift", 3)
	sector.start()
	sector.state.turn_number = 40
	for id in EventRules.eligible(sector, "patrol"):
		assert_false(id in ACT1_EVENTS, "%s offered in a galaxy campaign" % id)
	var e := _engine()
	e.start()
	e.state.turn_number = 40
	_outpost(e)
	_outpost(e)
	var eligible := EventRules.eligible(e, "patrol")
	assert_true("comet_flyby" in eligible)
	assert_true("front_sympathisers" in eligible)
	assert_true("mining_accident" in eligible)
	assert_false("brood_message" in eligible, "the brood speaks once its signals are found")
	_jump_to(e, "strange_signals")
	e._flush()
	assert_true("brood_message" in EventRules.eligible(e, "patrol"))


func test_act1_event_effects() -> void:
	var e := _engine()
	e.start()
	var target := _outpost(e)
	var stock: Dictionary = e.state.resources["patrol"]
	var volatiles := int(stock["volatiles"])
	var line := EventRules._apply_effect(e, "patrol", {"type": "resources", "volatiles": 10, "exotic_matter": 2}, "")
	assert_eq(int(stock["volatiles"]), volatiles + 10, "events can pay strategic resources")
	assert_eq(int(stock["exotic_matter"]), 2)
	assert_true(line.contains("exotic matter"), line)
	line = EventRules._apply_effect(e, "patrol", {"type": "offline", "turns": 3}, target.id)
	assert_true(EmpireRules.is_offline(e, target.bodies[0]), line)
	assert_eq(EmpireRules.offline_turns(e, target.bodies[0]), 3)
	var scavengers := e.state.fleets_of("scavengers").size()
	line = EventRules._apply_effect(e, "patrol", {"type": "raiders", "count": 1, "faction": "scavengers"}, target.id)
	assert_eq(e.state.fleets_of("scavengers").size(), scavengers + 1, "raiders of the named faction")
	assert_true(line.contains("Vrask"), line)
	# The AI weighs strategic resources and lost production.
	var ai := GalaxyAI.new()
	assert_true(ai._effects_value(e, "patrol", [{"type": "resources", "volatiles": 10}], {}) > 0.0)
	assert_true(ai._effects_value(e, "patrol", [{"type": "offline", "turns": 4}], {}) < 0.0)
	# Every Act 1 event can be answered by the AI.
	for id in ACT1_EVENTS:
		e.state.pending_event = {"faction": "patrol", "event": id, "turn": e.state.turn_number, "planet": target.id}
		var choice := ai.choose_event_choice(e)
		assert_true(choice >= 0 and choice < _data.events[id]["choices"].size(), id)
		var result := EventRules.apply(e, "patrol", e.state.pending_event, choice)
		assert_false(str(result["text"]).is_empty(), id)
	e.state.pending_event = {}


# --- Missions ----------------------------------------------------------------------

const ACT1_MISSIONS := ["listening_post", "scavenger_nest", "ice_cave"]


func _hero(level: int) -> Hero:
	var h := Hero.new()
	h.id = "tester"
	h.name = "Tester"
	h.class_id = "vanguard"
	h.owner = "patrol"
	h.level = level
	h.xp = HeroProgression.xp_for_level(_data, level)
	h.gear = {"weapon": "shotgun", "armor": "light_plating"}
	return h


func test_act1_missions_are_valid_and_auto_resolve() -> void:
	for id in ACT1_MISSIONS:
		var mission: Dictionary = _data.missions[id]
		var map: Dictionary = _data.maps[mission["map"]]
		assert_eq(map.get("floor", ""), "deck", "%s is a deck map" % id)
		assert_false(map.get("mood", {}).is_empty(), "%s has a mood" % id)
		var heroes: Array[Hero] = [_hero(1)]
		var squad := MissionFactory.squad_for(_data, mission, heroes, "human")
		assert_eq(squad.size(), 4)
		var wins := 0
		for i in 4:
			var battle := BattleEngine.from_scenario(_data, MissionFactory.scenario(_data, mission, squad, 0, "Away", "ai"), 77 + i)
			AutoResolver.resolve(battle)
			assert_true(battle.state.is_over, "%s ends" % id)
			if battle.state.winner == 0:
				wins += 1
		assert_true(wins >= 1, "%s can be won by a level 1 squad (%d of 4)" % [id, wins])
	# New hostiles have their own humanoid-alien and construct models.
	for unit_id in ["separatist_militia", "separatist_officer", "vrask_drone", "vrask_warrior", "vrask_broodmother",
			"precursor_sentinel", "precursor_guardian"]:
		var model: String = _data.units[unit_id]["visual"]["model"]
		assert_true(_data.models.has(model), unit_id)
	assert_eq(_data.models["vrask_warrior"]["base"], "humanoid")


func test_mission_rewards_can_be_strategic() -> void:
	var e := _engine()
	e.start()
	_jump_to(e, "exotic_matter")
	e._flush()
	var fleet: Fleet = null
	for f in e.state.fleets_of("patrol"):
		if not f.hero_id.is_empty():
			fleet = f
	assert_true(fleet != null)
	var hero: Hero = e.state.heroes[fleet.hero_id]
	hero.level = 4
	hero.xp = HeroProgression.xp_for_level(_data, 4)
	var anomaly: Dictionary = e.state.anomalies["ice_cave"].duplicate(true)
	fleet.cell = anomaly["cell"]
	var won := false
	for i in 8:
		e.state.pending_mission = {"anomaly": "ice_cave", "fleet": fleet.id}
		var before := int(e.state.resources["patrol"]["exotic_matter"])
		var events := e.auto_resolve_pending_mission()
		var resolved: Dictionary = events.filter(func(ev: Dictionary) -> bool: return ev["type"] == GalaxyEvents.MISSION_RESOLVED)[0]
		if resolved["success"]:
			assert_true(int(e.state.resources["patrol"]["exotic_matter"]) >= before + 5, "the vault's exotic matter")
			assert_true(int(resolved["strategic"].get("exotic_matter", 0)) >= 5)
			assert_true("lattice_ward" in e.state.inventory["patrol"])
			assert_true(_has(events + e._flush(), GalaxyEvents.STORY_STEP_COMPLETED), "the ice cave completes the milestone")
			won = true
			break
		hero.status = Hero.READY
		hero.fleet_id = fleet.id
		fleet.hero_id = hero.id
		e.state.anomalies["ice_cave"] = anomaly.duplicate(true)
	assert_true(won, "a level 4 commander clears the ice cave")


# --- Autoplay -----------------------------------------------------------------------

func test_capped_autoplay_tells_the_story() -> void:
	var e := _engine(2)
	var result := CampaignAutoRunner.run(e, 700)
	assert_true(e.state.turn_number >= 15, "reached turn %d" % e.state.turn_number)
	assert_true(int(result["events"].get(GalaxyEvents.STORY_STEP_COMPLETED, 0)) >= 2,
			"the AI reaches milestones (%d)" % int(result["events"].get(GalaxyEvents.STORY_STEP_COMPLETED, 0)))
