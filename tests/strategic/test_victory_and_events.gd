extends TestCase
## Victory types (science, score, conquest, scenario objective) and galactic
## events. Fixture galaxy as in test_empire.gd: a (player) and b (AI) with one
## colony each; add {"events": true} to switch events on.


func _end_round(e: GalaxyEngine) -> void:
	var start := e.current_faction_id()
	e.submit(EndFactionTurnCommand.new(start))
	while e.current_faction_id() != start and not e.state.is_over:
		e.submit(EndFactionTurnCommand.new(e.current_faction_id()))


func _rich(extra: Dictionary = {}) -> Dictionary:
	var base := {"resources": {"a": {"credits": 3000, "alloys": 3000, "rare_elements": 100, "volatiles": 100, "exotic_matter": 50}, "b": {"credits": 3000, "alloys": 3000, "rare_elements": 100, "volatiles": 100, "exotic_matter": 50}}}
	base.merge(extra, true)
	return base


func _two(extra: Dictionary = {}) -> GalaxyEngine:
	return Fixtures.galaxy([["a", "test_dummy", 1, 2], ["b", "test_dummy", 8, 2]], extra)


# --- Science victory ----------------------------------------------------------

func test_completing_the_ascension_gate_wins_by_science() -> void:
	var e := _two(_rich({"techs": {"a": ["ascension_theory"]}}))
	var queued := e.submit(QueueBuildCommand.new("a", "home_a", "megaproject", "ascension_gate"))
	assert_true(queued.ok, queued.error)
	var turns := int(e.data.megaprojects["ascension_gate"]["turns"])
	for i in turns - 1:
		_end_round(e)
		assert_false(e.state.is_over, "not before the last turn (%d)" % i)
	_end_round(e)
	assert_true(e.state.is_over)
	assert_eq(e.state.winner, "a")
	assert_eq(e.state.victory_reason, "science")
	assert_true("ascension_gate" in e.state.planets["home_a"].megaprojects)


func test_the_gate_needs_the_final_tech_and_can_be_switched_off() -> void:
	var locked := _two(_rich())
	assert_false(locked.submit(QueueBuildCommand.new("a", "home_a", "megaproject", "ascension_gate")).ok)
	var scenario := _two(_rich({"techs": {"a": ["ascension_theory"]}, "victory": {"eliminate": "b"}}))
	assert_false(VictoryRules.enabled(scenario, "science"), "objective scenarios don't use science victory")
	assert_true(EmpireRules.megaproject_hidden(scenario, "ascension_gate"))
	var ids := EmpireRules.build_options(scenario, scenario.state.planets["home_a"]).map(func(o: Dictionary) -> String: return o["id"])
	assert_false("ascension_gate" in ids)
	var forced := _two(_rich({"techs": {"a": ["ascension_theory"]}, "victory": {"eliminate": "b", "science": true}}))
	assert_true(VictoryRules.enabled(forced, "science"), "a campaign can switch it back on")


func test_science_progress_tracks_techs_and_the_build() -> void:
	var e := _two(_rich())
	assert_eq(VictoryRules.science_megaproject(e), "ascension_gate")
	var path := VictoryRules.tech_path(e, "ascension_theory")
	assert_true("quantum_computing" in path and "capital_ships" in path and "deep_space_sensors" in path)
	assert_eq(VictoryRules.science_progress(e, "a"), 0.0)
	e.state.research["a"]["known"].append_array(path)
	assert_near(VictoryRules.science_progress(e, "a"), 0.7, 0.001)
	e.submit(QueueBuildCommand.new("a", "home_a", "megaproject", "ascension_gate"))
	_end_round(e)
	_end_round(e)
	assert_true(VictoryRules.science_progress(e, "a") > 0.7)
	assert_true("building" in VictoryRules.science_status(e, "a"))
	assert_true(VictoryRules.science_progress(e, "a") > VictoryRules.science_progress(e, "b"))


