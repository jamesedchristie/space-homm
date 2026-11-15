class_name GalaxyState
extends RefCounted
## Everything that describes a campaign in progress. Rules live in GalaxyEngine.

var grid: TacticalGrid
## [{ "id", "name", "controller": "player"|"ai", "team": int }]
## `team` is also the faction's team number (and color) in tactical battles.
var factions: Array[Dictionary] = []
var planets: Dictionary = {}  # id -> Planet
var fleets: Dictionary = {}   # id -> Fleet (insertion ordered)

var turn_number := 0
var max_turns := 200
var current_faction_index := 0
## faction id -> { cell: true } for every cell that faction has ever seen.
var explored: Dictionary = {}
var eliminated: Array[String] = []

var rng := RandomNumberGenerator.new()
var seed_value := 0

## While non-empty, the campaign waits for the battle to be fought:
## {"attacker": fleet id, "defender": fleet id, "cell": Vector2i, "ambush": bool}
var pending_battle: Dictionary = {}

var is_over := false
## Winning faction id; "" for a draw or while running.
var winner := ""

var next_uid := 0


func current_faction() -> Dictionary:
	return factions[current_faction_index]


func faction(faction_id: String) -> Dictionary:
	for f in factions:
		if f["id"] == faction_id:
			return f
	return {}


func faction_for_team(team: int) -> Dictionary:
	for f in factions:
		if f["team"] == team:
			return f
	return {}


func fleet_at(cell: Vector2i) -> Fleet:
	for f: Fleet in fleets.values():
		if f.cell == cell:
			return f
	return null


func planet_at(cell: Vector2i) -> Planet:
	for p: Planet in planets.values():
		if p.cell == cell:
			return p
	return null


func fleets_of(faction_id: String) -> Array[Fleet]:
	var out: Array[Fleet] = []
	for f: Fleet in fleets.values():
		if f.owner == faction_id:
			out.append(f)
	return out


func planets_of(faction_id: String) -> Array[Planet]:
	var out: Array[Planet] = []
	for p: Planet in planets.values():
		if p.owner == faction_id:
			out.append(p)
	return out


func make_uid(prefix: String) -> String:
	next_uid += 1
	return "%s%d" % [prefix, next_uid]
