class_name PortraitKit
extends RefCounted
## Small helpers for building the procedural leader busts: materials (a soft skin
## shader, a hair shader, plain PBR for cloth/metal/glass) and primitive meshes.

const SKIN_SHADER := """
shader_type spatial;
uniform vec3 skin : source_color = vec3(0.8, 0.6, 0.5);
uniform vec3 shade_tint : source_color = vec3(0.55, 0.18, 0.16);
uniform vec3 rim_color : source_color = vec3(1.0);
uniform float rim_amount = 0.3;
uniform float wrap = 0.55;
uniform float irid = 0.0;
uniform float spec = 0.1;
uniform float gloss = 26.0;
varying vec3 vcol;
void vertex() { vcol = COLOR.rgb; }
void fragment() {
	vec3 base = skin * vcol;
	float fres = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 2.6);
	vec3 ir = 0.5 + 0.5 * cos(6.28318 * (fres * 0.8 + NORMAL.y * 0.15 + vec3(0.0, 0.33, 0.67)));
	base = mix(base, base * 0.55 + ir * 0.55, clamp(irid * (0.25 + fres * 1.4), 0.0, 1.0));
	ALBEDO = base;
	ROUGHNESS = 0.7;
	SPECULAR = 0.0;
	EMISSION = rim_color * fres * rim_amount;
}
void light() {
	float ndl = dot(NORMAL, LIGHT);
	float w = clamp((ndl + wrap) / (1.0 + wrap), 0.0, 1.0);
	vec3 diff = mix(shade_tint, vec3(1.0), smoothstep(0.0, 0.55, w)) * w;
	DIFFUSE_LIGHT += LIGHT_COLOR * ATTENUATION * diff / PI;
	vec3 hv = normalize(LIGHT + VIEW);
	SPECULAR_LIGHT += spec * pow(max(dot(NORMAL, hv), 0.0), gloss) * ATTENUATION * LIGHT_COLOR * step(0.0, ndl);
}
"""

const HAIR_SHADER := """
shader_type spatial;
uniform vec3 hair : source_color = vec3(0.2, 0.12, 0.08);
uniform float back_y = -0.07;
uniform float front_y = 0.084;
uniform float temple_drop = 0.05;
uniform float strip_w = 10.0;
uniform float sheen = 0.2;
varying vec3 opos;
void vertex() { opos = VERTEX; }
void fragment() {
	float front = smoothstep(-0.015, 0.075, opos.z);
	float cut = mix(back_y, front_y, front) - temple_drop * smoothstep(0.035, 0.078, abs(opos.x)) * smoothstep(0.0, 0.06, opos.z);
	if (opos.y < cut || abs(opos.x) > strip_w) { discard; }
	float strands = 0.5 + 0.5 * sin(opos.x * 420.0 + opos.y * 90.0 + sin(opos.z * 160.0) * 2.0);
	ALBEDO = hair * (0.82 + 0.28 * strands);
	ROUGHNESS = 0.45;
	SPECULAR = 0.0;
}
void light() {
	float ndl = max(dot(NORMAL, LIGHT), 0.0);
	DIFFUSE_LIGHT += LIGHT_COLOR * ATTENUATION * ndl / PI;
	vec3 hv = normalize(LIGHT + VIEW);
	float t = pow(max(dot(NORMAL, hv), 0.0), 22.0);
	SPECULAR_LIGHT += sheen * t * ATTENUATION * LIGHT_COLOR * (0.5 + 0.5 * ndl);
}
"""

static var _skin_shader: Shader
static var _hair_shader: Shader


static func col(d: Dictionary, key: String, fallback: Color) -> Color:
	var v: Variant = d.get(key, "")
	if v is String and Color.html_is_valid(v):
		return Color(v)
	return fallback


static func skin_material(color: Color, shade: Color, rim: Color, irid: float = 0.0, rim_amount: float = 0.3) -> ShaderMaterial:
	if _skin_shader == null:
		_skin_shader = Shader.new()
		_skin_shader.code = SKIN_SHADER
	var m := ShaderMaterial.new()
	m.shader = _skin_shader
	m.set_shader_parameter("skin", color)
	m.set_shader_parameter("shade_tint", shade)
	m.set_shader_parameter("rim_color", rim)
	m.set_shader_parameter("irid", irid)
	m.set_shader_parameter("rim_amount", rim_amount)
	return m


static func hair_material(color: Color) -> ShaderMaterial:
	if _hair_shader == null:
		_hair_shader = Shader.new()
		_hair_shader.code = HAIR_SHADER
	var m := ShaderMaterial.new()
	m.shader = _hair_shader
	m.set_shader_parameter("hair", color)
	return m


static func mat(color: Color, rough: float = 0.6, metal: float = 0.0) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.roughness = rough
	m.metallic = metal
	m.metallic_specular = 0.5
	return m


