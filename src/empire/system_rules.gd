class_name SystemRules
extends RefCounted
## The system map level: civilian ships (colony ships, constructors) working
## inside a star system. Static helpers over GalaxyEngine state so the engine,
## UI and AI agree on what is possible.
##
## A civilian ship is "here" when it is deployed in the system (Planet.civilians)
## or sits in a fleet parked on the system's cell. Orders deploy it on demand.


## Every civilian ship of the faction in the system, deployed or in the fleet in orbit:
## [{"ship": Dictionary, "fleet": Fleet or null, "deployed": bool, "role": String}]
static func ships_here(engine: GalaxyEngine, planet: Planet, faction_id: String) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for c in planet.civilians:
		if c["owner"] == faction_id:
			out.append({"ship": c, "fleet": null, "deployed": true, "role": Fleet.role_of(engine.data, c["unit"])})
	var fleet := engine.state.fleet_at(planet.cell)
	if fleet != null and fleet.owner == faction_id:
		for ship in fleet.ships:
			var role := Fleet.role_of(engine.data, ship["unit"])
			if role == "colony" or role == "constructor":
				out.append({"ship": ship, "fleet": fleet, "deployed": false, "role": role})
	return out


static func find_ship(engine: GalaxyEngine, planet: Planet, faction_id: String, uid: String) -> Dictionary:
	for entry in ships_here(engine, planet, faction_id):
		if entry["ship"]["uid"] == uid:
			return entry
	return {}


## Ships of the faction working a job in the system.
static func workers(planet: Planet, faction_id: String = "") -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for c in planet.civilians:
		if not c["job"].is_empty() and (faction_id.is_empty() or c["owner"] == faction_id):
			out.append(c)
	return out


static func job_on_body(planet: Planet, body_id: String) -> Dictionary:
	for c in planet.civilians:
		if not c["job"].is_empty() and c["job"]["body"] == body_id:
			return c
	return {}


## Whether the faction may develop or settle in this system: it is unclaimed or its own.
static func may_work_in(planet: Planet, faction_id: String) -> bool:
	return planet.owner.is_empty() or planet.owner == faction_id


## Why a colony can't be founded on `b` by `faction_id` ("" if it can).
static func found_error(engine: GalaxyEngine, planet: Planet, b: Dictionary, faction_id: String) -> String:
	if b.is_empty():
		return "No such body"
	if not may_work_in(planet, faction_id):
		return "Another power holds this system"
	if planet.is_blockaded():
		return "The system is blockaded"
	if not EmpireRules.is_habitable(engine, b):
		return "Only habitable worlds can be colonised"
	if not b["buildings"].is_empty():
		return "This world is already settled"
	if not job_on_body(planet, b["id"]).is_empty():
		return "A constructor is working there"
	return ""


## Why a constructor can't start `building_id` on body `b` ("" if it can).
static func job_error(engine: GalaxyEngine, planet: Planet, b: Dictionary, faction_id: String, building_id: String) -> String:
	if b.is_empty():
		return "No such body"
	if not may_work_in(planet, faction_id):
		return "Another power holds this system"
	if planet.is_blockaded():
		return "The system is blockaded"
	if not job_on_body(planet, b["id"]).is_empty():
		return "A constructor is already working there"
	for o in EmpireRules.constructor_options(engine, faction_id, b):
		if o["id"] == building_id:
			return o["reason"]
	return "Can't be built there"


## Validation of a CivilianCommand: "" if it can be carried out now.
static func command_error(engine: GalaxyEngine, cmd: CivilianCommand) -> String:
	var planet: Planet = engine.state.planets.get(cmd.planet_id)
	if planet == null:
		return "No such system"
	var entry := find_ship(engine, planet, cmd.faction_id, cmd.ship_uid)
	if entry.is_empty():
		return "That ship isn't in this system"
	var role: String = entry["role"]
	var b := planet.body(cmd.body_id)
	match cmd.action:
		CivilianCommand.MOVE:
			if b.is_empty():
				return "No such body"
			if not entry["ship"].get("job", {}).is_empty():
				return "That ship is working"
		CivilianCommand.JOB:
			if role != "constructor":
				return "Only a Constructor can build developments"
			if not entry["ship"].get("job", {}).is_empty():
				return "That ship is already working"
			return job_error(engine, planet, b, cmd.faction_id, cmd.item_id)
		CivilianCommand.FOUND:
			if role != "colony":
				return "Only a Colony Ship can found a colony"
			return found_error(engine, planet, b, cmd.faction_id)
		CivilianCommand.DEPART:
			if not entry["deployed"]:
				return "That ship is already in orbit"
			if not entry["ship"]["job"].is_empty():
				return "That ship is working"
			var fleet := engine.state.fleet_at(planet.cell)
			if fleet != null and (fleet.owner != cmd.faction_id or fleet.ships.size() >= EmpireRules.MAX_FLEET_SIZE):
				return "No room in orbit"
		CivilianCommand.CANCEL:
			if not entry["deployed"] or entry["ship"]["job"].is_empty():
				return "That ship has no job"
		_:
			return "Unknown order"
	return ""


