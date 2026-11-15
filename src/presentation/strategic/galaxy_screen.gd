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

const FLEET_OFFSET := Vector2(9, 9)
const PLANET_OFFSET := Vector2(-8, -6)

@export var campaign_id := "the_drift"
## 0 picks a random seed each campaign.
@export var rng_seed := 0
## Autoplay: the AI also plays the player's faction (press A).
@export var autoplay := false
## In autoplay, play battles involving the player on the battle screen
## (with autoplay there too) instead of auto-resolving them.
@export var watch_battles := false

@onready var map_view: HexMapView = $MapView
@onready var planets_layer: Node2D = $MapView/Planets
@onready var fleets_layer: Node2D = $MapView/Fleets
@onready var fx: FxLayer = $MapView/Fx
@onready var hud: GalaxyHud = $HUD/Hud

var data: DataRegistry
var engine: GalaxyEngine
var ai := GalaxyAI.new()
var player_faction := ""
var fleet_views: Dictionary = {}   # fleet id -> FleetView
var planet_views: Dictionary = {}  # planet id -> PlanetView
var selected_fleet := ""
var selected_planet := ""

var _busy := false
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
	get_viewport().size_changed.connect(_fit_map)
	start_campaign()


func start_campaign() -> void:
	_token += 1
	var token := _token
	for v: Node in fleet_views.values() + planet_views.values():
		v.queue_free()
	fleet_views.clear()
	planet_views.clear()
	selected_fleet = ""
	selected_planet = ""
	ai = GalaxyAI.new()

	engine = GalaxyEngine.from_campaign(data, campaign_id, rng_seed)
	player_faction = engine.state.factions[0]["id"]
	for f in engine.state.factions:
		if f["controller"] == "player":
			player_faction = f["id"]
			break
	map_view.setup(engine.state.grid)
	for p: Planet in engine.state.planets.values():
		var pv := PlanetView.new()
		planets_layer.add_child(pv)
		pv.setup(p, data)
		pv.position = map_view.cell_center(p.cell) + PLANET_OFFSET
		planet_views[p.id] = pv
	_sync_views()
	_fit_map()
	hud.clear_log()
	hud.set_objective(engine.campaign.get("description", ""))
	hud.log_line(UiKit.color_tag("%s  (seed %d)" % [engine.campaign.get("name", campaign_id), engine.state.seed_value], Palette.TEXT_DIM))

	_busy = true
	await _play(engine.start(), token)
	if token == _token:
		await _continue(token)


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
		if engine.has_pending_battle():
			await _resolve_battle(token)
			continue
		if _is_human_turn():
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
	if _is_human_turn() and not engine.state.fleets.has(selected_fleet):
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
	var defender: Fleet = engine.state.fleets[b["defender"]]
	var involves_player := attacker.owner == player_faction or defender.owner == player_faction
	var ask_player := involves_player and not autoplay
	var fight := autoplay and watch_battles and involves_player
	if ask_player:
		hud.ask("Battle %s" % engine.location_phrase(b["cell"]), _battle_preview(b, attacker, defender),
				[{"id": "fight", "label": "Fight"}, {"id": "auto", "label": "Auto-resolve"}])
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
			GalaxyEvents.PLANET_CAPTURED:
				var pv: PlanetView = planet_views[e["planet"]]
				pv.refresh(engine.state.planets[e["planet"]], engine.state)
				if _visible.has(engine.state.planets[e["planet"]].cell) or e["faction"] == player_faction:
					fx.float_text(pv.position, "Captured", Palette.team_color(engine.state.faction(e["faction"])["team"]))
			GalaxyEvents.BATTLE_TRIGGERED:
				var pos := map_view.cell_center(e["cell"])
				fx.play("pulse", pos, pos, Palette.BAD)
			GalaxyEvents.FLEET_DESTROYED:
				var view: FleetView = fleet_views.get(e["fleet"])
				if view != null and view.visible:
					await view.play_destroyed()
			GalaxyEvents.FLEET_REPAIRED:
				if engine.state.fleets[e["fleet"]].owner == player_faction:
					fx.float_text(fleet_views[e["fleet"]].position, "+%d hull" % e["amount"], Palette.GOOD)
			GalaxyEvents.CAMPAIGN_ENDED:
				_sync_views()
				_game_over()
	_sync_views()


