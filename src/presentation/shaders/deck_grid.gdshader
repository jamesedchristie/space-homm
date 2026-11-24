shader_type spatial;
// The square grid's lines on a station deck (high-quality look): faint,
// and only over explored cells (the fog-of-war mask of deck_surface.gdshader).

render_mode unshaded, blend_mix, cull_disabled, depth_draw_never, fog_disabled;

uniform vec4 color : source_color = vec4(0.45, 0.7, 0.95, 0.11);
uniform float cell_size = 1.8;
uniform sampler2D fog_mask : filter_linear, repeat_disable;
uniform vec2 fog_origin = vec2(0.0);
uniform vec2 fog_size = vec2(1.0);
uniform float fog_on = 0.0;

varying vec3 wpos;

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	float seen = 1.0;
	if (fog_on > 0.5) {
		vec2 m = texture(fog_mask, ((wpos.xz - fog_origin) / cell_size + 0.5) / fog_size).rg;
		seen = smoothstep(0.5, 0.78, m.r) * mix(0.5, 1.0, smoothstep(0.2, 0.8, m.g));
	}
	if (seen < 0.01) {
		discard;
	}
	ALBEDO = color.rgb;
	ALPHA = color.a * seen;
}
