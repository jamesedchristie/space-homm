class_name GalaxyBoard3D
extends GalaxyBoard
## The 2.5D galaxy map: translucent hex tiles over the nebula backdrop,
## spinning planets (Planet3D), fleets as small models of their ships
## (Fleet3D), anomaly crystals (Anomaly3D), and unexplored space as a dark
## slab. Names, bars and pips are 2D (GalaxyOverlay3D).
## Grid pixel coordinates map to the XZ plane like on the battle board:
## world = Vector3(px.x, 0, px.y) * SCALE.
##
## Camera (BoardCamera3D): mouse wheel zooms, Q/R or right-drag rotate,
## middle-drag or arrow keys pan. (E is taken by the Empire panel.)

const SCALE := 1.0 / GridMapView.CELL_SIZE
## Where planets and fleets sit inside their hex (back-left / front-right).
const PLANET_OFFSET := Vector3(-0.12, 0, -0.1)
const FLEET_OFFSET := Vector3(0.44, 0, 0.4)
const FOG_HEIGHT := 0.32
const FOG_SHADER := preload("res://src/presentation/shaders/fog_3d.gdshader")

var camera: Camera3D
var fleet_views: Dictionary = {}    # fleet id -> Fleet3D
var planet_views: Dictionary = {}   # planet id -> Planet3D
var anomaly_views: Dictionary = {}  # anomaly id -> Anomaly3D
var discovery_views: Dictionary = {}  # discovery id -> Discovery3D

var _world: Node3D
var _rig: BoardCamera3D
var _canvas: CanvasLayer
var _fx: Fx3D
var _fx2d: FxLayer
var _overlay_mesh: MeshInstance3D
var _fog_mesh: MeshInstance3D
var _fog_edge_mesh: MeshInstance3D
var _territory_mesh: MeshInstance3D
var _territory_key := ""

var _move: Array[Vector2i] = []
var _attack: Array[Vector2i] = []
var _path: Array[Vector2i] = []
var _hover: Variant = null
var _active: Variant = null
var _fog_key := ""
var _explored: Dictionary = {}
## cell -> [Node3D] terrain decorations (rocks, nebula puffs), hidden while unexplored.
var _decor: Dictionary = {}


func setup(p_engine: GalaxyEngine, p_data: DataRegistry, p_player_faction: String) -> void:
	super.setup(p_engine, p_data, p_player_faction)
	teardown()
	_world = Node3D.new()
	_world.name = "Galaxy3D"
	add_child(_world)
	BoardGeometry.build_environment(_world)
	_rig = BoardCamera3D.new()
	_rig.pitch = deg_to_rad(55.0)
	_rig.rotate_right_key = KEY_R
	_rig.max_distance = 90.0
	_world.add_child(_rig)
	camera = _rig.camera
	_build_board()
	var lo := Vector3(INF, 0, INF)
	var hi := Vector3(-INF, 0, -INF)
	for c in engine.state.grid.cells():
		var w := world(c)
		lo = Vector3(minf(lo.x, w.x), 0, minf(lo.z, w.z))
		hi = Vector3(maxf(hi.x, w.x), 0, maxf(hi.z, w.z))
	BoardGeometry.space_scenery(_world, (lo + hi) / 2.0, Vector2(hi.x - lo.x, hi.z - lo.z) / 2.0, engine.state.seed_value)
	_overlay_mesh = BoardGeometry.mesh_node(_world, BoardGeometry.overlay_material())
	var fog_mat := ShaderMaterial.new()
	fog_mat.shader = FOG_SHADER
	_fog_mesh = BoardGeometry.mesh_node(_world, fog_mat)
	_fog_edge_mesh = BoardGeometry.mesh_node(_world, BoardGeometry.overlay_material())
	for p: Planet in engine.state.planets.values():
		var pv := Planet3D.new()
		_world.add_child(pv)
		pv.setup(p, data)
		pv.position = world(p.cell) + PLANET_OFFSET
		planet_views[p.id] = pv
	_fx = Fx3D.new()
	_world.add_child(_fx)

	_canvas = CanvasLayer.new()
	_canvas.layer = 0
	add_child(_canvas)
	var overlay := GalaxyOverlay3D.new()
	overlay.board = self
	_canvas.add_child(overlay)
	_fx2d = FxLayer.new()
	_canvas.add_child(_fx2d)


