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
	# Collect every label as a box, stagger overlapping ones, then draw.
	var items: Array[Dictionary] = []
	var boxes: Array[Rect2] = []
	for pv: Planet3D in board.planet_views.values():
		if not pv.visible:
			continue
		if pv.owned:
			# Above the system, like a city banner.
			var at: Variant = _project(pv, pv.label_height + 0.35)
			if at != null:
				var w := _banner_width(pv)
				items.append({"banner": pv, "at": at})
				boxes.append(Rect2(at + Vector2(-w / 2.0, -16), Vector2(w, 22)))
		else:
			_add_text_item(items, boxes, pv, pv.label_height, pv.display_name, 12, Palette.TEXT_DIM)
	for av: Anomaly3D in board.anomaly_views.values():
		if av.visible:
			_add_text_item(items, boxes, av, av.label_height, av.display_name, 11, Anomaly3D.COLOR.lightened(0.35))
	for dv: Discovery3D in board.discovery_views.values():
		if dv.visible:
			_add_text_item(items, boxes, dv, dv.label_height, dv.display_name, 10, dv.color.lightened(0.2))
	for fv: Fleet3D in board.fleet_views.values():
		if not fv.visible or not fv.is_inside_tree():
			continue
		var p: Variant = _project(fv, fv.label_height)
		if p == null:
			continue
		var w := maxf(44.0, font.get_string_size(fv.display_name, HORIZONTAL_ALIGNMENT_LEFT, -1, 11).x)
		items.append({"fleet": fv, "at": p})
		boxes.append(Rect2(p + Vector2(-w / 2.0, -16), Vector2(w, 30)))
	var offsets := LabelLayout.resolve(boxes)
	for i in items.size():
		var item: Dictionary = items[i]
		var anchor: Vector2 = item["at"]
		var p := anchor + Vector2(0, offsets[i])
		if offsets[i] < -1.0:
			draw_line(anchor + Vector2(0, 4), p + Vector2(0, 6), Color(1, 1, 1, 0.22), 1.0)
		if item.has("fleet"):
			_draw_fleet(item["fleet"], p)
		elif item.has("banner"):
			_draw_banner(item["banner"], p)
		else:
			_text(p + Vector2(-70, 0), item["text"], 140, item["size"], item["color"])


const BANNER_FONT := 12


func _banner_width(pv: Planet3D) -> float:
	var text_w := ThemeDB.fallback_font.get_string_size(pv.display_name, HORIZONTAL_ALIGNMENT_LEFT, -1, BANNER_FONT).x
	var planet: Planet = board.engine.state.planets.get(pv.planet_id)
	var pips := planet.bodies.size() if planet != null else 0
	return text_w + 22.0 + pips * 7.0 + 26.0


## Civ-style city banner for an owned system: a dark plate edged in the
## owner's colour with the name, one pip per body (filled = developed), and
## markers for a shipyard (anchor) and defenses (shield with a count).
func _draw_banner(pv: Planet3D, p: Vector2) -> void:
	var planet: Planet = board.engine.state.planets.get(pv.planet_id)
	if planet == null:
		return
	var font := ThemeDB.fallback_font
	var w := _banner_width(pv)
	var rect := Rect2(p + Vector2(-w / 2.0, -15), Vector2(w, 20))
	var c := pv.owner_color
	draw_rect(rect.grow(1.0), Color(0, 0, 0, 0.6))
	draw_rect(rect, Color(c.darkened(0.78), 0.92))
	draw_rect(Rect2(rect.position, Vector2(4, rect.size.y)), c)
	draw_rect(rect, Color(c, 0.55), false, 1.0)
	var x := rect.position.x + 9.0
	var base_y := rect.position.y + 15.0
	draw_string(font, Vector2(x, base_y), pv.display_name, HORIZONTAL_ALIGNMENT_LEFT, -1, BANNER_FONT, c.lightened(0.55))
	x += font.get_string_size(pv.display_name, HORIZONTAL_ALIGNMENT_LEFT, -1, BANNER_FONT).x + 8.0
	for b: Dictionary in planet.bodies:
		var cy := rect.position.y + 10.0
		if b["buildings"].is_empty():
			draw_arc(Vector2(x + 2.5, cy), 2.4, 0, TAU, 10, Color(1, 1, 1, 0.35), 1.0)
		else:
			draw_circle(Vector2(x + 2.5, cy), 2.8, c.lightened(0.35))
		x += 7.0
	x += 3.0
	# Shipyards and defenses only for systems you've scouted (or your own).
	if planet.owner != board.player_faction and not board._explored.has(planet.cell):
		return
	var mid := rect.position.y + 10.0
	if EmpireRules.has_shipyard(board.engine, planet):
		# Anchor: a ring over a shank with a bar.
		draw_arc(Vector2(x + 4, mid - 4), 1.8, 0, TAU, 8, Palette.TEXT, 1.2)
		draw_line(Vector2(x + 4, mid - 2), Vector2(x + 4, mid + 5), Palette.TEXT, 1.2)
		draw_arc(Vector2(x + 4, mid + 1), 3.6, 0.3, PI - 0.3, 8, Palette.TEXT, 1.2)
		x += 11.0
	var defenses := EmpireRules.defense_units(board.engine, planet).size()
	if defenses > 0:
		var shield := PackedVector2Array([Vector2(x, mid - 5), Vector2(x + 8, mid - 5), Vector2(x + 8, mid),
				Vector2(x + 4, mid + 5), Vector2(x, mid)])
		draw_colored_polygon(shield, Color(Palette.BAD, 0.85))
		draw_string(font, Vector2(x + 10, mid + 4), str(defenses), HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Palette.TEXT)


func _add_text_item(items: Array[Dictionary], boxes: Array[Rect2], node: Node3D, height: float, text: String,
		size: int, color: Color) -> void:
	var p: Variant = _project(node, height)
	if p == null:
		return
	var w := ThemeDB.fallback_font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
	items.append({"at": p, "text": text, "size": size, "color": color})
	boxes.append(Rect2(p + Vector2(-w / 2.0, -size), Vector2(w, size + 4)))


func _draw_fleet(fv: Fleet3D, p: Vector2) -> void:
	var w := 34.0
	draw_rect(Rect2(p + Vector2(-w / 2.0 - 1, -1), Vector2(w + 2, 5)), Color(0, 0, 0, 0.75))
	draw_rect(Rect2(p + Vector2(-w / 2.0, 0), Vector2(w * clampf(fv.hull_ratio, 0, 1), 3)), Palette.HULL)
	_text(p + Vector2(w / 2.0 + 4, 6), str(fv.ship_count), 20, 11, Palette.TEXT, HORIZONTAL_ALIGNMENT_LEFT)
	var name_color := Palette.ACTIVE if fv.selected else fv.color.lightened(0.3)
	if fv.show_moves and fv.moves_left <= 0 and not fv.selected:
		name_color = Palette.TEXT_DIM
	_text(p + Vector2(-70, -5), fv.display_name, 140, 11, name_color)
	if fv.is_ready() and not fv.selected:
		FleetMarkers.draw_ready_chevron(self, p + Vector2(0, -22))
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
