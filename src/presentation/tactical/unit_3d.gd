class_name Unit3D
extends Node3D
## A unit on the 3D board: a procedural model (ModelFactory, unit JSON
## visual.model) with a team ring on the floor, an active-unit ring, an idle
## hover for ships, and hit/shield/destroy animations. Bars and names are drawn
## in 2D on top by BoardOverlay3D (crisp text at any zoom).

const SHIP_ALTITUDE := 0.38

var unit_id := ""
var display_name := ""
var team_color := Color.WHITE
var is_active := false
var hull := 1
var max_hull := 1
var shields := 0
var max_shields := 1
var status_text := ""
## Height of the overlay anchor (bars/name) above the unit's cell.
var label_height := 0.9

## How high this ship flies above its hex (space battles stagger them).
var altitude := SHIP_ALTITUDE
## Extra height and roll while maneuvering (tweened by move_along).
var _lift := 0.0
var _bank := 0.0
var _model: Node3D
var _active_ring: MeshInstance3D
var _is_ship := false
var _spins := false
var _t := 0.0
## Forward lean of a person's body (radians): the melee strike pose.
var _lean := 0.0
var _trail: CPUParticles3D


## p_altitude < 0 keeps the default ship height.
func setup(u: BattleUnit, data: DataRegistry, color: Color, style: String = "", p_altitude: float = -1.0) -> void:
	unit_id = u.id
	display_name = u.name
	team_color = color
	var visual: Dictionary = u.def.get("visual", {})
	_is_ship = "ship" in u.tags or "station" in u.tags
	_spins = "immobile" in u.tags
	var model_id: String = visual.get("model", visual.get("placeholder", "frigate"))
	_model = ModelFactory.build(data, model_id, color, style)
	var s := float(visual.get("size", 1.0)) * (1.45 if _is_ship else 1.6)
	_model.scale = Vector3(s, s, s)
	add_child(_model)
	if _is_ship and not _spins:
		if p_altitude >= 0.0:
			altitude = p_altitude
		_model.position.y = altitude
		_trail = BoardGeometry.engine_trail(color, 1.3)
		_trail.position.y = altitude
		add_child(_trail)
		if altitude > SHIP_ALTITUDE + 0.1:
			_add_tether(color)
	label_height = (altitude + 0.75) if _is_ship else 1.6
	_t = randf() * TAU

	# Team marker on the floor: faint disc plus a crisp ring.
	var disc_node := MeshInstance3D.new()
	var disc := CylinderMesh.new()
	disc.top_radius = 0.7
	disc.bottom_radius = 0.7
	disc.height = 0.01
	disc.radial_segments = 32
	disc_node.mesh = disc
	disc_node.material_override = _flat_material(Color(color, 0.1))
	disc_node.position.y = 0.012
	add_child(disc_node)
	var ring := MeshInstance3D.new()
	var ring_mesh := TorusMesh.new()
	ring_mesh.inner_radius = 0.66
	ring_mesh.outer_radius = 0.7
	ring_mesh.rings = 32
	ring.mesh = ring_mesh
	ring.material_override = _flat_material(Color(color, 0.75))
	ring.position.y = 0.02
	ring.scale = Vector3(1, 0.1, 1)
	add_child(ring)

	_active_ring = MeshInstance3D.new()
	var torus := TorusMesh.new()
	torus.inner_radius = 0.78
	torus.outer_radius = 0.86
	torus.rings = 32
	_active_ring.mesh = torus
	_active_ring.material_override = _flat_material(Palette.ACTIVE)
	_active_ring.position.y = 0.03
	_active_ring.scale = Vector3(1, 0.15, 1)
	_active_ring.visible = false
	add_child(_active_ring)
	refresh(u)


func refresh(u: BattleUnit) -> void:
	hull = u.hull
	max_hull = maxi(1, u.max_hull())
	shields = u.shields
	max_shields = maxi(1, u.max_shields())
	var tags := PackedStringArray()
	for s in u.statuses:
		if s.def.get("hidden", false):
			continue
		var label: String = s.def.get("name", s.id)
		tags.append(label if s.is_permanent() else "%s %d" % [label, s.remaining])
	status_text = ", ".join(tags)


