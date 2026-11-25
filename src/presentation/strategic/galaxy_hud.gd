class_name GalaxyHud
extends Control
## Galaxy UI: turn bar (top), selection info + log (right), hint line (bottom)
## and a modal dialog for battles and reports. Emits signals only.

signal end_turn_pressed
signal next_fleet_pressed
signal research_pressed
signal heroes_pressed
signal empire_pressed
signal menu_pressed
signal settings_closed
## Emitted when the player clicks one of the dialog's buttons.
signal dialog_choice(choice_id: String)
## A button on the selection card was pressed.
signal card_action(id: String)

const TOP_H := 44.0
const BOTTOM_H := 36.0
const RIGHT_W := 300.0
const INFO_H := 300.0
const MINIMAP_H := 170.0

var _turn_label: Label
var _faction_label: Label
## Resource id -> {"value": Label, "delta": Label, "panel": Control}.
var _chips: Dictionary = {}
var _chip_row: HBoxContainer
var _research_button: Button
var _research_bar: SelectionCard._Bar
var _attention: VBoxContainer
var _attention_key := "-"
var _end_turn_button: Button
var _next_fleet_button: Button
var _card: SelectionCard
var _card_key := ""
var _log: RichTextLabel
var _hint: Label
var _dialog: DialogPanel
## Hero management overlay (shown by the galaxy screen).
var roster: HeroRoster
## Colonies / research / diplomacy overlay.
var empire: EmpirePanel
## A star system up close: bodies and building.
var system_view: SystemView
## Technology tree overlay.
var tech_tree: TechTreeView
## Whole-sector overview, bottom right.
var minimap: GalaxyMinimap
## Full-screen conversation with another faction's leader.
var diplomacy: DiplomacyScreen


func _ready() -> void:
	mouse_filter = MOUSE_FILTER_IGNORE
	theme = GameTheme.get_theme()
	_build()


func _process(_delta: float) -> void:
	# The attention list steps aside for any overlay or dialog.
	_attention.visible = _attention.get_child_count() > 0 and not (empire.visible or roster.visible
			or system_view.visible or tech_tree.visible or diplomacy.visible or is_dialog_open() or is_settings_open())


func map_area() -> Rect2:
	var s := get_viewport_rect().size
	return Rect2(Vector2(0, TOP_H), Vector2(s.x - RIGHT_W, s.y - TOP_H - BOTTOM_H))


func set_turn(turn: int, faction_name: String, color: Color) -> void:
	_turn_label.text = "Turn %d" % turn
	_faction_label.text = faction_name
	_faction_label.add_theme_color_override("font_color", color)


## The campaign objective, shown as the turn counter's tooltip.
func set_objective(text: String) -> void:
	_turn_label.tooltip_text = text
	_turn_label.mouse_filter = Control.MOUSE_FILTER_STOP


## One chip per resource in the top bar: a coloured pip, the stockpile and the
## per-turn change, with a breakdown as the tooltip. Chips are created on
## first use and keep their order. Strategic resources (`diamond`) get a diamond pip
## and a compact chip; `shown` false hides a chip (a strategic resource you neither
## have nor produce).
func set_resource_chip(id: String, color: Color, value: int, delta: int, tooltip: String, diamond := false,
		shown := true) -> void:
	if not _chips.has(id):
		var chip := UiKit.panel(Color(0.06, 0.08, 0.13, 0.9), Color(color, 0.45))
		chip.mouse_filter = Control.MOUSE_FILTER_STOP
		var box := HBoxContainer.new()
		box.add_theme_constant_override("separation", 4 if diamond else 5)
		chip.add_child(box)
		var pip := Pip.new()
		pip.color = color
		pip.diamond = diamond
		pip.custom_minimum_size = Vector2(11, 11) if diamond else Vector2(10, 10)
		pip.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		box.add_child(pip)
		var value_label := UiKit.label("", 13 if diamond else 14, Palette.TEXT)
		box.add_child(value_label)
		var delta_label := UiKit.label("", 11 if diamond else 12, Palette.TEXT_DIM)
		delta_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		box.add_child(delta_label)
		_chip_row.add_child(chip)
		_chips[id] = {"value": value_label, "delta": delta_label, "panel": chip}
	var c: Dictionary = _chips[id]
	(c["value"] as Label).text = str(value)
	var dl: Label = c["delta"]
	dl.text = "%+d" % delta
	dl.add_theme_color_override("font_color", Palette.BAD if delta < 0 else (Palette.GOOD.darkened(0.15) if delta > 0 else Palette.TEXT_DIM))
	(c["panel"] as Control).tooltip_text = tooltip
	(c["panel"] as Control).visible = shown


