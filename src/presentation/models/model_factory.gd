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
##   sweep     a tube swept along "path": [[x, y, z, half_width, half_height], ...]
##             (long spines, curved blades, necks, arms). "shape" is the cross
##             section (see SHAPES, or [[a, b], ...] in -1..1), "subdiv": n smooths
##             the path (Catmull-Rom, n steps per segment), "smooth": true shades it
##             smoothly instead of faceted, "closed": true joins the ends. A point
##             with zero width and height is a sharp tip.
##   ring      a torus (or an arc of one): "radius", "tube": [radial, axial] half
##             sizes, "axis", "segments", "shape", "arc" and "start" (degrees, 0 =
##             +x, counter-clockwise seen from +axis), "taper": true sharpens the
##             ends of an arc into points (crescents).
## Any part may also turn: "rot" (degrees around y), "pitch" (around z, nose
## up) and "roll" (around x). Mirrored copies mirror the turn too.
## A part with "spin": degrees per second (around x, through its "pivot", by
## default its "at") is built into a node that turns slowly (habitat rings).
## A model may name a "base" model whose parts come first (e.g. "humanoid").
## "plating": true models get the hull-plating shader and greebles ("greebles":
## false keeps the panels but skips the surface detail; "windows": 0..1 sets how
## many side panels carry lit windows; "panels" scales the panel density).
## Engine parts ("material": "engine") on the x axis also get an exhaust plume
## pointing backwards. Lights: "light_red", "light_green", "beacon" blink;
## "stripe" is a brightly glowing team-color strip.
## Materials: hull, dark, accent (team color), glass, engine (glowing), gold,
## visor (glowing team color), rock, hazard, trim (a second paint colour), glow
## (crystal veins and light strips: a self-lit species colour).
##
## Species: data/strategic/species.json "style" repaints hull / dark / glass /
## trim / glow / engine and may set a "finish" ({material: [metallic, roughness]}).
## model_for() picks a species' own design ("frigate_kesh") when there is one.

const PLUME := preload("res://src/presentation/shaders/engine_plume.gdshader")
const NAV_LIGHT := preload("res://src/presentation/shaders/nav_light.gdshader")
const PLATING := preload("res://src/presentation/shaders/ship_plating.gdshader")
## Materials that get hull plating on models marked "plating": true.
const PLATED := {"hull": 0.14, "dark": 0.0}
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
## lite: small craft (squadrons, escorts) skip engine halos and nav lights: fewer draw calls.
static func build(data: DataRegistry, model_id: String, team_color: Color, style: String = "", lite: bool = false) -> Node3D:
	if data.models.get(model_id, {}).has("mesh"):
		return _build_imported(data.models[model_id], model_id, team_color, lite)
	var root := Node3D.new()
	root.name = model_id
	var style_def: Dictionary = data.species.get(style, {}).get("style", {})
	var groups := _meshes_for(data, model_id, style if not style_def.is_empty() else "")
	var def: Dictionary = data.models.get(model_id, {})
	var plated := bool(def.get("plating", false))
	for group: String in groups:
		var parent := root
		var entry: Dictionary = groups[group]
		if not group.is_empty():
			var spinner := ModelSpinner.new()
			spinner.speed = deg_to_rad(float(entry["spin"]))
			spinner.position = entry["at"]
			root.add_child(spinner)
			parent = spinner
		var meshes: Dictionary = entry["meshes"]
		for material_name: String in meshes:
			if lite and material_name in LIGHTS:
				continue  # blinking nav lights are lost at this size anyway
			var mi := MeshInstance3D.new()
			mi.mesh = meshes[material_name]
			var mat := _styled_material(material_name, team_color, style_def)
			if plated and PLATED.has(material_name) and mat is StandardMaterial3D:
				var windows := float(def.get("windows", PLATED[material_name])) if material_name == "hull" else 0.0
				mat = _plated(mat as StandardMaterial3D, windows, float(def.get("panels", 1.0)))
			mi.material_override = mat
			parent.add_child(mi)
	_add_plumes(root, data, model_id, team_color, style_def, lite)
	return root


