class_name Unit3D
extends Node3D
## A unit on the 3D board: procedural models (ModelFactory, unit JSON
## visual.model, the species' own design when it has one) with a team ring on
## the floor, an active-unit ring, an idle hover for ships, and hit / shield /
## destroy animations. Bars and names are drawn in 2D on top by BoardOverlay3D
## (crisp text at any zoom).
##
## Squadrons (visual.squadron > 1, see Squadron): the unit is several small
## craft in formation. `_model` is the formation; each craft follows the
## formation's recent path with a small delay (so the wing turns, banks and
## flies attack runs slightly staggered) and bobs on its own. Craft drop out as
## the hull falls (sync_craft()). A single ship is a squadron of one.

const SHIP_ALTITUDE := 0.38
## Seconds of formation history the trailing craft follow.
const HISTORY := 0.3

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
## Craft in the full squadron and craft currently shown.
var squadron := 1
var craft_shown := 1
## Extra height and roll while maneuvering (tweened by move_along).
var _lift := 0.0
var _bank := 0.0
## The formation (people and stations: the body), carrying heading effects.
var _model: Node3D
## Per craft: a holder placed every frame and the scaled model inside it.
var _holders: Array[Node3D] = []
var _bodies: Array[Node3D] = []
var _trails: Array[CPUParticles3D] = []
var _slots: Array[Vector3] = []
var _lags: Array[float] = []
var _phases: Array[float] = []
var _lost: Array[bool] = []
## [time, formation global transform, bank] samples, oldest first.
var _history: Array = []
var _craft_scale := 1.0
var _craft_length := 1.0
## Rough radius of the whole unit (shield bubble).
var _radius := 0.75
var _active_ring: MeshInstance3D
var _is_ship := false
var _spins := false
var _t := 0.0
## Forward lean of a person's body (radians): the melee strike pose.
var _lean := 0.0


## The model a unit is drawn with: the species' own design for its class, or
## the raiders' scrappy variant ("raider"), else the shared one.
static func model_id_for(data: DataRegistry, def: Dictionary, style: String, variant: String = "") -> String:
	var visual: Dictionary = def.get("visual", {})
	var base: String = visual.get("model", visual.get("placeholder", "frigate"))
	if not variant.is_empty():
		var own := ModelFactory.model_for(data, base, variant)
		if own != base:
			return own
	return ModelFactory.model_for(data, base, style)


## p_altitude < 0 keeps the default ship height. variant: "raider" for raider fleets.
func setup(u: BattleUnit, data: DataRegistry, color: Color, style: String = "", p_altitude: float = -1.0,
		variant: String = "") -> void:
	unit_id = u.id
	display_name = u.name
	team_color = color
	var visual: Dictionary = u.def.get("visual", {})
	_is_ship = "ship" in u.tags or "station" in u.tags
	_spins = "immobile" in u.tags
	var model_id := model_id_for(data, u.def, style, variant)
	squadron = Squadron.size_of(u.def) if _is_ship and not _spins else 1
	_craft_scale = float(visual.get("craft_size", float(visual.get("size", 1.0)) * (1.45 if _is_ship else 1.6)))
	_model = Node3D.new()
	_model.name = "Formation"
	add_child(_model)
	_slots = Squadron.slots(squadron)
	_lags = Squadron.lags(squadron)
	var box := AABB()
	for i in squadron:
		var holder := Node3D.new()
		var body := ModelFactory.build(data, model_id, color, style, squadron > 1)
		body.scale = Vector3.ONE * _craft_scale
		holder.add_child(body)
		holder.position = _slots[i]
		_model.add_child(holder)
		_holders.append(holder)
		_bodies.append(body)
		_phases.append(randf() * TAU)
		_lost.append(false)
		if i == 0:
			box = ModelFactory.bounds(body)
		if squadron > 1:
			# Small craft: no shadows (cheap, and they'd only speckle the board).
			_no_shadows(body)
	_craft_length = maxf(box.size.x, 0.2) * _craft_scale
	var extent := 0.0
	for s in _slots:
		extent = maxf(extent, Vector2(s.x, s.z).length())
	_radius = clampf(extent + _craft_length * 0.55, 0.6, 1.6)
	if _is_ship and not _spins:
		if p_altitude >= 0.0:
			altitude = p_altitude
		_model.position.y = altitude
		for i in squadron:
			var trail := BoardGeometry.engine_trail(color, 1.3 if squadron == 1 else 0.55)
			if squadron > 1:
				trail.amount = 40
			_trails.append(trail)
			add_child(trail)
		if altitude > SHIP_ALTITUDE + 0.1:
			_add_tether(color)
	var top := (box.position.y + box.size.y) * _craft_scale
	if _is_ship:
		label_height = altitude + maxf(top + 0.35, 0.6 if squadron > 1 else 0.75)
	else:
		label_height = 1.6
	_t = randf() * TAU

	# Team marker on the floor: faint disc plus a crisp ring.
	var disc_node := MeshInstance3D.new()
	var disc := CylinderMesh.new()
	disc.top_radius = 0.7
	disc.bottom_radius = 0.7
	disc.height = 0.01
	disc.radial_segments = 32
	disc_node.mesh = disc
	disc_node.material_override = _flat_material(Color(color, 0.035 if BoardGeometry.high_quality() else 0.1))
	disc_node.position.y = 0.012
	add_child(disc_node)
	var ring := MeshInstance3D.new()
	var ring_mesh := TorusMesh.new()
	ring_mesh.inner_radius = 0.66
	ring_mesh.outer_radius = 0.7
	ring_mesh.rings = 32
	ring.mesh = ring_mesh
	ring.material_override = _flat_material(Color(color, 0.5 if BoardGeometry.high_quality() else 0.75))
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
	# Start at full show for the current hull, without losses being animated.
	craft_shown = Squadron.craft_count(squadron, hull, max_hull) if hull > 0 else squadron
	for i in squadron:
		_lost[i] = i >= craft_shown
		_holders[i].visible = not _lost[i]


