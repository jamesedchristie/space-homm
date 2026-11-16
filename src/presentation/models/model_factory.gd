class_name ModelFactory
extends RefCounted
## Builds low-poly, flat-shaded 3D models from JSON recipes
## (data/models/models.json): each model is a list of parts.
##
## Model space: +X is forward, +Y up, +Z to the side; 1 unit = one cell radius.
## Part types (all take "at": [x, y, z], "material", optional "mirror": true to
## duplicate across Z, optional "rot": degrees around Y):
##   hull      "outline": [[x, z], ...] top-view polygon, "height", "bevel" (0-1,
##             how much the top face shrinks toward the centre), "taper" (bottom shrink)
##   box       "size": [x, y, z]
##   cylinder  "radius", "length", "axis": "x"|"y"|"z", "segments"
##   cone      same as cylinder; the tip points along +axis
##   sphere    "radius", "detail" (0-2), "squash": [x, y, z]
##   rock      "radius", "seed": an irregular faceted boulder
## A model may name a "base" model whose parts come first (e.g. "humanoid").
## Engine parts ("material": "engine") on the x axis also get an exhaust plume
## pointing backwards. Lights: "light_red", "light_green", "beacon" blink;
## "stripe" is a brightly glowing team-color strip.
## Materials: hull, dark, accent (team color), glass, engine (glowing), gold,
## visor (glowing team color), rock, hazard.

const PLUME := preload("res://src/presentation/shaders/engine_plume.gdshader")
const NAV_LIGHT := preload("res://src/presentation/shaders/nav_light.gdshader")
## Blinking light materials: [color, period, phase].
const LIGHTS := {
	"light_red": [Color(1.0, 0.18, 0.15), 1.4, 0.0],
	"light_green": [Color(0.2, 1.0, 0.35), 1.4, 0.7],
	"beacon": [Color(1.0, 0.85, 0.5), 2.2, 0.3],
}

static var _mesh_cache: Dictionary = {}
static var _material_cache: Dictionary = {}
## Centre of the part being built (local space); face normals point away from it.
static var _center := Vector3.ZERO


## A Node3D with one MeshInstance3D per material, ready to add to a scene.
## style: a species id (data/strategic/species.json "style"): its colours
## repaint hull / dark / glass, and its "extra" parts are added to the model
## (and to every model built on the same base, e.g. "humanoid").
static func build(data: DataRegistry, model_id: String, team_color: Color, style: String = "") -> Node3D:
	var root := Node3D.new()
	root.name = model_id
	var style_def: Dictionary = data.species.get(style, {}).get("style", {})
	var meshes := _meshes_for(data, model_id, style if not style_def.is_empty() else "")
	for material_name: String in meshes:
		var mi := MeshInstance3D.new()
		mi.mesh = meshes[material_name]
		mi.material_override = _styled_material(material_name, team_color, style_def)
		root.add_child(mi)
	_add_plumes(root, data, model_id, team_color)
	return root


## Exhaust cones behind every engine part that points along x.
static func _add_plumes(root: Node3D, data: DataRegistry, model_id: String, team_color: Color) -> void:
	var tint := team_color.lerp(Color(1.0, 0.6, 0.25), 0.35)
	var def: Dictionary = data.models.get(model_id, {})
	var phase := 0.0
	for part: Dictionary in _parts_of(data, def, 0):
		if part.get("material", "") != "engine" or part.get("type", "") != "cylinder" or part.get("axis", "x") != "x":
			continue
		var at := _vec3(part.get("at", [0, 0, 0]))
		var r := float(part.get("radius", 0.06))
		var nozzle := at.x - float(part.get("length", 0.03)) / 2.0
		for zsign in ([1.0, -1.0] if part.get("mirror", false) else [1.0]):
			var plume := MeshInstance3D.new()
			var cone := CylinderMesh.new()
			var length := r * 6.0
			cone.top_radius = r * 1.05
			cone.bottom_radius = r * 0.15
			cone.height = length
			cone.radial_segments = 12
			cone.rings = 1
			cone.cap_top = false
			cone.cap_bottom = false
			plume.mesh = cone
			var mat := ShaderMaterial.new()
			mat.shader = PLUME
			mat.set_shader_parameter("phase", phase)
			mat.set_shader_parameter("core_color", tint.lerp(Color.WHITE, 0.6))
			mat.set_shader_parameter("tail_color", tint)
			phase += 1.9
			plume.material_override = mat
			# CylinderMesh runs along +y with the top at +height/2: turn it so
			# the wide end sits on the nozzle and the tip points backwards (-x).
			plume.rotation_degrees = Vector3(0, 0, 90)
			plume.position = Vector3(nozzle - length / 2.0, at.y, at.z * zsign)
			plume.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			root.add_child(plume)
			var halo := MeshInstance3D.new()
			var dot := SphereMesh.new()
			dot.radius = r * 1.6
			dot.height = r * 3.2
			dot.radial_segments = 10
			dot.rings = 5
			halo.mesh = dot
			var glow := StandardMaterial3D.new()
			glow.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
			glow.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
			glow.albedo_color = tint * 0.3
			glow.cull_mode = BaseMaterial3D.CULL_DISABLED
			glow.no_depth_test = false
			halo.material_override = glow
			halo.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			halo.position = Vector3(nozzle - r * 0.3, at.y, at.z * zsign)
			root.add_child(halo)


