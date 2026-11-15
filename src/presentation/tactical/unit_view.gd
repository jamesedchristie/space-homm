class_name UnitView
extends Node2D
## Visual for one BattleUnit: a sprite (unit JSON visual.sprite, with "{team}"
## replaced by the team's color variant) or a placeholder shape, plus a team
## glow, engine glow, shield flashes, bars, name and status tags.
## Purely cosmetic: reads unit state, never changes it.

const SHIELD_TEXTURE := preload("res://assets/kenney_space_shooter/effects/shield2.png")

const PLACEHOLDER_SHAPES := {
	"frigate": [Vector2(1.0, 0), Vector2(0.45, 0.42), Vector2(-0.75, 0.42), Vector2(-1.0, 0.2),
			Vector2(-1.0, -0.2), Vector2(-0.75, -0.42), Vector2(0.45, -0.42)],
	"interceptor": [Vector2(1.0, 0), Vector2(-0.7, 0.75), Vector2(-0.35, 0), Vector2(-0.7, -0.75)],
	"drone": [Vector2(0.8, 0), Vector2(0, 0.6), Vector2(-0.8, 0), Vector2(0, -0.6)],
	"destroyer": [Vector2(1.0, 0), Vector2(0.6, 0.35), Vector2(0.2, 0.5), Vector2(-0.9, 0.5), Vector2(-1.0, 0.25),
			Vector2(-1.0, -0.25), Vector2(-0.9, -0.5), Vector2(0.2, -0.5), Vector2(0.6, -0.35)],
	"station": [Vector2(0.75, 0.3), Vector2(0.3, 0.75), Vector2(-0.3, 0.75), Vector2(-0.75, 0.3),
			Vector2(-0.75, -0.3), Vector2(-0.3, -0.75), Vector2(0.3, -0.75), Vector2(0.75, -0.3)],
}
## Round-bodied placeholders for people (with a facing marker).
const ROUND_SHAPES := ["trooper", "hero", "boarder"]

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
var _is_ship := false
var _spins := false
var _t := 0.0


func setup(unit: BattleUnit, def: Dictionary, cell_size: float) -> void:
	unit_id = unit.id
	display_name = unit.name
	team_color = Palette.team_color(unit.team)
	var visual: Dictionary = def.get("visual", {})
	shape = visual.get("placeholder", "frigate")
	radius = cell_size * 0.55 * float(visual.get("size", 1.0))
	facing = 0.0 if unit.team == 0 else PI

	_is_ship = "ship" in unit.tags
	_spins = "immobile" in unit.tags
	var sprite_path: String = visual.get("sprite", "")
	var variants: Array = visual.get("sprite_variants", Palette.TEAM_SPRITE_COLORS)
	sprite_path = sprite_path.replace("{team}", variants[unit.team % variants.size()])
	if not sprite_path.is_empty() and ResourceLoader.exists(sprite_path):
		_sprite = Sprite2D.new()
		_sprite.texture = load(sprite_path)
		var tex_size := _sprite.texture.get_size()
		var s := radius * 2.3 / maxf(tex_size.x, tex_size.y)
		_sprite.scale = Vector2(s, s)
		add_child(_sprite)
		_set_facing(facing)
	set_process(_spins)
	refresh(unit)


func _process(delta: float) -> void:
	# Stations turn slowly in place.
	_t += delta
	if _sprite != null:
		_sprite.rotation = _t * 0.4


func refresh(unit: BattleUnit) -> void:
	_hull = unit.hull
	_max_hull = maxi(1, unit.max_hull())
	_shields = unit.shields
	_max_shields = maxi(1, unit.max_shields())
	var tags := PackedStringArray()
	for s in unit.statuses:
		if s.def.get("hidden", false):
			continue
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


## Shield flare facing the attacker (angle from this unit towards the source).
func play_shield_hit(toward_source: float) -> void:
	var flare := Sprite2D.new()
	flare.texture = SHIELD_TEXTURE
	var s := radius * 2.8 / maxf(SHIELD_TEXTURE.get_width(), SHIELD_TEXTURE.get_height())
	flare.scale = Vector2(s, s)
	flare.rotation = toward_source + PI / 2.0
	flare.modulate = Color(Palette.SHIELDS, 0.9)
	var mat := CanvasItemMaterial.new()
	mat.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	flare.material = mat
	add_child(flare)
	var tw := flare.create_tween()
	tw.tween_property(flare, "modulate:a", 0.0, 0.45)
	tw.tween_callback(flare.queue_free)


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
	if _sprite != null and not _spins:
		_sprite.rotation = angle + PI / 2.0  # Kenney ships point up
	queue_redraw()


