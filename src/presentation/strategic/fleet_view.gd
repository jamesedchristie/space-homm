class_name FleetView
extends Node2D
## Galaxy-map marker for a fleet: the sprite of its biggest ship (team-colored
## variant), escort pips for the rest, ship count, hull bar, name and pips for
## remaining moves.

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
var team := 0
var _lead_texture: Texture2D


func setup(fleet: Fleet, team: int, data: DataRegistry, owned_by_player: bool) -> void:
	fleet_id = fleet.id
	self.team = team
	color = Palette.team_color(team)
	show_moves = owned_by_player
	facing = 0.0 if team == 0 else PI
	refresh(fleet, data)


## max_moves_override: moves per turn including tech bonuses (-1 = base speed).
func refresh(fleet: Fleet, data: DataRegistry, max_moves_override: int = -1) -> void:
	display_name = fleet.name
	ship_count = fleet.ships.size()
	_lead_texture = _lead_sprite(fleet, data)
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


## Sprite of the fleet's largest ship, or null to fall back to chevrons.
func _lead_sprite(fleet: Fleet, data: DataRegistry) -> Texture2D:
	var best: Dictionary = {}
	for ship in fleet.ships:
		var def: Dictionary = data.units[ship["unit"]]
		if best.is_empty() or def["stats"]["max_hull"] > best["stats"]["max_hull"]:
			best = def
	var visual: Dictionary = best.get("visual", {})
	var variants: Array = visual.get("sprite_variants", Palette.TEAM_SPRITE_COLORS)
	var path: String = visual.get("sprite", "").replace("{team}", variants[team % variants.size()])
	return load(path) if not path.is_empty() and ResourceLoader.exists(path) else null


func _draw() -> void:
	if selected:
		draw_arc(Vector2.ZERO, 19.0, 0, TAU, 32, Palette.ACTIVE, 2.0, true)
	draw_circle(Vector2.ZERO, 15.0, Color(0, 0, 0, 0.55))
	if _lead_texture != null:
		draw_circle(Vector2.ZERO, 15.0, Color(color, 0.18))
		var s := 26.0 / maxf(_lead_texture.get_width(), _lead_texture.get_height())
		draw_set_transform(Vector2.ZERO, facing + PI / 2.0, Vector2(s, s))
		draw_texture(_lead_texture, -_lead_texture.get_size() / 2.0)
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
		# One escort pip per additional ship.
		for i in mini(ship_count - 1, 5):
			draw_circle(Vector2(-12 + i * 5.0, 13).rotated(0), 1.8, color.lightened(0.3))
	var offsets := [Vector2(4, 0), Vector2(-5, -7), Vector2(-5, 7)]
	for i in (mini(ship_count, 3) if _lead_texture == null else 0):
		var o: Vector2 = offsets[i]
		var pts := PackedVector2Array()
		for p: Vector2 in [Vector2(7, 0), Vector2(-5, 5), Vector2(-2, 0), Vector2(-5, -5)]:
			pts.append((p + o).rotated(facing))
		draw_colored_polygon(pts, color)
	var font := ThemeDB.fallback_font
	draw_string(font, Vector2(8, 16), str(ship_count), HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Palette.TEXT)
	var spent := show_moves and moves_left <= 0 and not selected
	draw_string(font, Vector2(-60, 30), display_name, HORIZONTAL_ALIGNMENT_CENTER, 120, 10,
			Palette.TEXT_DIM if spent else color.lightened(0.3))
	# Hull bar.
	draw_rect(Rect2(Vector2(-14, 19), Vector2(28, 2.5)), Color(0, 0, 0, 0.6))
	draw_rect(Rect2(Vector2(-14, 19), Vector2(28 * clampf(hull_ratio, 0, 1), 2.5)), Palette.HULL)
	if show_moves:
		for i in max_moves:
			var c := Palette.ACTIVE if i < moves_left else Color(1, 1, 1, 0.15)
			draw_circle(Vector2(-((max_moves - 1) * 3.0) + i * 6.0, -20), 1.8, c)
		if moves_left > 0 and not selected:
			FleetMarkers.draw_ready_chevron(self, Vector2(0, -30))


func _process(_delta: float) -> void:
	# The ready arrow bobs.
	if show_moves and moves_left > 0 and not selected and visible:
		queue_redraw()
