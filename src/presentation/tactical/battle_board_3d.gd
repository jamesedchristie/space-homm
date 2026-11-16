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
## Camera: mouse wheel zooms, Q/E rotate, middle-drag or arrow keys pan.

const SCALE := 1.0 / GridMapView.CELL_SIZE
const PITCH := deg_to_rad(52.0)
const DECK_HEIGHT := 0.06
const WALL_HEIGHT := 0.95

var camera: Camera3D
var views: Dictionary = {}  # unit id -> Unit3D
## [{"pos": Vector3, "label": String, "color": Color}] drawn by the overlay.
var marker_labels: Array[Dictionary] = []

var _world: Node3D
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

var _pivot := Vector3.ZERO
var _yaw := 0.0
var _distance := 14.0
var _base_offset := Vector2.ZERO
var _panning := false
var _last_area := Rect2()


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
	_overlay_mesh = _mesh_node(_overlay_material())
	_fog_mesh = _mesh_node(_overlay_material())
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
	marker_labels.clear()
	if _world != null:
		_world.queue_free()
		_world = null
	if _canvas != null:
		_canvas.queue_free()
		_canvas = null
	camera = null


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
	var env_node := WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_CANVAS
	env.background_canvas_max_layer = -1
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.32, 0.38, 0.55)
	env.ambient_light_energy = 0.75
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.glow_enabled = true
	env.glow_intensity = 0.9
	env.glow_bloom = 0.15
	env_node.environment = env
	_world.add_child(env_node)

	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-55, -35, 0)
	sun.light_energy = 1.25
	sun.light_color = Color(1.0, 0.96, 0.9)
	sun.shadow_enabled = true
	_world.add_child(sun)
	var rim := DirectionalLight3D.new()
	rim.rotation_degrees = Vector3(-25, 150, 0)
	rim.light_energy = 0.35
	rim.light_color = Color(0.5, 0.7, 1.0)
	_world.add_child(rim)

	camera = Camera3D.new()
	camera.fov = 40.0
	camera.near = 0.1
	camera.far = 200.0
	_world.add_child(camera)


func _build_board() -> void:
	var grid := engine.state.grid
	var solid := SurfaceTool.new()
	solid.begin(Mesh.PRIMITIVE_TRIANGLES)
	var glass := SurfaceTool.new()
	glass.begin(Mesh.PRIMITIVE_TRIANGLES)
	var lines := PackedVector3Array()
	for c in grid.cells():
		var terrain := grid.terrain_def(c)
		var deco: String = terrain.get("decoration", "")
		if _floor == "deck":
			match deco:
				"bulkhead":
					_prism(solid, _cell_poly(c, 1.0), 0.0, WALL_HEIGHT, Color(0.17, 0.19, 0.24), Color(0.25, 0.28, 0.34))
				"hazard":
					_prism(solid, _cell_poly(c, 0.97), 0.0, DECK_HEIGHT, Color(0.14, 0.15, 0.17), Color(0.2, 0.2, 0.18))
					_door(solid, c)
				_:
					_prism(solid, _cell_poly(c, 0.97), 0.0, DECK_HEIGHT, Color(0.12, 0.15, 0.19), Color(0.17, 0.21, 0.26))
					if deco == "crates":
						_crates(solid, c)
		else:
			var fill := Color(0.06, 0.11, 0.2, 0.42)
			if terrain.has("color"):
				fill = Color(terrain["color"])
				fill.a = 0.55
			_prism(glass, _cell_poly(c, 0.95), -0.04, 0.04, fill.darkened(0.3), fill)
			if deco == "rocks":
				_rocks(c)
			if terrain.get("blocks_sight", false) and terrain.get("passable", true):
				_nebula_puffs(c, Color(terrain.get("color", "#553377")))
		var poly := _cell_poly(c, 0.95)
		for i in poly.size():
			lines.append(poly[i] + Vector3(0, _floor_y + 0.005, 0))
			lines.append(poly[(i + 1) % poly.size()] + Vector3(0, _floor_y + 0.005, 0))

	var solid_mat := StandardMaterial3D.new()
	solid_mat.vertex_color_use_as_albedo = true
	solid_mat.roughness = 0.6
	solid_mat.metallic = 0.35
	_mesh_node(solid_mat).mesh = solid.commit()
	var glass_mat := StandardMaterial3D.new()
	glass_mat.vertex_color_use_as_albedo = true
	glass_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	glass_mat.roughness = 0.25
	glass_mat.metallic = 0.5
	_mesh_node(glass_mat).mesh = glass.commit()

	var im := ImmediateMesh.new()
	im.surface_begin(Mesh.PRIMITIVE_LINES)
	for v in lines:
		im.surface_add_vertex(v)
	im.surface_end()
	var line_mat := StandardMaterial3D.new()
	line_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	line_mat.albedo_color = Color(0.45, 0.7, 0.95, 0.35)
	line_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_mesh_node(line_mat).mesh = im


