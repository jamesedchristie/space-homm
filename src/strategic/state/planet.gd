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
## "relic" for an ancient relic gate (lane campaigns); jump gates are buildings ("jump_gate").
var gate := ""
## Governor (Automation): when idle, the colony queues what the AI would build.
var auto_build := false
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
## Current build: {} when idle, else {"kind": "building"|"unit"|"megaproject", "item": id, "body": body id, "progress": int, "turns": int}
var queue: Dictionary = {}
## Civilian ships working in the system (the system map level), deployed from fleets:
## [{"uid", "unit", "name", "hull", "owner", "loc": body id or "" (arrival),
##   "job": {} or {"body", "building", "turns_left", "turns"}}]. A ship here is safe from
## fleets but is lost with the system if an enemy takes it.
var civilians: Array[Dictionary] = []
## While a faction's warfleet sits in the system with the garrison beaten and the
## colony not yet invaded: that faction's id. The system's production is halted.
var blockade := ""
## For a major power's undeveloped home system ("colony_ship" starts):
## {"faction", "buildings": [ids], "pop"}. Its first colony there gets those buildings.
var capital: Dictionary = {}
## Completed megaprojects (data/empire/megaprojects.json) standing in this system.
## They pass to whoever captures the system.
var megaprojects: Array[String] = []

## Colony bodies carry "pop" (population, 1..cap) and "growth" (progress toward the next pop).
const START_POP := 1


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
		if building_id == "colony":
			b["pop"] = int(b.get("pop", START_POP))
			b["growth"] = float(b.get("growth", 0.0))


## Removes one instance of a building (e.g. a destroyed defense platform).
func remove_building(building_id: String) -> void:
	for b in bodies:
		if building_id in b["buildings"]:
			b["buildings"].erase(building_id)
			return


## Colony bodies (habitable worlds with a colony building).
func colonies() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for b in bodies:
		if "colony" in b["buildings"]:
			out.append(b)
	return out


func population() -> int:
	var n := 0
	for b in bodies:
		if "colony" in b["buildings"]:
			n += int(b.get("pop", START_POP))
	return n


func is_blockaded() -> bool:
	return not blockade.is_empty()


## The deployed civilian ship with this uid, or {}.
func civilian(uid: String) -> Dictionary:
	for c in civilians:
		if c["uid"] == uid:
			return c
	return {}


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
