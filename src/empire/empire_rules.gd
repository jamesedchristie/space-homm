class_name EmpireRules
extends RefCounted
## Economy and technology effects: planet yields, income, what a planet can
## build and what it costs, and the bonuses a faction's techs give.
## Static helpers over GalaxyEngine state, so UI, AI and the engine agree.

## Ships per fleet (the battle maps have 6 deployment slots per side).
const MAX_FLEET_SIZE := 6
## Every "can't pay for it" reason starts with this (see afford_error / lacks_resources).
const NOT_ENOUGH := "Not enough "


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
	for mp_id in megaprojects_of(engine, faction_id):
		for e: Dictionary in engine.data.megaprojects.get(mp_id, {}).get("effects", []):
			if e.get("type", "") == effect_type:
				out.append(e)
	for m: Dictionary in engine.state.modifiers.get(faction_id, []):
		for e: Dictionary in m.get("effects", []):
			if e.get("type", "") == effect_type:
				out.append(e)
	return out


## Megaproject ids standing in systems the faction holds (each id once).
static func megaprojects_of(engine: GalaxyEngine, faction_id: String) -> Array[String]:
	var out: Array[String] = []
	for p in engine.state.planets_of(faction_id):
		for id in p.megaprojects:
			if id not in out:
				out.append(id)
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
	if planet.is_blockaded():
		return out  # an enemy fleet in orbit halts production
	for b in planet.bodies:
		_add(out, body_yields(engine, b, planet.owner))
	for mp_id in planet.megaprojects:
		_add(out, engine.data.megaprojects.get(mp_id, {}).get("yields", {}))
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
	if b["buildings"].is_empty() or is_offline(engine, b):
		return out
	var extra_pop := maxi(pop(b) - 1, 0)
	for building_id: String in b["buildings"]:
		var def: Dictionary = engine.data.buildings.get(building_id, {})
		_add(out, def.get("yields", {}))
		if extra_pop > 0:
			var per_pop: Dictionary = def.get("pop_yields", {})
			for k: String in per_pop:
				out[k] = float(out.get(k, 0.0)) + float(per_pop[k]) * extra_pop
	_add(out, engine.data.body_types.get(b["type"], {}).get("bonus", {}))
	for t: String in b["traits"]:
		_add(out, engine.data.planet_traits.get(t, {}).get("yields", {}))
	if not faction_id.is_empty():
		for e in tech_effects(engine, faction_id, "body_bonus"):
			if body_bonus_applies(engine, b, e):
				_add(out, e.get("yields", {}))
	_add(out, DepositRules.extraction(engine.data, b))  # strategic deposits its developments tap
	return out


## A development knocked offline (a raid, a mining accident) yields nothing until its
## "offline_until" turn comes round.
static func is_offline(engine: GalaxyEngine, b: Dictionary) -> bool:
	return int(b.get("offline_until", 0)) > engine.state.turn_number


## Turns until an offline development is back (0 when it works).
static func offline_turns(engine: GalaxyEngine, b: Dictionary) -> int:
	return maxi(int(b.get("offline_until", 0)) - engine.state.turn_number, 0)


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
		var base := 6 if opinion >= 60 else (3 if opinion >= 30 else 0)
		if base > 0:
			base += int(modifier(engine, faction_id, "trade_income"))
		total += base
	return total


## Per-turn income. "credits" is net of ship upkeep; "gross_credits" and "upkeep"
## show the two halves.
static func income(engine: GalaxyEngine, faction_id: String) -> Dictionary:
	var out := {"credits": trade_income(engine, faction_id), "alloys": 0, "research": 0}
	for k in DepositRules.strategic(engine.data):
		out[k] = 0
	for p in engine.state.planets_of(faction_id):
		_add(out, planet_yields(engine, p))
	var cost := upkeep(engine, faction_id)
	out["gross_credits"] = out["credits"]
	out["upkeep"] = cost
	out["credits"] = int(out["credits"]) - cost
	return out


static func can_afford(engine: GalaxyEngine, faction_id: String, cost: Dictionary) -> bool:
	return afford_error(engine, faction_id, cost).is_empty()


## Why the faction can't pay `cost` now, naming the first missing resource
## ("Not enough rare elements (6 needed, 2 in store)"), or "" if it can.
static func afford_error(engine: GalaxyEngine, faction_id: String, cost: Dictionary) -> String:
	var stock: Dictionary = engine.state.resources.get(faction_id, {})
	for k: String in cost:
		if int(stock.get(k, 0)) < int(cost[k]):
			return "%s%s (%d needed, %d in store)" % [NOT_ENOUGH, engine.data.resources.get(k, {}).get("name", k).to_lower(),
					int(cost[k]), int(stock.get(k, 0))]
	return ""


