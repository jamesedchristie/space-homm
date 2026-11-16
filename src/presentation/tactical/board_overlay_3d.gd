class_name BoardOverlay3D
extends Node2D
## 2D layer over the 3D board: health/shield bars, names and status tags for
## each visible unit, and labels for objective/trigger markers, projected from
## 3D positions every frame so text stays crisp at any camera angle.

var board: BattleBoard3D


func _process(_delta: float) -> void:
	queue_redraw()


func _draw() -> void:
	if board == null or board.camera == null:
		return
	var cam := board.camera
	var font := ThemeDB.fallback_font
	for m: Dictionary in board.marker_labels:
		var pos: Vector3 = m["pos"]
		if cam.is_position_behind(pos):
			continue
		var p := cam.unproject_position(pos)
		draw_string_outline(font, p + Vector2(-30, 0), m["label"], HORIZONTAL_ALIGNMENT_CENTER, 60, 22, 5, Color(0, 0, 0, 0.8))
		draw_string(font, p + Vector2(-30, 0), m["label"], HORIZONTAL_ALIGNMENT_CENTER, 60, 22, m["color"])
	for view: Unit3D in board.views.values():
		if not view.visible or not view.is_inside_tree():
			continue
		var anchor := view.global_position + Vector3(0, view.label_height, 0)
		if cam.is_position_behind(anchor):
			continue
		var p := cam.unproject_position(anchor)
		var w := 46.0
		_bar(p + Vector2(-w / 2.0, 0), w, float(view.shields) / view.max_shields, Palette.SHIELDS)
		_bar(p + Vector2(-w / 2.0, 6), w, float(view.hull) / view.max_hull, Palette.HULL)
		var name_color := Palette.ACTIVE if view.is_active else Palette.TEXT
		draw_string_outline(font, p + Vector2(-70, -6), view.display_name, HORIZONTAL_ALIGNMENT_CENTER, 140, 12, 4, Color(0, 0, 0, 0.85))
		draw_string(font, p + Vector2(-70, -6), view.display_name, HORIZONTAL_ALIGNMENT_CENTER, 140, 12, name_color)
		if not view.status_text.is_empty():
			draw_string_outline(font, p + Vector2(-80, -20), view.status_text, HORIZONTAL_ALIGNMENT_CENTER, 160, 10, 4, Color(0, 0, 0, 0.85))
			draw_string(font, p + Vector2(-80, -20), view.status_text, HORIZONTAL_ALIGNMENT_CENTER, 160, 10, Palette.ACTIVE)


func _bar(origin: Vector2, width: float, ratio: float, color: Color) -> void:
	draw_rect(Rect2(origin - Vector2(1, 1), Vector2(width + 2, 5.5)), Color(0, 0, 0, 0.75))
	draw_rect(Rect2(origin, Vector2(width * clampf(ratio, 0.0, 1.0), 3.5)), color)
	draw_rect(Rect2(origin, Vector2(width * clampf(ratio, 0.0, 1.0), 1.2)), color.lightened(0.4))
