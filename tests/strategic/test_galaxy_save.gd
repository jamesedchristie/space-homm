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
