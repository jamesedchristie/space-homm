class_name Fleet3D
extends Node3D
## A fleet on the 3D galaxy board: a model of its biggest ship with up to two
## smaller escorts, hovering over a team-colored ring. Name, hull bar, ship
## count and move pips are drawn in 2D by GalaxyOverlay3D.

const ALTITUDE := 0.32

var fleet_id := ""
var display_name := ""
var color := Color.WHITE
var ship_count := 0
var moves_left := 0
var max_moves := 0
var hull_ratio := 1.0
var selected := false
var show_moves := false
var label_height := 1.15

var _data: DataRegistry
var _models: Node3D
var _select_ring: MeshInstance3D
var _composition := ""
var _t := 0.0


func setup(fleet: Fleet, team: int, data: DataRegistry, owned_by_player: bool) -> void:
	fleet_id = fleet.id
	_data = data
	color = Palette.team_color(team)
	show_moves = owned_by_player
	_t = randf() * TAU
	_models = Node3D.new()
	_models.position.y = ALTITUDE
	add_child(_models)

	var ring := MeshInstance3D.new()
	var torus := TorusMesh.new()
	torus.inner_radius = 0.3
	torus.outer_radius = 0.33
	torus.rings = 32
	ring.mesh = torus
	ring.material_override = BoardGeometry.flat_material(Color(color, 0.8))
	ring.position.y = 0.03
	ring.scale = Vector3(1, 0.1, 1)
	add_child(ring)
	var disc := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = 0.31
	cyl.bottom_radius = 0.31
	cyl.height = 0.005
	cyl.radial_segments = 24
	disc.mesh = cyl
	disc.material_override = BoardGeometry.flat_material(Color(color, 0.12))
	disc.position.y = 0.025
	add_child(disc)

	_select_ring = MeshInstance3D.new()
	var sel := TorusMesh.new()
	sel.inner_radius = 0.38
	sel.outer_radius = 0.43
	sel.rings = 32
	_select_ring.mesh = sel
	_select_ring.material_override = BoardGeometry.flat_material(Palette.ACTIVE)
	_select_ring.position.y = 0.04
	_select_ring.scale = Vector3(1, 0.12, 1)
	_select_ring.visible = false
	add_child(_select_ring)
	face_angle(0.0 if team == 0 else PI)
	refresh(fleet, data)


## max_moves_override: moves per turn including tech bonuses (-1 = base speed).
func refresh(fleet: Fleet, data: DataRegistry, max_moves_override: int = -1) -> void:
	display_name = fleet.name
	ship_count = fleet.ships.size()
	moves_left = fleet.moves_left
	max_moves = max_moves_override if max_moves_override >= 0 else fleet.speed(data)
	hull_ratio = fleet.hull_ratio(data)
	var units := PackedStringArray()
	for ship in fleet.ships:
		units.append(ship["unit"])
	units.sort()
	var composition := ",".join(units)
	if composition != _composition:
		_composition = composition
		_build_models(fleet)


func _build_models(fleet: Fleet) -> void:
	for child in _models.get_children():
		child.queue_free()
	# Biggest ship leads; the next two biggest fly escort behind it.
	var defs: Array[Dictionary] = []
	for ship in fleet.ships:
		defs.append(_data.units[ship["unit"]])
	defs.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return a["stats"]["max_hull"] > b["stats"]["max_hull"])
	var slots := [Vector3(0.08, 0, 0), Vector3(-0.3, -0.04, -0.3), Vector3(-0.3, -0.04, 0.3)]
	for i in mini(defs.size(), slots.size()):
		var visual: Dictionary = defs[i].get("visual", {})
		var model := ModelFactory.build(_data, visual.get("model", "frigate"), color)
		var s := float(visual.get("size", 1.0)) * (0.85 if i == 0 else 0.5)
		model.scale = Vector3(s, s, s)
		model.position = slots[i]
		_models.add_child(model)


func set_selected(value: bool) -> void:
	selected = value
	_select_ring.visible = value


## Heading as an angle in the grid's pixel plane.
func face_angle(angle: float) -> void:
	_models.rotation.y = -angle


func _process(delta: float) -> void:
	_t += delta
	_models.position.y = ALTITUDE + sin(_t * 1.5) * 0.025
	if selected:
		_select_ring.rotation.y += delta * 0.8


func move_along(points: Array[Vector3], step_time: float = 0.14) -> void:
	if points.is_empty():
		return
	var tw := create_tween()
	var prev := position
	for p in points:
		var d := p - prev
		tw.tween_callback(face_angle.bind(atan2(d.z, d.x)))
		tw.tween_property(self, "position", p, step_time).set_trans(Tween.TRANS_SINE)
		prev = p
	await tw.finished


func play_destroyed() -> void:
	var tw := create_tween().set_parallel()
	tw.tween_property(_models, "scale", Vector3.ONE * 0.01, 0.45).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_IN)
	tw.tween_property(_models, "rotation:y", _models.rotation.y + 2.5, 0.45)
	await tw.finished
	visible = false


func aim_point() -> Vector3:
	return global_position + Vector3(0, ALTITUDE, 0)
