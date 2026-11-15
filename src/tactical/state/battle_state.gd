class_name BattleState
extends RefCounted
## Everything that describes a battle in progress. Contains no rules: those are
## in BattleEngine and rules/. Keeping state separate makes save/load, replays
## and auto-resolve straightforward.

const NO_WINNER := -1
const DRAW := -2

var grid: TacticalGrid
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


func teams_alive() -> Array[int]:
	var out: Array[int] = []
	for u in living_units():
		if u.team not in out:
			out.append(u.team)
	return out
