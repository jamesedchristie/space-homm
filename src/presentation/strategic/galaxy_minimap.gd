class_name GalaxyMinimap
extends Control
## The whole sector at a glance: charted systems in their owner's colour,
## terrain you've explored, fleets you can see, and the camera's view as an
## outline. Click or drag to move the view there.

signal jump_requested(pixel: Vector2)

var engine: GalaxyEngine
var board: GalaxyBoard
var player_faction := ""
var _explored: Dictionary = {}
var _visible: Dictionary = {}
var _bounds := Rect2()
var _dragging := false
var _t := 0.0


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	clip_contents = true
	tooltip_text = "Sector map: click or drag to move the view"


func setup(p_engine: GalaxyEngine, p_board: GalaxyBoard, faction: String) -> void:
	engine = p_engine
	board = p_board
	player_faction = faction
	_bounds = Rect2()
	if engine == null:
		return
	var first := true
	for c in engine.state.grid.cells():
		var p := engine.state.grid.to_pixel(c, GridMapView.CELL_SIZE)
		if first:
			_bounds = Rect2(p, Vector2.ZERO)
			first = false
		else:
			_bounds = _bounds.expand(p)
	_bounds = _bounds.grow(GridMapView.CELL_SIZE * 0.6)
	queue_redraw()


func sync(explored: Dictionary, visible_now: Dictionary) -> void:
	_explored = explored
	_visible = visible_now
	queue_redraw()


func _process(delta: float) -> void:
	# The camera outline moves with the view.
	_t += delta
	if _t > 0.1 and visible:
		_t = 0.0
		queue_redraw()


func _scale() -> float:
	if _bounds.size.x <= 0.0 or _bounds.size.y <= 0.0:
		return 1.0
	return minf(size.x / _bounds.size.x, size.y / _bounds.size.y)


func _to_mini(pixel: Vector2) -> Vector2:
	var s := _scale()
	var offset := (size - _bounds.size * s) / 2.0
	return offset + (pixel - _bounds.position) * s


func _to_pixel(mini: Vector2) -> Vector2:
	var s := _scale()
	var offset := (size - _bounds.size * s) / 2.0
	return (mini - offset) / s + _bounds.position


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), Color(0.01, 0.015, 0.03, 0.95))
	if engine == null:
		return
	var s := engine.state
	var cell_r := maxf(1.2, GridMapView.CELL_SIZE * _scale() * 0.5)
	for c in s.grid.cells():
		var p := _to_mini(s.grid.to_pixel(c, GridMapView.CELL_SIZE))
		if not _explored.has(c):
			draw_circle(p, cell_r * 0.55, Color(0.1, 0.13, 0.22, 0.8))  # uncharted: just the sector's shape
			continue
		var terrain := s.grid.terrain_def(c)
		var col := Color(0.12, 0.17, 0.27, 0.9) if _visible.has(c) else Color(0.07, 0.1, 0.16, 0.9)
		if terrain.has("color"):
			col = Color(terrain["color"]).lightened(0.15)
			if not terrain.get("passable", true):
				col = Color(0.0, 0.0, 0.0, 1.0)
		draw_circle(p, cell_r, col)
	for p: Planet in s.planets.values():
		var at := _to_mini(s.grid.to_pixel(p.cell, GridMapView.CELL_SIZE))
		var owned := not p.owner.is_empty()
		var col := Palette.team_color(s.faction(p.owner)["team"]) if owned else Palette.NEUTRAL
		if owned:
			draw_circle(at, cell_r * 1.9, Color(col, 0.25))
		draw_circle(at, maxf(2.4, cell_r * 1.15), col if owned else Color(col, 0.8))
		if p.blockade != "":
			draw_arc(at, cell_r * 2.2, 0, TAU, 12, Palette.BAD, 1.5)
	for f: Fleet in s.fleets.values():
		if not engine.can_see_fleet(player_faction, f, _visible):
			continue
		var at := _to_mini(s.grid.to_pixel(f.cell, GridMapView.CELL_SIZE)) + Vector2(cell_r, cell_r) * 0.7
		var col := Palette.team_color(s.faction(f.owner)["team"])
		var half := maxf(1.6, cell_r * 0.7)
		draw_rect(Rect2(at - Vector2(half, half), Vector2(half, half) * 2.0), col.lightened(0.2) if f.owner == player_faction else col)
	if board != null:
		var poly := board.view_polygon()
		if poly.size() == 4:
			var pts := PackedVector2Array()
			for v in poly:
				pts.append(_to_mini(v))
			pts.append(pts[0])
			draw_polyline(pts, Color(1, 1, 1, 0.75), 1.2, true)
	draw_rect(Rect2(Vector2.ZERO, size), Color(Palette.PANEL_BORDER, 0.8), false, 1.0)


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		_dragging = event.pressed
		if event.pressed:
			jump_requested.emit(_to_pixel(event.position))
		accept_event()
	elif event is InputEventMouseMotion and _dragging:
		jump_requested.emit(_to_pixel(event.position))
		accept_event()
