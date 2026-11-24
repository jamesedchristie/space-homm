extends Node2D
## Galaxy (strategic) screen. Wires a GalaxyEngine to input, AI and visuals,
## from the player's faction's point of view (fog of war).
##
## Battles: when one involves the player, a dialog offers Fight or
## Auto-resolve. "Fight" emits battle_requested; the owner (Game) shows the
## tactical BattleScreen and calls on_battle_finished() afterwards. Without an
## owner (running this scene alone with F6) battles are auto-resolved.

## Ask the owner to show a tactical battle.
signal battle_requested(scenario: Dictionary, battle_seed: int)
## Internal: the owner handed back a finished battle.
signal battle_returned(engine: BattleEngine)
## The player chose "Main menu" in the in-game menu.
signal main_menu_requested
## The player chose a save to load (the owner loads it via load_campaign()).
signal load_requested(slot: String)


@export var campaign_id := "the_drift"
## 0 picks a random seed each campaign.
@export var rng_seed := 0
## Start a campaign on _ready (running this scene alone). Game turns it off.
@export var auto_start := true
## Autoplay: the AI also plays the player's faction (press A).
@export var autoplay := false
## In autoplay, play battles involving the player on the battle screen
## (with autoplay there too) instead of auto-resolving them.
@export var watch_battles := false

@onready var map_view: GridMapView = $MapView
@onready var planets_layer: Node2D = $MapView/Planets
@onready var fleets_layer: Node2D = $MapView/Fleets
@onready var anomalies_layer: Node2D = $MapView/Anomalies
@onready var fx: FxLayer = $MapView/Fx
@onready var hud: GalaxyHud = $HUD/Hud

var data: DataRegistry
var engine: GalaxyEngine
var ai := GalaxyAI.new()
var player_faction := ""
var board: GalaxyBoard
var selected_fleet := ""
var selected_planet := ""
var selected_anomaly := ""
## Species the player chose ("" = the campaign's). The player's faction takes
## its species and empire name; an AI faction of that species swaps with the
## player's original one so every species stays unique.
var player_species := ""
## Optional override of the campaign's permadeath setting (true/false), or null.
var permadeath_override: Variant = null

var _busy := false
## First contacts made during an AI turn, shown when the player's turn starts.
var _queued_contacts: Array[String] = []
## Peace offers already presented ("from>to@turn").
var _offers_shown: Dictionary = {}
var _last_autosave_turn := -1
## Ships picked for detaching (D); while non-empty, clicks place the new fleet.
var _split_ships: Array[String] = []
var _hover: Variant = null
var _reach: Dictionary = {}
var _attack_cells: Array[Vector2i] = []
var _visible: Dictionary = {}
## Bumped on restart so coroutines from the previous campaign stop.
var _token := 0


func _ready() -> void:
	data = DataRegistry.get_default()
	for e in data.errors:
		push_error("Content: " + e)
	hud.end_turn_pressed.connect(_on_end_turn_pressed)
	hud.next_fleet_pressed.connect(func() -> void:
		if not _busy and _is_human_turn() and not hud.system_view.visible:
			_select_next_fleet()
			_refresh())
	hud.heroes_pressed.connect(_toggle_roster)
	hud.empire_pressed.connect(_toggle_empire)
	hud.empire.command_requested.connect(_on_empire_command)
	hud.empire.closed.connect(_refresh)
	hud.roster.command_requested.connect(_on_roster_command)
	hud.roster.closed.connect(_refresh)
	hud.system_view.command_requested.connect(_on_system_command)
	hud.system_view.send_ship_requested.connect(func(uid: String) -> void:
		hud.system_view.close()
		_start_send(uid))
	hud.system_view.closed.connect(_refresh)
	hud.research_pressed.connect(_toggle_tech_tree)
	hud.minimap.jump_requested.connect(func(pixel: Vector2) -> void:
		if board != null:
			board.center_on_pixel(pixel))
	hud.tech_tree.command_requested.connect(_on_tech_command)
	hud.tech_tree.closed.connect(_refresh)
	hud.empire.tech_tree_requested.connect(_toggle_tech_tree)
	hud.empire.contact_requested.connect(_on_contact_requested)
	hud.diplomacy.command_requested.connect(_on_diplomacy_command)
	hud.empire.system_requested.connect(func(planet_id: String) -> void:
		hud.empire.visible = false
		_open_system(planet_id))
	hud.menu_pressed.connect(_open_menu)
	hud.settings_closed.connect(func() -> void:
		# Apply a changed map view right away.
		var look_changed: bool = board is GalaxyBoard3D and board._hq != BoardGeometry.high_quality()
		if engine != null and ((board is GalaxyBoard3D) != (GameSettings.galaxy_view == "3d") or look_changed):
			_build_board()
		_refresh())
	get_viewport().size_changed.connect(_fit_map)
	if auto_start:
		start_campaign()


func start_campaign() -> void:
	var token := _begin(GalaxyEngine.from_campaign(data, _campaign_with_species(), rng_seed))
	if permadeath_override != null:
		engine.state.permadeath = permadeath_override
	_busy = true
	await _play(engine.start(), token)
	if token != _token:
		return
	_fit_map()  # now that the starting area is explored
	if not autoplay and engine.campaign.has("briefing"):
		hud.set_hint("")
		hud.ask(engine.campaign.get("name", campaign_id), engine.campaign["briefing"], [{"id": "begin", "label": "Begin"}],
				Vector2(640, 470))
		await hud.dialog_choice
		if token != _token:
			return
	await _continue(token)


func _campaign_with_species() -> Variant:
	if player_species.is_empty():
		return campaign_id
	return SpeciesNaming.with_player_species(data.campaigns[campaign_id], player_species, data)


## Continues a saved campaign (see GalaxySave). Saves are made between turns,
## so play picks up at the start of the player's turn.
func load_campaign(loaded: GalaxyEngine, p_campaign_id: String, label: String = "") -> void:
	campaign_id = p_campaign_id
	autoplay = false
	var token := _begin(loaded)
	_last_autosave_turn = engine.state.turn_number
	_sync_views()
	_fit_map()
	hud.log_line("\n[b]Turn %d[/b]  %s" % [engine.state.turn_number, UiKit.color_tag("Loaded %s" % label, Palette.TEXT_DIM)])
	await _continue(token)


## Swaps in an engine and resets the screen around it. Returns the new token.
func _begin(new_engine: GalaxyEngine) -> int:
	_token += 1
	selected_fleet = ""
	selected_planet = ""
	selected_anomaly = ""
	_hover = null
	_last_autosave_turn = -1
	hud.roster.visible = false
	hud.empire.visible = false
	hud.diplomacy.visible = false
	_queued_contacts.clear()
	_offers_shown.clear()
	hud.close_dialog()
	ai = GalaxyAI.new()
	engine = new_engine
	player_faction = engine.state.factions[0]["id"]
	for f in engine.state.factions:
		if f["controller"] == "player":
			player_faction = f["id"]
			break
	$Background/Backdrop.configure(engine.campaign.get("backdrop", {}), 5.0)
	_build_board()
	hud.clear_log()
	hud.set_objective(engine.campaign.get("description", ""))
	hud.log_line(UiKit.color_tag("%s  (seed %d)" % [engine.campaign.get("name", campaign_id), engine.state.seed_value], Palette.TEXT_DIM))
	return _token


## (Re)creates the map view for view_mode and brings it up to date.
func _build_board() -> void:
	if board != null:
		board.teardown()
		board.queue_free()
	map_view.visible = false
	GameSettings.ensure_loaded()
	board = GalaxyBoard3D.new() if GameSettings.galaxy_view == "3d" \
			else GalaxyBoard2D.new(map_view, planets_layer, fleets_layer, anomalies_layer, fx)
	add_child(board)
	board.setup(engine, data, player_faction)
	# The 3D map on Forward+ draws its own sky; the 2D nebula backdrop would cover it.
	$Background.visible = not (board is GalaxyBoard3D and BoardGeometry.high_quality())
	hud.minimap.setup(engine, board, player_faction)
	_sync_views()
	_fit_map()


func _switch_view() -> void:
	if _busy:
		hud.set_hint("Switch views between turns")
		return
	GameSettings.galaxy_view = "2d" if GameSettings.galaxy_view == "3d" else "3d"
	GameSettings.save()
	_build_board()
	_refresh()


## Called by the owner when a battle requested via battle_requested is over.
func on_battle_finished(battle: BattleEngine) -> void:
	battle_returned.emit(battle)


# --- Turn driving -------------------------------------------------------------

func _is_human_turn() -> bool:
	return not autoplay and engine.controller_of(engine.current_faction_id()) == "player"


## Runs AI turns and battles until the player has to act or the game ends.
func _continue(token: int) -> void:
	_busy = true
	_refresh()
	while token == _token and not engine.state.is_over:
		if player_faction in engine.state.eliminated and not autoplay:
			_busy = false
			_game_over()
			return
		if engine.has_pending_battle():
			await _resolve_battle(token)
			continue
		if engine.has_pending_mission():
			await _resolve_mission(token)
			continue
		if engine.has_pending_event() and _is_human_turn():
			await _resolve_event(token)
			continue
		if _is_human_turn():
			await _flush_diplomacy(token)
			if token != _token:
				return
			break
		var result := engine.submit(ai.decide(engine))
		if not result.ok:
			result = engine.submit(EndFactionTurnCommand.new(engine.current_faction_id()))
		await _play(result.events, token)
		if is_inside_tree():
			await get_tree().process_frame
	if token != _token:
		return
	_busy = false
	if _is_human_turn() and not engine.state.is_over and engine.state.turn_number != _last_autosave_turn:
		_last_autosave_turn = engine.state.turn_number
		var error := GalaxySave.write(GalaxySave.AUTOSAVE, engine, campaign_id)
		if not error.is_empty():
			hud.log_line(UiKit.color_tag("Autosave failed: " + error, Palette.BAD))
	if _is_human_turn():
		var current: Fleet = engine.state.fleets.get(selected_fleet)
		# Like Civ: once a fleet has used its moves, hand over to the next one that hasn't.
		if current == null or (current.owner == player_faction and current.moves_left <= 0 and _ready_fleet_count() > 0):
			_select_next_fleet()
	_refresh()


func _submit(cmd: GalaxyCommand) -> void:
	if _busy:
		return
	var result := engine.submit(cmd)
	if not result.ok:
		hud.set_hint(result.error)
		return
	var token := _token
	_busy = true
	await _play(result.events, token)
	if token == _token:
		await _continue(token)


func _resolve_battle(token: int) -> void:
	var b := engine.state.pending_battle
	var attacker: Fleet = engine.state.fleets[b["attacker"]]
	var defender: Fleet = engine.state.fleets.get(b.get("defender", ""))
	var defending_faction: String = defender.owner if defender != null else engine.state.planet_at(b["cell"]).owner
	var involves_player := attacker.owner == player_faction or defending_faction == player_faction
	var ask_player := involves_player and not autoplay
	var fight := autoplay and watch_battles and involves_player
	if ask_player:
		var preview := _battle_preview(b, attacker, defender)
		hud.ask("Battle %s" % engine.location_phrase(b["cell"]), preview,
				[{"id": "fight", "label": "Fight"}, {"id": "auto", "label": "Auto-resolve"}])
		_show_odds(engine.pending_battle_scenario(), engine.state.faction(player_faction)["team"], preview)
		var choice: String = await hud.dialog_choice
		if token != _token:
			return
		fight = choice == "fight"

	var events: Array[Dictionary]
	if fight and not battle_requested.get_connections().is_empty():
		battle_requested.emit(engine.pending_battle_scenario(), engine.next_battle_seed())
		var battle: BattleEngine = await battle_returned
		if token != _token:
			return
		events = engine.resolve_pending_battle(battle)
	else:
		events = engine.auto_resolve_pending_battle()
	await _play(events, token)
	if ask_player and token == _token and not engine.state.is_over:
		hud.ask("Battle report", _battle_report(events), [{"id": "ok", "label": "Continue"}])
		await hud.dialog_choice


