class_name FleetView
extends Node2D
## Galaxy-map marker for a fleet: one chevron per ship (up to 3), ship count,
## name, and pips for remaining moves. Placeholder art; swap for sprites later.

var fleet_id := ""
var display_name := ""
var color := Color.WHITE
var ship_count := 0
var moves_left := 0
var max_moves := 0
var hull_ratio := 1.0
var selected := false
var show_moves := false
var facing := 0.0


func setup(fleet: Fleet, team: int, data: DataRegistry, owned_by_player: bool) -> void:
	fleet_id = fleet.id
	color = Palette.team_color(team)
	show_moves = owned_by_player
	facing = 0.0 if team == 0 else PI
	refresh(fleet, data)


## max_moves_override: moves per turn including tech bonuses (-1 = base speed).
func refresh(fleet: Fleet, data: DataRegistry, max_moves_override: int = -1) -> void:
	display_name = fleet.name
	ship_count = fleet.ships.size()
	moves_left = fleet.moves_left
	max_moves = max_moves_override if max_moves_override >= 0 else fleet.speed(data)
	hull_ratio = fleet.hull_ratio(data)
	queue_redraw()


func set_selected(value: bool) -> void:
	if selected != value:
		selected = value
		queue_redraw()


func move_along(points: Array[Vector2], step_time: float = 0.12) -> void:
	if points.is_empty():
		return
	var tw := create_tween()
	var prev := position
	for p in points:
		tw.tween_callback(_set_facing.bind((p - prev).angle()))
		tw.tween_property(self, "position", p, step_time)
		prev = p
	await tw.finished


func play_destroyed() -> void:
	var tw := create_tween().set_parallel()
	tw.tween_property(self, "scale", Vector2(1.8, 1.8), 0.4)
	tw.tween_property(self, "modulate:a", 0.0, 0.4)
	await tw.finished
	visible = false


func _set_facing(angle: float) -> void:
	facing = angle
	queue_redraw()


func _draw() -> void:
	if selected:
		draw_arc(Vector2.ZERO, 19.0, 0, TAU, 32, Palette.ACTIVE, 2.0, true)
	draw_circle(Vector2.ZERO, 15.0, Color(0, 0, 0, 0.55))
	var offsets := [Vector2(4, 0), Vector2(-5, -7), Vector2(-5, 7)]
	for i in mini(ship_count, 3):
		var o: Vector2 = offsets[i]
		var pts := PackedVector2Array()
		for p: Vector2 in [Vector2(7, 0), Vector2(-5, 5), Vector2(-2, 0), Vector2(-5, -5)]:
			pts.append((p + o).rotated(facing))
		draw_colored_polygon(pts, color)
	var font := ThemeDB.fallback_font
	draw_string(font, Vector2(8, 16), str(ship_count), HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Palette.TEXT)
	draw_string(font, Vector2(-60, 30), display_name, HORIZONTAL_ALIGNMENT_CENTER, 120, 10, color.lightened(0.3))
	# Hull bar.
	draw_rect(Rect2(Vector2(-14, 19), Vector2(28, 2.5)), Color(0, 0, 0, 0.6))
	draw_rect(Rect2(Vector2(-14, 19), Vector2(28 * clampf(hull_ratio, 0, 1), 2.5)), Palette.HULL)
	if show_moves:
		for i in max_moves:
			var c := Palette.ACTIVE if i < moves_left else Color(1, 1, 1, 0.15)
			draw_circle(Vector2(-((max_moves - 1) * 3.0) + i * 6.0, -20), 1.8, c)
