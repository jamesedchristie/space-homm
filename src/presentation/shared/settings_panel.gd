class_name SettingsPanel
extends VBoxContainer
## Settings controls (fullscreen, volume, default views). Changes apply and
## save immediately. Used on the title screen and from the in-game menu.

signal closed


func _ready() -> void:
	GameSettings.ensure_loaded()
	add_theme_constant_override("separation", 12)
	add_child(UiKit.header("Settings", 18, Palette.ACTIVE))

	if OS.get_name() != "Web":
		var full := CheckButton.new()
		full.text = "Fullscreen  (F11)"
		full.button_pressed = GameSettings.fullscreen
		full.toggled.connect(func(on: bool) -> void:
			GameSettings.fullscreen = on
			GameSettings.apply()
			GameSettings.save())
		add_child(full)

	var volume_row := HBoxContainer.new()
	volume_row.add_theme_constant_override("separation", 10)
	volume_row.add_child(UiKit.label("Volume", 14, Palette.TEXT))
	var slider := HSlider.new()
	slider.min_value = 0
	slider.max_value = 100
	slider.step = 5
	slider.value = roundi(GameSettings.volume * 100)
	slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	slider.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var value_label := UiKit.label("%d%%" % slider.value, 13, Palette.TEXT_DIM)
	value_label.custom_minimum_size = Vector2(44, 0)
	slider.value_changed.connect(func(v: float) -> void:
		value_label.text = "%d%%" % v
		GameSettings.volume = v / 100.0
		GameSettings.apply()
		GameSettings.save())
	volume_row.add_child(slider)
	volume_row.add_child(value_label)
	add_child(volume_row)

	add_child(_view_row("Galaxy map", GameSettings.galaxy_view, func(v: String) -> void: GameSettings.galaxy_view = v))
	add_child(_view_row("Battles", GameSettings.battle_view, func(v: String) -> void: GameSettings.battle_view = v))
	var note := UiKit.label("V switches views in game; the last choice is remembered.", 12, Palette.TEXT_DIM)
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(note)

	var back := UiKit.button("Back", func() -> void: closed.emit())
	back.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	add_child(back)


func _view_row(label: String, current: String, on_change: Callable) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	var l := UiKit.label(label, 14, Palette.TEXT)
	l.custom_minimum_size = Vector2(110, 0)
	row.add_child(l)
	var picker := OptionButton.new()
	picker.add_item("3D (tilted)")
	picker.add_item("2D (top-down)")
	picker.selected = 1 if current == "2d" else 0
	picker.item_selected.connect(func(i: int) -> void:
		on_change.call("2d" if i == 1 else "3d")
		GameSettings.save())
	row.add_child(picker)
	return row
