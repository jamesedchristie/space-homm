class_name EventRules
extends RefCounted
## Galactic events (data/strategic/events.json): every few turns a major
## faction may be offered an event with 2-3 choices. This class decides which
## events can happen (conditions), rolls one from the campaign's seeded RNG,
## lists the choices (with costs and requirements) and applies the outcome.
## The engine owns the state (GalaxyState.pending_event) and the commands.
##
## Only campaigns that opt in ("events": true in the campaign file) get events.

const CONDITIONS := ["has_colony", "growing_colony", "pop_min", "min_colonies", "turn_min", "turn_max",
		"at_war", "at_war_major", "at_peace_minor", "barbarians", "has_building", "has_shipyard", "has_fleet",
		"researching", "credits_min", "credits_max", "tech_known", "has_hero",
		"scale", "story_step", "stock_min", "extracting", "faction_alive", "developed_min"]
const EFFECTS := ["resources", "research", "pop", "damage_building", "free_building", "repair_fleets",
		"damage_fleets", "opinion", "raiders", "free_ship", "free_hero", "modifier", "item", "offline"]
const OPINION_TARGETS := ["minor", "random_major", "war_target", "all_majors"]
const POP_TARGETS := ["context", "random", "all", "largest"]


static func enabled(engine: GalaxyEngine) -> bool:
	return bool(engine.campaign.get("events", false))


static func config(engine: GalaxyEngine, key: String, default: Variant) -> Variant:
	return engine.data.economy.get("events", {}).get(key, default)


# --- Content checks -----------------------------------------------------------

static func validate_event(data: DataRegistry, id: String, def: Dictionary) -> void:
	var owner := "event '%s'" % id
	if def.get("text", "").is_empty() or def.get("name", "").is_empty():
		data._err("%s: needs a name and text" % owner)
	var choices: Array = def.get("choices", [])
	if choices.size() < 2 or choices.size() > 3:
		data._err("%s: needs 2-3 choices" % owner)
	_validate_conditions(data, owner, def.get("conditions", []))
	for c: Dictionary in choices:
		var label := "%s choice '%s'" % [owner, c.get("label", "")]
		if c.get("label", "").is_empty() or c.get("result", "").is_empty():
			data._err("%s: needs a label and result" % label)
		_validate_conditions(data, label, c.get("requires", []))
		for k: String in c.get("cost", {}):
			if not data.resources.has(k):
				data._err("%s: unknown cost resource '%s'" % [label, k])
		var all_effects: Array = c.get("effects", []).duplicate()
		all_effects.append_array(c.get("fail_effects", []))
		for fx: Dictionary in all_effects:
			_validate_effect(data, label, fx)
		if c.has("chance") and not c.has("fail_effects") and float(c["chance"]) < 1.0:
			data._err("%s: a chance below 1 needs fail_effects" % label)


static func _validate_conditions(data: DataRegistry, owner: String, conditions: Array) -> void:
	for cond: Dictionary in conditions:
		if cond.get("type", "") not in CONDITIONS:
			data._err("%s: unknown condition '%s'" % [owner, cond.get("type", "")])
		elif cond["type"] == "has_building" and not data.buildings.has(cond.get("building", "")):
			data._err("%s: unknown building '%s'" % [owner, cond.get("building", "")])
		elif cond["type"] == "tech_known" and not data.techs.has(cond.get("tech", "")):
			data._err("%s: unknown tech '%s'" % [owner, cond.get("tech", "")])
		elif cond["type"] in ["stock_min", "extracting"] and not DepositRules.stockpiled(data).has(cond.get("resource", "")):
			data._err("%s: unknown resource '%s'" % [owner, cond.get("resource", "")])
		elif cond["type"] == "scale" and cond.get("scale", "") not in ["galaxy", "system"]:
			data._err("%s: scale must be 'galaxy' or 'system'" % owner)


