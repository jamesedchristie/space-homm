// High-quality galaxy map: one slice of a nebula / ion storm / dust field.
// Three slices stacked at different heights give the clouds depth and
// parallax as the camera turns. A world-space mask says where the terrain is
// (R nebula, G ion storm, B asteroid dust); the explored mask hides what you
// haven't charted.
shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, shadows_disabled;

uniform sampler2D terrain_mask : filter_linear, repeat_disable;
uniform sampler2D explored_mask : filter_linear, repeat_disable;
uniform vec4 bounds = vec4(0.0, 0.0, 1.0, 1.0);
uniform float layer = 0.0;  // 0 bottom .. 1 top
uniform vec4 nebula_a : source_color = vec4(0.55, 0.22, 0.75, 1.0);
uniform vec4 nebula_b : source_color = vec4(0.18, 0.35, 0.9, 1.0);
uniform vec4 storm_color : source_color = vec4(0.35, 0.7, 1.0, 1.0);
uniform vec4 dust_color : source_color = vec4(0.55, 0.42, 0.3, 1.0);
uniform float strength = 0.55;

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
		p = p * 2.05 + vec2(3.1, 1.7);
		a *= 0.5;
	}
	return v;
}

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec2 p = world_pos.xz;
	float t = TIME * 0.02;
	float off = layer * 17.3;
	float warp = fbm(p * 0.35 + off + t);
	vec2 q = p + vec2(warp - 0.5) * 1.4;
	vec2 uv = (q - bounds.xy) / bounds.zw;
	vec3 m = texture(terrain_mask, uv).rgb;
	float charted = texture(explored_mask, (p - bounds.xy) / bounds.zw).r;
	float n = fbm(q * 0.8 + off - t * 1.5);
	float fine = fbm(q * 2.6 + off * 2.0 + t);
	// Each layer thins towards the top; billows where the noise piles up.
	float thick = smoothstep(0.35, 0.8, n + layer * -0.12) * (1.0 - layer * 0.45);
	float neb = m.r * thick;
	float storm = m.g * smoothstep(0.3, 0.75, n) * (1.0 - layer * 0.3);
	float dust = m.b * smoothstep(0.45, 0.8, fine) * (1.0 - layer) * 0.55;
	vec3 neb_col = mix(nebula_a.rgb, nebula_b.rgb, smoothstep(0.3, 0.8, fine));
	// Bright filaments inside the nebula.
	neb_col += vec3(1.0, 0.75, 0.95) * smoothstep(0.7, 0.92, fine * n * 1.8) * 0.8;
	float flicker = step(0.992, hash(floor(q * 3.0) + floor(TIME * 5.0))) * storm;
	vec3 col = neb_col * neb + storm_color.rgb * (storm * 0.8 + flicker * 4.0) + dust_color.rgb * dust;
	ALBEDO = col * strength * charted;
}
