class_name BattleBoard3D
extends BattleBoard
## The 2.5D battlefield: a lit 3D board seen through a tilted camera.
## - Grid cells are built as meshes on the ground plane (translucent tiles in
##   space, metal plating and raised bulkheads in station interiors).
## - Units are procedural models (Unit3D); effects are 3D (Fx3D).
## - Bars, names, floating numbers and marker labels are 2D, drawn on top.
## - The nebula backdrop (CanvasLayer -1) shows behind the 3D scene.
## Grid pixel coordinates (TacticalGrid.to_pixel) map to the XZ plane:
## world = Vector3(px.x, 0, px.y) * SCALE, so one hex is ~1 unit across its radius.
##
## Camera (BoardCamera3D): mouse wheel zooms, Q/E or right-drag rotate,
## middle-drag or arrow keys pan.

const SCALE := 1.0 / GridMapView.CELL_SIZE
const DECK_HEIGHT := 0.06
const WALL_HEIGHT := 0.95

var camera: Camera3D
var views: Dictionary = {}  # unit id -> Unit3D
## [{"pos": Vector3, "label": String, "color": Color}] drawn by the overlay.
var marker_labels: Array[Dictionary] = []

var _world: Node3D
var _rig: BoardCamera3D
var _canvas: CanvasLayer
var _fx: Fx3D
var _fx2d: FxLayer
var _overlay_mesh: MeshInstance3D
var _fog_mesh: MeshInstance3D
var _marker_root: Node3D
var _floor := ""
var _floor_y := 0.0
var _explored: Dictionary = {}

var _reach: Array[Vector2i] = []
var _targets: Array[Vector2i] = []
var _area: Array[Vector2i] = []
var _path: Array[Vector2i] = []
var _hover: Variant = null
var _active: Variant = null


func setup(p_engine: BattleEngine, p_data: DataRegistry, floor_style: String) -> void:
	super.setup(p_engine, p_data, floor_style)
	teardown()
	_floor = floor_style
	_floor_y = DECK_HEIGHT if _floor == "deck" else 0.0

	_world = Node3D.new()
	_world.name = "Board3D"
	add_child(_world)
	_build_environment()
	_build_board()
	var lo := Vector3(INF, 0, INF)
	var hi := Vector3(-INF, 0, -INF)
	for c in engine.state.grid.cells():
		var w := world(c)
		lo = Vector3(minf(lo.x, w.x), 0, minf(lo.z, w.z))
		hi = Vector3(maxf(hi.x, w.x), 0, maxf(hi.z, w.z))
	BoardGeometry.space_scenery(_world, (lo + hi) / 2.0, Vector2(hi.x - lo.x, hi.z - lo.z) / 2.0,
			engine.state.seed_value, _floor == "deck")
	_overlay_mesh = BoardGeometry.mesh_node(_world, BoardGeometry.overlay_material())
	_fog_mesh = BoardGeometry.mesh_node(_world, BoardGeometry.overlay_material())
	_marker_root = Node3D.new()
	_world.add_child(_marker_root)
	_fx = Fx3D.new()
	_world.add_child(_fx)

	_canvas = CanvasLayer.new()
	_canvas.layer = 0
	add_child(_canvas)
	var overlay := BoardOverlay3D.new()
	overlay.board = self
	_canvas.add_child(overlay)
	_fx2d = FxLayer.new()
	_canvas.add_child(_fx2d)
	_redraw_overlays()


func teardown() -> void:
	views.clear()
	_props.clear()
	marker_labels.clear()
	if _world != null:
		_world.queue_free()
		_world = null
	if _canvas != null:
		_canvas.queue_free()
		_canvas = null
	camera = null
	_rig = null


# --- Coordinates --------------------------------------------------------------

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


func _unit_ground(u: BattleUnit) -> Vector3:
	return world(u.cell, _floor_y)


# --- Scene construction -------------------------------------------------------

func _build_environment() -> void:
	BoardGeometry.build_environment(_world)
	_rig = BoardCamera3D.new()
	_world.add_child(_rig)
	camera = _rig.camera


