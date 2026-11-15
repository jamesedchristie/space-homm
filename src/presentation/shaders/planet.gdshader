// Procedural planet for the galaxy map: a lit, slowly spinning sphere with
// fbm surface detail, optional gas-giant bands and ice caps, and an
// atmosphere glow. Drawn on a square quad; the planet fills `planet_radius`
// of it and the atmosphere uses the rest.
shader_type canvas_item;

uniform vec4 base_color : source_color = vec4(0.25, 0.55, 0.38, 1.0);
uniform vec4 accent_color : source_color = vec4(0.78, 0.74, 0.55, 1.0);
uniform vec4 atmosphere_color : source_color = vec4(0.45, 0.75, 1.0, 0.9);
uniform float bands = 0.0;
uniform float ice_caps = 0.0;
uniform float seed = 1.0;
uniform float spin_speed = 0.04;
uniform float planet_radius = 0.72;
uniform vec3 light_dir = vec3(-0.55, -0.45, 0.7);

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7)) + seed * 13.17) * 43758.5453);
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
		p = p * 2.03 + vec2(1.7, 9.2);
		a *= 0.5;
	}
	return v;
}

void fragment() {
	vec2 p = (UV - 0.5) * 2.0;
	float d = length(p);
	vec3 L = normalize(light_dir);
	if (d > planet_radius) {
		// Atmosphere halo, brighter on the lit side.
		float t = 1.0 - smoothstep(planet_radius, 1.0, d);
		float lit = clamp(dot(normalize(p), L.xy) * 0.6 + 0.5, 0.15, 1.0);
		COLOR = vec4(atmosphere_color.rgb, atmosphere_color.a * t * t * lit);
	} else {
		vec2 q = p / planet_radius;
		float z = sqrt(max(1.0 - dot(q, q), 0.0));
		vec3 n = vec3(q, z);
		float lon = atan(n.x, n.z) + TIME * spin_speed;
		float lat = asin(clamp(n.y, -1.0, 1.0));
		vec2 tex = vec2(lon, lat) * 2.2;
		float h = fbm(tex * 1.6 + seed * 3.1);
		vec3 col = mix(base_color.rgb, accent_color.rgb, smoothstep(0.38, 0.72, h));
		if (bands > 0.0) {
			float b = sin(lat * 16.0 + fbm(tex * 2.5) * 4.0);
			col = mix(col, mix(base_color.rgb, accent_color.rgb, 0.5 + 0.5 * b), bands);
		}
		if (ice_caps > 0.0) {
			float cap = smoothstep(0.62, 0.82, abs(n.y) + (h - 0.5) * 0.25);
			col = mix(col, vec3(0.93, 0.97, 1.0), cap * ice_caps);
		}
		float diff = clamp(dot(n, L), 0.0, 1.0);
		col *= 0.12 + 1.0 * diff;
		float rim = pow(1.0 - z, 2.5);
		col += atmosphere_color.rgb * rim * (0.25 + 0.75 * diff) * 0.7;
		float edge = smoothstep(planet_radius, planet_radius - 0.03, d);
		COLOR = vec4(col, edge);
	}
}
