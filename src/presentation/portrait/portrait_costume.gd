class_name PortraitCostume
extends RefCounted
## Shoulders, torso and costume of a leader bust, per species look: a naval uniform,
## layered Vel'tari robes with a winged collar, Kesh plate armour (or a raider's scrap
## plate) and Sorn tunics with a stiff collar (or a trader's vest, scarf and coin chain).
## `torso` is positioned at the shoulder line; the neck is part of the head node.


static func build(torso: Node3D, head: Node3D, look: String, p: Dictionary, team: Color) -> void:
	match look:
		"veltari":
			_veltari(torso, p, team)
		"kesh":
			_kesh(torso, p, team)
		"sorn":
			_sorn(torso, p, team)
		_:
			_human(torso, p, team)


static func _body(torso: Node3D, cloth: Material, arm_cloth: Material = null, width: float = 1.0) -> void:
	var arm := arm_cloth if arm_cloth != null else cloth
	PortraitKit.box(torso, Vector3(0.34 * width, 0.46, 0.24), cloth, Vector3(0, -0.3, 0.0))
	PortraitKit.sphere(torso, 1.0, cloth, Vector3(0, -0.062, -0.002), Vector3(0.18 * width, 0.085, 0.122), Vector3.ZERO, 32)
	PortraitKit.capsule(torso, 0.058, 0.44 * width, cloth, Vector3(0, -0.032, 0), Vector3(0, 0, 90))
	for side: float in [-1.0, 1.0]:
		# Sloping trapezius, rounded shoulder and a tapering arm.
		PortraitKit.capsule(torso, 0.045, 0.2, cloth, Vector3(side * 0.085 * width, -0.0, 0.0), Vector3(0, 0, side * -72.0))
		PortraitKit.sphere(torso, 0.066, arm, Vector3(side * 0.2 * width, -0.045, 0), Vector3(1, 0.95, 1), Vector3.ZERO, 24)
		PortraitKit.capsule(torso, 0.05, 0.36, arm, Vector3(side * 0.222 * width, -0.22, 0), Vector3(0, 0, side * 3.0))


static func _human(torso: Node3D, p: Dictionary, team: Color) -> void:
	var primary := PortraitKit.col(p, "primary", Color("233f6e"))
	var secondary := PortraitKit.col(p, "secondary", Color("e9eef7"))
	var accent := PortraitKit.col(p, "accent", Color("d9b44a"))
	var cloth := PortraitKit.mat(primary, 0.78)
	var white := PortraitKit.mat(secondary, 0.7)
	var gold := PortraitKit.mat(accent, 0.3, 0.85)
	_body(torso, cloth)
	# Open collar with the white shirt in a V and dark lapels.
	var shirt := PortraitKit.add(torso, _prism(0.1, 0.19, 0.02), white, Vector3(0, -0.105, 0.113), Vector3.ONE, Vector3(0, 0, 180))
	shirt.name = "Shirt"
	for side: float in [-1.0, 1.0]:
		PortraitKit.box(torso, Vector3(0.026, 0.215, 0.014), cloth, Vector3(side * 0.047, -0.1, 0.118), Vector3(0, 0, side * 14.0))
		# Stand collar behind the neck with gold tabs.
		PortraitKit.box(torso, Vector3(0.018, 0.012, 0.012), gold, Vector3(side * 0.05, -0.004, 0.058), Vector3(0, 0, 0))
		# Epaulettes: gold boards with rank bars and fringe.
		var ep := Node3D.new()
		ep.position = Vector3(side * 0.19, 0.022, 0.0)
		ep.rotation_degrees = Vector3(0, 0, side * -9.0)
		torso.add_child(ep)
		PortraitKit.box(ep, Vector3(0.078, 0.012, 0.105), gold, Vector3.ZERO)
		for k in 3:
			PortraitKit.box(ep, Vector3(0.07, 0.003, 0.008), PortraitKit.mat(primary.darkened(0.3), 0.6), Vector3(0, 0.0075, -0.03 + k * 0.016))
		for k in 7:
			PortraitKit.cylinder(ep, 0.0022, 0.0022, 0.02, gold, Vector3(-0.037 + k * 0.0123, -0.004, 0.058), Vector3(90, 0, 0), 6)
		PortraitKit.sphere(ep, 0.0065, gold, Vector3(0, 0.008, 0.04), Vector3(1, 0.6, 1), Vector3.ZERO, 10)
	PortraitKit.cylinder(torso, 0.049, 0.054, 0.02, cloth, Vector3(0, 0.002, -0.006), Vector3.ZERO, 28)
	# Ribbons and a name bar on the left breast, a small pin on the right.
	var ribbon_cols := [Color("b32b2b"), Color("2b55b3"), Color("d9b44a"), Color("2b9a55")]
	for row in 2:
		for k in 3:
			PortraitKit.box(torso, Vector3(0.022, 0.011, 0.005), PortraitKit.mat(ribbon_cols[(row * 3 + k) % 4], 0.5),
					Vector3(0.082 + k * 0.024, -0.17 - row * 0.013, 0.1186 - k * 0.0035), Vector3(0, -14, 0))
	PortraitKit.box(torso, Vector3(0.056, 0.008, 0.004), gold, Vector3(0.115, -0.208, 0.113), Vector3(0, -14, 0))
	PortraitKit.sphere(torso, 0.011, gold, Vector3(-0.1, -0.17, 0.115), Vector3(1, 1, 0.4), Vector3.ZERO, 16)
	# Team stripe on the sleeve.
	for side: float in [-1.0, 1.0]:
		PortraitKit.cylinder(torso, 0.0555, 0.0555, 0.012, PortraitKit.mat(team, 0.5), Vector3(side * 0.23, -0.3, 0), Vector3(0, 0, side * 5.0), 24)


