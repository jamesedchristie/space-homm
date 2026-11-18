class_name TechTreeView
extends PanelContainer
## Full-screen tech tree: every technology as a card, laid out left to right
## by prerequisite depth (grouped by era when techs carry an "era"), with
## curves from each prerequisite. Known techs are green, ones you can start
## now are bright, the current one shows its progress, locked ones are dim.
## Clicking an available card emits a SetResearchCommand. Data-driven: it
## reads data/empire/techs.json through ResearchRules, nothing is hard-coded.

signal command_requested(cmd: GalaxyCommand)
signal closed

const CARD := Vector2(214, 104)
const GAP := Vector2(70, 18)
const MARGIN := Vector2(24, 48)

var _canvas: TreeCanvas
var _scroll: ScrollContainer
var _title: Label
var _status: RichTextLabel


func _init() -> void:
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.02, 0.03, 0.06, 1.0)
	sb.border_color = Palette.PANEL_BORDER
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(4)
	sb.set_content_margin_all(12)
	add_theme_stylebox_override("panel", sb)
	visible = false
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 8)
	add_child(box)
	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 16)
	box.add_child(header)
	_title = UiKit.header("Technology", 20, Palette.ACTIVE)
	header.add_child(_title)
	_status = UiKit.rich_text(13)
	_status.scroll_following = false
	_status.fit_content = true
	_status.autowrap_mode = TextServer.AUTOWRAP_OFF
	_status.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_status.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	header.add_child(_status)
	header.add_child(UiKit.button("Close  [T]", func() -> void:
		visible = false
		closed.emit()))
	_scroll = ScrollContainer.new()
	_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	box.add_child(_scroll)
	_canvas = TreeCanvas.new()
	_scroll.add_child(_canvas)


func show_tree(engine: GalaxyEngine, faction_id: String, interactive: bool) -> void:
	for c in _canvas.get_children():
		c.queue_free()
	var data := engine.data
	var r: Dictionary = engine.state.research[faction_id]
	var per_turn := int(EmpireRules.income(engine, faction_id)["research"])
	if String(r["current"]).is_empty():
		_status.text = UiKit.color_tag("Choose a technology: research is banked until you do (%d banked, +%d per turn)." % [r["progress"], per_turn], Palette.ACTIVE)
	else:
		var cost := ResearchRules.cost(engine, r["current"])
		var turns := ceili(float(cost - int(r["progress"])) / maxf(1.0, per_turn))
		_status.text = "Researching [b]%s[/b]  %d / %d  (+%d per turn, %d turn%s)" % [data.techs[r["current"]]["name"],
				r["progress"], cost, per_turn, turns, "" if turns == 1 else "s"]

	var layout := _layout(data)
	var cells: Dictionary = layout["cells"]
	var eras: Array = layout["eras"]
	var cols := int(layout["cols"])
	var rows := int(layout["rows"])
	_canvas.custom_minimum_size = MARGIN * 2.0 + Vector2(cols * (CARD.x + GAP.x), rows * (CARD.y + GAP.y))
	_canvas.links.clear()
	for e: Dictionary in eras:
		var era := int(e["era"])
		e["name"] = ResearchRules.era_name(engine, era)
		e["open"] = ResearchRules.era_open(engine, faction_id, era)
		var need: Dictionary = data.eras.get(str(era), {}).get("requires", {})
		e["need"] = "" if need.is_empty() else "needs %d %s techs (%d known)" % [int(need["count"]),
				ResearchRules.era_name(engine, int(need["era"])), ResearchRules.known_in_era(engine, faction_id, int(need["era"]))]
	_canvas.eras = eras
	var rects := {}
	for tech_id: String in cells:
		var cell: Vector2i = cells[tech_id]
		rects[tech_id] = Rect2(MARGIN + Vector2(cell.x * (CARD.x + GAP.x), cell.y * (CARD.y + GAP.y)), CARD)
	for tech_id: String in cells:
		var tech: Dictionary = data.techs[tech_id]
		var status := ResearchRules.status(engine, faction_id, tech_id)
		var current: bool = r["current"] == tech_id
		_canvas.add_child(_card(engine, faction_id, tech_id, tech, status, current, rects[tech_id], interactive))
		for req: String in tech.get("requires", []):
			if rects.has(req):
				var known := ResearchRules.status(engine, faction_id, req) == ResearchRules.KNOWN
				_canvas.links.append({"from": rects[req], "to": rects[tech_id], "lit": known})
	_canvas.queue_redraw()
	visible = true