static func _validate_effect(data: DataRegistry, owner: String, fx: Dictionary) -> void:
	var kind: String = fx.get("type", "")
	if kind not in EFFECTS:
		data._err("%s: unknown effect '%s'" % [owner, kind])
		return
	match kind:
		"resources":
			for k: String in fx:
				if k != "type" and not data.resources.has(k):
					data._err("%s: unknown resource '%s'" % [owner, k])
		"pop":
			if fx.get("target", "context") not in POP_TARGETS:
				data._err("%s: unknown pop target '%s'" % [owner, fx.get("target", "")])
		"opinion":
			if fx.get("with", "") not in OPINION_TARGETS:
				data._err("%s: unknown opinion target '%s'" % [owner, fx.get("with", "")])
		"free_ship":
			if not data.units.has(fx.get("unit", "")):
				data._err("%s: unknown unit '%s'" % [owner, fx.get("unit", "")])
		"free_building":
			if not data.buildings.has(fx.get("building", "")):
				data._err("%s: unknown building '%s'" % [owner, fx.get("building", "")])
		"item":
			if not data.items.has(fx.get("item", "")):
				data._err("%s: unknown item '%s'" % [owner, fx.get("item", "")])
		"modifier":
			if fx.get("id", "").is_empty() or int(fx.get("turns", 0)) <= 0:
				data._err("%s: a modifier needs an id and turns" % owner)
			for e: Dictionary in fx.get("effects", []):
				if e.get("type", "") not in ["yield", "empire_modifier", "body_bonus"]:
					data._err("%s: modifier effects must be yield, empire_modifier or body_bonus" % owner)


# --- Conditions ---------------------------------------------------------------

static func condition_met(engine: GalaxyEngine, faction_id: String, cond: Dictionary) -> bool:
	var s := engine.state
	match cond.get("type", ""):
		"has_colony":
			return EmpireRules.colony_count(engine, faction_id) > 0
		"growing_colony":
			for p in s.planets_of(faction_id):
				for b in p.colonies():
					if EmpireRules.pop(b) < EmpireRules.pop_cap(engine, b, faction_id):
						return true
			return false
		"pop_min":
			for p in s.planets_of(faction_id):
				for b in p.colonies():
					if EmpireRules.pop(b) >= int(cond.get("n", 1)):
						return true
			return false
		"min_colonies":
			return EmpireRules.colony_count(engine, faction_id) >= int(cond.get("n", 1))
		"turn_min":
			return s.turn_number >= int(cond.get("n", 0))
		"turn_max":
			return s.turn_number <= int(cond.get("n", 9999))
		"at_war":
			for f in s.factions:
				if f["id"] != faction_id and not s.is_eliminated(f["id"]) and s.at_war(faction_id, f["id"]):
					return true
			return false
		"at_war_major":
			return not _war_targets(engine, faction_id).is_empty()
		"at_peace_minor":
			return not _minors_at_peace(engine, faction_id).is_empty()
		"barbarians":
			return not _barbarians(engine).is_empty()
		"has_building":
			for p in s.planets_of(faction_id):
				if cond.get("building", "") in p.buildings:
					return true
			return false
		"has_shipyard":
			for p in s.planets_of(faction_id):
				if EmpireRules.has_shipyard(engine, p):
					return true
			return false
		"has_fleet":
			return not s.fleets_of(faction_id).is_empty()
		"researching":
			return not str(s.research[faction_id]["current"]).is_empty()
		"credits_min":
			return int(s.resources[faction_id].get("credits", 0)) >= int(cond.get("n", 0))
		"credits_max":
			return int(s.resources[faction_id].get("credits", 0)) <= int(cond.get("n", 0))
		"tech_known":
			return cond.get("tech", "") in s.known_techs(faction_id)
		"has_hero":
			for h in s.heroes_of(faction_id):
				if h.status != Hero.DEAD and h.status != Hero.CAPTURED:
					return true
			return false
		"scale":
			return engine.scale() == cond.get("scale", "galaxy")
		"story_step":
			# The faction has reached (started or finished) that milestone of the campaign's story.
			var at := StoryRules.step_index(engine, cond.get("step", ""))
			var st := StoryRules.state_of(engine, faction_id)
			return at >= 0 and (int(st["step"]) > at or (int(st["step"]) == at and bool(st["active"])))
		"stock_min":
			return int(s.resources[faction_id].get(cond.get("resource", ""), 0)) >= int(cond.get("n", 1))
		"extracting":
			for p in s.planets_of(faction_id):
				for b in p.bodies:
					if DepositRules.is_tapped(engine.data, b, cond.get("resource", "")):
						return true
			return false
		"faction_alive":
			return s.faction(cond.get("faction", "")).has("id") and not s.is_eliminated(cond.get("faction", ""))
		"developed_min":
			# Bodies (or systems) with a development, the homeworld included.
			var n := 0
			for p in s.planets_of(faction_id):
				if not p.buildings.is_empty():
					n += 1
			return n >= int(cond.get("n", 1))
	return false


