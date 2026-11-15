class_name UnitView
extends Node2D
## Visual for one BattleUnit: a placeholder ship shape (or a sprite, if the
## unit JSON sets visual.sprite), shield/hull bars, name and status tags.
## Purely cosmetic: reads unit state, never changes it.

const PLACEHOLDER_SHAPES := {
	"frigate": [Vector2(1.0, 0), Vector2(0.45, 0.42), Vector2(-0.75, 0.42), Vector2(-1.0, 0.2),
			Vector2(-1.0, -0.2), Vector2(-0.75, -0.42), Vector2(0.45, -0.42)],
	"interceptor": [Vector2(1.0, 0), Vector2(-0.7, 0.75), Vector2(-0.35, 0), Vector2(-0.7, -0.75)],
	"drone": [Vector2(0.8, 0), Vector2(0, 0.6), Vector2(-0.8, 0), Vector2(0, -0.6)],
	"boarder": [Vector2(0.9, 0), Vector2(0.2, 0.55), Vector2(-0.6, 0.6), Vector2(-0.35, 0), Vector2(-0.6, -0.6),
			Vector2(0.2, -0.55)],
}
## Round-bodied placeholders for people (with a facing marker).
const ROUND_SHAPES := ["trooper", "hero"]

var unit_id := ""
var display_name := ""
var team_color := Color.WHITE
var shape := "frigate"
var radius := 20.0
var facing := 0.0
var is_active := false

var _hull := 1
var _max_hull := 1
var _shields := 0
var _max_shields := 1
var _status_text := ""
var _sprite: Sprite2D


func setup(unit: BattleUnit, def: Dictionary, cell_size: float) -> void:
	unit_id = unit.id
	display_name = unit.name
	team_color = Palette.team_color(unit.team)
	var visual: Dictionary = def.get("visual", {})
	shape = visual.get("placeholder", "frigate")
	radius = cell_size * 0.55 * float(visual.get("size", 1.0))
	facing = 0.0 if unit.team == 0 else PI

	var sprite_path: String = visual.get("sprite", "")
	if not sprite_path.is_empty() and ResourceLoader.exists(sprite_path):
		_sprite = Sprite2D.new()
		_sprite.texture = load(sprite_path)
		var tex_size := _sprite.texture.get_size()
		var s := radius * 2.0 / maxf(tex_size.x, tex_size.y)
		_sprite.scale = Vector2(s, s)
		_sprite.rotation = facing
		add_child(_sprite)
	refresh(unit)


func refresh(unit: BattleUnit) -> void:
	_hull = unit.hull
	_max_hull = maxi(1, unit.max_hull())
	_shields = unit.shields
	_max_shields = maxi(1, unit.max_shields())
	var tags := PackedStringArray()
	for s in unit.statuses:
		var label: String = s.def.get("name", s.id)
		tags.append(label if s.is_permanent() else "%s %d" % [label, s.remaining])
	_status_text = ", ".join(tags)
	queue_redraw()


func set_values(hull: int, shields: int) -> void:
	_hull = hull
	_shields = shields
	queue_redraw()


func set_active(active: bool) -> void:
	if is_active != active:
		is_active = active
		queue_redraw()


func face_towards(target: Vector2) -> void:
	if target.distance_to(position) > 1.0:
		_set_facing((target - position).angle())


func move_along(points: Array[Vector2], step_time: float = 0.11) -> void:
	if points.is_empty():
		return
	var tw := create_tween()
	var prev := position
	for p in points:
		tw.tween_callback(_set_facing.bind((p - prev).angle()))
		tw.tween_property(self, "position", p, step_time)
		prev = p
	await tw.finished


func play_hit() -> void:
	var tw := create_tween()
	tw.tween_property(self, "modulate", Color(2.0, 2.0, 2.0), 0.05)
	tw.tween_property(self, "modulate", Color.WHITE, 0.15)


func play_destroyed() -> void:
	var tw := create_tween().set_parallel()
	tw.tween_property(self, "scale", Vector2(1.7, 1.7), 0.4)
	tw.tween_property(self, "modulate:a", 0.0, 0.4)
	await tw.finished
	visible = false


func _set_facing(angle: float) -> void:
	facing = angle
	if _sprite != null:
		_sprite.rotation = angle
	queue_redraw()


func _draw() -> void:
	if is_active:
		draw_arc(Vector2.ZERO, radius * 1.15, 0, TAU, 40, Palette.ACTIVE, 2.0, true)

	if _sprite == null and shape in ROUND_SHAPES:
		draw_circle(Vector2.ZERO, radius * 0.62, team_color.darkened(0.45))
		draw_arc(Vector2.ZERO, radius * 0.62, 0, TAU, 24, team_color.lightened(0.2), 2.0, true)
		draw_line(Vector2.ZERO, Vector2(radius * 0.95, 0).rotated(facing), team_color.lightened(0.3), 3.0, true)
		if shape == "hero":
			_draw_star(Vector2.ZERO, radius * 0.32, Palette.ACTIVE)
	elif _sprite == null:
		var pts := PackedVector2Array()
		for p: Vector2 in PLACEHOLDER_SHAPES.get(shape, PLACEHOLDER_SHAPES["frigate"]):
			pts.append((p * radius).rotated(facing))
		draw_colored_polygon(pts, team_color.darkened(0.45))
		var closed := pts.duplicate()
		closed.append(pts[0])
		draw_polyline(closed, team_color.lightened(0.2), 2.0, true)
		# Engine glow at the stern.
		draw_circle(Vector2(-radius * 0.85, 0).rotated(facing), radius * 0.16, Color(1.0, 0.75, 0.35, 0.9))

	var bar_w := radius * 2.0
	var y := radius + 4.0
	_draw_bar(Vector2(-bar_w / 2.0, y), bar_w, float(_shields) / _max_shields, Palette.SHIELDS)
	_draw_bar(Vector2(-bar_w / 2.0, y + 5.0), bar_w, float(_hull) / _max_hull, Palette.HULL)

	var font := ThemeDB.fallback_font
	draw_string(font, Vector2(-60, y + 20.0), display_name, HORIZONTAL_ALIGNMENT_CENTER, 120, 11, Palette.TEXT)
	if not _status_text.is_empty():
		draw_string(font, Vector2(-70, -radius - 6.0), _status_text, HORIZONTAL_ALIGNMENT_CENTER, 140, 10, Palette.ACTIVE)


func _draw_star(center: Vector2, r: float, color: Color) -> void:
	var pts := PackedVector2Array()
	for i in 10:
		var rr := r if i % 2 == 0 else r * 0.45
		pts.append(center + Vector2.from_angle(-PI / 2 + i * PI / 5) * rr)
	draw_colored_polygon(pts, color)


func _draw_bar(origin: Vector2, width: float, ratio: float, color: Color) -> void:
	draw_rect(Rect2(origin, Vector2(width, 3.5)), Color(0, 0, 0, 0.6))
	draw_rect(Rect2(origin, Vector2(width * clampf(ratio, 0.0, 1.0), 3.5)), color)