func _resolve_mission(token: int) -> void:
	var fleet := engine.pending_mission_fleet()
	var mission := engine.pending_mission_def()
	var players := fleet.owner == player_faction
	var ask_player := players and not autoplay
	var choice := "auto"
	if autoplay and watch_battles and players:
		choice = "launch"
	if ask_player:
		var briefing := _mission_briefing(fleet, mission)
		hud.ask(mission.get("name", "Mission"), briefing,
				[{"id": "launch", "label": "Launch mission"}, {"id": "auto", "label": "Auto-resolve"},
				 {"id": "leave", "label": "Not now"}])
		_show_odds(engine.pending_mission_scenario(), engine.state.faction(player_faction)["team"], briefing)
		choice = await hud.dialog_choice
		if token != _token:
			return

	var events: Array[Dictionary]
	if choice == "leave":
		events = engine.decline_pending_mission()
	elif choice == "launch" and not battle_requested.get_connections().is_empty():
		battle_requested.emit(engine.pending_mission_scenario(), engine.next_battle_seed())
		var battle: BattleEngine = await battle_returned
		if token != _token:
			return
		events = engine.resolve_pending_mission(battle)
	else:
		events = engine.auto_resolve_pending_mission()
	await _play(events, token)
	_refresh()
	if ask_player and choice != "leave" and token == _token and not engine.state.is_over:
		hud.ask("Mission report", _mission_report(events), [{"id": "ok", "label": "Continue"}])
		await hud.dialog_choice


## The player's galactic event: a dialog with the choices (costs and effects in
## the hint), then a report of what happened.
func _resolve_event(token: int) -> void:
	var pending := engine.state.pending_event
	var def: Dictionary = data.events[pending["event"]]
	var offered := EventRules.choices(engine, player_faction, pending)
	var lines := PackedStringArray([EventRules.fill(engine, def["text"], pending.get("planet", "")), ""])
	var buttons: Array[Dictionary] = []
	for o in offered:
		var hint: String = o["hint"]
		var line := "[b]%d. %s[/b]" % [int(o["index"]) + 1, o["label"]]
		if not hint.is_empty():
			line += "  " + UiKit.color_tag(hint, Palette.TEXT_DIM)
		if not o["ok"]:
			line += "  " + UiKit.color_tag("(%s)" % o["reason"], Palette.BAD)
		lines.append(line)
		buttons.append({"id": str(o["index"]), "label": "%d. %s" % [int(o["index"]) + 1, o["label"]],
				"disabled": not o["ok"], "tooltip": o["reason"]})
	hud.ask(def["name"], "\n".join(lines), buttons, Vector2(700, 320))
	var choice := int(await hud.dialog_choice)
	if token != _token:
		return
	var result := engine.submit(ResolveEventCommand.new(player_faction, choice))
	if not result.ok:
		hud.set_hint(result.error)
		return
	await _play(result.events, token)
	if token != _token or engine.state.is_over:
		return
	for e in result.events:
		if e["type"] == GalaxyEvents.EVENT_RESOLVED:
			var body := PackedStringArray([e["text"], ""])
			for l: String in e["lines"]:
				body.append(UiKit.color_tag(l, Palette.ACTIVE))
			hud.ask(def["name"], "\n".join(body), [{"id": "ok", "label": "Continue"}], Vector2(560, 320))
			await hud.dialog_choice


## Fills in the open battle/mission dialog with auto-resolve odds as the
## simulations finish (in the background; the player can answer any time).
func _show_odds(scenario: Dictionary, team: int, body: String) -> void:
	# Single-threaded builds run one simulation per frame: keep it short there.
	var runs := 12 if OddsEstimator.threaded() else 6
	var odds := OddsEstimator.new(data, scenario, team, runs, engine.state.turn_number * 131)
	odds.start()
	var shown := -1
	var token := _token
	while is_inside_tree() and token == _token:
		odds.step()
		var dialog_up := hud.is_dialog_open()
		if dialog_up and odds.completed != shown:
			shown = odds.completed
			hud.set_dialog_body(body + "\n\n" + _odds_text(odds))
		if odds.is_done():
			break
		if not dialog_up and not OddsEstimator.threaded():
			break  # answered: no point spending frames on it
		await get_tree().process_frame
	odds.finish()


func _odds_text(odds: OddsEstimator) -> String:
	if not odds.is_done():
		return UiKit.color_tag("Estimating auto-resolve odds... %d/%d" % [odds.completed, odds.runs], Palette.TEXT_DIM)
	var pct := roundi(odds.ratio() * 100.0)
	var color := Palette.GOOD if pct >= 65 else (Palette.BAD if pct < 40 else Palette.ACTIVE)
	return "Auto-resolve: %s %s" % [UiKit.color_tag("about %d%% to win" % pct, color),
			UiKit.color_tag("(%d simulated battles; fighting it yourself can do better)" % odds.runs, Palette.TEXT_DIM)]


## Opens the system view (explored systems only; build only in your own).
func _open_system(planet_id: String) -> void:
	var planet: Planet = engine.state.planets.get(planet_id)
	if planet == null or not engine.explored_cells(player_faction).has(planet.cell):
		return
	hud.roster.visible = false
	hud.empire.visible = false
	hud.system_view.show_system(engine, planet, player_faction, not _busy and _is_human_turn())


func _on_system_command(cmd: GalaxyCommand) -> void:
	if _busy or not _is_human_turn():
		return
	var result := engine.submit(cmd)
	if not result.ok:
		hud.set_hint(result.error)
	else:
		await _play(result.events, _token)
	_refresh_resources()
	var shown := hud.system_view.shown_planet()
	if not shown.is_empty():
		hud.system_view.show_system(engine, engine.state.planets[shown], player_faction, not _busy and _is_human_turn())


func _toggle_tech_tree() -> void:
	if hud.tech_tree.visible:
		hud.tech_tree.visible = false
		_refresh()
		return
	hud.empire.visible = false
	hud.roster.visible = false
	hud.tech_tree.show_tree(engine, player_faction, not _busy and _is_human_turn())


func _on_tech_command(cmd: GalaxyCommand) -> void:
	if _busy or not _is_human_turn():
		return
	var result := engine.submit(cmd)
	if not result.ok:
		hud.set_hint(result.error)
	_refresh_resources()


func _toggle_empire() -> void:
	hud.tech_tree.visible = false
	if hud.empire.visible:
		hud.empire.visible = false
		_refresh()
	else:
		hud.roster.visible = false
		hud.empire.show_panel(engine, player_faction, not _busy and _is_human_turn())


func _on_empire_command(cmd: GalaxyCommand) -> void:
	if _busy or not _is_human_turn():
		return
	var result := engine.submit(cmd)
	if not result.ok:
		hud.set_hint(result.error)
	else:
		await _play(result.events, _token)
		for e in result.events:
			if e["type"] == GalaxyEvents.PEACE_REFUSED:
				hud.set_hint(e["reason"])
	if engine.state.is_over:
		hud.empire.visible = false
		return
	hud.empire.show_panel(engine, player_faction, not _busy and _is_human_turn())
	_refresh_resources()


func _refresh_resources() -> void:
	var f := player_faction
	var stock: Dictionary = engine.state.resources[f]
	var income := EmpireRules.income(engine, f)
	var trade := EmpireRules.trade_income(engine, f)
	var gross := int(income.get("gross_credits", income["credits"]))
	var upkeep := int(income.get("upkeep", 0))
	var credit_tip := "Credits: %d in the treasury.\nPer turn: +%d from systems%s, -%d ship upkeep = %+d." % [
			stock["credits"], gross - trade, (", +%d from trade" % trade) if trade > 0 else "", upkeep, income["credits"]]
	if int(stock["credits"]) < 0:
		credit_tip += "\nIn debt: colonies don't grow, fleets don't repair and ships lose hull each turn."
	hud.set_resource_chip("credits", Color(data.resources["credits"]["color"]), stock["credits"], income["credits"], credit_tip)
	hud.set_resource_chip("alloys", Color(data.resources["alloys"]["color"]), stock["alloys"], income["alloys"],
			"Alloys: %d in store, %+d per turn from mining bases and refineries.\nShips, buildings and wonders need them." % [stock["alloys"], income["alloys"]])
	# Strategic resources: shown once you have some or produce some.
	for k in DepositRules.strategic(data):
		var have := int(stock.get(k, 0))
		var gain := int(income.get(k, 0))
		hud.set_resource_chip(k, DepositRules.color(data, k), have, gain, _strategic_tip(k, have, gain), true,
				have > 0 or gain != 0)
	var r: Dictionary = engine.state.research[f]
	var per_turn := int(income["research"])
	var color := Color(data.resources["research"]["color"])
	var waiting := ""
	if not String(r["current"]).is_empty() and int(r["progress"]) >= ResearchRules.cost(engine, r["current"]):
		waiting = EmpireRules.afford_error(engine, f, ResearchRules.resource_cost(engine, r["current"]))
	if not waiting.is_empty():
		# Short, the bar is crowded: "Hyperdrive 4/16 exotic" (the first resource still missing).
		var needs := ResearchRules.resource_cost(engine, r["current"])
		var short := ""
		for k: String in needs:
			if int(stock.get(k, 0)) < int(needs[k]):
				short = "%d/%d %s" % [int(stock.get(k, 0)), int(needs[k]), DepositRules.resource_name(data, k).split(" ")[0].to_lower()]
				break
		hud.set_research_chip("%s %s" % [data.techs[r["current"]]["name"], short],
				Palette.BAD, "%s is researched, but it completes only with the resources in store: %s. Research points keep banking." % [
				data.techs[r["current"]]["name"], waiting], false)
	elif String(r["current"]).is_empty():
		hud.set_research_chip("Choose research  (+%d)" % per_turn, color,
				"Nothing is being researched: points are banked until you choose (%d banked). Click or press T." % r["progress"], true)
	else:
		var cost := ResearchRules.cost(engine, r["current"])
		var turns := ceili(float(cost - int(r["progress"])) / maxf(1.0, per_turn))
		hud.set_research_chip("%s  %d/%d · %dt" % [data.techs[r["current"]]["name"], r["progress"], cost, turns], color,
				"Researching %s: %d of %d (+%d per turn, %d turn(s) left). Click or press T for the tech tree." % [
				data.techs[r["current"]]["name"], r["progress"], cost, per_turn, turns], false)