## Station decks on the high-quality look: a soft team-tinted light over the
## person (they stand out from the dark floor and pick up a team-coloured rim)
## and a glowing team ring at their feet.
func add_deck_light() -> void:
	var lamp := OmniLight3D.new()
	lamp.light_color = team_color.lerp(Color.WHITE, 0.55)
	lamp.light_energy = 0.35
	lamp.omni_range = 2.1
	lamp.omni_attenuation = 1.4
	lamp.light_specular = 0.6
	lamp.light_volumetric_fog_energy = 0.0
	lamp.position = Vector3(-0.35, 1.9, 0.25)
	add_child(lamp)
	for child in get_children():
		var mi := child as MeshInstance3D
		if mi != null and mi.mesh is TorusMesh and mi != _active_ring:
			mi.material_override = _additive_material(team_color * 0.9)
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		elif mi != null and mi.mesh is CylinderMesh:
			mi.material_override = _flat_material(Color(team_color, 0.07))
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


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


## Brings the craft shown in line with the hull: craft beyond
## ceil(n * hull / max_hull) break up (the board plays an explosion at each
## returned world position), and repaired craft rejoin. The last craft stays
## until the unit is destroyed (play_destroyed).
func sync_craft() -> Array[Vector3]:
	var lost: Array[Vector3] = []
	if squadron <= 1:
		return lost
	var target := maxi(1, Squadron.craft_count(squadron, hull, max_hull))
	for i in range(squadron - 1, -1, -1):
		var should_fly := i < target
		if should_fly and _lost[i]:
			_lost[i] = false
			_holders[i].visible = true
			_bodies[i].scale = Vector3.ONE * _craft_scale
			_bodies[i].rotation = Vector3.ZERO
		elif not should_fly and not _lost[i]:
			_lost[i] = true
			lost.append(_holders[i].global_position + Vector3(0, 0.05, 0))
			_break_up(i)
	craft_shown = target
	return lost


func _break_up(i: int) -> void:
	var body := _bodies[i]
	var holder := _holders[i]
	var tw := create_tween().set_parallel()
	tw.tween_property(body, "scale", Vector3.ONE * _craft_scale * 0.05, 0.4).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_IN)
	tw.tween_property(body, "rotation", Vector3(randf_range(-2.0, 2.0), randf_range(-3.0, 3.0), randf_range(-2.0, 2.0)), 0.4)
	tw.tween_property(body, "position:y", -0.25, 0.4)
	tw.chain().tween_callback(func() -> void:
		if _lost[i]:
			holder.visible = false
		body.position = Vector3.ZERO)


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
	else:
		_model.position.y = altitude + _lift
		_fly_formation()
	if is_active:
		_active_ring.rotation.y += delta * 0.8


## Each craft takes the formation's place from a moment ago (its lag) plus its
## slot, then adds its own bob, drift and roll.
func _fly_formation() -> void:
	if not _model.is_inside_tree():
		return
	var now := _model.global_transform
	if not _history.is_empty() and (_history[_history.size() - 1][1] as Transform3D).origin.distance_to(now.origin) > 2.5:
		_history.clear()  # placed, not flown: no streaks across the board
	_history.append([_t, now, _bank])
	while _history.size() > 2 and float(_history[1][0]) < _t - HISTORY:
		_history.pop_front()
	var inv := now.affine_inverse()
	for i in squadron:
		var holder := _holders[i]
		if not holder.visible:
			continue
		var sample := _sample(_t - _lags[i])
		var past: Transform3D = sample[0]
		var bank: float = sample[1]
		var ph := _phases[i]
		var bob := Vector3(sin(_t * 0.9 + ph) * 0.018, sin(_t * 1.6 + ph) * 0.035, cos(_t * 0.7 + ph * 1.3) * 0.016)
		if squadron == 1:
			bob = Vector3(0, bob.y, 0)
		var xf := inv * past * Transform3D(Basis.IDENTITY, _slots[i] + bob)
		var roll := bank + sin(_t * 1.1 + ph) * 0.03
		holder.transform = Transform3D(xf.basis * Basis(Vector3.RIGHT, roll), xf.origin)
		if i < _trails.size():
			_trails[i].global_position = holder.global_position - holder.global_basis.x * _craft_length * 0.45


