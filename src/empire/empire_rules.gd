class_name EmpireRules
extends RefCounted
## Economy and technology effects: planet yields, income, what a planet can
## build and what it costs, and the bonuses a faction's techs give.
## Static helpers over GalaxyEngine state, so UI, AI and the engine agree.

const RESOURCES := ["credits", "alloys", "research"]
## Ships per fleet (the battle maps have 6 deployment slots per side).
const MAX_FLEET_SIZE := 6


# --- Technology effects -------------------------------------------------------

## Effects of a given type from every tech the faction knows, plus its
## species' innate effects (data/strategic/species.json, same effect types).
static func tech_effects(engine: GalaxyEngine, faction_id: String, effect_type: String) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var species_id: String = engine.state.faction(faction_id).get("species", "")
	for e: Dictionary in engine.data.species.get(species_id, {}).get("effects", []):
		if e.get("type", "") == effect_type:
			out.append(e)
	for tech_id: String in engine.state.known_techs(faction_id):
		for e: Dictionary in engine.data.techs.get(tech_id, {}).get("effects", []):
			if e.get("type", "") == effect_type:
				out.append(e)
	return out


## Sum of "empire_modifier" effects for a stat (fleet_speed, sensor, field_repair).
static func modifier(engine: GalaxyEngine, faction_id: String, stat: String) -> float:
	var total := 0.0
	for e in tech_effects(engine, faction_id, "empire_modifier"):
		if e.get("stat", "") == stat:
			total += float(e.get("add", 0.0))
	return total


## Statuses every ship of the faction starts battles with (from techs).
static func ship_statuses(engine: GalaxyEngine, faction_id: String) -> Array[String]:
	var out: Array[String] = []
	for e in tech_effects(engine, faction_id, "ship_status"):
		out.append(e["status"])
	return out


static func building_unlocked(engine: GalaxyEngine, faction_id: String, building_id: String) -> bool:
	var req: String = engine.data.buildings[building_id].get("requires_tech", "")
	return req.is_empty() or req in engine.state.known_techs(faction_id)


static func unit_unlocked(engine: GalaxyEngine, faction_id: String, unit_id: String) -> bool:
	var req: String = engine.data.units[unit_id].get("strategic", {}).get("requires_tech", "")
	return req.is_empty() or req in engine.state.known_techs(faction_id)


# --- Economy ------------------------------------------------------------------

## Per-turn output of a system: every developed body's buildings, plus that
## body's type bonus and traits, times tech multipliers. Undeveloped bodies
## produce nothing: a world's riches only pay once you build there.
static func planet_yields(engine: GalaxyEngine, planet: Planet) -> Dictionary:
	var out := {}
	for b in planet.bodies:
		_add(out, body_yields(engine, b, planet.owner))
	if not planet.owner.is_empty():
		for e in tech_effects(engine, planet.owner, "yield"):
			if out.has(e["resource"]):
				out[e["resource"]] = float(out[e["resource"]]) * float(e.get("mul", 1.0))
	for k: String in out:
		out[k] = roundi(out[k])
	return out


## Output of one body before tech multipliers. `faction_id` (the owner) adds
## the faction's "body_bonus" tech effects; leave it empty for base output.
static func body_yields(engine: GalaxyEngine, b: Dictionary, faction_id: String = "") -> Dictionary:
	var out := {}
	if b["buildings"].is_empty():
		return out
	for building_id: String in b["buildings"]:
		_add(out, engine.data.buildings.get(building_id, {}).get("yields", {}))
	_add(out, engine.data.body_types.get(b["type"], {}).get("bonus", {}))
	for t: String in b["traits"]:
		_add(out, engine.data.planet_traits.get(t, {}).get("yields", {}))
	if not faction_id.is_empty():
		for e in tech_effects(engine, faction_id, "body_bonus"):
			if body_bonus_applies(engine, b, e):
				_add(out, e.get("yields", {}))
	return out


