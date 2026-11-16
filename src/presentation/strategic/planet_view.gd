class_name PlanetView
extends Node2D
## A star system on the 2D galaxy map: the star, its bodies as dots on
## orbit circles (developed ones ringed in the owner's color), the owner's
## ring and the name.

var planet_id := ""
var display_name := ""
var owner_color := Palette.NEUTRAL
var owned := false
var _star_color := Color.WHITE
var _bodies: Array[Dictionary] = []  # {"color", "r", "radius", "angle", "belt", "developed"}
var _t := 0.0


func setup(planet: Planet, data: DataRegistry) -> void:
	planet_id = planet.id
	display_name = planet.name
	_star_color = Color(data.star_types.get(planet.star, {}).get("color", "#ffd88a"))
	var h := absi(hash(planet.id))
	var n := planet.bodies.size()
	for i in n:
		var b: Dictionary = planet.bodies[i]
		var def: Dictionary = data.body_types.get(b["type"], {})
		_bodies.append({"color": Color(def.get("surface", {}).get("accent", "#aaaaaa")),
				"r": 1.5 + 2.2 * float(def.get("size", 0.6)), "radius": lerpf(6.0, 15.0, float(i) / maxf(1.0, float(n - 1))),
				"angle": float((h >> (i * 3)) % 628) / 100.0, "belt": b["type"] == "asteroid_belt", "developed": false})


func refresh(planet: Planet, state: GalaxyState) -> void:
	owned = not planet.owner.is_empty()
	owner_color = Palette.team_color(state.faction(planet.owner)["team"]) if owned else Palette.NEUTRAL
	for i in mini(_bodies.size(), planet.bodies.size()):
		_bodies[i]["developed"] = not planet.bodies[i]["buildings"].is_empty()
	queue_redraw()


func _process(delta: float) -> void:
	_t += delta
	queue_redraw()


func _draw() -> void:
	draw_arc(Vector2.ZERO, 18.0, 0, TAU, 48, Color(owner_color, 0.9 if owned else 0.3), 2.0 if owned else 1.0, true)
	for b in _bodies:
		draw_arc(Vector2.ZERO, b["radius"], 0, TAU, 32, Color(0.6, 0.75, 1.0, 0.15), 1.0, true)
	draw_circle(Vector2.ZERO, 6.0, Color(_star_color, 0.25))
	draw_circle(Vector2.ZERO, 3.5, _star_color.lightened(0.3))
	for b in _bodies:
		if b["belt"]:
			for k in 14:
				var a: float = TAU * k / 14.0 + _t * 0.05
				draw_circle(Vector2(cos(a), sin(a)) * float(b["radius"]), 0.9, Color(b["color"], 0.8))
			continue
		var a: float = float(b["angle"]) + _t * 0.4 / float(b["radius"]) * 4.0
		var p := Vector2(cos(a), sin(a)) * float(b["radius"])
		draw_circle(p, b["r"], b["color"])
		if b["developed"] and owned:
			draw_arc(p, float(b["r"]) + 1.5, 0, TAU, 12, owner_color, 1.0, true)
	var font := ThemeDB.fallback_font
	draw_string_outline(font, Vector2(-60, -22), display_name, HORIZONTAL_ALIGNMENT_CENTER, 120, 11, 3, Color(0, 0, 0, 0.8))
	draw_string(font, Vector2(-60, -22), display_name, HORIZONTAL_ALIGNMENT_CENTER, 120, 11,
			owner_color.lightened(0.25) if owned else Palette.TEXT_DIM)
