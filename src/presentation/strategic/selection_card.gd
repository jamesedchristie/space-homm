class_name SelectionCard
extends VBoxContainer
## The right-hand info panel: a structured card for whatever is selected (fleet, system,
## mission site) instead of a wall of text. Built from a plain dictionary:
##   {"title", "subtitle", "subtitle_color",
##    "pills": [{"text", "color"?, "tooltip"?}],          small stat chips under the title
##    "section": "Ships",                                    caption over the rows (optional)
##    "rows": [{"text", "tag"?, "tag_color"?, "bar"?: 0..1, "bar_color"?, "value"?, "tooltip"?}],
##    "notes": [{"text", "color"?}],                        short status lines (keep to 2-3)
##    "actions": [{"id", "label", "tooltip"?, "disabled"?}]}  buttons; pressing one emits action_pressed
## Long explanations belong in tooltips, not on the card.

signal action_pressed(id: String)

const BAR_W := 64.0


func show_card(card: Dictionary) -> void:
	for c in get_children():
		remove_child(c)
		c.queue_free()
	add_theme_constant_override("separation", 6)
	if card.is_empty():
		return
	var title := UiKit.label(str(card.get("title", "")), 17, Palette.TEXT)
	title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(title)
	if card.has("subtitle"):
		add_child(UiKit.label(str(card["subtitle"]), 12, card.get("subtitle_color", Palette.TEXT_DIM)))
	var pills: Array = card.get("pills", [])
	if not pills.is_empty():
		var flow := HFlowContainer.new()
		flow.add_theme_constant_override("h_separation", 4)
		flow.add_theme_constant_override("v_separation", 4)
		for p: Dictionary in pills:
			flow.add_child(_pill(str(p["text"]), p.get("color", Palette.TEXT), str(p.get("tooltip", ""))))
		add_child(flow)
	var rows: Array = card.get("rows", [])
	if not rows.is_empty():
		if card.has("section"):
			add_child(_caption(str(card["section"])))
		var list := VBoxContainer.new()
		list.add_theme_constant_override("separation", 3)
		for r: Dictionary in rows:
			list.add_child(_row(r))
		add_child(list)
	var notes: Array = card.get("notes", [])
	for n: Dictionary in notes:
		var l := UiKit.label(str(n["text"]), 12, n.get("color", Palette.TEXT_DIM))
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		add_child(l)
	var actions: Array = card.get("actions", [])
	if not actions.is_empty():
		var flow := HFlowContainer.new()
		flow.add_theme_constant_override("h_separation", 6)
		flow.add_theme_constant_override("v_separation", 6)
		for a: Dictionary in actions:
			var id: String = a["id"]
			var b := UiKit.button(str(a["label"]), func() -> void: action_pressed.emit(id))
			b.tooltip_text = str(a.get("tooltip", ""))
			b.disabled = bool(a.get("disabled", false))
			b.add_theme_font_size_override("font_size", 13)
			flow.add_child(b)
		add_child(flow)


func _caption(text: String) -> Control:
	var l := UiKit.label(text.to_upper(), 11, Palette.TEXT_DIM)
	l.add_theme_constant_override("outline_size", 0)
	return l


func _pill(text: String, color: Color, tooltip: String) -> Control:
	var panel := PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = Color(color, 0.14)
	style.border_color = Color(color, 0.5)
	style.set_border_width_all(1)
	style.set_corner_radius_all(9)
	style.content_margin_left = 8
	style.content_margin_right = 8
	style.content_margin_top = 1
	style.content_margin_bottom = 1
	panel.add_theme_stylebox_override("panel", style)
	panel.add_child(UiKit.label(text, 12, color))
	panel.tooltip_text = tooltip
	panel.mouse_filter = Control.MOUSE_FILTER_PASS if not tooltip.is_empty() else Control.MOUSE_FILTER_IGNORE
	return panel


func _row(r: Dictionary) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	row.tooltip_text = str(r.get("tooltip", ""))
	row.mouse_filter = Control.MOUSE_FILTER_PASS if not row.tooltip_text.is_empty() else Control.MOUSE_FILTER_IGNORE
	var name := UiKit.label(str(r.get("text", "")), 13, r.get("color", Palette.TEXT))
	name.clip_text = true
	name.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(name)
	if r.has("tag"):
		var tag := _pill(str(r["tag"]), r.get("tag_color", Palette.TEXT_DIM), "")
		tag.mouse_filter = Control.MOUSE_FILTER_IGNORE
		row.add_child(tag)
	if r.has("bar"):
		row.add_child(_bar(float(r["bar"]), r.get("bar_color", Palette.HULL)))
	if r.has("value"):
		var v := UiKit.label(str(r["value"]), 12, r.get("value_color", Palette.TEXT_DIM))
		v.custom_minimum_size = Vector2(52, 0)
		v.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		v.mouse_filter = Control.MOUSE_FILTER_IGNORE
		row.add_child(v)
	return row


func _bar(frac: float, color: Color) -> Control:
	var bar := _Bar.new()
	bar.frac = clampf(frac, 0.0, 1.0)
	bar.color = color
	bar.custom_minimum_size = Vector2(BAR_W, 14)
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return bar


class _Bar:
	extends Control
	var frac := 1.0
	var color := Color.WHITE

	func _draw() -> void:
		var r := Rect2(Vector2(0, size.y * 0.5 - 3), Vector2(size.x, 6))
		draw_rect(r, Color(1, 1, 1, 0.08))
		draw_rect(Rect2(r.position, Vector2(r.size.x * frac, r.size.y)), color)
