extends Node2D
## Tactical battle screen. Wires a BattleEngine to input, AI and visuals.
## No game rules live here: clicks become commands, engine events become
## animations. The same screen will host ground and exploration missions.
##
## Drawing goes through a BattleBoard: BattleBoard3D (2.5D, default) or
## BattleBoard2D (top-down). Press V to switch views mid-battle.
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

@onready var map_view: GridMapView = $MapView
@onready var units_layer: Node2D = $MapView/Units
@onready var fx: FxLayer = $MapView/Fx
@onready var hud: BattleHud = $HUD/Hud

## What a failed skill check costs (BattleEngine.check_odds "risks").
const RISK_TEXT := {
	"alarm": "the alarm goes up and guards dig in",
	"alert": "enemies wake and come for you",
	"spawn": "reinforcements arrive",
	"harm": "someone gets hurt",
}

## The current view of the battlefield (2D or 3D).
var board: BattleBoard

var data: DataRegistry
var engine: BattleEngine
var ai := RuleBasedAI.new()
var mode := Mode.MOVE
var selected_ability := ""
var autoplay := false

var _busy := false
var _embedded_scenario: Dictionary = {}
## Team whose point of view (fog of war) the screen shows: the human's team.
var _viewer_team := 0
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
	hud.menu_pressed.connect(_open_menu)
	hud.settings_closed.connect(func() -> void:
		# Apply a changed battle view now if nothing is animating.
		# Also rebuild the 3D board when the battle look (high quality / classic) changed.
		var look_changed := board is BattleBoard3D and _built_look != BoardGeometry.high_quality()
		if engine != null and not _busy and ((board is BattleBoard3D) != (GameSettings.battle_view == "3d") or look_changed):
			_build_board()
		_refresh())
	get_viewport().size_changed.connect(_fit_map)
	start_battle()


## Use a generated scenario (e.g. from GalaxyEngine.pending_battle_scenario()).
## The battle look the 3D board was built with (see settings_closed).
var _built_look := false


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
	hud.hide_result()
	hud.clear_log()
	mode = Mode.MOVE
	selected_ability = ""

	var scenario: Dictionary = _embedded_scenario if is_embedded() else data.scenarios[scenario_id]
	engine = BattleEngine.from_scenario(data, scenario, rng_seed)
	_viewer_team = engine.state.teams[0]["team"]
	for t in engine.state.teams:
		if t["controller"] == "player":
			_viewer_team = t["team"]
			break
	$Background/Backdrop.configure(BattleEngine.map_def_for(data, scenario).get("backdrop", {}), float(engine.state.seed_value % 97))
	_build_board()
	hud.set_objective(engine.objective_text())
	hud.log_line("[color=#%s]%s  (seed %d)[/color]" % [Palette.hex(Palette.TEXT_DIM),
			scenario.get("name", "Battle"), engine.state.seed_value])

	_busy = true
	await _play(engine.start(), token)
	if token == _battle_token:
		await _run_ai_turns(token)


## (Re)creates the board for the current view mode from engine state.
func _build_board() -> void:
	if board != null:
		board.teardown()
		board.queue_free()
	map_view.visible = false
	GameSettings.ensure_loaded()
	board = BattleBoard3D.new() if GameSettings.battle_view == "3d" else BattleBoard2D.new(map_view, units_layer, fx)
	add_child(board)
	var map_def := BattleEngine.map_def_for(data, _embedded_scenario if is_embedded() else data.scenarios[scenario_id])
	board.setup(engine, data, map_def.get("floor", ""))
	_built_look = BoardGeometry.high_quality()
	# The 3D board on Forward+ draws its own sky; the 2D nebula backdrop would cover it.
	$Background.visible = not (board is BattleBoard3D and BoardGeometry.high_quality())
	for u: BattleUnit in engine.state.units.values():
		if u.alive:
			board.add_unit(u)
	_fit_map()
	_refresh_views()


func _switch_view() -> void:
	if _busy:
		hud.set_hint("Switch views between actions")
		return
	GameSettings.battle_view = "2d" if GameSettings.battle_view == "3d" else "3d"
	GameSettings.save()
	_build_board()
	_refresh()


## True if the human's side can see this unit (always, without fog).
func _can_see(u: BattleUnit) -> bool:
	return u.team == _viewer_team or engine.state.is_visible(_viewer_team, u.cell)


