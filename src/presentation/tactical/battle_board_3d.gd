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
	var in_system := not engine.state.scenery.is_empty()
	BoardGeometry.space_scenery(_world, (lo + hi) / 2.0, Vector2(hi.x - lo.x, hi.z - lo.z) / 2.0,
			engine.state.seed_value, _floor == "deck", not in_system)
	if in_system:  # a battle inside a star system: its planets and star (SystemBattleMap)
		SystemScenery3D.build(_world, engine.state.scenery, data, engine.state.grid, world, lo, hi, engine.state.seed_value)
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
	BoardGeometry.build_environment(_world, true)
	_rig = BoardCamera3D.new()
	if _floor != "deck":
		# Space: a lower view so ships at different heights read as a 3D formation.
		_rig.pitch = deg_to_rad(40.0)
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
			# A faint holographic plane: the ships and rocks above it carry the depth.
			var fill := Color(0.05, 0.08, 0.15, 0.05)
			if terrain.has("color"):
				fill = Color(terrain["color"])
				fill.a = 0.16
			# High quality: open space is open (just the grid lines); terrain a faint tint.
			if not BoardGeometry.high_quality() or terrain.has("color"):
				if BoardGeometry.high_quality():
					fill.a = 0.07
				BoardGeometry.prism(glass, _cell_poly(c, 0.95), -0.02, 0.0, fill.darkened(0.3), fill)
			if deco == "rocks":
				BoardGeometry.rocks(_world, world(c), hash(c), 0.6, true)
			elif deco == "debris":
				BoardGeometry.rocks(_world, world(c), hash(c), 0.5, true)
			if terrain.get("blocks_sight", false) and terrain.get("passable", true):
				BoardGeometry.nebula_puffs(_world, world(c), Color(terrain.get("color", "#553377")), hash(c) + 7, 1.5)
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
	var team := engine.state.team_info(u.team)
	view.setup(u, data, Palette.team_color(u.team), team.get("species", ""), _ship_altitude(u),
			String(team.get("model_variant", "")) if not String(team.get("model_variant", "")).is_empty() \
					else ("raider" if team.get("role", "") == "barbarian" else ""))
	view.position = _unit_ground(u)
	view.face_angle(0.0 if u.team == 0 else PI)
	views[u.id] = view


## Ships in open space fly at staggered heights (stable per unit); on decks
## and for stations, the default.
func _ship_altitude(u: BattleUnit) -> float:
	if _floor == "deck" or "ship" not in u.tags or "immobile" in u.tags:
		return -1.0
	var h := absi(hash(u.id + "alt")) % 1000 / 1000.0
	return lerpf(0.3, 1.35, h)


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
	_sync_craft(views[u.id])


func set_unit_values(unit_id: String, hull: int, shields: int) -> void:
	views[unit_id].hull = hull
	views[unit_id].shields = shields
	_sync_craft(views[unit_id])


## Squadron craft lost to damage break up in small explosions.
func _sync_craft(view: Unit3D) -> void:
	for p in view.sync_craft():
		if view.visible:
			_fx.explode(p, 0.45)


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
	_fx2d.play_sound("explosion")
	if view.squadron > 1:
		# The last craft of the wing go up one after another.
		var pts := view.craft_points()
		for i in pts.size():
			_fx.explode(pts[i], 0.6)
			if i < pts.size() - 1:
				await get_tree().create_timer(0.08).timeout
	else:
		_fx.explode(view.aim_point(), clampf(view.radius() * 1.2, 0.8, 1.8) if big else 0.8)
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
	var to: Vector3 = views[target_unit.id].hit_point() if target_unit != null and views.has(target_unit.id) \
			else world(target, _floor_y + 0.3)
	if kind == "melee":
		# Lunge at the target; the blow lands (flash, sparks, thud, flinch) mid-animation.
		var victim: Unit3D = views.get(target_unit.id) if target_unit != null else null
		await source.play_melee(world(target, _floor_y), func() -> void:
			_fx2d.play_sound("melee")
			_fx.play("melee", source.aim_point(), to, color, 0.0)
			if victim != null:
				victim.recoil(source.position)
			_rig.shake(0.12))
		return
	_fx2d.play_sound(kind)
	match _attack_style(source_id, kind):
		"run":
			await _strafing_run(source, target, to, color)
			return
		"broadside":
			await _broadside(source, to, color)
			return
		"spinal":
			await _spinal_shot(source, to, color)
			return
	var blast := float(radius) * engine.state.grid.to_pixel(Vector2i(1, 0), GridMapView.CELL_SIZE).length() * SCALE
	await _fx.play(kind, source.aim_point(), to, color, blast)


