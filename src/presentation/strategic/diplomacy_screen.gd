class_name DiplomacyScreen
extends Control
## Civ-style diplomacy: a full-screen modal with the other faction's leader as a 3D
## bust, their words typed out, and the replies you can make. It only reads the engine
## and emits DiplomacyCommands (command_requested); the owner submits them and calls
## show_result() with the events, and the leader answers in character.
##
## Modes (see open()): "first_contact" (their welcome), "hail" (you opened contact),
## "war_on_you" (they declared war: nothing to answer, it is not your turn) and
## "peace_offer" (accept or refuse).

signal command_requested(cmd: GalaxyCommand)
signal closed

const CHARS_PER_SECOND := 70.0

var _engine: GalaxyEngine
var _player := ""
var _other := ""
var _mode := ""
var _can_act := true
var _state := ""
var _awaiting := ""  # the command being answered: "peace", "war", "gift", "accept", "refuse"
var _salt := 0

var _portrait: LeaderPortrait
var _name_label: Label
var _title_label: Label
var _empire_label: Label
var _personality_label: Label
var _relation_label: Label
var _opinion_bar: ProgressBar
var _opinion_label: Label
var _opinion_fill: StyleBoxFlat
var _treasury_label: Label
var _speech: RichTextLabel
var _note: Label
var _choices: VBoxContainer
var _reveal := 0.0
var _revealing := false


func _init() -> void:
	visible = false
	mouse_filter = Control.MOUSE_FILTER_STOP
	set_anchors_preset(Control.PRESET_FULL_RECT)
	var dim := ColorRect.new()
	dim.color = Color(0.01, 0.015, 0.03, 0.9)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(dim)
	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right"]:
		margin.add_theme_constant_override("margin_" + side, 56)
	for side in ["top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 36)
	add_child(margin)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 28)
	margin.add_child(row)

	# Left: the portrait in a frame, with a nameplate.
	var left := VBoxContainer.new()
	left.add_theme_constant_override("separation", 8)
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	left.size_flags_stretch_ratio = 0.9
	row.add_child(left)
	var frame := UiKit.panel(Color(0.02, 0.03, 0.06, 1.0), Palette.ACTIVE, 2)
	frame.size_flags_vertical = Control.SIZE_EXPAND_FILL
	left.add_child(frame)
	_portrait = LeaderPortrait.new()
	_portrait.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_portrait.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_portrait.custom_minimum_size = Vector2(300, 380)
	frame.add_child(_portrait)
	var plate := UiKit.panel()
	left.add_child(plate)
	var plate_box := VBoxContainer.new()
	plate_box.add_theme_constant_override("separation", 1)
	plate.add_child(plate_box)
	_name_label = UiKit.header("", 24, Palette.TEXT)
	plate_box.add_child(_name_label)
	_title_label = UiKit.label("", 14, Palette.TEXT_DIM)
	plate_box.add_child(_title_label)
	_empire_label = UiKit.label("", 14, Palette.ACTIVE)
	plate_box.add_child(_empire_label)
	_personality_label = UiKit.label("", 12, Palette.TEXT_DIM)
	_personality_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_personality_label.custom_minimum_size = Vector2(300, 0)
	plate_box.add_child(_personality_label)

	# Right: relationship, their words, your replies.
	var right := VBoxContainer.new()
	right.add_theme_constant_override("separation", 12)
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right.size_flags_stretch_ratio = 1.1
	row.add_child(right)
	right.add_child(UiKit.header("Diplomacy", 20, Palette.ACTIVE))
	var status := UiKit.panel()
	right.add_child(status)
	var status_row := HBoxContainer.new()
	status_row.add_theme_constant_override("separation", 14)
	status.add_child(status_row)
	_relation_label = UiKit.header("", 18, Palette.GOOD)
	_relation_label.custom_minimum_size = Vector2(110, 0)
	status_row.add_child(_relation_label)
	var opinion_box := VBoxContainer.new()
	opinion_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	status_row.add_child(opinion_box)
	_opinion_label = UiKit.label("", 13, Palette.TEXT_DIM)
	opinion_box.add_child(_opinion_label)
	_opinion_bar = ProgressBar.new()
	_opinion_bar.min_value = -100
	_opinion_bar.max_value = 100
	_opinion_bar.show_percentage = false
	_opinion_bar.custom_minimum_size = Vector2(160, 12)
	_opinion_fill = StyleBoxFlat.new()
	_opinion_fill.set_corner_radius_all(3)
	_opinion_bar.add_theme_stylebox_override("fill", _opinion_fill)
	var bar_bg := StyleBoxFlat.new()
	bar_bg.bg_color = Color(0.1, 0.12, 0.18)
	bar_bg.set_corner_radius_all(3)
	_opinion_bar.add_theme_stylebox_override("background", bar_bg)
	opinion_box.add_child(_opinion_bar)
	_treasury_label = UiKit.label("", 13, Palette.TEXT)
	status_row.add_child(_treasury_label)

	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	right.add_child(spacer)
	var speech_panel := UiKit.panel(Color(0.05, 0.07, 0.12, 0.96), Palette.PANEL_BORDER, 1)
	speech_panel.custom_minimum_size = Vector2(0, 210)
	speech_panel.gui_input.connect(func(event: InputEvent) -> void:
		if event is InputEventMouseButton and event.pressed:
			_skip_reveal())
	right.add_child(speech_panel)
	var speech_box := VBoxContainer.new()
	speech_box.add_theme_constant_override("separation", 8)
	speech_panel.add_child(speech_box)
	_speech = UiKit.rich_text(21)
	_speech.scroll_active = false
	_speech.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_speech.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_speech.custom_minimum_size = Vector2(0, 130)
	speech_box.add_child(_speech)
	_note = UiKit.label("", 13, Palette.TEXT_DIM)
	_note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	speech_box.add_child(_note)

	_choices = VBoxContainer.new()
	_choices.add_theme_constant_override("separation", 6)
	right.add_child(_choices)


