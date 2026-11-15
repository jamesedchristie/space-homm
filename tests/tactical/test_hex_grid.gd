extends TestCase


func test_distance() -> void:
	assert_eq(Hex.distance(Vector2i(0, 0), Vector2i(0, 0)), 0)
	assert_eq(Hex.distance(Vector2i(0, 0), Vector2i(3, 0)), 3)
	assert_eq(Hex.distance(Vector2i(0, 0), Vector2i(2, -1)), 2)
	assert_eq(Hex.distance(Vector2i(-1, 2), Vector2i(2, -2)), 4)


func test_neighbors_are_all_distance_one() -> void:
	var ns := Hex.neighbors(Vector2i(2, 3))
	assert_eq(ns.size(), 6)
	for n in ns:
		assert_eq(Hex.distance(n, Vector2i(2, 3)), 1)


func test_within_counts() -> void:
	assert_eq(Hex.within(Vector2i.ZERO, 0).size(), 1)
	assert_eq(Hex.within(Vector2i.ZERO, 1).size(), 7)
	assert_eq(Hex.within(Vector2i.ZERO, 2).size(), 19)


func test_line_is_contiguous() -> void:
	var a := Vector2i(0, 0)
	var b := Vector2i(4, -2)
	var l := Hex.line(a, b)
	assert_eq(l.size(), Hex.distance(a, b) + 1)
	assert_eq(l[0], a)
	assert_eq(l[l.size() - 1], b)
	for i in range(1, l.size()):
		assert_eq(Hex.distance(l[i - 1], l[i]), 1)


func test_pixel_round_trip() -> void:
	for c in Hex.within(Vector2i(3, 2), 3):
		assert_eq(Hex.from_pixel(Hex.to_pixel(c, 40.0), 40.0), c)


func test_offset_round_trip() -> void:
	for row in 6:
		for col in 8:
			var layout := Vector2i(col, row)
			assert_eq(Hex.axial_to_oddr(Hex.oddr_to_axial(layout)), layout)


func test_rect_grid_bounds() -> void:
	var g := HexGrid.new(10, 6)
	assert_eq(g.cells().size(), 60)
	assert_true(g.has_cell(g.cell_from_layout(Vector2i(9, 5))))
	assert_false(g.has_cell(g.cell_from_layout(Vector2i(10, 0))))
	# Corner cells have fewer in-bounds neighbors.
	assert_eq(g.neighbors(g.cell_from_layout(Vector2i(0, 0))).size(), 2)


func test_terrain_blocks_movement_and_sight() -> void:
	var data := Fixtures.registry()
	var g := HexGrid.from_map(data.maps["test_wall"], data.terrain)
	var wall := g.cell_from_layout(Vector2i(2, 2))
	assert_eq(g.terrain_at(wall), "asteroid")
	assert_false(g.is_passable(wall))
	var left := g.cell_from_layout(Vector2i(0, 2))
	var right := g.cell_from_layout(Vector2i(4, 2))
	assert_false(g.has_line_of_sight(left, right), "asteroid wall should block LOS")
	assert_true(g.has_line_of_sight(left, g.cell_from_layout(Vector2i(1, 2))))


func test_pathfinding_goes_around_walls() -> void:
	var data := Fixtures.registry()
	var g := HexGrid.from_map(data.maps["test_wall"], data.terrain)
	var start := g.cell_from_layout(Vector2i(0, 2))
	var goal := g.cell_from_layout(Vector2i(4, 2))
	var reach := Pathfinding.reachable(g, start, 20, func(_c: Vector2i) -> bool: return false)
	assert_true(reach.has(goal))
	assert_true(reach[goal]["cost"] > g.distance(start, goal), "detour must cost more than straight line")
	var path := Pathfinding.path_to(reach, goal)
	assert_eq(path[0], start)
	assert_eq(path[path.size() - 1], goal)
	for c in path:
		assert_true(g.is_passable(c))


func test_pathfinding_respects_budget_and_nebula_cost() -> void:
	var data := Fixtures.registry()
	var g := HexGrid.new(6, 1, data.terrain)
	g.set_terrain(g.cell_from_layout(Vector2i(1, 0)), "nebula")
	var start := g.cell_from_layout(Vector2i(0, 0))
	var reach := Pathfinding.reachable(g, start, 3, func(_c: Vector2i) -> bool: return false)
	assert_eq(reach[g.cell_from_layout(Vector2i(1, 0))]["cost"], 2)
	assert_eq(reach[g.cell_from_layout(Vector2i(2, 0))]["cost"], 3)
	assert_false(reach.has(g.cell_from_layout(Vector2i(3, 0))))
