class_name MainMenu
extends Control
## Title screen: continue the latest save, start a new campaign (with
## options), load a save, quit. Emits signals; Game does the work.

## options: {"campaign": id, "permadeath": bool, "seed": int (0 = random)}
signal new_campaign_requested(options: Dictionary)
signal load_requested(slot: String)
signal quit_requested

var data: DataRegistry
var _pages: Control
var _status: Label


func _ready() -> void:
	theme = GameTheme.get_theme()
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	data = DataRegistry.get_default()
	var layer := CanvasLayer.new()
	layer.layer = -1
	add_child(layer)
	var backdrop := SpaceBackdrop.new()
	layer.add_child(backdrop)
	backdrop.configure({"a": "#1a2e6b", "b": "#611f6b", "density": 0.6}, 9.0)

	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 18)
	UiKit.anchor(column, 0.5, 0.5, 0.5, 0.5, -260, -250, 260, 250)
	add_child(column)
	var title := UiKit.header("SPACE HOMM", 46, Palette.ACTIVE)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(title)
	var subtitle := UiKit.label("working title", 13, Palette.TEXT_DIM)
	subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(subtitle)
	var panel := UiKit.panel()
	panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.add_child(panel)
	_pages = MarginContainer.new()
	_pages.add_theme_constant_override("margin_left", 16)
	_pages.add_theme_constant_override("margin_right", 16)
	_pages.add_theme_constant_override("margin_top", 12)
	_pages.add_theme_constant_override("margin_bottom", 12)
	panel.add_child(_pages)
	_status = UiKit.label("", 13, Palette.BAD)
	_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	column.add_child(_status)
	show_main()


## Shows an error under the menu (e.g. a save that failed to load).
func show_error(text: String) -> void:
	_status.text = text


func show_main() -> void:
	var box := _page()
	var saves := GalaxySave.list()
	if not saves.is_empty():
		var latest: Dictionary = saves[0]
		var b := _big_button("Continue", func() -> void: load_requested.emit(latest["slot"]))
		b.tooltip_text = _describe(latest)
		box.add_child(b)
		box.add_child(_note(_describe(latest)))
	box.add_child(_big_button("New campaign", show_new_campaign))
	var load_button := _big_button("Load game", show_load)
	load_button.disabled = saves.is_empty()
	box.add_child(load_button)
	box.add_child(_big_button("Settings", show_settings))
	if OS.get_name() != "Web":
		box.add_child(_big_button("Quit", func() -> void: quit_requested.emit()))


func show_new_campaign() -> void:
	var box := _page()
	box.add_child(UiKit.header("New campaign", 18, Palette.ACTIVE))
	var picker := OptionButton.new()
	var ids: Array = data.campaigns.keys()
	for id: String in ids:
		picker.add_item(data.campaigns[id].get("name", id))
	box.add_child(picker)
	var description := _note("")
	box.add_child(description)
	var species_row := HBoxContainer.new()
	species_row.add_theme_constant_override("separation", 10)
	species_row.add_child(UiKit.label("Play as", 14, Palette.TEXT))
	var species_picker := OptionButton.new()
	var species_ids: Array = data.species.keys()
	for sp_id: String in species_ids:
		species_picker.add_item("%s  (%s)" % [data.species[sp_id]["empire_name"], data.species[sp_id]["name"]])
	species_row.add_child(species_picker)
	box.add_child(species_row)
	var species_note := _note("")
	box.add_child(species_note)
	species_picker.item_selected.connect(func(i: int) -> void:
		var sp: Dictionary = data.species[species_ids[i]]
		species_note.text = "%s  %s" % [sp.get("description", ""), sp.get("bonus_text", "")])
	species_picker.item_selected.emit(0)
	var permadeath := CheckButton.new()
	permadeath.text = "Permadeath: heroes who fall on missions die"
	box.add_child(permadeath)
	var seed_row := HBoxContainer.new()
	seed_row.add_child(UiKit.label("Seed (blank = random)", 13, Palette.TEXT_DIM))
	var seed_edit := LineEdit.new()
	seed_edit.placeholder_text = "random"
	seed_edit.custom_minimum_size = Vector2(140, 0)
	seed_row.add_child(seed_edit)
	box.add_child(seed_row)
	var on_pick := func(index: int) -> void:
		var def: Dictionary = data.campaigns[ids[index]]
		description.text = def.get("description", "")
		permadeath.button_pressed = def.get("permadeath", false)
	picker.item_selected.connect(on_pick)
	on_pick.call(0)
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 12)
	row.add_child(UiKit.button("Start", func() -> void:
		new_campaign_requested.emit({"campaign": ids[picker.selected], "permadeath": permadeath.button_pressed,
				"species": species_ids[species_picker.selected],
				"seed": int(seed_edit.text) if seed_edit.text.strip_edges().is_valid_int() else 0})))
	row.add_child(UiKit.button("Back", show_main))
	box.add_child(row)


func show_settings() -> void:
	var box := _page()
	var panel := SettingsPanel.new()
	panel.closed.connect(show_main)
	box.add_child(panel)


func show_load() -> void:
	var box := _page()
	box.add_child(UiKit.header("Load game", 18, Palette.ACTIVE))
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	box.add_child(scroll)
	var list := VBoxContainer.new()
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(list)
	for s in GalaxySave.list():
		var slot: String = s["slot"]
		var b := UiKit.button(_describe(s), func() -> void: load_requested.emit(slot))
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		list.add_child(b)
	box.add_child(UiKit.button("Back", show_main))


static func slot_label(slot: String) -> String:
	match slot:
		GalaxySave.AUTOSAVE:
			return "Autosave"
		GalaxySave.QUICKSAVE:
			return "Quicksave"
	return slot.capitalize()


static func _describe(s: Dictionary) -> String:
	var meta: Dictionary = s.get("meta", {})
	return "%s  ·  %s, turn %d  ·  %s" % [slot_label(s["slot"]), meta.get("campaign_name", "?"),
			int(meta.get("turn", 0)), str(meta.get("saved_at", "")).replace("T", " ")]


func _page() -> VBoxContainer:
	_status.text = ""
	for c in _pages.get_children():
		c.queue_free()
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 12)
	_pages.add_child(box)
	return box


func _big_button(text: String, on_pressed: Callable) -> Button:
	var b := UiKit.button(text, on_pressed)
	b.custom_minimum_size = Vector2(0, 44)
	b.add_theme_font_size_override("font_size", 18)
	return b


func _note(text: String) -> Label:
	var l := UiKit.label(text, 12, Palette.TEXT_DIM)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	return l