## Colony targets in the system for a faction: habitable bodies a Colony Ship could settle.
static func colony_targets(engine: GalaxyEngine, planet: Planet, faction_id: String) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for b in planet.bodies:
		if found_error(engine, planet, b, faction_id).is_empty():
			out.append(b)
	return out


## Bodies in the system where a Constructor could build something now, with their options.
static func development_targets(engine: GalaxyEngine, planet: Planet, faction_id: String) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if not may_work_in(planet, faction_id) or planet.is_blockaded():
		return out
	for b in planet.bodies:
		if not job_on_body(planet, b["id"]).is_empty():
			continue
		var options := EmpireRules.constructor_options(engine, faction_id, b).filter(
				func(o: Dictionary) -> bool: return o["reason"].is_empty() or EmpireRules.lacks_resources(o["reason"]))
		if not options.is_empty():
			out.append({"body": b, "options": options})
	return out


# --- Standing orders (OrderShipCommand) -------------------------------------------

## Where a faction's civilian ship is: {"planet": Planet, "ship": Dictionary} when deployed in a
## system, {"fleet": Fleet, "ship": Dictionary} when riding in a fleet, {} if not found.
static func locate_ship(engine: GalaxyEngine, faction_id: String, uid: String) -> Dictionary:
	for p: Planet in engine.state.planets.values():
		for c in p.civilians:
			if c["uid"] == uid and c["owner"] == faction_id:
				return {"planet": p, "ship": c}
	for f in engine.state.fleets_of(faction_id):
		for s in f.ships:
			if s["uid"] == uid:
				return {"fleet": f, "ship": s}
	return {}


## The development a constructor builds on `b` by default: the one that taps the richest deposit the
## faction knows of there (exotic matter first), else the first fitting option that isn't a bare outpost
## (mining base, research station, refinery...), else an outpost. "" if none fits. `planet` (the body's
## system) limits the deposits to what the faction has surveyed; without it every deposit counts.
static func default_job(engine: GalaxyEngine, faction_id: String, b: Dictionary, planet: Planet = null) -> String:
	if b.is_empty():
		return ""
	var deposits := engine.known_deposits(faction_id, planet, b) if planet != null else DepositRules.of(b)
	var strategic := DepositRules.strategic(engine.data)
	var fallback := ""
	var first := ""
	var best := ""
	var best_value := 0.0
	for o in EmpireRules.constructor_options(engine, faction_id, b):
		if not (o["reason"].is_empty() or EmpireRules.lacks_resources(o["reason"])):
			continue
		if o["id"] == "outpost":
			fallback = "outpost"
			continue
		if first.is_empty():
			first = o["id"]
		var value := 0.0
		for resource: String in engine.data.buildings[o["id"]].get("extracts", []):
			if deposits.has(resource):
				# Rarer resources weigh more: exotic matter beats rare elements beats volatiles.
				value += float(deposits[resource]) * (1.0 + strategic.find(resource))
		if value > best_value:
			best_value = value
			best = o["id"]
	if not best.is_empty():
		return best
	return first if not first.is_empty() else fallback


## What an order would do there, for hints: "Build Mining Base" / "Found a colony" / "" if nothing.
static func order_label(engine: GalaxyEngine, faction_id: String, role: String, planet: Planet, b: Dictionary) -> String:
	if role == "colony":
		return "Found a colony" if found_error(engine, planet, b, faction_id).is_empty() else ""
	if role == "constructor":
		var item := default_job(engine, faction_id, b, planet)
		if item.is_empty() or not job_on_body(planet, b["id"]).is_empty() or not may_work_in(planet, faction_id):
			return ""
		return "Build %s" % engine.data.buildings[item].get("name", item)
	return ""


static func order_error(engine: GalaxyEngine, cmd: OrderShipCommand) -> String:
	var where := locate_ship(engine, cmd.faction_id, cmd.ship_uid)
	if where.is_empty():
		return "No such ship"
	var role := Fleet.role_of(engine.data, where["ship"]["unit"])
	var planet: Planet = engine.state.planets.get(cmd.planet_id)
	if planet == null:
		return "No such system"
	var b := planet.body(cmd.body_id)
	if b.is_empty():
		return "No such body"
	if where.has("planet") and not where["ship"].get("job", {}).is_empty():
		return "That ship is working"
	match cmd.action:
		OrderShipCommand.FOUND:
			if role != "colony":
				return "Only a Colony Ship can found a colony"
			return found_error(engine, planet, b, cmd.faction_id)
		OrderShipCommand.JOB:
			if role != "constructor":
				return "Only a Constructor can build developments"
			var item := cmd.item_id if not cmd.item_id.is_empty() else default_job(engine, cmd.faction_id, b, planet)
			if item.is_empty():
				return "Nothing a Constructor can build there"
			var err := job_error(engine, planet, b, cmd.faction_id, item)
			return "" if EmpireRules.lacks_resources(err) else err
	return "Unknown order"