## A standalone faceted boulder (asteroid terrain on the 3D board).
static func build_rock(rock_seed: int, radius: float) -> MeshInstance3D:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	_center = Vector3.ZERO
	_rock(st, Transform3D.IDENTITY, radius, rock_seed, false)
	var mi := MeshInstance3D.new()
	mi.mesh = st.commit()
	mi.material_override = material("rock")
	return mi


## Shared material per (name, team color).
static func material(material_name: String, team_color: Color = Color.WHITE) -> Material:
	var key := "%s:%s" % [material_name, team_color.to_html()]
	if _material_cache.has(key):
		return _material_cache[key]
	if material_name in LIGHTS:
		var light := ShaderMaterial.new()
		light.shader = NAV_LIGHT
		var spec: Array = LIGHTS[material_name]
		light.set_shader_parameter("color", spec[0])
		light.set_shader_parameter("period", spec[1])
		light.set_shader_parameter("phase", spec[2])
		_material_cache[key] = light
		return light
	var m := StandardMaterial3D.new()
	m.roughness = 0.55
	m.cull_mode = BaseMaterial3D.CULL_DISABLED  # normals are set explicitly, winding doesn't matter
	match material_name:
		"hull":
			m.albedo_color = Color("aab2bf")
			m.metallic = 0.55
			m.roughness = 0.38
		"dark":
			m.albedo_color = Color("3b4252")
			m.metallic = 0.5
		"accent":
			m.albedo_color = team_color
			m.emission_enabled = true
			m.emission = team_color
			m.emission_energy_multiplier = 0.25
		"glass":
			m.albedo_color = Color("13202e")
			m.metallic = 0.8
			m.roughness = 0.08
			m.emission_enabled = true
			m.emission = Color("4fb6ff")
			m.emission_energy_multiplier = 0.35
		"engine":
			m.albedo_color = Color("ffb35c")
			m.emission_enabled = true
			m.emission = Color("ff9a3c")
			m.emission_energy_multiplier = 3.0
		"gold":
			m.albedo_color = Color("e8c25a")
			m.metallic = 0.85
			m.roughness = 0.3
		"visor":
			m.albedo_color = team_color.lightened(0.4)
			m.emission_enabled = true
			m.emission = team_color.lightened(0.3)
			m.emission_energy_multiplier = 1.4
		"stripe":
			m.albedo_color = team_color.lightened(0.2)
			m.emission_enabled = true
			m.emission = team_color.lightened(0.15)
			m.emission_energy_multiplier = 1.6
		"rock":
			m.albedo_color = Color("6e6258")
			m.roughness = 0.95
		"hazard":
			m.albedo_color = Color("d9b026")
			m.roughness = 0.7
		_:
			m.albedo_color = Color.MAGENTA
	_material_cache[key] = m
	return m