## Civ-style "needs your attention" list at the top left of the map: each
## item is {"text", "color", "action": Callable}. Empty hides it.
func set_attention(items: Array[Dictionary]) -> void:
	var texts := PackedStringArray()
	for item in items:
		texts.append(item["text"])
	var key := "|".join(texts)
	if key == _attention_key:
		return  # unchanged (refresh runs on every hover)
	_attention_key = key
	for c in _attention.get_children():
		c.queue_free()
	for item in items:
		var b := Button.new()
		b.focus_mode = Control.FOCUS_NONE
		b.text = item["text"]
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.clip_text = true
		b.custom_minimum_size = Vector2(250, 26)
		b.add_theme_font_size_override("font_size", 12)
		var color: Color = item.get("color", Palette.ACTIVE)
		b.add_theme_color_override("font_color", color)
		b.add_theme_color_override("font_hover_color", color.lightened(0.3))
		for state_name in ["normal", "hover", "pressed"]:
			var sb := StyleBoxFlat.new()
			sb.bg_color = Color(0.03, 0.05, 0.09, 0.88) if state_name == "normal" else Color(0.07, 0.1, 0.16, 0.95)
			sb.border_color = Color(color, 0.7)
			sb.border_width_left = 3
			sb.set_corner_radius_all(4)
			sb.content_margin_left = 10
			sb.content_margin_right = 8
			b.add_theme_stylebox_override(state_name, sb)
		var action: Callable = item["action"]
		b.pressed.connect(action)
		_attention.add_child(b)


## The research chip: what's being researched (or a prompt to choose).
## Clicking it opens the tech tree.
func set_research_chip(text: String, color: Color, tooltip: String, needs_choice: bool, progress: float = -1.0) -> void:
	_research_button.text = text
	_research_bar.visible = progress >= 0.0
	_research_bar.frac = clampf(progress, 0.0, 1.0)
	_research_bar.queue_redraw()
	_research_button.tooltip_text = tooltip
	_research_button.add_theme_color_override("font_color", Palette.ACTIVE if needs_choice else color)
	_research_button.add_theme_color_override("font_hover_color", Palette.ACTIVE if needs_choice else color.lightened(0.3))


func set_end_turn_enabled(enabled: bool) -> void:
	_end_turn_button.disabled = not enabled


## How many of your fleets can still move this turn (Next Fleet button).
func set_ready_fleets(count: int, enabled: bool) -> void:
	_next_fleet_button.text = "Next (%d)" % count if count > 0 else "All moved"
	_next_fleet_button.disabled = not enabled or count == 0


## Shows a SelectionCard dictionary (rebuilt only when it changes: the screen refreshes often).
func show_card(card: Dictionary) -> void:
	var key := var_to_str(card)
	if key == _card_key:
		return
	_card_key = key
	_card.show_card(card)


func set_hint(text: String) -> void:
	_hint.text = text


func log_line(bbcode: String) -> void:
	_log.append_text(bbcode + "\n")


func clear_log() -> void:
	_log.clear()


## Shows a modal dialog. choices: [{"id": String, "label": String}].
## Await `dialog_choice` for the answer. size: dialog size in pixels.
func ask(title: String, body_bbcode: String, choices: Array[Dictionary], size := Vector2(520, 330)) -> void:
	_dialog.place(size.x, size.y)
	_dialog.ask(title, body_bbcode, choices)


func is_dialog_open() -> bool:
	return _dialog.is_open()


