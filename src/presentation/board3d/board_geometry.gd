class_name BoardGeometry
extends RefCounted
## Shared helpers for 2.5D boards: lighting, materials, extruded cell tiles
## and dynamic overlay geometry (highlights, paths, fog). Overlay geometry is
## collected in a buffer {"v": [Vector3], "c": [Color]} and committed to a
## mesh only when non-empty.


## WorldEnvironment (nebula canvas behind the 3D scene) plus key and rim lights.
static func build_environment(parent: Node3D) -> void:
	var env_node := WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_CANVAS
	env.background_canvas_max_layer = -1
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.32, 0.38, 0.55)
	env.ambient_light_energy = 0.75
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.glow_enabled = true
	env.glow_intensity = 0.9
	env.glow_bloom = 0.15
	env_node.environment = env
	parent.add_child(env_node)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-55, -35, 0)
	sun.light_energy = 1.25
	sun.light_color = Color(1.0, 0.96, 0.9)
	sun.shadow_enabled = true
	parent.add_child(sun)
	var rim := DirectionalLight3D.new()
	rim.rotation_degrees = Vector3(-25, 150, 0)
	rim.light_energy = 0.35
	rim.light_color = Color(0.5, 0.7, 1.0)
	parent.add_child(rim)


static func mesh_node(parent: Node3D, material: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.material_override = material
	parent.add_child(mi)
	return mi


## Unshaded, vertex-colored, alpha-blended (highlights, fog, lines).
static func overlay_material() -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.vertex_color_use_as_albedo = true
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	return m


static func flat_material(color: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = color
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	return m


static func additive_material(color: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	m.albedo_color = color
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	return m


## Lit, vertex-colored material for generated tiles and props.
static func tile_material(transparent: bool) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.vertex_color_use_as_albedo = true
	m.roughness = 0.25 if transparent else 0.6
	m.metallic = 0.5 if transparent else 0.35
	if transparent:
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	return m


# --- Solid geometry (SurfaceTool) ---------------------------------------------

## Extruded polygon (y0..y1) with explicit normals and vertex colors.
static func prism(st: SurfaceTool, poly: PackedVector3Array, y0: float, y1: float, side: Color, top: Color) -> void:
	var center := Vector3.ZERO
	for p in poly:
		center += p
	center /= poly.size()
	for i in range(1, poly.size() - 1):
		for v in [poly[0], poly[i], poly[i + 1]]:
			st.set_normal(Vector3.UP)
			st.set_color(top)
			st.add_vertex(v + Vector3(0, y1, 0))
	for i in poly.size():
		var a := poly[i]
		var b := poly[(i + 1) % poly.size()]
		var n := ((a + b) / 2.0 - center).normalized()
		for v in [a + Vector3(0, y0, 0), b + Vector3(0, y0, 0), b + Vector3(0, y1, 0),
				a + Vector3(0, y0, 0), b + Vector3(0, y1, 0), a + Vector3(0, y1, 0)]:
			st.set_normal(n)
			st.set_color(side)
			st.add_vertex(v)


static func box(st: SurfaceTool, center: Vector3, size: Vector3, color: Color) -> void:
	var h := size / 2.0
	var poly := PackedVector3Array([center + Vector3(-h.x, 0, -h.z), center + Vector3(h.x, 0, -h.z),
			center + Vector3(h.x, 0, h.z), center + Vector3(-h.x, 0, h.z)])
	prism(st, poly, -h.y, h.y, color.darkened(0.25), color)


# --- Overlay buffers ----------------------------------------------------------

static func buffer() -> Dictionary:
	return {"v": [], "c": []}


static func fill_poly(buf: Dictionary, poly: PackedVector3Array, color: Color, y: float = NAN) -> void:
	for i in range(1, poly.size() - 1):
		for v in [poly[0], poly[i], poly[i + 1]]:
			buf["c"].append(color)
			buf["v"].append(Vector3(v.x, v.y if is_nan(y) else y, v.z))


static func ribbon(buf: Dictionary, a: Vector3, b: Vector3, width: float, color: Color) -> void:
	var side := (b - a).cross(Vector3.UP).normalized() * width / 2.0
	for v in [a - side, a + side, b + side, a - side, b + side, b - side]:
		buf["c"].append(color)
		buf["v"].append(v)


static func outline(buf: Dictionary, poly: PackedVector3Array, y: float, width: float, color: Color) -> void:
	for i in poly.size():
		var a := poly[i]
		var b := poly[(i + 1) % poly.size()]
		ribbon(buf, Vector3(a.x, y, a.z), Vector3(b.x, y, b.z), width, color)


static func disc(center: Vector3, radius: float, segments: int = 12) -> PackedVector3Array:
	var out := PackedVector3Array()
	for i in segments:
		out.append(center + Vector3(cos(TAU * i / segments), 0, sin(TAU * i / segments)) * radius)
	return out


## Mesh from a buffer, or null when there is nothing to draw.
static func commit(buf: Dictionary) -> Mesh:
	var verts: Array = buf["v"]
	if verts.is_empty():
		return null
	var colors: Array = buf["c"]
	var mesh := ImmediateMesh.new()
	mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in verts.size():
		mesh.surface_set_color(colors[i])
		mesh.surface_add_vertex(verts[i])
	mesh.surface_end()
	return mesh


## Thin grid lines along every cell edge.
static func grid_lines(cell_polys: Array, y: float) -> Mesh:
	var im := ImmediateMesh.new()
	im.surface_begin(Mesh.PRIMITIVE_LINES)
	for poly: PackedVector3Array in cell_polys:
		for i in poly.size():
			im.surface_add_vertex(poly[i] + Vector3(0, y, 0))
			im.surface_add_vertex(poly[(i + 1) % poly.size()] + Vector3(0, y, 0))
	im.surface_end()
	return im


static func line_material() -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = Color(0.45, 0.7, 0.95, 0.35)
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	return m


## A cluster of faint additive glows (nebula terrain).
static func nebula_puffs(parent: Node3D, center: Vector3, color: Color, rng_seed: int) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = rng_seed
	for i in 4:
		var puff := MeshInstance3D.new()
		var sphere := SphereMesh.new()
		sphere.radius = rng.randf_range(0.35, 0.6)
		sphere.height = sphere.radius * 0.8
		puff.mesh = sphere
		puff.material_override = additive_material(color.lightened(0.3) * 0.12)
		puff.position = center + Vector3(rng.randf_range(-0.5, 0.5), rng.randf_range(0.1, 0.6), rng.randf_range(-0.5, 0.5))
		parent.add_child(puff)


## One or two faceted boulders scattered over a cell (asteroid terrain).
static func rocks(parent: Node3D, center: Vector3, rng_seed: int, scale: float = 1.0) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = rng_seed
	for i in 2:
		var r := (rng.randf_range(0.42, 0.62) if i == 0 else rng.randf_range(0.2, 0.3)) * scale
		var rock := ModelFactory.build_rock(rng.randi(), r)
		rock.position = center + Vector3(rng.randf_range(-0.3, 0.3), rng.randf_range(0.15, 0.4), rng.randf_range(-0.3, 0.3)) * scale
		rock.rotation = Vector3(rng.randf() * TAU, rng.randf() * TAU, rng.randf() * TAU)
		parent.add_child(rock)