func _animate_move(e: Dictionary) -> void:
	var fleet: Fleet = engine.state.fleets.get(e["fleet"])
	var view: FleetView = fleet_views.get(e["fleet"])
	if fleet == null or view == null:
		return
	var path: Array = e["path"]
	var seen := fleet.owner == player_faction
	var now_visible := engine.visible_cells(player_faction)
	for c: Vector2i in path:
		if _visible.has(c) or now_visible.has(c):
			seen = true
	if not seen or not is_inside_tree():
		return
	view.visible = true
	var points: Array[Vector2] = []
	for i in range(1, path.size()):
		points.append(map_view.cell_center(path[i]) + FLEET_OFFSET)
	await view.move_along(points)


func _game_over() -> void:
	var s := engine.state
	var title := "Draw"
	if s.winner == player_faction and not autoplay:
		title = "Victory"
	elif s.winner != "" and not autoplay:
		title = "Defeat"
	elif s.winner != "":
		title = "%s wins" % s.faction(s.winner)["name"]
	hud.ask(title, "The campaign is over after %d turns." % s.turn_number, [{"id": "new", "label": "New campaign"}])
	var token := _token
	await hud.dialog_choice
	if token == _token:
		start_campaign()


# --- View sync ----------------------------------------------------------------

## Updates fog, fleet markers and planet owners from engine state.
func _sync_views() -> void:
	_visible = engine.visible_cells(player_faction)
	map_view.set_fog(engine.explored_cells(player_faction), _visible)
	for id: String in fleet_views.keys():
		if not engine.state.fleets.has(id):
			fleet_views[id].queue_free()
			fleet_views.erase(id)
	for fleet: Fleet in engine.state.fleets.values():
		var view: FleetView = fleet_views.get(fleet.id)
		if view == null:
			view = FleetView.new()
			fleets_layer.add_child(view)
			view.setup(fleet, engine.state.faction(fleet.owner)["team"], data, fleet.owner == player_faction)
			fleet_views[fleet.id] = view
		view.refresh(fleet, data)
		view.position = map_view.cell_center(fleet.cell) + FLEET_OFFSET
		view.visible = engine.can_see_fleet(player_faction, fleet, _visible)
		view.set_selected(fleet.id == selected_fleet)
	for p: Planet in engine.state.planets.values():
		planet_views[p.id].refresh(p, engine.state)


## Recomputes highlights, info panel and hints.
func _refresh() -> void:
	var s := engine.state
	var current := s.current_faction()
	hud.set_turn(s.turn_number, current["name"], Palette.team_color(current["team"]))
	var human := not _busy and _is_human_turn()
	hud.set_end_turn_enabled(human)

	var move_cells: Array[Vector2i] = []
	var path: Array[Vector2i] = []
	_reach = {}
	_attack_cells = []
	var fleet: Fleet = s.fleets.get(selected_fleet)
	var mine := fleet != null and fleet.owner == player_faction
	if human and mine:
		_reach = engine.reachable_for(fleet.id)
		_attack_cells = engine.attack_targets(fleet.id, _reach)
		for c: Vector2i in _reach:
			if c != fleet.cell and c not in _attack_cells:
				move_cells.append(c)
		if _hover != null and _reach.has(_hover) and _hover != fleet.cell:
			path = Pathfinding.path_to(_reach, _hover)

	map_view.set_highlights(move_cells, _attack_cells, [], path)
	map_view.set_active(fleet.cell if fleet != null and fleet_views.has(fleet.id) and fleet_views[fleet.id].visible else null)
	map_view.set_hover(_hover)
	for id: String in fleet_views:
		fleet_views[id].set_selected(id == selected_fleet)

	if fleet != null:
		hud.set_info(_fleet_info(fleet))
	elif s.planets.has(selected_planet):
		hud.set_info(_planet_info(s.planets[selected_planet]))
	else:
		hud.set_info(UiKit.color_tag("Select a fleet or planet.", Palette.TEXT_DIM))
	hud.set_hint(_hint_text(human, fleet if mine else null))