static func _veltari(torso: Node3D, p: Dictionary, team: Color) -> void:
	var primary := PortraitKit.col(p, "primary", Color("4a3a78"))
	var secondary := PortraitKit.col(p, "secondary", Color("d9d3ee"))
	var accent := PortraitKit.col(p, "accent", Color("c9b0ff"))
	var glow_color := PortraitKit.col(p, "glow", Color("b48cff"))
	var silk := PortraitKit.mat(primary, 0.32, 0.25)
	var pearl := PortraitKit.mat(secondary, 0.25, 0.3)
	var trim := PortraitKit.glow(accent, 1.6)
	_body(torso, silk, null, 1.05)
	# Wide sleeves.
	for side: float in [-1.0, 1.0]:
		PortraitKit.cylinder(torso, 0.056, 0.082, 0.3, silk, Vector3(side * 0.25, -0.26, 0), Vector3(0, 0, side * 7.0), 28)
		PortraitKit.torus(torso, 0.0026, 0.08, trim, Vector3(side * 0.268, -0.405, 0), Vector3(0, 0, side * 7.0), Vector3(1.0, 1.0, 1.0))
	# Cross-over lapels in pearl, with a glowing edge.
	for side: float in [-1.0, 1.0]:
		var lap := PortraitKit.box(torso, Vector3(0.05, 0.3, 0.014), pearl, Vector3(side * 0.045, -0.14, 0.116), Vector3(0, 0, side * 24.0))
		lap.name = "Lapel"
		PortraitKit.box(torso, Vector3(0.004, 0.31, 0.016), trim, Vector3(side * 0.066, -0.14, 0.117), Vector3(0, 0, side * 24.0))
	# Winged collar behind the head, edged in light.
	for side: float in [-1.0, 1.0]:
		var wing := Node3D.new()
		wing.position = Vector3(side * 0.115, 0.115, -0.07)
		wing.rotation_degrees = Vector3(-6, side * -32.0, side * -13.0)
		torso.add_child(wing)
		PortraitKit.box(wing, Vector3(0.012, 0.3, 0.17), PortraitKit.mat(primary.lightened(0.05), 0.35, 0.3), Vector3.ZERO)
		PortraitKit.box(wing, Vector3(0.006, 0.3, 0.17), PortraitKit.mat(secondary, 0.3, 0.2), Vector3(-side * 0.0065, 0, 0.0))
		PortraitKit.box(wing, Vector3(0.014, 0.305, 0.006), trim, Vector3(0, 0, 0.088))
		PortraitKit.box(wing, Vector3(0.014, 0.006, 0.17), trim, Vector3(0, 0.152, 0))
		# Shoulder crystals.
		for k in 3:
			var c := PortraitKit.cylinder(torso, 0.0, 0.008, 0.045 + k * 0.012, PortraitKit.glow(glow_color.lerp(Color.WHITE, 0.4), 1.3, 0.85),
					Vector3(side * (0.19 + k * 0.03), 0.04 + k * 0.004, -0.02), Vector3(0, 0, -side * (18 + k * 14.0)), 5)
			c.name = "ShoulderShard"
	# Pendant: a crystal on a fine chain.
	PortraitKit.torus(torso, 0.0012, 0.046, PortraitKit.mat(Color("d8d8f0"), 0.2, 0.9), Vector3(0, -0.005, 0.0), Vector3.ZERO, Vector3(1, 1, 1.15))
	var gem := PortraitKit.sphere(torso, 0.016, PortraitKit.glow(glow_color.lerp(Color.WHITE, 0.3), 2.0, 0.9), Vector3(0, -0.145, 0.118), Vector3(0.8, 1.35, 0.7), Vector3.ZERO, 6)
	gem.name = "Pendant"
	PortraitKit.cylinder(torso, 0.0, 0.0035, 0.1, trim, Vector3(0, -0.07, 0.118), Vector3(0, 0, 0), 6)
	PortraitKit.sphere(torso, 0.006, PortraitKit.glow(team, 1.5), Vector3(0.06, -0.2, 0.118), Vector3.ONE, Vector3.ZERO, 10)