static func conditions_met(engine: GalaxyEngine, faction_id: String, conditions: Array) -> bool:
	for cond: Dictionary in conditions:
		if not condition_met(engine, faction_id, cond):
			return false
	return true


static func _war_targets(engine: GalaxyEngine, faction_id: String) -> Array[String]:
	var out: Array[String] = []
	for f in engine.state.factions:
		var id: String = f["id"]
		if id != faction_id and not engine.state.is_eliminated(id) and f.get("role", "major") == "major" \
				and engine.state.at_war(faction_id, id):
			out.append(id)
	return out


static func _minors_at_peace(engine: GalaxyEngine, faction_id: String) -> Array[String]:
	var out: Array[String] = []
	for f in engine.state.factions:
		var id: String = f["id"]
		if f.get("role", "") == "minor" and not engine.state.is_eliminated(id) and not engine.state.at_war(faction_id, id):
			out.append(id)
	return out


static func _barbarians(engine: GalaxyEngine) -> Array[String]:
	var out: Array[String] = []
	for f in engine.state.factions:
		if f.get("role", "") == "barbarian" and not engine.state.is_eliminated(f["id"]):
			out.append(f["id"])
	return out


# --- Rolling an event ---------------------------------------------------------

## Events that could be offered to the faction right now (ids, sorted).
static func eligible(engine: GalaxyEngine, faction_id: String) -> Array[String]:
	var out: Array[String] = []
	var s := engine.state
	var seen: Dictionary = s.event_log.get(faction_id, {}).get("seen", {})
	var cooldown := int(config(engine, "repeat_cooldown", 30))
	var ids := engine.data.events.keys()
	ids.sort()
	for id: String in ids:
		var def: Dictionary = engine.data.events[id]
		if s.turn_number < int(def.get("min_turn", 0)) or s.turn_number > int(def.get("max_turn", 9999)):
			continue
		if seen.has(id) and s.turn_number - int(seen[id]) < cooldown:
			continue
		if conditions_met(engine, faction_id, def.get("conditions", [])):
			out.append(id)
	return out


## Maybe offers the faction an event this turn. Returns the pending-event
## dictionary (and records it in the faction's log), or {} for none.
static func roll(engine: GalaxyEngine, faction_id: String) -> Dictionary:
	if not enabled(engine) or engine.state.faction(faction_id).get("role", "major") != "major":
		return {}
	var s := engine.state
	if s.turn_number < int(config(engine, "first_turn", 6)):
		return {}
	var log: Dictionary = s.event_log.get_or_add(faction_id, {"last": 0, "seen": {}})
	if s.turn_number - int(log["last"]) < int(config(engine, "every", 5)):
		return {}
	if s.rng.randf() >= float(config(engine, "chance", 0.7)):
		return {}
	var ids := eligible(engine, faction_id)
	if ids.is_empty():
		return {}
	var total := 0
	for id in ids:
		total += int(engine.data.events[id].get("weight", 1))
	var pick := s.rng.randi_range(1, maxi(total, 1))
	var chosen := ids[0]
	for id in ids:
		pick -= int(engine.data.events[id].get("weight", 1))
		if pick <= 0:
			chosen = id
			break
	var owned := s.planets_of(faction_id)
	var with_colony := owned.filter(func(p: Planet) -> bool: return p.has_colony())
	var pool: Array = with_colony if not with_colony.is_empty() else owned
	var planet_id := ""
	if not pool.is_empty():
		planet_id = (pool[s.rng.randi() % pool.size()] as Planet).id
	log["last"] = s.turn_number
	log["seen"][chosen] = s.turn_number
	return {"faction": faction_id, "event": chosen, "turn": s.turn_number, "planet": planet_id}


## "{planet}" -> the system's name in an event's text.
static func fill(engine: GalaxyEngine, text: String, planet_id: String) -> String:
	var planet: Planet = engine.state.planets.get(planet_id)
	return text.replace("{planet}", planet.name if planet != null else "the frontier")


## One entry per choice: {"index", "label", "hint", "cost", "ok", "reason"}.
static func choices(engine: GalaxyEngine, faction_id: String, pending: Dictionary) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var def: Dictionary = engine.data.events[pending["event"]]
	for i in def["choices"].size():
		var c: Dictionary = def["choices"][i]
		var reason := ""
		if not EmpireRules.can_afford(engine, faction_id, c.get("cost", {})):
			reason = "Needs %s" % EmpireRules.cost_text(engine, c["cost"])
		elif not conditions_met(engine, faction_id, c.get("requires", [])):
			reason = "Not available right now"
		out.append({"index": i, "label": c["label"], "hint": c.get("hint", ""), "cost": c.get("cost", {}),
				"ok": reason.is_empty(), "reason": reason})
	return out