## Tooltip for a strategic resource chip: stock and income, the bodies it comes from, where it is
## found, what extracts it and what it is for.
func _strategic_tip(k: String, have: int, gain: int) -> String:
	var res: Dictionary = data.resources[k]
	var lines := PackedStringArray()
	lines.append("%s: %d in store, %+d per turn. %s" % [res["name"], have, gain, res.get("description", "")])
	var sources := PackedStringArray()
	var untapped := 0
	for p: Planet in engine.state.planets.values():
		for b in p.bodies:
			var deposits := engine.known_deposits(player_faction, p, b)
			if not deposits.has(k):
				continue
			if p.owner == player_faction and DepositRules.is_tapped(data, b, k):
				var by: Array = b["buildings"].filter(func(x: String) -> bool: return k in data.buildings[x].get("extracts", []))
				sources.append("%s (%s, %+d)" % [b["name"], data.buildings[by[0]]["name"], int(DepositRules.extraction(data, b)[k])])
			elif p.owner.is_empty() or p.owner == player_faction:
				untapped += 1
	if not sources.is_empty():
		lines.append("From: " + ", ".join(sources))
	if untapped > 0:
		lines.append("%d known deposit%s still untapped." % [untapped, "" if untapped == 1 else "s"])
	lines.append("Found on %s; extracted by %s." % [res.get("found", "some bodies"), res.get("extracted_by", "a development")])
	var uses := DepositRules.uses(engine, k)
	if not uses.is_empty():
		lines.append("Needed for: " + ", ".join(uses) + ".")
	return "\n".join(lines)


func _toggle_roster() -> void:
	hud.empire.visible = false
	if hud.roster.visible:
		hud.roster.visible = false
		_refresh()
	else:
		hud.roster.show_roster(engine, player_faction, not _busy and _is_human_turn())


func _on_roster_command(cmd: GalaxyCommand) -> void:
	if _busy or not _is_human_turn():
		return
	var result := engine.submit(cmd)
	if not result.ok:
		hud.set_hint(result.error)
	else:
		await _play(result.events, _token)
	hud.roster.show_roster(engine, player_faction, not _busy and _is_human_turn())


# --- Event playback -----------------------------------------------------------

func _play(events: Array[Dictionary], token: int) -> void:
	for e in events:
		if token != _token:
			return
		var line := _describe(e)
		if not line.is_empty():
			hud.log_line(line)
		match e["type"]:
			GalaxyEvents.TURN_STARTED:
				_sync_views()
				_refresh()
			GalaxyEvents.FLEET_MOVED:
				await _animate_move(e)
				_sync_views()
			GalaxyEvents.SYSTEM_PLUNDERED:
				board.refresh_planet(e["planet"])
				if _visible.has(engine.state.planets[e["planet"]].cell):
					board.float_text_at_planet(e["planet"], "Plundered!", Palette.BAD)
			GalaxyEvents.COLONY_FOUNDED, GalaxyEvents.JOB_COMPLETED:
				board.refresh_planet(e["planet"])
				if e["faction"] == player_faction and _visible.has(engine.state.planets[e["planet"]].cell):
					board.float_text_at_planet(e["planet"], "Colony founded" if e["type"] == GalaxyEvents.COLONY_FOUNDED \
							else data.buildings[e["building"]]["name"], Palette.GOOD)
			GalaxyEvents.SYSTEM_CLAIMED:
				board.refresh_planet(e["planet"])
				if _visible.has(engine.state.planets[e["planet"]].cell) or e["faction"] == player_faction:
					board.float_text_at_planet(e["planet"], "Claimed", Palette.team_color(engine.state.faction(e["faction"])["team"]))
			GalaxyEvents.BLOCKADE_STARTED, GalaxyEvents.BLOCKADE_LIFTED:
				board.refresh_planet(e["planet"])
				if _visible.has(engine.state.planets[e["planet"]].cell) and e["type"] == GalaxyEvents.BLOCKADE_STARTED:
					board.float_text_at_planet(e["planet"], "Blockaded", Palette.BAD)
			GalaxyEvents.SYSTEM_INVADED:
				board.refresh_planet(e["planet"])
			GalaxyEvents.PLANET_CAPTURED:
				board.refresh_planet(e["planet"])
				if _visible.has(engine.state.planets[e["planet"]].cell) or e["faction"] == player_faction:
					board.float_text_at_planet(e["planet"], "Captured", Palette.team_color(engine.state.faction(e["faction"])["team"]))
			GalaxyEvents.BATTLE_TRIGGERED:
				board.pulse(e["cell"], Palette.BAD)
			GalaxyEvents.FLEET_DESTROYED:
				await board.destroy_fleet(e["fleet"])
			GalaxyEvents.FLEET_REPAIRED:
				if engine.state.fleets[e["fleet"]].owner == player_faction:
					board.float_text_at_fleet(e["fleet"], "+%d hull" % e["amount"], Palette.GOOD)
			GalaxyEvents.HERO_LEVELED:
				var hero: Hero = engine.state.heroes[e["hero"]]
				if hero.owner == player_faction and engine.state.fleets.has(hero.fleet_id):
					board.float_text_at_fleet(hero.fleet_id, "Level up!", Palette.ACTIVE)
			GalaxyEvents.ANOMALY_REMOVED, GalaxyEvents.ANOMALY_CHANGED:
				_sync_views()
			GalaxyEvents.DISCOVERY_FOUND:
				_sync_views()
				if e["faction"] == player_faction:
					board.float_text_at_fleet(e["fleet"], e["name"], Color(data.discoveries.get(e["kind"], {}).get("color", "#ffffff")))
					if not autoplay:
						hud.ask(e["name"], "%s\n\n%s" % [e["text"], _reward_text(e["rewards"])], [{"id": "ok", "label": "Continue"}])
						await hud.dialog_choice
			GalaxyEvents.POP_GREW:
				if engine.state.planets[e["planet"]].owner == player_faction and _visible.has(engine.state.planets[e["planet"]].cell):
					board.float_text_at_planet(e["planet"], "+1 pop", Palette.GOOD)
			GalaxyEvents.MEGAPROJECT_COMPLETED:
				board.refresh_planet(e["planet"])
				board.float_text_at_planet(e["planet"], data.megaprojects[e["megaproject"]]["name"],
						Palette.team_color(engine.state.faction(e["faction"])["team"]))
				if e["faction"] == player_faction and not autoplay \
						and data.megaprojects[e["megaproject"]].get("victory", "") != "science":
					hud.ask("Megaproject complete", "The [b]%s[/b] at %s is finished.\n\n%s" % [
							data.megaprojects[e["megaproject"]]["name"], engine.state.planets[e["planet"]].name,
							data.megaprojects[e["megaproject"]].get("description", "")], [{"id": "ok", "label": "Continue"}])
					await hud.dialog_choice
			GalaxyEvents.FIRST_CONTACT:
				var met := _contact_partner(e["factions"])
				if not met.is_empty() and not autoplay:
					if engine.current_faction_id() == player_faction:
						await _show_diplomacy(met, "first_contact")
					else:
						_queued_contacts.append(met)
			GalaxyEvents.WAR_DECLARED:
				if e["target"] == player_faction and not autoplay and not engine.state.is_over:
					await _show_diplomacy(e["faction"], "war_on_you")
			GalaxyEvents.CAMPAIGN_ENDED:
				_sync_views()
				_game_over()
	_sync_views()


# --- Diplomacy screens ---------------------------------------------------------

## The faction the player met in a FIRST_CONTACT pair, or "" if the player isn't in it.
func _contact_partner(pair: Array) -> String:
	if player_faction not in pair:
		return ""
	return pair[1] if pair[0] == player_faction else pair[0]


## Opens the leader screen and waits until it is closed. Skipped in autoplay.
func _show_diplomacy(other: String, mode: String) -> void:
	if autoplay or engine.state.is_over or hud.diplomacy.visible or not engine.state.faction(other).has("id"):
		return
	var can_act := engine.current_faction_id() == player_faction and engine.state.pending_event.is_empty()
	hud.diplomacy.open(engine, player_faction, other, mode, can_act)
	await hud.diplomacy.closed
	_refresh()


## At the start of the player's turn: first contacts made during AI turns, then any
## peace offers waiting for an answer.
func _flush_diplomacy(token: int) -> void:
	if autoplay:
		_queued_contacts.clear()
		return
	while not _queued_contacts.is_empty() and token == _token:
		var met: String = _queued_contacts.pop_front()
		if not engine.state.is_eliminated(met):
			await _show_diplomacy(met, "first_contact")
	for offer: Dictionary in engine.state.peace_offers.values().duplicate():
		if token != _token or engine.state.is_over:
			return
		var key := "%s>%s@%d" % [offer["from"], offer["to"], int(offer["turn"])]
		if offer["to"] != player_faction or _offers_shown.has(key) \
				or DiplomacyRules.pending_offer(engine.state, offer["from"], player_faction).is_empty():
			continue
		_offers_shown[key] = true
		await _show_diplomacy(offer["from"], "peace_offer")


func _on_contact_requested(other: String) -> void:
	if _busy or engine == null or not _is_human_turn():
		return
	await _show_diplomacy(other, "hail")
	if hud.empire.visible:
		hud.empire.show_panel(engine, player_faction, not _busy and _is_human_turn())


## A button on the leader screen: run the command, then let the leader answer.
func _on_diplomacy_command(cmd: GalaxyCommand) -> void:
	var result := engine.submit(cmd)
	if not result.ok:
		hud.diplomacy.show_result([], result.error)
		return
	var token := _token
	await _play(result.events, token)
	if token != _token:
		return
	hud.diplomacy.show_result(result.events)
	_refresh_resources()


func _animate_move(e: Dictionary) -> void:
	var fleet: Fleet = engine.state.fleets.get(e["fleet"])
	if fleet == null and not board.is_fleet_shown(e["fleet"]):
		return  # gone and never seen (a merged fleet we couldn't see)
	var path: Array = e["path"]
	var seen := fleet == null or fleet.owner == player_faction
	var now_visible := engine.visible_cells(player_faction)
	for c: Vector2i in path:
		if _visible.has(c) or now_visible.has(c):
			seen = true
	if not seen or not is_inside_tree():
		return
	await board.move_fleet(e["fleet"], path)


func _game_over() -> void:
	var s := engine.state
	var title := "Draw"
	var player_out := player_faction in s.eliminated and not s.is_over
	if player_out and not autoplay:
		title = "Defeat"
	elif s.winner == player_faction and not autoplay:
		title = "Victory"
	elif s.winner != "" and not autoplay:
		title = "Defeat"
	elif s.winner != "":
		title = "%s wins" % s.faction(s.winner)["name"]
	var majors_left := s.factions.filter(func(f: Dictionary) -> bool:
		return f.get("role", "major") == "major" and not s.is_eliminated(f["id"])).size()
	var endings := {"science": "by ascension: the Ascension Gate was completed", "score": "by score at the turn limit",
			"objective": "the objective was met", "peace": "by treaty", "max_turns": "at the turn limit",
			"act1": "Act 1 complete: Hyperdrive wakes the jump points, and the galaxy beyond awaits (in a later update)",
			"tech": "by technology"}
	var how: String = "your empire has fallen" if player_out else endings.get(s.victory_reason,
			"by conquest" if majors_left <= 1 else "by treaty")
	var lines := PackedStringArray(["The campaign is over after %d turns (%s)." % [s.turn_number, how], ""])
	for f in s.factions:
		if not s.is_eliminated(f["id"]):
			lines.append("%s: score %d" % [UiKit.color_tag(f["name"], Palette.team_color(f["team"])), EmpireRules.score(engine, f["id"])])
	hud.ask(title, "\n".join(lines), [{"id": "new", "label": "New campaign"}, {"id": "menu", "label": "Main menu"}])
	var token := _token
	var choice: String = await hud.dialog_choice
	if token != _token:
		return
	if choice == "menu" and not main_menu_requested.get_connections().is_empty():
		main_menu_requested.emit()
	else:
		start_campaign()


# --- View sync ----------------------------------------------------------------