func _build_board() -> void:
	var grid := engine.state.grid
	var solid := SurfaceTool.new()
	solid.begin(Mesh.PRIMITIVE_TRIANGLES)
	var glass := SurfaceTool.new()
	glass.begin(Mesh.PRIMITIVE_TRIANGLES)
	var polys: Array = []
	if _floor == "deck":
		DeckKit.build(self, _world)
	for c in grid.cells():
		var terrain := grid.terrain_def(c)
		var deco: String = terrain.get("decoration", "")
		if _floor == "deck":
			pass  # dressed by DeckKit
		else:
			var fill := Color(0.05, 0.08, 0.15, 0.1)
			if terrain.has("color"):
				fill = Color(terrain["color"])
				fill.a = 0.32
			BoardGeometry.prism(glass, _cell_poly(c, 0.95), -0.02, 0.0, fill.darkened(0.3), fill)
			if deco == "rocks":
				BoardGeometry.rocks(_world, world(c), hash(c))
			if terrain.get("blocks_sight", false) and terrain.get("passable", true):
				BoardGeometry.nebula_puffs(_world, world(c), Color(terrain.get("color", "#553377")), hash(c) + 7)
		polys.append(_cell_poly(c, 0.95))

	BoardGeometry.mesh_node(_world, BoardGeometry.tile_material(false)).mesh = solid.commit()
	BoardGeometry.mesh_node(_world, BoardGeometry.tile_material(true)).mesh = glass.commit()
	BoardGeometry.mesh_node(_world, BoardGeometry.line_material()).mesh = BoardGeometry.grid_lines(polys, _floor_y + 0.005)


func _door(st: SurfaceTool, c: Vector2i) -> void:
	var center := world(c, DECK_HEIGHT)
	for side in [-1.0, 1.0]:
		BoardGeometry.box(st, center + Vector3(side * 0.62, 0.08, 0), Vector3(0.18, 0.16, 1.5), Color(0.85, 0.68, 0.14))
		BoardGeometry.box(st, center + Vector3(0, 0.08, side * 0.62), Vector3(1.5, 0.16, 0.18), Color(0.85, 0.68, 0.14))


func _crates(st: SurfaceTool, c: Vector2i) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(c)
	var center := world(c, DECK_HEIGHT)
	for i in 3:
		var size := Vector3(rng.randf_range(0.45, 0.6), rng.randf_range(0.3, 0.5), rng.randf_range(0.45, 0.6))
		var offset := Vector3(rng.randf_range(-0.35, 0.35), size.y / 2.0, rng.randf_range(-0.35, 0.35))
		BoardGeometry.box(st, center + offset, size, Color(0.36, 0.42, 0.28))


# --- Units --------------------------------------------------------------------

func add_unit(u: BattleUnit) -> void:
	var view := Unit3D.new()
	_world.add_child(view)
	view.setup(u, data, Palette.team_color(u.team), engine.state.team_info(u.team).get("species", ""))
	view.position = _unit_ground(u)
	view.face_angle(0.0 if u.team == 0 else PI)
	views[u.id] = view


func move_unit(unit_id: String, path: Array, animate: bool) -> void:
	var view: Unit3D = views[unit_id]
	var points: Array[Vector3] = []
	for i in range(1, path.size()):
		points.append(world(path[i], _floor_y))
	if animate:
		view.visible = true
		await view.move_along(points)
	elif not points.is_empty():
		view.position = points[points.size() - 1]


func face_unit(unit_id: String, cell: Vector2i) -> void:
	var view: Unit3D = views[unit_id]
	var d := world(cell) - Vector3(view.position.x, 0, view.position.z)
	if d.length() > 0.01:
		view.face_angle(atan2(d.z, d.x))


func refresh_unit(u: BattleUnit, is_visible: bool) -> void:
	if not views.has(u.id):
		return  # e.g. reinforcements whose spawn event hasn't been played yet
	views[u.id].refresh(u)
	views[u.id].visible = is_visible