## An artist-made model (e.g. a CC0 asset pack) instead of a recipe:
## {"mesh": "res://...obj", "texture": "res://...png", "forward": "+z"|"-z"|"+x"|"-x" (the nose
##  in the source file), "length": model units nose to tail, "metallic", "roughness",
##  "engines": [[x, y, z, radius], ...] (in the normalised model: +X forward, centred)}.
## It is turned and scaled into the same model space as recipes, so squadrons, banking and
## attack styles work unchanged.
static func _build_imported(def: Dictionary, model_id: String, team_color: Color, lite: bool) -> Node3D:
	var root := Node3D.new()
	root.name = model_id
	var mesh := load(def["mesh"]) as Mesh
	if mesh == null:
		push_warning("ModelFactory: can't load mesh '%s'" % def["mesh"])
		return root
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	var key := "imported:%s" % def.get("texture", "")
	if not _material_cache.has(key):
		var mat := StandardMaterial3D.new()
		if def.has("texture"):
			mat.albedo_texture = load(def["texture"])
		mat.metallic = float(def.get("metallic", 0.45))
		mat.roughness = float(def.get("roughness", 0.5))
		mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
		_material_cache[key] = mat
	mi.material_override = _material_cache[key]
	# Turn the source's nose onto +X, centre it and scale it to "length".
	var yaw := 0.0
	match String(def.get("forward", "-z")):
		"-z":
			yaw = -PI / 2.0
		"+z":
			yaw = PI / 2.0
		"-x":
			yaw = PI
	var box := mesh.get_aabb()
	var turned := Basis(Vector3.UP, yaw)
	var long_side := box.size.z if String(def.get("forward", "-z")).ends_with("z") else box.size.x
	var s := float(def.get("length", 1.0)) / maxf(long_side, 0.001)
	var center := box.get_center()
	mi.transform = Transform3D(turned * Basis.from_scale(Vector3.ONE * s), turned * (-center * s))
	root.add_child(mi)
	var tint := team_color.lerp(Color(1.0, 0.6, 0.25), 0.35)
	var slot := 0
	for e: Array in def.get("engines", []):
		var r := float(e[3])
		var plume := MeshInstance3D.new()
		plume.mesh = _plume_mesh(r)
		plume.material_override = _plume_material(tint, slot % 3)
		slot += 1
		plume.rotation_degrees = Vector3(0, 0, 90)
		plume.position = Vector3(float(e[0]) - r * 3.0, float(e[1]), float(e[2]))
		plume.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		root.add_child(plume)
		if not lite:
			var halo := MeshInstance3D.new()
			halo.mesh = _halo_mesh(r)
			halo.material_override = _halo_material(tint)
			halo.position = Vector3(float(e[0]) - r * 0.3, float(e[1]), float(e[2]))
			root.add_child(halo)
	return root


## The model a species flies for a ship class: "<model>_<style>" when the
## content has one (e.g. "frigate_kesh"), else the shared design.
static func model_for(data: DataRegistry, model_id: String, style: String) -> String:
	if style.is_empty():
		return model_id
	var own := "%s_%s" % [model_id, style]
	return own if data.models.has(own) else model_id


## Bounding box of a built model (all its meshes, in model space).
static func bounds(model: Node3D) -> AABB:
	var box := AABB()
	var first := true
	for child in model.get_children():
		var mi := child as MeshInstance3D
		if mi == null or mi.mesh == null or mi.material_override is ShaderMaterial and (mi.material_override as ShaderMaterial).shader == PLUME:
			continue
		var b := mi.transform * mi.mesh.get_aabb()
		box = b if first else box.merge(b)
		first = false
	return box


## Exhaust cones behind every engine part that points along x.
static func _add_plumes(root: Node3D, data: DataRegistry, model_id: String, team_color: Color, style_def: Dictionary = {},
		lite: bool = false) -> void:
	var tint := team_color.lerp(Color(1.0, 0.6, 0.25), 0.35)
	if style_def.has("engine"):
		tint = team_color.lerp(Color(style_def["engine"]), 0.8)
	var def: Dictionary = data.models.get(model_id, {})
	var phase := 0
	for part: Dictionary in _parts_of(data, def, 0):
		if part.get("material", "") != "engine" or part.get("type", "") != "cylinder" or part.get("axis", "x") != "x":
			continue
		var at := _vec3(part.get("at", [0, 0, 0]))
		var r := float(part.get("radius", 0.06))
		var nozzle := at.x - float(part.get("length", 0.03)) / 2.0
		for zsign in ([1.0, -1.0] if part.get("mirror", false) else [1.0]):
			var plume := MeshInstance3D.new()
			var length := r * 6.0
			plume.mesh = _plume_mesh(r)
			plume.material_override = _plume_material(tint, phase % 3)
			phase += 1
			# CylinderMesh runs along +y with the top at +height/2: turn it so
			# the wide end sits on the nozzle and the tip points backwards (-x).
			plume.rotation_degrees = Vector3(0, 0, 90)
			plume.position = Vector3(nozzle - length / 2.0, at.y, at.z * zsign)
			plume.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			root.add_child(plume)
			if lite:
				continue
			var halo := MeshInstance3D.new()
			halo.mesh = _halo_mesh(r)
			halo.material_override = _halo_material(tint)
			halo.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			halo.position = Vector3(nozzle - r * 0.3, at.y, at.z * zsign)
			root.add_child(halo)


