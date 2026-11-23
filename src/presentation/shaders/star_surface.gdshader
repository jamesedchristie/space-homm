// A star close up: boiling granulation, darker limb, hot spots, and HDR
// emission so the renderer's glow gives it a corona. Colour from the star type.
shader_type spatial;
render_mode unshaded;

uniform vec4 star_color : source_color = vec4(1.0, 0.85, 0.55, 1.0);
uniform float energy = 3.0;
uniform float seed = 1.0;

varying vec3 local_n;

float hash3(vec3 p) {
	p = fract(p * vec3(443.897, 441.423, 437.195) + seed);
	p += dot(p, p.yzx + 19.19);
	return fract((p.x + p.y) * p.z);
}

float noise3(vec3 p) {
	vec3 i = floor(p);
	vec3 f = fract(p);
	vec3 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(mix(hash3(i), hash3(i + vec3(1, 0, 0)), u.x), mix(hash3(i + vec3(0, 1, 0)), hash3(i + vec3(1, 1, 0)), u.x), u.y),
		mix(mix(hash3(i + vec3(0, 0, 1)), hash3(i + vec3(1, 0, 1)), u.x), mix(hash3(i + vec3(0, 1, 1)), hash3(i + vec3(1, 1, 1)), u.x), u.y), u.z);
}

float fbm(vec3 p) {
	float v = 0.0;
	float a = 0.5;
	for (int i = 0; i < 5; i++) {
		v += a * noise3(p);
		p = p * 2.13 + vec3(1.7, 9.2, 3.4);
		a *= 0.5;
	}
	return v;
}

void vertex() {
	local_n = normalize(VERTEX);
}

void fragment() {
	vec3 n = normalize(local_n);
	float t = TIME * 0.06;
	// Granulation: cells that churn slowly, warped by a larger flow.
	float flow = fbm(n * 2.0 + vec3(t, -t * 0.7, t * 0.4));
	float cells = fbm(n * 9.0 + flow * 2.5 - vec3(t * 2.0));
	float spots = smoothstep(0.62, 0.8, fbm(n * 3.0 + vec3(seed * 3.1, t * 0.3, 0.0)));
	// Limb darkening: the edge of the disc is redder and dimmer.
	float facing = clamp(dot(NORMAL, VIEW), 0.0, 1.0);
	float limb = pow(facing, 0.45);
	vec3 hot = mix(star_color.rgb, vec3(1.0), 0.3);
	vec3 col = mix(star_color.rgb * vec3(1.0, 0.7, 0.5), hot, limb);
	col *= 0.65 + 0.7 * cells;
	col += hot * spots * 0.35;
	ALBEDO = col;
	EMISSION = col * energy * (0.55 + 0.45 * limb);
}
