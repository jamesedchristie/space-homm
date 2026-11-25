class_name Fleet
extends RefCounted
## A stack of ships moving on the galaxy map. Ships persist between battles:
## hull damage carries over (shields recharge) until repaired at a friendly planet.
##
## Each ship is a Dictionary: {"uid", "unit" (unit def id), "name", "hull"}.

const DEFAULT_SPEED := 3
const DEFAULT_SENSOR := 2

var id: String
var name: String
var owner: String
var cell: Vector2i
var ships: Array[Dictionary] = []
var moves_left := 0
## Hook for step 3: the hero commanding this fleet.
var hero_id := ""
## A civilian ship's standing order (OrderShipCommand), carried by its own fleet:
## {"ship", "planet", "body", "action": "job"|"found", "item"}; {} for none.
var order: Dictionary = {}
## Automation (Automation): "explore" for a fleet that explores on its own, "" otherwise.
var auto := ""


## Slowest ship sets the pace.
func speed(data: DataRegistry) -> int:
	var s := 1 << 30
	for ship in ships:
		s = mini(s, int(_strategic(data, ship).get("speed", DEFAULT_SPEED)))
	return s if not ships.is_empty() else 0


## Best sensor in the fleet.
func sensor(data: DataRegistry) -> int:
	var s := 0
	for ship in ships:
		s = maxi(s, int(_strategic(data, ship).get("sensor", DEFAULT_SENSOR)))
	return s


## Whether a unit is a civilian ship (colony ship, constructor, troop transport).
static func is_civilian_unit(data: DataRegistry, unit_id: String) -> bool:
	return bool(data.units.get(unit_id, {}).get("strategic", {}).get("civilian", false))


## The unit's civilian role: "colony", "constructor", "transport" ("" for warships).
static func role_of(data: DataRegistry, unit_id: String) -> String:
	return data.units.get(unit_id, {}).get("strategic", {}).get("role", "")


## Which ship designs a faction flies (ModelFactory variant): "raider" (salvaged designs, the
## barbarians' default) or "" (its species' own designs; a faction's "ship_variant": "species").
static func model_variant(faction: Dictionary) -> String:
	var v: String = faction.get("ship_variant", "raider" if faction.get("role", "") == "barbarian" else "")
	return "" if v == "species" else v


## Only civilian ships (and at least one): such a fleet can't fight, and enemy warfleets destroy it.
func is_civilian_only(data: DataRegistry) -> bool:
	for ship in ships:
		if not is_civilian_unit(data, ship["unit"]):
			return false
	return not ships.is_empty()


## Carries a colony ship or constructor (which should not be dragged into battles).
func has_workers(data: DataRegistry) -> bool:
	return has_role(data, "colony") or has_role(data, "constructor")


func has_role(data: DataRegistry, role: String) -> bool:
	for ship in ships:
		if role_of(data, ship["unit"]) == role:
			return true
	return false


## Rough combat power for AI decisions: effective hit points of the warships.
func strength(data: DataRegistry) -> float:
	var total := 0.0
	for ship in ships:
		if is_civilian_unit(data, ship["unit"]):
			continue
		var stats: Dictionary = data.units[ship["unit"]].get("stats", {})
		total += float(ship["hull"]) + float(stats.get("max_shields", 0)) * 0.5
	return total


func hull_ratio(data: DataRegistry) -> float:
	var hull := 0.0
	var max_hull := 0.0
	for ship in ships:
		hull += float(ship["hull"])
		max_hull += float(data.units[ship["unit"]].get("stats", {}).get("max_hull", 1))
	return hull / max_hull if max_hull > 0.0 else 0.0


func _strategic(data: DataRegistry, ship: Dictionary) -> Dictionary:
	return data.units[ship["unit"]].get("strategic", {})