func teardown() -> void:
	fleet_views.clear()
	planet_views.clear()
	anomaly_views.clear()
	discovery_views.clear()
	_fog_key = ""
	_territory_key = ""
	_explored = {}
	_decor.clear()
	if _world != null:
		_world.queue_free()
		_world = null
	if _canvas != null:
		_canvas.queue_free()
		_canvas = null
	camera = null
	_rig = null


# --- Coordinates and construction --------------------------------------------

func world(cell: Vector2i, y: float = 0.0) -> Vector3:
	var p := engine.state.grid.to_pixel(cell, GridMapView.CELL_SIZE) * SCALE
	return Vector3(p.x, y, p.y)


func _cell_poly(cell: Vector2i, inset: float = 1.0) -> PackedVector3Array:
	var center := world(cell)
	var out := PackedVector3Array()
	for p in engine.state.grid.cell_polygon(cell, GridMapView.CELL_SIZE):
		var w := Vector3(p.x * SCALE, 0, p.y * SCALE)
		out.append(center + (w - center) * inset)
	return out


func _build_board() -> void:
	var grid := engine.state.grid
	var glass := SurfaceTool.new()
	glass.begin(Mesh.PRIMITIVE_TRIANGLES)
	var polys: Array = []
	var rift := BoardGeometry.buffer()
	for c in grid.cells():
		var terrain := grid.terrain_def(c)
		if not terrain.get("passable", true):
			# A rift: a dark well with a faint violet lip.
			BoardGeometry.fill_poly(rift, _cell_poly(c, 1.0), Color(0.0, 0.0, 0.01, 0.92), -0.03)
			BoardGeometry.outline(rift, _cell_poly(c, 0.92), -0.02, 0.05, Color(0.45, 0.25, 0.7, 0.45))
			continue
		# Open space stays open: only terrain gets a tint; borders show who owns what.
		if terrain.has("color"):
			var fill := Color(terrain["color"])
			fill.a = 0.16
			BoardGeometry.prism(glass, _cell_poly(c, 0.95), -0.02, 0.0, fill.darkened(0.3), fill)
		polys.append(_cell_poly(c, 0.95))
		var decor := Node3D.new()
		if terrain.get("decoration", "") == "rocks":
			BoardGeometry.rocks(decor, world(c), hash(c), 0.6)
		elif terrain.has("color") and terrain.get("move_cost", 1) > 1:
			BoardGeometry.nebula_puffs(decor, world(c), Color(terrain["color"]).lightened(0.1), hash(c) + 7)
		if decor.get_child_count() > 0:
			_world.add_child(decor)
			_decor[c] = decor
		else:
			decor.free()
	BoardGeometry.mesh_node(_world, BoardGeometry.tile_material(true)).mesh = glass.commit()
	BoardGeometry.mesh_node(_world, BoardGeometry.line_material(0.05)).mesh = BoardGeometry.grid_lines(polys, 0.005)
	BoardGeometry.mesh_node(_world, BoardGeometry.overlay_material()).mesh = BoardGeometry.commit(rift)
	_territory_mesh = BoardGeometry.mesh_node(_world, BoardGeometry.overlay_material())


## Civ-style borders: each owned system claims its hex and the ring around it
## (nearest system wins), drawn as a faint wash with a crisp edge in the
## owner's color. Rebuilt only when ownership changes.
func _draw_territory() -> void:
	var owners := PackedStringArray()
	for p: Planet in engine.state.planets.values():
		owners.append(p.id + "=" + p.owner)
	var key := ",".join(owners)
	if key == _territory_key or _territory_mesh == null:
		return
	_territory_key = key
	var grid := engine.state.grid
	var claim: Dictionary = {}  # cell -> [owner, distance]
	for p: Planet in engine.state.planets.values():
		if p.owner.is_empty():
			continue
		for c in grid.cells():
			if not grid.terrain_def(c).get("passable", true):
				continue
			var d := grid.distance(c, p.cell)
			if d > 1:
				continue
			if not claim.has(c) or d < int(claim[c][1]):
				claim[c] = [p.owner, d]
	var buf := BoardGeometry.buffer()
	for c: Vector2i in claim:
		var owner: String = claim[c][0]
		var color := Palette.team_color(engine.state.faction(owner)["team"])
		BoardGeometry.fill_poly(buf, _cell_poly(c, 1.0), Color(color, 0.07), 0.004)
		var poly := _cell_poly(c, 1.0)
		for i in poly.size():
			var a := poly[i]
			var b := poly[(i + 1) % poly.size()]
			var outside := world(c) + ((a + b) / 2.0 - world(c)) * 1.6
			var n := grid.from_pixel(Vector2(outside.x, outside.z) / SCALE, GridMapView.CELL_SIZE)
			if claim.has(n) and claim[n][0] == owner:
				continue
			# Pull the edge slightly inside so two neighbors' borders sit side by side.
			var ia := a + (world(c) - a) * 0.04
			var ib := b + (world(c) - b) * 0.04
			BoardGeometry.ribbon(buf, Vector3(ia.x, 0.008, ia.z), Vector3(ib.x, 0.008, ib.z), 0.035, Color(color.lightened(0.15), 0.75))
	_territory_mesh.mesh = BoardGeometry.commit(buf)


