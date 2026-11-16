// Blinking navigation / beacon light: unshaded and bright, with a short
// flash every `period` seconds (offset by `phase` so ships don't sync up).
shader_type spatial;
render_mode unshaded, cull_disabled, shadows_disabled;

uniform vec4 color : source_color = vec4(1.0, 0.2, 0.2, 1.0);
uniform float period = 1.6;
uniform float phase = 0.0;
uniform float steady = 0.25;

void fragment() {
	float t = fract((TIME + phase) / period);
	float flash = smoothstep(0.0, 0.04, t) * (1.0 - smoothstep(0.12, 0.3, t));
	ALBEDO = color.rgb * (steady + 2.5 * flash);
}