## Whether a "body_bonus" tech effect covers body `b`: it must match one of
## the effect's "body_types" / "categories" (an effect naming neither matches
## every body) and, if the effect names a "building", have that building.
static func body_bonus_applies(engine: GalaxyEngine, b: Dictionary, effect: Dictionary) -> bool:
	var types: Array = effect.get("body_types", [])
	var categories: Array = effect.get("categories", [])
	if (not types.is_empty() or not categories.is_empty()) \
			and b["type"] not in types and body_category(engine, b) not in categories:
		return false
	var building: String = effect.get("building", "")
	return building.is_empty() or building in b["buildings"]


## Credits a faction earns from trade with friendly minor powers: at peace
## and liked (opinion >= 30: +3, >= 60: +6 per minor power).
static func trade_income(engine: GalaxyEngine, faction_id: String) -> int:
	var total := 0
	var s := engine.state
	if s.faction(faction_id).get("role", "major") != "major":
		return 0
	for f in s.factions:
		if f.get("role", "") != "minor" or s.is_eliminated(f["id"]) or s.at_war(faction_id, f["id"]):
			continue
		var opinion := s.opinion(f["id"], faction_id)
		total += 6 if opinion >= 60 else (3 if opinion >= 30 else 0)
	return total


static func income(engine: GalaxyEngine, faction_id: String) -> Dictionary:
	var out := {"credits": trade_income(engine, faction_id), "alloys": 0, "research": 0}
	for p in engine.state.planets_of(faction_id):
		_add(out, planet_yields(engine, p))
	return out


static func can_afford(engine: GalaxyEngine, faction_id: String, cost: Dictionary) -> bool:
	var stock: Dictionary = engine.state.resources.get(faction_id, {})
	for k: String in cost:
		if int(stock.get(k, 0)) < int(cost[k]):
			return false
	return true


static func pay(engine: GalaxyEngine, faction_id: String, cost: Dictionary) -> void:
	var stock: Dictionary = engine.state.resources[faction_id]
	for k: String in cost:
		stock[k] = int(stock.get(k, 0)) - int(cost[k])


static func cost_text(engine: GalaxyEngine, cost: Dictionary) -> String:
	var parts := PackedStringArray()
	for k: String in cost:
		parts.append("%d %s" % [int(cost[k]), engine.data.resources.get(k, {}).get("name", k).to_lower()])
	return ", ".join(parts)


# --- Colonies -----------------------------------------------------------------

## Build spots in the system: one installation per body, plus each colony's
## colony-building slots.
static func slots(engine: GalaxyEngine, planet: Planet) -> int:
	var n := 0
	for b in planet.bodies:
		n += 1
		if is_habitable(engine, b):
			n += colony_slots(engine, b, planet.owner)
	return n


static func body_category(engine: GalaxyEngine, b: Dictionary) -> String:
	return engine.data.body_types.get(b["type"], {}).get("category", "")


static func is_habitable(engine: GalaxyEngine, b: Dictionary) -> bool:
	return body_category(engine, b) == "habitable"


## Colony buildings a colonised body can hold (type slots + traits + the
## owner's "body_bonus" tech effects).
static func colony_slots(engine: GalaxyEngine, b: Dictionary, faction_id: String = "") -> int:
	var n := int(engine.data.body_types.get(b["type"], {}).get("colony_slots", 0))
	for t: String in b["traits"]:
		n += int(engine.data.planet_traits.get(t, {}).get("slots", 0))
	if not faction_id.is_empty():
		for e in tech_effects(engine, faction_id, "body_bonus"):
			if body_bonus_applies(engine, b, e):
				n += int(e.get("colony_slots", 0))
	return n


