class_name Discovery3D
extends Node3D
## A one-time find on the 3D galaxy map (salvage, signals, caches, pods): a
## small tumbling object in the find's color over a faint ring. The name is
## drawn by GalaxyOverlay3D.

var discovery_id := ""
var display_name := ""
var color := Color.WHITE
var label_height := 0.8

var _object: Node3D
var _ring: MeshInstance3D
var _t := 0.0


func setup(find: Dictionary, data: DataRegistry) -> void:
	discovery_id = find["id"]
	var def: Dictionary = data.discoveries.get(find["kind"], {})
	display_name = def.get("name", find["kind"])
	color = Color(def.get("color", "#ffffff"))
	_t = randf() * TAU
	match find["kind"]:
		"derelict_hulk":
			_object = ModelFactory.build(data, "frigate", Color(0.35, 0.33, 0.3))
			_object.scale = Vector3.ONE * 0.45
			_object.rotation = Vector3(0.5, 0.3, 0.6)
		"supply_cache":
			_object = Node3D.new()
			for i in 3:
				var crate := MeshInstance3D.new()
				var box := BoxMesh.new()
				box.size = Vector3(0.14, 0.12, 0.14)
				crate.mesh = box
				var m := StandardMaterial3D.new()
				m.albedo_color = color.darkened(0.3)
				m.emission_enabled = true
				m.emission = color
				m.emission_energy_multiplier = 0.3
				crate.material_override = m
				crate.position = Vector3(cos(i * 2.1) * 0.12, i * 0.05, sin(i * 2.1) * 0.12)
				crate.rotation.y = i * 0.7
				_object.add_child(crate)
		"survivor_pods":
			_object = Node3D.new()
			for i in 3:
				var pod := MeshInstance3D.new()
				var capsule := CapsuleMesh.new()
				capsule.radius = 0.045
				capsule.height = 0.18
				pod.mesh = capsule
				var m := StandardMaterial3D.new()
				m.albedo_color = Color(0.85, 0.88, 0.92)
				m.emission_enabled = true
				m.emission = Color(1.0, 0.4, 0.3)
				m.emission_energy_multiplier = 0.4 if i == 1 else 0.0
				pod.material_override = m
				pod.position = Vector3(cos(i * 2.1) * 0.13, 0, sin(i * 2.1) * 0.13)
				pod.rotation = Vector3(1.2, i, 0.4)
				_object.add_child(pod)
		_:
			_object = MeshInstance3D.new()
			var orb := SphereMesh.new()
			orb.radius = 0.1
			orb.height = 0.2
			(_object as MeshInstance3D).mesh = orb
			(_object as MeshInstance3D).material_override = BoardGeometry.additive_material(color * 0.9)
	_object.position.y = 0.45
	add_child(_object)
	var halo := MeshInstance3D.new()
	var glow := SphereMesh.new()
	glow.radius = 0.28
	glow.height = 0.56
	halo.mesh = glow
	halo.material_override = BoardGeometry.additive_material(color * 0.12)
	halo.position.y = 0.45
	add_child(halo)
	_ring = MeshInstance3D.new()
	var torus := TorusMesh.new()
	torus.inner_radius = 0.24
	torus.outer_radius = 0.27
	torus.rings = 24
	_ring.mesh = torus
	_ring.material_override = BoardGeometry.flat_material(Color(color, 0.55))
	_ring.position.y = 0.03
	_ring.scale = Vector3(1, 0.1, 1)
	add_child(_ring)


func _process(delta: float) -> void:
	if _object == null:
		return
	_t += delta
	_object.rotation.y += delta * 0.5
	_object.position.y = 0.45 + sin(_t * 1.4) * 0.04
	var pulse := 1.0 + 0.12 * sin(_t * 2.5)
	_ring.scale = Vector3(pulse, 0.1, pulse)
