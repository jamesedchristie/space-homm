extends TestCase


func _grid() -> SquareGrid:
	var data := Fixtures.registry()
	return SquareGrid.from_map(data.maps["test_room"], data.terrain)


func test_chebyshev_distance() -> void:
	var g := _grid()
	assert_eq(g.distance(Vector2i(0, 0), Vector2i(3, 2)), 3)
	assert_eq(g.distance(Vector2i(2, 2), Vector2i(2, 2)), 0)


func test_neighbors_and_corner_cutting() -> void:
	var g := _grid()
	assert_eq(g.neighbors(Vector2i(5, 2)).size(), 8)
	assert_eq(g.neighbors(Vector2i(0, 0)).size(), 3)
	# (2,4) -> (3,3) would squeeze past the wall's corner at (3,3)... (3,3) is wall itself;
	# (4,4) -> (3,3) is a wall too, but (2,3)->(3,4) cuts the corner of wall (3,3).
	assert_false(Vector2i(3, 4) in g.neighbors(Vector2i(2, 3)), "no diagonal past a wall corner")
	assert_true(Vector2i(2, 4) in g.neighbors(Vector2i(2, 3)))


func test_walls_block_sight_and_paths_go_around() -> void:
	var g := _grid()
	assert_false(g.has_line_of_sight(Vector2i(1, 1), Vector2i(5, 1)))
	assert_true(g.has_line_of_sight(Vector2i(1, 5), Vector2i(5, 5)))
	var reach := Pathfinding.reachable(g, Vector2i(1, 1), 20, func(_c: Vector2i) -> bool: return false)
	assert_true(reach[Vector2i(5, 1)]["cost"] > 4, "must detour below the wall")


func test_pixel_round_trip() -> void:
	var g := _grid()
	for c in g.cells():
		assert_eq(g.from_pixel(g.to_pixel(c, 40.0), 40.0), c)
