class_name Fx3D
extends Node3D
## 3D combat effects: glowing bolts, beams, torpedoes, explosions with sparks
## and light flashes, shockwave rings. Additive, unshaded materials so they
## read as light. Each effect owns its material so it can fade independently.


func play(kind: String, from: Vector3, to: Vector3, color: Color, blast_radius: float) -> void:
	match kind:
		"beam":
			await _beam(from, to, color, 0.035)
			_flash(to, 0.22, color)
		"torpedo":
			await _bolt(from, to, color, 0.09, 6.0)
			explode(to, maxf(blast_radius, 0.8), color)
			await _ring(to, maxf(blast_radius, 0.8), color)
		"pulse":
			await _beam(from, to, color, 0.02)
			await _ring(to, 0.7, color)
		"melee":
			melee_impact(to, color)
		"self":
			_flash(from, 0.4, color)
			await _ring(from - Vector3(0, from.y - 0.05, 0), 0.9, color)
		_:
			await _bolt(from, to, color, 0.045, 16.0)
			_flash(to, 0.2, color)


## Hand-to-hand contact: a white-hot flash, a spray of sparks and two
## crossing slash streaks at `at`. Returns immediately (it is part of the lunge).
func melee_impact(at: Vector3, color: Color) -> void:
	_flash(at, 0.09, Color(1.0, 0.95, 0.8), 1.0)
	_sparks(at, 0.6, color)
	for angle in [35.0, -40.0]:
		var streak := MeshInstance3D.new()
		var box := BoxMesh.new()
		box.size = Vector3(0.7, 0.025, 0.025)
		streak.mesh = box
		streak.material_override = _additive(color.lightened(0.5))
		streak.position = at
		streak.rotation_degrees = Vector3(randf_range(-20.0, 20.0), randf_range(0.0, 180.0), angle)
		streak.scale = Vector3(0.2, 1.0, 1.0)
		add_child(streak)
		var tw := create_tween().set_parallel()
		tw.tween_property(streak, "scale", Vector3(1.0, 1.0, 1.0), 0.1).set_ease(Tween.EASE_OUT)
		tw.tween_property(streak.material_override, "albedo_color", Color.BLACK, 0.22)
		tw.chain().tween_callback(streak.queue_free)


func explode(at: Vector3, size: float = 1.0, tint: Color = Color(1.0, 0.6, 0.25)) -> void:
	_flash(at, 0.45 * size, Color(1.0, 0.85, 0.6))
	_sparks(at, size, tint)
	_ring(at, 1.1 * size, tint)


func _sparks(at: Vector3, size: float, tint: Color) -> void:
	var sparks := CPUParticles3D.new()
	var mesh := SphereMesh.new()
	mesh.radius = 0.035
	mesh.height = 0.07
	mesh.radial_segments = 6
	mesh.rings = 3
	var mat := _additive(Color.WHITE)
	mat.vertex_color_use_as_albedo = true
	mesh.material = mat
	sparks.mesh = mesh
	sparks.one_shot = true
	sparks.explosiveness = 0.95
	sparks.amount = int(36 * clampf(size, 0.6, 2.0))
	sparks.lifetime = 0.9
	sparks.direction = Vector3.UP
	sparks.spread = 180.0
	sparks.gravity = Vector3(0, -1.5, 0)
	sparks.initial_velocity_min = 1.0 * size
	sparks.initial_velocity_max = 3.6 * size
	sparks.damping_min = 1.5
	sparks.damping_max = 3.0
	sparks.scale_amount_min = 0.6
	sparks.scale_amount_max = 1.8
	var ramp := Gradient.new()
	ramp.set_color(0, Color(1.0, 1.0, 0.85))
	ramp.set_color(1, Color(0, 0, 0))
	ramp.add_point(0.35, tint)
	sparks.color_ramp = ramp
	sparks.position = at
	add_child(sparks)
	sparks.emitting = true
	get_tree().create_timer(1.6).timeout.connect(sparks.queue_free)