func is_diplomacy_open() -> bool:
	return diplomacy.visible


func set_dialog_body(body_bbcode: String) -> void:
	_dialog.set_body(body_bbcode)


## Settings overlay (from the in-game menu). Emits settings_closed when done.
func show_settings() -> void:
	SettingsPanel.open_overlay(self, func() -> void: settings_closed.emit())


func is_settings_open() -> bool:
	return SettingsPanel.is_open_in(self)


## Hides the dialog without answering it (e.g. when a game is loaded).
func close_dialog() -> void:
	_dialog.visible = false


func _build() -> void:
	var top := UiKit.panel()
	UiKit.anchor(top, 0, 0, 1, 0, 0, 0, 0, TOP_H)
	add_child(top)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 14)
	top.add_child(row)
	# Turn number over the faction's name: one narrow block instead of two wide labels.
	var turn_box := VBoxContainer.new()
	turn_box.add_theme_constant_override("separation", -4)
	turn_box.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_child(turn_box)
	_turn_label = UiKit.header("Turn 1", 15, Palette.ACTIVE)
	turn_box.add_child(_turn_label)
	_faction_label = UiKit.label("", 11, Palette.TEXT)
	_faction_label.clip_text = true
	_faction_label.custom_minimum_size = Vector2(110, 0)
	turn_box.add_child(_faction_label)
	_chip_row = HBoxContainer.new()
	_chip_row.add_theme_constant_override("separation", 6)
	row.add_child(_chip_row)
	_research_button = UiKit.button("Research", func() -> void: research_pressed.emit())
	_research_button.clip_text = true
	_research_button.custom_minimum_size = Vector2(150, 0)
	_research_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_research_button.alignment = HORIZONTAL_ALIGNMENT_LEFT
	_research_button.add_theme_stylebox_override("normal", _flat_style(Color(0.06, 0.08, 0.13, 0.9)))
	_research_button.add_theme_stylebox_override("hover", _flat_style(Color(0.1, 0.13, 0.2, 0.95)))
	_research_button.add_theme_stylebox_override("pressed", _flat_style(Color(0.1, 0.13, 0.2, 0.95)))
	row.add_child(_research_button)
	_research_bar = SelectionCard._Bar.new()
	_research_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_research_bar.color = Color(0.45, 0.75, 1.0)
	_research_button.add_child(_research_bar)
	_research_bar.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	_research_bar.offset_top = -9
	_research_bar.offset_bottom = -1
	_research_bar.offset_left = 8
	_research_bar.offset_right = -8
	var empire_button := UiKit.button("Empire", func() -> void: empire_pressed.emit())
	empire_button.tooltip_text = "Systems, research, diplomacy and victory (E)"
	row.add_child(empire_button)
	var heroes_button := UiKit.button("Heroes", func() -> void: heroes_pressed.emit())
	heroes_button.tooltip_text = "Gear, levels and fleet commanders (H)"
	row.add_child(heroes_button)
	_next_fleet_button = UiKit.button("Next", func() -> void: next_fleet_pressed.emit())
	_next_fleet_button.tooltip_text = "Select your next fleet that can still move this turn (Tab)"
	row.add_child(_next_fleet_button)
	_end_turn_button = UiKit.button("End Turn", func() -> void: end_turn_pressed.emit())
	_end_turn_button.tooltip_text = "End your turn (Space)"
	# The main action: a bright button that stands out from the rest of the bar.
	for state_name in ["normal", "hover", "pressed"]:
		var sb := _flat_style(Color(0.85, 0.62, 0.12, 0.95) if state_name == "normal" else Color(1.0, 0.75, 0.2, 1.0))
		sb.set_corner_radius_all(4)
		_end_turn_button.add_theme_stylebox_override(state_name, sb)
	_end_turn_button.add_theme_stylebox_override("disabled", _flat_style(Color(0.2, 0.2, 0.24, 0.9)))
	_end_turn_button.add_theme_color_override("font_color", Color(0.08, 0.06, 0.02))
	_end_turn_button.add_theme_color_override("font_hover_color", Color(0.05, 0.04, 0.0))
	row.add_child(_end_turn_button)
	var menu_button := UiKit.button("Menu", func() -> void: menu_pressed.emit())
	menu_button.tooltip_text = "Save, load, settings (Esc)"
	row.add_child(menu_button)

	_attention = VBoxContainer.new()
	_attention.add_theme_constant_override("separation", 4)
	UiKit.anchor(_attention, 0, 0, 0, 0, 10, TOP_H + 10, 270, TOP_H + 200)
	_attention.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_attention)

	var info_panel := UiKit.panel()
	UiKit.anchor(info_panel, 1, 0, 1, 0, -RIGHT_W, TOP_H, 0, TOP_H + INFO_H)
	add_child(info_panel)
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	info_panel.add_child(scroll)
	_card = SelectionCard.new()
	_card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_card.action_pressed.connect(func(id: String) -> void: card_action.emit(id))
	scroll.add_child(_card)

	var log_panel := UiKit.panel()
	UiKit.anchor(log_panel, 1, 0, 1, 1, -RIGHT_W, TOP_H + INFO_H, 0, -MINIMAP_H)
	add_child(log_panel)
	minimap = GalaxyMinimap.new()
	UiKit.anchor(minimap, 1, 1, 1, 1, -RIGHT_W + 4, -MINIMAP_H + 4, -4, -4)
	add_child(minimap)
	_log = UiKit.rich_text(12)
	log_panel.add_child(_log)

	var bottom := UiKit.panel()
	UiKit.anchor(bottom, 0, 1, 1, 1, 0, -BOTTOM_H, -RIGHT_W, 0)
	add_child(bottom)
	_hint = UiKit.label("", 13, Palette.TEXT)
	_hint.clip_text = true
	bottom.add_child(_hint)

	roster = HeroRoster.new()
	UiKit.anchor(roster, 0, 0, 1, 1, 40, TOP_H + 16, -RIGHT_W - 40, -BOTTOM_H - 16)
	add_child(roster)
	empire = EmpirePanel.new()
	UiKit.anchor(empire, 0, 0, 1, 1, 40, TOP_H + 16, -RIGHT_W - 40, -BOTTOM_H - 16)
	add_child(empire)
	system_view = SystemView.new()
	UiKit.anchor(system_view, 0, 0, 1, 1, 14, TOP_H + 8, -14, -BOTTOM_H - 8)  # the system map takes the whole screen
	add_child(system_view)
	tech_tree = TechTreeView.new()
	UiKit.anchor(tech_tree, 0, 0, 1, 1, 16, TOP_H + 8, -16, -BOTTOM_H - 8)
	add_child(tech_tree)

	_dialog = DialogPanel.new()
	_dialog.place(520, 330)
	_dialog.choice_made.connect(func(id: String) -> void: dialog_choice.emit(id))
	add_child(_dialog)
	diplomacy = DiplomacyScreen.new()
	add_child(diplomacy)


static func _flat_style(bg: Color) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.border_color = Color(Palette.PANEL_BORDER, 0.6)
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(6)
	sb.content_margin_left = 10
	sb.content_margin_right = 10
	sb.content_margin_top = 3
	sb.content_margin_bottom = 3
	return sb


## A small colour pip (resource chips): round, or a diamond for strategic resources.
class Pip:
	extends Control
	var color := Color.WHITE
	var diamond := false

	func _draw() -> void:
		var c := size / 2.0
		var r := minf(size.x, size.y) / 2.0
		if diamond:
			var pts := PackedVector2Array([c + Vector2(0, -r), c + Vector2(r * 0.8, 0), c + Vector2(0, r), c + Vector2(-r * 0.8, 0)])
			draw_colored_polygon(pts, color)
			pts.append(pts[0])
			draw_polyline(pts, Color(1, 1, 1, 0.4), 1.0, true)
			return
		draw_circle(c, r, color)
		draw_arc(c, r, 0, TAU, 16, Color(1, 1, 1, 0.35), 1.0, true)
