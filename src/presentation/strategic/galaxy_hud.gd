class_name GalaxyHud
extends Control
## Galaxy UI: turn bar (top), selection info + log (right), hint line (bottom)
## and a modal dialog for battles and reports. Emits signals only.

signal end_turn_pressed
## Emitted when the player clicks one of the dialog's buttons.
signal dialog_choice(choice_id: String)

const TOP_H := 44.0
const BOTTOM_H := 36.0
const RIGHT_W := 300.0
const INFO_H := 250.0

var _turn_label: Label
var _faction_label: Label
var _objective_label: Label
var _end_turn_button: Button
var _info: RichTextLabel
var _log: RichTextLabel
var _hint: Label
var _dialog: PanelContainer
var _dialog_title: Label
var _dialog_body: RichTextLabel
var _dialog_buttons: HBoxContainer


func _ready() -> void:
	mouse_filter = MOUSE_FILTER_IGNORE
	_build()


func map_area() -> Rect2:
	var s := get_viewport_rect().size
	return Rect2(Vector2(0, TOP_H), Vector2(s.x - RIGHT_W, s.y - TOP_H - BOTTOM_H))


func set_turn(turn: int, faction_name: String, color: Color) -> void:
	_turn_label.text = "Turn %d" % turn
	_faction_label.text = faction_name
	_faction_label.add_theme_color_override("font_color", color)


func set_objective(text: String) -> void:
	_objective_label.text = text


func set_end_turn_enabled(enabled: bool) -> void:
	_end_turn_button.disabled = not enabled


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
## Await `dialog_choice` for the answer.
func ask(title: String, body_bbcode: String, choices: Array[Dictionary]) -> void:
	_dialog_title.text = title
	_dialog_body.clear()
	_dialog_body.append_text(body_bbcode)
	for c in _dialog_buttons.get_children():
		c.queue_free()
	for choice in choices:
		var id: String = choice["id"]
		_dialog_buttons.add_child(UiKit.button(choice["label"], func() -> void:
			_dialog.visible = false
			dialog_choice.emit(id)))
	_dialog.visible = true


func is_dialog_open() -> bool:
	return _dialog.visible


func _build() -> void:
	var top := UiKit.panel()
	UiKit.anchor(top, 0, 0, 1, 0, 0, 0, 0, TOP_H)
	add_child(top)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 14)
	top.add_child(row)
	_turn_label = UiKit.label("Turn 1", 16, Palette.ACTIVE)
	row.add_child(_turn_label)
	_faction_label = UiKit.label("", 16, Palette.TEXT)
	row.add_child(_faction_label)
	_objective_label = UiKit.label("", 13, Palette.TEXT_DIM)
	_objective_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_objective_label.clip_text = true
	row.add_child(_objective_label)
	_end_turn_button = UiKit.button("End Turn  [Space]", func() -> void: end_turn_pressed.emit())
	row.add_child(_end_turn_button)

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

	_dialog = UiKit.panel(Palette.PANEL_BG, Palette.ACTIVE, 2)
	UiKit.anchor(_dialog, 0.5, 0.5, 0.5, 0.5, -230, -130, 230, 130)
	_dialog.visible = false
	add_child(_dialog)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 10)
	_dialog.add_child(box)
	_dialog_title = UiKit.label("", 22, Palette.ACTIVE)
	_dialog_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(_dialog_title)
	_dialog_body = UiKit.rich_text(13)
	_dialog_body.scroll_following = false
	_dialog_body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	box.add_child(_dialog_body)
	_dialog_buttons = HBoxContainer.new()
	_dialog_buttons.alignment = BoxContainer.ALIGNMENT_CENTER
	_dialog_buttons.add_theme_constant_override("separation", 12)
	box.add_child(_dialog_buttons)
