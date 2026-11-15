class_name GridMapView
extends Node2D
## Draws a grid (battlefield or galaxy), its terrain, highlights and optional
## fog of war. Grid-agnostic: it only uses TacticalGrid geometry, so it will
## draw a square grid just as well. Child nodes (units, fleets, planets, fx)
## are positioned in the same local space via cell_center().

const CELL_SIZE := 40.0

var grid: TacticalGrid
var _reachable: Dictionary = {}
var _targets: Dictionary = {}
var _area: Dictionary = {}
var _path: Array[Vector2i] = []
var _hover: Variant = null
var _active: Variant = null
var _fog_enabled := false
var _explored: Dictionary = {}
var _visible: Dictionary = {}
## cell -> {"color": Color, "label": String} (objectives, triggers, ...)
var _markers: Dictionary = {}


func setup(p_grid: TacticalGrid) -> void:
	grid = p_grid
	_reachable.clear()
	_targets.clear()
	_area.clear()
	_path.clear()
	_hover = null
	_active = null
	queue_redraw()


func cell_center(c: Vector2i) -> Vector2:
	return grid.to_pixel(c, CELL_SIZE)


## Grid cell under a global position, or null.
func cell_at_global(global_pos: Vector2) -> Variant:
	if grid == null:
		return null
	var c := grid.from_pixel(to_local(global_pos), CELL_SIZE)
	return c if grid.has_cell(c) else null


## Local-space rectangle covering the whole grid.
func bounds() -> Rect2:
	var rect := Rect2()
	var first := true
	for c in grid.cells():
		for p in grid.cell_polygon(c, CELL_SIZE):
			if first:
				rect = Rect2(p, Vector2.ZERO)
				first = false
			else:
				rect = rect.expand(p)
	return rect


func set_highlights(reachable: Array[Vector2i], targets: Array[Vector2i], area: Array[Vector2i], path: Array[Vector2i]) -> void:
	_reachable = _to_set(reachable)
	_targets = _to_set(targets)
	_area = _to_set(area)
	_path = path
	queue_redraw()


func set_hover(cell: Variant) -> void:
	_hover = cell
	queue_redraw()


func set_active(cell: Variant) -> void:
	_active = cell
	queue_redraw()


## Fog of war: unexplored cells are black, explored-but-not-visible are dimmed.
func set_fog(explored: Dictionary, visible_now: Dictionary) -> void:
	_fog_enabled = true
	_explored = explored
	_visible = visible_now
	queue_redraw()


func set_markers(markers: Dictionary) -> void:
	_markers = markers
	queue_redraw()


func clear_fog() -> void:
	_fog_enabled = false
	queue_redraw()


func _draw() -> void:
	if grid == null:
		return
	for c in grid.cells():
		var poly := _inset_polygon(c)
		if _fog_enabled and not _explored.has(c):
			draw_colored_polygon(poly, Palette.FOG_UNEXPLORED)
		else:
			var terrain := grid.terrain_def(c)
			draw_colored_polygon(poly, Color(terrain["color"]) if terrain.has("color") else Palette.CELL_FILL)
			match terrain.get("decoration", ""):
				"rocks":
					_draw_rocks(c)
				"crates":
					_draw_crates(c)
			if _fog_enabled and not _visible.has(c):
				draw_colored_polygon(poly, Palette.FOG_DIM)
		if _reachable.has(c):
			draw_colored_polygon(poly, Palette.REACHABLE)
		if _targets.has(c):
			draw_colored_polygon(poly, Palette.TARGET)
		if _area.has(c):
			draw_colored_polygon(poly, Palette.AREA)
		_outline(poly, Palette.CELL_LINE, 1.0)

	for i in range(1, _path.size()):
		draw_line(cell_center(_path[i - 1]), cell_center(_path[i]), Palette.PATH, 3.0, true)
	if not _path.is_empty():
		draw_circle(cell_center(_path[_path.size() - 1]), 5.0, Palette.PATH)

	var font := ThemeDB.fallback_font
	for c: Vector2i in _markers:
		var m: Dictionary = _markers[c]
		if _fog_enabled and not _explored.has(c) and not m.get("always", false):
			continue
		var center := cell_center(c)
		draw_arc(center, CELL_SIZE * 0.55, 0, TAU, 32, m["color"], 2.5, true)
		draw_string(font, center + Vector2(-20, 7), m.get("label", ""), HORIZONTAL_ALIGNMENT_CENTER, 40, 20, m["color"])

	if _active != null:
		_outline(_inset_polygon(_active), Palette.ACTIVE, 2.5)
	if _hover != null:
		_outline(_inset_polygon(_hover), Palette.HOVER, 2.0)


## The cell's outline shrunk slightly toward its own centre, so neighbouring
## cells show a gap. (Shrinking via a smaller cell size would also move the
## centre and misalign the grid with units.)
func _inset_polygon(c: Vector2i, inset: float = 0.94) -> PackedVector2Array:
	var center := cell_center(c)
	var out := PackedVector2Array()
	for p in grid.cell_polygon(c, CELL_SIZE):
		out.append(center + (p - center) * inset)
	return out


func _draw_rocks(c: Vector2i) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(c)
	var center := cell_center(c)
	for i in 3:
		var offset := Vector2(rng.randf_range(-12, 12), rng.randf_range(-10, 10))
		var r := rng.randf_range(7, 14)
		draw_circle(center + offset, r, Color(0.42, 0.36, 0.30))
		draw_circle(center + offset + Vector2(-r * 0.25, -r * 0.25), r * 0.45, Color(0.55, 0.48, 0.40))


func _draw_crates(c: Vector2i) -> void:
	var center := cell_center(c)
	var s := CELL_SIZE * 0.45
	for offset: Vector2 in [Vector2(-s * 0.55, -s * 0.4), Vector2(s * 0.5, -s * 0.3), Vector2(0, s * 0.5)]:
		var r := Rect2(center + offset - Vector2(s, s) * 0.45, Vector2(s, s) * 0.9)
		draw_rect(r, Color(0.45, 0.5, 0.38))
		draw_rect(r, Color(0.25, 0.28, 0.2), false, 1.5)


func _outline(poly: PackedVector2Array, color: Color, width: float) -> void:
	var closed := poly.duplicate()
	closed.append(poly[0])
	draw_polyline(closed, color, width, true)


func _to_set(cells: Array[Vector2i]) -> Dictionary:
	var d := {}
	for c in cells:
		d[c] = true
	return d