func set_unit_values(unit_id: String, hull: int, shields: int) -> void:
	views[unit_id].hull = hull
	views[unit_id].shields = shields


func set_unit_visible(unit_id: String, is_visible: bool) -> void:
	views[unit_id].visible = is_visible


func set_active_unit(unit_id: String) -> void:
	for id: String in views:
		views[id].set_active(id == unit_id)


func unit_hit(unit_id: String, source_id: String, shield_hit: bool) -> void:
	var view: Unit3D = views[unit_id]
	view.play_hit()
	if shield_hit and views.has(source_id):
		view.play_shield_hit(views[source_id].global_position)


func destroy_unit(unit_id: String, big: bool) -> void:
	var view: Unit3D = views[unit_id]
	_fx.explode(view.aim_point(), 1.4 if big else 0.8)
	_fx2d.play_sound("explosion")
	if big:
		shake(0.35)
	await view.play_destroyed()


func float_text(unit_id: String, text: String, color: Color, rise: float = 0.0) -> void:
	var view: Unit3D = views[unit_id]
	if camera == null:
		return
	var p := camera.unproject_position(view.global_position + Vector3(0, view.label_height, 0))
	_fx2d.float_text(p + Vector2(0, 10 - rise), text, color)


func play_ability(kind: String, source_id: String, target: Vector2i, color: Color, radius: int, _laser: String) -> void:
	var source: Unit3D = views[source_id]
	if kind != "self":
		face_unit(source_id, target)
	var target_unit := engine.state.unit_at(target)
	var to: Vector3 = views[target_unit.id].aim_point() if target_unit != null and views.has(target_unit.id) \
			else world(target, _floor_y + 0.3)
	_fx2d.play_sound(kind)
	var blast := float(radius) * engine.state.grid.to_pixel(Vector2i(1, 0), GridMapView.CELL_SIZE).length() * SCALE
	await _fx.play(kind, source.aim_point(), to, color, blast)


func play_sound(key: String) -> void:
	_fx2d.play_sound(key)


func shake(strength: float) -> void:
	_rig.shake(strength)


# --- Highlights, fog, markers -------------------------------------------------

func set_highlights(reach: Array[Vector2i], targets: Array[Vector2i], area: Array[Vector2i], path: Array[Vector2i]) -> void:
	_reach = reach
	_targets = targets
	_area = area
	_path = path
	_redraw_overlays()


func set_hover(cell: Variant) -> void:
	_hover = cell
	_redraw_overlays()


func set_active_cell(cell: Variant) -> void:
	_active = cell
	_redraw_overlays()


func _redraw_overlays() -> void:
	if _overlay_mesh == null:
		return
	var im := {"v": [], "c": []}  # geometry buffer, committed below
	var y := _floor_y + 0.02
	for c in _reach:
		BoardGeometry.fill_poly(im, _cell_poly(c, 1.0), Color(Palette.REACHABLE, 0.15), y)
	for c in _targets:
		_fill_cell(im, c, y + 0.002, Color(Palette.TARGET, 0.32))
	for c in _area:
		_fill_cell(im, c, y + 0.004, Color(Palette.AREA, 0.5))
	for i in range(1, _path.size()):
		BoardGeometry.ribbon(im, world(_path[i - 1], y + 0.01), world(_path[i], y + 0.01), 0.07, Palette.PATH)
	if not _path.is_empty():
		BoardGeometry.fill_poly(im, BoardGeometry.disc(world(_path[_path.size() - 1], y + 0.012), 0.16), Palette.PATH)
	if _active != null:
		_outline_cell(im, _active, y + 0.015, 0.07, Palette.ACTIVE)
	if _hover != null:
		_outline_cell(im, _hover, y + 0.016, 0.05, Palette.HOVER)
	_overlay_mesh.mesh = BoardGeometry.commit(im)


## Props standing on a cell (hidden while it's unexplored, so fog doesn't leak them).
var _props: Dictionary = {}