# --- Applying the outcome -----------------------------------------------------

## Pays the choice's cost, rolls its chance and applies its effects.
## Returns {"success": bool, "text": result text, "lines": [what changed]}.
static func apply(engine: GalaxyEngine, faction_id: String, pending: Dictionary, index: int) -> Dictionary:
	var def: Dictionary = engine.data.events[pending["event"]]
	var c: Dictionary = def["choices"][index]
	EmpireRules.pay(engine, faction_id, c.get("cost", {}))
	var success := true
	var chance := float(c.get("chance", 1.0))
	if chance < 1.0:
		success = engine.state.rng.randf() < chance
	var effects: Array = c.get("effects", []) if success else c.get("fail_effects", [])
	var lines: Array[String] = []
	for k: String in c.get("cost", {}):
		lines.append("-%d %s" % [int(c["cost"][k]), engine.data.resources[k]["name"].to_lower()])
	for fx: Dictionary in effects:
		var line := _apply_effect(engine, faction_id, fx, pending.get("planet", ""))
		if not line.is_empty():
			lines.append(line)
	var text: String = c.get("result", "") if success else c.get("fail_result", c.get("result", ""))
	return {"success": success, "text": fill(engine, text, pending.get("planet", "")), "lines": lines}


static func _apply_effect(engine: GalaxyEngine, faction_id: String, fx: Dictionary, planet_id: String) -> String:
	var s := engine.state
	var rng := s.rng
	match fx["type"]:
		"resources":
			var parts := PackedStringArray()
			var stock: Dictionary = s.resources[faction_id]
			for k: String in DepositRules.stockpiled(engine.data):
				if fx.has(k):
					var delta := int(fx[k])
					if delta < 0:
						delta = -mini(-delta, maxi(int(stock.get(k, 0)), 0))
					stock[k] = int(stock.get(k, 0)) + delta
					if delta != 0:
						parts.append("%+d %s" % [delta, engine.data.resources[k]["name"].to_lower()])
			return ", ".join(parts)
		"research":
			var r: Dictionary = s.research[faction_id]
			var delta := int(fx.get("amount", 0))
			r["progress"] = maxi(int(r["progress"]) + delta, 0)
			return "%+d research" % delta
		"pop":
			return _apply_pop(engine, faction_id, fx, planet_id)
		"damage_building":
			return _damage_building(engine, faction_id, planet_id)
		"free_building":
			for p in s.planets_of(faction_id):
				for b in p.colonies():
					if fx["building"] not in b["buildings"] and EmpireRules.body_build_error(engine, b, fx["building"], faction_id).is_empty():
						p.add_building(b["id"], fx["building"])
						return "%s built at %s" % [engine.data.buildings[fx["building"]]["name"], p.name]
			return ""
		"repair_fleets":
			var healed := 0
			for f in s.fleets_of(faction_id):
				for ship in f.ships:
					var max_hull := int(engine.data.units[ship["unit"]]["stats"]["max_hull"])
					var amount := mini(max_hull - int(ship["hull"]), ceili(max_hull * float(fx.get("amount", 0.25))))
					ship["hull"] = int(ship["hull"]) + amount
					healed += amount
			return "Fleets repaired (%d hull)" % healed if healed > 0 else ""
		"damage_fleets":
			for f in s.fleets_of(faction_id):
				for ship in f.ships:
					ship["hull"] = maxi(1, int(ship["hull"]) - ceili(int(ship["hull"]) * float(fx.get("amount", 0.2))))
			return "Fleets damaged (-%d%% hull)" % roundi(float(fx.get("amount", 0.2)) * 100.0)
		"opinion":
			return _apply_opinion(engine, faction_id, fx)
		"raiders":
			return spawn_raiders(engine, faction_id, int(fx.get("count", 1)), planet_id, fx.get("faction", ""))
		"offline":
			return _offline(engine, faction_id, planet_id, int(fx.get("turns", 3)))
		"free_ship":
			return _free_ship(engine, faction_id, fx["unit"])
		"free_hero":
			return _free_hero(engine, faction_id)
		"modifier":
			var list: Array = s.modifiers.get_or_add(faction_id, [])
			for i in range(list.size() - 1, -1, -1):
				if list[i]["id"] == fx["id"]:
					list.remove_at(i)
			list.append({"id": fx["id"], "name": fx.get("name", fx["id"]), "turns": int(fx["turns"]),
					"effects": (fx.get("effects", []) as Array).duplicate(true)})
			return "%s for %d turns" % [fx.get("name", fx["id"]), int(fx["turns"])]
		"item":
			s.inventory[faction_id].append(fx["item"])
			return "Received %s" % engine.data.items[fx["item"]].get("name", fx["item"])
	return ""


