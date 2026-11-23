// A star's corona: a camera-facing quad with a soft radial glow and faint,
// slowly turning rays. Additive, so it only brightens.
shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, shadows_disabled;

uniform vec4 corona_color : source_color = vec4(1.0, 0.8, 0.5, 1.0);
uniform float intensity = 1.0;
// Radius of the star itself as a fraction of the quad's half-size.
uniform float core = 0.33;

void vertex() {
	// Billboard: keep the quad facing the camera.
	MODELVIEW_MATRIX = VIEW_MATRIX * mat4(INV_VIEW_MATRIX[0], INV_VIEW_MATRIX[1], INV_VIEW_MATRIX[2], MODEL_MATRIX[3]);
	MODELVIEW_MATRIX = MODELVIEW_MATRIX * mat4(vec4(length(MODEL_MATRIX[0].xyz), 0, 0, 0), vec4(0, length(MODEL_MATRIX[1].xyz), 0, 0),
			vec4(0, 0, length(MODEL_MATRIX[2].xyz), 0), vec4(0, 0, 0, 1));
}

void fragment() {
	vec2 d = UV * 2.0 - 1.0;
	float r = length(d);
	float a = atan(d.y, d.x);
	float outside = max(r - core, 0.0) / (1.0 - core);
	float glow = exp(-outside * 5.5) * (1.0 - smoothstep(0.85, 1.0, r));
	float rays = 0.5 + 0.5 * sin(a * 9.0 + TIME * 0.15) * sin(a * 5.0 - TIME * 0.11);
	glow *= 0.75 + 0.5 * rays * smoothstep(0.0, 0.4, outside);
	ALBEDO = corona_color.rgb * glow * intensity;
}
