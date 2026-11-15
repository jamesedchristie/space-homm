class_name BattleHud
extends Control
## Battle UI: turn order (top), unit info and abilities (bottom), combat log
## (right), result overlay. Built in code to keep the prototype easy to change.
## Emits signals; never touches the engine directly.

signal ability_pressed(ability_id: String)
signal end_turn_pressed
signal restart_pressed

const TOP_H := 44.0
const BOTTOM_H := 172.0
const LOG_W := 300.0

var _round_label: Label
var _objective_label: Label
var _order_box: HBoxContainer
var _info_box: VBoxContainer
var _name_label: Label
var _shield_bar: ProgressBar
var _shield_value: Label
var _hull_bar: ProgressBar
var _hull_value: Label
var _stats_label: Label
var _status_label: Label
var _ability_box: HBoxContainer
var _end_turn_button: Button
var _hint_label: Label
var _log: RichTextLabel
var _result_panel: PanelContainer
var _result_label: Label


func _ready() -> void:
	mouse_filter = MOUSE_FILTER_IGNORE
	_build()


## Screen area not covered by HUD panels, for fitting the map.
func map_area() -> Rect2:
	var s := get_viewport_rect().size
	return Rect2(Vector2(0, TOP_H), Vector2(s.x - LOG_W, s.y - TOP_H - BOTTOM_H))


# --- Updates ------------------------------------------------------------------

func set_round(n: int) -> void:
	_round_label.text = "Round %d" % n


func set_objective(text: String) -> void:
	_objective_label.text = text


func set_turn_order(units: Array[BattleUnit], active_id: String) -> void:
	for c in _order_box.get_children():
		c.queue_free()
	for u in units:
		var chip := _panel(Palette.team_color(u.team).darkened(0.7), Palette.team_color(u.team),
				3 if u.id == active_id else 1)
		var label := _label(u.name, 12, Palette.ACTIVE if u.id == active_id else Palette.TEXT)
		chip.add_child(label)
		_order_box.add_child(chip)


func show_unit(unit: BattleUnit, data: DataRegistry) -> void:
	_info_box.visible = unit != null
	if unit == null:
		return
	var def: Dictionary = data.units.get(unit.def_id, {})
	_name_label.text = "%s  ·  %s" % [unit.name, def.get("name", unit.def_id)]
	_name_label.add_theme_color_override("font_color", Palette.team_color(unit.team))
	_shield_bar.max_value = unit.max_shields()
	_shield_bar.value = unit.shields
	_shield_value.text = "%d / %d" % [unit.shields, unit.max_shields()]
	_hull_bar.max_value = unit.max_hull()
	_hull_bar.value = unit.hull
	_hull_value.text = "%d / %d" % [unit.hull, unit.max_hull()]
	_stats_label.text = "AP %d / %d    Armor %d    Initiative %d" % [
			unit.ap, unit.stat_i("max_ap"), unit.stat_i("armor"), unit.stat_i("initiative")]
	var tags := PackedStringArray()
	for s in unit.statuses:
		tags.append("%s (%d)" % [s.def.get("name", s.id), s.remaining])
	_status_label.text = "Status: " + (", ".join(tags) if not tags.is_empty() else "nominal")


## entries: [{id, name, ap_cost, cooldown, enabled, reason, description, selected, hotkey}]
func set_abilities(entries: Array[Dictionary], interactive: bool) -> void:
	for c in _ability_box.get_children():
		c.queue_free()
	for e in entries:
		var b := Button.new()
		b.focus_mode = Control.FOCUS_NONE
		var text := "%d  %s  ·  %d AP" % [e["hotkey"], e["name"], e["ap_cost"]]
		if e["cooldown"] > 0:
			text += "  ·  cd %d" % e["cooldown"]
		b.text = text
		b.tooltip_text = e["description"] + ("" if e["enabled"] else "\n(%s)" % e["reason"])
		b.disabled = not interactive or not e["enabled"]
		if e["selected"]:
			b.modulate = Palette.ACTIVE
		b.pressed.connect(func() -> void: ability_pressed.emit(e["id"]))
		_ability_box.add_child(b)
	_end_turn_button.disabled = not interactive


func set_hint(text: String) -> void:
	_hint_label.text = text


func log_line(bbcode: String) -> void:
	_log.append_text(bbcode + "\n")


func clear_log() -> void:
	_log.clear()


func show_result(title: String, color: Color) -> void:
	_result_label.text = title
	_result_label.add_theme_color_override("font_color", color)
	_result_panel.visible = true


func hide_result() -> void:
	_result_panel.visible = false


# --- Construction -------------------------------------------------------------

