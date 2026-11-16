class_name Anomaly3D
extends Node3D
## An anomaly (mission site) on the 3D galaxy board: a slowly turning,
## glowing crystal over a pulsing ring. Its name is drawn by GalaxyOverlay3D.

const COLOR := Color("c75bd6")

var anomaly_id := ""
var display_name := ""
var label_height := 0.95

var _crystal: MeshInstance3D
var _ring: MeshInstance3D
var _t := 0.0


func setup(anomaly: Dictionary) -> void:
	anomaly_id = anomaly["id"]
	display_name = anomaly["name"]
	if _crystal != null:
		return
	_crystal = MeshInstance3D.new()
	var gem := SphereMesh.new()
	gem.radius = 0.16
	gem.height = 0.42
	gem.radial_segments = 4
	gem.rings = 2
	_crystal.mesh = gem
	var mat := StandardMaterial3D.new()
	mat.albedo_color = COLOR.lightened(0.2)
	mat.emission_enabled = true
	mat.emission = COLOR
	mat.emission_energy_multiplier = 1.6
	mat.metallic = 0.3
	mat.roughness = 0.2
	_crystal.material_override = mat
	_crystal.position.y = 0.5
	add_child(_crystal)
	var halo := MeshInstance3D.new()
	var glow := SphereMesh.new()
	glow.radius = 0.3
	glow.height = 0.6
	halo.mesh = glow
	halo.material_override = BoardGeometry.additive_material(COLOR * 0.25)
	_crystal.add_child(halo)
	_ring = MeshInstance3D.new()
	var torus := TorusMesh.new()
	torus.inner_radius = 0.3
	torus.outer_radius = 0.35
	torus.rings = 32
	_ring.mesh = torus
	_ring.material_override = BoardGeometry.flat_material(Color(COLOR, 0.85))
	_ring.position.y = 0.04
	_ring.scale = Vector3(1, 0.1, 1)
	add_child(_ring)
	_t = randf() * TAU


func _process(delta: float) -> void:
	if _crystal == null:
		return
	_t += delta
	_crystal.rotation.y += delta * 0.9
	_crystal.position.y = 0.5 + sin(_t * 1.8) * 0.05
	var pulse := 1.0 + 0.15 * sin(_t * 3.0)
	_ring.scale = Vector3(pulse, 0.1, pulse)