## The human answers choices for their own units (unless autoplay is on).
func _human_controls(unit_id: String) -> bool:
	var u := engine.state.get_unit(unit_id)
	return u != null and not autoplay and engine.state.team_info(u.team).get("controller", "") == "player"


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
				var path: Array = e["path"]
				var seen := engine.state.get_unit(e["unit"]).team == _viewer_team
				for i in range(1, path.size()):
					seen = seen or engine.state.is_visible(_viewer_team, path[i])
				await board.move_unit(e["unit"], path, seen)
				_refresh_views()
			BattleEvents.UNIT_SPAWNED:
				board.add_unit(engine.state.get_unit(e["unit"]))
				_refresh_views()
				board.float_text(e["unit"], "Contact!", Palette.BAD)
			BattleEvents.UNIT_ALERTED:
				var alerted := engine.state.get_unit(e["unit"])
				if _can_see(alerted):
					board.float_text(e["unit"], "!", Palette.BAD)
			BattleEvents.TRIGGER_FIRED:
				await _play_trigger(e, token)
			BattleEvents.CHOICE_MADE:
				if not e["text"].is_empty() and not autoplay:
					var title: String = e["label"]
					var check: Dictionary = e.get("check", {})
					if not check.is_empty():
						title = "%s: %s" % [String(check["skill"]).capitalize(), "success" if check["success"] else "failed"]
					hud.ask(title, e["text"], [{"id": "ok", "label": "Continue"}])
					await hud.dialog_choice
			BattleEvents.REWARD_GAINED:
				var actor := engine.state.active_unit()
				if actor != null:
					board.float_text(actor.id, _reward_text(e["reward"]), Palette.ACTIVE, 30.0)
			BattleEvents.ABILITY_USED:
				if e.get("reaction", false):
					board.float_text(e["unit"], "Overwatch!", Palette.ACTIVE, 26.0)
				await _play_ability(e)
			BattleEvents.DAMAGE_DEALT:
				board.set_unit_values(e["target"], e["hull"], e["shields"])
				board.unit_hit(e["target"], e["source"], e["shield_damage"] > 0)
				var text := "-%d" % (e["shield_damage"] + e["hull_damage"])
				board.float_text(e["target"], text, Palette.HULL if e["hull_damage"] > 0 else Palette.SHIELDS)
				await _wait(0.15)
			BattleEvents.HEALED:
				board.float_text(e["target"], "+%d %s" % [e["amount"], e["stat"]], Palette.GOOD)
				board.refresh_unit(engine.state.get_unit(e["target"]), _can_see(engine.state.get_unit(e["target"])))
			BattleEvents.STATUS_APPLIED, BattleEvents.STATUS_RESISTED:
				var status_label := EventFormatter.status_name(data, e["status"])
				var resisted: bool = e["type"] == BattleEvents.STATUS_RESISTED
				# Unseen units (an alarm going up in the dark) don't give their position away.
				if _can_see(engine.state.get_unit(e["target"])):
					board.float_text(e["target"], ("avoided " if resisted else "") + status_label, Palette.ACTIVE, 18.0)
					await _wait(0.1)
			BattleEvents.TURN_SKIPPED:
				board.float_text(e["unit"], "Disabled", Palette.BAD)
				await _wait(0.4)
			BattleEvents.UNIT_DESTROYED:
				var dead := engine.state.get_unit(e["unit"])
				await board.destroy_unit(e["unit"], "ship" in dead.tags or "station" in dead.tags)
			BattleEvents.BATTLE_ENDED:
				_show_result()
	_refresh_views()


## Story beat: show the text, and if it offers choices, let the human pick
## (the AI picks for its own units through RuleBasedAI).
func _play_trigger(e: Dictionary, token: int) -> void:
	var choices: Array = e["choices"]
	if e["unit"] == "":
		# Timed trigger: show it if the human plays the team it's for.
		if autoplay or engine.state.team_info(int(e.get("team", 0))).get("controller", "") != "player":
			return
	elif not _human_controls(e["unit"]):
		return
	var buttons: Array[Dictionary] = []
	var checks: Array = e.get("checks", [])
	var notes := PackedStringArray()
	for i in choices.size():
		var label: String = choices[i]
		if i < checks.size() and not checks[i].is_empty():
			var c: Dictionary = checks[i]
			label += "  [%s %d%%]" % [String(c["skill"]).capitalize(), roundi(c["chance"] * 100.0)]
			var note := "%s: %s rolls %s (%d%%)" % [choices[i], c["by"], String(c["skill"]).capitalize(), roundi(c["chance"] * 100.0)]
			var risks := PackedStringArray()
			for r: String in c.get("risks", []):
				risks.append(RISK_TEXT.get(r, r))
			if not risks.is_empty():
				note += ". If it fails: " + ", ".join(risks)
			notes.append(note)
		buttons.append({"id": str(i), "label": label})
	if buttons.is_empty():
		buttons.append({"id": "ok", "label": "Continue"})
	var body: String = e["text"]
	if not notes.is_empty():
		body += "\n\n" + UiKit.color_tag("\n".join(notes), Palette.TEXT_DIM)
	hud.ask(e["title"] if not e["title"].is_empty() else "Event", body, buttons)
	var answer: String = await hud.dialog_choice
	if token != _battle_token or choices.is_empty():
		return
	var result := engine.submit(ChooseOptionCommand.new(e["unit"], int(answer)))
	if result.ok:
		await _play(result.events, token)