func _draw() -> void:
	if is_active:
		draw_circle(Vector2.ZERO, radius * 1.2, Color(Palette.ACTIVE, 0.10))
		draw_arc(Vector2.ZERO, radius * 1.2, 0, TAU, 48, Palette.ACTIVE, 2.0, true)
	# Team glow under the ship, so sides read at a glance.
	draw_circle(Vector2.ZERO, radius * 0.95, Color(team_color, 0.12))
	draw_arc(Vector2.ZERO, radius * 0.95, 0, TAU, 40, Color(team_color, 0.35), 1.0, true)
	if _sprite != null and _is_ship and not _spins:
		var stern := Vector2(-radius * 0.95, 0).rotated(facing)
		draw_circle(stern, radius * 0.34, Color(1.0, 0.6, 0.25, 0.18))
		draw_circle(stern, radius * 0.18, Color(1.0, 0.85, 0.5, 0.55))

	if _sprite == null and shape in ROUND_SHAPES:
		_draw_person()
	elif _sprite == null:
		var pts := PackedVector2Array()
		for p: Vector2 in PLACEHOLDER_SHAPES.get(shape, PLACEHOLDER_SHAPES["frigate"]):
			pts.append((p * radius).rotated(facing))
		draw_colored_polygon(pts, team_color.darkened(0.45))
		var closed := pts.duplicate()
		closed.append(pts[0])
		draw_polyline(closed, team_color.lightened(0.2), 2.0, true)
		if shape == "drone":
			draw_circle(Vector2(radius * 0.2, 0).rotated(facing), radius * 0.2, Color(1.0, 0.3, 0.25, 0.4))
			draw_circle(Vector2(radius * 0.2, 0).rotated(facing), radius * 0.1, Color(1.0, 0.55, 0.45))
		else:
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


## Top-down soldier: shoulders, rifle, helmet with visor. Heroes get a gold
## outline and badge; boarders a spiked helmet.
func _draw_person() -> void:
	var fwd := Vector2.from_angle(facing)
	var side := fwd.orthogonal()
	var outline := Palette.ACTIVE if shape == "hero" else team_color.lightened(0.2)
	var shoulders := PackedVector2Array()
	for i in 18:
		var a := TAU * i / 18.0
		shoulders.append(fwd * cos(a) * radius * 0.36 + side * sin(a) * radius * 0.72)
	draw_colored_polygon(shoulders, team_color.darkened(0.4))
	var closed := shoulders.duplicate()
	closed.append(shoulders[0])
	draw_polyline(closed, outline, 2.0 if shape == "hero" else 1.5, true)
	# Rifle held on the right side.
	var grip := side * radius * 0.38
	draw_line(grip - fwd * radius * 0.1, grip + fwd * radius * 0.95, Color(0.2, 0.22, 0.26), 5.0, true)
	draw_line(grip, grip + fwd * radius * 0.95, Color(0.7, 0.74, 0.8), 2.5, true)
	# Helmet and visor.
	var head := fwd * radius * 0.06
	if shape == "boarder":
		for k in [-1.0, 0.0, 1.0]:
			draw_line(head, head + Vector2.from_angle(facing + PI + k * 0.6) * radius * 0.48, Color(0.75, 0.3, 0.2), 3.0, true)
	draw_circle(head, radius * 0.3, Color(0.78, 0.8, 0.84) if shape != "boarder" else Color(0.45, 0.3, 0.28))
	draw_arc(head, radius * 0.24, facing - 0.85, facing + 0.85, 10, team_color.lightened(0.45), 3.5, true)
	if shape == "hero":
		_draw_star(-side * radius * 0.42, radius * 0.17, Palette.ACTIVE)


func _draw_star(center: Vector2, r: float, color: Color) -> void:
	var pts := PackedVector2Array()
	for i in 10:
		var rr := r if i % 2 == 0 else r * 0.45
		pts.append(center + Vector2.from_angle(-PI / 2 + i * PI / 5) * rr)
	draw_colored_polygon(pts, color)


func _draw_bar(origin: Vector2, width: float, ratio: float, color: Color) -> void:
	draw_rect(Rect2(origin - Vector2(1, 1), Vector2(width + 2, 5.5)), Color(0, 0, 0, 0.7))
	draw_rect(Rect2(origin, Vector2(width * clampf(ratio, 0.0, 1.0), 3.5)), color)
	draw_rect(Rect2(origin, Vector2(width * clampf(ratio, 0.0, 1.0), 1.2)), color.lightened(0.4))