func test_victory_panel_lists_every_condition() -> void:
	var e := _two()
	var entries := VictoryRules.progress(e)
	var ids := entries.map(func(x: Dictionary) -> String: return x["id"])
	assert_eq(ids, ["conquest", "science", "score"])
	for entry in entries:
		assert_eq(entry["rows"].size(), 2, "a row for each major power")
		assert_ne(entry["leader"], "")
		assert_true(entry["enabled"])
	var drift := _two({"victory": {"eliminate": "b"}})
	for entry in VictoryRules.progress(drift):
		if entry["id"] in ["science", "score"]:
			assert_false(entry["enabled"])
			assert_true(entry["rows"].is_empty())


# --- Score victory ------------------------------------------------------------

func test_highest_score_wins_at_the_turn_limit() -> void:
	var e := _two({"max_turns": 2, "techs": {"a": ["improved_drives"]}})
	for i in 4:
		if not e.state.is_over:
			_end_round(e)
	assert_true(e.state.is_over)
	assert_eq(e.state.victory_reason, "score")
	assert_eq(e.state.winner, "a", "more techs, higher score")
	var other := _two({"max_turns": 2, "techs": {"b": ["improved_drives", "reinforced_hulls"]}})
	for i in 4:
		if not other.state.is_over:
			_end_round(other)
	assert_eq(other.state.winner, "b")


func test_scenario_objectives_keep_their_own_ending() -> void:
	var e := _two({"max_turns": 2, "victory": {"eliminate": "b"}})
	for i in 4:
		if not e.state.is_over:
			_end_round(e)
	assert_true(e.state.is_over)
	assert_eq(e.state.victory_reason, "max_turns")
	assert_eq(e.state.winner, "", "no score win in a scenario with an objective")
	var won := _two({"victory": {"eliminate": "b"}})
	won.state.fleets.clear()
	won.state.planets["home_b"].owner = ""
	won._check_eliminations()
	assert_eq(won.state.victory_reason, "objective")
	assert_eq(won.state.winner, "a")


func test_conquest_still_ends_the_game() -> void:
	var e := _two()
	e.state.fleets.erase(e.state.fleets_of("b")[0].id)
	e.state.planets["home_b"].owner = ""
	e._check_eliminations()
	assert_eq(e.state.victory_reason, "elimination")
	assert_eq(e.state.winner, "a")


func test_treaty_ending_can_be_switched_off() -> void:
	var e := _two({"victory": {"peace": false}})
	for i in 3:
		_end_round(e)
	e.state.opinions["b"]["a"] = 50
	e.submit(DiplomacyCommand.new("a", "b", "propose_peace"))
	assert_false(e.state.at_war("a", "b"))
	assert_false(e.state.is_over, "peace alone doesn't end this campaign")


func test_drift_scenario_keeps_its_objective_victory() -> void:
	var data := DataRegistry.get_default()
	var e := GalaxyEngine.from_campaign(data, "the_drift", 3)
	assert_eq(VictoryRules.objective(e), "raiders")
	assert_false(VictoryRules.enabled(e, "science"))
	assert_false(VictoryRules.enabled(e, "score"))
	var random := GalaxyEngine.from_campaign(data, "random_sector", 3)
	assert_true(VictoryRules.enabled(random, "science") and VictoryRules.enabled(random, "score"))


# --- Galactic events ----------------------------------------------------------

## An engine with events switched on. `natural` false keeps the engine from
## rolling its own events, so a test controls exactly which one is offered.
func _events(extra: Dictionary = {}, natural := false) -> GalaxyEngine:
	var base := {"events": true}
	base.merge(extra, true)
	var e := _two(_rich(base))
	if not natural:
		e.data.economy["events"]["first_turn"] = 9999
	return e


func _offer(e: GalaxyEngine, event_id: String) -> void:
	e.state.pending_event = {"faction": "a", "event": event_id, "turn": e.state.turn_number, "planet": "home_a"}