func _reward_text(reward: Dictionary) -> String:
	var parts := PackedStringArray()
	if reward.has("xp"):
		parts.append("+%d XP" % reward["xp"])
	for k in ["credits", "alloys"]:
		if reward.has(k):
			parts.append("+%d %s" % [reward[k], k])
	if reward.has("research"):
		parts.append("+%d research" % reward["research"])
	if reward.has("intel"):
		parts.append("intel")
	if reward.has("loyalty"):
		parts.append("%+d loyalty" % reward["loyalty"])
	for item_id: String in reward.get("items", []):
		parts.append(data.items.get(item_id, {}).get("name", item_id))
	if reward.has("trait"):
		parts.append(data.traits.get(reward["trait"], {}).get("name", reward["trait"]))
	return ", ".join(parts)


func _play_ability(e: Dictionary) -> void:
	var ability: Dictionary = data.abilities[e["ability"]]
	var color := Palette.ACTIVE
	var laser := "Blue"
	for effect: Dictionary in ability.get("effects", []):
		if effect.get("type", "") == "damage":
			color = Palette.damage_color(effect.get("damage_type", ""))
			laser = Palette.DAMAGE_LASERS.get(effect.get("damage_type", ""), "Blue")
			break
	# "melee": true abilities lunge at their target (the "fx" field is the fallback look).
	var kind: String = "melee" if ability.get("melee", false) else ability.get("fx", "projectile")
	await board.play_ability(kind, e["unit"], e["target"], color,
			int(ability.get("radius", 0)), laser)


func _wait(seconds: float) -> void:
	await get_tree().create_timer(seconds).timeout


func _show_result() -> void:
	var s := engine.state
	var title := EventFormatter.result_text(engine)
	var color := Palette.TEXT
	if s.winner >= 0 and not autoplay:
		var player_won: bool = s.team_info(s.winner).get("controller", "") == "player"
		title = "Victory" if player_won else "Defeat"
		if not s.mission_id.is_empty():
			title = "Mission complete" if player_won else "Mission failed"
		color = Palette.GOOD if player_won else Palette.BAD
	elif not s.mission_id.is_empty() and s.winner == BattleState.DRAW:
		title = "Out of time: the squad withdraws"
	hud.show_result(title, color, "Continue" if is_embedded() else "Play again")
	# Watching an autoplayed campaign: return to the galaxy by itself.
	if autoplay and is_embedded():
		var token := _battle_token
		await _wait(1.5)
		if token == _battle_token:
			battle_finished.emit(engine)


# --- View refresh -------------------------------------------------------------

func _refresh_views() -> void:
	var s := engine.state
	if s.fog_enabled:
		board.set_fog(s.explored.get(_viewer_team, {}), s.visible_cells(_viewer_team))
	for u: BattleUnit in s.units.values():
		if u.alive:
			board.refresh_unit(u, _can_see(u))
	# Objective cells (green) and unfired story triggers (yellow).
	var markers := {}
	for t in s.triggers:
		if not t["fired"] and int(t.get("team", 0)) == _viewer_team:
			for c: Vector2i in t["_cells"]:
				markers[c] = {"color": Color("ffd166"), "label": "$"} if t.get("marker", "") == "loot" \
						else {"color": Palette.ACTIVE, "label": "?"}
	for o in s.objectives:
		for c in o.marked_cells():
			markers[c] = {"color": Palette.GOOD, "label": "★", "always": true}
	board.set_markers(markers)


