class_name JumpGate3D
extends RefCounted
## A jump gate: a ring on four field emitters, standing up and facing -Z (turn it with
## look_at). Active, its field shimmers blue and it lights its surroundings (the system view's
## gate, which ships fly through); dormant (the jump points of a system-scale map, before
## Hyperdrive), the field is dark, the emitters cold and the ring still. The field mesh is named
## "Field" so a caller can flash it.

const ACTIVE_FIELD := Color(0.06, 0.2, 0.32)
const DORMANT_FIELD := Color(0.012, 0.02, 0.03)


static func build(dormant: bool = false, size: float = 1.0) -> Node3D:
	var gate := Node3D.new()
	var hull := ModelFactory.material("hull")
	var dark := ModelFactory.material("dark")
	var ring := MeshInstance3D.new()
	var torus := TorusMesh.new()
	torus.inner_radius = 0.2 * size
	torus.outer_radius = 0.255 * size
	torus.rings = 40
	torus.ring_segments = 10
	ring.mesh = torus
	ring.material_override = hull
	ring.rotation.x = PI / 2.0  # stand the ring up, facing the system
	gate.add_child(ring)
	# Four field emitters around the ring.
	for k in 4:
		var a := k * TAU / 4.0 + PI / 4.0
		var lamp := MeshInstance3D.new()
		var sm := SphereMesh.new()
		sm.radius = 0.022 * size
		sm.height = 0.044 * size
		lamp.mesh = sm
		lamp.material_override = BoardGeometry.additive_material(Color(0.1, 0.16, 0.22) if dormant else Color(0.35, 0.85, 1.0))
		lamp.position = Vector3(cos(a), sin(a), 0.0) * 0.255 * size
		gate.add_child(lamp)
		var pod := MeshInstance3D.new()
		var cyl := CylinderMesh.new()
		cyl.top_radius = 0.03 * size
		cyl.bottom_radius = 0.04 * size
		cyl.height = 0.06 * size
		pod.mesh = cyl
		pod.material_override = dark
		pod.position = Vector3(cos(a), sin(a), 0.0) * 0.235 * size
		pod.rotation.z = a - PI / 2.0
		gate.add_child(pod)
	var field := MeshInstance3D.new()
	var disc := CylinderMesh.new()
	disc.top_radius = 0.2 * size
	disc.bottom_radius = 0.2 * size
	disc.height = 0.004 * size
	disc.radial_segments = 32
	field.mesh = disc
	field.material_override = BoardGeometry.additive_material(DORMANT_FIELD if dormant else ACTIVE_FIELD)
	field.rotation.x = PI / 2.0
	field.name = "Field"
	gate.add_child(field)
	if dormant:
		return gate
	var spin := Tumbler.new()
	spin.spin = Vector3(0, 0, 0.25)
	ring.add_child(spin)
	var light := OmniLight3D.new()
	light.light_color = Color(0.4, 0.8, 1.0)
	light.light_energy = 0.8
	light.omni_range = 0.8 * size
	gate.add_child(light)
	return gate
