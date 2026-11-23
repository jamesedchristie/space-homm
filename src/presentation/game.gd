extends Node
## Top-level flow: main menu -> galaxy screen, which swaps in a tactical
## battle screen when the player chooses to fight and gets the result back.

const GALAXY_SCENE := preload("res://src/presentation/strategic/galaxy_screen.tscn")
const BATTLE_SCENE := preload("res://src/presentation/tactical/battle_screen.tscn")

## Skip the title screen and start a campaign straight away (tools, F6 runs).
@export var skip_menu := false

var menu: MainMenu
var galaxy: Node
var battle: Node


func _ready() -> void:
	GameSettings.apply()
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--showcase="):
			_show_showcase.call_deferred(arg.trim_prefix("--showcase="))
			return
	if skip_menu or "--new-campaign" in OS.get_cmdline_user_args():
		new_campaign({})
	else:
		show_menu()


var _fps: Label


func _process(_delta: float) -> void:
	if _fps != null and _fps.visible:
		_fps.text = "%d fps  ·  %s  ·  %d draw calls" % [Engine.get_frames_per_second(), RenderingServer.get_current_rendering_method(),
				RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME)]


## F3: a frame-rate readout (for judging the graphics settings on your machine).
func _toggle_fps() -> void:
	if _fps == null:
		var layer := CanvasLayer.new()
		layer.layer = 100
		add_child(layer)
		_fps = UiKit.label("", 13, Palette.ACTIVE)
		_fps.position = Vector2(8, 52)
		layer.add_child(_fps)
		_fps.visible = false
	_fps.visible = not _fps.visible


func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_F3:
		_toggle_fps()
		get_viewport().set_input_as_handled()
		return
	if event is InputEventKey and event.pressed and not event.echo and (event.keycode == KEY_F11
			or (event.keycode == KEY_ENTER and event.alt_pressed)):
		GameSettings.toggle_fullscreen()
		get_viewport().set_input_as_handled()


func show_menu(error: String = "") -> void:
	_clear()
	menu = MainMenu.new()
	menu.new_campaign_requested.connect(func(options: Dictionary) -> void: new_campaign.call_deferred(options))
	menu.load_requested.connect(func(slot: String) -> void: load_game.call_deferred(slot))
	menu.quit_requested.connect(func() -> void: get_tree().quit())
	menu.showcase_requested.connect(func(id: String) -> void: _show_showcase.call_deferred(id))
	add_child(menu)
	if not error.is_empty():
		menu.show_error(error)


## options: {"campaign", "permadeath", "seed"} (all optional).
func new_campaign(options: Dictionary) -> void:
	_show_galaxy()
	if options.has("campaign"):
		galaxy.campaign_id = options["campaign"]
	galaxy.rng_seed = int(options.get("seed", 0))
	if options.has("permadeath"):
		galaxy.permadeath_override = options["permadeath"]
	galaxy.player_species = options.get("species", "")
	galaxy.start_campaign()


func load_game(slot: String) -> void:
	var loaded := GalaxySave.load_slot(DataRegistry.get_default(), slot)
	if loaded.has("error"):
		if galaxy != null and galaxy.is_inside_tree():
			galaxy.hud.set_hint(loaded["error"])
		else:
			show_menu(loaded["error"])
		return
	if galaxy == null:
		_show_galaxy()
	galaxy.load_campaign(loaded["engine"], loaded["campaign"], MainMenu.slot_label(slot))


func _show_galaxy() -> void:
	_clear()
	galaxy = GALAXY_SCENE.instantiate()
	galaxy.auto_start = false
	galaxy.battle_requested.connect(func(scenario: Dictionary, battle_seed: int) -> void:
		_show_battle.call_deferred(scenario, battle_seed))
	galaxy.main_menu_requested.connect(func() -> void: show_menu.call_deferred())
	galaxy.load_requested.connect(func(slot: String) -> void: load_game.call_deferred(slot))
	add_child(galaxy)


func _clear() -> void:
	for node: Node in [menu, galaxy, battle]:
		if node != null:
			if node.get_parent() == self:
				remove_child(node)
			node.queue_free()
	menu = null
	galaxy = null
	battle = null


func _show_showcase(scenario_id: String) -> void:
	_clear()
	battle = BATTLE_SCENE.instantiate()
	battle.configure(DataRegistry.get_default().scenarios[scenario_id], 0)
	battle.battle_finished.connect(func(_engine: BattleEngine) -> void: show_menu.call_deferred(), CONNECT_ONE_SHOT)
	add_child(battle)


func _show_battle(scenario: Dictionary, battle_seed: int) -> void:
	remove_child(galaxy)  # keeps it alive with all its state, just off-screen
	battle = BATTLE_SCENE.instantiate()
	battle.configure(scenario, battle_seed)
	battle.autoplay = galaxy.autoplay
	battle.battle_finished.connect(func(engine: BattleEngine) -> void:
		_return_to_galaxy.call_deferred(engine), CONNECT_ONE_SHOT)
	add_child(battle)


func _return_to_galaxy(engine: BattleEngine) -> void:
	remove_child(battle)
	battle.queue_free()
	battle = null
	add_child(galaxy)
	galaxy.on_battle_finished(engine)