## Updates fog, fleet markers and planet owners from engine state.
func _sync_views() -> void:
	_visible = engine.visible_cells(player_faction)
	board.sync(_visible, engine.explored_cells(player_faction), selected_fleet)
	hud.minimap.sync(engine.explored_cells(player_faction), _visible)


## Recomputes highlights, info panel and hints.
func _refresh() -> void:
	_refresh_resources()
	var s := engine.state
	var current := s.current_faction()
	hud.set_turn(s.turn_number, current["name"], Palette.team_color(current["team"]))
	var human := not _busy and _is_human_turn()
	hud.set_end_turn_enabled(human)
	hud.set_ready_fleets(_ready_fleet_count(), human)

	var move_cells: Array[Vector2i] = []
	var path: Array[Vector2i] = []
	_reach = {}
	_attack_cells = []
	var fleet: Fleet = s.fleets.get(selected_fleet)
	var mine := fleet != null and fleet.owner == player_faction
	if not (human and mine):
		_split_ships.clear()
	if human and mine and not _split_ships.is_empty():
		move_cells = engine.split_targets(fleet.id)
	elif human and mine:
		_reach = engine.reachable_for(fleet.id)
		_attack_cells = engine.attack_targets(fleet.id, _reach)
		for c: Vector2i in _reach:
			if c != fleet.cell and c not in _attack_cells:
				move_cells.append(c)
		if _hover != null and _reach.has(_hover) and _hover != fleet.cell:
			path = Pathfinding.path_to(_reach, _hover)

	board.set_highlights(move_cells, _attack_cells, path)
	board.set_active_cell(fleet.cell if fleet != null and board.is_fleet_shown(fleet.id) else null)
	board.set_hover(_hover)
	board.set_selected_fleet(selected_fleet)

	if fleet != null:
		hud.set_info(_fleet_info(fleet))
	elif s.anomalies.has(selected_anomaly):
		hud.set_info(_anomaly_info(s.anomalies[selected_anomaly]))
	elif s.planets.has(selected_planet):
		hud.set_info(_planet_info(s.planets[selected_planet]))
	else:
		hud.set_info(UiKit.color_tag("Select a fleet or planet.", Palette.TEXT_DIM))
	hud.set_hint(_hint_text(human, fleet if mine else null))
	_refresh_attention(human)


## What needs the player this turn, Civ-style: research to choose, systems
## building nothing, heroes waiting for a ride, debt. Each item jumps there.
func _refresh_attention(human: bool) -> void:
	var items: Array[Dictionary] = []
	if not human or engine.state.is_over or hud.empire.visible or hud.roster.visible or hud.tech_tree.visible \
			or hud.system_view.visible:
		hud.set_attention(items)
		return
	var f := player_faction
	if int(engine.state.resources[f]["credits"]) < 0:
		items.append({"text": "In debt: no growth, no repairs, hull loss", "color": Palette.BAD, "action": _toggle_empire})
	if String(engine.state.research[f]["current"]).is_empty():
		items.append({"text": "Choose a research project", "color": Palette.ACTIVE, "action": _toggle_tech_tree})
	# Settlers and workers waiting for orders.
	var founded := EmpireRules.colony_count(engine, f) > 0
	for p: Planet in engine.state.planets.values():
		var pid := p.id
		for entry in SystemRules.ships_here(engine, p, f):
			var ship: Dictionary = entry["ship"]
			if not ship.get("job", {}).is_empty():
				continue
			if entry["role"] == "colony" and not SystemRules.colony_targets(engine, p, f).is_empty():
				items.append({"text": "Found %s with %s" % ["your capital" if not founded else "a colony at " + p.name, ship["name"]],
						"color": Palette.GOOD, "action": func() -> void: _open_system(pid)})
			elif entry["role"] == "constructor" and entry["deployed"] and not SystemRules.development_targets(engine, p, f).is_empty():
				var idle_uid: String = ship["uid"]
				items.append({"text": "%s is idle at %s" % [ship["name"], p.name], "color": Palette.ACTIVE,
						"action": func() -> void: _start_send(idle_uid)})
	# Civilian ships riding in a fleet with nothing to do (system-scale maps: send them somewhere).
	if engine.is_system_scale():
		for fl in engine.state.fleets_of(f):
			if not fl.order.is_empty() or not fl.is_civilian_only(data):
				continue
			for s in fl.ships:
				if Fleet.role_of(data, s["unit"]) in ["colony", "constructor"]:
					var send_uid: String = s["uid"]
					items.append({"text": "%s awaits orders" % s["name"], "color": Palette.GOOD,
							"action": func() -> void: _start_send(send_uid)})
	var idle: Array[Planet] = []
	for p: Planet in engine.state.planets_of(f):
		if not p.queue.is_empty():
			continue
		var can_build := false
		for o: Dictionary in EmpireRules.build_options(engine, p):
			if o.get("ok", false):
				can_build = true
				break
		if can_build:
			idle.append(p)
	for i in mini(idle.size(), 3):
		var pid := idle[i].id
		items.append({"text": "%s is building nothing" % idle[i].name, "color": Palette.SHIELDS,
				"action": func() -> void: _open_system(pid)})
	if idle.size() > 3:
		items.append({"text": "+%d more idle %s" % [idle.size() - 3, "bodies" if engine.is_system_scale() else "systems"],
				"color": Palette.SHIELDS, "action": _toggle_empire})
	for hero: Hero in engine.state.heroes.values():
		if hero.owner == f and hero.status == Hero.READY and hero.fleet_id.is_empty() and not hero.planet_id.is_empty() \
				and engine.state.planets.has(hero.planet_id):
			items.append({"text": "%s is waiting at %s" % [hero.name, engine.state.planets[hero.planet_id].name],
					"color": Palette.GOOD, "action": _toggle_roster})
	hud.set_attention(items)


func _hint_text(human: bool, fleet: Fleet) -> String:
	if engine.state.is_over:
		return "The campaign is over."
	if not human:
		return "Autoplay: the AI plays every faction. Press A to take back control." if autoplay \
				else "%s is moving..." % engine.state.current_faction()["name"]
	var text := ""
	var order_text := _order_hint()
	if not order_text.is_empty():
		text = order_text
	elif fleet == null:
		text = "Click one of your fleets. Tab: next fleet with moves. Space: end turn. V: 2D/3D. 3D: wheel zoom, Q/R rotate, arrows pan."
	elif not _split_ships.is_empty():
		text = "Click a highlighted neighbouring system for the detached ships. Esc or right-click cancels."
	elif _hover != null and _reach.has(_hover) and engine.state.fleet_at(_hover) != null \
			and engine.state.fleet_at(_hover).owner == player_faction and _hover != fleet.cell:
		text = "Join %s (merge fleets, %d moves)" % [engine.state.fleet_at(_hover).name, _reach[_hover]["cost"]]
	elif _hover != null and _hover in _attack_cells:
		var target_fleet := engine.state.fleet_at(_hover)
		var target_system := engine.state.planet_at(_hover)
		if target_fleet != null:
			text = "Attack %s here" % target_fleet.name
		elif target_system != null:
			text = "Assault %s: %d gun(s) defend it, always a battle. %s" % [target_system.name,
					EmpireRules.defense_units(engine, target_system).size(), _assault_outcome_text(fleet, target_system)]
	elif _hover != null and _reach.has(_hover) and _hover != fleet.cell:
		text = "Move here: %d of %d moves" % [_reach[_hover]["cost"], fleet.moves_left]
	elif _hover != null and _hover == fleet.cell and _own_system_under_fleet() != null:
		text = ("Click again (or press S) to open %s" if engine.is_system_scale() else "Click again (or press S) to open the %s system") \
				% _own_system_under_fleet().name
	else:
		text = "%s: blue = move, red = attack. Move onto your own fleet to merge, D to detach ships. Right-click to deselect." % fleet.name
		if _own_system_under_fleet() != null:
			text += " S: open this body." if engine.is_system_scale() else " S: open this system."
	if _hover != null:
		var planet := engine.state.planet_at(_hover)
		if planet != null and engine.is_system_scale():
			var bdef: Dictionary = data.body_types.get(planet.bodies[0]["type"], {}) if not planet.bodies.is_empty() else {}
			text += "   ·   %s, %s%s" % [planet.name, bdef.get("name", "body").to_lower(),
					_deposit_hint(planet) if engine.is_surveyed(player_faction, planet) else " (not surveyed: deposits ?)"]
		elif planet != null:
			text += "   ·   %s system, %d bodies" % [planet.name, planet.bodies.size()]
		var anomaly := engine.state.anomaly_at(_hover)
		if not anomaly.is_empty() and engine.explored_cells(player_faction).has(_hover):
			text += "   ·   %s: end a move here with a commanded fleet to launch a mission" % anomaly["name"]
		var find := engine.state.discovery_at(_hover)
		if not find.is_empty() and engine.explored_cells(player_faction).has(_hover):
			var fdef: Dictionary = data.discoveries.get(find["kind"], {})
			text += "   ·   %s: %s" % [fdef.get("name", ""), fdef.get("description", "")]
		var terrain := engine.state.grid.terrain_def(_hover)
		if not terrain.is_empty() and engine.explored_cells(player_faction).has(_hover):
			text += "   ·   %s: %s" % [terrain.get("name", ""), terrain.get("description", "")]
	return text


## ", volatiles (good), exotic matter (rich)" for a surveyed body's deposits in the hover hint.
func _deposit_hint(planet: Planet) -> String:
	var parts := PackedStringArray()
	for b in planet.bodies:
		var deposits := engine.known_deposits(player_faction, planet, b)
		for k: String in deposits:
			parts.append("%s (%s)" % [DepositRules.resource_name(data, k).to_lower(), DepositRules.richness_word(int(deposits[k]))])
	return (": " + ", ".join(parts)) if not parts.is_empty() else ""


func _select_next_fleet() -> void:
	var own := engine.state.fleets_of(player_faction)
	if own.is_empty():
		selected_fleet = ""
		return
	var start := 0
	for i in own.size():
		if own[i].id == selected_fleet:
			start = i + 1
	for i in own.size():
		var f := own[(start + i) % own.size()]
		if f.moves_left > 0 and f.order.is_empty():
			selected_fleet = f.id
			selected_planet = ""
			selected_anomaly = ""
			board.focus_cell(f.cell)
			return
	selected_fleet = ""


# --- One-click orders for civilian ships (OrderShipCommand) ------------------------

## A ship picked with "Send to..." (or an idle-worker attention item): the next click on a world
## sends it there. "" when not targeting.
var _send_uid := ""


func _start_send(uid: String) -> void:
	_send_uid = uid
	hud.log_line(UiKit.color_tag("Click a world for it to work on (Esc cancels).", Palette.TEXT_DIM))
	_refresh()


## The civilian ship an order would go to now: the one being sent, or the only colony ship /
## constructor in the selected fleet. {} if none.
func _order_ship() -> Dictionary:
	if not _send_uid.is_empty():
		var where := SystemRules.locate_ship(engine, player_faction, _send_uid)
		return where.get("ship", {})
	var fleet: Fleet = engine.state.fleets.get(selected_fleet)
	if fleet == null or fleet.owner != player_faction or not fleet.is_civilian_only(data):
		return {}
	for s in fleet.ships:
		if Fleet.role_of(data, s["unit"]) in ["colony", "constructor"]:
			return s
	return {}