## Meshes per material for a model (geometry is shared by every team).
static func _meshes_for(data: DataRegistry, model_id: String, style: String = "") -> Dictionary:
	var cache_key := model_id + "@" + style
	if _mesh_cache.has(cache_key):
		return _mesh_cache[cache_key]
	var tools := {}  # material name -> SurfaceTool
	var def: Dictionary = data.models.get(model_id, {})
	if def.is_empty():
		push_warning("ModelFactory: unknown model '%s'" % model_id)
		def = {"parts": [{"type": "box", "size": [0.6, 0.3, 0.4], "material": "accent"}]}
	var parts := _parts_of(data, def, 0)
	if not style.is_empty():
		var extra: Dictionary = data.species.get(style, {}).get("style", {}).get("extra", {})
		parts.append_array(extra.get(model_id, []))
		var base: String = def.get("base", "")
		if not base.is_empty():
			parts.append_array(extra.get(base, []))
	for part: Dictionary in parts:
		var copies: Array = [1.0, -1.0] if part.get("mirror", false) else [1.0]
		for zsign in copies:
			var st: SurfaceTool = tools.get(part.get("material", "hull"))
			if st == null:
				st = SurfaceTool.new()
				st.begin(Mesh.PRIMITIVE_TRIANGLES)
				tools[part.get("material", "hull")] = st
			_add_part(st, part, zsign)
	var meshes := {}
	for material_name: String in tools:
		var st: SurfaceTool = tools[material_name]
		meshes[material_name] = st.commit()
	_mesh_cache[cache_key] = meshes
	return meshes


## A material recoloured by a species style (hull / dark / glass colours).
static func _styled_material(material_name: String, team_color: Color, style_def: Dictionary) -> Material:
	if not style_def.has(material_name):
		return material(material_name, team_color)
	var key := "%s:%s:%s" % [material_name, team_color.to_html(), style_def[material_name]]
	if _material_cache.has(key):
		return _material_cache[key]
	var m: StandardMaterial3D = (material(material_name, team_color) as StandardMaterial3D).duplicate()
	m.albedo_color = Color(style_def[material_name])
	if m.emission_enabled:
		m.emission = Color(style_def[material_name])
	_material_cache[key] = m
	return m


## A model's parts, after those of its "base" model (if any).
static func _parts_of(data: DataRegistry, def: Dictionary, depth: int) -> Array:
	var parts: Array = []
	var base: String = def.get("base", "")
	if not base.is_empty() and depth < 4:
		if data.models.has(base):
			parts.append_array(_parts_of(data, data.models[base], depth + 1))
		else:
			push_warning("ModelFactory: unknown base model '%s'" % base)
	parts.append_array(def.get("parts", []))
	return parts


static func _add_part(st: SurfaceTool, part: Dictionary, zsign: float) -> void:
	var at := _vec3(part.get("at", [0, 0, 0]))
	at.z *= zsign
	var xf := Transform3D(Basis(Vector3.UP, deg_to_rad(float(part.get("rot", 0.0))) * zsign), at)
	if zsign < 0.0:
		xf = xf * Transform3D(Basis.from_scale(Vector3(1, 1, -1)), Vector3.ZERO)
	_center = Vector3.ZERO
	if part.get("type", "") == "hull":
		var c := Vector2.ZERO
		for p: Array in part.get("outline", []):
			c += Vector2(float(p[0]), float(p[1]))
		c /= maxf(1.0, part.get("outline", []).size())
		_center = Vector3(c.x, float(part.get("height", 0.2)) * 0.4, c.y)
	match part.get("type", "box"):
		"hull":
			_hull(st, xf, part, zsign < 0.0)
		"box":
			_box(st, xf, _vec3(part.get("size", [0.2, 0.2, 0.2])), zsign < 0.0)
		"cylinder":
			_cylinder(st, xf, part, false, zsign < 0.0)
		"cone":
			_cylinder(st, xf, part, true, zsign < 0.0)
		"sphere":
			_sphere(st, xf, part, zsign < 0.0)
		"rock":
			_rock(st, xf, float(part.get("radius", 0.4)), int(part.get("seed", 1)), zsign < 0.0)
		_:
			push_warning("ModelFactory: unknown part type '%s'" % part.get("type", ""))


## Adds a flat-shaded triangle whose normal points away from the part centre.
static func _tri(st: SurfaceTool, xf: Transform3D, a: Vector3, b: Vector3, c: Vector3, _flipped: bool) -> void:
	var wa := xf * a
	var wb := xf * b
	var wc := xf * c
	var n := (wb - wa).cross(wc - wa)
	if n.length_squared() < 1e-12:
		return
	n = n.normalized()
	if n.dot((wa + wb + wc) / 3.0 - xf * _center) < 0.0:
		n = -n
	for v in [wa, wb, wc]:
		st.set_normal(n)
		st.add_vertex(v)