## Recomputes highlights and HUD from engine state + current input mode.
func _refresh() -> void:
	var s := engine.state
	var active := s.active_unit()
	board.set_active_unit(s.active_unit_id)
	hud.set_round(s.round_number)
	hud.set_turn_order(_turn_order_units(), s.active_unit_id)
	var hovered: BattleUnit = s.unit_at(_hover) if _hover != null else null
	if hovered != null and not _can_see(hovered):
		hovered = null
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
			hint += _cover_hint(active, _hover)
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

	board.set_highlights(reach_cells, _targets, area, path)
	board.set_active_cell(active.cell if active != null else null)
	board.set_hover(_hover)


func _turn_order_units() -> Array[BattleUnit]:
	var out: Array[BattleUnit] = []
	var active := engine.state.active_unit()
	if active != null:
		out.append(active)
	for id in engine.state.turn_queue:
		var u := engine.state.get_unit(id)
		if u.alive and u.alert and _can_see(u):
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
		var cover: Dictionary = p.get("cover", {})
		if cover.get("cover", "") == CoverRules.FULL:
			parts.append("full cover -50%")
		elif cover.get("cover", "") == CoverRules.HALF:
			parts.append("half cover -30%")
		elif cover.get("flanked", false):
			parts.append("FLANKED +25%")
		lines.append("%s%s: %s%s" % [u.name, friendly, ", ".join(parts), "  DESTROYED" if p["lethal"] else ""])
	return "Expected: " + ("; ".join(lines) if not lines.is_empty() else "nothing in the blast")


## "  ·  cover: full vs Boarder, flanked by Drone" for a cell the unit could move to.
func _cover_hint(unit: BattleUnit, cell: Vector2i) -> String:
	var parts := PackedStringArray()
	for e in engine.state.living_enemies_of(unit):
		if engine.state.fog_enabled and not engine.state.is_visible(unit.team, e.cell):
			continue
		var c := CoverRules.evaluate(engine.state, e.cell, cell)
		if c["cover"] != "":
			parts.append("%s cover vs %s" % [c["cover"], e.name])
		elif c["flanked"]:
			parts.append("FLANKED by %s" % e.name)
	return "" if parts.is_empty() else "  ·  " + ", ".join(parts)


func _terrain_hint(cell: Vector2i) -> String:
	var t := engine.state.grid.terrain_def(cell)
	return "" if t.is_empty() else "\n%s: %s" % [t.get("name", ""), t.get("description", "")]


func _fit_map() -> void:
	if engine != null and board != null:
		board.fit(hud.map_area())


# --- Input --------------------------------------------------------------------

func _unhandled_input(event: InputEvent) -> void:
	if engine == null or hud.is_dialog_open():
		return
	if board.handle_input(event):
		return
	if event is InputEventMouseMotion:
		var cell: Variant = board.cell_at_mouse()
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
				if mode == Mode.TARGET:
					_cancel_targeting()
				else:
					_open_menu()
			KEY_SPACE, KEY_ENTER, KEY_KP_ENTER:
				_on_end_turn_pressed()
			KEY_A:
				_toggle_autoplay()
			KEY_V:
				_switch_view()
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


## Esc / Menu button: resume, settings, autoplay, restart or quit.
func _open_menu() -> void:
	if engine == null or hud.is_dialog_open():
		return
	var choices: Array[Dictionary] = [{"id": "resume", "label": "Resume"}, {"id": "settings", "label": "Settings"}]
	if not autoplay and not engine.state.is_over:
		choices.append({"id": "autoplay", "label": "Let the AI finish"})
	if not is_embedded():
		choices.append({"id": "restart", "label": "Restart"})
	if String(_embedded_scenario.get("id", "")).begins_with("showcase"):
		choices.append({"id": "leave", "label": "Back to the main menu"})
	if OS.get_name() != "Web":
		choices.append({"id": "quit", "label": "Quit game"})
	var body := UiKit.color_tag("Battles can't be saved: the campaign autosaves at the start of your next turn. "
			+ "\"Let the AI finish\" plays both sides to the end (A toggles it back).", Palette.TEXT_DIM)
	hud.show_menu(body, choices)
	var token := _battle_token
	var choice: String = await hud.menu_choice
	if token != _battle_token:
		return
	match choice:
		"settings":
			hud.show_settings()
		"autoplay":
			_toggle_autoplay()
		"restart":
			start_battle()
		"leave":
			battle_finished.emit(engine)
		"quit":
			get_tree().quit()


func _toggle_autoplay() -> void:
	autoplay = not autoplay
	mode = Mode.MOVE
	selected_ability = ""
	hud.log_line("[i]Autoplay %s[/i]" % ("on" if autoplay else "off"))
	if autoplay and not _busy and not engine.state.is_over:
		_run_ai_turns(_battle_token)
	else:
		_refresh()
