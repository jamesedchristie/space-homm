class_name GalaxyHud
extends Control
## Galaxy UI: turn bar (top), selection info + log (right), hint line (bottom)
## and a modal dialog for battles and reports. Emits signals only.

signal end_turn_pressed
signal next_fleet_pressed
signal heroes_pressed
signal empire_pressed
signal menu_pressed
signal settings_closed
## Emitted when the player clicks one of the dialog's buttons.
signal dialog_choice(choice_id: String)

const TOP_H := 44.0
const BOTTOM_H := 36.0
const RIGHT_W := 300.0
const INFO_H := 250.0

var _turn_label: Label
var _faction_label: Label
var _resources_label: RichTextLabel
var _end_turn_button: Button
var _next_fleet_button: Button
var _info: RichTextLabel
var _log: RichTextLabel
var _hint: Label
var _dialog: DialogPanel
## Hero management overlay (shown by the galaxy screen).
var roster: HeroRoster
## Colonies / research / diplomacy overlay.
var empire: EmpirePanel
## A star system up close: bodies and building.
var system_view: SystemView


func _ready() -> void:
	mouse_filter = MOUSE_FILTER_IGNORE
	theme = GameTheme.get_theme()
	_build()


func map_area() -> Rect2:
	var s := get_viewport_rect().size
	return Rect2(Vector2(0, TOP_H), Vector2(s.x - RIGHT_W, s.y - TOP_H - BOTTOM_H))


func set_turn(turn: int, faction_name: String, color: Color) -> void:
	_turn_label.text = "Turn %d" % turn
	_faction_label.text = faction_name
	_faction_label.add_theme_color_override("font_color", color)


## The campaign objective, shown as the resource bar's tooltip.
func set_objective(text: String) -> void:
	_resources_label.tooltip_text = text


## Stockpiles and research status for the top bar (BBCode).
func set_resources(bbcode: String) -> void:
	_resources_label.clear()
	_resources_label.append_text(bbcode)


func set_end_turn_enabled(enabled: bool) -> void:
	_end_turn_button.disabled = not enabled


## How many of your fleets can still move this turn (Next Fleet button).
func set_ready_fleets(count: int, enabled: bool) -> void:
	_next_fleet_button.text = "Next Fleet (%d)  [Tab]" % count if count > 0 else "All fleets moved"
	_next_fleet_button.disabled = not enabled or count == 0


func set_info(bbcode: String) -> void:
	_info.clear()
	_info.append_text(bbcode)


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
	_turn_label = UiKit.header("Turn 1", 16, Palette.ACTIVE)
	row.add_child(_turn_label)
	_faction_label = UiKit.header("", 15, Palette.TEXT)
	row.add_child(_faction_label)
	_resources_label = UiKit.rich_text(13)
	_resources_label.scroll_following = false
	_resources_label.autowrap_mode = TextServer.AUTOWRAP_OFF
	_resources_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_resources_label.custom_minimum_size = Vector2(0, 22)
	_resources_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(_resources_label)
	row.add_child(UiKit.button("Empire  [E]", func() -> void: empire_pressed.emit()))
	row.add_child(UiKit.button("Heroes  [H]", func() -> void: heroes_pressed.emit()))
	_next_fleet_button = UiKit.button("Next Fleet  [Tab]", func() -> void: next_fleet_pressed.emit())
	_next_fleet_button.tooltip_text = "Select your next fleet that can still move this turn"
	row.add_child(_next_fleet_button)
	_end_turn_button = UiKit.button("End Turn  [Space]", func() -> void: end_turn_pressed.emit())
	row.add_child(_end_turn_button)
	row.add_child(UiKit.button("Menu  [Esc]", func() -> void: menu_pressed.emit()))

	var info_panel := UiKit.panel()
	UiKit.anchor(info_panel, 1, 0, 1, 0, -RIGHT_W, TOP_H, 0, TOP_H + INFO_H)
	add_child(info_panel)
	_info = UiKit.rich_text(13)
	_info.scroll_following = false
	info_panel.add_child(_info)

	var log_panel := UiKit.panel()
	UiKit.anchor(log_panel, 1, 0, 1, 1, -RIGHT_W, TOP_H + INFO_H, 0, 0)
	add_child(log_panel)
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
	UiKit.anchor(system_view, 0, 0, 1, 1, 30, TOP_H + 12, -RIGHT_W - 30, -BOTTOM_H - 12)
	add_child(system_view)

	_dialog = DialogPanel.new()
	_dialog.place(520, 330)
	_dialog.choice_made.connect(func(id: String) -> void: dialog_choice.emit(id))
	add_child(_dialog)
