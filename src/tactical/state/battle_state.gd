class_name BattleState
extends RefCounted
## Everything that describes a battle in progress. Contains no rules: those are
## in BattleEngine and rules/. Keeping state separate makes save/load, replays
## and auto-resolve straightforward.

const NO_WINNER := -1
const DRAW := -2

var grid: TacticalGrid
## Presentation extras of the map (system battles): {"star": {...}, "bodies": [...]}; empty otherwise.
var scenery: Dictionary = {}
## Insertion-ordered: unit id -> BattleUnit.
var units: Dictionary = {}
## [{ "team": int, "name": String, "controller": "player"|"ai" }]
var teams: Array[Dictionary] = []

var round_number := 0
var max_rounds := 50
## Unit ids still to act this round, in order. The active unit is not in it.
var turn_queue: Array[String] = []
var active_unit_id := ""

var rng := RandomNumberGenerator.new()
var seed_value := 0

var objectives: Array[BattleObjective] = []

# --- Missions: fog of war, triggers, rewards ---------------------------------
## When true, each team only sees cells within its units' sight and line of sight.
var fog_enabled := false
## team -> { cell: true } ever seen.
var explored: Dictionary = {}
## Scripted cell triggers from the scenario (see BattleEngine._check_triggers).
var triggers: Array[Dictionary] = []
## Set while a trigger waits for the player's choice: {"trigger": index, "unit": id}.
var pending_choice: Dictionary = {}
## Campaign rewards earned during the battle (xp, items, traits, loyalty).
var rewards: Array[Dictionary] = []
## Id of the mission this battle belongs to, if any.
var mission_id := ""
## Bumped whenever unit positions change; invalidates the visibility cache.
var version := 0
var _vis_cache: Dictionary = {}
var _vis_version := -1
var is_over := false
var winner := NO_WINNER


func active_unit() -> BattleUnit:
	return units.get(active_unit_id)


func get_unit(unit_id: String) -> BattleUnit:
	return units.get(unit_id)


## Living unit standing on `cell`, or null.
func unit_at(cell: Vector2i) -> BattleUnit:
	for u: BattleUnit in units.values():
		if u.alive and u.cell == cell:
			return u
	return null


func is_occupied(cell: Vector2i) -> bool:
	return unit_at(cell) != null


## Living units, optionally only those of one team.
func living_units(team: int = -1) -> Array[BattleUnit]:
	var out: Array[BattleUnit] = []
	for u: BattleUnit in units.values():
		if u.alive and (team < 0 or u.team == team):
			out.append(u)
	return out


func living_enemies_of(unit: BattleUnit) -> Array[BattleUnit]:
	var out: Array[BattleUnit] = []
	for u in living_units():
		if u.team != unit.team:
			out.append(u)
	return out


func team_info(team: int) -> Dictionary:
	for t in teams:
		if t["team"] == team:
			return t
	return {}


## Cells `team` can see right now: within each unit's sight, with line of sight.
## Without fog, every cell is visible.
func visible_cells(team: int) -> Dictionary:
	if _vis_version != version:
		_vis_cache.clear()
		_vis_version = version
	if _vis_cache.has(team):
		return _vis_cache[team]
	var vis := {}
	if not fog_enabled:
		for c in grid.cells():
			vis[c] = true
	else:
		for u in living_units(team):
			for c in grid.cells_within(u.cell, u.stat_i("sight")):
				if not vis.has(c) and grid.has_line_of_sight(u.cell, c):
					vis[c] = true
	_vis_cache[team] = vis
	return vis


func is_visible(team: int, cell: Vector2i) -> bool:
	return not fog_enabled or visible_cells(team).has(cell)


func teams_alive() -> Array[int]:
	var out: Array[int] = []
	for u in living_units():
		if u.team not in out:
			out.append(u.team)
	return out
