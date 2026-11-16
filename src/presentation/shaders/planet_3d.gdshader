// Procedural planet surface for 3D spheres (galaxy map). Same look as
// planet.gdshader (fbm continents, gas-giant bands, ice caps, atmospheric
// rim) but lit by the scene's lights. Uses 3D noise on the object-space
// normal so there is no seam; the node itself spins.
shader_type spatial;

uniform vec4 base_color : source_color = vec4(0.25, 0.55, 0.38, 1.0);
uniform vec4 accent_color : source_color = vec4(0.78, 0.74, 0.55, 1.0);
uniform vec4 atmosphere_color : source_color = vec4(0.45, 0.75, 1.0, 0.9);
uniform float bands = 0.0;
uniform float ice_caps = 0.0;
uniform float seed = 1.0;

varying vec3 local_n;

float hash3(vec3 p) {
	return fract(sin(dot(p, vec3(127.1, 311.7, 74.7)) + seed * 13.17) * 43758.5453);
}

float noise3(vec3 p) {
	vec3 i = floor(p);
	vec3 f = fract(p);
	vec3 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(mix(hash3(i), hash3(i + vec3(1, 0, 0)), u.x),
			mix(hash3(i + vec3(0, 1, 0)), hash3(i + vec3(1, 1, 0)), u.x), u.y),
		mix(mix(hash3(i + vec3(0, 0, 1)), hash3(i + vec3(1, 0, 1)), u.x),
			mix(hash3(i + vec3(0, 1, 1)), hash3(i + vec3(1, 1, 1)), u.x), u.y), u.z);
}

float fbm3(vec3 p) {
	float v = 0.0;
	float a = 0.5;
	for (int i = 0; i < 5; i++) {
		v += a * noise3(p);
		p = p * 2.03 + vec3(1.7, 9.2, 3.4);
		a *= 0.5;
	}
	return v;
}

void vertex() {
	local_n = normalize(VERTEX);
}

void fragment() {
	vec3 n = normalize(local_n);
	float h = fbm3(n * 2.6 + seed * 3.1);
	vec3 col = mix(base_color.rgb, accent_color.rgb, smoothstep(0.38, 0.72, h));
	if (bands > 0.0) {
		float b = sin(n.y * 14.0 + fbm3(n * 4.0) * 4.0);
		col = mix(col, mix(base_color.rgb, accent_color.rgb, 0.5 + 0.5 * b), bands);
	}
	if (ice_caps > 0.0) {
		float cap = smoothstep(0.62, 0.82, abs(n.y) + (h - 0.5) * 0.25);
		col = mix(col, vec3(0.93, 0.97, 1.0), cap * ice_caps);
	}
	// Pale surfaces (gas giants, ice) would glare under the board's lights.
	float lum = dot(col, vec3(0.299, 0.587, 0.114));
	ALBEDO = col * mix(0.8, 0.55, smoothstep(0.45, 0.85, lum));
	ROUGHNESS = 0.8;
	SPECULAR = 0.15;
	float rim = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 2.5);
	EMISSION = atmosphere_color.rgb * rim * 0.45 + col * 0.05;
}