## Plume and halo meshes and materials are shared (per radius / tint), so a
## squadron of identical craft costs no extra resources.
static func _plume_mesh(r: float) -> Mesh:
	var key := "plume:%.4f" % r
	if not _mesh_cache.has(key):
		var cone := CylinderMesh.new()
		cone.top_radius = r * 1.05
		cone.bottom_radius = r * 0.15
		cone.height = r * 6.0
		cone.radial_segments = 10
		cone.rings = 1
		cone.cap_top = false
		cone.cap_bottom = false
		_mesh_cache[key] = cone
	return _mesh_cache[key]


static func _halo_mesh(r: float) -> Mesh:
	var key := "halo:%.4f" % r
	if not _mesh_cache.has(key):
		var dot := SphereMesh.new()
		dot.radius = r * 1.6
		dot.height = r * 3.2
		dot.radial_segments = 8
		dot.rings = 4
		_mesh_cache[key] = dot
	return _mesh_cache[key]


static func _plume_material(tint: Color, slot: int) -> Material:
	var key := "plume:%s:%d" % [tint.to_html(), slot]
	if not _material_cache.has(key):
		var mat := ShaderMaterial.new()
		mat.shader = PLUME
		mat.set_shader_parameter("phase", slot * 1.9)
		mat.set_shader_parameter("core_color", tint.lerp(Color.WHITE, 0.6))
		mat.set_shader_parameter("tail_color", tint)
		_material_cache[key] = mat
	return _material_cache[key]


static func _halo_material(tint: Color) -> Material:
	var key := "halo:%s" % tint.to_html()
	if not _material_cache.has(key):
		var glow := StandardMaterial3D.new()
		glow.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		glow.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
		glow.albedo_color = tint * 0.3
		glow.cull_mode = BaseMaterial3D.CULL_DISABLED
		_material_cache[key] = glow
	return _material_cache[key]


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
			m.albedo_color = Color("4d453f")
			m.roughness = 1.0
			m.metallic = 0.0
		"hazard":
			m.albedo_color = Color("d9b026")
			m.roughness = 0.7
		"trim":
			m.albedo_color = Color("d8dadf")
			m.metallic = 0.3
			m.roughness = 0.45
		"glow":
			m.albedo_color = Color("bfe6ff")
			m.emission_enabled = true
			m.emission = Color("9fd8ff")
			m.emission_energy_multiplier = 1.6
		_:
			m.albedo_color = Color.MAGENTA
	_material_cache[key] = m
	return m


