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
var _floor := ""
## System battles: bodies [{"center": Vector2, "radius": px, "base", "accent", "atmosphere": Color, "ring", "colony": bool}]
## and the star {"pos": Vector2, "color": Color}; drawn over the terrain cells.
var _bodies: Array[Dictionary] = []
var _star: Dictionary = {}

## Big meteors first (indices 0-3), then medium ones.
const METEORS := ["meteorBrown_big1", "meteorGrey_big2", "meteorBrown_big3", "meteorGrey_big4",
		"meteorBrown_med1", "meteorGrey_med2", "meteorBrown_med3", "meteorGrey_med1"]
static var _meteors: Array[Texture2D] = []


## floor: "" (open space: translucent cells) or "deck" (metal plating, for
## station and ship interiors).
func setup(p_grid: TacticalGrid, floor_style: String = "") -> void:
	grid = p_grid
	_floor = floor_style
	_reachable.clear()
	_targets.clear()
	_area.clear()
	_path.clear()
	_hover = null
	_active = null
	queue_redraw()


## Planets and star of a battle inside a star system (see SystemBattleMap).
func set_scenery(bodies: Array[Dictionary], star: Dictionary) -> void:
	_bodies = bodies
	_star = star
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
			if _floor == "deck" and terrain.get("decoration", "") != "bulkhead":
				_draw_deck_plate(c)
			if terrain.has("color") and not (_floor == "deck" and terrain.get("decoration", "") == "crates"):
				draw_colored_polygon(poly, Color(terrain["color"]))
			elif not terrain.has("color") and _floor != "deck":
				draw_colored_polygon(poly, Palette.CELL_FILL)
			match terrain.get("decoration", ""):
				"rocks":
					_draw_rocks(c)
				"debris":
					_draw_debris(c)
				"crates":
					_draw_crates(c)
				"bulkhead":
					_draw_bulkhead(c)
				"hazard":
					_draw_hazard(c)
			if _fog_enabled and not _visible.has(c):
				draw_colored_polygon(poly, Palette.FOG_DIM)
		if _reachable.has(c):
			draw_colored_polygon(poly, Palette.REACHABLE)
		if _targets.has(c):
			draw_colored_polygon(poly, Palette.TARGET)
		if _area.has(c):
			draw_colored_polygon(poly, Palette.AREA)
		_outline(poly, Palette.CELL_LINE, 1.0)

	_draw_scenery()
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


func _draw_scenery() -> void:
	if not _star.is_empty():
		var color: Color = _star["color"]
		for k in 4:
			draw_circle(_star["pos"], CELL_SIZE * (3.2 - k * 0.7), Color(color, 0.07 + 0.06 * k))
	for b in _bodies:
		var center: Vector2 = b["center"]
		var r: float = b["radius"]
		var atmo: Color = b["atmosphere"]
		if atmo.a > 0.05:
			draw_circle(center, r * 1.08, Color(atmo, 0.35))
		draw_circle(center, r, b["base"])
		draw_circle(center + Vector2(-r * 0.18, -r * 0.12), r * 0.62, Color(b["accent"], 0.45))
		draw_arc(center, r, 0, TAU, 40, Color(b["accent"], 0.7), 1.5, true)
		if b["ring"]:
			draw_arc(center, r * 1.4, 0, TAU, 48, Color(b["accent"], 0.55), 3.0, true)
		if b["colony"]:
			for k in 7:
				var a := k * 2.4
				draw_circle(center + Vector2(cos(a), sin(a)) * r * (0.2 + 0.07 * k), 1.6, Color(1.0, 0.85, 0.5))


## The cell's outline shrunk slightly toward its own centre, so neighbouring
## cells show a gap. (Shrinking via a smaller cell size would also move the
## centre and misalign the grid with units.)
func _inset_polygon(c: Vector2i, inset: float = 0.94) -> PackedVector2Array:
	var center := cell_center(c)
	var out := PackedVector2Array()
	for p in grid.cell_polygon(c, CELL_SIZE):
		out.append(center + (p - center) * inset)
	return out


