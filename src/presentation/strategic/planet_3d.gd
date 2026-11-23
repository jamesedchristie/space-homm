class_name Planet3D
extends Node3D
## A star system on the 3D galaxy map: a glowing star with its bodies on
## tilted orbits (procedural planet spheres, an asteroid belt of tumbling
## rocks), and the owner's ring on the board. Developed bodies carry a small
## light in the owner's color. The name is drawn by GalaxyOverlay3D.

const SURFACE_SHADER := preload("res://src/presentation/shaders/planet_3d.gdshader")
const ATMOSPHERE_SHADER := preload("res://src/presentation/shaders/atmosphere.gdshader")
const STAR_SHADER := preload("res://src/presentation/shaders/star_surface.gdshader")
const CORONA_SHADER := preload("res://src/presentation/shaders/star_corona.gdshader")
const ORBIT_MIN := 0.22
const ORBIT_MAX := 0.58
const TILT := 0.22

var planet_id := ""
var display_name := ""
var owner_color := Palette.NEUTRAL
var owned := false
## Height of the name label above the board.
var label_height := 0.85

var _data: DataRegistry
var _system: Node3D
var _orbiters: Array[Dictionary] = []  # {"node", "radius", "speed", "angle"}
var _owner_ring: StandardMaterial3D
var _glow: StandardMaterial3D
var _markers: Array[MeshInstance3D] = []
var _body_ids: Array[String] = []
var _floor: Array[Node3D] = []
## Per body (same order as the planet's bodies): its sphere, or the belt node.
var _body_nodes: Array[Node3D] = []
var _body_radii: Array[float] = []
var _surface_materials: Array[ShaderMaterial] = []
var _structures_key := ""
## The star's meshes (core, corona or halos): scaled by set_star_scale().
var _star_nodes: Array[Node3D] = []


func setup(planet: Planet, data: DataRegistry) -> void:
	planet_id = planet.id
	display_name = planet.name
	_data = data
	_system = Node3D.new()
	_system.position.y = 0.32
	_system.rotation = Vector3(TILT, 0, 0)
	add_child(_system)
	var star_def: Dictionary = data.star_types.get(planet.star, {})
	var star_color := Color(star_def.get("color", "#ffd88a"))
	var star_r := 0.15 * float(star_def.get("size", 1.0))
	_add_star(star_color, star_r)

	var h := absi(hash(planet.id))
	var n := planet.bodies.size()
	for i in n:
		var b: Dictionary = planet.bodies[i]
		_body_ids.append(b["id"])
		var radius := lerpf(ORBIT_MIN, ORBIT_MAX, float(i) / maxf(1.0, float(n - 1))) if n > 1 else 0.4
		_add_orbit_line(radius)
		var angle := float((h >> (i * 3)) % 628) / 100.0
		var speed := 0.35 / (radius * 4.0)
		if b["type"] == "asteroid_belt":
			_body_nodes.append(_add_belt(radius, h + i))
			_body_radii.append(0.03)
			_surface_materials.append(null)
			_markers.append(null)
			continue
		var node := _add_body(b, data, h + i * 13)
		_body_nodes.append(node)
		_body_radii.append(_body_radius(b, data))
		_surface_materials.append(node.material_override as ShaderMaterial)
		_orbiters.append({"node": node, "radius": radius, "speed": speed, "angle": angle})
		var marker := MeshInstance3D.new()
		var torus := TorusMesh.new()
		var br := _body_radius(b, data)
		torus.inner_radius = br + 0.02
		torus.outer_radius = br + 0.035
		torus.rings = 20
		marker.mesh = torus
		marker.material_override = BoardGeometry.flat_material(Color(1, 1, 1, 0))
		marker.rotation.x = -TILT
		node.add_child(marker)
		_markers.append(marker)

	# Owner ring and glow on the board under the system.
	var ring := MeshInstance3D.new()
	var t := TorusMesh.new()
	t.inner_radius = ORBIT_MAX + 0.08
	t.outer_radius = ORBIT_MAX + 0.11
	t.rings = 48
	ring.mesh = t
	_owner_ring = BoardGeometry.flat_material(Palette.NEUTRAL)
	ring.material_override = _owner_ring
	ring.position.y = 0.03
	ring.scale = Vector3(1, 0.1, 1)
	add_child(ring)
	_floor.append(ring)
	var glow := MeshInstance3D.new()
	var disc := CylinderMesh.new()
	disc.top_radius = ORBIT_MAX + 0.1
	disc.bottom_radius = ORBIT_MAX + 0.1
	disc.height = 0.005
	disc.radial_segments = 32
	glow.mesh = disc
	_glow = BoardGeometry.flat_material(Color(0, 0, 0, 0))
	glow.material_override = _glow
	glow.position.y = 0.025
	add_child(glow)
	_floor.append(glow)