## What clicking `cell` would order: {"ship", "planet", "body", "action", "label"} or {}.
## Only for bodies where the ship can do its job (found a colony / build something).
func _order_at(cell: Variant) -> Dictionary:
	if cell == null or engine == null:
		return {}
	var ship := _order_ship()
	if ship.is_empty():
		return {}
	var planet := engine.state.planet_at(cell)
	if planet == null or planet.bodies.size() != 1 and not engine.is_system_scale():
		return {}
	if planet == null or planet.bodies.is_empty():
		return {}
	var fleet: Fleet = engine.state.fleets.get(selected_fleet)
	# Clicking the selected fleet's own cell keeps its old meaning (open the body).
	if _send_uid.is_empty() and fleet != null and fleet.cell == cell:
		return {}
	var role := Fleet.role_of(data, ship["unit"])
	var b: Dictionary = planet.bodies[0]
	var label := SystemRules.order_label(engine, player_faction, role, planet, b)
	if label.is_empty():
		return {}
	return {"ship": ship["uid"], "planet": planet.id, "body": b["id"], "label": label,
			"action": OrderShipCommand.FOUND if role == "colony" else OrderShipCommand.JOB}


func _order_hint() -> String:
	var ship := _order_ship()
	if ship.is_empty():
		return ""
	var order := _order_at(_hover)
	if not order.is_empty():
		var planet: Planet = engine.state.planets[order["planet"]]
		var turns := _turns_to(planet.cell)
		return "Click: %s at %s (%s)%s" % [order["label"], planet.name,
				"here" if turns == 0 else ("%d turn%s away" % [turns, "" if turns == 1 else "s"]),
				"" if not _send_uid.is_empty() else ". Shift-click just moves."]
	if not _send_uid.is_empty():
		return "Click a world for %s to work on. Esc or right-click cancels." % ship["name"]
	return ""


## Rough travel time for the order ship to `cell` (turns).
func _turns_to(cell: Vector2i) -> int:
	var where := SystemRules.locate_ship(engine, player_faction, _order_ship().get("uid", ""))
	var from: Vector2i = where["fleet"].cell if where.has("fleet") else (where["planet"].cell if where.has("planet") else cell)
	if from == cell:
		return 0
	var field := Pathfinding.distance_field(engine.state.grid, [cell] as Array[Vector2i])
	var speed := 3
	if where.has("fleet"):
		speed = maxi(engine.fleet_speed(where["fleet"]), 1)
	return ceili(float(field.get(from, 99)) / float(speed))


func _ready_fleet_count() -> int:
	var n := 0
	for f in engine.state.fleets_of(player_faction):
		if f.moves_left > 0 and f.order.is_empty():
			n += 1
	return n


## The system under the selected fleet that its owner can open: their own, or an unclaimed one
## (where a Colony Ship or Constructor can start work).
func _own_system_under_fleet() -> Planet:
	var fleet: Fleet = engine.state.fleets.get(selected_fleet)
	if fleet == null or fleet.owner != player_faction:
		return null
	var planet := engine.state.planet_at(fleet.cell)
	return planet if planet != null and planet.owner in [player_faction, ""] else null


## Whether clicking this system opens the system map: it is yours, or you have ships working in it.
func _opens_system(planet: Planet) -> bool:
	if planet.owner == player_faction:
		return true
	for c in planet.civilians:
		if c["owner"] == player_faction:
			return true
	return false


func _fit_map() -> void:
	if engine != null and board != null:
		board.fit(hud.map_area())


# --- Text ---------------------------------------------------------------------

func _fleet_name(fleet: Fleet) -> String:
	return UiKit.color_tag(fleet.name, Palette.team_color(engine.state.faction(fleet.owner)["team"]))


func _fleet_info(fleet: Fleet) -> String:
	var faction := engine.state.faction(fleet.owner)
	var lines := PackedStringArray()
	lines.append("[b]%s[/b]  %s" % [_fleet_name(fleet), UiKit.color_tag(faction["name"], Palette.TEXT_DIM)])
	if fleet.owner == player_faction:
		lines.append("Moves %d / %d   ·   Sensors %d" % [fleet.moves_left, engine.fleet_speed(fleet), engine.fleet_sensor(fleet)])
		if not fleet.order.is_empty() and engine.state.planets.has(fleet.order["planet"]):
			var target: Planet = engine.state.planets[fleet.order["planet"]]
			var what := "found a colony" if fleet.order["action"] == OrderShipCommand.FOUND \
					else "build %s" % data.buildings.get(fleet.order.get("item", ""), {}).get("name", "a development")
			lines.append(UiKit.color_tag("Orders: %s at %s (moves on its own; a manual move cancels)" % [what, target.name], Palette.ACTIVE))
	lines.append("")
	for ship in fleet.ships:
		var def: Dictionary = data.units[ship["unit"]]
		var max_hull := int(def["stats"]["max_hull"])
		var hull_color := Palette.HULL if ship["hull"] > max_hull * 0.5 else Palette.BAD
		# The ship's class (strike / escort / capital): what it counters, see RoleRules.
		var role := RoleRules.hint(data, def)
		lines.append("%s  %s  %s" % [ship["name"], UiKit.color_tag(def.get("name", "") + ("" if role.is_empty() else " (%s)" % role), Palette.TEXT_DIM),
				UiKit.color_tag("%d/%d" % [ship["hull"], max_hull], hull_color)])
	var planet := engine.state.planet_at(fleet.cell)
	if planet != null and planet.owner == fleet.owner:
		lines.append("")
		lines.append(UiKit.color_tag("At %s: repairing %d%% hull per turn" % [planet.name, roundi(GalaxyEngine.REPAIR_RATE * 100)], Palette.GOOD))
	var commander := engine.state.commander_of(fleet)
	lines.append("")
	if commander == null:
		lines.append(UiKit.color_tag("No commander. Assign a hero at a planet (H).", Palette.TEXT_DIM))
	else:
		var cls: Dictionary = data.hero_classes[commander.class_id]
		var doctrine: Dictionary = data.statuses.get(cls.get("command_status", ""), {})
		lines.append("Commander: [b]%s[/b] (%s %d)" % [commander.name, cls.get("name", ""), commander.level])
		if commander.is_ready():
			lines.append(UiKit.color_tag("%s: %s" % [doctrine.get("name", ""), doctrine.get("description", "")], Palette.GOOD))
		else:
			lines.append(UiKit.color_tag("Away (%s) until turn %d: no doctrine bonus" % [commander.status.replace("_", " "), commander.busy_until], Palette.BAD))
	return "\n".join(lines)


func _anomaly_info(a: Dictionary) -> String:
	var mission: Dictionary = data.missions[a["mission"]]
	var needs := "A fleet with a ready commander can launch it." if mission.get("requires_hero", true) \
			else "Any fleet can launch it."
	return "[b]%s[/b]\n%s\n\n%s\nAway team: %d. Heroes are away for %d turns." % [a["name"],
			UiKit.color_tag(mission.get("name", ""), Palette.ACTIVE), mission.get("description", ""), int(mission.get("squad_size", 4)),
			int(mission.get("duration", 2))] + "\n\n" + UiKit.color_tag(needs + " End a move on it.", Palette.TEXT_DIM)


func _mission_briefing(fleet: Fleet, mission: Dictionary) -> String:
	var heroes := engine.mission_heroes(fleet)
	var team := PackedStringArray()
	for h in heroes:
		team.append("%s (%s %d)" % [h.name, data.hero_classes[h.class_id].get("name", ""), h.level])
	var marines := int(mission.get("squad_size", 4)) - heroes.size()
	if marines > 0:
		team.append("%d marine%s" % [marines, "s" if marines > 1 else ""])
	var risk := "Heroes who fall will be [b]killed[/b] (permadeath)." if engine.state.permadeath \
			else "Heroes who fall are injured on success, or captured if the mission fails (a rescue mission follows)."
	var lines := PackedStringArray([mission.get("description", ""), "",
			"[b]Away team:[/b] " + ", ".join(team),
			UiKit.color_tag("Recommended hero level: %d" % int(mission.get("recommended_level", 1)),
				Palette.BAD if not heroes.is_empty() and heroes[0].level < int(mission.get("recommended_level", 1)) else Palette.TEXT_DIM),
			UiKit.color_tag("%s will be away for %d turns: %s loses its doctrine bonus meanwhile." % [
				heroes[0].name if not heroes.is_empty() else "The team", int(mission.get("duration", 2)), fleet.name], Palette.TEXT_DIM),
			UiKit.color_tag(risk, Palette.TEXT_DIM)])
	return "\n".join(lines)


func _mission_report(events: Array[Dictionary]) -> String:
	var lines := PackedStringArray()
	for e in events:
		match e["type"]:
			GalaxyEvents.MISSION_RESOLVED:
				lines.append(UiKit.color_tag("Mission complete", Palette.GOOD) if e["success"] else UiKit.color_tag("Mission failed", Palette.BAD))
				lines.append("")
				for hero_id: String in e["heroes"]:
					lines.append("%s: %s" % [engine.state.heroes[hero_id].name, e["heroes"][hero_id]])
				if e["xp"] > 0:
					lines.append("+%d XP" % e["xp"])
				if e["loyalty"] != 0:
					lines.append("Loyalty %+d" % e["loyalty"])
				if not e.get("loot_text", "").is_empty():
					lines.append(UiKit.color_tag(e["loot_text"], Palette.TEXT_DIM))
				for k in ["credits", "alloys"]:
					if e.get(k, 0) != 0:
						lines.append(UiKit.color_tag("+%d %s" % [e[k], k], Color(data.resources[k]["color"])))
				if e.get("research", 0) != 0:
					lines.append(UiKit.color_tag("+%d research progress" % e["research"], Color(data.resources["research"]["color"])))
				if not e.get("intel", []).is_empty():
					lines.append("Intel: star charts around %s" % ", ".join(e["intel"]))
				for item_id: String in e["items"]:
					lines.append("Recovered: [b]%s[/b] (equip it in the Heroes panel)" % data.items[item_id]["name"])
				for t: String in e["traits"]:
					lines.append("New trait: %s (%s)" % [data.traits[t]["name"], data.traits[t]["description"]])
			GalaxyEvents.HERO_LEVELED:
				var skills := PackedStringArray()
				for ability_id: String in e["skills"]:
					skills.append(data.abilities[ability_id]["name"])
				lines.append(UiKit.color_tag("%s reached level %d%s" % [engine.state.heroes[e["hero"]].name, e["level"],
						(": learned " + ", ".join(skills)) if not skills.is_empty() else ""], Palette.ACTIVE))
			GalaxyEvents.ANOMALY_CHANGED:
				lines.append(UiKit.color_tag("New mission: %s" % e["name"], Palette.BAD))
			GalaxyEvents.HERO_FREED:
				lines.append(UiKit.color_tag("%s has been rescued" % engine.state.heroes[e["hero"]].name, Palette.GOOD))
	return "\n".join(lines)


## "+45 alloys, Interceptor joins the fleet, map revealed (radius 4)".
func _reward_text(r: Dictionary) -> String:
	var parts := PackedStringArray()
	for k in DepositRules.stockpiled(data):
		if r.has(k):
			parts.append(UiKit.color_tag("+%d %s" % [r[k], DepositRules.resource_name(data, k).to_lower()], Color(data.resources[k]["color"])))
	if r.has("research"):
		parts.append(UiKit.color_tag("+%d research progress" % r["research"], Color(data.resources["research"]["color"])))
	if r.has("ship"):
		parts.append("a %s joins the fleet" % data.units[r["ship"]].get("name", r["ship"]))
	if r.has("item"):
		parts.append("found: [b]%s[/b] (equip it in the Heroes panel)" % data.items[r["item"]]["name"])
	if r.has("intel"):
		parts.append("star charts for the surrounding systems")
	if r.has("xp"):
		parts.append("+%d XP for the commander" % r["xp"])
	if r.has("damage"):
		parts.append(UiKit.color_tag("every ship loses %d%% hull" % roundi(float(r["damage"]) * 100.0), Palette.BAD))
	return ", ".join(parts) if not parts.is_empty() else "Nothing of use."


