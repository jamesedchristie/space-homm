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
		var compact := _compact(pv)
		if compact != "":
			var at_c: Variant = _project(pv, pv.label_height)
			if at_c != null:
				var wc := _tag_width(pv, compact)
				items.append({"tag": pv, "kind": compact, "at": at_c})
				boxes.append(Rect2(at_c + Vector2(-wc / 2.0, -12), Vector2(wc, 16)))
		elif pv.owned:
			# Above the system, like a city banner.
			var at: Variant = _project(pv, pv.label_height + 0.35)
			if at != null:
				var w := _banner_width(pv)
				items.append({"banner": pv, "at": at})
				boxes.append(Rect2(at + Vector2(-w / 2.0, -16), Vector2(w, 22)))
		else:
			_add_text_item(items, boxes, pv, pv.label_height, pv.display_name, 12, Palette.TEXT_DIM, _deposit_marks(pv))
	for av: Anomaly3D in board.anomaly_views.values():
		if av.visible:
			_add_text_item(items, boxes, av, av.label_height, av.display_name, 11, Anomaly3D.COLOR.lightened(0.35))
	for dv: Discovery3D in board.discovery_views.values():
		if dv.visible:
			_add_text_item(items, boxes, dv, dv.label_height, dv.display_name, 10, dv.color.lightened(0.2))
	if board.solar != null:
		# The dormant jump gates at the edge of a system-scale map.
		for gate in board.solar.gates:
			_add_text_item(items, boxes, gate, 0.75, "Jump point (dormant)", 10, Color(0.5, 0.75, 0.85, 0.8))
	for fv: Fleet3D in board.fleet_views.values():
		if not fv.visible or not fv.is_inside_tree():
			continue
		var p: Variant = _project(fv, fv.label_height)
		if p == null:
			continue
		var w := maxf(44.0, font.get_string_size(fv.display_name, HORIZONTAL_ALIGNMENT_LEFT, -1, 11).x)
		items.append({"fleet": fv, "at": p})
		boxes.append(Rect2(p + Vector2(-w / 2.0, -16), Vector2(w, 30)))
	_draw_order_lines()
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
		elif item.has("tag"):
			_draw_tag(item["tag"], item["kind"], p)
		else:
			_text(p + Vector2(-70, 0), item["text"], 140, item["size"], item["color"])
			var marks: Array = item.get("marks", [])
			if not marks.is_empty():
				var tw := ThemeDB.fallback_font.get_string_size(item["text"], HORIZONTAL_ALIGNMENT_LEFT, -1, item["size"]).x
				_draw_marks(marks, p + Vector2(tw / 2.0 + 6.0, -4.0))


const BANNER_FONT := 12


## A dotted course line from each of the player's ships on standing orders to its target.
func _draw_order_lines() -> void:
	var e := board.engine
	for fv: Fleet3D in board.fleet_views.values():
		if not fv.visible:
			continue
		var fleet: Fleet = e.state.fleets.get(fv.fleet_id)
		if fleet == null or fleet.owner != board.player_faction or fleet.order.is_empty():
			continue
		var target: Planet = e.state.planets.get(fleet.order["planet"])
		if target == null or not board.planet_views.has(target.id):
			continue
		var a: Variant = _project(fv, 0.3)
		var b: Variant = _project(board.planet_views[target.id], 0.3)
		if a == null or b == null:
			continue
		var from: Vector2 = a
		var to: Vector2 = b
		var length := from.distance_to(to)
		var dir := (to - from) / maxf(length, 1.0)
		var t := fmod(Time.get_ticks_msec() / 60.0, 14.0)
		var d := t
		while d < length - 6.0:
			draw_line(from + dir * d, from + dir * minf(d + 7.0, length), Color(Palette.ACTIVE, 0.65), 2.0, true)
			d += 14.0
		draw_arc(to, 9.0, 0.0, TAU, 24, Color(Palette.ACTIVE, 0.85), 2.0, true)
## Zoomed in closer than this (camera distance), compact tags show their names too.
const TAG_NAME_ZOOM := 16.0


## On a system-scale map only colonies (and enemy bases) carry a full banner; every other
## claimed body gets a compact tag: "dev" (a development of yours or a rival's), "" = banner/text.
func _compact(pv: Planet3D) -> String:
	if not board.engine.is_system_scale() or not pv.owned:
		return ""
	var planet: Planet = board.engine.state.planets.get(pv.planet_id)
	if planet == null or planet.has_colony():
		return ""
	var role: String = board.engine.state.faction(planet.owner).get("role", "major")
	if role == "barbarian":
		return ""  # dens keep their banner: they're what you're hunting
	return "dev"


func _tag_name_shown(pv: Planet3D) -> bool:
	var planet: Planet = board.engine.state.planets.get(pv.planet_id)
	var hover: Variant = board.hover_cell()
	if planet != null and hover != null and hover == planet.cell:
		return true
	return board.zoom_distance() > 0.0 and board.zoom_distance() < TAG_NAME_ZOOM


func _tag_width(pv: Planet3D, _kind: String) -> float:
	var w := 22.0 + _deposit_marks(pv).size() * MARK_STEP
	if _tag_name_shown(pv):
		w += ThemeDB.fallback_font.get_string_size(pv.display_name, HORIZONTAL_ALIGNMENT_LEFT, -1, 11).x + 6.0
	return w