func _hint_text(human: bool, fleet: Fleet) -> String:
	if engine.state.is_over:
		return "The campaign is over."
	if not human:
		return "Autoplay: the AI plays every faction. Press A to take back control." if autoplay \
				else "%s is moving..." % engine.state.current_faction()["name"]
	var text := ""
	if fleet == null:
		text = "Click one of your fleets. Tab: next fleet with moves. Space: end turn."
	elif _hover != null and _hover in _attack_cells:
		text = "Attack %s here" % engine.state.fleet_at(_hover).name
	elif _hover != null and _reach.has(_hover) and _hover != fleet.cell:
		text = "Move here: %d of %d moves" % [_reach[_hover]["cost"], fleet.moves_left]
	else:
		text = "%s: blue = move, red = attack. Right-click to deselect." % fleet.name
	if _hover != null:
		var planet := engine.state.planet_at(_hover)
		if planet != null:
			text += "   ·   %s" % planet.name
		var terrain := engine.state.grid.terrain_def(_hover)
		if not terrain.is_empty() and engine.explored_cells(player_faction).has(_hover):
			text += "   ·   %s: %s" % [terrain.get("name", ""), terrain.get("description", "")]
	return text


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
		if f.moves_left > 0:
			selected_fleet = f.id
			selected_planet = ""
			return
	selected_fleet = ""


func _fit_map() -> void:
	if engine == null:
		return
	var area := hud.map_area()
	var b := map_view.bounds()
	var f := clampf(minf((area.size.x - 32.0) / b.size.x, (area.size.y - 32.0) / b.size.y), 0.4, 1.6)
	map_view.scale = Vector2(f, f)
	map_view.position = area.get_center() - b.get_center() * f


# --- Text ---------------------------------------------------------------------

func _fleet_name(fleet: Fleet) -> String:
	return UiKit.color_tag(fleet.name, Palette.team_color(engine.state.faction(fleet.owner)["team"]))


func _fleet_info(fleet: Fleet) -> String:
	var faction := engine.state.faction(fleet.owner)
	var lines := PackedStringArray()
	lines.append("[b]%s[/b]  %s" % [_fleet_name(fleet), UiKit.color_tag(faction["name"], Palette.TEXT_DIM)])
	if fleet.owner == player_faction:
		lines.append("Moves %d / %d   ·   Sensors %d" % [fleet.moves_left, fleet.speed(data), fleet.sensor(data)])
	lines.append("")
	for ship in fleet.ships:
		var def: Dictionary = data.units[ship["unit"]]
		var max_hull := int(def["stats"]["max_hull"])
		var hull_color := Palette.HULL if ship["hull"] > max_hull * 0.5 else Palette.BAD
		lines.append("%s  %s  %s" % [ship["name"], UiKit.color_tag(def.get("name", ""), Palette.TEXT_DIM),
				UiKit.color_tag("%d/%d" % [ship["hull"], max_hull], hull_color)])
	var planet := engine.state.planet_at(fleet.cell)
	if planet != null and planet.owner == fleet.owner:
		lines.append("")
		lines.append(UiKit.color_tag("At %s: repairing %d%% hull per turn" % [planet.name, roundi(GalaxyEngine.REPAIR_RATE * 100)], Palette.GOOD))
	return "\n".join(lines)


func _planet_info(planet: Planet) -> String:
	var type_def: Dictionary = data.planet_types.get(planet.type, {})
	var owner := "Unclaimed"
	var color := Palette.NEUTRAL
	if not planet.owner.is_empty():
		var f := engine.state.faction(planet.owner)
		owner = f["name"]
		color = Palette.team_color(f["team"])
	return "[b]%s[/b]  %s\n%s\n\n%s\n\nSensors %d. Friendly fleets here repair. Move a fleet here to capture it." % [
			planet.name, UiKit.color_tag(type_def.get("name", planet.type), Palette.TEXT_DIM),
			UiKit.color_tag(owner, color), planet.description, planet.sensor]