## The board markings (owner ring and glow): off in the close-up system view.
func show_floor(on: bool) -> void:
	for n in _floor:
		n.visible = on


func refresh(planet: Planet, state: GalaxyState) -> void:
	owned = not planet.owner.is_empty()
	owner_color = Palette.team_color(state.faction(planet.owner)["team"]) if owned else Palette.NEUTRAL
	_owner_ring.albedo_color = Color(owner_color, 0.85) if owned else Color(owner_color, 0.22)
	_glow.albedo_color = Color(owner_color, 0.04 if BoardGeometry.high_quality() else 0.1) if owned else Color(0, 0, 0, 0)
	for i in mini(_markers.size(), planet.bodies.size()):
		if _markers[i] == null:
			continue
		var developed: bool = not planet.bodies[i]["buildings"].is_empty()
		(_markers[i].material_override as StandardMaterial3D).albedo_color = Color(owner_color, 0.16) if developed and owned else Color(1, 1, 1, 0)
	_refresh_structures(planet)


## What's built shows in orbit: lit cities on colonies, a drydock for a
## shipyard, turret satellites for defense platforms, dishes for research
## stations, rigs for mining, ring stations for refineries and trade hubs.
## Rebuilt only when buildings or the owner change.
func _refresh_structures(planet: Planet) -> void:
	var parts := PackedStringArray([planet.owner])
	for b: Dictionary in planet.bodies:
		parts.append(",".join(PackedStringArray(b["buildings"])))
	var key := "|".join(parts)
	if key == _structures_key:
		return
	_structures_key = key
	for i in mini(_body_nodes.size(), planet.bodies.size()):
		var node := _body_nodes[i]
		for child in node.get_children():
			if child.is_in_group("structure"):
				child.queue_free()
		var b: Dictionary = planet.bodies[i]
		var buildings: Array = b["buildings"]
		if _surface_materials[i] != null:
			_surface_materials[i].set_shader_parameter("city_lights", 1.0 if "colony" in buildings else 0.0)
		var r := _body_radii[i]
		var slot := 0
		for building_id: String in buildings:
			var s := _structure(building_id, r, owner_color, slot)
			if s == null:
				continue
			s.add_to_group("structure")
			if b["type"] == "asteroid_belt":
				# On the belt itself: out on the ring, a little apart from each other.
				var ring_r: float = 0.0
				for o in _orbiters:
					if o["node"] == node:
						ring_r = float(o.get("ring", 0.0))
				var a := 0.9 + slot * 1.3
				s.position = Vector3(cos(a), 0.0, sin(a)) * ring_r
			node.add_child(s)
			slot += 1


