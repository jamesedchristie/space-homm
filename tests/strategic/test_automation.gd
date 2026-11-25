extends TestCase
## Phase 7 automation: automated civilian ships, auto-explore and colony governors.


func _run(e: GalaxyEngine, auto: Automation, faction: String) -> Array[GalaxyCommand]:
	var done: Array[GalaxyCommand] = []
	for i in 40:
		var cmd := auto.next_command(e, faction)
		if cmd == null:
			break
		var r := e.submit(cmd)
		assert_true(r.ok, "%s: %s" % [cmd.to_dict(), r.error])
		done.append(cmd)
	return done


func test_governor_queues_a_build_when_idle() -> void:
	var e := GalaxyEngine.from_campaign(DataRegistry.get_default(), "solar_age", 2)
	e.start()
	var home: Planet = e.state.planets_of("patrol")[0]
	home.queue = {}
	var auto := Automation.new()
	assert_true(_run(e, auto, "patrol").is_empty(), "nothing is automated yet")
	home.auto_build = true
	var cmds := _run(e, Automation.new(), "patrol")
	assert_eq(cmds.size(), 1)
	assert_true(cmds[0] is QueueBuildCommand)
	assert_false(home.queue.is_empty())


func test_automated_constructor_gets_to_work() -> void:
	var e := GalaxyEngine.from_campaign(DataRegistry.get_default(), "solar_age", 2)
	e.start()
	var foreman: Fleet = null
	for f: Fleet in e.state.fleets_of("patrol"):
		if f.name == "Foreman":
			foreman = f
	var uid: String = foreman.ships[0]["uid"]
	foreman.ships[0]["auto"] = true
	assert_true(Automation.is_automated(e, foreman))
	var auto := Automation.new()
	var working := false
	for turn in 8:
		_run(e, auto, "patrol")
		var where := SystemRules.locate_ship(e, "patrol", uid)
		if where.has("planet") and not where["ship"].get("job", {}).is_empty():
			working = true
			break
		# Let everyone else play the round out.
		var ai := GalaxyAI.new()
		e.submit(EndFactionTurnCommand.new("patrol"))
		var guard := 0
		while e.current_faction_id() != "patrol" and not e.state.is_over and guard < 500:
			guard += 1
			if e.has_pending_battle():
				e.auto_resolve_pending_battle()
				continue
			if e.has_pending_mission():
				e.auto_resolve_pending_mission()
				continue
			if not e.submit(ai.decide(e)).ok:
				e.submit(EndFactionTurnCommand.new(e.current_faction_id()))
	assert_true(working, "the automated constructor should have started a job on its own")
	var where := SystemRules.locate_ship(e, "patrol", uid)
	assert_true(Automation.is_automated_ship(where["ship"]), "and stays automated while it works")


func test_auto_explore_heads_for_uncharted_space() -> void:
	var e := GalaxyEngine.from_campaign(DataRegistry.get_default(), "random_sector", 3)
	e.start()
	var fleet: Fleet = null
	for f: Fleet in e.state.fleets_of("patrol"):
		if not f.is_civilian_only(e.data):
			fleet = f
			break
	fleet.auto = "explore"
	var before := e.explored_cells("patrol").size()
	var cmds := _run(e, Automation.new(), "patrol")
	assert_false(cmds.is_empty())
	assert_true(cmds[0] is MoveFleetCommand)
	assert_true(e.explored_cells("patrol").size() > before, "it charted something")
	assert_true(Automation.is_automated(e, fleet), "an exploring fleet doesn't wait for orders")


func test_automation_survives_a_save() -> void:
	var e := GalaxyEngine.from_campaign(DataRegistry.get_default(), "random_sector", 3)
	e.start()
	var fleet: Fleet = e.state.fleets_of("patrol")[0]
	fleet.auto = "explore"
	fleet.ships[0]["auto"] = true
	var p: Planet = e.state.planets.values()[0]
	p.auto_build = true
	var e2: GalaxyEngine = GalaxySave.from_dict(e.data, GalaxySave.to_dict(e, "random_sector"))["engine"]
	assert_eq(e2.state.fleets[fleet.id].auto, "explore")
	assert_true(Automation.is_automated_ship(e2.state.fleets[fleet.id].ships[0]))
	assert_true(e2.state.planets[p.id].auto_build)