func _choose(e: GalaxyEngine, index: int) -> CommandResult:
	return e.submit(ResolveEventCommand.new("a", index))


func test_events_content() -> void:
	var data := DataRegistry.get_default()
	assert_eq(data.errors.size(), 0, "\n".join(data.errors))
	assert_true(data.events.size() >= 15 and data.events.size() <= 24, "%d events" % data.events.size())
	for id: String in data.events:
		var def: Dictionary = data.events[id]
		assert_true(def["choices"].size() >= 2 and def["choices"].size() <= 3, id)
		assert_false(def["text"].is_empty())
	var bad := Fixtures.registry()
	bad.events["bad"] = {"name": "Bad", "text": "x", "choices": [{"label": "a", "result": "r", "effects": [{"type": "nope"}]},
			{"label": "b", "result": "r", "requires": [{"type": "also_nope"}], "chance": 0.5, "effects": []}]}
	bad.validate()
	var text := "\n".join(bad.errors)
	assert_true("unknown effect" in text and "unknown condition" in text and "needs fail_effects" in text, text)


func test_pending_event_blocks_everything_until_answered() -> void:
	var e := _events()
	_offer(e, "market_boom")
	assert_true(e.has_pending_event())
	assert_eq(e.submit(EndFactionTurnCommand.new("a")).error, "Answer the event first")
	assert_false(e.submit(MoveFleetCommand.new("a", e.state.fleets_of("a")[0].id, Vector2i(2, 2))).ok)
	assert_false(_choose(e, 7).ok, "no such choice")
	var credits: int = e.state.resources["a"]["credits"]
	var result := _choose(e, 0)
	assert_true(result.ok, result.error)
	assert_false(e.has_pending_event())
	assert_eq(e.state.resources["a"]["credits"], credits + 70)
	assert_eq(result.events[0]["type"], GalaxyEvents.EVENT_RESOLVED)
	assert_true(e.submit(EndFactionTurnCommand.new("a")).ok)
	assert_false(_choose(e, 0).ok, "nothing to answer")


func test_choices_have_costs_and_requirements() -> void:
	var e := _events()
	e.state.resources["a"]["alloys"] = 5
	_offer(e, "market_boom")
	var offered := EventRules.choices(e, "a", e.state.pending_event)
	assert_eq(offered.size(), 3)
	assert_true(offered[0]["ok"])
	assert_false(offered[1]["ok"], "the investment costs 20 alloys")
	assert_true("alloys" in offered[1]["reason"])
	assert_false(_choose(e, 1).ok)
	assert_true(e.has_pending_event(), "a refused answer leaves the event open")
	e.state.resources["a"]["alloys"] = 30
	assert_true(_choose(e, 1).ok)
	assert_eq(e.state.resources["a"]["alloys"], 10, "paid 20 alloys")


func test_modifiers_apply_and_expire() -> void:
	var e := _events()
	var home: Planet = e.state.planets["home_a"]
	var before := int(EmpireRules.planet_yields(e, home)["credits"])
	_offer(e, "market_boom")
	_choose(e, 1)
	assert_eq(e.state.modifiers["a"].size(), 1)
	assert_true(int(EmpireRules.planet_yields(e, home)["credits"]) > before, "+25% credits")
	var expired := false
	for i in 9:
		e.submit(EndFactionTurnCommand.new("a"))
		var r := e.submit(EndFactionTurnCommand.new("b"))
		for ev in r.events:
			expired = expired or ev["type"] == GalaxyEvents.MODIFIER_EXPIRED
	assert_true(expired)
	assert_true(e.state.modifiers["a"].is_empty())
	e.state.planets["home_a"].bodies[0]["pop"] = 1
	assert_eq(int(EmpireRules.planet_yields(e, home)["credits"]), before)


