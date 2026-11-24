class_name SolarSystem3D
extends Node3D
## The set dressing of a system-scale map (GalaxyBoard3D on a campaign with "scale": "system"):
## the sun blazing in the centre cell (high quality: the churning star_surface shader with a
## billboard corona and a shadow-casting light; classic: an emissive core with soft halos), faint
## orbit circles through the bodies (and round the giants for their moons), a dusty band along
## the asteroid belt, and the dormant jump gates at the edge of the system. The bodies themselves
## are Body3D views owned by the board.

const STAR_SHADER := preload("res://src/presentation/shaders/star_surface.gdshader")
const CORONA_SHADER := preload("res://src/presentation/shaders/star_corona.gdshader")
## The sun's radius and height over the board (world units: a hex is ~1.7 wide).
const SUN_RADIUS := 0.95
const SUN_LIFT := 0.55
const ORBIT_COLOR := Color(0.62, 0.78, 1.0, 0.13)
const GATE_SIZE := 2.4
## Orbits are drawn just over the fog of unexplored space: the system's layout is charted.
const ORBIT_Y := GalaxyBoard3D.FOG_HEIGHT + 0.015

var star_world := Vector3.ZERO
var star_color := Color("#ffd88a")
## Dormant jump gates (for labels): [Node3D].
var gates: Array[Node3D] = []
var gate_cells: Array[Vector2i] = []


func build(board: GalaxyBoard3D) -> void:
	var engine := board.engine
	var grid := engine.state.grid
	var system: Dictionary = engine.campaign.get("system", {})
	var star_cell := Vector2i.ZERO
	if system.has("at"):
		star_cell = grid.cell_from_layout(Vector2i(int(system["at"][0]), int(system["at"][1])))
	else:
		for c in grid.cells():
			if grid.terrain_at(c) == "star":
				star_cell = c
	var star_def: Dictionary = engine.data.star_types.get(str(system.get("star", "yellow")), {})
	star_color = Color(star_def.get("color", "#ffd88a"))
	var size := float(star_def.get("size", 1.0))
	star_world = board.world(star_cell) + Vector3(0, SUN_LIFT, 0)
	var hq := BoardGeometry.high_quality()
	_sun(SUN_RADIUS * clampf(size, 0.8, 1.2), hq, engine.state.seed_value)
	_orbits(board, star_cell, system)
	for c in grid.cells():
		if grid.terrain_at(c) == "jump_point":
			_gate(board.world(c))
			gate_cells.append(c)


# --- The sun ------------------------------------------------------------------

func _sun(r: float, hq: bool, seed_value: int) -> void:
	var root := Node3D.new()
	root.position = star_world
	add_child(root)
	var core := MeshInstance3D.new()
	var sphere := SphereMesh.new()
	sphere.radius = r
	sphere.height = r * 2.0
	sphere.radial_segments = 64
	sphere.rings = 32
	core.mesh = sphere
	core.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(core)
	var light := OmniLight3D.new()
	light.light_color = star_color.lerp(Color.WHITE, 0.45)
	light.omni_range = 46.0
	if hq:
		var sm := ShaderMaterial.new()
		sm.shader = STAR_SHADER
		sm.set_shader_parameter("star_color", star_color.lerp(Color(1.0, 0.62, 0.25), 0.3))
		sm.set_shader_parameter("energy", 3.2)
		sm.set_shader_parameter("seed", float(absi(seed_value) % 97) * 0.1)
		core.material_override = sm
		for k in 2:
			var corona := MeshInstance3D.new()
			var quad := QuadMesh.new()
			quad.size = Vector2.ONE * r * (5.6 if k == 0 else 12.0)
			corona.mesh = quad
			var cm := ShaderMaterial.new()
			cm.shader = CORONA_SHADER
			cm.set_shader_parameter("corona_color", star_color.lightened(0.2) if k == 0 else star_color)
			cm.set_shader_parameter("intensity", 1.15 if k == 0 else 0.4)
			cm.set_shader_parameter("core", 1.0 / (2.6 if k == 0 else 5.5))
			corona.material_override = cm
			corona.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			root.add_child(corona)
		# The sun lights every world (a real day and night side) and the fleets, with soft shadows.
		light.light_energy = 5.5
		light.omni_attenuation = 0.55
		light.shadow_enabled = true
		light.shadow_blur = 1.5
		light.light_size = 0.6
	else:
		var m := StandardMaterial3D.new()
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m.albedo_color = star_color.lightened(0.45) * 1.7
		core.material_override = m
		for k in 3:
			var halo := MeshInstance3D.new()
			var hs := SphereMesh.new()
			hs.radius = r * (1.25 + k * 0.7)
			hs.height = hs.radius * 2.0
			hs.radial_segments = 32
			hs.rings = 16
			halo.mesh = hs
			halo.material_override = BoardGeometry.additive_material(star_color * (0.32 - k * 0.09))
			halo.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			root.add_child(halo)
		light.light_energy = 2.2
		light.omni_attenuation = 0.45
	root.add_child(light)
	var spin := Tumbler.new()
	spin.spin = Vector3(0, 0.05, 0)
	core.add_child(spin)