func set_active(value: bool) -> void:
	is_active = value
	_active_ring.visible = value


## Heading in the board's 2D sense: angle in the grid's pixel plane.
func face_angle(angle: float) -> void:
	if not _spins:
		rotation.y = -angle


func _process(delta: float) -> void:
	_t += delta
	if _spins:
		_model.rotation.y += delta * 0.4
	elif not _is_ship:
		# People breathe and shift their weight; leaning in is the melee pose.
		_model.position.y = (sin(_t * 2.1) + 1.0) * 0.006
		_model.rotation.z = -_lean + sin(_t * 0.9) * 0.012
		_model.rotation.x = sin(_t * 0.7 + 1.3) * 0.015
	elif _is_ship:
		_model.position.y = altitude + _lift + sin(_t * 1.6) * 0.035
		_model.rotation.x = sin(_t * 1.1) * 0.03 + _bank
		if _trail != null:
			_trail.position.y = _model.position.y
	if is_active:
		_active_ring.rotation.y += delta * 0.8


func move_along(points: Array[Vector3], step_time: float = 0.16) -> void:
	if points.is_empty():
		return
	var tw := create_tween()
	var prev := position
	var heading := -rotation.y
	for p in points:
		var d := p - prev
		var angle := atan2(d.z, d.x)
		if _is_ship and not _spins:
			# Bank into the turn, then level out over the step.
			var turn := wrapf(angle - heading, -PI, PI)
			tw.tween_callback(func() -> void: _bank = clampf(-turn * 0.6, -0.6, 0.6))
		tw.tween_callback(face_angle.bind(angle))
		tw.tween_property(self, "position", p, step_time).set_trans(Tween.TRANS_SINE)
		if _is_ship and not _spins:
			tw.parallel().tween_property(self, "_bank", 0.0, step_time).set_trans(Tween.TRANS_SINE)
		heading = angle
		prev = p
	if _is_ship and not _spins:
		# Climb out and settle back: a shallow arc over the whole move.
		var total := step_time * points.size()
		var arc := create_tween()
		arc.tween_property(self, "_lift", minf(0.18 + 0.05 * points.size(), 0.45), total * 0.5).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
		arc.tween_property(self, "_lift", 0.0, total * 0.5).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
	if _trail != null:
		_trail.emitting = true
	await tw.finished
	if _trail != null:
		_trail.emitting = false


## Attack runs and broadsides steer the ship directly: roll (radians) and
## extra height on top of its cruising altitude.
func set_maneuver(roll: float, lift: float) -> void:
	_bank = roll
	_lift = lift


func set_engines(on: bool) -> void:
	if _trail != null:
		_trail.emitting = on


## Model-space nose of the ship in world space (where forward guns fire from).
func nose_point(ahead: float = 0.35) -> Vector3:
	var heading := -rotation.y
	return aim_point() + Vector3(cos(heading), 0, sin(heading)) * ahead * _model.scale.x


## Recoil: the hull kicks back along its heading and settles.
func play_recoil(amount: float = 0.12) -> void:
	# The model's forward is local +X (the node itself carries the heading).
	var tw := create_tween()
	tw.tween_property(_model, "position:x", -amount, 0.05)
	tw.tween_property(_model, "position:x", 0.0, 0.35).set_trans(Tween.TRANS_SINE)


## A faint holo line from the ship down to its hex, so height reads as
## height rather than as position.
func _add_tether(color: Color) -> void:
	var tether := MeshInstance3D.new()
	var line := CylinderMesh.new()
	line.top_radius = 0.016
	line.bottom_radius = 0.016
	line.height = altitude - 0.08
	line.radial_segments = 6
	line.rings = 1
	tether.mesh = line
	tether.material_override = _additive_material(Color(color, 1.0) * 0.6)
	tether.position.y = 0.02 + line.height / 2.0
	tether.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(tether)


