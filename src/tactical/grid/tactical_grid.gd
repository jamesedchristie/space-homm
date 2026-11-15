class_name TacticalGrid
extends RefCounted
## Abstract battlefield grid. The tactical engine only talks to this interface,
## so fleet battles (HexGrid) and, later, ground missions (a SquareGrid) share
## every rule, ability and AI routine.
##
## Cells are Vector2i in the grid's own coordinate system. Content files use
## "layout" coordinates (column, row); convert with cell_from_layout().

## Terrain definitions from data/tactical/terrain.json, keyed by id.
var terrain_defs: Dictionary = {}
var _terrain: Dictionary = {}  # Vector2i -> terrain id


# --- Topology: subclasses must implement these --------------------------------

func has_cell(_c: Vector2i) -> bool:
	push_error("TacticalGrid.has_cell not implemented")
	return false


func cells() -> Array[Vector2i]:
	push_error("TacticalGrid.cells not implemented")
	return []


## In-bounds neighbors.
func neighbors(_c: Vector2i) -> Array[Vector2i]:
	push_error("TacticalGrid.neighbors not implemented")
	return []


func distance(_a: Vector2i, _b: Vector2i) -> int:
	push_error("TacticalGrid.distance not implemented")
	return 0


func line(_a: Vector2i, _b: Vector2i) -> Array[Vector2i]:
	push_error("TacticalGrid.line not implemented")
	return []


## In-bounds cells within `radius` of center.
func cells_within(_center: Vector2i, _radius: int) -> Array[Vector2i]:
	push_error("TacticalGrid.cells_within not implemented")
	return []


func cell_from_layout(layout: Vector2i) -> Vector2i:
	return layout


func layout_from_cell(c: Vector2i) -> Vector2i:
	return c


# --- Geometry for presentation ------------------------------------------------

func to_pixel(_c: Vector2i, _cell_size: float) -> Vector2:
	push_error("TacticalGrid.to_pixel not implemented")
	return Vector2.ZERO


func from_pixel(_p: Vector2, _cell_size: float) -> Vector2i:
	push_error("TacticalGrid.from_pixel not implemented")
	return Vector2i.ZERO


func cell_polygon(_c: Vector2i, _cell_size: float) -> PackedVector2Array:
	push_error("TacticalGrid.cell_polygon not implemented")
	return PackedVector2Array()


# --- Terrain (shared by every grid type) --------------------------------------

func set_terrain(c: Vector2i, terrain_id: String) -> void:
	if terrain_id.is_empty():
		_terrain.erase(c)
	else:
		_terrain[c] = terrain_id


func terrain_at(c: Vector2i) -> String:
	return _terrain.get(c, "")


func terrain_def(c: Vector2i) -> Dictionary:
	return terrain_defs.get(terrain_at(c), {})


func is_passable(c: Vector2i) -> bool:
	return has_cell(c) and terrain_def(c).get("passable", true)


func blocks_sight(c: Vector2i) -> bool:
	return terrain_def(c).get("blocks_sight", false)


## AP cost to enter the cell.
func move_cost(c: Vector2i) -> int:
	return int(terrain_def(c).get("move_cost", 1))


## True if no sight-blocking terrain lies strictly between a and b.
## Units never block line of sight (keeps targeting readable).
func has_line_of_sight(a: Vector2i, b: Vector2i) -> bool:
	for c in line(a, b):
		if c != a and c != b and blocks_sight(c):
			return false
	return true
