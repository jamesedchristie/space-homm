extends Node2D
## Tactical battle screen. Wires a BattleEngine to input, AI and visuals.
## No game rules live here: clicks become commands, engine events become
## animations. The same screen will host ground and exploration missions.
##
## Standalone (F6 on this scene): plays `scenario_id`, "Play again" restarts.
## Embedded (from the galaxy): call configure() before adding it to the tree;
## "Continue" emits battle_finished with the finished engine.

## Emitted when an embedded battle is over and the player clicks Continue.
signal battle_finished(engine: BattleEngine)

enum Mode { MOVE, TARGET }

@export var scenario_id := "first_skirmish"
## 0 picks a random seed each battle (shown in the log for reproducing bugs).
@export var rng_seed := 0
## Pause between AI actions, in seconds.
@export var ai_step_delay := 0.3

@onready var map_view: HexMapView = $MapView
@onready var units_layer: Node2D = $MapView/Units
@onready var fx: FxLayer = $MapView/Fx
@onready var hud: BattleHud = $HUD/Hud

var data: DataRegistry
var engine: BattleEngine
var ai := RuleBasedAI.new()
var unit_views: Dictionary = {}  # unit id -> UnitView
var mode := Mode.MOVE
var selected_ability := ""
var autoplay := false

var _busy := false
var _embedded_scenario: Dictionary = {}
var _hover: Variant = null
var _reach: Dictionary = {}
var _targets: Array[Vector2i] = []
## Bumped on restart so coroutines from the previous battle stop.
var _battle_token := 0


func _ready() -> void:
	data = DataRegistry.get_default()
	for e in data.errors:
		push_error("Content: " + e)
	for e in EffectRegistry.validate_content(data):
		push_error("Content: " + e)
	hud.ability_pressed.connect(_on_ability_pressed)
	hud.end_turn_pressed.connect(_on_end_turn_pressed)
	hud.restart_pressed.connect(_on_result_button)
	get_viewport().size_changed.connect(_fit_map)
	start_battle()


## Use a generated scenario (e.g. from GalaxyEngine.pending_battle_scenario()).
func configure(scenario: Dictionary, battle_seed: int) -> void:
	_embedded_scenario = scenario
	rng_seed = battle_seed


func is_embedded() -> bool:
	return not _embedded_scenario.is_empty()


func _on_result_button() -> void:
	if is_embedded():
		battle_finished.emit(engine)
	else:
		start_battle()


func start_battle() -> void:
	_battle_token += 1
	var token := _battle_token
	for v: UnitView in unit_views.values():
		v.queue_free()
	unit_views.clear()
	hud.hide_result()
	hud.clear_log()
	mode = Mode.MOVE
	selected_ability = ""

	var scenario: Dictionary = _embedded_scenario if is_embedded() else data.scenarios[scenario_id]
	engine = BattleEngine.from_scenario(data, scenario, rng_seed)
	map_view.setup(engine.state.grid)
	for u: BattleUnit in engine.state.units.values():
		var view := UnitView.new()
		units_layer.add_child(view)
		view.setup(u, data.units[u.def_id], HexMapView.CELL_SIZE)
		view.position = map_view.cell_center(u.cell)
		unit_views[u.id] = view
	_fit_map()
	hud.set_objective(engine.objective_text())
	hud.log_line("[color=#%s]%s  (seed %d)[/color]" % [Palette.hex(Palette.TEXT_DIM),
			scenario.get("name", "Battle"), engine.state.seed_value])

	_busy = true
	await _play(engine.start(), token)
	if token == _battle_token:
		await _run_ai_turns(token)


# --- Turn driving -------------------------------------------------------------

func _is_human_turn() -> bool:
	var u := engine.state.active_unit()
	if u == null or autoplay:
		return false
	return engine.state.team_info(u.team).get("controller", "ai") == "player"


## Lets the AI act until it is a human's turn or the battle ends.
func _run_ai_turns(token: int) -> void:
	_busy = true
	_refresh()
	while not engine.state.is_over and not _is_human_turn():
		await get_tree().create_timer(ai_step_delay).timeout
		if token != _battle_token:
			return
		var unit := engine.state.active_unit()
		var result := engine.submit(ai.decide(engine))
		if not result.ok:
			push_warning("AI command rejected: %s" % result.error)
			result = engine.submit(EndTurnCommand.new(unit.id))
		await _play(result.events, token)
		if token != _battle_token:
			return
	_busy = false
	mode = Mode.MOVE
	selected_ability = ""
	_refresh()