## Meshes per material for a model (geometry is shared by every team), in
## groups: "" is the hull; each spinning part gets its own group
## {"meshes": {material: Mesh}, "spin": degrees per second, "at": Vector3}.
static func _meshes_for(data: DataRegistry, model_id: String, style: String = "") -> Dictionary:
	var cache_key := model_id + "@" + style
	if _mesh_cache.has(cache_key):
		return _mesh_cache[cache_key]
	var def: Dictionary = data.models.get(model_id, {})
	if def.is_empty():
		push_warning("ModelFactory: unknown model '%s'" % model_id)
		def = {"parts": [{"type": "box", "size": [0.6, 0.3, 0.4], "material": "accent"}]}
	var parts := _parts_of(data, def, 0)
	if def.get("plating", false) and def.get("greebles", true):
		parts.append_array(_greebles(parts, absi(hash(model_id))))
	if not style.is_empty():
		var extra: Dictionary = data.species.get(style, {}).get("style", {}).get("extra", {})
		parts.append_array(extra.get(model_id, []))
		var base: String = def.get("base", "")
		if not base.is_empty():
			parts.append_array(extra.get(base, []))
	var group_tools := {"": {}}  # group -> material name -> SurfaceTool
	var groups := {"": {"spin": 0.0, "at": Vector3.ZERO}}
	for i in parts.size():
		var part: Dictionary = parts[i]
		var group := ""
		if part.has("spin"):
			# Parts with the same speed and pivot turn together on one node.
			var at := _vec3(part.get("at", [0, 0, 0]))
			var pivot := _vec3(part.get("pivot", part.get("at", [0, 0, 0])))
			group = "spin:%s:%s" % [part["spin"], pivot]
			if not groups.has(group):
				groups[group] = {"spin": float(part["spin"]), "at": pivot}
				group_tools[group] = {}
			part = part.duplicate()
			var local := at - pivot
			part["at"] = [local.x, local.y, local.z]
		var tools: Dictionary = group_tools[group]
		var copies: Array = [1.0, -1.0] if part.get("mirror", false) else [1.0]
		for zsign in copies:
			var material_name: String = part.get("material", "hull")
			var st: SurfaceTool = tools.get(material_name)
			if st == null:
				st = SurfaceTool.new()
				st.begin(Mesh.PRIMITIVE_TRIANGLES)
				tools[material_name] = st
			_add_part(st, part, zsign)
	var out := {}
	for group: String in group_tools:
		var meshes := {}
		for material_name: String in group_tools[group]:
			var st: SurfaceTool = group_tools[group][material_name]
			meshes[material_name] = st.commit()
		var entry: Dictionary = groups[group]
		entry["meshes"] = meshes
		out[group] = entry
	_mesh_cache[cache_key] = out
	return out


## A material recoloured by a species style: hull / dark / glass / trim / glow /
## engine colours, plus an optional "finish" {material: [metallic, roughness]}.
static func _styled_material(material_name: String, team_color: Color, style_def: Dictionary) -> Material:
	var finish: Array = style_def.get("finish", {}).get(material_name, [])
	if not style_def.has(material_name) and finish.is_empty():
		return material(material_name, team_color)
	var key := "%s:%s:%s:%s" % [material_name, team_color.to_html(), style_def.get(material_name, ""), str(finish)]
	if _material_cache.has(key):
		return _material_cache[key]
	var base := material(material_name, team_color) as StandardMaterial3D
	if base == null:
		return material(material_name, team_color)
	var m: StandardMaterial3D = base.duplicate()
	if style_def.has(material_name):
		var c := Color(style_def[material_name])
		m.albedo_color = c.lightened(0.25) if material_name in ["glow", "engine"] else c
		if m.emission_enabled:
			m.emission = c
	if finish.size() >= 2:
		m.metallic = float(finish[0])
		m.roughness = float(finish[1])
	_material_cache[key] = m
	return m


## Surface detail for plated ships: small blocks (vents, sensor housings,
## conduits) scattered over the top faces of the main hull parts, so the
## silhouettes read as machinery rather than smooth toys. Deterministic per model.
static func _greebles(parts: Array, rng_seed: int) -> Array:
	var rng := RandomNumberGenerator.new()
	rng.seed = rng_seed
	var out: Array = []
	for part: Dictionary in parts:
		if part.get("type", "") != "hull" or part.get("material", "") != "hull" or float(part.get("rot", 0.0)) != 0.0 \
				or float(part.get("roll", 0.0)) != 0.0 or float(part.get("pitch", 0.0)) != 0.0:
			continue
		var h := float(part.get("height", 0.2))
		if h < 0.1:
			continue
		var outline := PackedVector2Array()
		var centre := Vector2.ZERO
		for p: Array in part.get("outline", []):
			outline.append(Vector2(float(p[0]), float(p[1])))
			centre += Vector2(float(p[0]), float(p[1]))
		if outline.size() < 3:
			continue
		centre /= outline.size()
		var top := PackedVector2Array()
		for p in outline:
			top.append(p.lerp(centre, float(part.get("bevel", 0.3)) + 0.08))
		var lo := Vector2(INF, INF)
		var hi := Vector2(-INF, -INF)
		for p in top:
			lo = Vector2(minf(lo.x, p.x), minf(lo.y, p.y))
			hi = Vector2(maxf(hi.x, p.x), maxf(hi.y, p.y))
		var area := (hi.x - lo.x) * (hi.y - lo.y)
		var count := clampi(int(area * 60.0), 3, 14)
		var at := _vec3(part.get("at", [0, 0, 0]))
		var placed := 0
		for attempt in count * 6:
			if placed >= count:
				break
			var q := Vector2(rng.randf_range(lo.x, hi.x), rng.randf_range(lo.y, hi.y))
			if not Geometry2D.is_point_in_polygon(q, top):
				continue
			var size := Vector3(rng.randf_range(0.04, 0.12), rng.randf_range(0.012, 0.035), rng.randf_range(0.025, 0.07))
			if rng.randf() < 0.3:
				size = Vector3(size.z, size.y, size.x)
			out.append({"type": "box", "size": [size.x, size.y, size.z],
				"at": [at.x + q.x, at.y + h + size.y / 2.0 - 0.004, at.z + q.y],
				"material": "dark" if rng.randf() < 0.7 else "hull", "mirror": part.get("mirror", false)})
			placed += 1
	return out


