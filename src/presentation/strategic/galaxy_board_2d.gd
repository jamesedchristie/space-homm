class_name GalaxyBoard2D
extends GalaxyBoard
## The top-down 2D galaxy map: GridMapView with PlanetView, FleetView and
## AnomalyView markers and an FxLayer, all living in the screen's scene.

const FLEET_OFFSET := Vector2(9, 9)
const PLANET_OFFSET := Vector2(-8, -6)

var map_view: GridMapView
var planets_layer: Node2D
var fleets_layer: Node2D
var anomalies_layer: Node2D
var fx: FxLayer
var fleet_views: Dictionary = {}    # fleet id -> FleetView
var planet_views: Dictionary = {}   # planet id -> PlanetView
var anomaly_views: Dictionary = {}  # anomaly id -> AnomalyView


func _init(p_map_view: GridMapView, p_planets: Node2D, p_fleets: Node2D, p_anomalies: Node2D, p_fx: FxLayer) -> void:
	map_view = p_map_view
	planets_layer = p_planets
	fleets_layer = p_fleets
	anomalies_layer = p_anomalies
	fx = p_fx


func setup(p_engine: GalaxyEngine, p_data: DataRegistry, p_player_faction: String) -> void:
	super.setup(p_engine, p_data, p_player_faction)
	_clear()
	map_view.visible = true
	map_view.setup(engine.state.grid)
	for p: Planet in engine.state.planets.values():
		var pv := PlanetView.new()
		planets_layer.add_child(pv)
		pv.setup(p, data)
		pv.position = map_view.cell_center(p.cell) + PLANET_OFFSET
		planet_views[p.id] = pv


func teardown() -> void:
	_clear()
	map_view.visible = false


func _clear() -> void:
	for v: Node in fleet_views.values() + planet_views.values() + anomaly_views.values():
		v.queue_free()
	fleet_views.clear()
	planet_views.clear()
	anomaly_views.clear()


func sync(visible_now: Dictionary, explored: Dictionary, selected_fleet: String) -> void:
	map_view.set_fog(explored, visible_now)
	for id: String in fleet_views.keys():
		if not engine.state.fleets.has(id):
			fleet_views[id].queue_free()
			fleet_views.erase(id)
	for fleet: Fleet in engine.state.fleets.values():
		var view: FleetView = fleet_views.get(fleet.id)
		if view == null:
			view = FleetView.new()
			fleets_layer.add_child(view)
			view.setup(fleet, engine.state.faction(fleet.owner)["team"], data, fleet.owner == player_faction)
			fleet_views[fleet.id] = view
		view.refresh(fleet, data, engine.fleet_speed(fleet))
		view.position = map_view.cell_center(fleet.cell) + FLEET_OFFSET
		view.visible = engine.can_see_fleet(player_faction, fleet, visible_now)
		view.set_selected(fleet.id == selected_fleet)
	for p: Planet in engine.state.planets.values():
		planet_views[p.id].refresh(p, engine.state)
	for id: String in anomaly_views.keys():
		if not engine.state.anomalies.has(id):
			anomaly_views[id].queue_free()
			anomaly_views.erase(id)
	for a: Dictionary in engine.state.anomalies.values():
		var av: AnomalyView = anomaly_views.get(a["id"])
		if av == null:
			av = AnomalyView.new()
			anomalies_layer.add_child(av)
			anomaly_views[a["id"]] = av
		av.setup(a)
		av.position = map_view.cell_center(a["cell"]) + PLANET_OFFSET
		av.visible = explored.has(a["cell"])


func is_fleet_shown(fleet_id: String) -> bool:
	return fleet_views.has(fleet_id) and fleet_views[fleet_id].visible


func move_fleet(fleet_id: String, path: Array) -> void:
	var view: FleetView = fleet_views.get(fleet_id)
	if view == null:
		return
	view.visible = true
	var points: Array[Vector2] = []
	for i in range(1, path.size()):
		points.append(map_view.cell_center(path[i]) + FLEET_OFFSET)
	await view.move_along(points)


func destroy_fleet(fleet_id: String) -> void:
	var view: FleetView = fleet_views.get(fleet_id)
	if view == null or not view.visible:
		return
	fx.explode(view.position, 1.0)
	fx.play_sound("explosion")
	await view.play_destroyed()


func refresh_planet(planet_id: String) -> void:
	planet_views[planet_id].refresh(engine.state.planets[planet_id], engine.state)


func float_text_at_fleet(fleet_id: String, text: String, color: Color) -> void:
	if fleet_views.has(fleet_id):
		fx.float_text(fleet_views[fleet_id].position, text, color)


func float_text_at_planet(planet_id: String, text: String, color: Color) -> void:
	fx.float_text(planet_views[planet_id].position, text, color)


func pulse(cell: Vector2i, color: Color) -> void:
	var pos := map_view.cell_center(cell)
	fx.play("pulse", pos, pos, color, 0.0, "Red")


func set_highlights(move: Array[Vector2i], attack: Array[Vector2i], path: Array[Vector2i]) -> void:
	map_view.set_highlights(move, attack, [], path)


func set_hover(cell: Variant) -> void:
	map_view.set_hover(cell)


func set_active_cell(cell: Variant) -> void:
	map_view.set_active(cell)


func set_selected_fleet(fleet_id: String) -> void:
	for id: String in fleet_views:
		fleet_views[id].set_selected(id == fleet_id)


func cell_at_mouse() -> Variant:
	return map_view.cell_at_global(map_view.get_global_mouse_position())


func fit(area: Rect2) -> void:
	var b := map_view.bounds()
	var f := clampf(minf((area.size.x - 32.0) / b.size.x, (area.size.y - 32.0) / b.size.y), 0.4, 1.6)
	map_view.scale = Vector2(f, f)
	map_view.position = area.get_center() - b.get_center() * f