## Self-lit material (crystal, eyes, trim lights).
static func glow(color: Color, energy: float = 1.5, alpha: float = 1.0) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(color, alpha)
	m.emission_enabled = true
	m.emission = color
	m.emission_energy_multiplier = energy
	m.roughness = 0.2
	if alpha < 1.0:
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	return m


static func add(parent: Node3D, mesh: Mesh, material: Material, pos: Vector3 = Vector3.ZERO,
		scale: Vector3 = Vector3.ONE, rot_deg: Vector3 = Vector3.ZERO) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = material
	mi.position = pos
	mi.scale = scale
	mi.rotation_degrees = rot_deg
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mi)
	return mi


static func sphere(parent: Node3D, r: float, material: Material, pos: Vector3 = Vector3.ZERO,
		scale: Vector3 = Vector3.ONE, rot_deg: Vector3 = Vector3.ZERO, segs: int = 32) -> MeshInstance3D:
	var m := SphereMesh.new()
	m.radius = r
	m.height = r * 2.0
	m.radial_segments = segs
	m.rings = maxi(segs / 2, 4)
	return add(parent, m, material, pos, scale, rot_deg)


static func hemisphere(parent: Node3D, r: float, material: Material, pos: Vector3 = Vector3.ZERO,
		scale: Vector3 = Vector3.ONE, rot_deg: Vector3 = Vector3.ZERO, segs: int = 32) -> MeshInstance3D:
	var m := SphereMesh.new()
	m.radius = r
	m.height = r * 2.0
	m.is_hemisphere = true
	m.radial_segments = segs
	m.rings = maxi(segs / 4, 4)
	return add(parent, m, material, pos, scale, rot_deg)


## An uncapped dome (top of a sphere, axis +y) reaching `reach` radians from the pole;
## used for eyelids, so no flat cap shows.
static func dome_mesh(r: float, reach: float = PI * 0.5, lon: int = 24, lat: int = 10) -> ArrayMesh:
	var verts := PackedVector3Array()
	var normals := PackedVector3Array()
	for i in lat + 1:
		var th := reach * float(i) / lat
		for j in lon:
			var ph := TAU * float(j) / lon
			var n := Vector3(sin(th) * sin(ph), cos(th), sin(th) * cos(ph))
			verts.append(n * r)
			normals.append(n)
	var idx := PackedInt32Array()
	for i in lat:
		for j in lon:
			var a := i * lon + j
			var b := i * lon + (j + 1) % lon
			var c := (i + 1) * lon + j
			var d := (i + 1) * lon + (j + 1) % lon
			idx.append_array([a, b, c, b, d, c])
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_INDEX] = idx
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh


static func capsule(parent: Node3D, r: float, h: float, material: Material, pos: Vector3 = Vector3.ZERO,
		rot_deg: Vector3 = Vector3.ZERO, scale: Vector3 = Vector3.ONE, segs: int = 24) -> MeshInstance3D:
	var m := CapsuleMesh.new()
	m.radius = r
	m.height = maxf(h, r * 2.0)
	m.radial_segments = segs
	m.rings = 8
	return add(parent, m, material, pos, scale, rot_deg)


static func cylinder(parent: Node3D, top_r: float, bottom_r: float, h: float, material: Material,
		pos: Vector3 = Vector3.ZERO, rot_deg: Vector3 = Vector3.ZERO, segs: int = 28, scale: Vector3 = Vector3.ONE) -> MeshInstance3D:
	var m := CylinderMesh.new()
	m.top_radius = top_r
	m.bottom_radius = bottom_r
	m.height = h
	m.radial_segments = segs
	m.rings = 1
	return add(parent, m, material, pos, scale, rot_deg)


static func box(parent: Node3D, size: Vector3, material: Material, pos: Vector3 = Vector3.ZERO,
		rot_deg: Vector3 = Vector3.ZERO) -> MeshInstance3D:
	var m := BoxMesh.new()
	m.size = size
	return add(parent, m, material, pos, Vector3.ONE, rot_deg)


static func torus(parent: Node3D, inner: float, outer: float, material: Material, pos: Vector3 = Vector3.ZERO,
		rot_deg: Vector3 = Vector3.ZERO, scale: Vector3 = Vector3.ONE) -> MeshInstance3D:
	var m := TorusMesh.new()
	m.inner_radius = inner
	m.outer_radius = outer
	m.rings = 40
	m.ring_segments = 12
	return add(parent, m, material, pos, scale, rot_deg)


## A cone (point up) from a cylinder with top radius 0.
static func cone(parent: Node3D, r: float, h: float, material: Material, pos: Vector3 = Vector3.ZERO,
		rot_deg: Vector3 = Vector3.ZERO, segs: int = 16) -> MeshInstance3D:
	return cylinder(parent, 0.0, r, h, material, pos, rot_deg, segs)