func _bolt(from: Vector3, to: Vector3, color: Color, radius: float, speed: float) -> void:
	var bolt := MeshInstance3D.new()
	var capsule := CapsuleMesh.new()
	capsule.radius = radius
	capsule.height = radius * 9.0
	bolt.mesh = capsule
	bolt.material_override = _additive(color * 1.4)
	bolt.basis = _basis_along(to - from)
	bolt.position = from
	add_child(bolt)
	var light := OmniLight3D.new()
	light.light_color = color
	light.light_energy = 1.2
	light.omni_range = 1.4
	bolt.add_child(light)
	var tw := create_tween()
	tw.tween_property(bolt, "position", to, maxf(0.12, from.distance_to(to) / speed))
	await tw.finished
	bolt.queue_free()


func _beam(from: Vector3, to: Vector3, color: Color, radius: float) -> void:
	var length := from.distance_to(to)
	var pieces: Array[MeshInstance3D] = []
	for layer in [[radius, color.lightened(0.6)], [radius * 3.0, color * 0.5]]:
		var mi := MeshInstance3D.new()
		var cyl := CylinderMesh.new()
		cyl.top_radius = layer[0]
		cyl.bottom_radius = layer[0]
		cyl.height = length
		cyl.radial_segments = 8
		mi.mesh = cyl
		mi.material_override = _additive(layer[1])
		mi.basis = _basis_along(to - from)
		mi.position = (from + to) / 2.0
		add_child(mi)
		pieces.append(mi)
	var tw := create_tween().set_parallel()
	for mi in pieces:
		tw.tween_property(mi.material_override, "albedo_color", Color.BLACK, 0.35)
	await tw.finished
	for mi in pieces:
		mi.queue_free()


func _flash(at: Vector3, radius: float, color: Color, energy: float = 3.0) -> void:
	var ball := MeshInstance3D.new()
	var sphere := SphereMesh.new()
	sphere.radius = radius
	sphere.height = radius * 2.0
	ball.mesh = sphere
	ball.material_override = _additive(color)
	ball.position = at
	add_child(ball)
	var light := OmniLight3D.new()
	light.light_color = color
	light.light_energy = energy
	light.omni_range = radius * 10.0
	ball.add_child(light)
	var tw := create_tween().set_parallel()
	tw.tween_property(ball, "scale", Vector3.ONE * 2.2, 0.3).set_ease(Tween.EASE_OUT)
	tw.tween_property(ball.material_override, "albedo_color", Color.BLACK, 0.35)
	tw.tween_property(light, "light_energy", 0.0, 0.35)
	tw.chain().tween_callback(ball.queue_free)


func _ring(at: Vector3, radius: float, color: Color) -> void:
	var ring := MeshInstance3D.new()
	var torus := TorusMesh.new()
	torus.inner_radius = radius * 0.9
	torus.outer_radius = radius
	torus.rings = 32
	ring.mesh = torus
	ring.material_override = _additive(color)
	ring.position = at
	ring.scale = Vector3(0.2, 0.05, 0.2)
	add_child(ring)
	var tw := create_tween().set_parallel()
	tw.tween_property(ring, "scale", Vector3(1, 0.05, 1), 0.32).set_ease(Tween.EASE_OUT)
	tw.tween_property(ring.material_override, "albedo_color", Color.BLACK, 0.38)
	await tw.finished
	ring.queue_free()


## Basis whose Y axis points along `dir` (meshes like cylinders run along Y).
static func _basis_along(dir: Vector3) -> Basis:
	var y := dir.normalized()
	var helper := Vector3.UP if absf(y.dot(Vector3.UP)) < 0.95 else Vector3.RIGHT
	var x := helper.cross(y).normalized()
	var z := x.cross(y).normalized()
	return Basis(x, y, z)


static func _additive(color: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	m.albedo_color = color
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	return m
