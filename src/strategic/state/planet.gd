class_name Planet
extends RefCounted
## A star system on the galaxy map (the class keeps its historical name):
## a star and its bodies (planets, moons, asteroid belts). The system gives
## vision, repairs friendly fleets and can be captured; each body can be
## developed (a colony on a habitable world, a mining base on rock, a
## research station on ice...), and colonies host extra buildings.

var id: String
var name: String
var cell: Vector2i
## Star type (data/strategic/star_types.json).
var star := "yellow"
## Faction id, or "" if unclaimed.
var owner := ""
var sensor := 2
var description := ""
## [{"id", "name", "type" (data/strategic/body_types.json), "traits": [ids], "buildings": [ids]}]
## Buildings: one installation per body (colony, mining_base, ...); a colony
## body also holds colony buildings (shipyard, trade_hub, ...).
var bodies: Array[Dictionary] = []
## Every building in the system (read-only view over the bodies).
var buildings: Array[String]:
	get:
		var out: Array[String] = []
		for b in bodies:
			for building_id: String in b.get("buildings", []):
				out.append(building_id)
		return out
## Current build: {} when idle, else {"kind": "building"|"unit", "item": id, "body": body id, "progress": int, "turns": int}
var queue: Dictionary = {}


func body(body_id: String) -> Dictionary:
	for b in bodies:
		if b["id"] == body_id:
			return b
	return {}


func add_building(body_id: String, building_id: String) -> void:
	var b := body(body_id)
	if b.is_empty() and not bodies.is_empty():
		b = bodies[0]
	if not b.is_empty():
		b["buildings"].append(building_id)


## Removes one instance of a building (e.g. a destroyed defense platform).
func remove_building(building_id: String) -> void:
	for b in bodies:
		if building_id in b["buildings"]:
			b["buildings"].erase(building_id)
			return


func has_colony() -> bool:
	return "colony" in buildings


## The body to show for the system on small views: its colony, else the biggest world.
func main_body(data: DataRegistry) -> Dictionary:
	var best: Dictionary = {}
	for b in bodies:
		if "colony" in b["buildings"]:
			return b
		if best.is_empty() or float(data.body_types.get(b["type"], {}).get("size", 0.0)) > float(data.body_types.get(best["type"], {}).get("size", 0.0)):
			best = b
	return best
