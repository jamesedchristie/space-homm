extends TestCase
## SystemBattleMap: battles inside a star system.

var _data: DataRegistry


func before_each() -> void:
	_data = Fixtures.registry()


func _bodies(types: Array) -> Array:
	var out: Array = []
	for i in types.size():
		out.append({"id": "s_%d" % i, "type": types[i], "name": "S %d" % i})
	return out


func _grid(map: Dictionary) -> TacticalGrid:
	return GridFactory.from_map(map, _data.terrain)


func _cell_set(grid: TacticalGrid, pairs: Array) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for p: Array in pairs:
		out.append(grid.cell_from_layout(Vector2i(int(p[0]), int(p[1]))))
	return out


func test_deterministic() -> void:
	var bodies := _bodies(["volcanic", "terran", "asteroid_belt", "gas_giant"])
	var a := SystemBattleMap.build_for(_data, "sol", "Sol", "yellow", bodies, "s_1")
	var b := SystemBattleMap.build_for(_data, "sol", "Sol", "yellow", bodies, "s_1")
	assert_eq(a, b, "same system, same map")
	var c := SystemBattleMap.build_for(_data, "other", "Other", "yellow", bodies, "s_1")
	assert_ne(a["terrain"], c["terrain"], "another system lays out differently")


func test_planets_are_impassable_and_block_sight() -> void:
	var map := SystemBattleMap.build_for(_data, "sol", "Sol", "yellow", _bodies(["terran", "gas_giant", "ice_moon"]), "s_0")
	var grid := _grid(map)
	assert_true(_data.terrain["planet"]["blocks_sight"])
	var planet_cells := 0
	for body: Dictionary in map["bodies"]:
		assert_eq(body["kind"], "planet")
		var cells := _cell_set(grid, body["cells"])
		assert_true(cells.size() in [1, 3, 7], "1, 3 or 7 hexes")
		for c in cells:
			planet_cells += 1
			assert_false(grid.is_passable(c))
			assert_true(grid.blocks_sight(c))
	assert_eq((map["terrain"]["planet"] as Array).size(), planet_cells)
	# A planet in the line of fire hides what is behind it.
	var body_cells := _cell_set(grid, map["bodies"][0]["cells"])
	var center := body_cells[0]
	var behind := center + Vector2i(3, 0)
	var before := center - Vector2i(3, 0)
	if grid.has_cell(behind) and grid.has_cell(before) and grid.is_passable(behind) and grid.is_passable(before):
		assert_false(grid.has_line_of_sight(before, behind))


func test_bodies_sizes_and_types() -> void:
	var map := SystemBattleMap.build_for(_data, "sol", "Sol", "yellow", _bodies(["terran", "ice_moon", "gas_giant", "asteroid_belt"]), "s_0")
	var by_type := {}
	for body: Dictionary in map["bodies"]:
		by_type[body["type"]] = body
	if by_type.has("terran"):  # shrunk only when the layout would not fit
		assert_true(by_type["terran"]["cells"].size() in [7, 3, 1])
	assert_eq(by_type["ice_moon"]["cells"].size(), 1)
	assert_eq(by_type["asteroid_belt"]["kind"], "belt")
	assert_true(map["terrain"].has("debris") or map["terrain"].has("asteroid"))
	assert_eq(map["star"]["side"], "north")


