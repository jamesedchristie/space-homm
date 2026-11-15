class_name AnomalyView
extends Node2D
## Galaxy-map marker for an anomaly (a mission site): a pulsing ring and "?".

var anomaly_id := ""
var display_name := ""
var _t := 0.0


func setup(anomaly: Dictionary) -> void:
	anomaly_id = anomaly["id"]
	display_name = anomaly["name"]
	queue_redraw()


func _process(delta: float) -> void:
	_t += delta
	queue_redraw()


func _draw() -> void:
	var color := Color("c75bd6")
	var pulse := 0.5 + 0.5 * sin(_t * 3.0)
	draw_circle(Vector2.ZERO, 13.0, Color(color, 0.18 + 0.12 * pulse))
	draw_arc(Vector2.ZERO, 11.0 + 3.0 * pulse, 0, TAU, 32, Color(color, 0.9), 2.0, true)
	var font := ThemeDB.fallback_font
	draw_string(font, Vector2(-10, 6), "?", HORIZONTAL_ALIGNMENT_CENTER, 20, 16, Color.WHITE)
	draw_string(font, Vector2(-60, -18), display_name, HORIZONTAL_ALIGNMENT_CENTER, 120, 10, color.lightened(0.3))
