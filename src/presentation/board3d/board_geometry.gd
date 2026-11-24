class_name BoardGeometry
extends RefCounted
## Shared helpers for 2.5D boards: lighting, materials, extruded cell tiles
## and dynamic overlay geometry (highlights, paths, fog). Overlay geometry is
## collected in a buffer {"v": [Vector3], "c": [Color]} and committed to a
## mesh only when non-empty.


const SPACE_SKY := preload("res://src/presentation/shaders/space_sky.gdshader")


## True when the game runs on the Forward+ renderer (desktop): boards then use
## the high-quality look (sky, ambient occlusion, soft shadows, volumetric fog).
## The Compatibility renderer (web, older GPUs) keeps the classic look.
static func high_quality() -> bool:
	GameSettings.ensure_loaded()
	return supports_high_quality() and GameSettings.battle_look == "high"


## Whether this build runs the Forward+ renderer at all (desktop; not the web build).
static func supports_high_quality() -> bool:
	return RenderingServer.get_current_rendering_method() == "forward_plus"


## WorldEnvironment (nebula canvas behind the 3D scene) plus key and rim lights.
## hq: the high-quality look (see high_quality()); only honoured on Forward+.
## kind: "battle" or "galaxy" (no global dust, a long fog range for the zoomed-out map:
## only FogVolumes such as nebulae add fog there).
## mood: the station deck's look for kind "deck" on the high-quality path (DeckMood).
static func build_environment(parent: Node3D, hq: bool = false, kind: String = "battle", mood: DeckMood = null) -> Environment:
	if hq and high_quality():
		if kind == "deck":
			return _build_deck_environment(parent, mood if mood != null else DeckMood.new())
		return _build_hq_environment(parent, kind)
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
	if kind == "solar":
		# The sun in the middle of the map does most of the lighting (SolarSystem3D).
		sun.light_energy = 0.45
		env.ambient_light_energy = 0.6
	if kind == "deck" and supports_high_quality():
		# Forward+ lights the same scene much brighter than the compatibility renderer the
		# deck was tuned on: dim it to match (room lights and the glow strips carry it).
		env.ambient_light_energy = 0.4
		env.tonemap_exposure = 0.8
		sun.light_energy = 0.6
	parent.add_child(sun)
	var rim := DirectionalLight3D.new()
	rim.rotation_degrees = Vector3(-25, 150, 0)
	rim.light_energy = 0.35
	rim.light_color = Color(0.5, 0.7, 1.0)
	parent.add_child(rim)
	return env


## Forward+ look: a real space sky that also lights and reflects off the hulls,
## AgX tone mapping, ambient occlusion, HDR bloom, a whisper of volumetric dust,
## and a sun with soft shadows.
static func _build_hq_environment(parent: Node3D, kind: String = "battle") -> Environment:
	var env_node := WorldEnvironment.new()
	var env := Environment.new()
	var sky := Sky.new()
	var sky_mat := ShaderMaterial.new()
	sky_mat.shader = SPACE_SKY
	sky_mat.set_shader_parameter("seed", float(absi(parent.get_instance_id()) % 97) * 0.13)
	sky.sky_material = sky_mat
	sky.radiance_size = Sky.RADIANCE_SIZE_256
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_sky_contribution = 1.0
	env.ambient_light_energy = 2.2
	env.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	env.tonemap_mode = Environment.TONE_MAPPER_AGX
	env.tonemap_exposure = 1.15
	env.ssao_enabled = true
	env.ssao_radius = 0.6
	env.ssao_intensity = 1.6
	env.ssil_enabled = false  # indirect light: costly, little gain on a mostly dark board
	env.ssil_radius = 1.5
	env.ssil_intensity = 0.6
	env.glow_enabled = true
	env.glow_intensity = 0.7
	env.glow_bloom = 0.06
	env.glow_hdr_threshold = 1.1
	env.glow_blend_mode = Environment.GLOW_BLEND_MODE_SOFTLIGHT
	env.volumetric_fog_enabled = true
	env.volumetric_fog_density = 0.004
	env.volumetric_fog_albedo = Color(0.4, 0.5, 0.8)
	env.volumetric_fog_anisotropy = 0.6
	env.volumetric_fog_sky_affect = 0.0
	env.adjustment_enabled = true
	env.adjustment_saturation = 1.12
	env.adjustment_contrast = 1.05
	if kind == "system":
		# A star system up close: the star does the lighting (worlds get a real night side).
		env.volumetric_fog_enabled = false
		env.ambient_light_energy = 0.55
		env.ssao_radius = 0.25
		env.glow_intensity = 0.8
		env.glow_hdr_threshold = 1.2
	if kind == "galaxy" or kind == "solar":
		env.volumetric_fog_density = 0.0
		env.volumetric_fog_length = 160.0
		env.volumetric_fog_detail_spread = 1.5
		env.volumetric_fog_ambient_inject = 0.4
		env.ssao_radius = 0.35
		env.glow_intensity = 0.9
		env.glow_bloom = 0.1
	env_node.environment = env
	parent.add_child(env_node)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-50, -35, 0)
	sun.light_energy = 2.4
	sun.light_color = Color(1.0, 0.95, 0.86)
	sun.light_angular_distance = 1.2  # soft shadow edges
	sun.shadow_enabled = true
	sun.shadow_blur = 1.5
	sun.directional_shadow_max_distance = 60.0
	sun.light_volumetric_fog_energy = 1.5
	if kind == "system":
		sun.light_energy = 0.25  # the star's own light does the work
		sun.shadow_enabled = false
	if kind == "solar":
		# A system-scale map: the sun in the middle of the board lights it (SolarSystem3D).
		env.ambient_light_energy = 0.9
		sun.light_energy = 0.35
		sun.shadow_enabled = false
	parent.add_child(sun)
	var rim := DirectionalLight3D.new()
	rim.rotation_degrees = Vector3(-20, 150, 0)
	rim.light_energy = 0.6
	rim.light_color = Color(0.45, 0.65, 1.0)
	parent.add_child(rim)
	return env