## A few specks of rubble (ring dust, belt debris).
func _draw_debris(c: Vector2i) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(c)
	var center := cell_center(c)
	for i in 6:
		var p := center + Vector2(rng.randf_range(-16, 16), rng.randf_range(-13, 13))
		draw_circle(p, rng.randf_range(1.2, 3.0), Color(0.62, 0.56, 0.5, rng.randf_range(0.5, 0.9)))


## Two meteor sprites per asteroid cell, picked and rotated deterministically.
func _draw_rocks(c: Vector2i) -> void:
	if _meteors.is_empty():
		for meteor in METEORS:
			_meteors.append(load("res://assets/kenney_space_shooter/meteors/%s.png" % meteor))
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(c)
	var center := cell_center(c)
	for i in 2:
		var tex: Texture2D = _meteors[rng.randi_range(0 if i == 0 else 4, 3 if i == 0 else _meteors.size() - 1)]
		var target := CELL_SIZE * (1.1 if i == 0 else 0.55)
		var s := target / maxf(tex.get_width(), tex.get_height())
		var offset := Vector2(rng.randf_range(-8, 8), rng.randf_range(-6, 6)) if i == 0 else Vector2(rng.randf_range(-16, 16), rng.randf_range(-12, 12))
		draw_set_transform(center + offset, rng.randf() * TAU, Vector2(s, s))
		draw_texture(tex, -tex.get_size() / 2.0, Color(0.85, 0.85, 0.85))
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


## Metal floor plate with seams and rivets.
func _draw_deck_plate(c: Vector2i) -> void:
	var r := _cell_rect(c)
	draw_rect(r, Color(0.11, 0.14, 0.18))
	var inner := r.grow(-3.0)
	draw_rect(inner, Color(0.15, 0.19, 0.24))
	draw_rect(inner, Color(0.07, 0.09, 0.12), false, 1.0)
	draw_line(inner.position + Vector2(inner.size.x * 0.5, 0), inner.position + Vector2(inner.size.x * 0.5, inner.size.y),
			Color(0.08, 0.1, 0.13), 1.0)
	for corner in [Vector2(5, 5), Vector2(inner.size.x - 5, 5), Vector2(5, inner.size.y - 5), Vector2(inner.size.x - 5, inner.size.y - 5)]:
		draw_circle(inner.position + corner, 1.6, Color(0.3, 0.36, 0.44))


## Raised wall block with a bevelled top.
func _draw_bulkhead(c: Vector2i) -> void:
	var r := _cell_rect(c)
	draw_rect(r, Color(0.2, 0.24, 0.3))
	var top := r.grow(-5.0)
	draw_rect(top, Color(0.3, 0.35, 0.43))
	draw_line(top.position, top.position + Vector2(top.size.x, 0), Color(0.5, 0.56, 0.65), 2.0)
	draw_line(top.position, top.position + Vector2(0, top.size.y), Color(0.42, 0.48, 0.56), 2.0)
	draw_line(top.end, top.end - Vector2(top.size.x, 0), Color(0.14, 0.17, 0.21), 2.0)
	draw_line(top.end, top.end - Vector2(0, top.size.y), Color(0.14, 0.17, 0.21), 2.0)


## Door: hazard stripes around a dark slot.
func _draw_hazard(c: Vector2i) -> void:
	var r := _cell_rect(c).grow(-4.0)
	draw_rect(r, Color(0.12, 0.12, 0.1))
	var stripe := r.size.x / 6.0
	for i in 6:
		if i % 2 == 0:
			draw_rect(Rect2(r.position + Vector2(i * stripe, 0), Vector2(stripe, 6)), Color(0.85, 0.7, 0.15))
			draw_rect(Rect2(r.position + Vector2(i * stripe, r.size.y - 6), Vector2(stripe, 6)), Color(0.85, 0.7, 0.15))
	draw_rect(Rect2(r.position + Vector2(r.size.x * 0.44, 8), Vector2(r.size.x * 0.12, r.size.y - 16)), Color(0.35, 0.8, 1.0, 0.6))


func _cell_rect(c: Vector2i) -> Rect2:
	var poly := grid.cell_polygon(c, CELL_SIZE)
	var rect := Rect2(poly[0], Vector2.ZERO)
	for p in poly:
		rect = rect.expand(p)
	return rect


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
