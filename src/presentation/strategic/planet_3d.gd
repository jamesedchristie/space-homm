class_name Planet3D
extends Node3D
## A star system on the 3D galaxy map: a glowing star with its bodies on
## tilted orbits (procedural planet spheres, an asteroid belt of tumbling
## rocks), and the owner's ring on the board. Developed bodies carry a small
## light in the owner's color. The name is drawn by GalaxyOverlay3D.

const SURFACE_SHADER := preload("res://src/presentation/shaders/planet_3d.gdshader")
const ATMOSPHERE_SHADER := preload("res://src/presentation/shaders/atmosphere.gdshader")
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
			_add_belt(radius, h + i)
			_markers.append(null)
			continue
		var node := _add_body(b, data, h + i * 13)
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
	_glow.albedo_color = Color(owner_color, 0.1) if owned else Color(0, 0, 0, 0)
	for i in mini(_markers.size(), planet.bodies.size()):
		if _markers[i] == null:
			continue
		var developed: bool = not planet.bodies[i]["buildings"].is_empty()
		(_markers[i].material_override as StandardMaterial3D).albedo_color = Color(owner_color, 0.9) if developed and owned else Color(1, 1, 1, 0)


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
	for k in 2:
		var halo := MeshInstance3D.new()
		var hs := SphereMesh.new()
		hs.radius = r * (1.8 + k * 1.4)
		hs.height = hs.radius * 2.0
		halo.mesh = hs
		halo.material_override = BoardGeometry.additive_material(color * (0.22 if k == 0 else 0.08))
		halo.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_system.add_child(halo)
	var light := OmniLight3D.new()
	light.light_color = color
	light.light_energy = 0.6
	light.omni_range = ORBIT_MAX + 0.4
	_system.add_child(light)


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
	return 0.05 + 0.08 * float(data.body_types.get(b["type"], {}).get("size", 0.6))


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


func _add_belt(radius: float, seed_value: int) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var belt := Node3D.new()
	_system.add_child(belt)
	for k in 22:
		var a := TAU * k / 22.0 + rng.randf_range(-0.1, 0.1)
		var rock := ModelFactory.build_rock(rng.randi(), rng.randf_range(0.012, 0.026))
		rock.position = Vector3(cos(a), rng.randf_range(-0.02, 0.02), sin(a)) * radius + Vector3(rng.randf_range(-0.03, 0.03), 0, rng.randf_range(-0.03, 0.03))
		belt.add_child(rock)
	_orbiters.append({"node": belt, "radius": 0.0, "speed": 0.0, "angle": 0.0})