func _submit_player(cmd: BattleCommand) -> void:
	if _busy:
		return
	var result := engine.submit(cmd)
	if not result.ok:
		hud.set_hint(result.error)
		return
	var token := _battle_token
	_busy = true
	mode = Mode.MOVE
	selected_ability = ""
	_refresh()
	await _play(result.events, token)
	if token != _battle_token:
		return
	# Out of things to do: end the turn automatically.
	var u := engine.state.active_unit()
	if not engine.state.is_over and u != null and _is_human_turn() and not engine.has_available_actions(u.id):
		await _play(engine.submit(EndTurnCommand.new(u.id)).events, token)
		if token != _battle_token:
			return
	await _run_ai_turns(token)


# --- Event playback -----------------------------------------------------------

func _play(events: Array[Dictionary], token: int) -> void:
	for e in events:
		if token != _battle_token:
			return
		var line := EventFormatter.describe(e, engine)
		if not line.is_empty():
			hud.log_line(line)
		match e["type"]:
			BattleEvents.ROUND_STARTED:
				hud.set_round(e["round"])
			BattleEvents.TURN_STARTED:
				_refresh()
			BattleEvents.UNIT_MOVED:
				var points: Array[Vector2] = []
				var path: Array = e["path"]
				for i in range(1, path.size()):
					points.append(map_view.cell_center(path[i]))
				await unit_views[e["unit"]].move_along(points)
			BattleEvents.ABILITY_USED:
				await _play_ability(e)
			BattleEvents.DAMAGE_DEALT:
				var view: UnitView = unit_views[e["target"]]
				view.set_values(e["hull"], e["shields"])
				view.play_hit()
				var text := "-%d" % (e["shield_damage"] + e["hull_damage"])
				fx.float_text(view.position, text, Palette.HULL if e["hull_damage"] > 0 else Palette.SHIELDS)
				await _wait(0.15)
			BattleEvents.HEALED:
				var view: UnitView = unit_views[e["target"]]
				fx.float_text(view.position, "+%d %s" % [e["amount"], e["stat"]], Palette.GOOD)
				view.refresh(engine.state.get_unit(e["target"]))
			BattleEvents.STATUS_APPLIED, BattleEvents.STATUS_RESISTED:
				var view: UnitView = unit_views[e["target"]]
				var status_label := EventFormatter.status_name(data, e["status"])
				var resisted: bool = e["type"] == BattleEvents.STATUS_RESISTED
				fx.float_text(view.position + Vector2(0, -18), ("avoided " if resisted else "") + status_label, Palette.ACTIVE)
				await _wait(0.1)
			BattleEvents.TURN_SKIPPED:
				fx.float_text(unit_views[e["unit"]].position, "Disabled", Palette.BAD)
				await _wait(0.4)
			BattleEvents.UNIT_DESTROYED:
				fx.play("pulse", unit_views[e["unit"]].position, unit_views[e["unit"]].position, Palette.BAD)
				await unit_views[e["unit"]].play_destroyed()
			BattleEvents.BATTLE_ENDED:
				_show_result()
	_refresh_views()


func _play_ability(e: Dictionary) -> void:
	var ability: Dictionary = data.abilities[e["ability"]]
	var source: UnitView = unit_views[e["unit"]]
	var to := map_view.cell_center(e["target"])
	if ability.get("target", "") != "self":
		source.face_towards(to)
	var color := Palette.ACTIVE
	for effect: Dictionary in ability.get("effects", []):
		if effect.get("type", "") == "damage":
			color = Palette.damage_color(effect.get("damage_type", ""))
			break
	var blast := float(ability.get("radius", 0)) * HexMapView.CELL_SIZE * 1.8
	await fx.play(ability.get("fx", "projectile"), source.position, to, color, blast)


func _wait(seconds: float) -> void:
	await get_tree().create_timer(seconds).timeout