## Forward+ station interior (XCOM-like): a dark void around the deck, low tinted
## ambient so the room lamps (DeckKit) do the lighting, AgX tone mapping, strong
## contact shadows (SSAO) and a touch of bounce light (SSIL), bloom on the light
## strips and screens, volumetric fog for the haze volume, and a per-map colour
## grade (DeckMood).
static func _build_deck_environment(parent: Node3D, mood: DeckMood) -> Environment:
	var env_node := WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = mood.shadows * 0.35
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = mood.ambient
	env.ambient_light_energy = mood.ambient_energy
	env.reflected_light_source = Environment.REFLECTION_SOURCE_BG
	env.tonemap_mode = Environment.TONE_MAPPER_AGX
	env.tonemap_exposure = 0.9 * mood.exposure
	env.ssao_enabled = true
	env.ssao_radius = 1.1
	env.ssao_intensity = 3.2
	env.ssao_power = 1.7
	env.ssao_detail = 0.6
	env.ssao_horizon = 0.08
	env.ssao_light_affect = 0.15
	env.ssil_enabled = true
	env.ssil_radius = 2.5
	env.ssil_intensity = 0.5
	env.ssil_normal_rejection = 1.0
	env.glow_enabled = true
	env.glow_intensity = 0.85
	env.glow_strength = 1.0
	env.glow_bloom = 0.02
	env.glow_hdr_threshold = 0.9
	env.glow_blend_mode = Environment.GLOW_BLEND_MODE_SCREEN
	env.set_glow_level(0, 0.0)
	env.set_glow_level(1, 1.0)
	env.set_glow_level(2, 0.8)
	env.set_glow_level(3, 0.6)
	env.set_glow_level(4, 0.3)
	env.volumetric_fog_enabled = true
	env.volumetric_fog_density = 0.0  # only the deck's haze volume (DeckKit)
	env.volumetric_fog_albedo = mood.haze
	env.volumetric_fog_length = 48.0
	env.volumetric_fog_detail_spread = 1.6
	env.volumetric_fog_anisotropy = 0.45
	env.volumetric_fog_ambient_inject = 0.0
	env.volumetric_fog_sky_affect = 0.0
	env.adjustment_enabled = true
	env.adjustment_saturation = 1.08 * mood.saturation
	env.adjustment_contrast = 1.06
	env.adjustment_color_correction = mood.grade_texture()
	env_node.environment = env
	parent.add_child(env_node)
	# A faint cool key from above so forms read even between the lamps (no shadows:
	# the lamps cast those), and a rim from behind to outline the people.
	var key := DirectionalLight3D.new()
	key.rotation_degrees = Vector3(-62, -30, 0)
	key.light_energy = 0.08
	key.light_color = mood.ambient.lerp(Color.WHITE, 0.6)
	key.light_volumetric_fog_energy = 0.0
	parent.add_child(key)
	var rim := DirectionalLight3D.new()
	rim.rotation_degrees = Vector3(-28, 160, 0)
	rim.light_energy = 0.3
	rim.light_color = mood.accent.lerp(Color.WHITE, 0.5)
	rim.light_volumetric_fog_energy = 0.0
	rim.light_specular = 0.0
	parent.add_child(rim)
	return env


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
	if transparent and high_quality():
		# With a real sky the glass would mirror it: keep tiles a matte tint.
		m.metallic = 0.0
		m.roughness = 1.0
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
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


