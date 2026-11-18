extends TestCase
## Saving and loading campaigns (GalaxySave).


## Plays the real campaign with the AI for every faction until the start of
## the player's turn `turn`, auto-resolving battles and missions.
func _campaign_at_turn(turn: int, rng_seed: int = 5) -> GalaxyEngine:
	var e := GalaxyEngine.from_campaign(DataRegistry.get_default(), "the_drift", rng_seed)
	e.start()
	var ai := GalaxyAI.new()
	var guard := 0
	while guard < 3000 and not e.state.is_over:
		guard += 1
		if e.has_pending_battle():
			e.auto_resolve_pending_battle()
		elif e.has_pending_mission():
			e.auto_resolve_pending_mission()
		elif e.state.turn_number >= turn and e.state.current_faction_index == 0:
			break
		elif not e.submit(ai.decide(e)).ok:
			e.submit(EndFactionTurnCommand.new(e.current_faction_id()))
	return e


func _state_text(e: GalaxyEngine) -> String:
	return var_to_str(GalaxySave.to_dict(e, "the_drift")["state"])


func test_round_trip_preserves_state() -> void:
	var e := _campaign_at_turn(6)
	var save := GalaxySave.to_dict(e, "the_drift")
	assert_false(save.is_empty())
	assert_eq(save["meta"]["turn"], e.state.turn_number)
	var loaded := GalaxySave.from_dict(e.data, save)
	assert_true(loaded.has("engine"), str(loaded.get("error", "")))
	var e2: GalaxyEngine = loaded["engine"]
	assert_eq(_state_text(e2), _state_text(e))
	assert_eq(e2.visible_cells("patrol"), e.visible_cells("patrol"))
	assert_eq(e2.state.fleets.keys(), e.state.fleets.keys())


func test_loaded_game_plays_out_identically() -> void:
	var e := _campaign_at_turn(4, 11)
	var e2: GalaxyEngine = GalaxySave.from_dict(e.data, GalaxySave.to_dict(e, "the_drift"))["engine"]
	var a := CampaignAutoRunner.run(e)
	var b := CampaignAutoRunner.run(e2)
	assert_eq(b, a, "same RNG state and data -> same campaign")
	assert_eq(_state_text(e2), _state_text(e))


func test_refuses_mid_battle_and_bad_input() -> void:
	var e := _campaign_at_turn(2)
	e.state.pending_battle = {"attacker": "x", "defender": "y", "cell": Vector2i.ZERO}
	assert_true(GalaxySave.to_dict(e, "the_drift").is_empty())
	assert_true(GalaxySave.from_dict(e.data, {"format": "nope"}).has("error"))
	assert_true(GalaxySave.from_dict(e.data, {"format": GalaxySave.FORMAT, "version": 999}).has("error"))
	assert_true(GalaxySave.from_dict(e.data, {"format": GalaxySave.FORMAT, "version": 1, "campaign": "missing"}).has("error"))


func test_file_slots() -> void:
	var e := _campaign_at_turn(3)
	var slot := "test_slot_%d" % randi()
	assert_eq(GalaxySave.write(slot, e, "the_drift"), "")
	var listed := GalaxySave.list().filter(func(s: Dictionary) -> bool: return s["slot"] == slot)
	assert_eq(listed.size(), 1)
	assert_eq(listed[0]["meta"]["turn"], 3)
	var loaded := GalaxySave.load_slot(e.data, slot)
	assert_true(loaded.has("engine"), str(loaded.get("error", "")))
	assert_eq(loaded["campaign"], "the_drift")
	assert_eq(_state_text(loaded["engine"]), _state_text(e))
	GalaxySave.delete(slot)
	assert_true(GalaxySave.load_slot(e.data, slot).has("error"))