## Column = era block + depth along prerequisites inside that era; rows fill
## top to bottom in data order.
func _layout(data: DataRegistry) -> Dictionary:
	var depth := {}
	var ids: Array[String] = []
	for tech_id: String in data.techs:
		ids.append(tech_id)
	var era_of := func(id: String) -> int: return int(data.techs[id].get("era", 1))
	# Depth inside the era, by longest chain of same-era prerequisites.
	for _pass in ids.size():
		var changed := false
		for id in ids:
			var d := 0
			for req: String in data.techs[id].get("requires", []):
				if depth.has(req) and era_of.call(req) == era_of.call(id):
					d = maxi(d, int(depth[req]) + 1)
			if int(depth.get(id, -1)) != d:
				depth[id] = d
				changed = true
		if not changed:
			break
	var era_list: Array[int] = []
	var era_depth := {}
	for id in ids:
		var e: int = era_of.call(id)
		if e not in era_list:
			era_list.append(e)
		era_depth[e] = maxi(int(era_depth.get(e, 0)), int(depth[id]))
	era_list.sort()
	var offset := {}
	var col := 0
	var eras: Array = []
	for e in era_list:
		offset[e] = col
		eras.append({"era": e, "from": col, "to": col + int(era_depth[e])})
		col += int(era_depth[e]) + 1
	var cells := {}
	var used := {}
	var rows := 0
	for id in ids:
		var c := int(offset[era_of.call(id)]) + int(depth[id])
		var row := int(used.get(c, 0))
		used[c] = row + 1
		rows = maxi(rows, row + 1)
		cells[id] = Vector2i(c, row)
	for e: Dictionary in eras:
		e["x0"] = MARGIN.x + int(e["from"]) * (CARD.x + GAP.x) - GAP.x / 2.0
		e["x1"] = MARGIN.x + (int(e["to"]) + 1) * (CARD.x + GAP.x) - GAP.x / 2.0
	return {"cells": cells, "cols": col, "rows": rows, "eras": eras if era_list.size() > 1 else []}


