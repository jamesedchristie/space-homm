class_name Body3D
extends Planet3D
## One body on a system-scale map (every body is its own Planet there): a single planet sphere
## (the planet_3d shader with its body type's surface colours) sized by the body's size, with an
## atmosphere shell, rings round gas giants, city lights on colonies and the orbital structures of
## what's built on it (OrbitalStructures, via Planet3D's refresh). A belt body is a cluster of big
## tumbling rocks. The owner's ring and glow sit on the board under it. The sun's light comes from
## the map (SolarSystem3D); aim_light() points the night side away from it.

## Sphere radius: base + per unit of the body type's size (world units; a hex is ~1.7 wide).
const RADIUS_BASE := 0.16
const RADIUS_PER_SIZE := 0.31
const LIFT := 0.36


static func body_radius(b: Dictionary, data: DataRegistry) -> float:
	if b.get("type", "") == "asteroid_belt":
		return 0.2
	return RADIUS_BASE + RADIUS_PER_SIZE * float(data.body_types.get(b["type"], {}).get("size", 0.6))


func setup(planet: Planet, data: DataRegistry) -> void:
	planet_id = planet.id
	display_name = planet.name
	_data = data
	_system = Node3D.new()
	_system.position.y = LIFT
	add_child(_system)
	var b: Dictionary = planet.bodies[0] if not planet.bodies.is_empty() else {"id": planet.id, "type": "barren"}
	_body_ids.append(b["id"])
	var r := body_radius(b, data)
	label_height = LIFT + r + 0.25
	var seed_value := absi(hash(planet.id))
	var node: Node3D
	if b["type"] == "asteroid_belt":
		node = _add_rock_cluster(seed_value)
		_surface_materials.append(null)
		# Structures stand out on a ring round the cluster (see Planet3D._refresh_structures).
		_orbiters.append({"node": node, "radius": 0.0, "speed": 0.0, "angle": 0.0, "ring": r + 0.12})
	else:
		node = _add_body(b, data, seed_value, r)
		for child in node.get_children():
			if child is MeshInstance3D and (child as MeshInstance3D).mesh is TorusMesh:
				# A gas giant's rings: finer and fainter than on the galaxy map's tiny worlds.
				var torus := (child as MeshInstance3D).mesh as TorusMesh
				torus.inner_radius = r * 1.3
				torus.outer_radius = r * 1.62
				var ring_mat := (child as MeshInstance3D).material_override as StandardMaterial3D
				ring_mat.albedo_color = Color(ring_mat.albedo_color.darkened(0.15), 0.2)
				ring_mat.cull_mode = BaseMaterial3D.CULL_BACK  # one layer of the flattened tube, not four
				# A second, narrower band inside: a hint of the ring's structure.
				var inner := MeshInstance3D.new()
				var band := TorusMesh.new()
				band.inner_radius = r * 1.16
				band.outer_radius = r * 1.27
				band.rings = 48
				inner.mesh = band
				inner.material_override = BoardGeometry.flat_material(Color(ring_mat.albedo_color, 0.14))
				(inner.material_override as StandardMaterial3D).cull_mode = BaseMaterial3D.CULL_BACK
				inner.scale = (child as MeshInstance3D).scale
				inner.rotation = (child as MeshInstance3D).rotation
				node.add_child(inner)
		_surface_materials.append(node.material_override as ShaderMaterial)
		_add_atmosphere(node, b, data, r)
		# A slow spin (radius 0: Planet3D._process turns it in place).
		_orbiters.append({"node": node, "radius": 0.0, "speed": 0.0, "angle": 0.0})
	_body_nodes.append(node)
	_body_radii.append(r)
	_markers.append(null)

	# The owner's ring and a faint glow on the board.
	var ring_r := r + 0.16
	var ring := MeshInstance3D.new()
	var t := TorusMesh.new()
	t.inner_radius = ring_r
	t.outer_radius = ring_r + 0.035
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
	disc.top_radius = ring_r + 0.03
	disc.bottom_radius = ring_r + 0.03
	disc.height = 0.005
	disc.radial_segments = 32
	glow.mesh = disc
	_glow = BoardGeometry.flat_material(Color(0, 0, 0, 0))
	glow.material_override = _glow
	glow.position.y = 0.025
	add_child(glow)
	_floor.append(glow)


func refresh(planet: Planet, state: GalaxyState, known: String = "\u0000", scanned: bool = true) -> void:
	super.refresh(planet, state, known, scanned)
	# Unclaimed bodies keep only a whisper of a ring (the map has a lot of them).
	if not owned:
		_owner_ring.albedo_color = Color(owner_color, 0.08)


## Points the planet shader's night side away from the sun at `star` (world position).
func aim_light(star: Vector3) -> void:
	var to_star := (star - position)
	to_star.y = maxf(to_star.y, 0.0) + 0.3
	set_light_dir(to_star.normalized())


## The world-space direction towards the sun (the planet shader's night side faces away).
func set_light_dir(dir: Vector3) -> void:
	for m in _surface_materials:
		if m != null:
			m.set_shader_parameter("light_dir", dir)


func _add_atmosphere(node: Node3D, b: Dictionary, data: DataRegistry, r: float) -> void:
	var surface: Dictionary = data.body_types.get(b["type"], {}).get("surface", {})
	var atmosphere := Color(surface.get("atmosphere", "#00000000"))
	if atmosphere.a <= 0.05:
		return
	var shell := MeshInstance3D.new()
	var mesh := SphereMesh.new()
	mesh.radius = r * 1.1
	mesh.height = r * 2.2
	mesh.radial_segments = 40
	mesh.rings = 20
	shell.mesh = mesh
	var mat := ShaderMaterial.new()
	mat.shader = ATMOSPHERE_SHADER
	mat.set_shader_parameter("atmosphere_color", atmosphere)
	mat.set_shader_parameter("strength", 1.3 if atmosphere.a > 0.5 else 0.8)
	shell.material_override = mat
	shell.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# The shell sits on the planet's parent so it doesn't spin with the surface.
	_system.add_child(shell)


## A belt body: one big rock and a handful of smaller ones round it, all tumbling.
func _add_rock_cluster(seed_value: int) -> Node3D:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var cluster := Node3D.new()
	_system.add_child(cluster)
	var big := ModelFactory.build_rock(rng.randi(), 0.17)
	cluster.add_child(big)
	for k in 7:
		var a := TAU * k / 7.0 + rng.randf_range(-0.3, 0.3)
		var rock := ModelFactory.build_rock(rng.randi(), rng.randf_range(0.03, 0.065))
		rock.position = Vector3(cos(a), rng.randf_range(-0.08, 0.08), sin(a)) * rng.randf_range(0.24, 0.36)
		cluster.add_child(rock)
	return cluster
