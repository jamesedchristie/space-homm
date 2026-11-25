extends TestCase
## Hyperlane campaigns (Random Sector): the generated lane network, lane-only movement, relic gates
## and Jump Gates.


func _sector(seed_value: int = 1) -> GalaxyEngine:
	var e := GalaxyEngine.from_campaign(DataRegistry.get_default(), "random_sector", seed_value)
	e.start()
	return e


func test_lane_network_connects_every_system() -> void:
	for seed_value in [1, 2, 3]:
		var e := GalaxyEngine.from_campaign(DataRegistry.get_default(), "random_sector", seed_value)
		var s := e.state
		assert_true(e.has_lanes())
		assert_true(e.lanes().size() >= s.planets.size() - 1, "too few lanes")
		var home: Planet = s.planets_of(s.factions[0]["id"])[0] if not s.planets_of(s.factions[0]["id"]).is_empty() \
				else s.planets.values()[0]
		var field := Pathfinding.distance_field(s.grid, [home.cell] as Array[Vector2i])
		for p: Planet in s.planets.values():
			assert_true(field.has(p.cell), "seed %d: %s is cut off" % [seed_value, p.name])
		for a: Dictionary in s.anomalies.values():
			assert_true(field.has(a["cell"]), "seed %d: mission site %s is cut off" % [seed_value, a["name"]])
		var relics := 0
		for p: Planet in s.planets.values():
			if e.gate_kind(p) == "relic":
				relics += 1
		assert_eq(relics, 3, "seed %d relic gates" % seed_value)


func test_fleets_only_move_along_lanes() -> void:
	var e := _sector()
	var s := e.state
	for f: Fleet in s.fleets.values():
		assert_true(s.grid.is_passable(f.cell), "%s starts in the void" % f.name)
		for c: Vector2i in e.reachable_for(f.id):
			assert_ne(s.grid.terrain_at(c), "void")


func test_intel_levels() -> void:
	var e := _sector()
	var s := e.state
	var player: String = s.factions[0]["id"]
	var home: Planet = s.planets_of(player)[0] if not s.planets_of(player).is_empty() else null
	# A rival's home far away: charted only, owner unknown.
	var rival: Planet = s.planets_of("kesh")[0] if not s.planets_of("kesh").is_empty() else null
	if rival == null:
		for p: Planet in s.planets.values():
			if not p.capital.is_empty() and p.capital["faction"] == "kesh":
				rival = p
	rival.owner = "kesh"
	assert_eq(e.intel_level(player, rival), "charted")
	assert_eq(e.known_owner(player, rival), "?")
	# Scout it: live, then out of sight it is remembered as last seen.
	var scout: Fleet = s.fleets_of(player)[0]
	var old_cell := scout.cell
	scout.cell = rival.cell + Vector2i(0, 0)
	e._reveal_around(scout)
	assert_eq(e.intel_level(player, rival), "live")
	assert_eq(e.known_owner(player, rival), "kesh")
	scout.cell = old_cell
	assert_true(e.intel_level(player, rival) in ["scanned", "surveyed"])
	assert_eq(e.last_seen(player, rival), s.turn_number)
	rival.owner = "veltari"  # changes hands out of sight
	assert_eq(e.known_owner(player, rival), "kesh", "you only know what you last saw")
	if home != null:
		assert_eq(e.intel_level(player, home), "live")


func test_jump_through_a_relic_gate() -> void:
	var e := _sector()
	var s := e.state
	var player: String = s.factions[0]["id"]
	var gates: Array[Planet] = []
	for p: Planet in s.planets.values():
		if e.gate_kind(p) == "relic":
			gates.append(p)
	var fleet: Fleet = s.fleets_of(player)[0]
	fleet.cell = gates[0].cell
	fleet.moves_left = 2
	var dests := e.gate_destinations(fleet.id)
	assert_true(gates[1].cell in dests or gates[2].cell in dests, "relic gates should link: %s" % [dests])
	var to: Vector2i = dests[0]
	var result := e.submit(MoveFleetCommand.new(player, fleet.id, to))
	assert_true(result.ok, result.error)
	assert_eq(fleet.cell, to)
	assert_eq(fleet.moves_left, 0)
	assert_true(e.gate_destinations(fleet.id).is_empty(), "no moves left: no more jumps")


func test_jump_gates_link_their_owners_systems_only() -> void:
	var e := _sector()
	var s := e.state
	var player: String = s.factions[0]["id"]
	var others: Array[Planet] = []
	for p: Planet in s.planets.values():
		if p.owner.is_empty() and p.gate.is_empty() and s.fleet_at(p.cell) == null:
			others.append(p)
	var a := others[0]
	var b := others[1]
	for p in [a, b]:
		p.owner = player
		p.add_building(p.bodies[0]["id"], "jump_gate")
	assert_eq(e.gate_kind(a), "jump")
	var fleet: Fleet = s.fleets_of(player)[0]
	fleet.cell = a.cell
	fleet.moves_left = 1
	assert_true(b.cell in e.gate_destinations(fleet.id))
	# Someone else's fleet at our gate can't use it.
	var rival: Fleet = s.fleets_of(s.factions[1]["id"])[0]
	fleet.cell = s.planets_of(player)[0].cell if not s.planets_of(player).is_empty() else fleet.cell
	rival.cell = a.cell
	rival.moves_left = 3
	assert_true(e.gate_destinations(rival.id).is_empty())


func test_lanes_and_gates_survive_a_save() -> void:
	var e := _sector(2)
	var e2: GalaxyEngine = GalaxySave.from_dict(e.data, GalaxySave.to_dict(e, "random_sector"))["engine"]
	assert_eq(e2.lanes(), e.lanes())
	for p: Planet in e.state.planets.values():
		assert_eq(e2.state.planets[p.id].gate, p.gate)
		assert_eq(e2.state.grid.terrain_at(p.cell), e.state.grid.terrain_at(p.cell))