func play_hit() -> void:
	var tw := create_tween()
	tw.tween_property(_model, "scale", _model.scale * 1.08, 0.05)
	tw.tween_property(_model, "scale", _model.scale, 0.15)


## Hand-to-hand strike: rock back, lunge to just short of `target_ground`
## (the target's position), call `on_contact` as the blow lands, then recover.
## Ships have no melee pose, they just ram forward and back.
func play_melee(target_ground: Vector3, on_contact: Callable) -> void:
	var start := position
	var dir := target_ground - start
	dir.y = 0.0
	var gap := dir.length()
	if gap < 0.01:
		on_contact.call()
		return
	var contact := start + dir.normalized() * maxf(gap - 0.95, 0.0)
	var tw := create_tween()
	tw.tween_property(self, "_lean", 0.18, 0.1).set_trans(Tween.TRANS_SINE)
	tw.parallel().tween_property(self, "position", start - dir.normalized() * 0.08, 0.1)
	tw.tween_property(self, "_lean", 0.5, 0.09).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tw.parallel().tween_property(self, "position", contact, 0.09).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tw.tween_callback(on_contact)
	tw.tween_interval(0.07)
	tw.tween_property(self, "_lean", 0.0, 0.22).set_trans(Tween.TRANS_SINE)
	tw.parallel().tween_property(self, "position", start, 0.22).set_trans(Tween.TRANS_SINE)
	await tw.finished


## A short flinch away from `from_ground` (taking a melee blow).
func recoil(from_ground: Vector3) -> void:
	var away := position - from_ground
	away.y = 0.0
	if away.length() < 0.01:
		return
	var rest := position
	var tw := create_tween()
	tw.tween_property(self, "position", rest + away.normalized() * 0.14, 0.06).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.tween_property(self, "position", rest, 0.2).set_trans(Tween.TRANS_SINE)


## Shield bubble flash, brightest on the side facing the attacker.
func play_shield_hit(from_world: Vector3) -> void:
	var bubble := MeshInstance3D.new()
	var sphere := SphereMesh.new()
	sphere.radius = 0.75
	sphere.height = 1.0
	bubble.mesh = sphere
	var mat := _additive_material(Color(Palette.SHIELDS, 1.0) * 0.6)
	bubble.material_override = mat
	bubble.position.y = _model.position.y + 0.15
	add_child(bubble)
	var flare := MeshInstance3D.new()
	var dot := SphereMesh.new()
	dot.radius = 0.18
	dot.height = 0.36
	flare.mesh = dot
	flare.material_override = _additive_material(Palette.SHIELDS)
	add_child(flare)
	var toward := from_world - global_position
	toward.y = 0.0
	flare.position = Vector3(0, bubble.position.y, 0) + (toward.normalized() * 0.72).rotated(Vector3.UP, -rotation.y)
	var tw := create_tween().set_parallel()
	tw.tween_property(mat, "albedo_color", Color.BLACK, 0.45)
	tw.tween_property(flare, "scale", Vector3.ONE * 2.0, 0.3)
	tw.tween_property(flare.material_override, "albedo_color", Color.BLACK, 0.3)
	tw.chain().tween_callback(func() -> void:
		bubble.queue_free()
		flare.queue_free())


func play_destroyed() -> void:
	var tw := create_tween().set_parallel()
	tw.tween_property(_model, "scale", Vector3.ONE * 0.01, 0.45).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_IN)
	tw.tween_property(_model, "rotation:y", _model.rotation.y + 2.5, 0.45)
	await tw.finished
	visible = false


## World position shots should aim at / come from.
func aim_point() -> Vector3:
	return global_position + Vector3(0, _model.position.y + (0.12 if _is_ship else 0.85), 0)


static func _flat_material(color: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = color
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	return m


static func _additive_material(color: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	m.albedo_color = color
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.no_depth_test = false
	return m