func _planet_info(planet: Planet) -> String:
	var owner := "Unclaimed"
	var color := Palette.NEUTRAL
	if not planet.owner.is_empty():
		var f := engine.state.faction(planet.owner)
		owner = f["name"]
		color = Palette.team_color(f["team"])
	var star: Dictionary = data.star_types.get(planet.star, {})
	var text := "[b]%s[/b]  %s\n%s%s\n\nYields %s per turn\n" % [
			planet.name, UiKit.color_tag(star.get("name", ""), Color(star.get("color", "#ffffff"))),
			UiKit.color_tag(owner, color), ("\n" + planet.description) if not planet.description.is_empty() else "",
			EmpirePanel._resource_text(engine, EmpireRules.planet_yields(engine, planet), true)]
	for b in planet.bodies:
		var bdef: Dictionary = data.body_types.get(b["type"], {})
		var line := "%s %s" % [UiKit.color_tag("●", Color(bdef.get("surface", {}).get("accent", "#aaaaaa"))), bdef.get("name", b["type"])]
		if "colony" in b["buildings"]:
			line += " (pop %d/%d)" % [EmpireRules.pop(b), EmpireRules.pop_cap(engine, b, planet.owner)]
		if not b["buildings"].is_empty():
			line += ": " + ", ".join(b["buildings"].map(func(x: String) -> String: return data.buildings[x]["name"]))
		var known := engine.known_traits(player_faction, planet, b)
		if not known.is_empty():
			line += "  " + UiKit.color_tag(", ".join(known.map(func(t: String) -> String: return data.planet_traits[t]["name"])), Palette.ACTIVE)
		elif not engine.is_surveyed(player_faction, planet):
			line += "  " + UiKit.color_tag("not surveyed: fly a ship next to it (deposits ?)", Palette.TEXT_DIM)
		var deposits := engine.known_deposits(player_faction, planet, b)
		for k: String in deposits:
			line += "  " + SystemView.deposit_tag(data, k, int(deposits[k])) \
					+ (UiKit.color_tag(" tapped", Palette.GOOD) if DepositRules.is_tapped(data, b, k) and planet.owner == player_faction else "")
		text += "\n" + line
	for mp_id in planet.megaprojects:
		text += "\n" + UiKit.color_tag("Wonder: %s" % data.megaprojects[mp_id]["name"], Palette.ACTIVE)
	text += "\n" + UiKit.color_tag("Click your %s or press S to open it." % ("body" if engine.is_system_scale() else "system"), Palette.TEXT_DIM)
	var defenses := EmpireRules.defense_units(engine, planet).size()
	if defenses > 0:
		text += "\n" + UiKit.color_tag("Defended by %d gun(s): attackers always have to fight them." % defenses, Palette.BAD)
	if planet.is_blockaded():
		text += "\n" + UiKit.color_tag("BLOCKADED by %s: no production, no growth." % engine.state.faction(planet.blockade)["name"], Palette.BAD)
	var mine_here := planet.civilians.filter(func(c: Dictionary) -> bool: return c["owner"] == player_faction)
	if not mine_here.is_empty():
		text += "\n" + UiKit.color_tag("Your ships here: %s (open the system with S)" % ", ".join(mine_here.map(func(c: Dictionary) -> String: return c["name"])), Palette.GOOD)
	if planet.owner.is_empty():
		text += "\n" + UiKit.color_tag("Unclaimed: a Colony Ship (on a habitable world) or a Constructor (an outpost) claims it. Flying in doesn't.", Palette.TEXT_DIM)
	if planet.owner == player_faction:
		if planet.queue.is_empty():
			text += "\n" + UiKit.color_tag("Idle: open the system (S) to build.", Palette.TEXT_DIM)
		else:
			var q := planet.queue
			var item := SystemView._queue_name(data, planet)
			text += "\n" + UiKit.color_tag("Building %s (%d/%d turns)" % [item, q["progress"], q["turns"]], Palette.ACTIVE)
	elif not planet.owner.is_empty() and not engine.state.at_war(player_faction, planet.owner):
		text += "\n" + UiKit.color_tag("At peace with you: can't be captured.", Palette.TEXT_DIM)
	var waiting := PackedStringArray()
	for h in engine.state.heroes_of(player_faction):
		if h.planet_id == planet.id and h.fleet_id.is_empty() and h.status != Hero.CAPTURED and h.status != Hero.DEAD:
			waiting.append(h.name)
	if not waiting.is_empty():
		text += "\n\nHeroes here: %s\n%s" % [", ".join(waiting),
				UiKit.color_tag("Bring a fleet here and assign them in the Heroes panel (H).", Palette.TEXT_DIM)]
	return text


func _battle_preview(b: Dictionary, attacker: Fleet, defender: Fleet) -> String:
	var lines := PackedStringArray()
	var planet := engine.state.planet_at(b["cell"])
	if defender == null:
		lines.append("[b]%s[/b] attacks the defenses of [b]%s[/b] (%d gun%s)." % [_fleet_name(attacker), planet.name,
				EmpireRules.defense_units(engine, planet).size(), "" if EmpireRules.defense_units(engine, planet).size() == 1 else "s"])
		lines.append(UiKit.color_tag(_assault_outcome_text(attacker, planet), Palette.TEXT_DIM))
		return "\n".join(lines)
	if planet != null and planet.owner == defender.owner and not EmpireRules.defense_units(engine, planet).is_empty():
		lines.append(UiKit.color_tag("%s's defense platforms join the fight." % planet.name, Palette.BAD))
	for fleet in [attacker, defender]:
		var cmdr := engine.state.active_commander(fleet)
		if cmdr != null:
			lines.append(UiKit.color_tag("%s commands %s: %s" % [cmdr.name, (fleet as Fleet).name,
					data.statuses[HeroBuilder.command_status(cmdr, data)].get("description", "")], Palette.TEXT_DIM))
	if b.get("ambush", false) or attacker.owner != player_faction and defender.owner == player_faction:
		lines.append(UiKit.color_tag("Enemy contact!", Palette.BAD))
	for fleet in [attacker, defender]:
		var ships := PackedStringArray()
		for ship in (fleet as Fleet).ships:
			ships.append("%s (%d hull)" % [ship["name"], ship["hull"]])
		lines.append("[b]%s[/b]: %s" % [_fleet_name(fleet), ", ".join(ships)])
	var map_name: String = BattleEngine.map_def_for(data, engine.pending_battle_scenario()).get("name", "")
	lines.append("")
	lines.append(UiKit.color_tag("Battlefield: %s. Damage to hulls carries over after the battle." % map_name, Palette.TEXT_DIM))
	return "\n".join(lines)


## What winning an assault on a system gets the attacker.
func _assault_outcome_text(fleet: Fleet, planet: Planet) -> String:
	if planet.colonies().is_empty() or engine.state.faction(planet.owner).get("role", "") == "barbarian":
		return "Win and the fleet takes the system."
	if fleet.has_role(data, "transport"):
		return "Win and the Troop Transport lands: the system changes hands."
	return "Win and the fleet blockades the system (no production or growth while it stays). Taking a colony needs a Troop Transport in the fleet."


func _battle_report(events: Array[Dictionary]) -> String:
	for e in events:
		if e["type"] != GalaxyEvents.BATTLE_RESOLVED:
			continue
		var winner: String = e["winner"]
		var headline := "Draw: both fleets withdraw"
		if winner == player_faction:
			headline = UiKit.color_tag("Victory", Palette.GOOD)
		elif winner != "":
			headline = UiKit.color_tag("Defeat", Palette.BAD)
		var lines := PackedStringArray([headline, ""])
		for side: Array in [[e["attacker"], e["attacker_name"]], [e["defender"], e["defender_name"]]]:
			var lost: Array = e["losses"].get(side[0], [])
			lines.append("%s lost %s" % [side[1], ", ".join(lost) if not lost.is_empty() else "nothing"])
		if e.get("platforms_lost", 0) > 0:
			lines.append("%d defense platform(s) destroyed" % e["platforms_lost"])
		for ev in events:
			match ev["type"]:
				GalaxyEvents.PLANET_CAPTURED:
					lines.append(UiKit.color_tag("%s now belongs to %s" % [engine.state.planets[ev["planet"]].name,
							engine.state.faction(ev["faction"])["name"]], Palette.GOOD if ev["faction"] == player_faction else Palette.BAD))
				GalaxyEvents.BLOCKADE_STARTED:
					lines.append(UiKit.color_tag("%s is blockaded: no production or growth while the fleet stays. Bring a Troop Transport to take it." % engine.state.planets[ev["planet"]].name, Palette.ACTIVE))
		return "\n".join(lines)
	return ""