# --- Ship attack styles -------------------------------------------------------
# Unit visual "attack_style" picks how a ship delivers its direct-fire weapons
# (projectile and beam abilities) in open space:
#   "run"        fighters: a strafing pass over the target and a loop back home
#   "broadside"  line ships: turn side-on and ripple-fire down the hull
#   "spinal"     capital ships: charge, one heavy slug down the keel, recoil

func _attack_style(source_id: String, kind: String) -> String:
	if _floor == "deck" or kind not in ["projectile", "beam"]:
		return ""
	var u := engine.state.get_unit(source_id)
	return "" if u == null else str(u.def.get("visual", {}).get("attack_style", ""))


func _strafing_run(view: Unit3D, target: Vector2i, to: Vector3, color: Color) -> void:
	var home := view.position
	var tgt := world(target, _floor_y)
	var flat := tgt - home
	flat.y = 0.0
	var dist := flat.length()
	if dist < 0.05:
		await _fx.play("projectile", view.aim_point(), to, color, 0.0)
		return
	var fwd := flat / dist
	var side := fwd.cross(Vector3.UP).normalized() * (1.0 if absi(hash(view.unit_id)) % 2 == 0 else -1.0)
	# Out past the target and back round in a loop.
	var pts: Array[Vector3] = [home, home + fwd * dist * 0.35 + side * 0.25, tgt - fwd * 0.75 + side * 0.18,
			tgt + fwd * 0.85 - side * 0.12, tgt + fwd * 1.15 - side * 1.0, home - fwd * 0.4 - side * 0.9, home]
	# Dive toward the target's height on the pass.
	var target_view: Unit3D = null
	var tu := engine.state.unit_at(target)
	if tu != null and views.has(tu.id):
		target_view = views[tu.id]
	var dive := 0.0 if target_view == null else clampf(target_view.altitude - view.altitude, -0.6, 0.6)
	var duration := 1.5 + dist * 0.12
	var state := {"heading": -view.rotation.y, "next_shot": 0.3}
	view.set_engines(true)
	var step := func(t: float) -> void:
		var p := _catmull(pts, t)
		var ahead := _catmull(pts, minf(t + 0.02, 1.0))
		view.position = p
		var d := ahead - p
		if d.length() > 0.0005:
			var heading := atan2(d.z, d.x)
			var turn := wrapf(heading - float(state["heading"]), -PI, PI)
			state["heading"] = heading
			view.face_angle(heading)
			view.set_maneuver(clampf(-turn * 6.0, -0.9, 0.9), dive * sin(PI * clampf((t - 0.15) / 0.5, 0.0, 1.0)))
		# Guns on the approach: a stream of short bolts at the target.
		if t >= float(state["next_shot"]) and t <= 0.5:
			state["next_shot"] = t + 0.035
			var jitter := Vector3(randf_range(-0.08, 0.08), randf_range(-0.05, 0.05), randf_range(-0.08, 0.08))
			var noses := view.craft_noses(0.5)
			_fx.play("projectile", noses[randi() % noses.size()], to + jitter, color, 0.0)
	var tw := create_tween()
	tw.tween_method(step, 0.0, 1.0, duration).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	await tw.finished
	view.position = home
	view.set_maneuver(0.0, 0.0)
	view.set_engines(false)
	face_unit(view.unit_id, target)


