// High-quality galaxy map: unexplored space as soft, drifting cloud cover
// (Civ's "fog of war" clouds), and a thin dark veil over charted space that
// is out of sensor range. One quad over the whole map reads a world-space
// mask (R = explored, G = visible now) so the cover's edge is soft and
// organic rather than hex-shaped.
shader_type spatial;
render_mode unshaded, depth_draw_never, cull_disabled;

uniform sampler2D mask : filter_linear, repeat_disable;
// x0, z0, width, depth of the mask in world units.
uniform vec4 bounds = vec4(0.0, 0.0, 1.0, 1.0);
uniform vec4 deep_color : source_color = vec4(0.035, 0.045, 0.085, 1.0);
uniform vec4 cloud_color : source_color = vec4(0.12, 0.14, 0.24, 1.0);
uniform vec4 crest_color : source_color = vec4(0.32, 0.38, 0.58, 1.0);

varying vec3 world_pos;

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), u.x), mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), u.x), u.y);
}

float fbm(vec2 p) {
	float v = 0.0;
	float a = 0.5;
	for (int i = 0; i < 5; i++) {
		v += a * noise(p);
		p = p * 2.03 + vec2(3.1, 1.7);
		a *= 0.5;
	}
	return v;
}

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec2 p = world_pos.xz;
	float drift = TIME * 0.01;
	float n = fbm(p * 0.45 + vec2(drift, drift * 0.6));
	float n2 = fbm(p * 1.3 - vec2(drift * 1.7, 0.0));
	// Wobble the lookup so the cover's edge billows instead of following hexes.
	vec2 warp = vec2(n - 0.5, n2 - 0.5) * 0.9;
	vec2 uv = (p + warp - bounds.xy) / bounds.zw;
	vec4 m = texture(mask, uv);
	// Past the map's edge the cover thins out into open sky.
	vec2 outside = max(max(bounds.xy - p, p - (bounds.xy + bounds.zw)), vec2(0.0));
	float beyond = smoothstep(0.0, 9.0, length(outside));
	float unexplored = 1.0 - m.r;
	float cover = smoothstep(0.3, 0.7, unexplored + (n - 0.5) * 0.5);
	// Cloud body: dark with brighter crests where the noise piles up.
	vec3 col = mix(deep_color.rgb, cloud_color.rgb, smoothstep(0.3, 0.75, n));
	col += crest_color.rgb * smoothstep(0.55, 0.9, n2 * n * 1.7) * 0.7;
	// Soft light and shade across the bank, so it reads as cloud, not a flat sheet.
	col *= 0.75 + 0.5 * smoothstep(0.2, 0.8, fbm(p * 0.18 + vec2(-drift * 0.5, drift)));
	// Its edge catches a little light, like the rim of a cloud bank.
	float rim = cover * (1.0 - cover) * 4.0;
	col += crest_color.rgb * rim * 0.35;
	// Charted space out of sensor range: a light dark veil.
	float veil = m.r * (1.0 - m.g) * 0.42;
	ALBEDO = col;
	ALPHA = clamp(max(cover * 0.97, veil), 0.0, 1.0) * (1.0 - beyond * 0.85);
	if (cover < 0.5 && veil > cover) {
		ALBEDO = vec3(0.0, 0.004, 0.02);
	}
}