## Whether a build reason only says the faction is short of resources (it could save up for it).
static func lacks_resources(reason: String) -> bool:
	return reason.begins_with(NOT_ENOUGH)


## A cost as the campaign charges it: strategic resources scaled by the campaign's
## "strategic_cost_mul" (galaxy-scale campaigns ask less), zeros dropped.
static func cost_of(engine: GalaxyEngine, cost: Dictionary) -> Dictionary:
	var mul := float(engine.campaign.get("strategic_cost_mul", 1.0))
	var out := {}
	for k: String in cost:
		var n := int(cost[k])
		if mul != 1.0 and DepositRules.is_strategic(engine.data, k):
			n = maxi(roundi(float(n) * mul), 1) if n > 0 else 0
		if n != 0:
			out[k] = n
	return out


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
## Body developments ("on") are built by Constructors; colony buildings ("needs") are queued.
static func body_build_error(engine: GalaxyEngine, b: Dictionary, building_id: String, faction_id: String = "") -> String:
	var def: Dictionary = engine.data.buildings.get(building_id, {})
	if def.has("on"):
		if def.get("founded", false):
			return "Founded by a Colony Ship"
		if body_category(engine, b) not in def["on"]:
			return "Can't be built on a %s" % engine.data.body_types.get(b["type"], {}).get("name", b["type"]).to_lower()
		# An outpost is a placeholder claim: a real development may replace it (and some, like an
		# Exotic Containment, may replace any of the developments listed in their "replaces").
		var replaceable: Array = def.get("replaces", [])
		if building_id != "outpost" and not replaceable.has("outpost"):
			replaceable = replaceable + ["outpost"]
		var replaces_all := true
		for existing: String in b["buildings"]:
			replaces_all = replaces_all and existing in replaceable and existing != building_id
		if not b["buildings"].is_empty() and not replaces_all:
			return "This world is already developed"
		var deposit: String = def.get("needs_deposit", "")
		if not deposit.is_empty() and not DepositRules.of(b).has(deposit):
			return "Needs %s here" % engine.data.resources.get(deposit, {}).get("name", deposit).to_lower()
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


## What a Constructor could start on body `b`: [{"id", "name", "cost", "turns", "ok", "reason"}].
## Only developments that suit the body are listed (an extractor that needs a deposit only where
## there is one); "reason" says what blocks one now.
static func constructor_options(engine: GalaxyEngine, faction_id: String, b: Dictionary) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for b_id: String in engine.data.buildings:
		var def: Dictionary = engine.data.buildings[b_id]
		if not def.has("on") or def.get("founded", false) or body_category(engine, b) not in def["on"]:
			continue
		if not building_unlocked(engine, faction_id, b_id):
			continue
		if def.has("needs_deposit") and not DepositRules.of(b).has(def["needs_deposit"]):
			continue
		var reason := body_build_error(engine, b, b_id, faction_id)
		if reason.begins_with("This world is already"):
			continue
		var cost := cost_of(engine, def.get("cost", {}))
		if reason.is_empty():
			reason = afford_error(engine, faction_id, cost)
		out.append({"id": b_id, "name": def.get("name", b_id), "cost": cost, "turns": int(def.get("turns", 1)),
				"ok": reason.is_empty(), "reason": reason})
	return out


static func has_shipyard(engine: GalaxyEngine, planet: Planet) -> bool:
	for b in planet.buildings:
		if engine.data.buildings.get(b, {}).get("shipyard", false):
			return true
	return false


## Unit ids of the buildings' defenses (one per defense building).
static func building_defense_units(engine: GalaxyEngine, planet: Planet) -> Array[String]:
	var out: Array[String] = []
	for b in planet.buildings:
		var unit: String = engine.data.buildings.get(b, {}).get("defense_unit", "")
		if not unit.is_empty():
			out.append(unit)
	return out


## The base garrison every claimed system fields: orbital batteries, one plus one
## per few population (economy.json "garrison"). None while the system is blockaded
## (the garrison is already beaten) or unclaimed.
static func garrison_units(engine: GalaxyEngine, planet: Planet) -> Array[String]:
	var out: Array[String] = []
	if planet.owner.is_empty() or planet.is_blockaded():
		return out
	if engine.state.faction(planet.owner).get("role", "") == "barbarian":
		return out  # raider dens rely on their own platforms
	var cfg: Dictionary = engine.data.economy.get("garrison", {})
	var unit: String = cfg.get("unit", "")
	if unit.is_empty() or not engine.data.units.has(unit):
		return out
	var n := int(cfg.get("base", 1)) + planet.population() / maxi(int(cfg.get("pop_per_extra", 4)), 1)
	n = mini(n, int(cfg.get("max", 3)))
	for i in n:
		out.append(unit)
	return out