func _broadside(view: Unit3D, to: Vector3, color: Color) -> void:
	# Turn side-on to the target (whichever way is the shorter turn), then
	# ripple-fire from gun ports along the hull.
	var d := to - view.global_position
	var bearing := atan2(d.z, d.x)
	var heading := -view.rotation.y
	var a := bearing + PI / 2.0
	var b := bearing - PI / 2.0
	var goal := a if absf(wrapf(a - heading, -PI, PI)) < absf(wrapf(b - heading, -PI, PI)) else b
	var tw := create_tween()
	tw.tween_method(func(h: float) -> void: view.face_angle(h), heading, heading + wrapf(goal - heading, -PI, PI), 0.3) \
			.set_trans(Tween.TRANS_SINE)
	await tw.finished
	var fwd := Vector3(cos(goal), 0, sin(goal))
	var guns: Array[Vector3] = []
	if view.squadron > 1:
		# Each craft of the squadron fires in turn, a rolling broadside down the line.
		await get_tree().create_timer(0.12).timeout  # let the wing finish wheeling
		for p in view.craft_points():
			guns.append(p + (to - p).normalized() * 0.08)
		if guns.size() < 3:
			guns.append_array(guns.duplicate())
	else:
		var span := view.craft_length() * 0.32
		for port in [-span, 0.0, span]:
			guns.append(view.aim_point() + fwd * port + (to - view.aim_point()).normalized() * 0.18)
	for i in guns.size():
		var from := guns[i]
		_fx.flash_small(from, color)
		if i == guns.size() - 1:
			await _fx.play("projectile", from, to, color, 0.0)
		else:
			_fx.play("projectile", from, to + Vector3(0, 0.04 * (i % 3), 0), color, 0.0)
			await get_tree().create_timer(0.09).timeout


func _spinal_shot(view: Unit3D, to: Vector3, color: Color) -> void:
	# Each ship (one capital ship, or every ship of a squadron) charges its
	# spinal gun at the bow, then they fire in turn.
	var noses := view.craft_noses(0.55)
	for i in noses.size():
		if i < noses.size() - 1:
			_fx.charge(noses[i], color, 0.28)
		else:
			await _fx.charge(noses[i], color, 0.28)
	view.play_recoil(0.14 if noses.size() == 1 else 0.1)
	shake(0.08)
	noses = view.craft_noses(0.55)
	for i in noses.size():
		if i < noses.size() - 1:
			_fx.play("slug", noses[i], to + Vector3(0, 0.05 * i, 0), color, 0.0)
			await get_tree().create_timer(0.1).timeout
		else:
			await _fx.play("slug", noses[i], to, color, 0.0)


## Catmull-Rom spline through pts, t in 0..1 over the whole path.
static func _catmull(pts: Array[Vector3], t: float) -> Vector3:
	var n := pts.size() - 1
	var f := clampf(t, 0.0, 1.0) * n
	var i := mini(int(f), n - 1)
	var u := f - i
	var p0 := pts[maxi(i - 1, 0)]
	var p1 := pts[i]
	var p2 := pts[i + 1]
	var p3 := pts[mini(i + 2, n)]
	return 0.5 * ((2.0 * p1) + (-p0 + p2) * u + (2.0 * p0 - 5.0 * p1 + 4.0 * p2 - p3) * u * u
			+ (-p0 + 3.0 * p1 - 3.0 * p2 + p3) * u * u * u)


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
		BoardGeometry.fill_poly(im, _cell_poly(c, 1.0), Color(Palette.REACHABLE, 0.07 if BoardGeometry.high_quality() else 0.15), y)
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
	# Ships fly above their hexes: pointing at the model picks its cell.
	var mouse := camera.get_viewport().get_mouse_position()
	var best_d := 30.0
	var best: Variant = null
	for id: String in views:
		var view: Unit3D = views[id]
		var u: BattleUnit = engine.state.units.get(id)
		if u == null or not u.alive or not view.visible or view.altitude <= Unit3D.SHIP_ALTITUDE + 0.1:
			continue
		var at := view.aim_point()
		if camera.is_position_behind(at):
			continue
		var d := camera.unproject_position(at).distance_to(mouse)
		if d < best_d:
			best_d = d
			best = u.cell
	if best != null:
		return best
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
	if _floor != "deck":
		# Space boards are wide and flat: frame them a little tighter so the squadrons read.
		_rig.fit(lo, hi, area, Vector2(1.0, 0.6))
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