## The plating shader carrying a standard material's colour and finish.
static func _plated(base: StandardMaterial3D, windows: float, panels: float = 1.0) -> ShaderMaterial:
	var key := "plated:%s:%s:%s:%s:%s:%s" % [base.albedo_color.to_html(), base.emission.to_html() if base.emission_enabled else "-",
			windows, panels, base.metallic, base.roughness]
	if _material_cache.has(key):
		return _material_cache[key]
	var m := ShaderMaterial.new()
	m.shader = PLATING
	m.set_shader_parameter("albedo", base.albedo_color)
	m.set_shader_parameter("metallic", base.metallic)
	m.set_shader_parameter("roughness", base.roughness)
	if base.emission_enabled:
		m.set_shader_parameter("emission_color", base.emission)
		m.set_shader_parameter("emission_energy", base.emission_energy_multiplier)
	m.set_shader_parameter("window_density", windows)
	m.set_shader_parameter("panel_scale", 5.5 * panels)
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
	var basis := Basis(Vector3.UP, deg_to_rad(float(part.get("rot", 0.0)))) \
			* Basis(Vector3.BACK, deg_to_rad(float(part.get("pitch", 0.0)))) \
			* Basis(Vector3.RIGHT, deg_to_rad(float(part.get("roll", 0.0))))
	var xf := Transform3D(basis, at)
	if zsign < 0.0:
		# The mirrored copy is the reflection of the whole part across the XY plane.
		xf = Transform3D(Basis.from_scale(Vector3(1, 1, -1)), Vector3.ZERO) * xf
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
		"sweep":
			_sweep_part(st, xf, part)
		"ring":
			_ring(st, xf, part)
		_:
			push_warning("ModelFactory: unknown part type '%s'" % part.get("type", ""))


## Adds a flat-shaded triangle whose normal points away from the part centre.
static func _tri(st: SurfaceTool, xf: Transform3D, a: Vector3, b: Vector3, c: Vector3, _flipped: bool) -> void:
	var wa := xf * a
	var wb := xf * b
	var wc := xf * c
	var raw := (wb - wa).cross(wc - wa)
	if raw.length_squared() < 1e-12:
		return
	var n := raw.normalized()
	if n.dot((wa + wb + wc) / 3.0 - xf * _center) < 0.0:
		n = -n
	# Wind the triangle to match its normal (Godot's front faces are clockwise
	# seen from outside), so back-face culling and two-sided lighting agree.
	var order := [wa, wc, wb] if raw.dot(n) > 0.0 else [wa, wb, wc]
	for v in order:
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


## Cross sections for sweeps and rings: (side, up) pairs in -1..1.
const SHAPES := {
	"diamond": [[1, 0], [0, 1], [-1, 0], [0, -1]],
	"box": [[1, 1], [-1, 1], [-1, -1], [1, -1]],
	"oct": [[1, 0.45], [0.45, 1], [-0.45, 1], [-1, 0.45], [-1, -0.45], [-0.45, -1], [0.45, -1], [1, -0.45]],
	"hex": [[1, 0], [0.5, 0.87], [-0.5, 0.87], [-1, 0], [-0.5, -0.87], [0.5, -0.87]],
	"lens": [[1, 0], [0.7, 0.62], [0, 1], [-0.7, 0.62], [-1, 0], [-0.7, -0.62], [0, -1], [0.7, -0.62]],
	"blade": [[1, 0], [0.35, 1], [-0.35, 1], [-1, 0], [-0.35, -1], [0.35, -1]],
	"tri": [[0, 1], [-0.87, -0.5], [0.87, -0.5]],
	"keel": [[1, 0.55], [0.45, 1], [-0.45, 1], [-1, 0.55], [-0.35, -0.45], [0, -1], [0.35, -0.45]],
	"wedge": [[1, 1], [-1, 1], [-0.55, -0.6], [0, -1], [0.55, -0.6]],
}