## Everything that fights an attacker in the system: defense buildings, then the base garrison.
static func defense_units(engine: GalaxyEngine, planet: Planet) -> Array[String]:
	var out := building_defense_units(engine, planet)
	out.append_array(garrison_units(engine, planet))
	return out


# --- Population ---------------------------------------------------------------

## Population of a colony body (0 for bodies without a colony).
static func pop(b: Dictionary) -> int:
	return int(b.get("pop", Planet.START_POP)) if "colony" in b["buildings"] else 0


## Most population the colony can hold: body type + traits + its buildings
## + the owner's "body_bonus" tech effects (min 1).
static func pop_cap(engine: GalaxyEngine, b: Dictionary, faction_id: String = "") -> int:
	var n := int(engine.data.body_types.get(b["type"], {}).get("pop_cap", 0))
	for t: String in b["traits"]:
		n += int(engine.data.planet_traits.get(t, {}).get("pop_cap", 0))
	for building_id: String in b["buildings"]:
		n += int(engine.data.buildings.get(building_id, {}).get("pop_cap", 0))
	if not faction_id.is_empty():
		for e in tech_effects(engine, faction_id, "body_bonus"):
			if body_bonus_applies(engine, b, e):
				n += int(e.get("pop_cap", 0))
	return maxi(n, 1)


## Growth progress a colony makes per turn: the base rate plus growth techs,
## megaprojects and buildings, slowing as it fills up (0 at the cap).
static func growth_rate(engine: GalaxyEngine, b: Dictionary, faction_id: String = "") -> float:
	var cap := pop_cap(engine, b, faction_id)
	var current := pop(b)
	if current <= 0 or current >= cap:
		return 0.0
	var growth_cfg: Dictionary = engine.data.economy.get("growth", {})
	var rate := float(growth_cfg.get("base", 1.0))
	for building_id: String in b["buildings"]:
		rate += float(engine.data.buildings.get(building_id, {}).get("growth", 0.0))
	if not faction_id.is_empty():
		rate += modifier(engine, faction_id, "growth")
		for e in tech_effects(engine, faction_id, "body_bonus"):
			if body_bonus_applies(engine, b, e):
				rate += float(e.get("growth", 0.0))
	var slowdown := float(growth_cfg.get("slowdown", 0.5))
	return maxf(rate, 0.0) * (1.0 - slowdown * float(current) / float(cap))


## Progress needed for a colony of `current` population to gain one.
static func growth_cost(engine: GalaxyEngine, current: int) -> float:
	var growth_cfg: Dictionary = engine.data.economy.get("growth", {})
	return float(growth_cfg.get("cost_base", 5.0)) + float(growth_cfg.get("cost_per_pop", 1.5)) * current


## Turns until the colony's next pop at its current rate (-1 when full or stalled).
static func turns_to_grow(engine: GalaxyEngine, b: Dictionary, faction_id: String) -> int:
	var rate := growth_rate(engine, b, faction_id)
	if rate <= 0.0:
		return -1
	var left := growth_cost(engine, pop(b)) - float(b.get("growth", 0.0))
	return maxi(ceili(left / rate), 1)


static func total_population(engine: GalaxyEngine, faction_id: String) -> int:
	var n := 0
	for p in engine.state.planets_of(faction_id):
		n += p.population()
	return n


static func colony_count(engine: GalaxyEngine, faction_id: String) -> int:
	var n := 0
	for p in engine.state.planets_of(faction_id):
		n += p.colonies().size()
	return n


## Sensor range of a system: its base plus Sensor Arrays (tech bonuses are added by the engine).
static func planet_sensor(engine: GalaxyEngine, planet: Planet) -> int:
	var n := planet.sensor
	for building_id in planet.buildings:
		n += int(engine.data.buildings.get(building_id, {}).get("sensor", 0))
	return n


## XP every fleet commander earns each turn: Fleet Academies plus tech/megaproject bonuses.
static func hero_xp_per_turn(engine: GalaxyEngine, faction_id: String) -> int:
	var n := 0
	for p in engine.state.planets_of(faction_id):
		for building_id in p.buildings:
			n += int(engine.data.buildings.get(building_id, {}).get("hero_xp", 0))
	return n + int(modifier(engine, faction_id, "hero_xp"))