func register_prop(cell: Vector2i, node: Node3D) -> void:
	_props.get_or_add(cell, []).append(node)


func set_fog(explored: Dictionary, visible_now: Dictionary) -> void:
	_explored = explored
	for c: Vector2i in _props:
		for n: Node3D in _props[c]:
			n.visible = not engine.state.fog_enabled or explored.has(c)
	var im := {"v": [], "c": []}
	for c in engine.state.grid.cells():
		if not explored.has(c):
			BoardGeometry.fill_poly(im, _cell_poly(c, 1.0), Color(0.0, 0.005, 0.015, 0.97), WALL_HEIGHT + 0.3)
		elif not visible_now.has(c):
			BoardGeometry.fill_poly(im, _cell_poly(c, 1.0), Color(0.0, 0.0, 0.03, 0.5), _floor_y + 0.012)
	_fog_mesh.mesh = BoardGeometry.commit(im)


func set_markers(markers: Dictionary) -> void:
	for child in _marker_root.get_children():
		child.queue_free()
	marker_labels.clear()
	for c: Vector2i in markers:
		var m: Dictionary = markers[c]
		if engine.state.fog_enabled and not _explored.has(c) and not m.get("always", false):
			continue
		var beam := MeshInstance3D.new()
		var cyl := CylinderMesh.new()
		cyl.top_radius = 0.35
		cyl.bottom_radius = 0.5
		cyl.height = 1.6
		cyl.radial_segments = 16
		cyl.cap_top = false
		cyl.cap_bottom = false
		beam.mesh = cyl
		var mat := StandardMaterial3D.new()
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
		mat.albedo_color = m["color"] * 0.35
		mat.cull_mode = BaseMaterial3D.CULL_DISABLED
		beam.material_override = mat
		beam.position = world(c, _floor_y + 0.8)
		_marker_root.add_child(beam)
		marker_labels.append({"pos": world(c, _floor_y + 1.7), "label": m.get("label", ""), "color": m["color"]})


func _fill_cell(im: Dictionary, c: Vector2i, y: float, color: Color) -> void:
	BoardGeometry.fill_poly(im, _cell_poly(c, 0.9), color, y)


func _outline_cell(im: Dictionary, c: Vector2i, y: float, width: float, color: Color) -> void:
	var poly := _cell_poly(c, 0.95)
	for i in poly.size():
		BoardGeometry.ribbon(im, Vector3(poly[i].x, y, poly[i].z), Vector3(poly[(i + 1) % poly.size()].x, y, poly[(i + 1) % poly.size()].z), width, color)


# --- Camera and input ---------------------------------------------------------

func cell_at_mouse() -> Variant:
	if _rig == null:
		return null
	var hit: Variant = _rig.pick(_floor_y)
	if hit == null:
		return null
	var cell := engine.state.grid.from_pixel(Vector2(hit.x, hit.z) / SCALE, GridMapView.CELL_SIZE)
	return cell if engine.state.grid.has_cell(cell) else null


func fit(area: Rect2) -> void:
	var lo := Vector3(INF, 0, INF)
	var hi := Vector3(-INF, 0, -INF)
	for c in engine.state.grid.cells():
		var w := world(c)
		lo = Vector3(minf(lo.x, w.x), 0, minf(lo.z, w.z))
		hi = Vector3(maxf(hi.x, w.x), 0, maxf(hi.z, w.z))
	_rig.fit(lo, hi, area)
	# Big maps (missions especially) would be framed from far away: zoom in on
	# the player's units instead; the wheel zooms out to see everything.
	var limit := 17.0 if _floor == "deck" else 45.0
	if _rig.distance > limit:
		var own := engine.state.living_units(0)
		if not own.is_empty():
			var sum := Vector3.ZERO
			for u in own:
				sum += world(u.cell)
			_rig.pivot = sum / own.size()
		_rig.distance = limit
		_rig.update()


func handle_input(event: InputEvent) -> bool:
	return _rig != null and _rig.handle_input(event)