# --- Sync ---------------------------------------------------------------------

func sync(visible_now: Dictionary, explored: Dictionary, selected_fleet: String) -> void:
	_set_fog(explored, visible_now)
	_draw_territory()
	for id: String in fleet_views.keys():
		if not engine.state.fleets.has(id):
			fleet_views[id].queue_free()
			fleet_views.erase(id)
	for fleet: Fleet in engine.state.fleets.values():
		var view: Fleet3D = fleet_views.get(fleet.id)
		if view == null:
			view = Fleet3D.new()
			_world.add_child(view)
			var faction := engine.state.faction(fleet.owner)
			view.setup(fleet, faction["team"], data, fleet.owner == player_faction, faction.get("species", ""))
			fleet_views[fleet.id] = view
		view.refresh(fleet, data, engine.fleet_speed(fleet))
		view.position = world(fleet.cell) + FLEET_OFFSET
		view.visible = engine.can_see_fleet(player_faction, fleet, visible_now)
		view.set_selected(fleet.id == selected_fleet)
	for p: Planet in engine.state.planets.values():
		planet_views[p.id].refresh(p, engine.state)
		# Planets are charted: unexplored ones rest on top of the fog.
		planet_views[p.id].position.y = 0.0 if explored.has(p.cell) else FOG_HEIGHT
	for id: String in anomaly_views.keys():
		if not engine.state.anomalies.has(id):
			anomaly_views[id].queue_free()
			anomaly_views.erase(id)
	for a: Dictionary in engine.state.anomalies.values():
		var av: Anomaly3D = anomaly_views.get(a["id"])
		if av == null:
			av = Anomaly3D.new()
			_world.add_child(av)
			anomaly_views[a["id"]] = av
		av.setup(a)
		av.position = world(a["cell"]) + PLANET_OFFSET
		av.visible = explored.has(a["cell"])
	for id: String in discovery_views.keys():
		if not engine.state.discoveries.has(id):
			discovery_views[id].queue_free()
			discovery_views.erase(id)
	for d: Dictionary in engine.state.discoveries.values():
		var dv: Discovery3D = discovery_views.get(d["id"])
		if dv == null:
			dv = Discovery3D.new()
			_world.add_child(dv)
			dv.setup(d, data)
			discovery_views[d["id"]] = dv
		dv.position = world(d["cell"])
		dv.visible = explored.has(d["cell"])


## Unexplored space is a dark slab with a soft rim; explored cells out of
## sensor range are dimmed.
func _set_fog(explored: Dictionary, visible_now: Dictionary) -> void:
	var key := "%d:%d:%d" % [explored.size(), visible_now.size(), hash(visible_now.keys())]
	if key == _fog_key:
		return
	_fog_key = key
	_explored = explored
	for c: Vector2i in _decor:
		_decor[c].visible = explored.has(c)
	var grid := engine.state.grid
	var solid := BoardGeometry.buffer()
	var edges := BoardGeometry.buffer()
	var top := Color.WHITE
	var side := Color(0.55, 0.6, 0.75)
	for c in grid.cells():
		var poly := _cell_poly(c, 1.0)
		if not explored.has(c):
			BoardGeometry.fill_poly(solid, poly, top, FOG_HEIGHT)
			# Faint hex outlines: "charted grid, unknown contents" rather than open space.
			BoardGeometry.outline(edges, _cell_poly(c, 0.96), FOG_HEIGHT + 0.003, 0.025, Color(0.32, 0.45, 0.8, 0.07))
			for i in poly.size():
				var a := poly[i]
				var b := poly[(i + 1) % poly.size()]
				var outside := world(c) + ((a + b) / 2.0 - world(c)) * 1.6
				var n := grid.from_pixel(Vector2(outside.x, outside.z) / SCALE, GridMapView.CELL_SIZE)
				if grid.has_cell(n) and not explored.has(n):
					continue
				_wall(solid, a, b, -0.05, FOG_HEIGHT, side)
				BoardGeometry.ribbon(edges, Vector3(a.x, FOG_HEIGHT + 0.004, a.z), Vector3(b.x, FOG_HEIGHT + 0.004, b.z),
						0.05, Color(0.35, 0.5, 0.85, 0.2))
		elif not visible_now.has(c):
			BoardGeometry.fill_poly(edges, _cell_poly(c, 0.95), Color(0.0, 0.0, 0.03, 0.45), 0.012)
	_fog_mesh.mesh = BoardGeometry.commit(solid)
	_fog_edge_mesh.mesh = BoardGeometry.commit(edges)


