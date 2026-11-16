// Unexplored space on the 3D galaxy map: dark, slowly drifting clouds in
// world space (so neighbouring fog cells join up seamlessly). Vertex color
// darkens the slab's sides.
shader_type spatial;
render_mode unshaded;

uniform vec4 deep_color : source_color = vec4(0.012, 0.016, 0.035, 1.0);
uniform vec4 cloud_color : source_color = vec4(0.09, 0.07, 0.17, 1.0);
uniform vec4 glint_color : source_color = vec4(0.16, 0.24, 0.42, 1.0);

varying vec3 world_pos;

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), u.x),
			mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), u.x), u.y);
}

float fbm(vec2 p) {
	float v = 0.0;
	float a = 0.5;
	for (int i = 0; i < 5; i++) {
		v += a * noise(p);
		p = p * 2.07 + vec2(3.1, 1.7);
		a *= 0.5;
	}
	return v;
}

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec2 p = world_pos.xz * 0.35;
	float clouds = fbm(p + vec2(TIME * 0.015, TIME * 0.008));
	float detail = fbm(p * 3.0 - vec2(TIME * 0.02, 0.0));
	vec3 col = mix(deep_color.rgb, cloud_color.rgb, smoothstep(0.35, 0.8, clouds));
	col += glint_color.rgb * smoothstep(0.62, 0.9, detail * clouds * 1.6) * 0.5;
	// Rare faint stars, so it reads as "uncharted" rather than "nothing".
	float star = step(0.9965, hash(floor(world_pos.xz * 18.0)));
	col += vec3(0.5, 0.6, 0.8) * star * 0.5;
	ALBEDO = col * COLOR.rgb;
}