func test_population_and_research_effects() -> void:
	var e := _events()
	var body: Dictionary = e.state.planets["home_a"].bodies[0]
	body["pop"] = 4
	_offer(e, "plague")
	var result := _choose(e, 2)
	assert_true(result.ok, result.error)
	assert_eq(EmpireRules.pop(body), 2, "do nothing: -2 population")
	_offer(e, "refugee_convoy")
	var research: int = e.state.research["a"]["progress"]
	_choose(e, 1)
	assert_eq(e.state.research["a"]["progress"], research + 25)
	_offer(e, "refugee_convoy")
	_choose(e, 0)
	assert_eq(EmpireRules.pop(body), 3, "welcomed: +1 population")
	body["pop"] = 1
	_offer(e, "plague")
	_choose(e, 2)
	assert_eq(EmpireRules.pop(body), 1, "never below 1")


func test_hero_ship_and_building_effects() -> void:
	var e := Fixtures.galaxy([["a", "test_dummy", 1, 2], ["b", "test_dummy", 8, 2]], _rich({"events": true,
			"planets": [{"id": "home_a", "at": [0, 5], "owner": "a", "bodies": [{"type": "terran", "buildings": ["colony", "shipyard", "trade_hub"]}]},
				{"id": "home_b", "at": [9, 5], "owner": "b", "bodies": [{"type": "desert", "buildings": ["colony"]}]}]}))
	_offer(e, "veteran_volunteers")
	_choose(e, 0)
	assert_eq(e.state.heroes_of("a").size(), 1, "a free hero")
	var hero := e.state.heroes_of("a")[0]
	assert_eq(hero.planet_id, "home_a")
	assert_true(e.data.hero_classes.has(hero.class_id))
	var ships_before := e.state.fleets_of("a").size()
	_offer(e, "reactor_accident")
	_choose(e, 1)
	var home: Planet = e.state.planets["home_a"]
	assert_eq(home.buildings.size(), 2, "one building was lost (colony and one of shipyard / trade hub left)")
	assert_true("colony" in home.buildings, "the colony itself is safe")
	assert_eq(e.state.fleets_of("a").size(), ships_before)


func test_free_ships_and_raiders() -> void:
	var e := _two(_rich({"events": true,
			"factions": [{"id": "a", "controller": "player"}, {"id": "b", "controller": "ai"},
				{"id": "r", "controller": "ai", "role": "barbarian", "barbarian": {"fleet": ["test_dummy"]}}],
			"planets": [{"id": "home_a", "at": [0, 5], "owner": "a", "bodies": [{"type": "terran", "buildings": ["colony", "shipyard"]}]},
				{"id": "home_b", "at": [9, 5], "owner": "b", "bodies": [{"type": "desert", "buildings": ["colony"]}]}]}))
	var raiders_before := e.state.fleets_of("r").size()
	_offer(e, "raider_gathering")
	_choose(e, 2)
	assert_eq(e.state.fleets_of("r").size(), raiders_before + 1, "a raider fleet spawns")
	var raider := e.state.fleets_of("r")[e.state.fleets_of("r").size() - 1]
	assert_true(e.state.grid.distance(raider.cell, e.state.planets["home_a"].cell) >= 2)
	assert_eq(raider.moves_left, 0)
	var ships := 0
	for f in e.state.fleets_of("a"):
		ships += f.ships.size()
	var found := false
	for attempt in 12:
		_offer(e, "salvage_convoy")
		e.state.rng.seed = attempt + 1
		_choose(e, 0)
		var now := 0
		for f in e.state.fleets_of("a"):
			now += f.ships.size()
		if now > ships:
			found = true
			break
		ships = now
	assert_true(found, "towing the hulk sometimes yields a ship")


