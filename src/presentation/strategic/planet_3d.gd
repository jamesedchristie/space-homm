class_name Planet3D
extends Node3D
## A planet on the 3D galaxy board: a spinning, procedurally shaded sphere
## (shaders/planet_3d.gdshader, colors from the planet type's "surface"), an
## atmosphere glow shell, and a tilted orbit ring in the owner's color. Its
## name is drawn in 2D by GalaxyOverlay3D.

const SURFACE_SHADER := preload("res://src/presentation/shaders/planet_3d.gdshader")
const ATMOSPHERE_SHADER := preload("res://src/presentation/shaders/atmosphere.gdshader")

var planet_id := ""
var display_name := ""
var radius := 0.38
var owner_color := Palette.NEUTRAL
var owned := false
## Height of the name label above the board.
var label_height := 1.0

var _body: MeshInstance3D
var _ring_mat: StandardMaterial3D
var _glow_mat: StandardMaterial3D
var _spin := 0.05


func setup(planet: Planet, data: DataRegistry) -> void:
	planet_id = planet.id
	display_name = planet.name
	var type_def: Dictionary = data.planet_types.get(planet.type, {})
	var surface: Dictionary = type_def.get("surface", {})
	radius = 0.42 * float(type_def.get("size", 1.0))
	var center_y := radius + 0.18
	label_height = center_y + radius * 1.5 + 0.3
	var h := absi(hash(planet.id))
	_spin = 0.08 + float(h % 7) * 0.025

	_body = MeshInstance3D.new()
	var sphere := SphereMesh.new()
	sphere.radius = radius
	sphere.height = radius * 2.0
	sphere.radial_segments = 48
	sphere.rings = 24
	_body.mesh = sphere
	var mat := ShaderMaterial.new()
	mat.shader = SURFACE_SHADER
	var atmosphere := Color(surface.get("atmosphere", "#88aaff"))
	mat.set_shader_parameter("base_color", Color(surface.get("base", type_def.get("color", "#888888"))))
	mat.set_shader_parameter("accent_color", Color(surface.get("accent", "#bbbbbb")))
	mat.set_shader_parameter("atmosphere_color", atmosphere)
	mat.set_shader_parameter("bands", float(surface.get("bands", 0.0)))
	mat.set_shader_parameter("ice_caps", float(surface.get("ice_caps", 0.0)))
	mat.set_shader_parameter("seed", float(h % 1000) / 37.0)
	_body.material_override = mat
	_body.position.y = center_y
	_body.rotation.z = deg_to_rad(12.0 + float(h % 5) * 4.0)
	add_child(_body)

	var shell := MeshInstance3D.new()
	var shell_mesh := SphereMesh.new()
	shell_mesh.radius = radius * 1.22
	shell_mesh.height = radius * 2.44
	shell.mesh = shell_mesh
	var shell_mat := ShaderMaterial.new()
	shell_mat.shader = ATMOSPHERE_SHADER
	shell_mat.set_shader_parameter("atmosphere_color", atmosphere)
	shell.material_override = shell_mat
	shell.position.y = center_y
	add_child(shell)

	# Orbit ring, tilted like the planet; colored by owner.
	var ring := MeshInstance3D.new()
	var torus := TorusMesh.new()
	torus.inner_radius = radius * 1.45
	torus.outer_radius = radius * 1.52
	torus.rings = 48
	ring.mesh = torus
	_ring_mat = BoardGeometry.flat_material(Palette.NEUTRAL)
	ring.material_override = _ring_mat
	ring.position.y = center_y
	ring.rotation = Vector3(deg_to_rad(-14.0), 0, deg_to_rad(8.0))
	ring.scale = Vector3(1, 0.12, 1)
	add_child(ring)

	# Soft owner glow on the board.
	var glow := MeshInstance3D.new()
	var disc := CylinderMesh.new()
	disc.top_radius = radius * 1.5
	disc.bottom_radius = radius * 1.5
	disc.height = 0.005
	disc.radial_segments = 32
	glow.mesh = disc
	_glow_mat = BoardGeometry.flat_material(Color(0, 0, 0, 0))
	glow.material_override = _glow_mat
	glow.position.y = 0.03
	add_child(glow)


func refresh(planet: Planet, state: GalaxyState) -> void:
	owned = not planet.owner.is_empty()
	owner_color = Palette.team_color(state.faction(planet.owner)["team"]) if owned else Palette.NEUTRAL
	_ring_mat.albedo_color = Color(owner_color, 0.9) if owned else Color(owner_color, 0.3)
	_glow_mat.albedo_color = Color(owner_color, 0.16) if owned else Color(0, 0, 0, 0)


func _process(delta: float) -> void:
	_body.rotate_object_local(Vector3.UP, delta * _spin)