## Starts a conversation with `other_id` from `player_id`'s side.
## can_act: the player may issue commands now (it is their turn).
func open(engine: GalaxyEngine, player_id: String, other_id: String, mode: String, can_act: bool = true) -> void:
	_engine = engine
	_player = player_id
	_other = other_id
	_mode = mode
	_can_act = can_act
	_salt = engine.state.turn_number * 7 + hash(other_id) % 13 + hash(mode) % 5
	var data := engine.data
	var faction := _faction()
	var def := LeaderRules.leader(data, faction)
	_portrait.setup(def, Palette.team_color(int(faction.get("team", 0))))
	_name_label.text = def.get("name", faction["name"])
	_title_label.text = def.get("title", "")
	_empire_label.text = faction["name"]
	_personality_label.text = def.get("personality", "")
	_empire_label.add_theme_color_override("font_color", Palette.team_color(int(faction.get("team", 0))))
	visible = true
	_refresh_status()
	match mode:
		"first_contact":
			_say("first_contact", "pleased" if LeaderRules.negotiates(faction) else "angry")
			_state = "first_contact"
		"war_on_you":
			_say("war_on_you", "angry")
			_state = "war_notice"
		"peace_offer":
			_say("peace_offer", "neutral")
			_state = "offer"
		_:
			_say("hail_war" if _at_war() else "greeting", "grim" if _at_war() else "neutral")
			_state = "menu"


func close() -> void:
	_portrait.set_speaking(false)
	visible = false
	_revealing = false
	closed.emit()


func current_text() -> String:
	return _speech.get_parsed_text()


## True while the typewriter is still revealing the leader's words.
func is_revealing() -> bool:
	return _revealing


## The owner calls this after submitting the command this screen emitted.
## `events` are the engine's events; `error` is set when the engine refused it.
func show_result(events: Array[Dictionary], error: String = "") -> void:
	_refresh_status()
	var faction := _faction()
	if not error.is_empty():
		_note.text = error
		_state = "menu"
		_show_choices()
		return
	var kind := _awaiting
	_awaiting = ""
	var key := "farewell"
	var mood := "neutral"
	var note := ""
	match kind:
		"peace":
			key = "peace_refused"
			mood = "grim"
			for e in events:
				if e["type"] == GalaxyEvents.PEACE_SIGNED:
					key = "peace_accepted"
					mood = "pleased"
				elif e["type"] == GalaxyEvents.PEACE_REFUSED:
					note = str(e.get("reason", ""))
		"accept":
			key = "peace_accepted"
			mood = "pleased"
		"refuse":
			key = "offer_declined"
			mood = "angry"
		"war":
			key = "you_declare_war"
			mood = "angry"
		"gift":
			key = "gift"
			mood = "pleased"
			note = "You sent %d credits. They like you a little more." % DiplomacyRules.GIFT_CREDITS
		"threat":
			key = "you_declare_war"
			mood = "angry"
	_say(key, mood, note)
	_state = "menu" if kind not in ["accept", "refuse"] else "after"
	if not LeaderRules.negotiates(faction):
		_state = "barbarian"


# --- Conversation -------------------------------------------------------------

func _faction() -> Dictionary:
	return _engine.state.faction(_other)


func _at_war() -> bool:
	return _engine.state.at_war(_player, _other)


func _say(key: String, mood: String, note: String = "") -> void:
	var faction := _faction()
	var text := LeaderRules.line(_engine.data, faction, key, _engine.state.faction(_player)["name"], _salt)
	_salt += 1
	_speech.clear()
	_speech.append_text("[i]“%s”[/i]" % text)
	_note.text = note
	_speech.visible_characters = 0
	_reveal = 0.0
	_revealing = true
	_portrait.set_speaking(true)
	_portrait.set_mood(mood)
	_clear_choices()


func _process(delta: float) -> void:
	if not visible or not _revealing:
		return
	_reveal += delta * CHARS_PER_SECOND
	var total := _speech.get_total_character_count()
	_speech.visible_characters = int(_reveal)
	if int(_reveal) >= total:
		_finish_reveal()


func _skip_reveal() -> void:
	if _revealing:
		_finish_reveal()


func _finish_reveal() -> void:
	_revealing = false
	_speech.visible_characters = -1
	_portrait.set_speaking(false)
	_show_choices()


