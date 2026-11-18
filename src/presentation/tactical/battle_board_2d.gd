class_name BattleBoard2D
extends BattleBoard
## The top-down 2D battlefield: GridMapView + UnitView sprites + FxLayer.

var map_view: GridMapView
var units_layer: Node2D
var fx: FxLayer
var views: Dictionary = {}  # unit id -> UnitView


func _init(p_map_view: GridMapView, p_units_layer: Node2D, p_fx: FxLayer) -> void:
	map_view = p_map_view
	units_layer = p_units_layer
	fx = p_fx


func setup(p_engine: BattleEngine, p_data: DataRegistry, floor_style: String) -> void:
	super.setup(p_engine, p_data, floor_style)
	_clear_units()
	map_view.visible = true
	map_view.setup(engine.state.grid, floor_style)
	if not engine.state.fog_enabled:
		map_view.clear_fog()
	_set_scenery()


## Discs for the planets (and a glow for the star) of a battle inside a star system.
func _set_scenery() -> void:
	var bodies: Array[Dictionary] = []
	var star_info: Dictionary = {}
	var scenery := engine.state.scenery
	if not scenery.is_empty():
		var grid := engine.state.grid
		for body: Dictionary in scenery.get("bodies", []):
			if body.get("kind", "planet") != "planet":
				continue
			var center := Vector2.ZERO
			for p: Array in body["cells"]:
				center += map_view.cell_center(grid.cell_from_layout(Vector2i(int(p[0]), int(p[1]))))
			center /= float((body["cells"] as Array).size())
			var surface: Dictionary = data.body_types.get(body["type"], {}).get("surface", {})
			bodies.append({"center": center, "radius": float(body["radius"]) * GridMapView.CELL_SIZE,
					"base": Color(surface.get("base", "#888888")), "accent": Color(surface.get("accent", "#bbbbbb")),
					"atmosphere": Color(surface.get("atmosphere", "#00000000")),
					"ring": body["type"] == "gas_giant", "colony": body.get("colony", false)})
		var star: Dictionary = scenery.get("star", {})
		if star.has("dir"):
			var rect := map_view.bounds()
			var dir := Vector2(float(star["dir"][0]), float(star["dir"][1])).normalized()
			star_info = {"pos": rect.get_center() + dir * (rect.size.length() * 0.5 * 0.8),
					"color": Color(data.star_types.get(star.get("type", ""), {}).get("color", "#ffd88a"))}
	map_view.set_scenery(bodies, star_info)


func teardown() -> void:
	_clear_units()
	map_view.set_scenery([], {})
	map_view.visible = false


func _clear_units() -> void:
	for v: UnitView in views.values():
		v.queue_free()
	views.clear()


func add_unit(u: BattleUnit) -> void:
	var view := UnitView.new()
	units_layer.add_child(view)
	view.setup(u, u.def, GridMapView.CELL_SIZE)
	view.position = map_view.cell_center(u.cell)
	views[u.id] = view


func move_unit(unit_id: String, path: Array, animate: bool) -> void:
	var view: UnitView = views[unit_id]
	var points: Array[Vector2] = []
	for i in range(1, path.size()):
		points.append(map_view.cell_center(path[i]))
	if animate:
		view.visible = true
		await view.move_along(points)
	elif not points.is_empty():
		view.position = points[points.size() - 1]


func face_unit(unit_id: String, cell: Vector2i) -> void:
	views[unit_id].face_towards(map_view.cell_center(cell))


func refresh_unit(u: BattleUnit, is_visible: bool) -> void:
	if not views.has(u.id):
		return  # e.g. reinforcements whose spawn event hasn't been played yet
	views[u.id].refresh(u)
	views[u.id].visible = is_visible


func set_unit_values(unit_id: String, hull: int, shields: int) -> void:
	views[unit_id].set_values(hull, shields)


func set_unit_visible(unit_id: String, is_visible: bool) -> void:
	views[unit_id].visible = is_visible


func set_active_unit(unit_id: String) -> void:
	for id: String in views:
		views[id].set_active(id == unit_id)


func unit_hit(unit_id: String, source_id: String, shield_hit: bool) -> void:
	var view: UnitView = views[unit_id]
	view.play_hit()
	if shield_hit and views.has(source_id):
		view.play_shield_hit((views[source_id].position - view.position).angle())


func destroy_unit(unit_id: String, big: bool) -> void:
	var view: UnitView = views[unit_id]
	fx.explode(view.position, 1.4 if big else 0.8)
	fx.play_sound("explosion")
	if big:
		shake(7.0)
	await view.play_destroyed()


func float_text(unit_id: String, text: String, color: Color, rise: float = 0.0) -> void:
	fx.float_text(views[unit_id].position + Vector2(0, -rise), text, color)


func play_ability(kind: String, source_id: String, target: Vector2i, color: Color, radius: int, laser: String) -> void:
	var source: UnitView = views[source_id]
	var to := map_view.cell_center(target)
	if kind != "self":
		source.face_towards(to)
	if kind == "melee":
		# Lunge at the target, land the blow, step back.
		var home := source.position
		var tw := create_tween()
		tw.tween_property(source, "position", home.lerp(to, 0.6), 0.1).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
		tw.tween_callback(fx.play.bind("melee", source.position, to, color, 0.0, laser))
		tw.tween_callback(shake.bind(3.0))
		tw.tween_property(source, "position", home, 0.2).set_trans(Tween.TRANS_SINE)
		await tw.finished
		return
	await fx.play(kind, source.position, to, color, radius * GridMapView.CELL_SIZE * 1.8, laser)


func play_sound(key: String) -> void:
	fx.play_sound(key)


func shake(strength: float) -> void:
	var base := map_view.position
	var tw := create_tween()
	for i in 6:
		var offset := Vector2(randf_range(-1, 1), randf_range(-1, 1)) * strength * (1.0 - i / 6.0)
		tw.tween_property(map_view, "position", base + offset, 0.035)
	tw.tween_property(map_view, "position", base, 0.04)


func set_highlights(reach: Array[Vector2i], targets: Array[Vector2i], area: Array[Vector2i], path: Array[Vector2i]) -> void:
	map_view.set_highlights(reach, targets, area, path)


func set_hover(cell: Variant) -> void:
	map_view.set_hover(cell)


func set_active_cell(cell: Variant) -> void:
	map_view.set_active(cell)


func set_fog(explored: Dictionary, visible_now: Dictionary) -> void:
	map_view.set_fog(explored, visible_now)


func set_markers(markers: Dictionary) -> void:
	map_view.set_markers(markers)


func cell_at_mouse() -> Variant:
	return map_view.cell_at_global(map_view.get_global_mouse_position())


func fit(area: Rect2) -> void:
	var b := map_view.bounds()
	var f := clampf(minf((area.size.x - 32.0) / b.size.x, (area.size.y - 32.0) / b.size.y), 0.4, 1.6)
	map_view.scale = Vector2(f, f)
	map_view.position = area.get_center() - b.get_center() * f
