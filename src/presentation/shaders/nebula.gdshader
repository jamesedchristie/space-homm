// Animated space backdrop: two domain-warped fbm nebula layers plus a
// twinkling star field. Put it on a full-screen ColorRect behind the map.
shader_type canvas_item;

uniform vec4 space_color : source_color = vec4(0.012, 0.016, 0.035, 1.0);
uniform vec4 color_a : source_color = vec4(0.10, 0.18, 0.42, 1.0);
uniform vec4 color_b : source_color = vec4(0.38, 0.12, 0.42, 1.0);
uniform float density = 0.55;
uniform float seed = 3.0;
uniform float aspect = 1.78;
uniform vec2 drift = vec2(0.006, 0.003);

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7)) + seed * 7.31) * 43758.5453);
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
		p = p * 2.02 + vec2(5.3, 1.9);
		a *= 0.5;
	}
	return v;
}

float stars(vec2 uv, float scale, float threshold) {
	vec2 sp = uv * scale;
	vec2 cell = floor(sp);
	vec2 f = fract(sp) - 0.5;
	float h = hash(cell);
	if (h < threshold) {
		return 0.0;
	}
	vec2 offset = vec2(hash(cell + 1.3), hash(cell + 7.9)) - 0.5;
	float size = 0.06 + (h - threshold) / (1.0 - threshold) * 0.12;
	float twinkle = 0.65 + 0.35 * sin(TIME * (0.8 + h * 2.5) + h * 50.0);
	return smoothstep(size, 0.0, length(f - offset * 0.6)) * twinkle;
}

void fragment() {
	vec2 uv = UV * vec2(aspect, 1.0);
	vec2 p = uv * 2.2 + TIME * drift;
	float warp = fbm(p * 0.6 + seed);
	float n1 = fbm(p + warp * 1.4);
	float n2 = fbm(p * 1.6 - warp + seed * 2.0);
	vec3 col = space_color.rgb;
	col += color_a.rgb * smoothstep(0.42, 0.95, n1) * density;
	col += color_b.rgb * smoothstep(0.50, 1.0, n2) * density * 0.85;
	col += vec3(0.82, 0.88, 1.0) * stars(uv, 140.0, 0.975);
	col += vec3(1.0, 0.95, 0.85) * stars(uv + 3.7, 60.0, 0.988) * 1.3;
	COLOR = vec4(col, 1.0);
}
