class_name BattleUnit
extends RefCounted
## One combatant on a tactical grid: a ship in a fleet battle, later a squad
## member in a ground mission. Pure state; rules live in BattleEngine.
##
## Stats are open-ended (whatever the unit JSON lists), and statuses modify
## them via get_stat(). Well-known stats:
##   max_hull, max_shields, armor, initiative, max_ap  (from unit data)
##   damage_dealt, damage_taken                        (multipliers, default 1.0)

##   sight                                             (vision radius when fog is on)

const DEFAULT_STATS := {"damage_dealt": 1.0, "damage_taken": 1.0, "sight": 6.0}

var id: String
var def_id: String
## The definition this unit was built from (content JSON, or generated for heroes).
var def: Dictionary = {}
var name: String
var team: int
var cell: Vector2i
var tags: PackedStringArray = []
var base_stats: Dictionary = {}
var abilities: PackedStringArray = []

var hull: int
var shields: int
var ap: int
var alive := true

## ability id -> own turns until usable again.
var cooldowns: Dictionary = {}
var statuses: Array[StatusInstance] = []

## Hook for step 3: the named hero commanding this ship / leading this squad.
## Heroes will add abilities and stat modifiers on top of the unit definition.
var hero_id: String = ""

## Identifier of whatever this unit represents outside the battle (e.g. a ship
## in a galaxy fleet), so results can be written back after the fight.
var ref: String = ""

## Dormant units (mission enemies) skip their turns until they spot an enemy,
## take damage, or a trigger alerts them. Units sharing a `group` wake together.
var alert := true
var group := ""


static func from_def(p_id: String, p_def: Dictionary, p_team: int, p_cell: Vector2i, display_name: String = "") -> BattleUnit:
	var u := BattleUnit.new()
	u.id = p_id
	u.def = p_def
	u.def_id = p_def.get("id", "")
	u.name = display_name if not display_name.is_empty() else p_def.get("name", u.def_id)
	u.team = p_team
	u.cell = p_cell
	u.tags = PackedStringArray(p_def.get("tags", []))
	u.abilities = PackedStringArray(p_def.get("abilities", []))
	var stats: Dictionary = p_def.get("stats", {})
	for key: String in stats:
		u.base_stats[key] = float(stats[key])
	u.hull = u.max_hull()
	u.shields = u.max_shields()
	u.ap = 0
	return u


## Base stat plus status modifiers: (base + sum(add)) * product(mul).
func get_stat(stat: String) -> float:
	var value: float = base_stats.get(stat, DEFAULT_STATS.get(stat, 0.0))
	var mul := 1.0
	for s in statuses:
		var mods: Dictionary = s.def.get("modifiers", {})
		if mods.has(stat):
			var m: Dictionary = mods[stat]
			value += float(m.get("add", 0.0))
			mul *= float(m.get("mul", 1.0))
	return value * mul


func stat_i(stat: String) -> int:
	return roundi(get_stat(stat))


func max_hull() -> int:
	return stat_i("max_hull")


func max_shields() -> int:
	return stat_i("max_shields")


func has_flag(flag: String) -> bool:
	for s in statuses:
		if s.has_flag(flag):
			return true
	return false


## True if one of its statuses makes it immune to this one ("blocks": [status ids]).
func blocks_status(status_id: String) -> bool:
	for s in statuses:
		if status_id in s.def.get("blocks", []):
			return true
	return false


func find_status(status_id: String) -> StatusInstance:
	for s in statuses:
		if s.id == status_id:
			return s
	return null


func cooldown_of(ability_id: String) -> int:
	return int(cooldowns.get(ability_id, 0))
