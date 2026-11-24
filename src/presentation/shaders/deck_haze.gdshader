shader_type fog;
// Haze hanging in a station deck's rooms (a FogVolume over the board, high-
// quality look only): densest near the floor, slowly drifting, and only over
// explored cells (the same fog-of-war mask as deck_surface.gdshader), so the
// ceiling lamps throw soft shafts of light without giving away hidden rooms.

uniform vec4 albedo : source_color = vec4(0.5, 0.55, 0.65, 1.0);
uniform float density = 0.05;
uniform float height = 2.6;
uniform float cell_size = 1.8;
uniform sampler2D fog_mask : filter_linear, repeat_disable;
uniform vec2 fog_origin = vec2(0.0);
uniform vec2 fog_size = vec2(1.0);
uniform float fog_on = 0.0;

float hash2(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash2(i), hash2(i + vec2(1.0, 0.0)), f.x),
			mix(hash2(i + vec2(0.0, 1.0)), hash2(i + vec2(1.0, 1.0)), f.x), f.y);
}

void fog() {
	float explored = 1.0;
	if (fog_on > 0.5) {
		vec2 uv = ((WORLD_POSITION.xz - fog_origin) / cell_size + 0.5) / fog_size;
		explored = smoothstep(0.5, 0.8, texture(fog_mask, uv).r);
	}
	float y = clamp(WORLD_POSITION.y / height, 0.0, 1.0);
	float falloff = 1.0 - smoothstep(0.15, 1.0, y);
	vec2 drift = WORLD_POSITION.xz * 0.35 + vec2(TIME * 0.05, TIME * 0.03);
	float wisps = 0.7 + 0.6 * vnoise(drift) * vnoise(drift * 2.3 + 4.0);
	DENSITY = density * falloff * wisps * explored;
	ALBEDO = albedo.rgb;
}