func _build() -> void:
	# Top bar: round, turn order, objective.
	var top := _panel()
	_anchor(top, 0, 0, 1, 0, 0, 0, 0, TOP_H)
	add_child(top)
	var top_row := HBoxContainer.new()
	top_row.add_theme_constant_override("separation", 12)
	top.add_child(top_row)
	_round_label = _label("Round 1", 16, Palette.ACTIVE)
	top_row.add_child(_round_label)
	_order_box = HBoxContainer.new()
	_order_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top_row.add_child(_order_box)
	_objective_label = _label("", 13, Palette.TEXT_DIM)
	top_row.add_child(_objective_label)

	# Bottom panel: unit info + abilities.
	var bottom := _panel()
	_anchor(bottom, 0, 1, 1, 1, 0, -BOTTOM_H, -LOG_W, 0)
	add_child(bottom)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 16)
	bottom.add_child(row)

	var info := VBoxContainer.new()
	info.custom_minimum_size = Vector2(330, 0)
	row.add_child(info)
	_info_box = info
	_name_label = _label("", 18, Palette.TEXT)
	info.add_child(_name_label)
	var shield_row := _bar_row("Shields", Palette.SHIELDS)
	_shield_bar = shield_row[0]
	_shield_value = shield_row[1]
	info.add_child(shield_row[2])
	var hull_row := _bar_row("Hull", Palette.HULL)
	_hull_bar = hull_row[0]
	_hull_value = hull_row[1]
	info.add_child(hull_row[2])
	_stats_label = _label("", 13, Palette.TEXT)
	info.add_child(_stats_label)
	_status_label = _label("", 13, Palette.TEXT_DIM)
	info.add_child(_status_label)

	row.add_child(VSeparator.new())

	var actions := VBoxContainer.new()
	actions.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	actions.add_theme_constant_override("separation", 8)
	row.add_child(actions)
	actions.add_child(_label("Abilities", 13, Palette.TEXT_DIM))
	_ability_box = HBoxContainer.new()
	_ability_box.add_theme_constant_override("separation", 6)
	actions.add_child(_ability_box)
	_end_turn_button = Button.new()
	_end_turn_button.text = "End Turn  [Space]"
	_end_turn_button.focus_mode = Control.FOCUS_NONE
	_end_turn_button.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	_end_turn_button.pressed.connect(func() -> void: end_turn_pressed.emit())
	actions.add_child(_end_turn_button)
	_hint_label = _label("", 13, Palette.TEXT)
	_hint_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_hint_label.size_flags_vertical = Control.SIZE_EXPAND_FILL
	actions.add_child(_hint_label)
	actions.add_child(_label("Click: move/target · 1-3: abilities · Right-click/Esc: cancel · A: autoplay · R: restart",
			11, Palette.TEXT_DIM))

	# Combat log.
	var log_panel := _panel()
	_anchor(log_panel, 1, 0, 1, 1, -LOG_W, TOP_H, 0, 0)
	add_child(log_panel)
	_log = RichTextLabel.new()
	_log.bbcode_enabled = true
	_log.scroll_following = true
	_log.add_theme_font_size_override("normal_font_size", 12)
	_log.add_theme_font_size_override("bold_font_size", 13)
	_log.add_theme_font_size_override("italics_font_size", 12)
	_log.add_theme_font_size_override("bold_italics_font_size", 13)
	log_panel.add_child(_log)

	# Result overlay.
	_result_panel = _panel(Palette.PANEL_BG, Palette.ACTIVE, 2)
	_anchor(_result_panel, 0.5, 0.5, 0.5, 0.5, -170, -80, 170, 80)
	_result_panel.visible = false
	add_child(_result_panel)
	var result_box := VBoxContainer.new()
	result_box.alignment = BoxContainer.ALIGNMENT_CENTER
	result_box.add_theme_constant_override("separation", 14)
	_result_panel.add_child(result_box)
	_result_label = _label("", 28, Palette.TEXT)
	_result_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	result_box.add_child(_result_label)
	var restart := Button.new()
	restart.text = "Play again"
	restart.focus_mode = Control.FOCUS_NONE
	restart.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	restart.pressed.connect(func() -> void: restart_pressed.emit())
	result_box.add_child(restart)


func _bar_row(title: String, color: Color) -> Array:
	var row := HBoxContainer.new()
	var label := _label(title, 13, Palette.TEXT_DIM)
	label.custom_minimum_size = Vector2(60, 0)
	row.add_child(label)
	var bar := ProgressBar.new()
	bar.show_percentage = false
	bar.custom_minimum_size = Vector2(170, 12)
	bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var fill := StyleBoxFlat.new()
	fill.bg_color = color
	bar.add_theme_stylebox_override("fill", fill)
	var bg := StyleBoxFlat.new()
	bg.bg_color = Color(0, 0, 0, 0.5)
	bar.add_theme_stylebox_override("background", bg)
	row.add_child(bar)
	var value := _label("", 13, Palette.TEXT)
	row.add_child(value)
	return [bar, value, row]


func _panel(bg: Color = Palette.PANEL_BG, border: Color = Palette.PANEL_BORDER, border_width: int = 1) -> PanelContainer:
	var p := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.border_color = border
	sb.set_border_width_all(border_width)
	sb.set_corner_radius_all(4)
	sb.set_content_margin_all(8)
	p.add_theme_stylebox_override("panel", sb)
	return p


func _label(text: String, font_size: int, color: Color) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", font_size)
	l.add_theme_color_override("font_color", color)
	return l


func _anchor(c: Control, left: float, top: float, right: float, bottom: float,
		off_left: float, off_top: float, off_right: float, off_bottom: float) -> void:
	c.anchor_left = left
	c.anchor_top = top
	c.anchor_right = right
	c.anchor_bottom = bottom
	c.offset_left = off_left
	c.offset_top = off_top
	c.offset_right = off_right
	c.offset_bottom = off_bottom
