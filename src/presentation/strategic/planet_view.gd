class_name PlanetView
extends Node2D
## Galaxy-map planet: a procedurally shaded, slowly spinning sphere
## (shaders/planet.gdshader, colors from the planet type's "surface"), with the
## owner's ring and the name drawn on top.

const SHADER := preload("res://src/presentation/shaders/planet.gdshader")
## Fraction of the quad the planet body fills (the rest is atmosphere).
const BODY_FRACTION := 0.72

var planet_id := ""
var display_name := ""
var radius := 13.0
var owner_color := Palette.NEUTRAL
var owned := false
var _overlay: Node2D


func setup(planet: Planet, data: DataRegistry) -> void:
	planet_id = planet.id
	display_name = planet.name
	var type_def: Dictionary = data.planet_types.get(planet.type, {})
	var surface: Dictionary = type_def.get("surface", {})
	radius = 15.0 * float(type_def.get("size", 1.0))

	var body := ColorRect.new()
	var quad := radius * 2.0 / BODY_FRACTION
	body.size = Vector2(quad, quad)
	body.position = -body.size / 2.0
	body.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var mat := ShaderMaterial.new()
	mat.shader = SHADER
	mat.set_shader_parameter("base_color", Color(surface.get("base", type_def.get("color", "#888888"))))
	mat.set_shader_parameter("accent_color", Color(surface.get("accent", "#bbbbbb")))
	mat.set_shader_parameter("atmosphere_color", Color(surface.get("atmosphere", "#88aaff")))
	mat.set_shader_parameter("bands", float(surface.get("bands", 0.0)))
	mat.set_shader_parameter("ice_caps", float(surface.get("ice_caps", 0.0)))
	mat.set_shader_parameter("planet_radius", BODY_FRACTION)
	var h := absi(hash(planet.id))
	mat.set_shader_parameter("seed", float(h % 1000) / 37.0)
	mat.set_shader_parameter("spin_speed", 0.03 + float(h % 7) * 0.01)
	body.material = mat
	add_child(body)

	_overlay = Node2D.new()
	add_child(_overlay)
	_overlay.draw.connect(_draw_overlay)


func refresh(planet: Planet, state: GalaxyState) -> void:
	owned = not planet.owner.is_empty()
	owner_color = Palette.team_color(state.faction(planet.owner)["team"]) if owned else Palette.NEUTRAL
	queue_redraw()
	_overlay.queue_redraw()


func _draw() -> void:
	# Soft owner glow behind the planet.
	if owned:
		draw_circle(Vector2.ZERO, radius + 9.0, Color(owner_color, 0.10))


func _draw_overlay() -> void:
	if owned:
		_overlay.draw_arc(Vector2.ZERO, radius + 5.0, 0, TAU, 48, Color(owner_color, 0.9), 2.0, true)
	else:
		_overlay.draw_arc(Vector2.ZERO, radius + 5.0, 0, TAU, 48, Color(owner_color, 0.35), 1.0, true)
	var font := ThemeDB.fallback_font
	_overlay.draw_string_outline(font, Vector2(-60, -radius - 10.0), display_name, HORIZONTAL_ALIGNMENT_CENTER, 120, 11,
			3, Color(0, 0, 0, 0.8))
	_overlay.draw_string(font, Vector2(-60, -radius - 10.0), display_name, HORIZONTAL_ALIGNMENT_CENTER, 120, 11,
			owner_color.lightened(0.25) if owned else Palette.TEXT_DIM)
