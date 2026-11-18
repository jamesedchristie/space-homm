class_name SystemBuilder
extends RefCounted
## Creates star systems' contents: bodies from a campaign definition, or a
## random set (seeded) when the definition doesn't list them.
##
## Campaign system entry:
##   {"id", "name", "at": [c, r], "owner"?, "star"?, "sensor"?, "description"?,
##    "bodies": [{"type", "name"?, "buildings"?: [ids], "traits"?: [ids], "pop"?: starting population of a colony}]
##              or omitted / "random": rolled from the seed,
##    "home": true  (random bodies always include a terran world)}

## How likely each body type is in a random system.
const WEIGHTS := {
	"terran": 3, "ocean": 2, "desert": 3, "arctic": 3,
	"barren": 6, "volcanic": 3, "asteroid_belt": 5, "gas_giant": 4, "ice_moon": 5,
}
const ROMAN := ["I", "II", "III", "IV", "V", "VI", "VII"]


static func bodies_from_def(data: DataRegistry, def: Dictionary, system_name: String, rng: RandomNumberGenerator) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var listed: Variant = def.get("bodies", "random")
	if listed is Array and not listed.is_empty():
		for i in listed.size():
			var b: Dictionary = listed[i]
			var traits: Array[String] = []
			traits.assign(b.get("traits", []))
			var buildings: Array[String] = []
			buildings.assign(b.get("buildings", []))
			var body := {"id": "%s_%d" % [def.get("id", system_name), i], "type": b["type"],
					"name": b.get("name", _body_name(system_name, b["type"], i)), "traits": traits, "buildings": buildings}
			if "colony" in buildings:
				body["pop"] = int(b.get("pop", Planet.START_POP))
				body["growth"] = 0.0
			out.append(body)
		return out
	return random_bodies(data, rng, def.get("id", system_name), system_name, def.get("home", false))


## 2-5 bodies; home systems always get a terran world (and nothing hostile).
static func random_bodies(data: DataRegistry, rng: RandomNumberGenerator, system_id: String, system_name: String,
		home: bool = false) -> Array[Dictionary]:
	var types: Array[String] = []
	if home:
		types.append("terran")
	var count := rng.randi_range(2, 5) if not home else rng.randi_range(3, 4)
	var total := 0
	for t: String in WEIGHTS:
		total += int(WEIGHTS[t])
	while types.size() < count:
		var roll := rng.randi_range(1, total)
		for t: String in WEIGHTS:
			roll -= int(WEIGHTS[t])
			if roll <= 0:
				if not (t == "asteroid_belt" and "asteroid_belt" in types):
					types.append(t)
				break
	# Order by distance from the star: rocky inner worlds, then habitable, then belts and giants, ice outermost.
	var order := {"volcanic": 0, "barren": 1, "desert": 2, "terran": 3, "ocean": 3, "arctic": 4, "asteroid_belt": 5, "gas_giant": 6, "ice_moon": 7}
	types.sort_custom(func(a: String, b: String) -> bool: return int(order.get(a, 9)) < int(order.get(b, 9)))
	var out: Array[Dictionary] = []
	for i in types.size():
		out.append({"id": "%s_%d" % [system_id, i], "type": types[i], "name": _body_name(system_name, types[i], i),
				"traits": [] as Array[String], "buildings": [] as Array[String]})
	return out


static func random_star(data: DataRegistry, rng: RandomNumberGenerator) -> String:
	var ids := data.star_types.keys()
	ids.sort()
	var total := 0
	for id: String in ids:
		total += int(data.star_types[id].get("weight", 1))
	var roll := rng.randi_range(1, maxi(total, 1))
	for id: String in ids:
		roll -= int(data.star_types[id].get("weight", 1))
		if roll <= 0:
			return id
	return "yellow"


static func _body_name(system_name: String, type: String, index: int) -> String:
	if type == "asteroid_belt":
		return "%s Belt" % system_name
	return "%s %s" % [system_name, ROMAN[mini(index, ROMAN.size() - 1)]]
