class_name SystemScenery3D
extends RefCounted
## The 3D set of a battle fought inside a star system (maps from
## SystemBattleMap): each body is a procedural planet sphere (the galaxy map's
## planet shader, body type colours, atmosphere, city lights on colonies, gas
## giant rings) sunk a little into the board plane so ships fly over and round
## it; the star is a big glowing sphere beyond the far edge and lights the
## scene from its direction.

const SURFACE_SHADER := preload("res://src/presentation/shaders/planet_3d.gdshader")
const ATMOSPHERE_SHADER := preload("res://src/presentation/shaders/atmosphere.gdshader")
## How far a planet sphere sinks below the plane (fraction of its radius).
const SINK := 0.3
## Height above the plane the star's light comes from (as a share of the horizontal run).
const LIGHT_ELEVATION := 0.5


## world_of: Callable(cell: Vector2i) -> Vector3 (ground position of a cell).
## lo/hi: world-space corners (XZ) of the board.
static func build(parent: Node3D, scenery: Dictionary, data: DataRegistry, grid: TacticalGrid, world_of: Callable,
		lo: Vector3, hi: Vector3, rng_seed: int) -> void:
	var star: Dictionary = scenery.get("star", {})
	var dir2 := Vector2(0, -1)
	if star.has("dir"):
		dir2 = Vector2(float(star["dir"][0]), float(star["dir"][1])).normalized()
	var to_star := Vector3(dir2.x, LIGHT_ELEVATION, dir2.y).normalized()
	var sun := _sun_light(parent)
	var star_def: Dictionary = data.star_types.get(star.get("type", "yellow"), {})
	var star_color := Color(star_def.get("color", "#ffd88a"))
	if sun != null:
		sun.basis = Basis.looking_at(-to_star, Vector3.UP)
		sun.light_color = Color(1, 1, 1).lerp(star_color, 0.55)
		sun.light_energy = 1.5

	for body: Dictionary in scenery.get("bodies", []):
		if body.get("kind", "planet") != "planet":
			continue  # belts are terrain cells with floating rocks
		var cells: Array = body["cells"]
		var center := Vector3.ZERO
		for p: Array in cells:
			center += world_of.call(grid.cell_from_layout(Vector2i(int(p[0]), int(p[1]))))
		center /= float(cells.size())
		_planet(parent, body, data.body_types.get(body["type"], {}), center, to_star, rng_seed)

	_star(parent, star_color, float(star_def.get("size", 1.0)), lo, hi, dir2)


static func _sun_light(parent: Node3D) -> DirectionalLight3D:
	for child in parent.get_children():
		if child is DirectionalLight3D:
			return child
	return null


static func _planet(parent: Node3D, body: Dictionary, def: Dictionary, center: Vector3, to_star: Vector3, rng_seed: int) -> void:
	var surface: Dictionary = def.get("surface", {})
	var r := float(body.get("radius", 1.0))
	if body["type"] == "gas_giant":
		r *= 0.92
	var root := Node3D.new()
	root.position = center + Vector3(0, -r * SINK, 0)
	root.rotation.z = 0.25
	parent.add_child(root)

	var sphere_node := MeshInstance3D.new()
	var sphere := SphereMesh.new()
	sphere.radius = r
	sphere.height = r * 2.0
	sphere.radial_segments = 64
	sphere.rings = 32
	sphere_node.mesh = sphere
	var mat := ShaderMaterial.new()
	mat.shader = SURFACE_SHADER
	mat.set_shader_parameter("base_color", Color(surface.get("base", "#888888")))
	mat.set_shader_parameter("accent_color", Color(surface.get("accent", "#bbbbbb")))
	mat.set_shader_parameter("atmosphere_color", Color(surface.get("atmosphere", "#88aaff")))
	mat.set_shader_parameter("bands", float(surface.get("bands", 0.0)))
	mat.set_shader_parameter("ice_caps", float(surface.get("ice_caps", 0.0)))
	mat.set_shader_parameter("seed", float(absi(hash(str(body["id"])) + rng_seed) % 1000) / 37.0)
	mat.set_shader_parameter("city_lights", 1.0 if body.get("colony", false) else 0.0)
	mat.set_shader_parameter("light_dir", to_star)
	sphere_node.material_override = mat
	root.add_child(sphere_node)
	var spin := Tumbler.new()
	spin.spin = Vector3(0, 0.04, 0)
	sphere_node.add_child(spin)

	var atmosphere := Color(surface.get("atmosphere", "#00000000"))
	if atmosphere.a > 0.05:
		var shell := MeshInstance3D.new()
		var shell_mesh := SphereMesh.new()
		shell_mesh.radius = r * 1.1
		shell_mesh.height = r * 2.2
		shell_mesh.radial_segments = 48
		shell_mesh.rings = 24
		shell.mesh = shell_mesh
		var shell_mat := ShaderMaterial.new()
		shell_mat.shader = ATMOSPHERE_SHADER
		shell_mat.set_shader_parameter("atmosphere_color", atmosphere)
		shell_mat.set_shader_parameter("strength", 1.5)
		shell.material_override = shell_mat
		shell.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		root.add_child(shell)

	if body["type"] == "gas_giant":
		var rings := MeshInstance3D.new()
		var torus := TorusMesh.new()
		torus.inner_radius = r * 1.25
		torus.outer_radius = r * 1.6
		torus.rings = 64
		rings.mesh = torus
		rings.material_override = BoardGeometry.flat_material(Color(Color(surface.get("accent", "#ccbbaa")), 0.4))
		rings.scale = Vector3(1, 0.03, 1)
		rings.rotation.z = 0.3
		rings.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		root.add_child(rings)


## A big glowing star past the board's far edge, with halos.
static func _star(parent: Node3D, color: Color, size: float, lo: Vector3, hi: Vector3, dir2: Vector2) -> void:
	var mid := (lo + hi) / 2.0
	var half := Vector2(hi.x - lo.x, hi.z - lo.z) / 2.0
	var r := 2.0 * size
	# Out along dir2 from the board's middle, past the edge.
	var reach := minf(half.x / maxf(absf(dir2.x), 0.01), half.y / maxf(absf(dir2.y), 0.01)) + r * 2.6 + 7.0
	var pos := mid + Vector3(dir2.x, 0, dir2.y) * reach + Vector3(0, 1.0, 0)
	var root := Node3D.new()
	root.position = pos
	parent.add_child(root)
	var core := MeshInstance3D.new()
	var sphere := SphereMesh.new()
	sphere.radius = r
	sphere.height = r * 2.0
	sphere.radial_segments = 48
	sphere.rings = 24
	core.mesh = sphere
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = color.lightened(0.45) * 1.8
	core.material_override = m
	core.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(core)
	for k in 3:
		var halo := MeshInstance3D.new()
		var hs := SphereMesh.new()
		hs.radius = r * (1.2 + k * 0.55)
		hs.height = hs.radius * 2.0
		hs.radial_segments = 32
		hs.rings = 16
		halo.mesh = hs
		halo.material_override = BoardGeometry.additive_material(color * (0.28 - k * 0.08))
		halo.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		root.add_child(halo)
