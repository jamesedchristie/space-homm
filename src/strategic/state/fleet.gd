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


## Rough combat power for AI decisions: effective hit points.
func strength(data: DataRegistry) -> float:
	var total := 0.0
	for ship in ships:
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
