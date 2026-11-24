class_name DepositRules
extends RefCounted
## Strategic resources (data/empire/resources.json "kind": "strategic": volatiles, rare elements,
## exotic matter) and the deposits they come from. A body carries "deposits": {resource: richness 1-3};
## a development that "extracts" a resource yields `per_richness` x richness of it per turn
## (economy.json "deposits"). Strategic resources are stockpiled like alloys and spent by costs.
## Static helpers, so the engine, UI and AI agree.


## Ids of the strategic resources, in data order.
static func strategic(data: DataRegistry) -> Array[String]:
	var out: Array[String] = []
	for id: String in data.resources:
		if data.resources[id].get("kind", "") == "strategic":
			out.append(id)
	return out


static func is_strategic(data: DataRegistry, resource: String) -> bool:
	return data.resources.get(resource, {}).get("kind", "") == "strategic"


## Resources a faction keeps a stockpile of: everything but research (which flows into the current tech).
static func stockpiled(data: DataRegistry) -> Array[String]:
	var out: Array[String] = []
	for id: String in data.resources:
		if data.resources[id].get("kind", "basic") != "flow":
			out.append(id)
	return out


## A body's deposits: {resource: richness}.
static func of(b: Dictionary) -> Dictionary:
	return b.get("deposits", {})


# --- Rolling ------------------------------------------------------------------

## Deposits for a new body of this type, from its "deposits" table in body_types.json:
## {"chance": [first, second], "table": {resource: weight}}. Each deposit is a different
## resource; richness 1-3 is weighted by economy.json deposits.richness_weights.
static func roll(data: DataRegistry, type: String, rng: RandomNumberGenerator) -> Dictionary:
	var out := {}
	var spec: Dictionary = data.body_types.get(type, {}).get("deposits", {})
	var table: Dictionary = spec.get("table", {})
	for chance: float in spec.get("chance", []):
		if rng.randf() >= chance:
			break
		var pick := _weighted(table, out, rng)
		if pick.is_empty():
			break
		out[pick] = roll_richness(data, rng)
	return out


static func roll_richness(data: DataRegistry, rng: RandomNumberGenerator) -> int:
	var weights: Array = data.economy.get("deposits", {}).get("richness_weights", [6, 3, 1])
	var total := 0.0
	for w: Variant in weights:
		total += float(w)
	var roll_at := rng.randf() * total
	for i in weights.size():
		roll_at -= float(weights[i])
		if roll_at < 0.0:
			return i + 1
	return 1


static func _weighted(table: Dictionary, skip: Dictionary, rng: RandomNumberGenerator) -> String:
	var total := 0.0
	var keys: Array = table.keys()
	keys.sort()
	for k: String in keys:
		if not skip.has(k):
			total += float(table[k])
	if total <= 0.0:
		return ""
	var at := rng.randf() * total
	for k: String in keys:
		if skip.has(k):
			continue
		at -= float(table[k])
		if at < 0.0:
			return k
	return ""


# --- Extraction ---------------------------------------------------------------

## Per-turn strategic output of a body: each deposit tapped by one of its developments
## (a building whose "extracts" lists that resource).
static func extraction(data: DataRegistry, b: Dictionary) -> Dictionary:
	var out := {}
	var deposits := of(b)
	if deposits.is_empty():
		return out
	var per := float(data.economy.get("deposits", {}).get("per_richness", 1))
	for resource: String in deposits:
		for building_id: String in b.get("buildings", []):
			if resource in data.buildings.get(building_id, {}).get("extracts", []):
				out[resource] = float(deposits[resource]) * per
				break
	return out


## Whether one of the body's developments taps this deposit.
static func is_tapped(data: DataRegistry, b: Dictionary, resource: String) -> bool:
	return extraction(data, b).has(resource)


## Developments that could tap `resource` on body `b` (by category; colonies only on habitable worlds).
static func extractors_for(engine: GalaxyEngine, b: Dictionary, resource: String) -> Array[String]:
	var out: Array[String] = []
	var category := EmpireRules.body_category(engine, b)
	for id: String in engine.data.buildings:
		var def: Dictionary = engine.data.buildings[id]
		if resource in def.get("extracts", []) and category in def.get("on", []):
			out.append(id)
	return out


# --- Text ---------------------------------------------------------------------

static func resource_name(data: DataRegistry, resource: String) -> String:
	return data.resources.get(resource, {}).get("name", resource)


static func color(data: DataRegistry, resource: String) -> Color:
	return Color(data.resources.get(resource, {}).get("color", "#ffffff"))


static func richness_word(richness: int) -> String:
	return ["", "poor", "good", "rich"][clampi(richness, 0, 3)]


## What the faction can spend a resource on, from the data: names of units, buildings,
## megaprojects and techs whose cost (or tech "cost_resources") lists it.
static func uses(engine: GalaxyEngine, resource: String) -> PackedStringArray:
	var out := PackedStringArray()
	var data := engine.data
	for id: String in data.units:
		if data.units[id].get("strategic", {}).get("cost", {}).has(resource):
			out.append(data.units[id].get("name", id))
	for id: String in data.buildings:
		if data.buildings[id].get("cost", {}).has(resource):
			out.append(data.buildings[id].get("name", id))
	for id: String in data.megaprojects:
		if data.megaprojects[id].get("cost", {}).has(resource) and not EmpireRules.megaproject_hidden(engine, id):
			out.append(data.megaprojects[id].get("name", id))
	for id: String in data.techs:
		if data.techs[id].get("cost_resources", {}).has(resource) and ResearchRules.offered(engine, id):
			out.append(data.techs[id].get("name", id))
	return out