static func _kesh(torso: Node3D, p: Dictionary, team: Color) -> void:
	var primary := PortraitKit.col(p, "primary", Color("4b3326"))
	var secondary := PortraitKit.col(p, "secondary", Color("2d2420"))
	var accent := PortraitKit.col(p, "accent", Color("d36a2e"))
	var raider: bool = p.get("scar", false)
	var leather := PortraitKit.mat(primary, 0.8)
	var steel := PortraitKit.mat(secondary.lightened(0.12), 0.5, 0.25)
	var trim := PortraitKit.mat(accent.lightened(0.1), 0.35, 0.7)
	_body(torso, leather, leather, 1.12)
	# Breastplate with ribs and a clan emblem.
	var plate := PortraitKit.sphere(torso, 1.0, steel, Vector3(0, -0.17, 0.02), Vector3(0.2, 0.2, 0.115), Vector3.ZERO, 32)
	plate.name = "Breastplate"
	for k in 3:
		PortraitKit.torus(torso, 0.003, 0.012, trim, Vector3(0, -0.12 - k * 0.045, 0.125 - k * 0.003), Vector3(90, 0, 0), Vector3(6.2 - k * 0.55, 1.0, 1.0))
	var skull := PortraitKit.mat(Color(0.86, 0.8, 0.66), 0.5)
	PortraitKit.sphere(torso, 0.021, skull, Vector3(0, -0.205, 0.128), Vector3(1, 1.05, 0.6), Vector3.ZERO, 18)
	for side: float in [-1.0, 1.0]:
		PortraitKit.sphere(torso, 0.005, PortraitKit.mat(Color(0.05, 0.03, 0.03), 0.9), Vector3(side * 0.008, -0.2, 0.14), Vector3(1, 1.2, 0.5), Vector3.ZERO, 8)
	# Gorget around the neck.
	PortraitKit.cylinder(torso, 0.059, 0.068, 0.045, steel, Vector3(0, 0.01, -0.004), Vector3.ZERO, 32)
	PortraitKit.torus(torso, 0.003, 0.0645, trim, Vector3(0, 0.032, -0.004), Vector3.ZERO, Vector3(1, 1, 1))
	# Big pauldrons with spikes.
	for side: float in [-1.0, 1.0]:
		var pauld := Node3D.new()
		pauld.position = Vector3(side * 0.245, 0.004, 0.0)
		torso.add_child(pauld)
		PortraitKit.sphere(pauld, 0.105, steel, Vector3.ZERO, Vector3(1.0, 0.68, 1.05), Vector3(0, 0, side * -8.0), 32)
		PortraitKit.torus(pauld, 0.004, 0.096, trim, Vector3(0, -0.026, 0), Vector3(0, 0, side * -8.0), Vector3(1.0, 1.0, 1.0))
		for k in 3:
			var a := (k - 1) * 0.55
			var s := PortraitKit.cone(pauld, 0.0155, 0.07 - absf(k - 1) * 0.015, steel,
					Vector3(side * (0.02 + 0.015 * cos(a)), 0.06, sin(a) * 0.06), Vector3(-a * 40.0, 0, -side * 35.0), 12)
			s.name = "Spike"
		if raider:
			PortraitKit.box(pauld, Vector3(0.05, 0.01, 0.07), PortraitKit.mat(Color("7a2a1a"), 0.9), Vector3(side * 0.01, 0.045, 0.0), Vector3(0, 12, -side * 10.0))
	# Leather straps across the chest.
	for side: float in [-1.0, 1.0]:
		PortraitKit.box(torso, Vector3(0.03, 0.34, 0.012), PortraitKit.mat(primary.darkened(0.35), 0.75), Vector3(side * 0.07, -0.16, 0.126), Vector3(0, 0, side * -32.0))
	if raider:
		# Chains and rags.
		for k in 9:
			var t := float(k) / 8.0
			PortraitKit.torus(torso, 0.0015, 0.0075, PortraitKit.mat(Color(0.45, 0.42, 0.4), 0.45, 0.8),
					Vector3(-0.13 + 0.26 * t, -0.1 - 0.05 * sin(t * PI), 0.13), Vector3(90 if k % 2 == 0 else 0, 20, 0))
		PortraitKit.box(torso, Vector3(0.05, 0.14, 0.006), PortraitKit.mat(Color("8a1d12"), 0.9), Vector3(0.12, -0.35, 0.12), Vector3(0, 0, 8))
		for k in 5:
			PortraitKit.sphere(torso, 0.005, PortraitKit.mat(Color(0.6, 0.5, 0.35), 0.4, 0.7), Vector3(-0.12 + k * 0.06, -0.31, 0.118), Vector3(1, 1, 0.5), Vector3.ZERO, 8)
	else:
		PortraitKit.sphere(torso, 0.008, PortraitKit.glow(team, 1.5), Vector3(0.1, -0.12, 0.124), Vector3.ONE, Vector3.ZERO, 10)


