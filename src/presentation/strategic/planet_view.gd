class_name PlanetView
extends Node2D
## Galaxy-map marker for a planet: colored disc by type, owner ring, name.

var planet_id := ""
var display_name := ""
var body_color := Color.GRAY
var radius := 12.0
var owner_color := Palette.NEUTRAL
var owned := false
var ringed := false


func setup(planet: Planet, data: DataRegistry) -> void:
	planet_id = planet.id
	display_name = planet.name
	var type_def: Dictionary = data.planet_types.get(planet.type, {})
	body_color = Color(type_def.get("color", "#888888"))
	radius = 11.0 * float(type_def.get("size", 1.0))
	ringed = planet.type == "gas_giant"


func refresh(planet: Planet, state: GalaxyState) -> void:
	owned = not planet.owner.is_empty()
	owner_color = Palette.team_color(state.faction(planet.owner)["team"]) if owned else Palette.NEUTRAL
	queue_redraw()


func _draw() -> void:
	if owned:
		draw_circle(Vector2.ZERO, radius + 5.0, Color(owner_color, 0.25))
		draw_arc(Vector2.ZERO, radius + 4.0, 0, TAU, 40, owner_color, 2.0, true)
	else:
		draw_arc(Vector2.ZERO, radius + 4.0, 0, TAU, 40, Color(owner_color, 0.5), 1.0, true)
	draw_circle(Vector2.ZERO, radius, body_color.darkened(0.25))
	draw_circle(Vector2(-radius * 0.3, -radius * 0.3), radius * 0.55, body_color)
	if ringed:
		draw_set_transform(Vector2.ZERO, -0.35, Vector2(1.0, 0.35))
		draw_arc(Vector2.ZERO, radius * 1.6, 0, TAU, 40, Color(1, 0.9, 0.75, 0.7), 2.0, true)
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	var font := ThemeDB.fallback_font
	draw_string(font, Vector2(-60, -radius - 8.0), display_name, HORIZONTAL_ALIGNMENT_CENTER, 120, 11,
			owner_color.lightened(0.2) if owned else Palette.TEXT_DIM)