## A compact tag: an owner-coloured chip with an icon for what stands there (pick = mining,
## flask = research, drop = refinery, flag = outpost, star = anything else), the name when
## hovered or zoomed in, and a red edge if blockaded.
func _draw_tag(pv: Planet3D, _kind: String, p: Vector2) -> void:
	var planet: Planet = board.engine.state.planets.get(pv.planet_id)
	if planet == null:
		return
	var font := ThemeDB.fallback_font
	var w := _tag_width(pv, _kind)
	var rect := Rect2(p + Vector2(-w / 2.0, -12), Vector2(w, 16))
	var c := pv.owner_color
	draw_rect(rect.grow(1.0), Color(0, 0, 0, 0.55))
	draw_rect(rect, Color(c.darkened(0.75), 0.9))
	draw_rect(rect, Color(c, 0.6) if planet.blockade.is_empty() else Palette.BAD, false, 1.0)
	var icon := rect.position + Vector2(10, 8)
	var ic := c.lightened(0.45)
	var buildings: Array[String] = planet.buildings
	if "mining_base" in buildings:
		draw_line(icon + Vector2(-4, 4), icon + Vector2(3, -3), ic, 1.6)
		draw_line(icon + Vector2(0, -5), icon + Vector2(5, 0), ic, 2.2)
	elif "research_station" in buildings:
		draw_colored_polygon(PackedVector2Array([icon + Vector2(-2, -5), icon + Vector2(2, -5), icon + Vector2(5, 4), icon + Vector2(-5, 4)]), ic)
	elif "gas_refinery" in buildings:
		draw_circle(icon + Vector2(0, 1.5), 3.5, ic)
		draw_colored_polygon(PackedVector2Array([icon + Vector2(-3, 0), icon + Vector2(0, -6), icon + Vector2(3, 0)]), ic)
	elif "outpost" in buildings:
		draw_line(icon + Vector2(-3, 5), icon + Vector2(-3, -5), ic, 1.5)
		draw_colored_polygon(PackedVector2Array([icon + Vector2(-3, -5), icon + Vector2(4, -3), icon + Vector2(-3, -1)]), ic)
	else:
		draw_circle(icon, 3.5, ic)
	var marks := _deposit_marks(pv)
	_draw_marks(marks, rect.position + Vector2(21.0, 8.0))
	if _tag_name_shown(pv):
		draw_string(font, rect.position + Vector2(20 + marks.size() * MARK_STEP, 12), pv.display_name, HORIZONTAL_ALIGNMENT_LEFT, -1, 11,
				c.lightened(0.5))


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
	if not planet.blockade.is_empty():
		# Blockaded: a red tag under the banner, with who holds it.
		var who: String = board.engine.state.faction(planet.blockade).get("name", "")
		var tag := "BLOCKADED" if who.is_empty() else "BLOCKADED by %s" % who
		var tw := font.get_string_size(tag, HORIZONTAL_ALIGNMENT_LEFT, -1, 10).x + 10.0
		var tr := Rect2(Vector2(rect.position.x + (rect.size.x - tw) / 2.0, rect.end.y + 2.0), Vector2(tw, 14))
		draw_rect(tr, Color(0.45, 0.04, 0.03, 0.92))
		draw_rect(tr, Palette.BAD, false, 1.0)
		draw_string(font, tr.position + Vector2(5, 11), tag, HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color(1, 0.85, 0.8))
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
		size: int, color: Color, marks: Array = []) -> void:
	var p: Variant = _project(node, height)
	if p == null:
		return
	var w := ThemeDB.fallback_font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x + marks.size() * MARK_STEP * 2.0
	items.append({"at": p, "text": text, "size": size, "color": color, "marks": marks})
	boxes.append(Rect2(p + Vector2(-w / 2.0, -size), Vector2(w, size + 4)))


## Horizontal space per deposit diamond.
const MARK_STEP := 9.0


## Strategic deposits the player knows of on a body of a system-scale map, as diamonds:
## [{"color", "tapped"}] (tapped = extracted by its owner). Unsurveyed bodies show none.
func _deposit_marks(pv: Planet3D) -> Array:
	var out: Array = []
	var e := board.engine
	if not e.is_system_scale():
		return out
	var planet: Planet = e.state.planets.get(pv.planet_id)
	if planet == null or planet.bodies.is_empty():
		return out
	var deposits := e.known_deposits(board.player_faction, planet, planet.bodies[0])
	for k: String in deposits:
		out.append({"color": DepositRules.color(e.data, k), "tapped": DepositRules.is_tapped(e.data, planet.bodies[0], k),
				"richness": int(deposits[k])})
	return out


## A row of small diamonds from `at` (left centre): filled when tapped, an outline when not.
func _draw_marks(marks: Array, at: Vector2) -> void:
	var x := at.x
	for m: Dictionary in marks:
		var c: Color = m["color"]
		var r := 3.0 + 0.6 * float(m["richness"])
		var pts := PackedVector2Array([Vector2(x + r * 0.8, at.y - r), Vector2(x + r * 1.6, at.y), Vector2(x + r * 0.8, at.y + r),
				Vector2(x, at.y)])
		draw_colored_polygon(pts, Color(0, 0, 0, 0.6) if not m["tapped"] else c)
		pts.append(pts[0])
		draw_polyline(pts, c.lightened(0.2), 1.3, true)
		x += MARK_STEP


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
