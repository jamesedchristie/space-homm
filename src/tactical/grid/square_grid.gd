class_name SquareGrid
extends TacticalGrid
## Square-cell battlefield for ground and station missions. 8-way movement,
## diagonals cost the same as straight steps (Chebyshev distance), and
## diagonal moves can't cut corners past walls.
## Layout coordinates are (column, row), same as cell coordinates.

## Cell pitch relative to the shared cell_size (hex cell_size is a radius).
const PITCH := 1.8

var width: int
var height: int
var _cells: Array[Vector2i] = []
var _cell_set: Dictionary = {}


func _init(p_width: int = 0, p_height: int = 0, p_terrain_defs: Dictionary = {}) -> void:
	width = p_width
	height = p_height
	terrain_defs = p_terrain_defs
	for row in height:
		for col in width:
			var c := Vector2i(col, row)
			_cells.append(c)
			_cell_set[c] = true


static func from_map(map_def: Dictionary, p_terrain_defs: Dictionary) -> SquareGrid:
	var grid := SquareGrid.new(int(map_def["width"]), int(map_def["height"]), p_terrain_defs)
	var terrain: Dictionary = map_def.get("terrain", {})
	for terrain_id: String in terrain:
		for pos: Array in terrain[terrain_id]:
			grid.set_terrain(Vector2i(int(pos[0]), int(pos[1])), terrain_id)
	return grid


func has_cell(c: Vector2i) -> bool:
	return _cell_set.has(c)


func cells() -> Array[Vector2i]:
	return _cells


func neighbors(c: Vector2i) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for dy in [-1, 0, 1]:
		for dx in [-1, 0, 1]:
			if dx == 0 and dy == 0:
				continue
			var n := c + Vector2i(dx, dy)
			if not has_cell(n):
				continue
			if dx != 0 and dy != 0:
				# No squeezing diagonally between two blocked cells' corners.
				if not is_passable(c + Vector2i(dx, 0)) or not is_passable(c + Vector2i(0, dy)):
					continue
			out.append(n)
	return out


func distance(a: Vector2i, b: Vector2i) -> int:
	return maxi(absi(a.x - b.x), absi(a.y - b.y))


## Cells on the line from a to b (inclusive), sampled at cell centres.
func line(a: Vector2i, b: Vector2i) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	var n := distance(a, b)
	if n == 0:
		out.append(a)
		return out
	for i in range(n + 1):
		var t := float(i) / float(n)
		var p := Vector2(a).lerp(Vector2(b), t)
		var c := Vector2i(roundi(p.x + 1e-6), roundi(p.y + 2e-6))
		if out.is_empty() or out[out.size() - 1] != c:
			out.append(c)
	return out


func cells_within(center: Vector2i, radius: int) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for dy in range(-radius, radius + 1):
		for dx in range(-radius, radius + 1):
			var c := center + Vector2i(dx, dy)
			if has_cell(c):
				out.append(c)
	return out


func to_pixel(c: Vector2i, cell_size: float) -> Vector2:
	return Vector2(c) * cell_size * PITCH


func from_pixel(p: Vector2, cell_size: float) -> Vector2i:
	var f := p / (cell_size * PITCH)
	return Vector2i(roundi(f.x), roundi(f.y))


func cell_polygon(c: Vector2i, cell_size: float) -> PackedVector2Array:
	var center := to_pixel(c, cell_size)
	var h := cell_size * PITCH * 0.5
	return PackedVector2Array([center + Vector2(-h, -h), center + Vector2(h, -h),
			center + Vector2(h, h), center + Vector2(-h, h)])