func _structure(building_id: String, r: float, color: Color, slot: int) -> Node3D:
	var root := Node3D.new()
	var hull := ModelFactory.material("hull")
	var dark := ModelFactory.material("dark")
	var accent := ModelFactory.material("accent", color)
	var scale := maxf(r, 0.05)
	var angle := 0.6 + slot * 2.1
	var out := Vector3(cos(angle), 0.0, sin(angle))
	match building_id:
		"colony":
			return null  # the city lights show it
		"shipyard":
			# An open drydock frame beside the planet.
			root.position = out * (r + scale * 0.9) + Vector3(0, scale * 0.3, 0)
			root.rotation.y = -angle
			for side in [-1.0, 1.0]:
				_box(root, Vector3(0, 0, side * scale * 0.22), Vector3(scale * 0.9, scale * 0.08, scale * 0.06), hull)
			for k in 3:
				_box(root, Vector3((k - 1) * scale * 0.4, 0, 0), Vector3(scale * 0.06, scale * 0.06, scale * 0.5), dark)
			_box(root, Vector3(0, scale * 0.06, 0), Vector3(scale * 0.5, scale * 0.04, scale * 0.04), accent)
		"defense_platform":
			# Turret satellites on short orbits, above and below the planet's plane.
			for k in 2:
				var sat := Node3D.new()
				var a := angle + k * PI
				sat.position = Vector3(cos(a), (0.4 if k == 0 else -0.4) * scale, sin(a)) * (r + scale * 0.55)
				_box(sat, Vector3.ZERO, Vector3.ONE * scale * 0.16, dark)
				_box(sat, Vector3(scale * 0.12, 0, 0), Vector3(scale * 0.2, scale * 0.03, scale * 0.03), hull)
				_glow_dot(sat, Vector3(0, scale * 0.1, 0), scale * 0.04, Color(1.0, 0.3, 0.25))
				root.add_child(sat)
		"research_station":
			# A sensor dish on a mast.
			root.position = out * (r + scale * 0.55)
			var dish := MeshInstance3D.new()
			var cone := CylinderMesh.new()
			cone.top_radius = scale * 0.22
			cone.bottom_radius = scale * 0.02
			cone.height = scale * 0.12
			cone.radial_segments = 12
			dish.mesh = cone
			dish.material_override = hull
			dish.rotation.z = -0.6
			root.add_child(dish)
			_box(root, Vector3(0, -scale * 0.12, 0), Vector3(scale * 0.05, scale * 0.2, scale * 0.05), dark)
			_glow_dot(root, Vector3(0, scale * 0.08, 0), scale * 0.04, Color(0.5, 0.85, 1.0))
		"mining_base":
			# A rig on the surface with a work light.
			root.position = Vector3(0, r * 0.92, 0) if r > 0.04 else Vector3.ZERO
			_box(root, Vector3.ZERO, Vector3(scale * 0.22, scale * 0.12, scale * 0.16), dark)
			_box(root, Vector3(0, scale * 0.14, 0), Vector3(scale * 0.04, scale * 0.22, scale * 0.04), hull)
			_glow_dot(root, Vector3(0, scale * 0.26, 0), scale * 0.04, Color(1.0, 0.75, 0.3))
		"gas_refinery", "trade_hub":
			# A ring station: a wheel round a hub, spinning slowly.
			root.position = out * (r + scale * 0.75)
			var wheel := MeshInstance3D.new()
			var t := TorusMesh.new()
			t.inner_radius = scale * 0.16
			t.outer_radius = scale * 0.22
			t.rings = 16
			t.ring_segments = 6
			wheel.mesh = t
			wheel.material_override = hull if building_id == "trade_hub" else dark
			root.add_child(wheel)
			_box(root, Vector3.ZERO, Vector3(scale * 0.08, scale * 0.08, scale * 0.08), accent)
			var spin := Tumbler.new()
			spin.spin = Vector3(0, 0.8, 0)
			root.add_child(spin)
		_:
			# Anything else: a small station block in the owner's colour.
			root.position = out * (r + scale * 0.6)
			_box(root, Vector3.ZERO, Vector3.ONE * scale * 0.14, hull)
			_box(root, Vector3(0, scale * 0.09, 0), Vector3(scale * 0.18, scale * 0.03, scale * 0.03), accent)
	return root


static func _box(parent: Node3D, at: Vector3, size: Vector3, mat: Material) -> void:
	var mi := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = size
	mi.mesh = box
	mi.material_override = mat
	mi.position = at
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mi)


static func _glow_dot(parent: Node3D, at: Vector3, radius: float, color: Color) -> void:
	var mi := MeshInstance3D.new()
	var s := SphereMesh.new()
	s.radius = radius
	s.height = radius * 2.0
	s.radial_segments = 6
	s.rings = 3
	mi.mesh = s
	mi.material_override = BoardGeometry.additive_material(color)
	mi.position = at
	parent.add_child(mi)


func _process(delta: float) -> void:
	for o in _orbiters:
		var node: Node3D = o["node"]
		if float(o["radius"]) == 0.0:
			node.rotate_y(delta * 0.05)  # asteroid belt
			continue
		o["angle"] = float(o["angle"]) + delta * float(o["speed"])
		node.position = Vector3(cos(o["angle"]), 0, sin(o["angle"])) * float(o["radius"])
		node.rotate_y(delta * 0.4)