func _battle_preview(b: Dictionary, attacker: Fleet, defender: Fleet) -> String:
	var lines := PackedStringArray()
	if b.get("ambush", false) or attacker.owner != player_faction and defender.owner == player_faction:
		lines.append(UiKit.color_tag("Enemy contact!", Palette.BAD))
	for fleet in [attacker, defender]:
		var ships := PackedStringArray()
		for ship in (fleet as Fleet).ships:
			ships.append("%s (%d hull)" % [ship["name"], ship["hull"]])
		lines.append("[b]%s[/b]: %s" % [_fleet_name(fleet), ", ".join(ships)])
	var map_name: String = data.maps[engine.battle_map_for(b["cell"])].get("name", "")
	lines.append("")
	lines.append(UiKit.color_tag("Battlefield: %s. Damage to hulls carries over after the battle." % map_name, Palette.TEXT_DIM))
	return "\n".join(lines)


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
		return "\n".join(lines)
	return ""


func _describe(e: Dictionary) -> String:
	var s := engine.state
	match e["type"]:
		GalaxyEvents.TURN_STARTED:
			var f := s.faction(e["faction"])
			return "\n[b]Turn %d[/b]  %s" % [e["turn"], UiKit.color_tag(f["name"], Palette.team_color(f["team"]))]
		GalaxyEvents.PLANET_CAPTURED:
			var f := s.faction(e["faction"])
			return "%s captures %s" % [UiKit.color_tag(f["name"], Palette.team_color(f["team"])), s.planets[e["planet"]].name]
		GalaxyEvents.BATTLE_TRIGGERED:
			var a: Fleet = s.fleets[e["attacker"]]
			var d: Fleet = s.fleets[e["defender"]]
			if a.owner != player_faction and d.owner != player_faction:
				return ""
			if e["ambush"]:
				return "%s is ambushed by %s %s" % [_fleet_name(a), _fleet_name(d), engine.location_phrase(e["cell"])]
			return "%s engages %s %s" % [_fleet_name(a), _fleet_name(d), engine.location_phrase(e["cell"])]
		GalaxyEvents.BATTLE_RESOLVED:
			var winner: String = e["winner"]
			return "   Battle won by %s (%d rounds)" % [s.faction(winner).get("name", "nobody"), e["rounds"]]
		GalaxyEvents.FLEET_DESTROYED:
			return UiKit.color_tag("   %s destroyed" % e["name"], Palette.BAD)
		GalaxyEvents.FACTION_ELIMINATED:
			return "[b]%s eliminated[/b]" % s.faction(e["faction"])["name"]
		GalaxyEvents.CAMPAIGN_ENDED:
			return "\n[b]Campaign over[/b]"
	return ""


# --- Input --------------------------------------------------------------------

func _unhandled_input(event: InputEvent) -> void:
	if engine == null or hud.is_dialog_open():
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
			_deselect()
	elif event is InputEventKey and event.pressed and not event.echo:
		match event.keycode:
			KEY_ESCAPE:
				_deselect()
			KEY_SPACE, KEY_ENTER, KEY_KP_ENTER:
				_on_end_turn_pressed()
			KEY_TAB:
				_select_next_fleet()
				_refresh()
			KEY_A:
				_toggle_autoplay()


func _on_left_click() -> void:
	if _hover == null:
		return
	var cell: Vector2i = _hover
	var fleet: Fleet = engine.state.fleets.get(selected_fleet)
	if not _busy and _is_human_turn() and fleet != null and fleet.owner == player_faction:
		if cell in _attack_cells or (_reach.has(cell) and cell != fleet.cell):
			_submit(MoveFleetCommand.new(player_faction, fleet.id, cell))
			return
	var other := engine.state.fleet_at(cell)
	if other != null and engine.can_see_fleet(player_faction, other, _visible):
		selected_fleet = other.id
		selected_planet = ""
	elif engine.state.planet_at(cell) != null:
		selected_planet = engine.state.planet_at(cell).id
		selected_fleet = ""
	else:
		_deselect()
		return
	_refresh()


func _deselect() -> void:
	selected_fleet = ""
	selected_planet = ""
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