## The formation's transform and bank `at` seconds (interpolated).
func _sample(at: float) -> Array:
	var n := _history.size()
	if n == 0:
		return [_model.global_transform, _bank]
	for k in range(n - 1, -1, -1):
		var s: Array = _history[k]
		if float(s[0]) <= at:
			if k == n - 1:
				return [s[1], s[2]]
			var nxt: Array = _history[k + 1]
			var span := float(nxt[0]) - float(s[0])
			var f := 0.0 if span <= 0.0 else clampf((at - float(s[0])) / span, 0.0, 1.0)
			return [(s[1] as Transform3D).interpolate_with(nxt[1], f), lerpf(float(s[2]), float(nxt[2]), f)]
	return [_history[0][1], _history[0][2]]


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
	set_engines(true)
	await tw.finished
	set_engines(false)


## Attack runs and broadsides steer the ship directly: roll (radians) and
## extra height on top of its cruising altitude.
func set_maneuver(roll: float, lift: float) -> void:
	_bank = roll
	_lift = lift


func set_engines(on: bool) -> void:
	for i in _trails.size():
		_trails[i].emitting = on and not _lost[i]


## World positions of the craft still flying (the lead first).
func craft_points() -> Array[Vector3]:
	var out: Array[Vector3] = []
	for i in squadron:
		if not _lost[i] and _holders[i].is_inside_tree():
			out.append(_holders[i].global_position + Vector3(0, 0.04, 0))
	if out.is_empty():
		out.append(aim_point())
	return out


## The nose of each craft still flying, `ahead` model lengths forward.
func craft_noses(ahead: float = 0.5) -> Array[Vector3]:
	var out: Array[Vector3] = []
	for i in squadron:
		if not _lost[i] and _holders[i].is_inside_tree():
			out.append(_holders[i].global_position + _holders[i].global_basis.x.normalized() * _craft_length * ahead
					+ Vector3(0, 0.04, 0))
	if out.is_empty():
		out.append(nose_point())
	return out


## Model-space nose of the (lead) ship in world space (where forward guns fire from).
func nose_point(ahead: float = 0.35) -> Vector3:
	var heading := -rotation.y
	var origin := aim_point()
	if squadron > 1:
		var pts := craft_points()
		origin = pts[0]
	return origin + Vector3(cos(heading), 0, sin(heading)) * ahead * _craft_scale


## Length of one craft (world units).
func craft_length() -> float:
	return _craft_length


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


## A jolt: one craft of a squadron (the whole ship for singles) shakes.
func play_hit() -> void:
	var flying: Array[int] = []
	for i in squadron:
		if not _lost[i]:
			flying.append(i)
	if flying.is_empty():
		return
	var body := _bodies[flying[randi() % flying.size()]]
	var rest := Vector3.ONE * _craft_scale
	var tw := create_tween()
	tw.tween_property(body, "scale", rest * 1.1, 0.05)
	tw.parallel().tween_property(body, "rotation:x", randf_range(-0.35, 0.35), 0.05)
	tw.tween_property(body, "scale", rest, 0.18)
	tw.parallel().tween_property(body, "rotation:x", 0.0, 0.25)


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


## Shield bubble flash around the whole unit, brightest on the side facing the attacker.
func play_shield_hit(from_world: Vector3) -> void:
	var bubble := MeshInstance3D.new()
	var sphere := SphereMesh.new()
	sphere.radius = _radius
	sphere.height = _radius * (1.33 if squadron == 1 else 0.9)
	bubble.mesh = sphere
	var mat := _additive_material(Color(Palette.SHIELDS, 1.0) * 0.6)
	bubble.material_override = mat
	bubble.position.y = _model.position.y + 0.1
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
	flare.position = Vector3(0, bubble.position.y, 0) + (toward.normalized() * _radius * 0.96).rotated(Vector3.UP, -rotation.y)
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
	for trail in _trails:
		trail.emitting = false
	await tw.finished
	visible = false


## World position shots should aim at / come from (the formation's centre).
func aim_point() -> Vector3:
	return global_position + Vector3(0, _model.position.y + (0.08 if _is_ship else 0.85), 0)


## Where an incoming shot lands: one of the craft still flying.
func hit_point() -> Vector3:
	if squadron <= 1:
		return aim_point()
	var pts := craft_points()
	return pts[randi() % pts.size()]


## Radius of the unit (formation or capital ship), for effects.
func radius() -> float:
	return _radius


static func _no_shadows(node: Node) -> void:
	for child in node.get_children():
		if child is GeometryInstance3D:
			(child as GeometryInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_no_shadows(child)


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