func _describe(e: Dictionary) -> String:
	var s := engine.state
	match e["type"]:
		GalaxyEvents.TURN_STARTED:
			var f := s.faction(e["faction"])
			return "\n[b]Turn %d[/b]  %s" % [e["turn"], UiKit.color_tag(f["name"], Palette.team_color(f["team"]))]
		GalaxyEvents.ORDER_SET:
			if not s.fleets.has(e["fleet"]) or s.fleets[e["fleet"]].owner != player_faction:
				return ""
			return "%s sets course for %s" % [s.fleets[e["fleet"]].name, s.planets[e["planet"]].name]
		GalaxyEvents.ORDER_FAILED:
			if not s.fleets.has(e["fleet"]) or s.fleets[e["fleet"]].owner != player_faction:
				return ""
			return UiKit.color_tag("%s: orders for %s dropped (%s)" % [s.fleets[e["fleet"]].name,
					s.planets[e["planet"]].name if s.planets.has(e["planet"]) else "?", e["reason"]], Palette.BAD)
		GalaxyEvents.PLANET_CAPTURED:
			var f := s.faction(e["faction"])
			return "%s captures %s" % [UiKit.color_tag(f["name"], Palette.team_color(f["team"])), s.planets[e["planet"]].name]
		GalaxyEvents.COLONY_FOUNDED:
			if s.planets[e["planet"]].owner != player_faction:
				return ""
			var body_name: String = s.planets[e["planet"]].body(e["body"]).get("name", "")
			return UiKit.color_tag("   %s founded on %s (%s)" % ["Capital" if e["capital"] else "Colony", body_name, s.planets[e["planet"]].name], Palette.GOOD)
		GalaxyEvents.BODY_SURVEYED:
			if e["faction"] != player_faction:
				return ""
			var found := PackedStringArray()
			for t: String in e.get("traits", []):
				found.append(data.planet_traits.get(t, {}).get("name", t))
			for b in s.planets[e["planet"]].bodies:
				for k: String in DepositRules.of(b):
					found.append("%s (%s)" % [DepositRules.resource_name(data, k), DepositRules.richness_word(int(DepositRules.of(b)[k]))])
			return UiKit.color_tag("   Surveyed %s: %s" % [s.planets[e["planet"]].name,
					", ".join(found) if not found.is_empty() else "nothing special"], Palette.SHIELDS if found.is_empty() else Palette.ACTIVE)
		GalaxyEvents.SYSTEM_CLAIMED:
			if e["faction"] != player_faction:
				return ""
			return UiKit.color_tag("   %s is yours (%s)" % [s.planets[e["planet"]].name, "outpost" if e["how"] == "outpost" else "colony"], Palette.GOOD)
		GalaxyEvents.JOB_COMPLETED:
			if e["faction"] != player_faction:
				return ""
			return "   %s finished at %s" % [data.buildings[e["building"]]["name"], s.planets[e["planet"]].name]
		GalaxyEvents.JOB_CANCELLED:
			if s.planets[e["planet"]].owner != player_faction and s.planets[e["planet"]].owner != "":
				return ""
			return UiKit.color_tag("   %s job dropped (%s)" % [data.buildings[e["building"]]["name"], e["reason"]], Palette.TEXT_DIM)
		GalaxyEvents.CIVILIANS_LOST:
			if e["faction"] != player_faction:
				return ""
			return UiKit.color_tag("   Lost with %s: %s" % [s.planets[e["planet"]].name, ", ".join(e["ships"])], Palette.BAD)
		GalaxyEvents.BLOCKADE_STARTED:
			var p: Planet = s.planets[e["planet"]]
			if e["faction"] != player_faction and p.owner != player_faction:
				return ""
			return UiKit.color_tag("   %s is blockaded by %s: no production, no growth%s" % [p.name, s.faction(e["faction"])["name"],
					"" if e["faction"] != player_faction else ". Bring a Troop Transport to take it"], Palette.BAD if p.owner == player_faction else Palette.ACTIVE)
		GalaxyEvents.BLOCKADE_LIFTED:
			var p: Planet = s.planets[e["planet"]]
			if e["faction"] != player_faction and p.owner != player_faction:
				return ""
			return UiKit.color_tag("   The blockade of %s is lifted" % p.name, Palette.GOOD)
		GalaxyEvents.SYSTEM_INVADED:
			var p: Planet = s.planets[e["planet"]]
			if e["faction"] != player_faction and e["previous_owner"] != player_faction:
				return ""
			return UiKit.color_tag("   Troops land on %s" % p.name, Palette.ACTIVE)
		GalaxyEvents.BATTLE_TRIGGERED:
			var a: Fleet = s.fleets[e["attacker"]]
			var d: Fleet = s.fleets.get(e["defender"])
			if d == null:
				var target: Planet = s.planets[e["planet"]]
				if a.owner != player_faction and target.owner != player_faction:
					return ""
				return "%s assaults the defenses of %s" % [_fleet_name(a), target.name]
			if a.owner != player_faction and d.owner != player_faction:
				return ""
			if e["ambush"]:
				return "%s is ambushed by %s %s" % [_fleet_name(a), _fleet_name(d), engine.location_phrase(e["cell"])]
			return "%s engages %s %s" % [_fleet_name(a), _fleet_name(d), engine.location_phrase(e["cell"])]
		GalaxyEvents.BATTLE_RESOLVED:
			var winner: String = e["winner"]
			return "   Battle won by %s (%d rounds)" % [s.faction(winner).get("name", "nobody"), e["rounds"]]
		GalaxyEvents.FLEET_DESTROYED:
			if not e.get("by", "").is_empty():
				return UiKit.color_tag("   %s caught and destroyed without a fight" % e["name"], Palette.BAD)
			return UiKit.color_tag("   %s destroyed" % e["name"], Palette.BAD)
		GalaxyEvents.SYSTEM_PLUNDERED:
			if e["previous_owner"] != player_faction:
				return ""
			var losses := PackedStringArray()
			if int(e["credits"]) > 0:
				losses.append("%d credits stolen" % e["credits"])
			if not e["building"].is_empty():
				losses.append("%s wrecked" % data.buildings[e["building"]]["name"])
			if e.get("razed", true):
				losses.append("the system is lost")
			return UiKit.color_tag("   Raiders plundered %s: %s" % [s.planets[e["planet"]].name, ", ".join(losses)], Palette.BAD)
		GalaxyEvents.DEN_CLEARED:
			if e["faction"] != player_faction:
				return ""
			return UiKit.color_tag("   Raider den cleared: ", Palette.GOOD) + _reward_text(e["loot"]) + UiKit.color_tag(" in loot", Palette.GOOD)
		GalaxyEvents.DISCOVERY_FOUND:
			if e["faction"] != player_faction:
				return ""
			return UiKit.color_tag("   %s: %s" % [e["name"], _reward_text(e["rewards"])], Palette.ACTIVE)
		GalaxyEvents.FLEETS_MERGED:
			if s.fleets.has(e["into"]) and s.fleets[e["into"]].owner == player_faction:
				return "   %s joins %s" % [e["name"], e["into_name"]]
			return ""
		GalaxyEvents.FLEET_SPLIT:
			if s.fleets.has(e["fleet"]) and s.fleets[e["fleet"]].owner == player_faction:
				return "   %s detached from %s" % [", ".join(e["ships"]), s.fleets[e["fleet"]].name]
			return ""
		GalaxyEvents.FACTION_ELIMINATED:
			return "[b]%s eliminated[/b]" % s.faction(e["faction"])["name"]
		GalaxyEvents.CAMPAIGN_ENDED:
			return "\n[b]Campaign over[/b]"
		GalaxyEvents.MISSION_RESOLVED:
			if s.fleets.has(e["fleet"]) and s.fleets[e["fleet"]].owner != player_faction:
				return ""
			return "[b]%s[/b]: %s" % [data.missions[e["mission"]]["name"], "success" if e["success"] else "failed"]
		GalaxyEvents.HERO_LEVELED, GalaxyEvents.HERO_RETURNED, GalaxyEvents.HERO_INJURED, \
				GalaxyEvents.HERO_CAPTURED, GalaxyEvents.HERO_KILLED, GalaxyEvents.HERO_FREED:
			var hero: Hero = s.heroes[e["hero"]]
			if hero.owner != player_faction:
				return ""
			var what := {
				GalaxyEvents.HERO_LEVELED: "reaches level %d" % e.get("level", 0),
				GalaxyEvents.HERO_RETURNED: "is back on duty",
				GalaxyEvents.HERO_INJURED: "is injured until turn %d" % e.get("until", 0),
				GalaxyEvents.HERO_CAPTURED: "has been captured",
				GalaxyEvents.HERO_KILLED: "has been killed",
				GalaxyEvents.HERO_FREED: "has been rescued",
			}
			return UiKit.color_tag("   %s %s" % [hero.name, what[e["type"]]], Palette.ACTIVE)
		GalaxyEvents.ANOMALY_CHANGED:
			return UiKit.color_tag("New mission available: %s" % e["name"], Palette.BAD)
		GalaxyEvents.TECH_RESEARCHED:
			if e["faction"] != player_faction:
				return ""
			return UiKit.color_tag("Research complete: %s" % data.techs[e["tech"]]["name"], Color(data.resources["research"]["color"]))
		GalaxyEvents.RESEARCH_WAITING:
			if e["faction"] != player_faction:
				return ""
			return UiKit.color_tag("%s is researched but can't complete: %s. Extract more (points keep banking)." % [
					data.techs[e["tech"]]["name"], e["reason"].to_lower()], Palette.BAD)
		GalaxyEvents.BUILDING_COMPLETED:
			if s.planets[e["planet"]].owner != player_faction:
				return ""
			return "   %s completed at %s" % [data.buildings[e["building"]]["name"], s.planets[e["planet"]].name]
		GalaxyEvents.SHIP_COMPLETED:
			if s.planets[e["planet"]].owner != player_faction:
				return ""
			if e.get("deployed", false):
				return "   New %s ready at %s" % [data.units[e["unit"]]["name"], s.planets[e["planet"]].name]
			return "   New %s launched at %s" % [data.units[e["unit"]]["name"], s.planets[e["planet"]].name]
		GalaxyEvents.MEGAPROJECT_STARTED:
			var mp: Dictionary = data.megaprojects[e["megaproject"]]
			var builder := s.faction(e["faction"])
			if e["faction"] != player_faction and mp.get("victory", "") != "science" and mp.get("scope", "empire") != "galaxy":
				return ""
			return UiKit.color_tag("%s begins the %s at %s" % [builder["name"], mp["name"], s.planets[e["planet"]].name],
					Palette.BAD if e["faction"] != player_faction else Palette.ACTIVE)
		GalaxyEvents.MEGAPROJECT_COMPLETED:
			var mp: Dictionary = data.megaprojects[e["megaproject"]]
			return UiKit.color_tag("[b]%s completes the %s at %s[/b]" % [s.faction(e["faction"])["name"], mp["name"],
					s.planets[e["planet"]].name], Palette.ACTIVE)
		GalaxyEvents.BUDGET_CRISIS:
			if e["faction"] != player_faction:
				return ""
			return UiKit.color_tag("Budget crisis: upkeep has emptied the treasury (%d credits). Colonies stop growing, fleets stop repairing and ships lose hull until you are in the black again." % e["credits"], Palette.BAD)
		GalaxyEvents.EVENT_RESOLVED:
			if e["faction"] != player_faction:
				return ""
			return "   %s: %s" % [data.events[e["event"]]["name"], ", ".join(e["lines"]) if not e["lines"].is_empty() else e["label"]]
		GalaxyEvents.MODIFIER_EXPIRED:
			if e["faction"] != player_faction:
				return ""
			return UiKit.color_tag("   %s has worn off" % e["name"], Palette.TEXT_DIM)
		GalaxyEvents.WAR_DECLARED:
			return UiKit.color_tag("[b]%s declares war on %s[/b]" % [s.faction(e["faction"])["name"], s.faction(e["target"])["name"]], Palette.BAD)
		GalaxyEvents.PEACE_SIGNED:
			return UiKit.color_tag("[b]Peace: %s and %s[/b]" % [s.faction(e["factions"][0])["name"], s.faction(e["factions"][1])["name"]], Palette.GOOD)
		GalaxyEvents.PEACE_REFUSED:
			return UiKit.color_tag(e["reason"], Palette.TEXT_DIM) if e["faction"] == player_faction else ""
		GalaxyEvents.FIRST_CONTACT:
			if player_faction not in e["factions"]:
				return ""
			var other := _contact_partner(e["factions"])
			return UiKit.color_tag("[b]First contact: %s[/b]" % s.faction(other)["name"], Palette.ACTIVE)
		GalaxyEvents.PEACE_OFFERED:
			if e["target"] != player_faction:
				return ""
			return UiKit.color_tag("[b]%s offers you peace[/b]" % s.faction(e["faction"])["name"], Palette.GOOD)
		GalaxyEvents.PEACE_OFFER_REFUSED:
			if e["faction"] != player_faction:
				return ""
			return UiKit.color_tag("You refuse peace with %s" % s.faction(e["target"])["name"], Palette.TEXT_DIM)
		GalaxyEvents.GIFT_SENT:
			if e["faction"] != player_faction and e["target"] != player_faction:
				return ""
			return "   %s sends %s a gift of %d credits" % [s.faction(e["faction"])["name"], s.faction(e["target"])["name"], e["credits"]]
	return ""


# --- Input --------------------------------------------------------------------

