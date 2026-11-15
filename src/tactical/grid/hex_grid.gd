class_name HexGrid
extends TacticalGrid
## Rectangular battlefield made of pointy-top hexes (HoMM-style), used for
## space battles. Layout coordinates are odd-r offset (column, row).

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
			var c := cell_from_layout(Vector2i(col, row))
			_cells.append(c)
			_cell_set[c] = true


## Builds a grid from a map definition (data/tactical/maps/*.json).
static func from_map(map_def: Dictionary, p_terrain_defs: Dictionary) -> HexGrid:
	var grid := HexGrid.new(int(map_def["width"]), int(map_def["height"]), p_terrain_defs)
	var terrain: Dictionary = map_def.get("terrain", {})
	for terrain_id: String in terrain:
		for pos: Array in terrain[terrain_id]:
			grid.set_terrain(grid.cell_from_layout(Vector2i(int(pos[0]), int(pos[1]))), terrain_id)
	return grid


func has_cell(c: Vector2i) -> bool:
	return _cell_set.has(c)


func cells() -> Array[Vector2i]:
	return _cells


func neighbors(c: Vector2i) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for n in Hex.neighbors(c):
		if has_cell(n):
			out.append(n)
	return out


func distance(a: Vector2i, b: Vector2i) -> int:
	return Hex.distance(a, b)


func line(a: Vector2i, b: Vector2i) -> Array[Vector2i]:
	return Hex.line(a, b)


func cells_within(center: Vector2i, radius: int) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for c in Hex.within(center, radius):
		if has_cell(c):
			out.append(c)
	return out


func cell_from_layout(layout: Vector2i) -> Vector2i:
	return Hex.oddr_to_axial(layout)


func layout_from_cell(c: Vector2i) -> Vector2i:
	return Hex.axial_to_oddr(c)


func to_pixel(c: Vector2i, cell_size: float) -> Vector2:
	return Hex.to_pixel(c, cell_size)


func from_pixel(p: Vector2, cell_size: float) -> Vector2i:
	return Hex.from_pixel(p, cell_size)


func cell_polygon(c: Vector2i, cell_size: float) -> PackedVector2Array:
	return Hex.corners(to_pixel(c, cell_size), cell_size)