static func _sorn(torso: Node3D, p: Dictionary, team: Color) -> void:
	var primary := PortraitKit.col(p, "primary", Color("2e4658"))
	var secondary := PortraitKit.col(p, "secondary", Color("c2cdd6"))
	var accent := PortraitKit.col(p, "accent", Color("4dd0c8"))
	var trader: bool = p.get("goggles", false)
	var cloth := PortraitKit.mat(primary, 0.7, 0.1)
	var light := PortraitKit.mat(secondary, 0.5, 0.2)
	var trim := PortraitKit.glow(accent, 1.4)
	_body(torso, cloth, cloth, 1.0)
	if not trader:
		# Layered tunic: a pale under-panel, a glowing seam, and a high stiff collar.
		for side: float in [-1.0, 1.0]:
			PortraitKit.box(torso, Vector3(0.06, 0.34, 0.012), light, Vector3(side * 0.04, -0.16, 0.118), Vector3(0, 0, side * 9.0))
			PortraitKit.box(torso, Vector3(0.0045, 0.35, 0.014), trim, Vector3(side * 0.07, -0.16, 0.12), Vector3(0, 0, side * 9.0))
			var wing := Node3D.new()
			wing.position = Vector3(side * 0.088, 0.1, -0.05)
			wing.rotation_degrees = Vector3(-4, side * -24.0, side * -7.0)
			torso.add_child(wing)
			PortraitKit.box(wing, Vector3(0.012, 0.25, 0.12), PortraitKit.mat(primary.darkened(0.1), 0.5, 0.2), Vector3.ZERO)
			PortraitKit.box(wing, Vector3(0.014, 0.254, 0.005), trim, Vector3(0, 0, 0.0625))
			PortraitKit.cylinder(torso, 0.07, 0.075, 0.006, light, Vector3(side * 0.225, -0.005, 0.0), Vector3(side * 2.0, 0, side * -8.0), 28)
		PortraitKit.box(torso, Vector3(0.18, 0.2, 0.012), PortraitKit.mat(primary.darkened(0.12), 0.5, 0.2), Vector3(0, 0.1, -0.075))
		var med := PortraitKit.cylinder(torso, 0.026, 0.026, 0.008, PortraitKit.mat(accent.darkened(0.45), 0.25, 0.8), Vector3(0, -0.2, 0.123), Vector3(90, 0, 0), 28)
		med.name = "Medallion"
		PortraitKit.sphere(torso, 0.011, trim, Vector3(0, -0.2, 0.129), Vector3(1, 1, 0.5), Vector3.ZERO, 14)
	else:
		# Trader: leather vest, bandolier, a bright scarf and a coin chain.
		var vest := PortraitKit.mat(Color("5a3a22"), 0.8)
		var brass := PortraitKit.mat(Color("c79a3a"), 0.28, 0.85)
		for side: float in [-1.0, 1.0]:
			PortraitKit.box(torso, Vector3(0.09, 0.3, 0.012), vest, Vector3(side * 0.105, -0.17, 0.115), Vector3(0, 0, side * 7.0))
			PortraitKit.box(torso, Vector3(0.035, 0.42, 0.012), PortraitKit.mat(Color("3a2418"), 0.8), Vector3(side * 0.02, -0.2, 0.128), Vector3(0, 0, -side * 28.0 + 0.0))
		for k in 3:
			PortraitKit.box(torso, Vector3(0.02, 0.026, 0.02), brass, Vector3(-0.08 + k * 0.08, -0.3, 0.118))
		PortraitKit.box(torso, Vector3(0.06, 0.05, 0.03), PortraitKit.mat(Color("3a2418"), 0.8), Vector3(-0.17, -0.3, 0.08))
		# Scarf around the neck.
		var scarf := PortraitKit.torus(torso, 0.016, 0.052, PortraitKit.mat(accent, 0.7), Vector3(0, -0.005, 0.0), Vector3.ZERO, Vector3(1.0, 1.0, 1.1))
		scarf.name = "Scarf"
		PortraitKit.box(torso, Vector3(0.05, 0.16, 0.012), PortraitKit.mat(accent.darkened(0.15), 0.7), Vector3(0.04, -0.09, 0.118), Vector3(0, 0, -6))
		# Coin chain swinging across the chest.
		for k in 13:
			var t := float(k) / 12.0
			var xx := lerpf(-0.14, 0.14, t)
			var yy := -0.12 - 0.075 * sin(t * PI)
			PortraitKit.cylinder(torso, 0.0075, 0.0075, 0.003, brass, Vector3(xx, yy, 0.122), Vector3(80, 0, 0), 14)
		PortraitKit.cylinder(torso, 0.017, 0.017, 0.005, brass, Vector3(0, -0.2, 0.128), Vector3(90, 0, 0), 20)
	PortraitKit.sphere(torso, 0.006, PortraitKit.glow(team, 1.4), Vector3(0.095, -0.12, 0.12), Vector3.ONE, Vector3.ZERO, 10)


static func _prism(w: float, h: float, d: float) -> PrismMesh:
	var m := PrismMesh.new()
	m.size = Vector3(w, h, d)
	return m
