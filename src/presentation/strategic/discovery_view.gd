class_name DiscoveryView
extends Node2D
## A one-time find on the 2D galaxy map: a small pulsing diamond in the
## find's color with its name.

var discovery_id := ""
var display_name := ""
var color := Color.WHITE
var _t := 0.0


func setup(find: Dictionary, data: DataRegistry) -> void:
	discovery_id = find["id"]
	var def: Dictionary = data.discoveries.get(find["kind"], {})
	display_name = def.get("name", find["kind"])
	color = Color(def.get("color", "#ffffff"))
	queue_redraw()


func _process(delta: float) -> void:
	_t += delta
	queue_redraw()


func _draw() -> void:
	var pulse := 0.5 + 0.5 * sin(_t * 2.5)
	var r := 6.0 + pulse
	draw_colored_polygon(PackedVector2Array([Vector2(0, -r), Vector2(r, 0), Vector2(0, r), Vector2(-r, 0)]), Color(color, 0.85))
	draw_arc(Vector2.ZERO, 10.0 + 2.0 * pulse, 0, TAU, 24, Color(color, 0.5), 1.5, true)
	draw_string(ThemeDB.fallback_font, Vector2(-60, -14), display_name, HORIZONTAL_ALIGNMENT_CENTER, 120, 10, color.lightened(0.2))