# --- Upkeep -------------------------------------------------------------------

## Credits per turn a ship of this class costs to keep.
static func ship_upkeep(engine: GalaxyEngine, unit_id: String) -> int:
	return int(engine.data.units.get(unit_id, {}).get("strategic", {}).get("upkeep", 0))


## Total upkeep of every ship the faction has, before the free allowance.
static func fleet_upkeep(engine: GalaxyEngine, faction_id: String) -> int:
	var n := 0
	for f in engine.state.fleets_of(faction_id):
		for ship in f.ships:
			n += ship_upkeep(engine, ship["unit"])
	for p: Planet in engine.state.planets.values():
		for c in p.civilians:  # workers deployed in a system still cost upkeep
			if c["owner"] == faction_id:
				n += ship_upkeep(engine, c["unit"])
	return n


## Upkeep a faction's colonies carry for free: a base plus some per colony.
static func free_upkeep(engine: GalaxyEngine, faction_id: String) -> int:
	var cfg: Dictionary = engine.data.economy.get("upkeep", {})
	return int(cfg.get("free_base", 3)) + int(cfg.get("free_per_colony", 2)) * colony_count(engine, faction_id)


## Credits per turn the faction pays for its ships (major powers only), after
## the free allowance and upkeep-reducing techs.
static func upkeep(engine: GalaxyEngine, faction_id: String) -> int:
	return upkeep_for(engine, faction_id, fleet_upkeep(engine, faction_id))


## Upkeep the faction would pay if its ships added up to `gross` credits.
static func upkeep_for(engine: GalaxyEngine, faction_id: String, gross: int) -> int:
	if engine.state.faction(faction_id).get("role", "major") != "major":
		return 0
	var mul := maxf(1.0 + modifier(engine, faction_id, "upkeep"), 0.0)
	return maxi(ceili(float(gross) * mul) - free_upkeep(engine, faction_id), 0)


# --- Megaprojects -------------------------------------------------------------

static func megaproject_unlocked(engine: GalaxyEngine, faction_id: String, mp_id: String) -> bool:
	var req: String = engine.data.megaprojects[mp_id].get("requires_tech", "")
	return req.is_empty() or req in engine.state.known_techs(faction_id)


## System of the faction (or anywhere when `faction_id` is empty) currently
## building the megaproject, or null.
static func megaproject_under_construction(engine: GalaxyEngine, mp_id: String, faction_id: String = "") -> Planet:
	for p: Planet in engine.state.planets.values():
		if p.queue.get("kind", "") == "megaproject" and p.queue.get("item", "") == mp_id \
				and (faction_id.is_empty() or p.owner == faction_id):
			return p
	return null


## System anywhere in the galaxy where the megaproject stands, or null.
static func megaproject_site(engine: GalaxyEngine, mp_id: String, faction_id: String = "") -> Planet:
	for p: Planet in engine.state.planets.values():
		if mp_id in p.megaprojects and (faction_id.is_empty() or p.owner == faction_id):
			return p
	return null


## Why `mp_id` can't start in this system ("" if it can, ignoring cost and queue).
static func megaproject_error(engine: GalaxyEngine, planet: Planet, mp_id: String) -> String:
	var def: Dictionary = engine.data.megaprojects[mp_id]
	var faction_id := planet.owner
	if not megaproject_unlocked(engine, faction_id, mp_id):
		return "Needs %s" % engine.data.techs.get(def.get("requires_tech", ""), {}).get("name", "a technology")
	if "colony" not in planet.buildings:
		return "Needs a colony in the system"
	if mp_id in planet.megaprojects:
		return "Already built here"
	if def.get("scope", "empire") == "galaxy":
		var site := megaproject_site(engine, mp_id)
		if site != null:
			return "Already built at %s" % site.name
		var rival := megaproject_under_construction(engine, mp_id)
		if rival != null and rival != planet:
			return "Being built at %s" % rival.name
	else:
		var own := megaproject_site(engine, mp_id, faction_id)
		if own != null:
			return "Your empire already has it (%s)" % own.name
		var building := megaproject_under_construction(engine, mp_id, faction_id)
		if building != null and building != planet:
			return "Already being built at %s" % building.name
	return ""


## Whether the victory this megaproject grants is switched on in this campaign.
static func megaproject_hidden(engine: GalaxyEngine, mp_id: String) -> bool:
	var kind: String = engine.data.megaprojects[mp_id].get("victory", "")
	return not kind.is_empty() and not VictoryRules.enabled(engine, kind)


