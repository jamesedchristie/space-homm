// Engine exhaust: an additive cone that fades from a hot core at the nozzle
// to nothing at the tip, flickering slightly. UV.y runs along the cone.
shader_type spatial;
render_mode unshaded, blend_add, cull_disabled, depth_draw_never, shadows_disabled;

uniform vec4 core_color : source_color = vec4(1.0, 0.95, 0.8, 1.0);
uniform vec4 tail_color : source_color = vec4(1.0, 0.45, 0.12, 1.0);
uniform float intensity = 0.75;
uniform float phase = 0.0;

void fragment() {
	float along = UV.y;  // 0 = nozzle, 1 = tip
	float edge = pow(clamp(abs(dot(NORMAL, VIEW)), 0.0, 1.0), 2.5);
	float flicker = 0.85 + 0.15 * sin(TIME * 37.0 + phase) * sin(TIME * 23.0 + phase * 1.7);
	vec3 col = mix(core_color.rgb, tail_color.rgb, smoothstep(0.0, 0.35, along));
	float fade = pow(1.0 - along, 2.2);
	ALBEDO = col * fade * edge * intensity * flicker;
}