func test_opinion_effects() -> void:
	var e := _two(_rich({"events": true,
			"factions": [{"id": "a", "controller": "player"}, {"id": "b", "controller": "ai"},
				{"id": "m", "controller": "ai", "role": "minor"}],
			"relations": [{"factions": ["a", "m"], "status": "peace", "opinion": 10}]}))
	e.state.turn_number = 12
	assert_true("first_contact" in EventRules.eligible(e, "a"))
	_offer(e, "first_contact")
	_choose(e, 0)
	assert_eq(e.state.opinion("m", "a"), 25, "10 + the apology gift's 15")


func test_conditions_gate_events() -> void:
	var e := _events()
	e.state.turn_number = 30
	var ids := EventRules.eligible(e, "a")
	assert_false("first_contact" in ids, "needs a minor power at peace")
	assert_false("raider_gathering" in ids, "needs barbarians")
	assert_true("solar_flare" in ids)
	assert_true("war_weariness" in ids, "at war with the other major")
	e.state.turn_number = 3
	assert_false("refugee_convoy" in EventRules.eligible(e, "a"), "min turn")
	e.state.turn_number = 30
	assert_false("mining_strike" in EventRules.eligible(e, "a"), "needs a mining base")
	e.state.planets["home_a"].bodies[1]["buildings"].append("mining_base")
	assert_true("mining_strike" in EventRules.eligible(e, "a"))
	e.state.set_relation("a", "b", "peace")
	assert_false("war_weariness" in EventRules.eligible(e, "a"))


func test_event_rolling_is_seeded_spaced_out_and_opt_in() -> void:
	var off := _two()
	off.state.turn_number = 30
	assert_true(EventRules.roll(off, "a").is_empty(), "campaigns must opt in")
	var picks: Array[String] = []
	for run in 2:
		var e := _events({}, true)
		e.state.turn_number = 30
		var pick := {}
		for i in 40:
			e.state.event_log["a"]["last"] = 0
			pick = EventRules.roll(e, "a")
			if not pick.is_empty():
				break
		assert_false(pick.is_empty(), "something is eventually offered")
		picks.append(pick["event"])
		assert_eq(e.state.event_log["a"]["seen"][pick["event"]], 30)
		assert_true(EventRules.roll(e, "a").is_empty(), "not again right away")
		assert_false(pick["event"] in EventRules.eligible(e, "a"), "and not the same event within its cooldown")
	assert_eq(picks[0], picks[1], "same seed, same event")
	var e2 := _events({}, true)
	e2.state.turn_number = 2
	e2.state.event_log["a"]["last"] = 0
	assert_true(EventRules.roll(e2, "a").is_empty(), "none before the first event turn")


func test_engine_offers_events_on_turn_start_and_ai_answers() -> void:
	var e := _events({}, true)
	var ai := GalaxyAI.new()
	var offered_to_a := false
	var answered_by_ai := false
	var guard := 0
	while guard < 400 and not e.state.is_over and e.state.turn_number < 80:
		guard += 1
		if e.has_pending_event():
			var faction: String = e.state.pending_event["faction"]
			offered_to_a = offered_to_a or faction == "a"
			var cmd := ai.decide(e)
			assert_true(cmd is ResolveEventCommand, "the AI answers events first")
			var r := e.submit(cmd)
			assert_true(r.ok, r.error)
			answered_by_ai = true
		else:
			e.submit(EndFactionTurnCommand.new(e.current_faction_id()))
	assert_true(offered_to_a and answered_by_ai, "events arrive every few turns")


func test_ai_picks_sensible_choices() -> void:
	var e := _events()
	var ai := GalaxyAI.new()
	_offer(e, "plague")
	var pick := ai.choose_event_choice(e)
	assert_true(pick in [0, 1], "it won't do nothing and lose population (%d)" % pick)
	_offer(e, "market_boom")
	e.state.resources["a"]["alloys"] = 0
	pick = ai.choose_event_choice(e)
	assert_ne(pick, 1, "it can't pay for the investment")
	e.state.resources["a"]["credits"] = 0
	_offer(e, "plague")
	pick = ai.choose_event_choice(e)
	assert_eq(pick, 2, "broke: the only affordable choice")