static func _quad(st: SurfaceTool, xf: Transform3D, a: Vector3, b: Vector3, c: Vector3, d: Vector3, flipped: bool) -> void:
	_tri(st, xf, a, b, c, flipped)
	_tri(st, xf, a, c, d, flipped)


## Extruded top-view polygon with a bevelled top (and optionally tapered bottom).
static func _hull(st: SurfaceTool, xf: Transform3D, part: Dictionary, flipped: bool) -> void:
	var outline := PackedVector2Array()
	for p: Array in part.get("outline", []):
		outline.append(Vector2(float(p[0]), float(p[1])))
	if Geometry2D.is_polygon_clockwise(outline):
		outline.reverse()
	var h := float(part.get("height", 0.2))
	var bevel := float(part.get("bevel", 0.3))
	var taper := float(part.get("taper", 0.15))
	var centre := Vector2.ZERO
	for p in outline:
		centre += p
	centre /= outline.size()
	var top := PackedVector2Array()
	var bottom := PackedVector2Array()
	for p in outline:
		top.append(p.lerp(centre, bevel))
		bottom.append(p.lerp(centre, taper))
	var mid_y := h * 0.45
	var n := outline.size()
	var tris := Geometry2D.triangulate_polygon(top)
	for i in range(0, tris.size(), 3):
		var a := top[tris[i]]
		var b := top[tris[i + 1]]
		var c := top[tris[i + 2]]
		_tri(st, xf, Vector3(a.x, h, a.y), Vector3(c.x, h, c.y), Vector3(b.x, h, b.y), flipped)
	tris = Geometry2D.triangulate_polygon(bottom)
	for i in range(0, tris.size(), 3):
		var a := bottom[tris[i]]
		var b := bottom[tris[i + 1]]
		var c := bottom[tris[i + 2]]
		_tri(st, xf, Vector3(a.x, 0, a.y), Vector3(b.x, 0, b.y), Vector3(c.x, 0, c.y), flipped)
	for i in n:
		var j := (i + 1) % n
		var o1 := outline[i]
		var o2 := outline[j]
		# Upper bevel (outline at mid height -> inset top) and lower side.
		_quad(st, xf, Vector3(o1.x, mid_y, o1.y), Vector3(o2.x, mid_y, o2.y),
				Vector3(top[j].x, h, top[j].y), Vector3(top[i].x, h, top[i].y), flipped)
		_quad(st, xf, Vector3(bottom[i].x, 0, bottom[i].y), Vector3(bottom[j].x, 0, bottom[j].y),
				Vector3(o2.x, mid_y, o2.y), Vector3(o1.x, mid_y, o1.y), flipped)


static func _box(st: SurfaceTool, xf: Transform3D, size: Vector3, flipped: bool) -> void:
	var h := size / 2.0
	var v := [
		Vector3(-h.x, -h.y, -h.z), Vector3(h.x, -h.y, -h.z), Vector3(h.x, h.y, -h.z), Vector3(-h.x, h.y, -h.z),
		Vector3(-h.x, -h.y, h.z), Vector3(h.x, -h.y, h.z), Vector3(h.x, h.y, h.z), Vector3(-h.x, h.y, h.z),
	]
	for f in [[0, 3, 2, 1], [4, 5, 6, 7], [0, 1, 5, 4], [3, 7, 6, 2], [0, 4, 7, 3], [1, 2, 6, 5]]:
		_quad(st, xf, v[f[0]], v[f[1]], v[f[2]], v[f[3]], flipped)