func _add_star(color: Color, r: float) -> void:
	var star := MeshInstance3D.new()
	var sphere := SphereMesh.new()
	sphere.radius = r
	sphere.height = r * 2.0
	star.mesh = sphere
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = color.lightened(0.35) * 1.6
	star.material_override = m
	star.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_system.add_child(star)
	_star_nodes.append(star)
	var hq := BoardGeometry.high_quality()
	if hq:
		# A churning surface with a darker limb, in HDR so the glow gives it a corona.
		var sm := ShaderMaterial.new()
		sm.shader = STAR_SHADER
		sm.set_shader_parameter("star_color", color)
		sm.set_shader_parameter("energy", 2.0)
		sm.set_shader_parameter("seed", float(absi(hash(planet_id)) % 97) * 0.1)
		star.material_override = sm
		sphere.radial_segments = 48
		sphere.rings = 24
		var corona := MeshInstance3D.new()
		var quad := QuadMesh.new()
		quad.size = Vector2.ONE * r * 4.6
		corona.mesh = quad
		var cm := ShaderMaterial.new()
		cm.shader = CORONA_SHADER
		cm.set_shader_parameter("corona_color", color.lightened(0.2))
		cm.set_shader_parameter("intensity", 0.85)
		cm.set_shader_parameter("core", 1.0 / 2.3)
		corona.material_override = cm
		corona.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_system.add_child(corona)
		_star_nodes.append(corona)
	for k in (0 if hq else 2):
		var halo := MeshInstance3D.new()
		var hs := SphereMesh.new()
		hs.radius = r * (1.45 + k * 0.9)
		hs.height = hs.radius * 2.0
		halo.mesh = hs
		halo.material_override = BoardGeometry.additive_material(color * (0.2 if k == 0 else 0.06))
		halo.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_system.add_child(halo)
		_star_nodes.append(halo)
	var light := OmniLight3D.new()
	light.light_color = color
	light.light_energy = 0.6
	light.omni_range = ORBIT_MAX + 0.4
	if hq:
		# The star lights its worlds and the fleets parked around it.
		light.light_energy = 1.6
		light.omni_range = ORBIT_MAX + 1.4
		light.omni_attenuation = 1.6
	_system.add_child(light)


## Shrinks (or grows) the star without touching the orbits (the system view
## keeps the sun small so the worlds get the space).
func set_star_scale(f: float) -> void:
	for n in _star_nodes:
		n.scale = Vector3.ONE * f


func _add_orbit_line(radius: float) -> void:
	var line := MeshInstance3D.new()
	var t := TorusMesh.new()
	t.inner_radius = radius - 0.003
	t.outer_radius = radius + 0.003
	t.rings = 64
	t.ring_segments = 3
	line.mesh = t
	line.material_override = BoardGeometry.flat_material(Color(0.6, 0.75, 1.0, 0.12))
	line.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_system.add_child(line)


static func _body_radius(b: Dictionary, data: DataRegistry) -> float:
	# Worlds are small next to their star (stylised, but no longer star-sized).
	return 0.028 + 0.036 * float(data.body_types.get(b["type"], {}).get("size", 0.6))


func _add_body(b: Dictionary, data: DataRegistry, seed_value: int) -> Node3D:
	var def: Dictionary = data.body_types.get(b["type"], {})
	var surface: Dictionary = def.get("surface", {})
	var r := _body_radius(b, data)
	var body := MeshInstance3D.new()
	var sphere := SphereMesh.new()
	sphere.radius = r
	sphere.height = r * 2.0
	sphere.radial_segments = 48
	sphere.rings = 24
	body.mesh = sphere
	var mat := ShaderMaterial.new()
	mat.shader = SURFACE_SHADER
	mat.set_shader_parameter("base_color", Color(surface.get("base", "#888888")))
	mat.set_shader_parameter("accent_color", Color(surface.get("accent", "#bbbbbb")))
	mat.set_shader_parameter("atmosphere_color", Color(surface.get("atmosphere", "#88aaff")))
	mat.set_shader_parameter("bands", float(surface.get("bands", 0.0)))
	mat.set_shader_parameter("ice_caps", float(surface.get("ice_caps", 0.0)))
	mat.set_shader_parameter("seed", float(absi(seed_value) % 1000) / 37.0)
	body.material_override = mat
	_system.add_child(body)
	if b["type"] == "gas_giant":
		var rings := MeshInstance3D.new()
		var t := TorusMesh.new()
		t.inner_radius = r * 1.35
		t.outer_radius = r * 1.75
		t.rings = 32
		rings.mesh = t
		rings.material_override = BoardGeometry.flat_material(Color(Color(surface.get("accent", "#ccbbaa")), 0.45))
		rings.scale = Vector3(1, 0.05, 1)
		rings.rotation.z = 0.35
		body.add_child(rings)
	return body


func _add_belt(radius: float, seed_value: int) -> Node3D:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var belt := Node3D.new()
	_system.add_child(belt)
	for k in 22:
		var a := TAU * k / 22.0 + rng.randf_range(-0.1, 0.1)
		var rock := ModelFactory.build_rock(rng.randi(), rng.randf_range(0.012, 0.026))
		rock.position = Vector3(cos(a), rng.randf_range(-0.02, 0.02), sin(a)) * radius + Vector3(rng.randf_range(-0.03, 0.03), 0, rng.randf_range(-0.03, 0.03))
		belt.add_child(rock)
	_orbiters.append({"node": belt, "radius": 0.0, "speed": 0.0, "angle": 0.0, "ring": radius})
	return belt