static func _shape(spec: Variant) -> Array[Vector2]:
	var pts: Array = []
	if spec is Array:
		pts = spec
	elif str(spec) == "round":
		for i in 12:
			pts.append([cos(TAU * i / 12.0), sin(TAU * i / 12.0)])
	else:
		pts = SHAPES.get(str(spec), SHAPES["oct"])
	var out: Array[Vector2] = []
	for p: Array in pts:
		out.append(Vector2(float(p[0]), float(p[1])))
	return out


static func _sweep_part(st: SurfaceTool, xf: Transform3D, part: Dictionary) -> void:
	var pts: Array[Vector3] = []
	var sizes: Array[Vector2] = []
	for p: Array in part.get("path", []):
		pts.append(Vector3(float(p[0]), float(p[1]), float(p[2])))
		var w := float(p[3]) if p.size() > 3 else 0.05
		var h := float(p[4]) if p.size() > 4 else w
		sizes.append(Vector2(w, h))
	var closed := bool(part.get("closed", false))
	var subdiv := int(part.get("subdiv", 0))
	if subdiv > 1 and pts.size() > 2:
		var sp: Array[Vector3] = []
		var ss: Array[Vector2] = []
		var n := pts.size()
		var segs := n if closed else n - 1
		for i in segs:
			var p0 := pts[(i - 1 + n) % n] if closed or i > 0 else pts[0]
			var p1 := pts[i]
			var p2 := pts[(i + 1) % n]
			var p3 := pts[(i + 2) % n] if closed or i + 2 < n else pts[n - 1]
			for k in subdiv:
				var t := float(k) / subdiv
				sp.append(_catmull_rom(p0, p1, p2, p3, t))
				ss.append(sizes[i].lerp(sizes[(i + 1) % n], t))
		if not closed:
			sp.append(pts[n - 1])
			ss.append(sizes[n - 1])
		pts = sp
		sizes = ss
	var ref := Vector3.UP
	match str(part.get("ref", "up")):
		"x":
			ref = Vector3.RIGHT
		"z":
			ref = Vector3.BACK
	_sweep(st, xf, pts, sizes, _shape(part.get("shape", "oct")), closed, bool(part.get("smooth", false)), ref)


static func _ring(st: SurfaceTool, xf: Transform3D, part: Dictionary) -> void:
	var r := float(part.get("radius", 0.4))
	var tube: Array = part.get("tube", [0.04, 0.04])
	var size := Vector2(float(tube[0]), float(tube[1]))
	var arc := float(part.get("arc", 360.0))
	var start := deg_to_rad(float(part.get("start", 0.0)))
	var segs := int(part.get("segments", 16))
	var closed := arc >= 359.9
	var taper := bool(part.get("taper", false))
	var axis: String = part.get("axis", "y")
	var ref := Vector3.UP
	if axis == "x":
		ref = Vector3.RIGHT
	elif axis == "z":
		ref = Vector3.BACK
	var pts: Array[Vector3] = []
	var sizes: Array[Vector2] = []
	var count := segs if closed else segs + 1
	for k in count:
		var f := float(k) / segs
		var a := start + deg_to_rad(arc) * f
		# Angle 0 is +x (+y for rings around x), counter-clockwise seen from +axis.
		match axis:
			"x":
				pts.append(Vector3(0, r * cos(a), -r * sin(a)))
			"z":
				pts.append(Vector3(r * cos(a), r * sin(a), 0))
			_:
				pts.append(Vector3(r * cos(a), 0, -r * sin(a)))
		var s := size
		if taper and not closed:
			s = size * maxf(pow(sin(PI * f), 0.7), 0.0)
		sizes.append(s)
	_sweep(st, xf, pts, sizes, _shape(part.get("shape", "box")), closed, bool(part.get("smooth", false)), ref)