func _wall(buf: Dictionary, a: Vector3, b: Vector3, y0: float, y1: float, color: Color) -> void:
	for v in [Vector3(a.x, y0, a.z), Vector3(b.x, y0, b.z), Vector3(b.x, y1, b.z),
			Vector3(a.x, y0, a.z), Vector3(b.x, y1, b.z), Vector3(a.x, y1, a.z)]:
		buf["c"].append(color)
		buf["v"].append(v)


# --- Fleets, planets, effects ------------------------------------------------

func is_fleet_shown(fleet_id: String) -> bool:
	return fleet_views.has(fleet_id) and fleet_views[fleet_id].visible


func move_fleet(fleet_id: String, path: Array) -> void:
	var view: Fleet3D = fleet_views.get(fleet_id)
	if view == null:
		return
	view.visible = true
	var points: Array[Vector3] = []
	for i in range(1, path.size()):
		points.append(world(path[i]) + FLEET_OFFSET)
	await view.move_along(points)


func destroy_fleet(fleet_id: String) -> void:
	var view: Fleet3D = fleet_views.get(fleet_id)
	if view == null or not view.visible:
		return
	_fx.explode(view.aim_point(), 0.8)
	_fx2d.play_sound("explosion")
	_rig.shake(0.25)
	await view.play_destroyed()


func refresh_planet(planet_id: String) -> void:
	planet_views[planet_id].refresh(engine.state.planets[planet_id], engine.state)


func float_text_at_fleet(fleet_id: String, text: String, color: Color) -> void:
	if fleet_views.has(fleet_id):
		var view: Fleet3D = fleet_views[fleet_id]
		_float_text(view.global_position + Vector3(0, view.label_height, 0), text, color)


func float_text_at_planet(planet_id: String, text: String, color: Color) -> void:
	var view: Planet3D = planet_views[planet_id]
	_float_text(view.global_position + Vector3(0, view.label_height, 0), text, color)


func _float_text(at: Vector3, text: String, color: Color) -> void:
	if camera != null and not camera.is_position_behind(at):
		_fx2d.float_text(camera.unproject_position(at) + Vector2(0, -12), text, color)


func pulse(cell: Vector2i, color: Color) -> void:
	_fx.play("self", world(cell, 0.4), world(cell, 0.4), color, 0.0)


# --- Highlights ---------------------------------------------------------------

func set_highlights(move: Array[Vector2i], attack: Array[Vector2i], path: Array[Vector2i]) -> void:
	_move = move
	_attack = attack
	_path = path
	_redraw_overlays()


func set_hover(cell: Variant) -> void:
	_hover = cell
	_redraw_overlays()


func set_active_cell(cell: Variant) -> void:
	_active = cell
	_redraw_overlays()


func set_selected_fleet(fleet_id: String) -> void:
	for id: String in fleet_views:
		fleet_views[id].set_selected(id == fleet_id)