func _show_result() -> void:
	var s := engine.state
	var title := EventFormatter.result_text(engine)
	var color := Palette.TEXT
	if s.winner >= 0 and not autoplay:
		var player_won: bool = s.team_info(s.winner).get("controller", "") == "player"
		title = "Victory" if player_won else "Defeat"
		color = Palette.GOOD if player_won else Palette.BAD
	hud.show_result(title, color, "Continue" if is_embedded() else "Play again")
	# Watching an autoplayed campaign: return to the galaxy by itself.
	if autoplay and is_embedded():
		var token := _battle_token
		await _wait(1.5)
		if token == _battle_token:
			battle_finished.emit(engine)


# --- View refresh -------------------------------------------------------------

func _refresh_views() -> void:
	for id: String in unit_views:
		var u := engine.state.get_unit(id)
		if u.alive:
			unit_views[id].refresh(u)


## Recomputes highlights and HUD from engine state + current input mode.
func _refresh() -> void:
	var s := engine.state
	var active := s.active_unit()
	for id: String in unit_views:
		unit_views[id].set_active(id == s.active_unit_id)
	hud.set_round(s.round_number)
	hud.set_turn_order(_turn_order_units(), s.active_unit_id)
	var hovered: BattleUnit = s.unit_at(_hover) if _hover != null else null
	hud.show_unit(hovered if hovered != null else active, data)

	var human := not _busy and _is_human_turn()
	var reach_cells: Array[Vector2i] = []
	var area: Array[Vector2i] = []
	var path: Array[Vector2i] = []
	_reach = {}
	_targets = []

	if active == null:
		hud.set_abilities([], false)
		hud.set_hint("")
	elif not human:
		hud.set_abilities(_ability_entries(active), false)
		hud.set_hint("Autoplay: AI controls both sides. Press A to take back control." if autoplay
				else "%s is acting..." % active.name)
	elif mode == Mode.MOVE:
		hud.set_abilities(_ability_entries(active), true)
		_reach = engine.reachable_cells(active.id)
		for c: Vector2i in _reach:
			if c != active.cell:
				reach_cells.append(c)
		var hint := "%s: click a blue hex to move, or pick an ability." % active.name
		if _hover != null and _reach.has(_hover) and _hover != active.cell:
			path = Pathfinding.path_to(_reach, _hover)
			hint = "Move here: %d AP (%d left)" % [_reach[_hover]["cost"], active.ap - _reach[_hover]["cost"]]
		if _hover != null:
			hint += _terrain_hint(_hover)
		hud.set_hint(hint)
	else:
		hud.set_abilities(_ability_entries(active), true)
		var ability: Dictionary = data.abilities[selected_ability]
		_targets = engine.ability_targets(active.id, selected_ability)
		if _hover != null and _hover in _targets:
			area = engine.ability_area(active.id, selected_ability, _hover)
			hud.set_hint(_preview_text(active, _hover))
		else:
			hud.set_hint("%s: pick a red hex. Right-click to cancel.\n%s" % [ability.get("name", ""), ability.get("description", "")])

	map_view.set_highlights(reach_cells, _targets, area, path)
	map_view.set_active(active.cell if active != null else null)
	map_view.set_hover(_hover)


func _turn_order_units() -> Array[BattleUnit]:
	var out: Array[BattleUnit] = []
	var active := engine.state.active_unit()
	if active != null:
		out.append(active)
	for id in engine.state.turn_queue:
		var u := engine.state.get_unit(id)
		if u.alive:
			out.append(u)
	return out


func _ability_entries(unit: BattleUnit) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for i in unit.abilities.size():
		var id := unit.abilities[i]
		var def: Dictionary = data.abilities[id]
		var reason := engine.ability_error(unit.id, id)
		if reason.is_empty() and engine.ability_targets(unit.id, id).is_empty():
			reason = "No targets in range"
		out.append({
			"id": id, "name": def.get("name", id), "ap_cost": int(def.get("ap_cost", 0)),
			"cooldown": unit.cooldown_of(id), "enabled": reason.is_empty(), "reason": reason,
			"description": def.get("description", ""), "selected": id == selected_ability, "hotkey": i + 1,
		})
	return out


