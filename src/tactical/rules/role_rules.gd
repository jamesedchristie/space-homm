class_name RoleRules
extends RefCounted
## Ship classes and counters (data/tactical/roles.json): a rock-paper-scissors of
## three roles plus a few specialists.
##   strike craft  beat capital ships, lose to escorts
##   escorts       beat strike craft, lose to capital ships
##   capital ships beat escorts, lose to strike craft
## A unit's "class" (strike | escort | capital | station | civilian) and optional
## "specialty" (interceptor | bomber | flak | ion) pick a damage multiplier for each
## target class: the specialty's entry in "specialty_vs" if it has one, else the
## class's entry in "vs", else 1.0. Units without a class (people, drones, heroes)
## always deal and take x1.0, so missions are unaffected.
## DamageEffect applies the multiplier, so previews, the AI, auto-resolve and the
## odds all agree. Pure functions over DataRegistry; the strategic AI and the UI use
## the same helpers.

const CLASSES := ["strike", "escort", "capital", "station", "civilian"]
## The three roles of the triangle, and who counters whom.
const ROLES := ["strike", "escort", "capital"]
const COUNTER := {"capital": "strike", "strike": "escort", "escort": "capital"}


static func class_of(def: Dictionary) -> String:
	return str(def.get("class", ""))


static func specialty_of(def: Dictionary) -> String:
	return str(def.get("specialty", ""))


## Damage multiplier for an attacker of this class/specialty against a target class.
static func multiplier_for(data: DataRegistry, attacker_class: String, attacker_specialty: String, target_class: String) -> float:
	if attacker_class.is_empty() or target_class.is_empty():
		return 1.0
	var roles := data.roles
	if not attacker_specialty.is_empty():
		var row: Dictionary = roles.get("specialty_vs", {}).get(attacker_specialty, {})
		if row.has(target_class):
			return float(row[target_class])
	var class_row: Dictionary = roles.get("vs", {}).get(attacker_class, {})
	return float(class_row.get(target_class, 1.0))


## Multiplier for attacker def -> target def (unit definitions).
static func multiplier(data: DataRegistry, attacker_def: Dictionary, target_def: Dictionary) -> float:
	return multiplier_for(data, class_of(attacker_def), specialty_of(attacker_def), class_of(target_def))


## Multiplier between two battle units (null source: x1.0, e.g. a status ticking).
static func unit_multiplier(data: DataRegistry, source: BattleUnit, target: BattleUnit) -> float:
	if source == null or target == null or data == null:
		return 1.0
	return multiplier(data, source.def, target.def)


static func class_name_of(data: DataRegistry, cls: String, plural: bool = false) -> String:
	var def: Dictionary = data.roles.get("classes", {}).get(cls, {})
	if def.is_empty():
		return cls
	return str(def.get("plural" if plural else "name", def.get("name", cls)))


## {class, specialty, name, strong: [{class, mul}], weak: [{class, mul}]}: what a unit
## hits hard (its multiplier > 1) and which classes hit it hard (theirs > 1), for the UI.
## Empty for units without a class.
static func profile(data: DataRegistry, def: Dictionary) -> Dictionary:
	var cls := class_of(def)
	if cls.is_empty():
		return {}
	var spec := specialty_of(def)
	var name := class_name_of(data, cls)
	if not spec.is_empty():
		name = "%s (%s)" % [name, str(data.roles.get("specialties", {}).get(spec, {}).get("name", spec))]
	var strong: Array[Dictionary] = []
	var weak: Array[Dictionary] = []
	var poor: Array[Dictionary] = []
	for other: String in ROLES + ["station"]:
		var out := multiplier_for(data, cls, spec, other)
		if out > 1.0:
			strong.append({"class": other, "mul": out})
		elif out < 1.0:
			poor.append({"class": other, "mul": out})
		if other == "station":
			continue
		# Who hits this class hard: the other class's own row (its specialists may differ).
		var incoming := multiplier_for(data, other, "", cls)
		if incoming > 1.0:
			weak.append({"class": other, "mul": incoming})
	return {"class": cls, "specialty": spec, "name": name, "strong": strong, "weak": weak, "poor": poor}