# --- Orbits -------------------------------------------------------------------

## A faint circle through every planet (several bodies on one orbit share it), one round each
## giant through its moons, and a dusty band along the belt.
func _orbits(board: GalaxyBoard3D, star_cell: Vector2i, system: Dictionary) -> void:
	var engine := board.engine
	var grid := engine.state.grid
	var center := board.world(star_cell)
	var moons := {}  # planet id -> parent planet id
	for p_def: Dictionary in engine.campaign.get("planets", []):
		if p_def.has("moon_of"):
			moons[p_def["id"]] = p_def["moon_of"]
	var radii: Array[float] = []
	var buf := BoardGeometry.buffer()
	for p: Planet in engine.state.planets.values():
		if p.bodies.is_empty() or p.bodies[0]["type"] == "asteroid_belt":
			continue
		var at := board.body_position(p)
		if moons.has(p.id):
			var parent: Planet = engine.state.planets.get(moons[p.id])
			if parent != null:
				var pc := board.body_position(parent)
				_circle(buf, Vector3(pc.x, ORBIT_Y, pc.z), Vector2(at.x - pc.x, at.z - pc.z).length(), 0.018, Color(ORBIT_COLOR, 0.09))
			continue
		var r := Vector2(at.x - center.x, at.z - center.z).length()
		var close := false
		for o in radii:
			close = close or absf(o - r) < 0.25
		if close:
			continue
		radii.append(r)
		_circle(buf, Vector3(center.x, ORBIT_Y, center.z), r, 0.022, ORBIT_COLOR)
	var belt: Dictionary = system.get("belt", {})
	if belt.has("radius"):
		var r := float(belt["radius"]) * Hex.SQRT3
		var from := float(belt["from"])
		var to := float(belt["to"])
		var steps := maxi(12, int((to - from) * r * 2.0))
		for i in steps:
			var a0 := lerpf(from, to, float(i) / steps)
			var a1 := lerpf(from, to, float(i + 1) / steps)
			# Fade out towards the ends of the arc.
			var fade := sin(PI * (float(i) + 0.5) / steps)
			BoardGeometry.ribbon(buf, center + Vector3(cos(a0), 0, sin(a0)) * r + Vector3(0, ORBIT_Y, 0),
					center + Vector3(cos(a1), 0, sin(a1)) * r + Vector3(0, ORBIT_Y, 0), 1.25, Color(0.75, 0.62, 0.48, 0.05 * fade))
	var mat := BoardGeometry.overlay_material()
	mat.render_priority = 1  # over the cloud cover of uncharted space (high quality)
	BoardGeometry.mesh_node(self, mat).mesh = BoardGeometry.commit(buf)


func _circle(buf: Dictionary, center: Vector3, r: float, width: float, color: Color) -> void:
	var steps := maxi(24, int(r * 10.0))
	for i in steps:
		var a0 := TAU * i / steps
		var a1 := TAU * (i + 1) / steps
		BoardGeometry.ribbon(buf, center + Vector3(cos(a0), 0, sin(a0)) * r, center + Vector3(cos(a1), 0, sin(a1)) * r, width, color)


# --- Jump points --------------------------------------------------------------

## A dormant gate standing over its cell, facing the sun.
func _gate(at: Vector3) -> void:
	var gate := JumpGate3D.build(true, GATE_SIZE)
	add_child(gate)
	var pos := at + Vector3(0, 0.62, 0)
	var facing := Vector3(star_world.x, pos.y, star_world.z)
	gate.look_at_from_position(pos, facing, Vector3.UP)
	gates.append(gate)
	# A faint ring on the board marks the jump point.
	var buf := BoardGeometry.buffer()
	_circle(buf, Vector3(at.x, 0.02, at.z), 0.72, 0.03, Color(0.35, 0.7, 0.9, 0.22))
	BoardGeometry.mesh_node(self, BoardGeometry.overlay_material()).mesh = BoardGeometry.commit(buf)
