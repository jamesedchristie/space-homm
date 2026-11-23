shader_type sky;
// Deep-space sky for the high-quality renderer: layered star fields (with a
// few bright, coloured stars), two nebula colours in drifting fbm clouds, a
// faint galactic band, and a warm glow towards the sun. It also lights and
// reflects off ship hulls (ambient and reflections come from the sky).

uniform vec3 nebula_a : source_color = vec3(0.16, 0.22, 0.55);
uniform vec3 nebula_b : source_color = vec3(0.45, 0.14, 0.42);
uniform float nebula_strength = 0.95;
uniform float star_density = 0.9;
uniform float seed = 3.0;
uniform vec3 band_normal = vec3(0.35, 0.8, 0.45);

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
	for (int i = 0; i < 6; i++) {
		v += a * noise3(p);
		p = p * 2.07 + vec3(3.1, 1.7, 5.3);
		a *= 0.5;
	}
	return v;
}

// Stars on a 3D grid of cells: one candidate per cell, sharp core.
vec3 stars(vec3 dir, float scale, float threshold, float size) {
	vec3 p = dir * scale;
	vec3 cell = floor(p);
	vec3 f = fract(p) - 0.5;
	float h = hash3(cell);
	if (h < threshold) {
		return vec3(0.0);
	}
	vec3 offset = vec3(hash3(cell + 1.3), hash3(cell + 2.7), hash3(cell + 4.1)) - 0.5;
	float d = length(f - offset * 0.7);
	float core = smoothstep(size, 0.0, d);
	float tint = hash3(cell + 7.7);
	vec3 col = tint < 0.6 ? vec3(0.8, 0.88, 1.0) : (tint < 0.85 ? vec3(1.0, 0.9, 0.75) : vec3(1.0, 0.7, 0.6));
	return col * core * (0.6 + 2.5 * (h - threshold) / (1.0 - threshold));
}

void sky() {
	vec3 dir = normalize(EYEDIR);
	// Nebula: two colours, domain-warped clouds, thicker along the galactic band.
	float band = exp(-pow(dot(dir, normalize(band_normal)) * 3.2, 2.0));
	vec3 q = dir * 2.2;
	float warp = fbm(q + vec3(seed));
	float n1 = fbm(q * 1.3 + warp * 1.6);
	float n2 = fbm(q * 2.1 - warp * 1.2 + 7.0);
	float clouds = smoothstep(0.42, 0.85, n1) * (0.35 + 0.9 * band);
	float wisps = smoothstep(0.5, 0.9, n2) * (0.25 + 0.6 * band);
	vec3 col = nebula_a * clouds * nebula_strength + nebula_b * wisps * nebula_strength * 0.9;
	// Dark dust lanes across the band.
	col *= 1.0 - 0.55 * smoothstep(0.55, 0.75, fbm(q * 3.0 + 11.0)) * band;
	col += vec3(0.05, 0.06, 0.1) * band * 0.6;
	// Stars: dense faint field plus sparse bright ones; more along the band.
	col += stars(dir, 260.0, 0.93 - 0.03 * band * star_density, 0.18) * 0.55;
	col += stars(dir, 90.0, 0.985, 0.12) * 1.4;
	// Glow towards the sun.
	if (LIGHT0_ENABLED) {
		float sun = max(dot(dir, LIGHT0_DIRECTION), 0.0);
		col += LIGHT0_COLOR * (pow(sun, 64.0) * 0.6 + pow(sun, 8.0) * 0.06);
	}
	COLOR = col;
}
