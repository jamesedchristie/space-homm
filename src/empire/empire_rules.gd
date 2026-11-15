class_name EmpireRules
extends RefCounted
## Economy and technology effects: planet yields, income, what a planet can
## build and what it costs, and the bonuses a faction's techs give.
## Static helpers over GalaxyEngine state, so UI, AI and the engine agree.

const RESOURCES := ["credits", "alloys", "research"]
## Ships per fleet (the battle maps have 6 deployment slots per side).
const MAX_FLEET_SIZE := 6


# --- Technology effects -------------------------------------------------------

## Effects of a given type from every tech the faction knows.
static func tech_effects(engine: GalaxyEngine, faction_id: String, effect_type: String) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
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

## Per-turn output of a planet: type yields + building yields, times tech multipliers.
static func planet_yields(engine: GalaxyEngine, planet: Planet) -> Dictionary:
	var out := {}
	_add(out, engine.data.planet_types.get(planet.type, {}).get("yields", {}))
	for b in planet.buildings:
		_add(out, engine.data.buildings.get(b, {}).get("yields", {}))
	if not planet.owner.is_empty():
		for e in tech_effects(engine, planet.owner, "yield"):
			if out.has(e["resource"]):
				out[e["resource"]] = float(out[e["resource"]]) * float(e.get("mul", 1.0))
	for k: String in out:
		out[k] = roundi(out[k])
	return out


static func income(engine: GalaxyEngine, faction_id: String) -> Dictionary:
	var out := {"credits": 0, "alloys": 0, "research": 0}
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

static func slots(engine: GalaxyEngine, planet: Planet) -> int:
	return int(engine.data.planet_types.get(planet.type, {}).get("slots", 2))


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


## Everything the planet could start building, with whether it's possible now:
## [{"kind", "id", "name", "cost", "turns", "ok": bool, "reason": String}]
static func build_options(engine: GalaxyEngine, planet: Planet) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var faction_id := planet.owner
	var busy := not planet.queue.is_empty()
	for b_id: String in engine.data.buildings:
		var def: Dictionary = engine.data.buildings[b_id]
		if b_id in planet.buildings or not building_unlocked(engine, faction_id, b_id):
			continue
		var reason := ""
		if planet.buildings.size() >= slots(engine, planet):
			reason = "No free building slots"
		out.append(_option(engine, planet, "building", b_id, def.get("name", b_id), def.get("cost", {}),
				int(def.get("turns", 1)), reason, busy))
	if has_shipyard(engine, planet):
		for u_id: String in engine.data.units:
			var strat: Dictionary = engine.data.units[u_id].get("strategic", {})
			if not strat.has("cost") or not unit_unlocked(engine, faction_id, u_id):
				continue
			out.append(_option(engine, planet, "unit", u_id, engine.data.units[u_id].get("name", u_id),
					strat["cost"], int(strat.get("build_turns", 1)), "", busy))
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