static func _cylinder(st: SurfaceTool, xf: Transform3D, part: Dictionary, cone: bool, flipped: bool) -> void:
	var r := float(part.get("radius", 0.1))
	var length := float(part.get("length", 0.3))
	var segs := int(part.get("segments", 8))
	var axis: String = part.get("axis", "x")
	# Build along +Y, then rotate onto the requested axis.
	var rot := Basis.IDENTITY
	if axis == "x":
		rot = Basis(Vector3.BACK, -PI / 2.0)
	elif axis == "z":
		rot = Basis(Vector3.RIGHT, PI / 2.0)
	var t := xf * Transform3D(rot, Vector3.ZERO)
	var y0 := -length / 2.0
	var y1 := length / 2.0
	var top_r := 0.0 if cone else r
	for i in segs:
		var a0 := TAU * i / segs
		var a1 := TAU * (i + 1) / segs
		var p0 := Vector3(cos(a0), 0, sin(a0))
		var p1 := Vector3(cos(a1), 0, sin(a1))
		_quad(st, t, p0 * r + Vector3(0, y0, 0), p0 * top_r + Vector3(0, y1, 0),
				p1 * top_r + Vector3(0, y1, 0), p1 * r + Vector3(0, y0, 0), flipped)
		_tri(st, t, Vector3(0, y0, 0), p0 * r + Vector3(0, y0, 0), p1 * r + Vector3(0, y0, 0), flipped)
		if not cone:
			_tri(st, t, Vector3(0, y1, 0), p1 * r + Vector3(0, y1, 0), p0 * r + Vector3(0, y1, 0), flipped)


static func _sphere(st: SurfaceTool, xf: Transform3D, part: Dictionary, flipped: bool) -> void:
	var r := float(part.get("radius", 0.2))
	var squash := _vec3(part.get("squash", [1, 1, 1]))
	var tris := _icosphere(int(part.get("detail", 1)))
	for i in range(0, tris.size(), 3):
		_tri(st, xf, tris[i] * r * squash, tris[i + 1] * r * squash, tris[i + 2] * r * squash, flipped)


static func _rock(st: SurfaceTool, xf: Transform3D, r: float, rock_seed: int, flipped: bool) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = rock_seed
	var bumps := {}
	var tris := _icosphere(1)
	for v in tris:
		var key := v.snapped(Vector3.ONE * 0.001)
		if not bumps.has(key):
			bumps[key] = rng.randf_range(0.7, 1.15)
	var squash := Vector3(rng.randf_range(0.8, 1.2), rng.randf_range(0.55, 0.8), rng.randf_range(0.8, 1.2))
	for i in range(0, tris.size(), 3):
		var a: Vector3 = tris[i] * bumps[tris[i].snapped(Vector3.ONE * 0.001)] * r * squash
		var b: Vector3 = tris[i + 1] * bumps[tris[i + 1].snapped(Vector3.ONE * 0.001)] * r * squash
		var c: Vector3 = tris[i + 2] * bumps[tris[i + 2].snapped(Vector3.ONE * 0.001)] * r * squash
		_tri(st, xf, a, b, c, flipped)


## Unit icosphere as a flat triangle list (outward winding).
static func _icosphere(detail: int) -> Array[Vector3]:
	var t := (1.0 + sqrt(5.0)) / 2.0
	var v: Array[Vector3] = []
	for p in [[-1, t, 0], [1, t, 0], [-1, -t, 0], [1, -t, 0], [0, -1, t], [0, 1, t], [0, -1, -t], [0, 1, -t],
			[t, 0, -1], [t, 0, 1], [-t, 0, -1], [-t, 0, 1]]:
		v.append(Vector3(p[0], p[1], p[2]).normalized())
	var faces := [[0, 11, 5], [0, 5, 1], [0, 1, 7], [0, 7, 10], [0, 10, 11], [1, 5, 9], [5, 11, 4], [11, 10, 2],
			[10, 7, 6], [7, 1, 8], [3, 9, 4], [3, 4, 2], [3, 2, 6], [3, 6, 8], [3, 8, 9], [4, 9, 5], [2, 4, 11],
			[6, 2, 10], [8, 6, 7], [9, 8, 1]]
	var out: Array[Vector3] = []
	for f in faces:
		out.append_array([v[f[0]], v[f[1]], v[f[2]]])
	for d in detail:
		var next: Array[Vector3] = []
		for i in range(0, out.size(), 3):
			var a := out[i]
			var b := out[i + 1]
			var c := out[i + 2]
			var ab := (a + b).normalized()
			var bc := (b + c).normalized()
			var ca := (c + a).normalized()
			next.append_array([a, ab, ca, b, bc, ab, c, ca, bc, ab, bc, ca])
		out = next
	# Godot's front faces are clockwise when seen from outside.
	for i in range(0, out.size(), 3):
		var tmp := out[i + 1]
		out[i + 1] = out[i + 2]
		out[i + 2] = tmp
	return out


static func _vec3(a: Array) -> Vector3:
	return Vector3(float(a[0]), float(a[1]), float(a[2]))