## Extruded cell polygon with explicit normals and vertex colors.
func _prism(st: SurfaceTool, poly: PackedVector3Array, y0: float, y1: float, side: Color, top: Color) -> void:
	var center := Vector3.ZERO
	for p in poly:
		center += p
	center /= poly.size()
	for i in range(1, poly.size() - 1):
		for v in [poly[0], poly[i], poly[i + 1]]:
			st.set_normal(Vector3.UP)
			st.set_color(top)
			st.add_vertex(v + Vector3(0, y1, 0))
	for i in poly.size():
		var a := poly[i]
		var b := poly[(i + 1) % poly.size()]
		var n := ((a + b) / 2.0 - center).normalized()
		for v in [a + Vector3(0, y0, 0), b + Vector3(0, y0, 0), b + Vector3(0, y1, 0),
				a + Vector3(0, y0, 0), b + Vector3(0, y1, 0), a + Vector3(0, y1, 0)]:
			st.set_normal(n)
			st.set_color(side)
			st.add_vertex(v)


func _box(st: SurfaceTool, center: Vector3, size: Vector3, color: Color) -> void:
	var h := size / 2.0
	var poly := PackedVector3Array([center + Vector3(-h.x, 0, -h.z), center + Vector3(h.x, 0, -h.z),
			center + Vector3(h.x, 0, h.z), center + Vector3(-h.x, 0, h.z)])
	_prism(st, poly, -h.y + 0.0, h.y, color.darkened(0.25), color)


func _door(st: SurfaceTool, c: Vector2i) -> void:
	var center := world(c, DECK_HEIGHT)
	for side in [-1.0, 1.0]:
		_box(st, center + Vector3(side * 0.62, 0.08, 0), Vector3(0.18, 0.16, 1.5), Color(0.85, 0.68, 0.14))
		_box(st, center + Vector3(0, 0.08, side * 0.62), Vector3(1.5, 0.16, 0.18), Color(0.85, 0.68, 0.14))


func _crates(st: SurfaceTool, c: Vector2i) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(c)
	var center := world(c, DECK_HEIGHT)
	for i in 3:
		var size := Vector3(rng.randf_range(0.45, 0.6), rng.randf_range(0.3, 0.5), rng.randf_range(0.45, 0.6))
		var offset := Vector3(rng.randf_range(-0.35, 0.35), size.y / 2.0, rng.randf_range(-0.35, 0.35))
		_box(st, center + offset, size, Color(0.36, 0.42, 0.28))


func _rocks(c: Vector2i) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(c)
	for i in 2:
		var rock := ModelFactory.build_rock(rng.randi(), rng.randf_range(0.42, 0.62) if i == 0 else rng.randf_range(0.2, 0.3))
		rock.position = world(c) + Vector3(rng.randf_range(-0.3, 0.3), rng.randf_range(0.15, 0.4), rng.randf_range(-0.3, 0.3))
		rock.rotation = Vector3(rng.randf() * TAU, rng.randf() * TAU, rng.randf() * TAU)
		_world.add_child(rock)


func _nebula_puffs(c: Vector2i, color: Color) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(c) + 7
	for i in 4:
		var puff := MeshInstance3D.new()
		var sphere := SphereMesh.new()
		sphere.radius = rng.randf_range(0.35, 0.6)
		sphere.height = sphere.radius * 0.8
		puff.mesh = sphere
		var m := StandardMaterial3D.new()
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
		m.albedo_color = color.lightened(0.3) * 0.12
		m.cull_mode = BaseMaterial3D.CULL_DISABLED
		puff.material_override = m
		puff.position = world(c) + Vector3(rng.randf_range(-0.5, 0.5), rng.randf_range(0.1, 0.6), rng.randf_range(-0.5, 0.5))
		_world.add_child(puff)