## "Strong vs capital ships x1.8, stations x1.4 · weak vs escorts" (one line, plain text).
static func summary(data: DataRegistry, def: Dictionary, with_numbers: bool = true) -> String:
	var p := profile(data, def)
	if p.is_empty():
		return ""
	var parts := PackedStringArray()
	if not (p["strong"] as Array).is_empty():
		parts.append("strong vs " + _list(data, p["strong"], with_numbers))
	if not (p["weak"] as Array).is_empty():
		parts.append("weak vs " + _list(data, p["weak"], false))
	if parts.is_empty():
		return "no counters"
	return " · ".join(parts)


## Short hint for build lists: "strike: kills capital ships".
static func hint(data: DataRegistry, def: Dictionary) -> String:
	var p := profile(data, def)
	if p.is_empty():
		return ""
	var cls: String = p["class"]
	var short := cls if cls != "strike" else "strike craft"
	if (p["strong"] as Array).is_empty():
		return short
	var best: Dictionary = p["strong"][0]
	for s: Dictionary in p["strong"]:
		if float(s["mul"]) > float(best["mul"]):
			best = s
	return "%s, vs %s" % [short, class_name_of(data, best["class"], true)]


static func _list(data: DataRegistry, entries: Array, with_numbers: bool) -> String:
	var out := PackedStringArray()
	for e: Dictionary in entries:
		var text := class_name_of(data, e["class"], true)
		if with_numbers:
			text += " x%s" % mul_text(float(e["mul"]))
		out.append(text)
	return ", ".join(out)


## 1.5 -> "1.5", 0.7 -> "0.7", 1.25 -> "1.25".
static func mul_text(mul: float) -> String:
	var s := "%.2f" % mul
	s = s.rstrip("0").rstrip(".")
	return s


# --- Fleets (strategic layer) -------------------------------------------------

## Strength per class of a list of ships ({unit, hull}); civilian ships and units
## without a class count under "" (they neither counter nor are countered).
static func composition(data: DataRegistry, ships: Array) -> Dictionary:
	var out := {}
	for ship: Dictionary in ships:
		var def: Dictionary = data.units.get(ship.get("unit", ""), {})
		if def.is_empty():
			continue
		var stats: Dictionary = def.get("stats", {})
		var hp := float(ship.get("hull", stats.get("max_hull", 0))) + float(stats.get("max_shields", 0)) * 0.5
		var cls := class_of(def)
		out[cls] = float(out.get(cls, 0.0)) + hp
	return out


## How hard `mine` hits `theirs` on average: each of my ships' multiplier against
## their ships, weighted by both sides' strength. 1.0 when either side is empty.
static func matchup(data: DataRegistry, mine: Array, theirs: Array) -> float:
	var their_total := 0.0
	var their_by_def := []
	for ship: Dictionary in theirs:
		var def: Dictionary = data.units.get(ship.get("unit", ""), {})
		if def.is_empty() or class_of(def) == "civilian":
			continue
		var stats: Dictionary = def.get("stats", {})
		var hp := float(ship.get("hull", stats.get("max_hull", 0))) + float(stats.get("max_shields", 0)) * 0.5
		their_by_def.append([def, hp])
		their_total += hp
	if their_total <= 0.0:
		return 1.0
	var weighted := 0.0
	var my_total := 0.0
	for ship: Dictionary in mine:
		var def: Dictionary = data.units.get(ship.get("unit", ""), {})
		if def.is_empty() or class_of(def) == "civilian":
			continue
		var stats: Dictionary = def.get("stats", {})
		var hp := float(ship.get("hull", stats.get("max_hull", 0))) + float(stats.get("max_shields", 0)) * 0.5
		var m := 0.0
		for entry: Array in their_by_def:
			m += multiplier(data, def, entry[0]) * float(entry[1]) / their_total
		weighted += m * hp
		my_total += hp
	return weighted / my_total if my_total > 0.0 else 1.0


## How a unit fares against an enemy mix (class -> strength): its average outgoing
## multiplier over the average incoming one. > 1 counters the mix, < 1 is countered.
static func counter_value(data: DataRegistry, def: Dictionary, enemy_mix: Dictionary) -> float:
	var total := 0.0
	for cls: String in enemy_mix:
		total += float(enemy_mix[cls])
	if total <= 0.0:
		return 1.0
	var out := 0.0
	var incoming := 0.0
	for cls: String in enemy_mix:
		var w := float(enemy_mix[cls]) / total
		out += multiplier_for(data, class_of(def), specialty_of(def), cls) * w
		incoming += multiplier_for(data, cls, "", class_of(def)) * w
	return out / maxf(incoming, 0.1)