## Sweeps a cross section along pts. Section frame: side = ref x tangent,
## up = tangent x side; sizes are (side, up) half extents per point.
static func _sweep(st: SurfaceTool, xf: Transform3D, pts: Array[Vector3], sizes: Array[Vector2], shape: Array[Vector2],
		closed: bool, smooth: bool, ref: Vector3) -> void:
	var n := pts.size()
	if n < 2:
		return
	var rings: Array = []
	var normals: Array = []
	for i in n:
		var t: Vector3
		if closed:
			t = pts[(i + 1) % n] - pts[(i - 1 + n) % n]
		else:
			t = pts[mini(i + 1, n - 1)] - pts[maxi(i - 1, 0)]
		t = t.normalized()
		var r := ref
		if absf(t.dot(r)) > 0.98:
			r = Vector3.RIGHT if absf(t.dot(Vector3.RIGHT)) < 0.9 else Vector3.BACK
		var side := r.cross(t).normalized()
		var up := t.cross(side).normalized()
		var w := sizes[i].x
		var h := sizes[i].y
		var ring: Array[Vector3] = []
		var nrm: Array[Vector3] = []
		for q in shape:
			ring.append(pts[i] + side * q.x * w + up * q.y * h)
			if w > 0.0005 and h > 0.0005:
				nrm.append((side * q.x * h + up * q.y * w).normalized())
			else:
				nrm.append((side * q.x + up * q.y).normalized())
		rings.append(ring)
		normals.append(nrm)
	var m := shape.size()
	var segs := n if closed else n - 1
	for i in segs:
		var j := (i + 1) % n
		_center = (pts[i] + pts[j]) / 2.0
		var ra: Array[Vector3] = rings[i]
		var rb: Array[Vector3] = rings[j]
		var na: Array[Vector3] = normals[i]
		var nb: Array[Vector3] = normals[j]
		for k in m:
			var l := (k + 1) % m
			if smooth:
				_tri_n(st, xf, ra[k], ra[l], rb[l], na[k], na[l], nb[l])
				_tri_n(st, xf, ra[k], rb[l], rb[k], na[k], nb[l], nb[k])
			else:
				_quad(st, xf, ra[k], ra[l], rb[l], rb[k], false)
	if closed:
		return
	for end: int in [0, n - 1]:
		if sizes[end].x < 0.0005 or sizes[end].y < 0.0005:
			continue
		var inward := (pts[1] - pts[0]) if end == 0 else (pts[n - 2] - pts[n - 1])
		_center = pts[end] + inward.normalized() * 0.05
		var ring: Array[Vector3] = rings[end]
		for k in m:
			_tri(st, xf, pts[end], ring[k], ring[(k + 1) % m], false)


## A smooth-shaded triangle with explicit (model space) vertex normals.
static func _tri_n(st: SurfaceTool, xf: Transform3D, a: Vector3, b: Vector3, c: Vector3,
		na: Vector3, nb: Vector3, nc: Vector3) -> void:
	var wa := xf * a
	var wb := xf * b
	var wc := xf * c
	if (wb - wa).cross(wc - wa).length_squared() < 1e-12:
		return
	var nbasis := xf.basis.inverse().transposed()
	var n1 := (nbasis * na).normalized()
	var n2 := (nbasis * nb).normalized()
	var n3 := (nbasis * nc).normalized()
	if (wb - wa).cross(wc - wa).dot(n1 + n2 + n3) > 0.0:
		# Clockwise seen from outside (see _tri).
		var tw := wb
		wb = wc
		wc = tw
		var tn := n2
		n2 = n3
		n3 = tn
	st.set_normal(n1)
	st.add_vertex(wa)
	st.set_normal(n2)
	st.add_vertex(wb)
	st.set_normal(n3)
	st.add_vertex(wc)


static func _catmull_rom(p0: Vector3, p1: Vector3, p2: Vector3, p3: Vector3, t: float) -> Vector3:
	return 0.5 * ((2.0 * p1) + (-p0 + p2) * t + (2.0 * p0 - 5.0 * p1 + 4.0 * p2 - p3) * t * t
			+ (-p0 + 3.0 * p1 - 3.0 * p2 + p3) * t * t * t)


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