static func line_material(alpha: float = 0.11) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = Color(0.45, 0.7, 0.95, alpha)
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	return m


## A cluster of faint additive glows (nebula terrain).
## height: how far up the puffs billow (battles use a taller column than the galaxy map).
static func nebula_puffs(parent: Node3D, center: Vector3, color: Color, rng_seed: int, height: float = 0.6) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = rng_seed
	var count := 4 if height <= 0.6 else 7
	for i in count:
		var puff := MeshInstance3D.new()
		var sphere := SphereMesh.new()
		sphere.radius = rng.randf_range(0.35, 0.6)
		sphere.height = sphere.radius * 0.8
		puff.mesh = sphere
		puff.material_override = additive_material(color.lightened(0.3) * (0.12 if height <= 0.6 else 0.09))
		puff.position = center + Vector3(rng.randf_range(-0.5, 0.5), rng.randf_range(0.1, height), rng.randf_range(-0.5, 0.5))
		parent.add_child(puff)


## One or two faceted boulders scattered over a cell (asteroid terrain).
## floating: battle maps stack 3-4 slowly tumbling rocks at different
## heights instead of two resting near the plane.
static func rocks(parent: Node3D, center: Vector3, rng_seed: int, scale: float = 1.0, floating: bool = false) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = rng_seed
	var count := 2 if not floating else 3 + rng.randi() % 2
	for i in count:
		var r := (rng.randf_range(0.42, 0.62) if i == 0 else rng.randf_range(0.2, 0.32)) * scale
		var rock := ModelFactory.build_rock(rng.randi(), r)
		var y := rng.randf_range(0.15, 0.4) if not floating else rng.randf_range(-0.35, 1.5)
		rock.position = center + Vector3(rng.randf_range(-0.3, 0.3) * scale, y * scale, rng.randf_range(-0.3, 0.3) * scale)
		rock.rotation = Vector3(rng.randf() * TAU, rng.randf() * TAU, rng.randf() * TAU)
		if floating:
			var tumble := Tumbler.new()
			tumble.spin = Vector3(rng.randf_range(-0.25, 0.25), rng.randf_range(-0.3, 0.3), rng.randf_range(-0.2, 0.2))
			rock.add_child(tumble)
		parent.add_child(rock)


## A fading wake of glowing motes, emitted in world space (so it trails
## behind a moving parent). Toggle `emitting` while the parent moves.
static func engine_trail(color: Color, size: float = 1.0) -> CPUParticles3D:
	var p := CPUParticles3D.new()
	var mote := SphereMesh.new()
	mote.radius = 0.055 * size
	mote.height = 0.11 * size
	mote.radial_segments = 6
	mote.rings = 3
	var mat := additive_material(Color.WHITE)
	mat.vertex_color_use_as_albedo = true
	mote.material = mat
	p.mesh = mote
	p.local_coords = false
	p.emitting = false
	p.amount = 150
	p.lifetime = 0.7
	p.direction = Vector3.ZERO
	p.spread = 180.0
	p.initial_velocity_min = 0.0
	p.initial_velocity_max = 0.08
	p.gravity = Vector3.ZERO
	p.scale_amount_min = 0.6
	p.scale_amount_max = 1.2
	var ramp := Gradient.new()
	ramp.set_color(0, color.lightened(0.6) * 1.6)
	ramp.set_color(1, Color(0, 0, 0))
	p.color_ramp = ramp
	return p


# --- Space scenery ------------------------------------------------------------

const PLANET_SHADER := preload("res://src/presentation/shaders/planet_3d.gdshader")
const ATMOSPHERE_SHADER := preload("res://src/presentation/shaders/atmosphere.gdshader")