func _input(event: InputEvent) -> void:
	if not visible or not event is InputEventKey or not event.pressed or event.echo:
		return
	match event.keycode:
		KEY_SPACE, KEY_ENTER, KEY_KP_ENTER:
			if _revealing:
				_skip_reveal()
				get_viewport().set_input_as_handled()
		KEY_ESCAPE:
			if _state in ["menu", "first_contact", "war_notice", "barbarian", "after"] and not _revealing:
				get_viewport().set_input_as_handled()
				close()


func _clear_choices() -> void:
	for c in _choices.get_children():
		c.queue_free()
		_choices.remove_child(c)


func _choice(text: String, on_pressed: Callable, enabled: bool = true, tip: String = "") -> void:
	var b := UiKit.button(text, on_pressed)
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	b.custom_minimum_size = Vector2(0, 34)
	b.disabled = not enabled
	b.tooltip_text = tip
	_choices.add_child(b)


func _show_choices() -> void:
	_clear_choices()
	var faction := _faction()
	var s := _engine.state
	var credits := int(s.resources[_player].get("credits", 0))
	var farewell := func() -> void: close()
	match _state:
		"first_contact":
			if LeaderRules.negotiates(faction):
				_choice("Greetings. We come in peace.", func() -> void:
					_state = "menu"
					_say("greeting", "neutral"))
				_choice("We have nothing to discuss.", farewell)
			else:
				_choice("Answer with defiance.", func() -> void:
					_awaiting = "threat"
					show_result([]))
				_choice("Cut the channel.", farewell)
		"war_notice":
			_choice("So be it.", farewell)
			if _can_act:
				_choice("Open negotiations.", func() -> void:
					_state = "menu"
					_say("hail_war", "grim"))
		"offer":
			_choice("Accept their offer of peace.", func() -> void:
				_awaiting = "accept"
				command_requested.emit(DiplomacyCommand.new(_player, _other, "accept_peace")))
			_choice("Refuse.", func() -> void:
				_awaiting = "refuse"
				command_requested.emit(DiplomacyCommand.new(_player, _other, "refuse_peace")))
		"barbarian":
			_choice("Answer with defiance.", func() -> void:
				_awaiting = "threat"
				show_result([]))
			_choice("Cut the channel.", farewell)
		"confirm_war":
			_choice("Yes. Declare war on the %s." % faction["name"], func() -> void:
				_awaiting = "war"
				command_requested.emit(DiplomacyCommand.new(_player, _other, "declare_war")))
			_choice("On second thought, no.", func() -> void:
				_state = "menu"
				_show_choices())
		"after":
			_choice("Farewell.", farewell)
		_:
			_menu_choices(faction, credits)


func _menu_choices(faction: Dictionary, credits: int) -> void:
	var war := _at_war()
	var wait_tip := "Wait for your turn."
	var do_peace := func() -> void:
		_awaiting = "peace"
		command_requested.emit(DiplomacyCommand.new(_player, _other, "propose_peace"))
	var do_gift := func() -> void:
		_awaiting = "gift"
		command_requested.emit(DiplomacyCommand.new(_player, _other, "gift"))
	var ask_war := func() -> void:
		_state = "confirm_war"
		_show_choices()
		_note.text = "War ends any trade and lets fleets attack each other. They will not forget it."
	if war:
		var proposable: bool = LeaderRules.negotiates(faction) and faction.get("controller", "") != "player"
		_choice("Propose peace.", do_peace, _can_act and proposable, "" if _can_act else wait_tip)
	var gift_tip := "Improves their opinion of you."
	if not _can_act:
		gift_tip = wait_tip
	elif credits < DiplomacyRules.GIFT_CREDITS:
		gift_tip = "Not enough credits."
	_choice("Send a gift (%d credits)." % DiplomacyRules.GIFT_CREDITS, do_gift,
			_can_act and credits >= DiplomacyRules.GIFT_CREDITS, gift_tip)
	if not war:
		_choice("Declare war.", ask_war, _can_act, "" if _can_act else wait_tip)
	_choice("Farewell.", func() -> void: close())


func _refresh_status() -> void:
	var s := _engine.state
	var war := _at_war()
	_relation_label.text = "AT WAR" if war else "AT PEACE"
	_relation_label.add_theme_color_override("font_color", Palette.BAD if war else Palette.GOOD)
	var opinion := s.opinion(_other, _player)
	_opinion_bar.value = opinion
	_opinion_fill.bg_color = Palette.BAD.lerp(Palette.GOOD, (opinion + 100) / 200.0)
	_opinion_label.text = "Their opinion of you: %+d (%s)" % [opinion, opinion_word(opinion)]
	_treasury_label.text = "Treasury: %d" % int(s.resources[_player].get("credits", 0))


static func opinion_word(opinion: int) -> String:
	if opinion <= -60:
		return "hostile"
	if opinion <= -25:
		return "unfriendly"
	if opinion < 10:
		return "wary"
	if opinion < 40:
		return "cordial"
	if opinion < 70:
		return "friendly"
	return "devoted"
