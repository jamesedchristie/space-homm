shader_type spatial;
// Hull plating for ship models: staggered panels with dark seams, a slight
// per-panel tone and roughness variation, and (on side-facing hull) rows of
// small lit windows. Works from model-space position and normal (triplanar),
// so the procedural meshes need no UVs.

uniform vec4 albedo : source_color = vec4(0.67, 0.7, 0.75, 1.0);
uniform float metallic = 0.55;
uniform float roughness = 0.4;
uniform vec4 emission_color : source_color = vec4(0.0, 0.0, 0.0, 1.0);
uniform float emission_energy = 0.0;
// Panels per model unit (a unit is one hex radius).
uniform float panel_scale = 5.5;
uniform float seam_strength = 0.28;
uniform float tone_variation = 0.1;
// 0..1: share of side panels that carry a window.
uniform float window_density = 0.0;
uniform vec4 window_color : source_color = vec4(1.0, 0.86, 0.6, 1.0);

varying vec3 model_pos;
varying vec3 model_normal;

float hash2(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

void vertex() {
	model_pos = VERTEX;
	model_normal = NORMAL;
}

void fragment() {
	vec3 n = abs(normalize(model_normal));
	vec2 uv;
	float face;
	if (n.y >= n.x && n.y >= n.z) {
		uv = model_pos.xz;
		face = 0.0;
	} else if (n.x >= n.z) {
		uv = model_pos.zy;
		face = 1.0;
	} else {
		uv = model_pos.xy;
		face = 2.0;
	}
	// Long plates along the hull (x), staggered every other row; some plates
	// are split in two so the pattern doesn't read as a regular grid.
	vec2 p = uv * vec2(panel_scale, panel_scale * 1.7);
	float row = floor(p.y);
	p.x += hash2(vec2(row, face)) * 0.8;
	vec2 cell = floor(p);
	vec2 f = fract(p);
	float id = hash2(cell + face * 17.0);
	if (id > 0.6) {
		f.x = fract(f.x * 2.0);
		cell.x += step(0.5, fract(p.x)) * 0.5;
		id = hash2(cell + face * 31.0);
	}
	// Seams: thin dark lines at the plate edges, softened with distance.
	float edge = min(min(f.x, 1.0 - f.x) * 0.5, min(f.y, 1.0 - f.y));
	float width = fwidth(p.y) * 0.9;
	float seam = 1.0 - smoothstep(width * 0.5, width * 1.5 + 0.01, edge);
	// Broad, low-frequency weathering on top of per-plate tone.
	float grime = hash2(floor(uv * 1.7) + face) * 0.5 + hash2(floor(uv * 3.1) + 3.0) * 0.5;
	vec3 base = albedo.rgb * (1.0 + (id - 0.5) * tone_variation) * (0.94 + grime * 0.08);
	base *= 1.0 - seam * seam_strength;
	ALBEDO = base;
	METALLIC = metallic;
	ROUGHNESS = clamp(roughness + (id - 0.5) * 0.2 + seam * 0.25, 0.05, 1.0);
	vec3 glow = emission_color.rgb * emission_energy;
	// Windows: small bright slots on side plates (not on top or bottom).
	if (window_density > 0.0 && face > 0.5 && n.y < 0.35) {
		vec2 w = abs(f - vec2(0.5, 0.45));
		float slot = step(w.x, 0.16) * step(w.y, 0.12);
		float lit = step(id, window_density) * slot;
		glow += window_color.rgb * lit * 2.2;
		ALBEDO = mix(ALBEDO, window_color.rgb * 0.3, lit);
	}
	EMISSION = glow;
}
