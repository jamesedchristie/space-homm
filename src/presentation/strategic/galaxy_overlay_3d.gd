class_name GalaxyOverlay3D
extends Node2D
## 2D layer over the 3D galaxy board: planet and anomaly names, and each
## visible fleet's name, ship count, hull bar and remaining-move pips,
## projected from 3D every frame so text stays crisp at any camera angle.

var board: GalaxyBoard3D


func _process(_delta: float) -> void:
	queue_redraw()


func _draw() -> void:
	if board == null or board.camera == null:
		return
	var font := ThemeDB.fallback_font
	for pv: Planet3D in board.planet_views.values():
		if not pv.visible:
			continue
		var p: Variant = _project(pv, pv.label_height)
		if p != null:
			_text(p + Vector2(-70, 0), pv.display_name, 140, 12, pv.owner_color.lightened(0.25) if pv.owned else Palette.TEXT_DIM)
	for av: Anomaly3D in board.anomaly_views.values():
		if not av.visible:
			continue
		var p: Variant = _project(av, av.label_height)
		if p != null:
			_text(p + Vector2(-70, 0), av.display_name, 140, 11, Anomaly3D.COLOR.lightened(0.35))
	for fv: Fleet3D in board.fleet_views.values():
		if not fv.visible or not fv.is_inside_tree():
			continue
		var p: Variant = _project(fv, fv.label_height)
		if p == null:
			continue
		var w := 34.0
		draw_rect(Rect2(p + Vector2(-w / 2.0 - 1, -1), Vector2(w + 2, 5)), Color(0, 0, 0, 0.75))
		draw_rect(Rect2(p + Vector2(-w / 2.0, 0), Vector2(w * clampf(fv.hull_ratio, 0, 1), 3)), Palette.HULL)
		_text(p + Vector2(w / 2.0 + 4, 6), str(fv.ship_count), 20, 11, Palette.TEXT, HORIZONTAL_ALIGNMENT_LEFT)
		_text(p + Vector2(-70, -5), fv.display_name, 140, 11, Palette.ACTIVE if fv.selected else fv.color.lightened(0.3))
		if fv.show_moves:
			for i in fv.max_moves:
				var c := Palette.ACTIVE if i < fv.moves_left else Color(1, 1, 1, 0.2)
				draw_circle(p + Vector2(-((fv.max_moves - 1) * 3.5) + i * 7.0, 10), 2.2, c)


func _project(node: Node3D, height: float) -> Variant:
	var at := node.global_position + Vector3(0, height, 0)
	if board.camera.is_position_behind(at):
		return null
	return board.camera.unproject_position(at)


func _text(pos: Vector2, text: String, width: float, size: int, color: Color,
		align: HorizontalAlignment = HORIZONTAL_ALIGNMENT_CENTER) -> void:
	var font := ThemeDB.fallback_font
	draw_string_outline(font, pos, text, align, width, size, 4, Color(0, 0, 0, 0.85))
	draw_string(font, pos, text, align, width, size, color)