## Depth around a board: a deep starfield below and around it (parallax as the
## camera moves), slowly drifting dust over it and a big distant planet.
## center/extent: the board's middle and half-size (world XZ). Interiors
## (station decks) only get the stars.
static func space_scenery(parent: Node3D, center: Vector3, extent: Vector2, rng_seed: int, interior: bool = false,
		backdrop_planet: bool = true) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = rng_seed
	var span := maxf(extent.x, extent.y)

	# Stars: one MultiMesh of tiny additive spheres, spread through a deep slab.
	var star := SphereMesh.new()
	star.radius = 0.5
	star.height = 1.0
	star.radial_segments = 6
	star.rings = 3
	var star_mat := StandardMaterial3D.new()
	star_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	star_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	star_mat.vertex_color_use_as_albedo = true
	star_mat.disable_receive_shadows = true
	star.material = star_mat
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.mesh = star
	mm.instance_count = 1400
	for i in mm.instance_count:
		var depth := rng.randf_range(3.0, 45.0)
		var spread := span * 2.2 + depth * 1.6
		var pos := center + Vector3(rng.randf_range(-spread, spread), -depth, rng.randf_range(-spread * 1.2, spread * 0.6))
		var size := rng.randf_range(0.03, 0.09) * (1.0 + depth * 0.06)
		mm.set_instance_transform(i, Transform3D(Basis().scaled(Vector3.ONE * size), pos))
		var hue := rng.randf()
		var tint := Color(0.75, 0.85, 1.0) if hue < 0.6 else (Color(1.0, 0.9, 0.7) if hue < 0.85 else Color(0.8, 0.7, 1.0))
		var bright := rng.randf_range(0.25, 1.0) * (1.3 if rng.randf() < 0.05 else 0.7)
		mm.set_instance_color(i, tint * bright)
	var stars := MultiMeshInstance3D.new()
	stars.multimesh = mm
	stars.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(stars)

	if interior:
		return
	# Dust: faint motes drifting through the space above the board.
	var dust := CPUParticles3D.new()
	var mote := SphereMesh.new()
	mote.radius = 0.02
	mote.height = 0.04
	mote.radial_segments = 4
	mote.rings = 2
	var mote_mat := additive_material(Color(0.55, 0.65, 0.85) * 0.5)
	mote.material = mote_mat
	dust.mesh = mote
	dust.amount = int(clampf(span * 18.0, 60.0, 400.0))
	dust.lifetime = 14.0
	dust.preprocess = 14.0
	dust.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	dust.emission_box_extents = Vector3(extent.x + 2.0, 1.2, extent.y + 2.0)
	dust.position = center + Vector3(0, 0.9, 0)
	dust.direction = Vector3(1, 0.05, 0.3)
	dust.spread = 40.0
	dust.initial_velocity_min = 0.03
	dust.initial_velocity_max = 0.12
	dust.gravity = Vector3.ZERO
	dust.scale_amount_min = 0.5
	dust.scale_amount_max = 1.5
	var fade := Gradient.new()
	fade.set_color(0, Color(0, 0, 0))
	fade.add_point(0.2, Color(1, 1, 1))
	fade.add_point(0.8, Color(1, 1, 1))
	fade.set_color(fade.get_point_count() - 1, Color(0, 0, 0))
	dust.color_ramp = fade
	dust.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(dust)

	if not backdrop_planet:
		return  # system battles bring their own planets and star
	# A big planet far below and beyond the board, catching the sun.
	var radius := span * rng.randf_range(0.35, 0.5)
	var body := MeshInstance3D.new()
	var sphere := SphereMesh.new()
	sphere.radius = radius
	sphere.height = radius * 2.0
	sphere.radial_segments = 64
	sphere.rings = 32
	body.mesh = sphere
	var mat := ShaderMaterial.new()
	mat.shader = PLANET_SHADER
	var palettes := [
		[Color("2b4a6e"), Color("7fa6c9"), Color("8ec5ff"), 0.0, 0.4],
		[Color("6b3d2a"), Color("c98d5a"), Color("ffb27a"), 0.8, 0.0],
		[Color("2f2a4a"), Color("6a5a9a"), Color("b39cff"), 0.5, 0.0],
		[Color("2e4a3a"), Color("8a9a6a"), Color("9fe0c0"), 0.0, 0.2],
	]
	var pal: Array = palettes[rng.randi() % palettes.size()]
	mat.set_shader_parameter("base_color", pal[0])
	mat.set_shader_parameter("accent_color", pal[1])
	mat.set_shader_parameter("atmosphere_color", pal[2])
	mat.set_shader_parameter("bands", pal[3])
	mat.set_shader_parameter("ice_caps", pal[4])
	mat.set_shader_parameter("seed", rng.randf() * 20.0)
	body.material_override = mat
	body.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var side := -1.0 if rng.randf() < 0.5 else 1.0
	# Low and far beyond the board's back edge, off to one side: it rises
	# behind the board at the top of the view rather than under the ships.
	body.position = center + Vector3(side * (extent.x * 0.9 + radius * 0.6), -(radius * 0.6 + 6.0), -(extent.y + radius * 3.0 + 45.0))
	body.rotation = Vector3(0.3, rng.randf() * TAU, 0.2)
	parent.add_child(body)
	var shell := MeshInstance3D.new()
	var shell_mesh := SphereMesh.new()
	shell_mesh.radius = radius * 1.08
	shell_mesh.height = radius * 2.16
	shell_mesh.radial_segments = 48
	shell_mesh.rings = 24
	shell.mesh = shell_mesh
	var shell_mat := ShaderMaterial.new()
	shell_mat.shader = ATMOSPHERE_SHADER
	shell_mat.set_shader_parameter("atmosphere_color", pal[2])
	shell_mat.set_shader_parameter("strength", 0.9)
	shell.material_override = shell_mat
	shell.position = body.position
	shell.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(shell)