func _card(engine: GalaxyEngine, faction_id: String, tech_id: String, tech: Dictionary, status: String,
		current: bool, rect: Rect2, interactive: bool) -> Control:
	var accent := Palette.TEXT_DIM
	var bg := Color(0.05, 0.07, 0.11, 0.95)
	match status:
		ResearchRules.KNOWN:
			accent = Palette.GOOD
			bg = Color(0.05, 0.12, 0.08, 0.95)
		ResearchRules.AVAILABLE:
			accent = Palette.SHIELDS
			bg = Color(0.06, 0.1, 0.16, 0.97)
	if current:
		accent = Palette.ACTIVE
		bg = Color(0.14, 0.12, 0.04, 0.97)
	var card := Button.new()
	card.focus_mode = Control.FOCUS_NONE
	card.position = rect.position
	card.size = rect.size
	card.clip_contents = true
	for state_name in ["normal", "hover", "pressed", "disabled"]:
		var sb := StyleBoxFlat.new()
		sb.bg_color = bg.lightened(0.08) if state_name == "hover" else bg
		sb.border_color = accent if state_name != "hover" else accent.lightened(0.3)
		sb.set_border_width_all(2 if current or state_name == "hover" else 1)
		sb.border_width_left = 4
		sb.set_corner_radius_all(4)
		card.add_theme_stylebox_override(state_name, sb)
	var available := status == ResearchRules.AVAILABLE
	card.disabled = not (interactive and available and not current)
	card.pressed.connect(func() -> void:
		command_requested.emit(SetResearchCommand.new(faction_id, tech_id))
		show_tree(engine, faction_id, interactive))
	card.tooltip_text = "%s\n%s" % [tech.get("name", tech_id), tech.get("description", "")]
	var text := UiKit.rich_text(11)
	text.scroll_following = false
	text.mouse_filter = Control.MOUSE_FILTER_IGNORE
	text.position = Vector2(10, 6)
	text.size = rect.size - Vector2(16, 10)
	var state_text := ""
	match status:
		ResearchRules.KNOWN:
			state_text = UiKit.color_tag("Researched", Palette.GOOD)
		ResearchRules.LOCKED:
			state_text = UiKit.color_tag("Locked", Palette.TEXT_DIM)
		_:
			state_text = UiKit.color_tag("Researching" if current else "Click to research", Palette.ACTIVE if current else Palette.SHIELDS)
	var name_color := Palette.TEXT if status != ResearchRules.LOCKED else Palette.TEXT_DIM
	text.text = "[b]%s[/b]   %s\n%s\n%s" % [UiKit.color_tag(tech.get("name", tech_id), name_color),
			UiKit.color_tag("%d" % ResearchRules.cost(engine, tech_id), Palette.TEXT_DIM),
			UiKit.color_tag(tech.get("description", ""), Palette.TEXT_DIM if status == ResearchRules.LOCKED else Palette.TEXT),
			state_text]
	card.add_child(text)
	if current:
		var r: Dictionary = engine.state.research[faction_id]
		var bar := ColorRect.new()
		bar.color = Palette.ACTIVE
		bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
		bar.position = Vector2(4, rect.size.y - 4)
		bar.size = Vector2((rect.size.x - 6) * clampf(float(r["progress"]) / maxf(1.0, ResearchRules.cost(engine, tech_id)), 0.0, 1.0), 3)
		card.add_child(bar)
	return card


## Draws era bands and the prerequisite curves behind the cards.
class TreeCanvas:
	extends Control
	var links: Array = []
	var eras: Array = []

	func _draw() -> void:
		var font := ThemeDB.fallback_font
		for i in eras.size():
			var e: Dictionary = eras[i]
			var band := Rect2(Vector2(float(e["x0"]), 0), Vector2(float(e["x1"]) - float(e["x0"]), size.y))
			draw_rect(band, Color(1, 1, 1, 0.025 if i % 2 == 0 else 0.0))
			var open: bool = e.get("open", true)
			draw_string(font, Vector2(band.position.x + 12, 22), String(e.get("name", "Era %d" % int(e["era"]))).to_upper(),
					HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color(Palette.ACTIVE, 0.8) if open else Color(Palette.TEXT_DIM, 0.8))
			if not open and not String(e.get("need", "")).is_empty():
				draw_string(font, Vector2(band.position.x + 12, 36), String(e["need"]), HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Palette.TEXT_DIM)
		for link: Dictionary in links:
			var a: Rect2 = link["from"]
			var b: Rect2 = link["to"]
			var p0 := Vector2(a.end.x, a.position.y + a.size.y / 2.0)
			var p3 := Vector2(b.position.x, b.position.y + b.size.y / 2.0)
			var dx := maxf(30.0, (p3.x - p0.x) * 0.5)
			var pts := PackedVector2Array()
			for k in 17:
				var t := k / 16.0
				var u := 1.0 - t
				pts.append(u * u * u * p0 + 3.0 * u * u * t * (p0 + Vector2(dx, 0)) + 3.0 * u * t * t * (p3 - Vector2(dx, 0)) + t * t * t * p3)
			var lit: bool = link["lit"]
			draw_polyline(pts, Color(Palette.GOOD, 0.75) if lit else Color(Palette.PANEL_BORDER, 0.6), 2.0 if lit else 1.5, true)
