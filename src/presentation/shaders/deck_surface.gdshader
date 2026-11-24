shader_type spatial;
// Station deck surfaces on the high-quality look (DeckKit): vertex-coloured
// floor plates, bulkheads and props with world-space detail (no UVs needed):
// fine panel seams and bolts, diamond tread on walkways, grime that gathers
// low on the walls and in blotches on the floor, scuffs, and blast scorch
// marks. `glow` turns the surface into a light strip / screen (its vertex
// colour, emissive).
//
// Fog of war: `fog_mask` holds one texel per grid cell (R explored, G visible
// now). Unexplored cells are not drawn at all (nothing leaks through the fog,
// from any camera angle); explored cells out of sight are dimmed.

render_mode blend_mix, cull_back, depth_draw_opaque;

uniform float roughness = 0.6;
uniform float metallic = 0.4;
uniform float glow = 0.0;
uniform float glow_energy = 2.5;
uniform vec4 tint : source_color = vec4(1.0);
// Detail amounts.
uniform float grime = 0.4;
uniform float tread = 0.0;
uniform float scorch = 0.0;
uniform float seams = 0.0;
uniform float wear = 0.3;
uniform vec4 grime_color : source_color = vec4(0.06, 0.05, 0.04, 1.0);
uniform float cell_size = 1.8;

uniform sampler2D fog_mask : filter_linear, repeat_disable;
uniform vec2 fog_origin = vec2(0.0);
uniform vec2 fog_size = vec2(1.0);
uniform float fog_on = 0.0;

varying vec3 wpos;
varying vec3 wnrm;

float hash2(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	float a = hash2(i);
	float b = hash2(i + vec2(1.0, 0.0));
	float c = hash2(i + vec2(0.0, 1.0));
	float d = hash2(i + vec2(1.0, 1.0));
	return mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
}

float fbm(vec2 p) {
	return vnoise(p) * 0.55 + vnoise(p * 2.13 + 7.1) * 0.3 + vnoise(p * 4.7 + 1.3) * 0.15;
}

// Explored (x) and visible (y) at a world position, 0..1 with soft cell edges.
vec2 fog_at(vec3 p) {
	if (fog_on < 0.5) {
		return vec2(1.0);
	}
	vec2 uv = ((p.xz - fog_origin) / cell_size + 0.5) / fog_size;
	vec2 m = texture(fog_mask, uv).rg;
	return vec2(smoothstep(0.5, 0.78, m.r), smoothstep(0.2, 0.8, m.g));
}

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	wnrm = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

void fragment() {
	vec2 fog = fog_at(wpos);
	if (fog.x < 0.02) {
		discard;
	}
	float seen = mix(0.32, 1.0, fog.y) * fog.x;
	vec3 base = COLOR.rgb * tint.rgb;
	if (glow > 0.5) {
		ALBEDO = base * 0.15;
		ROUGHNESS = 0.4;
		EMISSION = base * glow_energy * seen * mix(0.4, 1.0, fog.y);
	} else {
		vec3 n = abs(wnrm);
		bool up = n.y > 0.6;
		vec2 uv = up ? wpos.xz : (n.x > n.z ? wpos.zy : wpos.xy);
		// Grime: broad blotches, and on walls a band that gathers near the floor.
		float g = fbm(uv * 2.3);
		float dirt = smoothstep(0.5, 0.85, g) * grime * 0.7;
		if (!up) {
			dirt = max(dirt, grime * (1.0 - smoothstep(0.0, 0.45, wpos.y)) * 0.7);
			// Streaks running down the walls.
			dirt = max(dirt, grime * 0.5 * smoothstep(0.7, 0.95, vnoise(vec2(uv.x * 9.0, uv.y * 0.6))));
		}
		float detail = 1.0;
		// Diamond tread on walkway plates.
		if (up && tread > 0.0) {
			vec2 t = uv * 11.0;
			vec2 r = vec2(t.x + t.y, t.x - t.y);
			vec2 f = abs(fract(r) - 0.5);
			float bump = smoothstep(0.32, 0.22, max(f.x, f.y * 3.0)) + smoothstep(0.32, 0.22, max(f.x * 3.0, f.y));
			detail -= tread * 0.1 * min(bump, 1.0);
		}
		// Fine seams: sub-panels on bulkhead faces and tops.
		if (seams > 0.0) {
			vec2 p = uv * vec2(1.6, 2.4);
			if (up) {
				p = uv * 2.2;
			}
			vec2 f = fract(p);
			float e = min(min(f.x, 1.0 - f.x), min(f.y, 1.0 - f.y));
			float w = fwidth(p.x) + fwidth(p.y);
			float line = 1.0 - smoothstep(w * 0.4, w * 1.2 + 0.004, e);
			detail -= seams * 0.35 * line;
			// Bolt heads near the panel corners.
			vec2 c = abs(f - 0.5);
			float bolt = 1.0 - smoothstep(0.015, 0.03, length(c - vec2(0.43)));
			detail += seams * 0.25 * bolt;
		}
		// Scuffs and scratches: light streaks where boots and crates have worn the paint.
		float scratch = smoothstep(0.88, 0.98, vnoise(vec2(uv.x * 26.0, uv.y * 5.0) + vnoise(uv * 3.0) * 3.0)) * step(0.55, vnoise(uv * 1.3 + 5.0));
		float scuff = scratch * wear * (up ? 1.0 : 0.4);
		// Blast scorch marks on some floor cells.
		float burn = 0.0;
		if (up && scorch > 0.0 && wpos.y < 0.3) {
			vec2 cell = floor(wpos.xz / cell_size + 0.5);
			float h = hash2(cell + 3.7);
			if (h < scorch) {
				vec2 center = (cell + (vec2(hash2(cell + 1.1), hash2(cell + 2.3)) - 0.5) * 0.4) * cell_size;
				float d = length(wpos.xz - center) / cell_size;
				float edge = 0.18 + fbm(wpos.xz * 2.2 + h * 9.0) * 0.26;
				burn = smoothstep(edge, edge * 0.2, d) * (0.55 + 0.45 * vnoise(wpos.xz * 7.0));
			}
		}
		vec3 col = base * detail;
		col = mix(col, col * grime_color.rgb * 6.0, dirt * 0.65);
		col = mix(col, col * 1.6 + vec3(0.04), scuff * 0.6);
		col = mix(col, vec3(0.02, 0.016, 0.013), burn * 0.8);
		ALBEDO = col * seen;
		METALLIC = metallic * (1.0 - dirt * 0.5) * (1.0 - burn);
		// Clean worn metal is shiny; dirt and soot are matte.
		ROUGHNESS = clamp(roughness + dirt * 0.25 - scuff * 0.3 + burn * 0.35 + (fbm(uv * 0.6 + 9.0) - 0.5) * 0.25, 0.08, 1.0);
		SPECULAR = 0.5 * seen;
	}
}