static func _apply_pop(engine: GalaxyEngine, faction_id: String, fx: Dictionary, planet_id: String) -> String:
	var s := engine.state
	var amount := int(fx.get("amount", 0))
	var target: String = fx.get("target", "context")
	var colonies: Array = []  # [planet, body]
	for p in s.planets_of(faction_id):
		for b in p.colonies():
			colonies.append([p, b])
	if colonies.is_empty():
		return ""
	var chosen: Array = []
	match target:
		"all":
			chosen = colonies
		"largest":
			colonies.sort_custom(func(a: Array, b: Array) -> bool: return EmpireRules.pop(a[1]) > EmpireRules.pop(b[1]))
			chosen = [colonies[0]]
		_:
			var local := colonies.filter(func(e: Array) -> bool: return (e[0] as Planet).id == planet_id)
			var pool: Array = local if target == "context" and not local.is_empty() else colonies
			if amount > 0:
				var growable := pool.filter(func(e: Array) -> bool: return EmpireRules.pop(e[1]) < EmpireRules.pop_cap(engine, e[1], faction_id))
				pool = growable if not growable.is_empty() else pool
			elif amount < 0:
				var shrinkable := pool.filter(func(e: Array) -> bool: return EmpireRules.pop(e[1]) > 1)
				pool = shrinkable if not shrinkable.is_empty() else pool
			chosen = [pool[s.rng.randi() % pool.size()]]
	var names := PackedStringArray()
	for entry: Array in chosen:
		var b: Dictionary = entry[1]
		var before := EmpireRules.pop(b)
		b["pop"] = clampi(before + amount, 1, maxi(EmpireRules.pop_cap(engine, b, faction_id), before))
		if int(b["pop"]) != before:
			names.append((entry[0] as Planet).name)
	if names.is_empty():
		return ""
	return "Population %+d at %s" % [amount, ", ".join(names)]


static func _damage_building(engine: GalaxyEngine, faction_id: String, planet_id: String) -> String:
	var s := engine.state
	var candidates: Array = []  # [planet, building id]
	var local: Array = []
	for p in s.planets_of(faction_id):
		for building_id in p.buildings:
			if building_id == "colony":
				continue
			candidates.append([p, building_id])
			if p.id == planet_id:
				local.append([p, building_id])
	var pool: Array = local if not local.is_empty() else candidates
	if pool.is_empty():
		return ""
	var pick: Array = pool[s.rng.randi() % pool.size()]
	(pick[0] as Planet).remove_building(pick[1])
	return "%s lost at %s" % [engine.data.buildings[pick[1]]["name"], (pick[0] as Planet).name]


static func _apply_opinion(engine: GalaxyEngine, faction_id: String, fx: Dictionary) -> String:
	var s := engine.state
	var amount := int(fx.get("amount", 0))
	var targets: Array[String] = []
	match fx.get("with", ""):
		"minor":
			targets = _minors_at_peace(engine, faction_id)
		"war_target":
			targets = _war_targets(engine, faction_id)
		"random_major", "all_majors":
			for f in s.factions:
				if f["id"] != faction_id and f.get("role", "major") == "major" and not s.is_eliminated(f["id"]):
					targets.append(f["id"])
			if fx["with"] == "random_major" and not targets.is_empty():
				targets = [targets[s.rng.randi() % targets.size()]]
	var names := PackedStringArray()
	for t in targets:
		DiplomacyRules.change_opinion(s, t, faction_id, amount)
		names.append(s.faction(t)["name"])
	if names.is_empty():
		return ""
	return "%s opinion of you %+d" % [", ".join(names), amount]