func _preview_text(active: BattleUnit, target: Vector2i) -> String:
	var lines := PackedStringArray()
	for p in engine.preview_ability(active.id, selected_ability, target):
		var u := engine.state.get_unit(p["unit"])
		var parts := PackedStringArray()
		if p["shield_damage"] > 0:
			parts.append("-%d shields" % p["shield_damage"])
		if p["hull_damage"] > 0:
			parts.append("-%d hull" % p["hull_damage"])
		if p["heal"] > 0:
			parts.append("+%d" % p["heal"])
		for st: Dictionary in p["statuses"]:
			var chance := "" if st["chance"] >= 1.0 else " %d%%" % roundi(st["chance"] * 100)
			parts.append(EventFormatter.status_name(data, st["status"]) + chance)
		var friendly := " (FRIENDLY!)" if u.team == active.team and u != active else ""
		lines.append("%s%s: %s%s" % [u.name, friendly, ", ".join(parts), "  DESTROYED" if p["lethal"] else ""])
	return "Expected: " + ("; ".join(lines) if not lines.is_empty() else "nothing in the blast")


func _terrain_hint(cell: Vector2i) -> String:
	var t := engine.state.grid.terrain_def(cell)
	return "" if t.is_empty() else "\n%s: %s" % [t.get("name", ""), t.get("description", "")]


func _fit_map() -> void:
	if engine == null:
		return
	var area := hud.map_area()
	var b := map_view.bounds()
	var f := clampf(minf((area.size.x - 32.0) / b.size.x, (area.size.y - 32.0) / b.size.y), 0.4, 1.6)
	map_view.scale = Vector2(f, f)
	map_view.position = area.get_center() - b.get_center() * f


# --- Input --------------------------------------------------------------------

func _unhandled_input(event: InputEvent) -> void:
	if engine == null:
		return
	if event is InputEventMouseMotion:
		var cell: Variant = map_view.cell_at_global(get_global_mouse_position())
		if cell != _hover:
			_hover = cell
			_refresh()
	elif event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_LEFT:
			_on_left_click()
		elif event.button_index == MOUSE_BUTTON_RIGHT:
			_cancel_targeting()
	elif event is InputEventKey and event.pressed and not event.echo:
		match event.keycode:
			KEY_ESCAPE:
				_cancel_targeting()
			KEY_SPACE, KEY_ENTER, KEY_KP_ENTER:
				_on_end_turn_pressed()
			KEY_A:
				_toggle_autoplay()
			KEY_R:
				if not is_embedded():
					start_battle()
			_:
				var index: int = event.keycode - KEY_1
				var active := engine.state.active_unit()
				if active != null and index >= 0 and index < active.abilities.size():
					_on_ability_pressed(active.abilities[index])


func _on_left_click() -> void:
	if _busy or not _is_human_turn() or _hover == null:
		return
	var active := engine.state.active_unit()
	if mode == Mode.MOVE:
		if _reach.has(_hover) and _hover != active.cell:
			_submit_player(MoveCommand.new(active.id, _hover))
	elif _hover in _targets:
		_submit_player(UseAbilityCommand.new(active.id, selected_ability, _hover))


func _on_ability_pressed(ability_id: String) -> void:
	if _busy or not _is_human_turn():
		return
	var active := engine.state.active_unit()
	var error := engine.ability_error(active.id, ability_id)
	if not error.is_empty():
		hud.set_hint(error)
		return
	if data.abilities[ability_id].get("target", "") == "self":
		_submit_player(UseAbilityCommand.new(active.id, ability_id, active.cell))
		return
	if mode == Mode.TARGET and selected_ability == ability_id:
		_cancel_targeting()
		return
	mode = Mode.TARGET
	selected_ability = ability_id
	_refresh()


func _on_end_turn_pressed() -> void:
	if _busy or not _is_human_turn():
		return
	_submit_player(EndTurnCommand.new(engine.state.active_unit_id))


func _cancel_targeting() -> void:
	if mode == Mode.TARGET:
		mode = Mode.MOVE
		selected_ability = ""
		_refresh()


func _toggle_autoplay() -> void:
	autoplay = not autoplay
	mode = Mode.MOVE
	selected_ability = ""
	hud.log_line("[i]Autoplay %s[/i]" % ("on" if autoplay else "off"))
	if autoplay and not _busy and not engine.state.is_over:
		_run_ai_turns(_battle_token)
	else:
		_refresh()