func _mesh_node(material: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.material_override = material
	_world.add_child(mi)
	return mi


func _overlay_material() -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.vertex_color_use_as_albedo = true
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	return m


# --- Units --------------------------------------------------------------------

func add_unit(u: BattleUnit) -> void:
	var view := Unit3D.new()
	_world.add_child(view)
	view.setup(u, data, Palette.team_color(u.team))
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
	var tw := create_tween()
	for i in 6:
		var offset := Vector2(randf_range(-1, 1), randf_range(-1, 1)) * strength * (1.0 - i / 6.0)
		tw.tween_property(camera, "h_offset", _base_offset.x + offset.x, 0.035)
		tw.parallel().tween_property(camera, "v_offset", _base_offset.y + offset.y, 0.035)
	tw.tween_property(camera, "h_offset", _base_offset.x, 0.04)
	tw.parallel().tween_property(camera, "v_offset", _base_offset.y, 0.04)


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
		_fill_cell(im, c, y, Color(Palette.REACHABLE, 0.35))
	for c in _targets:
		_fill_cell(im, c, y + 0.002, Color(Palette.TARGET, 0.32))
	for c in _area:
		_fill_cell(im, c, y + 0.004, Color(Palette.AREA, 0.5))
	for i in range(1, _path.size()):
		_ribbon(im, world(_path[i - 1], y + 0.01), world(_path[i], y + 0.01), 0.07, Palette.PATH)
	if not _path.is_empty():
		_fill_poly(im, _disc(world(_path[_path.size() - 1], y + 0.012), 0.16), Palette.PATH)
	if _active != null:
		_outline_cell(im, _active, y + 0.015, 0.07, Palette.ACTIVE)
	if _hover != null:
		_outline_cell(im, _hover, y + 0.016, 0.05, Palette.HOVER)
	_overlay_mesh.mesh = _commit(im)


func set_fog(explored: Dictionary, visible_now: Dictionary) -> void:
	_explored = explored
	var im := {"v": [], "c": []}
	for c in engine.state.grid.cells():
		if not explored.has(c):
			_fill_poly(im, _cell_poly(c, 1.0), Color(0.0, 0.005, 0.015, 0.97), WALL_HEIGHT + 0.05)
		elif not visible_now.has(c):
			_fill_poly(im, _cell_poly(c, 1.0), Color(0.0, 0.0, 0.03, 0.5), _floor_y + 0.012)
	_fog_mesh.mesh = _commit(im)


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


## Turns a {"v": [...], "c": [...]} triangle buffer into a mesh (null if empty).
func _commit(buf: Dictionary) -> Mesh:
	var verts: Array = buf["v"]
	if verts.is_empty():
		return null
	var colors: Array = buf["c"]
	var mesh := ImmediateMesh.new()
	mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in verts.size():
		mesh.surface_set_color(colors[i])
		mesh.surface_add_vertex(verts[i])
	mesh.surface_end()
	return mesh


func _fill_cell(im: Dictionary, c: Vector2i, y: float, color: Color) -> void:
	_fill_poly(im, _cell_poly(c, 0.9), color, y)


func _fill_poly(im: Dictionary, poly: PackedVector3Array, color: Color, y: float = NAN) -> void:
	for i in range(1, poly.size() - 1):
		for v in [poly[0], poly[i], poly[i + 1]]:
			im["c"].append(color)
			im["v"].append(Vector3(v.x, v.y if is_nan(y) else y, v.z))


func _outline_cell(im: Dictionary, c: Vector2i, y: float, width: float, color: Color) -> void:
	var poly := _cell_poly(c, 0.95)
	for i in poly.size():
		_ribbon(im, Vector3(poly[i].x, y, poly[i].z), Vector3(poly[(i + 1) % poly.size()].x, y, poly[(i + 1) % poly.size()].z), width, color)


func _ribbon(im: Dictionary, a: Vector3, b: Vector3, width: float, color: Color) -> void:
	var side := (b - a).cross(Vector3.UP).normalized() * width / 2.0
	for v in [a - side, a + side, b + side, a - side, b + side, b - side]:
		im["c"].append(color)
		im["v"].append(v)


func _disc(center: Vector3, radius: float) -> PackedVector3Array:
	var out := PackedVector3Array()
	for i in 12:
		out.append(center + Vector3(cos(TAU * i / 12.0), 0, sin(TAU * i / 12.0)) * radius)
	return out


# --- Camera and input ---------------------------------------------------------

func cell_at_mouse() -> Variant:
	if camera == null:
		return null
	var mp := camera.get_viewport().get_mouse_position()
	var origin := camera.project_ray_origin(mp)
	var dir := camera.project_ray_normal(mp)
	if absf(dir.y) < 0.0001:
		return null
	var t := (_floor_y - origin.y) / dir.y
	if t < 0.0:
		return null
	var hit := origin + dir * t
	var cell := engine.state.grid.from_pixel(Vector2(hit.x, hit.z) / SCALE, GridMapView.CELL_SIZE)
	return cell if engine.state.grid.has_cell(cell) else null


func fit(area: Rect2) -> void:
	_last_area = area
	var lo := Vector3(INF, 0, INF)
	var hi := Vector3(-INF, 0, -INF)
	for c in engine.state.grid.cells():
		var w := world(c)
		lo = Vector3(minf(lo.x, w.x), 0, minf(lo.z, w.z))
		hi = Vector3(maxf(hi.x, w.x), 0, maxf(hi.z, w.z))
	_pivot = (lo + hi) / 2.0
	var screen := camera.get_viewport().get_visible_rect().size
	var tan_half := tan(deg_to_rad(camera.fov) / 2.0)
	# Margins: the near rows look wider than the pivot row under perspective.
	var width := (hi.x - lo.x) + 3.5
	var depth := (hi.z - lo.z) + 2.5
	var d_w := (width * screen.x / area.size.x) / (2.0 * tan_half * screen.x / screen.y)
	# Near rows are closer to the camera and take more screen height than sin(pitch) suggests.
	var d_h := (depth * sin(PITCH) * 1.3 * screen.y / area.size.y) / (2.0 * tan_half)
	_distance = maxf(d_w, d_h) * 1.12
	_update_camera()


func _update_camera() -> void:
	if camera == null:
		return
	var offset := Vector3(0, sin(PITCH), cos(PITCH)).rotated(Vector3.UP, _yaw) * _distance
	camera.look_at_from_position(_pivot + offset, _pivot, Vector3.UP)
	# Shift the view so the board's centre sits in the middle of the HUD-free area.
	if _last_area.size != Vector2.ZERO:
		var screen := camera.get_viewport().get_visible_rect().size
		var world_per_px := 2.0 * _distance * tan(deg_to_rad(camera.fov) / 2.0) / screen.y
		var d := _last_area.get_center() - screen / 2.0
		_base_offset = Vector2(-d.x, d.y) * world_per_px
		camera.h_offset = _base_offset.x
		camera.v_offset = _base_offset.y


func handle_input(event: InputEvent) -> bool:
	if camera == null:
		return false
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP and event.pressed:
			_distance = maxf(_distance * 0.9, 5.0)
			_update_camera()
			return true
		if event.button_index == MOUSE_BUTTON_WHEEL_DOWN and event.pressed:
			_distance = minf(_distance * 1.1, 60.0)
			_update_camera()
			return true
		if event.button_index == MOUSE_BUTTON_MIDDLE:
			_panning = event.pressed
			return true
	elif event is InputEventMouseMotion and _panning:
		_pan(-event.relative * _distance * 0.0016)
		return true
	elif event is InputEventKey and event.pressed:
		match event.keycode:
			KEY_Q:
				_rotate(-PI / 4.0)
				return true
			KEY_E:
				_rotate(PI / 4.0)
				return true
			KEY_LEFT:
				_pan(Vector2(-0.8, 0))
				return true
			KEY_RIGHT:
				_pan(Vector2(0.8, 0))
				return true
			KEY_UP:
				_pan(Vector2(0, -0.8))
				return true
			KEY_DOWN:
				_pan(Vector2(0, 0.8))
				return true
	return false


func _pan(screen_delta: Vector2) -> void:
	var right := Vector3.RIGHT.rotated(Vector3.UP, _yaw)
	var forward := Vector3.BACK.rotated(Vector3.UP, _yaw)
	_pivot += right * screen_delta.x + forward * screen_delta.y
	_update_camera()


func _rotate(amount: float) -> void:
	var tw := create_tween()
	tw.tween_method(func(y: float) -> void:
		_yaw = y
		_update_camera(), _yaw, _yaw + amount, 0.25).set_trans(Tween.TRANS_SINE)
