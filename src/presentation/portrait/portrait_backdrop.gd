class_name PortraitBackdrop
extends RefCounted
## Painted backdrops for the leader busts: a soft gradient plate with a few blurred
## shapes (windows, pillars, lamps) drawn into a small image and shown on an unlit quad
## behind the bust, so it reads as an out-of-focus bridge / hall / market.

const W := 96
const H := 120
static var _cache: Dictionary = {}


static func build(world: Node3D, kind: String, p: Dictionary) -> Node3D:
	var root := Node3D.new()
	world.add_child(root)
	var quad := MeshInstance3D.new()
	var m := QuadMesh.new()
	m.size = Vector2(1.6, 2.0)
	quad.mesh = m
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR
	mat.albedo_texture = texture_for(kind, p)
	quad.material_override = mat
	quad.position = Vector3(0, -0.12, -0.95)
	quad.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(quad)
	return root


static func texture_for(kind: String, p: Dictionary) -> ImageTexture:
	var key := "%s|%s|%s" % [kind, p.get("glow", ""), p.get("accent", "")]
	if not _cache.has(key):
		_cache[key] = ImageTexture.create_from_image(paint(kind, p))
	return _cache[key]


static func paint(kind: String, p: Dictionary) -> Image:
	var img := Image.create(W, H, false, Image.FORMAT_RGBA8)
	var glow := PortraitKit.col(p, "glow", Color("5aa8ff"))
	var accent := PortraitKit.col(p, "accent", Color("d9b44a"))
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(kind)
	match kind:
		"bridge":
			_gradient(img, Color("070d1c"), Color("12263a"))
			# Viewport: deep space with a planet limb.
			_rect(img, 0.04, 0.08, 0.96, 0.52, Color("02040b"), 0.9, 0.02)
			for i in 40:
				_blob(img, rng.randf(), rng.randf_range(0.09, 0.5), 0.006, Color(0.8, 0.9, 1.0), 0.8)
			_blob(img, 0.88, 0.62, 0.42, Color("2d6fc2"), 0.9)
			_blob(img, 0.88, 0.62, 0.36, Color("0b1d3d"), 0.97)
			_blob(img, 0.7, 0.3, 0.2, Color(0.25, 0.4, 0.85), 0.25)
			# Struts and consoles.
			_rect(img, 0.0, 0.0, 0.07, 1.0, Color("0a1019"), 1.0, 0.02)
			_rect(img, 0.47, 0.06, 0.53, 0.54, Color("0b121c"), 1.0, 0.02)
			_rect(img, 0.0, 0.54, 1.0, 1.0, Color("0d1826"), 1.0, 0.03)
			for i in 14:
				var c := glow if i % 3 != 0 else accent
				_blob(img, rng.randf_range(0.08, 0.92), rng.randf_range(0.6, 0.95), rng.randf_range(0.015, 0.04), c, 0.75)
			_rect(img, 0.1, 0.57, 0.9, 0.585, glow, 0.7, 0.01)
		"crystal_hall":
			_gradient(img, Color("1d1238"), Color("4a3a78"))
			_blob(img, 0.5, 0.42, 0.55, Color("a58cf0"), 0.55)
			for i in 9:
				var x := rng.randf_range(0.0, 1.0)
				var w := rng.randf_range(0.03, 0.08)
				var top := rng.randf_range(0.0, 0.3)
				_rect(img, x - w, top, x + w, 1.0, Color(0.72, 0.62, 1.0), 0.35, 0.03)
				_rect(img, x - w * 0.35, top + 0.04, x + w * 0.35, 1.0, Color(0.95, 0.9, 1.0), 0.35, 0.02)
			for i in 16:
				_blob(img, rng.randf(), rng.randf_range(0.05, 0.9), rng.randf_range(0.015, 0.04), Color(0.85, 0.8, 1.0), 0.55)
			_rect(img, 0.0, 0.88, 1.0, 1.0, Color("1a1030"), 0.8, 0.05)
		"forge_hall":
			_gradient(img, Color("120806"), Color("3a160c"))
			_blob(img, 0.5, 0.52, 0.6, Color("ff6a1c"), 0.7)
			_blob(img, 0.5, 0.52, 0.28, Color("ffc060"), 0.65)
			_rect(img, 0.0, 0.0, 0.17, 1.0, Color("0c0605"), 1.0, 0.03)
			_rect(img, 0.83, 0.0, 1.0, 1.0, Color("0c0605"), 1.0, 0.03)
			_rect(img, 0.26, 0.0, 0.32, 0.7, Color("100906"), 0.95, 0.02)
			_rect(img, 0.68, 0.0, 0.74, 0.7, Color("100906"), 0.95, 0.02)
			# Banners.
			_rect(img, 0.05, 0.05, 0.14, 0.5, Color("8a1d12"), 0.9, 0.02)
			_blob(img, 0.095, 0.25, 0.03, Color("e8b84a"), 0.8)
			_rect(img, 0.86, 0.05, 0.95, 0.5, Color("8a1d12"), 0.9, 0.02)
			_blob(img, 0.905, 0.25, 0.03, Color("e8b84a"), 0.8)
			for i in 26:
				_blob(img, rng.randf(), rng.randf_range(0.2, 0.95), rng.randf_range(0.006, 0.014), Color(1.0, 0.6, 0.2), 0.85)
			_rect(img, 0.0, 0.86, 1.0, 1.0, Color("0b0504"), 0.85, 0.06)
		"directorate":
			_gradient(img, Color("0a1219"), Color("1c3340"))
			for x in [0.14, 0.34, 0.66, 0.86]:
				_rect(img, x - 0.045, 0.06, x + 0.045, 0.78, glow.darkened(0.3), 0.55, 0.02)
				_rect(img, x - 0.012, 0.08, x + 0.012, 0.76, Color(0.8, 1.0, 1.0), 0.45, 0.01)
			_rect(img, 0.0, 0.8, 1.0, 1.0, Color("0b1218"), 0.95, 0.03)
			for i in 6:
				var yy := rng.randf_range(0.1, 0.7)
				_rect(img, rng.randf_range(0.0, 0.4), yy, rng.randf_range(0.6, 1.0), yy + 0.006, glow, 0.35, 0.005)
			_blob(img, 0.5, 0.4, 0.5, glow, 0.18)
		"scrapyard":
			_gradient(img, Color("0d0a09"), Color("2b1c14"))
			_blob(img, 0.82, 0.18, 0.4, Color("ff2a1a"), 0.5)
			_blob(img, 0.82, 0.18, 0.06, Color("ffb090"), 0.9)
			_blob(img, 0.2, 0.45, 0.4, Color("a0501e"), 0.25)
			for i in 6:
				var x := rng.randf_range(0.0, 1.0)
				_rect(img, x - 0.05, 0.0, x + 0.03, rng.randf_range(0.5, 1.0), Color("160f0c"), 0.9, 0.02)
			for i in 5:
				var x2 := rng.randf_range(0.1, 0.9)
				_rect(img, x2, 0.0, x2 + 0.008, rng.randf_range(0.2, 0.55), Color("3a2a22"), 0.8, 0.004)
			for i in 22:
				_blob(img, rng.randf(), rng.randf_range(0.3, 0.95), rng.randf_range(0.005, 0.012), Color(1.0, 0.55, 0.2), 0.8)
			_rect(img, 0.0, 0.9, 1.0, 1.0, Color("0a0706"), 0.9, 0.05)
		"market":
			_gradient(img, Color("2a1630"), Color("6a3e2a"))
			_blob(img, 0.5, 0.55, 0.6, Color("ffb050"), 0.3)
			_rect(img, 0.0, 0.0, 1.0, 0.14, Color("5b2a1e"), 0.9, 0.04)
			for i in 6:
				_rect(img, i * 0.18 - 0.02, 0.0, i * 0.18 + 0.07, 0.15, Color("c25a3a"), 0.75, 0.01)
			for i in 30:
				var c2: Color = [Color("ffc55a"), Color("ff8a3a"), Color("ffe6a0"), Color("ff5a4a")][rng.randi() % 4]
				_blob(img, rng.randf(), rng.randf_range(0.12, 0.7), rng.randf_range(0.02, 0.05), c2, 0.6)
			_rect(img, 0.04, 0.72, 0.3, 1.0, Color("2a1a14"), 0.95, 0.02)
			_rect(img, 0.72, 0.68, 0.98, 1.0, Color("2a1a14"), 0.95, 0.02)
			_rect(img, 0.3, 0.84, 0.72, 1.0, Color("1f130e"), 0.9, 0.03)
		_:
			_gradient(img, Color("0a0f18"), Color("1a2636"))
	_vignette(img)
	return img