## Everything the system could start building, with whether it's possible now:
## [{"kind", "id", "name", "body": body id or "", "cost", "turns", "ok": bool, "reason": String}]
## The queue builds colony buildings (shipyard, trade hub...), megaprojects and ships; body
## developments (mining bases, research stations...) are built by Constructors instead
## (see constructor_options).
static func build_options(engine: GalaxyEngine, planet: Planet) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var faction_id := planet.owner
	var busy := not planet.queue.is_empty()
	var blockaded := planet.is_blockaded()
	for b in planet.bodies:
		for b_id: String in engine.data.buildings:
			var def: Dictionary = engine.data.buildings[b_id]
			if def.get("needs", "") != "colony" or "colony" not in b["buildings"]:
				continue
			if not building_unlocked(engine, faction_id, b_id):
				continue
			var reason := body_build_error(engine, b, b_id, faction_id)
			if reason == "Already built here":
				continue
			var option := _option(engine, planet, "building", b_id, def.get("name", b_id), cost_of(engine, def.get("cost", {})),
					int(def.get("turns", 1)), reason, busy, blockaded)
			option["body"] = b["id"]
			out.append(option)
	if "colony" in planet.buildings:
		for mp_id: String in engine.data.megaprojects:
			if not megaproject_unlocked(engine, faction_id, mp_id) or megaproject_hidden(engine, mp_id):
				continue
			var mp: Dictionary = engine.data.megaprojects[mp_id]
			var reason := megaproject_error(engine, planet, mp_id)
			if reason.begins_with("Already built") or reason.begins_with("Your empire already"):
				continue
			var option := _option(engine, planet, "megaproject", mp_id, mp.get("name", mp_id), cost_of(engine, mp.get("cost", {})),
					int(mp.get("turns", 8)), reason, busy, blockaded)
			option["body"] = ""
			out.append(option)
	for u_id: String in engine.data.units:
		var strat: Dictionary = engine.data.units[u_id].get("strategic", {})
		if not strat.has("cost") or not unit_unlocked(engine, faction_id, u_id):
			continue
		var reason := ""
		if bool(strat.get("civilian", false)):
			reason = civilian_build_error(engine, planet, u_id)
		elif not has_shipyard(engine, planet):
			continue
		var option := _option(engine, planet, "unit", u_id, engine.data.units[u_id].get("name", u_id),
				cost_of(engine, strat["cost"]), int(strat.get("build_turns", 1)), reason, busy, blockaded)
		option["body"] = ""
		out.append(option)
	return out


## Civilian ships need a colony; some need people to spare ("min_pop": a colony of at least that size).
static func civilian_build_error(engine: GalaxyEngine, planet: Planet, unit_id: String) -> String:
	var strat: Dictionary = engine.data.units[unit_id].get("strategic", {})
	if planet.colonies().is_empty():
		return "Needs a colony in the system"
	var min_pop := int(strat.get("min_pop", 0))
	if min_pop > 0 and pop_donor(planet, min_pop).is_empty():
		return "Needs a colony of %d+ population" % min_pop
	return ""


## The colony that gives up population for a ship (the biggest one with at least `min_pop`), or {}.
static func pop_donor(planet: Planet, min_pop: int) -> Dictionary:
	var best: Dictionary = {}
	for b in planet.colonies():
		if pop(b) >= min_pop and (best.is_empty() or pop(b) > pop(best)):
			best = b
	return best


static func _option(engine: GalaxyEngine, planet: Planet, kind: String, id: String, item_name: String,
		cost: Dictionary, turns: int, reason: String, busy: bool, blockaded: bool = false) -> Dictionary:
	if reason.is_empty() and blockaded:
		reason = "Blockaded"
	if reason.is_empty() and busy:
		reason = "Already building something"
	if reason.is_empty():
		reason = afford_error(engine, planet.owner, cost)
	return {"kind": kind, "id": id, "name": item_name, "cost": cost, "turns": turns,
			"ok": reason.is_empty(), "reason": reason}


# --- Score --------------------------------------------------------------------

## Used to pick a winner when the war ends by treaty or at the turn limit.
static func score(engine: GalaxyEngine, faction_id: String) -> int:
	var s := engine.state.planets_of(faction_id).size() * 100
	s += engine.state.known_techs(faction_id).size() * 25
	s += total_population(engine, faction_id) * int(engine.data.economy.get("pop_score", 8))
	s += megaprojects_of(engine, faction_id).size() * int(engine.data.economy.get("megaproject_score", 150))
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