func test_generated_sector_is_seeded_and_saves() -> void:
	var data := DataRegistry.get_default()
	var a := GalaxyEngine.from_campaign(data, "random_sector", 4)
	var b := GalaxyEngine.from_campaign(data, "random_sector", 4)
	var c := GalaxyEngine.from_campaign(data, "random_sector", 5)
	assert_eq(var_to_str(a.campaign["planets"]), var_to_str(b.campaign["planets"]), "same seed, same sector")
	assert_ne(var_to_str(a.campaign["planets"]), var_to_str(c.campaign["planets"]), "different seed, different sector")
	# Homes: the raiders' den and the traders' port start owned; each major's waits for its colony ship.
	var homes := a.state.planets.values().filter(func(p: Planet) -> bool: return not p.owner.is_empty() or not p.capital.is_empty())
	assert_eq(homes.size(), 5, "three majors, the raiders' den and the traders' port")
	for i in homes.size():
		for j in range(i + 1, homes.size()):
			assert_true(a.state.grid.distance(homes[i].cell, homes[j].cell) >= 5, "homes spread apart")
	a.start()
	var loaded := GalaxySave.from_dict(data, GalaxySave.to_dict(a, "random_sector"))
	assert_true(loaded.has("engine"), str(loaded.get("error", "")))
	assert_eq(_state_text(loaded["engine"]), _state_text(a))
	assert_eq(loaded["engine"].state.grid.cells().size(), a.state.grid.cells().size())


func test_round_trip_keeps_population_wonders_modifiers_and_events() -> void:
	var e := _campaign_at_turn(8)
	var home := e.state.home_planet("patrol")
	var body := home.colonies()[0]
	body["pop"] = 5
	body["growth"] = 2.5
	home.megaprojects.append("grand_archive")
	e.state.modifiers["patrol"].append({"id": "market_boom", "name": "Market boom", "turns": 6,
			"effects": [{"type": "yield", "resource": "credits", "mul": 1.25}]})
	e.state.event_log["patrol"] = {"last": 7, "seen": {"plague": 7}}
	e.state.pending_event = {"faction": "patrol", "event": "market_boom", "turn": 8, "planet": home.id}
	var save := GalaxySave.to_dict(e, "the_drift")
	assert_false(save.is_empty(), "a pending event doesn't stop saving")
	assert_eq(save["version"], GalaxySave.VERSION)
	var loaded := GalaxySave.from_dict(e.data, save)
	assert_true(loaded.has("engine"), str(loaded.get("error", "")))
	var e2: GalaxyEngine = loaded["engine"]
	var home2: Planet = e2.state.planets[home.id]
	assert_eq(EmpireRules.pop(home2.colonies()[0]), 5)
	assert_eq(float(home2.colonies()[0]["growth"]), 2.5)
	assert_eq(home2.megaprojects, ["grand_archive"] as Array[String])
	assert_eq(e2.state.modifiers["patrol"][0]["turns"], 6)
	assert_eq(e2.state.event_log["patrol"]["seen"]["plague"], 7)
	assert_eq(e2.state.pending_event["event"], "market_boom")
	assert_eq(EmpireRules.income(e2, "patrol"), EmpireRules.income(e, "patrol"), "modifiers and wonders still count")
	assert_eq(_state_text(e2), _state_text(e))
	# The restored event can be answered.
	var answered := e2.submit(ResolveEventCommand.new("patrol", 0))
	assert_true(answered.ok, answered.error)


func test_saves_remember_how_the_game_ended() -> void:
	var e := GalaxyEngine.from_campaign(DataRegistry.get_default(), "random_sector", 6)
	e.start()
	e._finish("patrol", "science")
	var loaded := GalaxySave.from_dict(e.data, GalaxySave.to_dict(e, "random_sector"))
	assert_eq(loaded["engine"].state.victory_reason, "science")
	assert_eq(loaded["engine"].state.winner, "patrol")


func test_old_saves_are_rejected() -> void:
	var e := _campaign_at_turn(2)
	var save := GalaxySave.to_dict(e, "the_drift")
	save["version"] = 2
	var loaded := GalaxySave.from_dict(e.data, save)
	assert_true(loaded.has("error"), "version 2 saves predate population and megaprojects")