# --- Balance helpers (tools/simulate_battles.gd --matrix, tests) --------------

## A unit's price in one number: credits + alloys, strategic resources at `strategic_weight` each.
static func unit_cost(data: DataRegistry, unit_id: String, strategic_weight: float = 2.0) -> float:
	var cost: Dictionary = data.units.get(unit_id, {}).get("strategic", {}).get("cost", {})
	var total := 0.0
	for k: String in cost:
		total += float(cost[k]) * (1.0 if k in ["credits", "alloys"] else strategic_weight)
	return total


## Ships ({unit, hull}) worth `budget`, cycling through `unit_ids`, at most `max_units`: whole
## ships while they fit, then one more ship with the hull the rest of the budget pays for.
static func fleet_for_budget(data: DataRegistry, unit_ids: Array, budget: float, max_units: int = 6) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var left := budget
	var i := 0
	while out.size() < max_units and not unit_ids.is_empty():
		var id: String = unit_ids[i % unit_ids.size()]
		var cost := unit_cost(data, id)
		var max_hull := int(data.units[id]["stats"]["max_hull"])
		if cost <= left + 0.01:
			out.append({"unit": id, "hull": max_hull})
			left -= cost
		else:
			var share := left / cost
			if share >= 0.15:
				out.append({"unit": id, "hull": maxi(1, roundi(max_hull * share))})
			break
		i += 1
	return out


## A battle scenario between two lists of ships ({unit, hull}) on a map with deployment slots
## (west attacker, team 0; east defender, team 1), both sides AI.
static func duel_scenario(data: DataRegistry, west: Array, east: Array, map_id: String = "open_space", max_rounds: int = 40) -> Dictionary:
	var deployment: Dictionary = data.maps.get(map_id, {}).get("deployment", {})
	var teams: Array = []
	var sides := [["west", west], ["east", east]]
	for t in 2:
		var slots: Array = deployment.get(sides[t][0], [])
		var units: Array = []
		var ships: Array = sides[t][1]
		for i in mini(ships.size(), slots.size()):
			var ship: Dictionary = ships[i]
			units.append({"unit": ship["unit"], "at": slots[i], "hull": ship.get("hull", data.units[ship["unit"]]["stats"]["max_hull"])})
		teams.append({"team": t, "name": "Team %d" % t, "controller": "ai", "units": units})
	return {"id": "duel", "map": map_id, "max_rounds": max_rounds, "teams": teams}


## Problems in roles.json and in units' class / specialty (for DataRegistry.validate()).
static func validate(data: DataRegistry) -> PackedStringArray:
	var errors := PackedStringArray()
	var classes: Dictionary = data.roles.get("classes", {})
	var specialties: Dictionary = data.roles.get("specialties", {})
	for cls: String in CLASSES:
		if not classes.has(cls):
			errors.append("roles: missing class '%s'" % cls)
	for table: String in ["vs", "specialty_vs"]:
		var rows: Dictionary = data.roles.get(table, {})
		for key: String in rows:
			if (table == "vs" and not classes.has(key)) or (table == "specialty_vs" and not specialties.has(key)):
				errors.append("roles: %s has unknown %s '%s'" % [table, "class" if table == "vs" else "specialty", key])
			var row: Variant = rows[key]
			if not row is Dictionary:
				errors.append("roles: %s.%s must be an object" % [table, key])
				continue
			for target: String in row:
				if not classes.has(target):
					errors.append("roles: %s.%s has unknown target class '%s'" % [table, key, target])
				elif not (row[target] is float or row[target] is int) or float(row[target]) <= 0.0:
					errors.append("roles: %s.%s.%s must be a positive number" % [table, key, target])
	for id: String in data.units:
		var def: Dictionary = data.units[id]
		var cls := class_of(def)
		if not cls.is_empty() and not classes.has(cls):
			errors.append("unit '%s': unknown class '%s'" % [id, cls])
		var spec := specialty_of(def)
		if not spec.is_empty() and not specialties.has(spec):
			errors.append("unit '%s': unknown specialty '%s'" % [id, spec])
		if not spec.is_empty() and cls.is_empty():
			errors.append("unit '%s': a specialty needs a class" % id)
		var tags: Array = def.get("tags", [])
		if cls.is_empty() and ("ship" in tags or "station" in tags):
			errors.append("unit '%s': ships and stations need a class (%s)" % [id, ", ".join(CLASSES)])
	return errors