func _unhandled_input(event: InputEvent) -> void:
	if engine == null or hud.is_dialog_open() or hud.is_settings_open() or hud.is_diplomacy_open():
		return
	if event is InputEventKey and event.pressed and not event.echo:
		match event.keycode:
			KEY_F5:
				_quick_save()
				return
			KEY_F9:
				_request_load(GalaxySave.QUICKSAVE)
				return
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_H:
		_toggle_roster()
		return
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_E:
		_toggle_empire()
		return
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_T:
		_toggle_tech_tree()
		return
	if hud.tech_tree.visible:
		if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_ESCAPE:
			_toggle_tech_tree()
		return
	if hud.system_view.visible:
		if event is InputEventKey and event.pressed and not event.echo and event.keycode in [KEY_ESCAPE, KEY_S]:
			hud.system_view.close()
		return
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_S:
		if not selected_planet.is_empty():
			_open_system(selected_planet)
			return
		var under := _own_system_under_fleet()
		if under != null:
			_open_system(under.id)
			return
	if hud.roster.visible or hud.empire.visible:
		return
	if board.handle_input(event):
		_update_hover()
		return
	if event is InputEventMouseMotion:
		_update_hover()
	elif event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_LEFT:
			_on_left_click()
		elif event.button_index == MOUSE_BUTTON_RIGHT:
			_deselect()
	elif event is InputEventKey and event.pressed and not event.echo:
		match event.keycode:
			KEY_ESCAPE:
				if _send_uid.is_empty() and _split_ships.is_empty() and selected_fleet.is_empty() and selected_planet.is_empty() and selected_anomaly.is_empty():
					_open_menu()
				else:
					_deselect()
			KEY_SPACE, KEY_ENTER, KEY_KP_ENTER:
				_on_end_turn_pressed()
			KEY_TAB:
				_select_next_fleet()
				_refresh()
			KEY_A:
				_toggle_autoplay()
			KEY_D:
				_start_split()
			KEY_V:
				_switch_view()


func _update_hover() -> void:
	var cell: Variant = board.cell_at_mouse()
	if cell != _hover:
		_hover = cell
		_refresh()


func _on_left_click() -> void:
	if _hover == null:
		return
	var cell: Vector2i = _hover
	var fleet: Fleet = engine.state.fleets.get(selected_fleet)
	if not _busy and _is_human_turn():
		var order := _order_at(cell) if not Input.is_key_pressed(KEY_SHIFT) or not _send_uid.is_empty() else {}
		if not order.is_empty():
			_send_uid = ""
			_submit(OrderShipCommand.new(player_faction, order["ship"], order["planet"], order["body"], order["action"]))
			return
		if not _send_uid.is_empty():
			_send_uid = ""  # clicked somewhere no order fits: drop the targeting
	if not _busy and _is_human_turn() and fleet != null and fleet.owner == player_faction:
		if not _split_ships.is_empty():
			if cell in engine.split_targets(fleet.id):
				var ships := _split_ships.duplicate()
				_split_ships.clear()
				_submit(SplitFleetCommand.new(player_faction, fleet.id, ships, cell))
			return
		var own := engine.state.fleet_at(cell)
		if own != null and own != fleet and own.owner == player_faction and _reach.has(cell):
			_ask_merge(fleet, own)
			return
		if cell in _attack_cells or (_reach.has(cell) and cell != fleet.cell):
			_submit(MoveFleetCommand.new(player_faction, fleet.id, cell))
			return
		# Clicking the selected fleet again opens the system it's parked in.
		var under := _own_system_under_fleet()
		if cell == fleet.cell and under != null:
			_open_system(under.id)
			return
	var other := engine.state.fleet_at(cell)
	var anomaly := engine.state.anomaly_at(cell)
	selected_anomaly = ""
	if other != null and engine.can_see_fleet(player_faction, other, _visible):
		selected_fleet = other.id
		selected_planet = ""
	elif engine.state.planet_at(cell) != null:
		selected_planet = engine.state.planet_at(cell).id
		selected_fleet = ""
		# Like a city screen: clicking your own system opens it.
		if _opens_system(engine.state.planet_at(cell)):
			_refresh()
			_open_system(selected_planet)
			return
	elif not anomaly.is_empty() and engine.explored_cells(player_faction).has(cell):
		selected_anomaly = anomaly["id"]
		selected_fleet = ""
		selected_planet = ""
	else:
		_deselect()
		return
	_refresh()


## Clicking another of your fleets that this one can reach: merge or just select?
func _ask_merge(fleet: Fleet, other: Fleet) -> void:
	hud.ask("Merge fleets?", "Move [b]%s[/b] (%d ships) into [b]%s[/b] (%d ships)? The merged fleet keeps the lower moves left." % [
			fleet.name, fleet.ships.size(), other.name, other.ships.size()],
			[{"id": "merge", "label": "Merge"}, {"id": "select", "label": "Select %s" % other.name}, {"id": "cancel", "label": "Cancel"}])
	var token := _token
	var choice: String = await hud.dialog_choice
	if token != _token:
		return
	match choice:
		"merge":
			_submit(MoveFleetCommand.new(player_faction, fleet.id, other.cell))
		"select":
			selected_fleet = other.id
			_refresh()
		_:
			_refresh()


## D: pick ships to detach into a new fleet next to this one.
func _start_split() -> void:
	var fleet: Fleet = engine.state.fleets.get(selected_fleet)
	if _busy or not _is_human_turn() or fleet == null or fleet.owner != player_faction:
		return
	if fleet.ships.size() < 2:
		hud.set_hint("A one-ship fleet can't be split")
		return
	if engine.split_targets(fleet.id).is_empty():
		hud.set_hint("No free neighbouring system to detach into (or no moves left)")
		return
	var choices: Array[Dictionary] = []
	var lines := PackedStringArray()
	for ship in fleet.ships:
		var def: Dictionary = data.units[ship["unit"]]
		choices.append({"id": ship["uid"], "label": ship["name"]})
		lines.append("%s  %s  %d/%d hull" % [ship["name"], UiKit.color_tag(def.get("name", ""), Palette.TEXT_DIM),
				ship["hull"], int(def["stats"]["max_hull"])])
	if fleet.ships.size() > 2:
		choices.append({"id": "half", "label": "Half the fleet"})
	choices.append({"id": "cancel", "label": "Cancel"})
	hud.ask("Detach ships from %s" % fleet.name, "\n".join(lines) + "\n\n" + UiKit.color_tag(
			"Pick a ship (or half the fleet), then a neighbouring system for it. The commander stays.", Palette.TEXT_DIM),
			choices, Vector2(620, 340))
	var token := _token
	var choice: String = await hud.dialog_choice
	if token != _token or choice == "cancel":
		_refresh()
		return
	_split_ships.clear()
	if choice == "half":
		for i in range(fleet.ships.size() / 2, fleet.ships.size()):
			_split_ships.append(fleet.ships[i]["uid"])
	else:
		_split_ships.append(choice)
	_refresh()


func _deselect() -> void:
	if not _send_uid.is_empty():
		_send_uid = ""
		_refresh()
		return
	if not _split_ships.is_empty():
		_split_ships.clear()
		_refresh()
		return
	selected_fleet = ""
	selected_planet = ""
	selected_anomaly = ""
	_refresh()


func _on_end_turn_pressed() -> void:
	if not _busy and _is_human_turn():
		_submit(EndFactionTurnCommand.new(player_faction))


func _toggle_autoplay() -> void:
	autoplay = not autoplay
	hud.log_line("[i]Autoplay %s[/i]" % ("on" if autoplay else "off"))
	if autoplay and not _busy and not engine.state.is_over:
		_continue(_token)
	else:
		_refresh()


# --- Menu, saving and loading -------------------------------------------------

func _can_save() -> bool:
	return engine != null and not _busy and _is_human_turn() and not engine.state.is_over


func _quick_save() -> void:
	if not _can_save():
		hud.set_hint("You can save on your own turn, between moves")
		return
	var error := GalaxySave.write(GalaxySave.QUICKSAVE, engine, campaign_id)
	hud.set_hint("Quicksaved (F9 to load)" if error.is_empty() else error)


func _request_load(slot: String) -> void:
	if not FileAccess.file_exists(GalaxySave.path_for(slot)):
		hud.set_hint("No %s yet" % MainMenu.slot_label(slot).to_lower())
		return
	if _busy and not hud.is_dialog_open() and not _is_human_turn():
		hud.set_hint("Wait for the other factions to finish their turns")
		return
	if load_requested.get_connections().is_empty():
		var loaded := GalaxySave.load_slot(data, slot)
		if loaded.has("error"):
			hud.set_hint(loaded["error"])
		else:
			load_campaign(loaded["engine"], loaded["campaign"], MainMenu.slot_label(slot))
	else:
		load_requested.emit(slot)


## Esc / Menu button: resume, save, load, main menu, quit.
func _open_menu() -> void:
	if engine == null or hud.is_dialog_open() or (_busy and not engine.state.is_over):
		return
	hud.roster.visible = false
	hud.empire.visible = false
	var choices: Array[Dictionary] = [{"id": "resume", "label": "Resume"}]
	if _can_save():
		choices.append({"id": "save", "label": "Save"})
	if not GalaxySave.list().is_empty():
		choices.append({"id": "load", "label": "Load"})
	choices.append({"id": "settings", "label": "Settings"})
	if not main_menu_requested.get_connections().is_empty():
		choices.append({"id": "menu", "label": "Main menu"})
	if OS.get_name() != "Web":
		choices.append({"id": "quit", "label": "Quit"})
	var body := "%s, turn %d.\n\n%s" % [engine.campaign.get("name", campaign_id), engine.state.turn_number,
			UiKit.color_tag("The game autosaves at the start of each of your turns. F5 quicksaves, F9 loads the quicksave.", Palette.TEXT_DIM)]
	hud.ask("Menu", body, choices)
	var token := _token
	var choice: String = await hud.dialog_choice
	if token != _token:
		return
	match choice:
		"save":
			_save_menu()
		"load":
			_load_menu()
		"settings":
			hud.show_settings()
		"menu":
			main_menu_requested.emit()
		"quit":
			get_tree().quit()
		_:
			_refresh()


func _save_menu() -> void:
	var slots := ["slot_1", "slot_2", "slot_3"]
	var existing := {}
	for s in GalaxySave.list():
		existing[s["slot"]] = s
	var lines := PackedStringArray()
	var choices: Array[Dictionary] = []
	for slot: String in slots:
		var label := MainMenu.slot_label(slot)
		lines.append("[b]%s[/b]  %s" % [label, MainMenu._describe(existing[slot]).split("  ·  ", true, 1)[1]
				if existing.has(slot) else UiKit.color_tag("empty", Palette.TEXT_DIM)])
		choices.append({"id": slot, "label": label})
	choices.append({"id": "cancel", "label": "Cancel"})
	hud.ask("Save game", "\n".join(lines), choices)
	var token := _token
	var choice: String = await hud.dialog_choice
	if token != _token or choice == "cancel":
		_refresh()
		return
	var error := GalaxySave.write(choice, engine, campaign_id)
	hud.set_hint("Saved to %s" % MainMenu.slot_label(choice) if error.is_empty() else error)


func _load_menu() -> void:
	var saves := GalaxySave.list()
	var lines := PackedStringArray()
	var choices: Array[Dictionary] = []
	for s in saves.slice(0, 5):
		lines.append(MainMenu._describe(s))
		choices.append({"id": s["slot"], "label": MainMenu.slot_label(s["slot"])})
	choices.append({"id": "cancel", "label": "Cancel"})
	hud.ask("Load game", "\n".join(lines) + "\n\n" + UiKit.color_tag("Progress since your last save will be lost.", Palette.TEXT_DIM), choices)
	var token := _token
	var choice: String = await hud.dialog_choice
	if token != _token or choice == "cancel":
		_refresh()
		return
	_request_load(choice)
