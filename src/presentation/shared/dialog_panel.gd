class_name DialogPanel
extends PanelContainer
## Modal dialog with a title, BBCode body and a row of buttons. Used for
## battle offers, mission briefings, story triggers and reports.
##   dialog.ask("Title", "Body", [{"id": "yes", "label": "Yes"}])
##   var choice: String = await dialog.choice_made

signal choice_made(choice_id: String)

var _title: Label
var _body: RichTextLabel
var _buttons: HBoxContainer


func _init() -> void:
	var sb := StyleBoxFlat.new()
	sb.bg_color = Palette.PANEL_BG
	sb.border_color = Palette.ACTIVE
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(6)
	sb.set_content_margin_all(14)
	sb.shadow_color = Color(Palette.ACTIVE, 0.25)
	sb.shadow_size = 14
	add_theme_stylebox_override("panel", sb)
	visible = false
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 10)
	add_child(box)
	_title = UiKit.header("", 21, Palette.ACTIVE)
	_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(_title)
	_body = UiKit.rich_text(13)
	_body.scroll_following = false
	_body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	box.add_child(_body)
	_buttons = HBoxContainer.new()
	_buttons.alignment = BoxContainer.ALIGNMENT_CENTER
	_buttons.add_theme_constant_override("separation", 12)
	box.add_child(_buttons)


## Centers the dialog in its parent at the given size.
func place(width: float, height: float) -> void:
	UiKit.anchor(self, 0.5, 0.5, 0.5, 0.5, -width / 2.0, -height / 2.0, width / 2.0, height / 2.0)


## choices: [{"id": String, "label": String, "disabled"?: bool, "tooltip"?: String}]
func ask(title: String, body_bbcode: String, choices: Array[Dictionary]) -> void:
	_title.text = title
	_body.clear()
	_body.append_text(body_bbcode)
	for c in _buttons.get_children():
		c.queue_free()
	for choice in choices:
		var id: String = choice["id"]
		var button := UiKit.button(choice["label"], func() -> void:
			visible = false
			choice_made.emit(id))
		button.disabled = choice.get("disabled", false)
		button.tooltip_text = choice.get("tooltip", "")
		_buttons.add_child(button)
	visible = true


## Replaces the body text of the open dialog (e.g. a live estimate).
func set_body(body_bbcode: String) -> void:
	_body.clear()
	_body.append_text(body_bbcode)


func is_open() -> bool:
	return visible
