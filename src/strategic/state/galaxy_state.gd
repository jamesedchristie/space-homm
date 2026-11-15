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

# Heroes and missions
var heroes: Dictionary = {}       # id -> Hero
var inventory: Dictionary = {}    # faction id -> Array[String] of item ids
## id -> {"id", "name", "cell": Vector2i, "mission": mission id, "faction"?: only this faction may take it}
var anomalies: Dictionary = {}
## While non-empty, a fleet is at an anomaly waiting for a decision:
## {"anomaly": id, "fleet": fleet id}
var pending_mission: Dictionary = {}
## Heroes downed on missions die instead of being injured or captured.
var permadeath := false

# Empire (step 4)
## faction id -> {"credits": int, "alloys": int}
var resources: Dictionary = {}
## faction id -> {"current": tech id or "", "progress": int, "known": Array[String]}
var research: Dictionary = {}
## "a|b" (ids sorted) -> {"status": "war"|"peace", "since": turn}. Missing pairs are at war.
var relations: Dictionary = {}
## faction id -> {other faction id: opinion -100..100}: how the first feels about the second.
var opinions: Dictionary = {}


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


func heroes_of(faction_id: String) -> Array[Hero]:
	var out: Array[Hero] = []
	for h: Hero in heroes.values():
		if h.owner == faction_id:
			out.append(h)
	return out


## The hero assigned to the fleet (ready or not), or null.
func commander_of(fleet: Fleet) -> Hero:
	return heroes.get(fleet.hero_id) if not fleet.hero_id.is_empty() else null


## The commander only counts while ready (not away on a mission or injured).
func active_commander(fleet: Fleet) -> Hero:
	var h := commander_of(fleet)
	return h if h != null and h.is_ready() else null


func anomaly_at(cell: Vector2i) -> Dictionary:
	for a: Dictionary in anomalies.values():
		if a["cell"] == cell:
			return a
	return {}


## Where heroes go when they come home: the faction's first planet.
func home_planet(faction_id: String) -> Planet:
	var owned := planets_of(faction_id)
	return owned[0] if not owned.is_empty() else null


static func relation_key(a: String, b: String) -> String:
	return "%s|%s" % [a, b] if a < b else "%s|%s" % [b, a]


func relation(a: String, b: String) -> Dictionary:
	return relations.get(relation_key(a, b), {"status": "war", "since": 0})


## Unowned planets and the faction itself are never "at war".
func at_war(a: String, b: String) -> bool:
	if a.is_empty() or b.is_empty() or a == b:
		return false
	return relation(a, b)["status"] == "war"


func set_relation(a: String, b: String, status: String) -> void:
	relations[relation_key(a, b)] = {"status": status, "since": turn_number}


func opinion(of_faction: String, about: String) -> int:
	return int(opinions.get(of_faction, {}).get(about, 0))


func known_techs(faction_id: String) -> Array:
	return research.get(faction_id, {}).get("known", [])


func is_eliminated(faction_id: String) -> bool:
	return faction_id in eliminated


func make_uid(prefix: String) -> String:
	next_uid += 1
	return "%s%d" % [prefix, next_uid]