## Why `building_id` can't go on body `b` ("" if it can, ignoring cost and queue).
static func body_build_error(engine: GalaxyEngine, b: Dictionary, building_id: String, faction_id: String = "") -> String:
	var def: Dictionary = engine.data.buildings.get(building_id, {})
	if def.has("on"):
		if body_category(engine, b) not in def["on"]:
			return "Can't be built on a %s" % engine.data.body_types.get(b["type"], {}).get("name", b["type"]).to_lower()
		if not b["buildings"].is_empty():
			return "This world is already developed"
		return ""
	if def.get("needs", "") == "colony":
		if "colony" not in b["buildings"]:
			return "Needs a colony on this world"
		if building_id in b["buildings"]:
			return "Already built here"
		if b["buildings"].size() - 1 >= colony_slots(engine, b, faction_id):
			return "No free colony slots"
		return ""
	return "Can't be built here"


static func has_shipyard(engine: GalaxyEngine, planet: Planet) -> bool:
	for b in planet.buildings:
		if engine.data.buildings.get(b, {}).get("shipyard", false):
			return true
	return false


## Unit ids of the planet's defenses (one per defense building).
static func defense_units(engine: GalaxyEngine, planet: Planet) -> Array[String]:
	var out: Array[String] = []
	for b in planet.buildings:
		var unit: String = engine.data.buildings.get(b, {}).get("defense_unit", "")
		if not unit.is_empty():
			out.append(unit)
	return out


## Everything the system could start building, with whether it's possible now:
## [{"kind", "id", "name", "body": body id or "", "cost", "turns", "ok": bool, "reason": String}]
## Buildings are only listed for bodies where they make sense.
static func build_options(engine: GalaxyEngine, planet: Planet) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var faction_id := planet.owner
	var busy := not planet.queue.is_empty()
	for b in planet.bodies:
		for b_id: String in engine.data.buildings:
			var def: Dictionary = engine.data.buildings[b_id]
			if not building_unlocked(engine, faction_id, b_id):
				continue
			var reason := body_build_error(engine, b, b_id, faction_id)
			# Hide what can never go here; show what's merely blocked for now.
			if def.has("on") and body_category(engine, b) not in def["on"]:
				continue
			if def.get("needs", "") == "colony" and "colony" not in b["buildings"]:
				continue
			if reason == "Already built here" or reason == "This world is already developed":
				continue
			var option := _option(engine, planet, "building", b_id, def.get("name", b_id), def.get("cost", {}),
					int(def.get("turns", 1)), reason, busy)
			option["body"] = b["id"]
			out.append(option)
	if has_shipyard(engine, planet):
		for u_id: String in engine.data.units:
			var strat: Dictionary = engine.data.units[u_id].get("strategic", {})
			if not strat.has("cost") or not unit_unlocked(engine, faction_id, u_id):
				continue
			var option := _option(engine, planet, "unit", u_id, engine.data.units[u_id].get("name", u_id),
					strat["cost"], int(strat.get("build_turns", 1)), "", busy)
			option["body"] = ""
			out.append(option)
	return out


static func _option(engine: GalaxyEngine, planet: Planet, kind: String, id: String, item_name: String,
		cost: Dictionary, turns: int, reason: String, busy: bool) -> Dictionary:
	if reason.is_empty() and busy:
		reason = "Already building something"
	if reason.is_empty() and not can_afford(engine, planet.owner, cost):
		reason = "Can't afford it"
	return {"kind": kind, "id": id, "name": item_name, "cost": cost, "turns": turns,
			"ok": reason.is_empty(), "reason": reason}


# --- Score --------------------------------------------------------------------

## Used to pick a winner when the war ends by treaty rather than conquest.
static func score(engine: GalaxyEngine, faction_id: String) -> int:
	var s := engine.state.planets_of(faction_id).size() * 100
	s += engine.state.known_techs(faction_id).size() * 25
	for f in engine.state.fleets_of(faction_id):
		for ship in f.ships:
			s += int(ship["hull"]) / 10
	for h in engine.state.heroes_of(faction_id):
		if h.status != Hero.DEAD and h.status != Hero.CAPTURED:
			s += h.level * 10
	return s


static func _add(into: Dictionary, values: Dictionary) -> void:
	for k: String in values:
		into[k] = into.get(k, 0) + values[k]