static func _gradient(img: Image, top: Color, bottom: Color) -> void:
	for y in H:
		var c := top.lerp(bottom, float(y) / (H - 1))
		for x in W:
			img.set_pixel(x, y, c)


static func _mix(img: Image, x: int, y: int, c: Color, a: float) -> void:
	var o := img.get_pixel(x, y)
	img.set_pixel(x, y, Color(lerpf(o.r, c.r, a), lerpf(o.g, c.g, a), lerpf(o.b, c.b, a), 1.0))


## Soft round blob; (cx, cy) and r are fractions of the image width/height.
static func _blob(img: Image, cx: float, cy: float, r: float, c: Color, alpha: float) -> void:
	var pr := r * W
	var x0 := maxi(int(cx * W - pr * 1.6), 0)
	var x1 := mini(int(cx * W + pr * 1.6), W - 1)
	var y0 := maxi(int(cy * H - pr * 1.6), 0)
	var y1 := mini(int(cy * H + pr * 1.6), H - 1)
	for y in range(y0, y1 + 1):
		for x in range(x0, x1 + 1):
			var d := Vector2(x - cx * W, y - cy * H).length() / maxf(pr, 0.5)
			var a := alpha * exp(-d * d * 1.2)
			if a > 0.004:
				_mix(img, x, y, c, a)


## Axis-aligned rectangle with a soft edge (fractions of the image).
static func _rect(img: Image, ax: float, ay: float, bx: float, by: float, c: Color, alpha: float, soft: float) -> void:
	var s := maxf(soft * W, 0.6)
	var x0 := maxi(int(ax * W - s * 2.0), 0)
	var x1 := mini(int(bx * W + s * 2.0), W - 1)
	var y0 := maxi(int(ay * H - s * 2.0), 0)
	var y1 := mini(int(by * H + s * 2.0), H - 1)
	for y in range(y0, y1 + 1):
		for x in range(x0, x1 + 1):
			var dx := minf(x - ax * W, bx * W - x)
			var dy := minf(y - ay * H, by * H - y)
			var a := alpha * clampf(dx / s + 0.5, 0.0, 1.0) * clampf(dy / s + 0.5, 0.0, 1.0)
			if a > 0.004:
				_mix(img, x, y, c, a)


static func _vignette(img: Image) -> void:
	for y in H:
		for x in W:
			var d := Vector2((x + 0.5) / W - 0.5, (y + 0.5) / H - 0.5)
			var v := clampf(1.0 - pow(d.length() * 1.25, 2.4) * 0.8, 0.25, 1.0)
			var o := img.get_pixel(x, y)
			img.set_pixel(x, y, Color(o.r * v, o.g * v, o.b * v, 1.0))