## A development of the faction (the event's own body first) is knocked offline for `turns`
## turns: it yields nothing until it is repaired (see EmpireRules.is_offline).
static func _offline(engine: GalaxyEngine, faction_id: String, planet_id: String, turns: int) -> String:
	var s := engine.state
	var pool: Array = []  # [planet, body]
	var local: Array = []
	for p in s.planets_of(faction_id):
		for b in p.bodies:
			if b["buildings"].is_empty() or "colony" in b["buildings"] or EmpireRules.is_offline(engine, b):
				continue
			pool.append([p, b])
			if p.id == planet_id:
				local.append([p, b])
	var from: Array = local if not local.is_empty() else pool
	if from.is_empty():
		return ""
	var pick: Array = from[s.rng.randi() % from.size()]
	(pick[1] as Dictionary)["offline_until"] = s.turn_number + turns
	return "%s at %s offline for %d turns" % [engine.data.buildings[pick[1]["buildings"][0]]["name"], (pick[0] as Planet).name, turns]


## Spawns `count` raider fleets of `raider_id` (default: the first barbarian faction still in the game)
## a couple of cells from the faction's system `planet_id` (or its first system). Used by events and
## story milestones.
static func spawn_raiders(engine: GalaxyEngine, faction_id: String, count: int, planet_id: String, raider_id: String = "") -> String:
	var s := engine.state
	var barbarians := _barbarians(engine)
	if barbarians.is_empty():
		return ""
	if raider_id.is_empty() or raider_id not in barbarians:
		raider_id = barbarians[0]
	var spec: Dictionary = s.faction(raider_id).get("barbarian", {})
	var anchor: Planet = s.planets.get(planet_id)
	if anchor == null:
		var owned := s.planets_of(faction_id)
		if owned.is_empty():
			return ""
		anchor = owned[0]
	var spawned := 0
	for i in count:
		var cell := _free_cell_near(engine, anchor.cell)
		if cell == Vector2i(-1, -1):
			break
		var fleet := Fleet.new()
		fleet.id = s.make_uid("fleet")
		fleet.owner = raider_id
		fleet.cell = cell
		fleet.name = "%s %d" % [spec.get("fleet_name", "Raiders"), s.next_uid]
		for unit_id: String in spec.get("fleet", ["interceptor", "interceptor"]):
			var def: Dictionary = engine.data.units[unit_id]
			fleet.ships.append({"uid": s.make_uid("ship"), "unit": unit_id,
					"name": "%s %d" % [def.get("name", unit_id), s.next_uid], "hull": int(def["stats"]["max_hull"])})
		s.fleets[fleet.id] = fleet
		engine.emit({"type": GalaxyEvents.FLEET_CREATED, "fleet": fleet.id, "planet": ""})
		spawned += 1
	return "A %s fleet appears near %s" % [s.faction(raider_id).get("name", "raider"), anchor.name] if spawned > 0 else ""


## A free, passable cell 2-3 systems from `from`, or (-1, -1).
static func _free_cell_near(engine: GalaxyEngine, from: Vector2i) -> Vector2i:
	var s := engine.state
	var options: Array[Vector2i] = []
	for radius in [2, 3, 4]:
		for c in s.grid.cells_within(from, radius):
			if s.grid.distance(from, c) >= 2 and s.grid.is_passable(c) and s.fleet_at(c) == null \
					and s.planet_at(c) == null and s.anomaly_at(c).is_empty():
				options.append(c)
		if not options.is_empty():
			break
	if options.is_empty():
		return Vector2i(-1, -1)
	return options[s.rng.randi() % options.size()]


static func _free_ship(engine: GalaxyEngine, faction_id: String, unit_id: String) -> String:
	var unit_name: String = engine.data.units[unit_id].get("name", unit_id)
	for p in engine.state.planets_of(faction_id):
		if engine._launch_ship(p, unit_id):
			return "A free %s joins you at %s" % [unit_name, p.name]
	var stock: Dictionary = engine.state.resources[faction_id]
	stock["alloys"] = int(stock.get("alloys", 0)) + 40
	return "No room for the %s: +40 alloys instead" % unit_name


static func _free_hero(engine: GalaxyEngine, faction_id: String) -> String:
	var s := engine.state
	var home := s.home_planet(faction_id)
	if home == null:
		return ""
	var classes := engine.data.hero_classes.keys()
	classes.sort()
	var names: Array = engine.data.economy.get("hero_names", ["Cmdr. Vale"])
	var h := Hero.new()
	h.id = s.make_uid("hero")
	h.name = names[s.rng.randi() % names.size()]
	h.class_id = classes[s.rng.randi() % classes.size()]
	h.owner = faction_id
	h.level = 1
	h.xp = 0
	h.loyalty = 60
	h.planet_id = home.id
	s.heroes[h.id] = h
	return "%s (%s) joins you at %s" % [h.name, engine.data.hero_classes[h.class_id].get("name", h.class_id), home.name]
