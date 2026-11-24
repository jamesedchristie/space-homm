class_name OrbitalStructures
extends RefCounted
## What's built on a body, shown in orbit round its sphere: lit cities on colonies (the planet
## shader's city lights, so nothing here), a drydock for a shipyard, turret satellites for defense
## platforms, dishes for research stations, rigs for mining, ring stations for refineries and trade
## hubs, a station block for anything else. Shared by the galaxy map's systems (Planet3D), the
## bodies of a system-scale map (Body3D) and the system view (SystemMap).


## The structure for one building round a body of radius `r` in the owner's `color`;
## `slot` spreads several round the body. null for buildings with nothing to show.
static func build(building_id: String, r: float, color: Color, slot: int) -> Node3D:
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