func _redraw_overlays() -> void:
	if _overlay_mesh == null:
		return
	var buf := BoardGeometry.buffer()
	var y := 0.02
	# Movement range: a light wash with a crisp outline around its edge.
	var in_range: Dictionary = {}
	for c in _move:
		in_range[c] = true
	if _active != null:
		in_range[_active] = true
	for c in _move:
		BoardGeometry.fill_poly(buf, _cell_poly(c, 1.0), Color(Palette.REACHABLE, 0.06), y)
	for c: Vector2i in in_range:
		var poly := _cell_poly(c, 1.0)
		for i in poly.size():
			var a := poly[i]
			var b := poly[(i + 1) % poly.size()]
			var outside := world(c) + ((a + b) / 2.0 - world(c)) * 1.6
			var n := engine.state.grid.from_pixel(Vector2(outside.x, outside.z) / SCALE, GridMapView.CELL_SIZE)
			if not in_range.has(n):
				BoardGeometry.ribbon(buf, Vector3(a.x, y + 0.003, a.z), Vector3(b.x, y + 0.003, b.z), 0.03, Color(Palette.REACHABLE, 0.55))
	for c in _attack:
		BoardGeometry.fill_poly(buf, _cell_poly(c, 0.9), Color(Palette.TARGET, 0.32), y + 0.002)
	for i in range(1, _path.size()):
		BoardGeometry.ribbon(buf, world(_path[i - 1], y + 0.01), world(_path[i], y + 0.01), 0.07, Palette.PATH)
	if not _path.is_empty():
		BoardGeometry.fill_poly(buf, BoardGeometry.disc(world(_path[_path.size() - 1], y + 0.012), 0.14), Palette.PATH)
	if _active != null:
		BoardGeometry.outline(buf, _cell_poly(_active, 0.95), y + 0.015, 0.07, Palette.ACTIVE)
	if _hover != null:
		BoardGeometry.outline(buf, _cell_poly(_hover, 0.95), y + 0.016, 0.05, Palette.HOVER)
	_overlay_mesh.mesh = BoardGeometry.commit(buf)


# --- Camera and input ---------------------------------------------------------

## Glides the camera to `cell` when it's off screen or near the edge of the map area.
func focus_cell(cell: Vector2i) -> void:
	if _rig == null or not _rig.camera.is_inside_tree():
		return
	var at := world(cell)
	var area := _rig.get_area()
	if not _rig.camera.is_position_behind(at) and area.size != Vector2.ZERO:
		var inner := area.grow_individual(-area.size.x * 0.15, -area.size.y * 0.15, -area.size.x * 0.15, -area.size.y * 0.15)
		if inner.has_point(_rig.camera.unproject_position(at)):
			return
	var tw := _rig.create_tween()
	tw.tween_method(func(p: Vector3) -> void:
		_rig.pivot = p
		_rig.update(), _rig.pivot, Vector3(at.x, 0.0, at.z), 0.35).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)

func cell_at_mouse() -> Variant:
	if _rig == null:
		return null
	var hit: Variant = _rig.pick(0.0)
	if hit == null:
		return null
	var cell := engine.state.grid.from_pixel(Vector2(hit.x, hit.z) / SCALE, GridMapView.CELL_SIZE)
	return cell if engine.state.grid.has_cell(cell) else null


## Frames what the player has explored (plus a margin) rather than the whole
## map, so the game opens close to home; zoom out to see everything.
func fit(area: Rect2) -> void:
	if _rig == null:
		return
	var lo := Vector3(INF, 0, INF)
	var hi := Vector3(-INF, 0, -INF)
	var all_lo := Vector3(INF, 0, INF)
	var all_hi := Vector3(-INF, 0, -INF)
	for c in engine.state.grid.cells():
		var w := world(c)
		all_lo = Vector3(minf(all_lo.x, w.x), 0, minf(all_lo.z, w.z))
		all_hi = Vector3(maxf(all_hi.x, w.x), 0, maxf(all_hi.z, w.z))
		if _explored.has(c):
			lo = Vector3(minf(lo.x, w.x), 0, minf(lo.z, w.z))
			hi = Vector3(maxf(hi.x, w.x), 0, maxf(hi.z, w.z))
	if lo.x == INF:
		lo = all_lo
		hi = all_hi
	# At least ~9 x 6 hexes, but never more than the map.
	var min_size := Vector3(15.0, 0, 9.0)
	var center := (lo + hi) / 2.0
	var half := Vector3(maxf(hi.x - lo.x + 2.0, min_size.x), 0, maxf(hi.z - lo.z + 2.0, min_size.z)) / 2.0
	half = Vector3(minf(half.x, (all_hi.x - all_lo.x) / 2.0), 0, minf(half.z, (all_hi.z - all_lo.z) / 2.0))
	_rig.fit(center - half, center + half, area, Vector2(2.0, 1.5))
	_rig.distance *= 0.9
	_rig.update()


func handle_input(event: InputEvent) -> bool:
	return _rig != null and _rig.handle_input(event)