func test_deployment_free_and_connected() -> void:
	for i in 40:
		var rng := RandomNumberGenerator.new()
		rng.seed = i
		var bodies := SystemBuilder.random_bodies(_data, rng, "sys%d" % i, "Sys %d" % i, i % 3 == 0)
		var colony := ""
		for b: Dictionary in bodies:
			if _data.body_types[b["type"]].get("category", "") == "habitable":
				colony = b["id"]
				break
		var map := SystemBattleMap.build_for(_data, "sys%d" % i, "Sys %d" % i, "red", bodies, colony)
		assert_eq(SystemBattleMap.check(map, _data.terrain), "", "system %d" % i)
		var grid := _grid(map)
		var seen := {}
		for side: String in ["west", "east"]:
			var slots := _cell_set(grid, map["deployment"][side])
			assert_true(slots.size() >= 6, "six slots")
			for c in slots:
				assert_true(grid.has_cell(c) and grid.is_passable(c) and grid.terrain_at(c) == "", "slot is open space")
				assert_false(seen.has(c), "slots are distinct")
				seen[c] = true
		# Every passable cell is reachable from the first attacker slot.
		var start: Vector2i = _cell_set(grid, map["deployment"]["west"])[0]
		var reach := {start: true}
		var queue: Array[Vector2i] = [start]
		while not queue.is_empty():
			var c: Vector2i = queue.pop_back()
			for n in grid.neighbors(c):
				if not reach.has(n) and grid.is_passable(n):
					reach[n] = true
					queue.append(n)
		for c in grid.cells():
			if grid.is_passable(c):
				assert_true(reach.has(c), "every open cell is reachable (system %d)" % i)


func test_defender_deploys_around_its_colony() -> void:
	var bodies := _bodies(["volcanic", "terran", "gas_giant"])
	var map := SystemBattleMap.build_for(_data, "sol", "Sol", "yellow", bodies, "s_1")
	var grid := _grid(map)
	var colony_cells: Array[Vector2i] = []
	for body: Dictionary in map["bodies"]:
		if body["colony"]:
			colony_cells = _cell_set(grid, body["cells"])
	assert_false(colony_cells.is_empty())
	for c in _cell_set(grid, map["deployment"]["east"]):
		var nearest := 99
		for o in colony_cells:
			nearest = mini(nearest, grid.distance(c, o))
		assert_true(nearest <= 3, "defender slot hugs the colony body")
	# No colony: the east edge.
	var plain := SystemBattleMap.build_for(_data, "sol", "Sol", "yellow", bodies, "")
	for p: Array in plain["deployment"]["east"]:
		assert_true(int(p[0]) >= plain["width"] - 2)


func test_check_rejects_broken_maps() -> void:
	var map := SystemBattleMap.build_for(_data, "sol", "Sol", "yellow", _bodies(["terran"]), "s_0")
	assert_eq(SystemBattleMap.check(map, _data.terrain), "")
	var blocked: Dictionary = map.duplicate(true)
	blocked["terrain"]["planet"].append(blocked["deployment"]["west"][0])
	assert_ne(SystemBattleMap.check(blocked, _data.terrain), "", "slot on a planet")
	var walled: Dictionary = map.duplicate(true)
	var wall: Array = []
	for r in walled["height"]:
		wall.append([8, r])
	walled["terrain"]["planet"] = wall
	assert_ne(SystemBattleMap.check(walled, _data.terrain), "", "a full wall splits the map")


func test_system_cell_battle_uses_system_map() -> void:
	var e := Fixtures.galaxy([["a", "test_fast_dummy", 3, 2], ["b", "test_dummy", 5, 3]])
	var a: Fleet = e.state.fleets_of("a")[0]
	var b: Fleet = e.state.fleets_of("b")[0]
	# Fight in the middle system (5,3).
	e.state.pending_battle = {"cell": b.cell, "attacker": a.id, "defender": b.id}
	var scenario := e.pending_battle_scenario()
	assert_true(scenario["map_def"].get("system", false), "system map")
	assert_eq(scenario["map"], scenario["map_def"]["id"])
	assert_eq(scenario["map_def"], e.pending_battle_scenario()["map_def"], "stable between calls")
	var engine := BattleEngine.from_scenario(e.data, scenario, 7)
	assert_true(engine != null)
	assert_false(engine.state.scenery.is_empty(), "scenery for the presentation")
	assert_eq(engine.state.grid.width if engine.state.grid is HexGrid else 0, scenario["map_def"]["width"])
	# Deep space keeps the data map.
	var open_cell := e.state.grid.cell_from_layout(Vector2i(2, 1))
	b.cell = open_cell
	e.state.pending_battle = {"cell": open_cell, "attacker": a.id, "defender": b.id}
	var plain := e.pending_battle_scenario()
	assert_eq(plain["map"], "open_space")
	assert_true((plain["map_def"] as Dictionary).is_empty())
