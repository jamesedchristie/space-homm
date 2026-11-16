// Glow shell around a planet: drawn on the inside (back faces) of a slightly
// larger sphere, brightest next to the planet and fading to nothing at the
// shell's silhouette.
shader_type spatial;
render_mode unshaded, blend_add, cull_front, depth_draw_never;

uniform vec4 atmosphere_color : source_color = vec4(0.45, 0.75, 1.0, 0.9);
uniform float strength = 1.2;

void fragment() {
	float d = abs(dot(NORMAL, VIEW));
	ALBEDO = atmosphere_color.rgb * pow(d, 3.0) * atmosphere_color.a * strength;
}
