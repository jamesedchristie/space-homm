class_name GalaxySave
extends RefCounted
## Saving and loading campaigns. A save is the whole GalaxyState as plain data
## (dictionaries, arrays, numbers, strings, Vector2i) plus the campaign id and
## some display info. The grid is rebuilt from the campaign definition (galaxy
## terrain never changes), and the RNG state is restored so a loaded game
## continues exactly as the original would have.
##
## Files are written with FileAccess.store_var and read with objects disallowed,
## so a save file can only ever contain data, never code.
##
## Saves are taken between turns (no pending battle or mission), which is all
## the UI allows; to_dict() refuses otherwise.

const FORMAT := "space-homm-save"
## 2: star systems with bodies (planets have "bodies" instead of type/buildings/traits).
## 3: empire depth: colony population and growth (in the bodies), megaprojects, temporary
## modifiers, event log and pending event, why the game ended.
## 4: the system layer: civilian ships deployed in systems (with their jobs), blockades and the
## capital-to-be of unfounded home systems; claiming by colony or outpost instead of by entering.
## 5: system-scale campaigns: surveyed bodies per faction (older saves load with nothing surveyed).
## 6: strategic resources: deposits on bodies ({resource: richness}) and strategic stockpiles
## (version 5 saves load with no deposits and empty strategic stockpiles).
const VERSION := 6
const DIR := "user://saves"
const AUTOSAVE := "autosave"
const QUICKSAVE := "quicksave"


## Plain-data snapshot of a campaign, or {} if it can't be saved right now.
static func to_dict(engine: GalaxyEngine, campaign_id: String) -> Dictionary:
	var s := engine.state
	if not s.pending_battle.is_empty() or not s.pending_mission.is_empty():
		return {}
	var planets := []
	for p: Planet in s.planets.values():
		planets.append({"id": p.id, "name": p.name, "star": p.star, "cell": p.cell, "owner": p.owner,
				"sensor": p.sensor, "description": p.description, "bodies": p.bodies.duplicate(true),
				"queue": p.queue.duplicate(true), "megaprojects": p.megaprojects.duplicate(),
				"civilians": p.civilians.duplicate(true), "blockade": p.blockade, "capital": p.capital.duplicate(true)})
	var fleets := []
	for f: Fleet in s.fleets.values():
		fleets.append({"id": f.id, "name": f.name, "owner": f.owner, "cell": f.cell,
				"ships": f.ships.duplicate(true), "moves_left": f.moves_left, "hero_id": f.hero_id,
				"order": f.order.duplicate(true)})
	var heroes := []
	for h: Hero in s.heroes.values():
		heroes.append({"id": h.id, "name": h.name, "class_id": h.class_id, "owner": h.owner, "level": h.level,
				"xp": h.xp, "traits": h.traits.duplicate(), "gear": h.gear.duplicate(true), "loyalty": h.loyalty,
				"status": h.status, "busy_until": h.busy_until, "fleet_id": h.fleet_id, "planet_id": h.planet_id})
	var explored := {}
	for faction_id: String in s.explored:
		explored[faction_id] = s.explored[faction_id].keys()
	var current: Dictionary = s.factions[s.current_faction_index]
	return {
		"format": FORMAT,
		"version": VERSION,
		"campaign": campaign_id,
		# Generated sectors aren't in the data files: keep the generated definition.
		"campaign_def": engine.campaign if engine.campaign.get("generated", false) else {},
		"meta": {
			"campaign_name": engine.campaign.get("name", campaign_id),
			"turn": s.turn_number,
			"faction": current.get("name", ""),
			"saved_at": Time.get_datetime_string_from_system(false, true),
		},
		"state": {
			"factions": s.factions.duplicate(true),
			"planets": planets,
			"fleets": fleets,
			"heroes": heroes,
			"turn_number": s.turn_number,
			"max_turns": s.max_turns,
			"current_faction_index": s.current_faction_index,
			"explored": explored,
			"eliminated": s.eliminated.duplicate(),
			"seed_value": s.seed_value,
			"rng_state": s.rng.state,
			"is_over": s.is_over,
			"winner": s.winner,
			"next_uid": s.next_uid,
			"inventory": s.inventory.duplicate(true),
			"anomalies": s.anomalies.duplicate(true),
			"discoveries": s.discoveries.duplicate(true),
			"permadeath": s.permadeath,
			"resources": s.resources.duplicate(true),
			"research": s.research.duplicate(true),
			"relations": s.relations.duplicate(true),
			"opinions": s.opinions.duplicate(true),
			"met": s.met.duplicate(true),
			"peace_offers": s.peace_offers.duplicate(true),
			"modifiers": s.modifiers.duplicate(true),
			"event_log": s.event_log.duplicate(true),
			"pending_event": s.pending_event.duplicate(true),
			"victory_reason": s.victory_reason,
			"surveyed": s.surveyed.duplicate(true),
		},
	}


## Rebuilds an engine from a to_dict() snapshot. Returns {"engine": GalaxyEngine}
## or {"error": String}.
static func from_dict(data: DataRegistry, save: Dictionary) -> Dictionary:
	if save.get("format", "") != FORMAT:
		return {"error": "Not a save file"}
	if int(save.get("version", 0)) > VERSION:
		return {"error": "This save is from a newer version of the game"}
	if int(save.get("version", 0)) < 4:
		return {"error": "This save is from before the system layer (colony ships, constructors, blockades) was added and can't be loaded"}
	var campaign_id: String = save.get("campaign", "")
	if not data.campaigns.has(campaign_id):
		return {"error": "Unknown campaign '%s'" % campaign_id}
	var d: Dictionary = save.get("state", {})
	var engine := GalaxyEngine.new()
	engine.data = data
	engine.campaign = save.get("campaign_def", {}) if not save.get("campaign_def", {}).is_empty() \
			else data.campaigns[campaign_id]
	var s := GalaxyState.new()
	engine.state = s
	s.grid = HexGrid.from_map(engine.campaign.get("map", {}), data.galaxy_terrain)

	s.factions.assign(d["factions"])
	for p_d: Dictionary in d["planets"]:
		var p := Planet.new()
		p.id = p_d["id"]
		p.name = p_d["name"]
		p.star = p_d.get("star", "yellow")
		p.cell = p_d["cell"]
		p.owner = p_d["owner"]
		p.sensor = p_d["sensor"]
		p.description = p_d["description"]
		for b: Dictionary in p_d.get("bodies", []):
			var body := b.duplicate(true)
			var traits: Array[String] = []
			traits.assign(b.get("traits", []))
			var buildings: Array[String] = []
			buildings.assign(b.get("buildings", []))
			body["traits"] = traits
			body["buildings"] = buildings
			body.get_or_add("deposits", {})  # version 5 saves: bodies without deposits
			p.bodies.append(body)
		p.queue = p_d["queue"]
		p.megaprojects.assign(p_d.get("megaprojects", []))
		p.civilians.assign(p_d.get("civilians", []))
		p.blockade = p_d.get("blockade", "")
		p.capital = p_d.get("capital", {})
		s.planets[p.id] = p
	for f_d: Dictionary in d["fleets"]:
		var f := Fleet.new()
		f.id = f_d["id"]
		f.name = f_d["name"]
		f.owner = f_d["owner"]
		f.cell = f_d["cell"]
		f.ships.assign(f_d["ships"])
		f.moves_left = f_d["moves_left"]
		f.hero_id = f_d["hero_id"]
		f.order = f_d.get("order", {})
		s.fleets[f.id] = f
	for h_d: Dictionary in d["heroes"]:
		var h := Hero.new()
		h.id = h_d["id"]
		h.name = h_d["name"]
		h.class_id = h_d["class_id"]
		h.owner = h_d["owner"]
		h.level = h_d["level"]
		h.xp = h_d["xp"]
		h.traits.assign(h_d["traits"])
		h.gear = h_d["gear"]
		h.loyalty = h_d["loyalty"]
		h.status = h_d["status"]
		h.busy_until = h_d["busy_until"]
		h.fleet_id = h_d["fleet_id"]
		h.planet_id = h_d["planet_id"]
		s.heroes[h.id] = h
	s.turn_number = d["turn_number"]
	s.max_turns = d["max_turns"]
	s.current_faction_index = d["current_faction_index"]
	for faction_id: String in d["explored"]:
		var cells := {}
		for c: Vector2i in d["explored"][faction_id]:
			cells[c] = true
		s.explored[faction_id] = cells
	s.eliminated.assign(d["eliminated"])
	s.seed_value = d["seed_value"]
	s.rng.seed = s.seed_value
	s.rng.state = d["rng_state"]
	s.is_over = d["is_over"]
	s.winner = d["winner"]
	s.next_uid = d["next_uid"]
	s.inventory = d["inventory"]
	s.anomalies = d["anomalies"]
	s.discoveries = d.get("discoveries", {})
	s.permadeath = d["permadeath"]
	s.resources = d["resources"]
	for faction_id: String in s.resources:  # saves before strategic resources (version 5): none in store
		for k in DepositRules.stockpiled(data):
			s.resources[faction_id].get_or_add(k, 0)
	s.research = d["research"]
	s.relations = d["relations"]
	s.opinions = d["opinions"]
	s.peace_offers = d.get("peace_offers", {})
	if d.has("met"):
		s.met = d["met"]
	else:
		# Saves from before first contact existed: everyone already knows everyone.
		for a: Dictionary in s.factions:
			for b: Dictionary in s.factions:
				if a["id"] < b["id"]:
					s.met[GalaxyState.relation_key(a["id"], b["id"])] = s.turn_number
	s.modifiers = d.get("modifiers", {})
	s.event_log = d.get("event_log", {})
	s.pending_event = d.get("pending_event", {})
	s.victory_reason = d.get("victory_reason", "")
	s.surveyed = d.get("surveyed", {})
	for f: Dictionary in s.factions:
		s.surveyed.get_or_add(f["id"], {})
	# Typed arrays inside dictionaries come back untyped; the rules only read them.
	for faction_id: String in s.research:
		var known: Array[String] = []
		known.assign(s.research[faction_id]["known"])
		s.research[faction_id]["known"] = known
	return {"engine": engine}


# --- Files --------------------------------------------------------------------

static func path_for(slot: String) -> String:
	return "%s/%s.save" % [DIR, slot]


## Writes a snapshot to a slot. Returns "" or an error message.
static func write(slot: String, engine: GalaxyEngine, campaign_id: String) -> String:
	var save := to_dict(engine, campaign_id)
	if save.is_empty():
		return "Can't save in the middle of a battle or mission"
	DirAccess.make_dir_recursive_absolute(DIR)
	var tmp := path_for(slot) + ".tmp"
	var file := FileAccess.open(tmp, FileAccess.WRITE)
	if file == null:
		return "Couldn't write the save (%s)" % error_string(FileAccess.get_open_error())
	file.store_var(save, false)
	file.close()
	# Replace the old file only once the new one is complete.
	DirAccess.rename_absolute(tmp, path_for(slot))
	return ""


## Reads a slot: {"save": Dictionary} or {"error": String}.
static func read(slot: String) -> Dictionary:
	var path := path_for(slot)
	if not FileAccess.file_exists(path):
		return {"error": "No save in this slot"}
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return {"error": "Couldn't open the save (%s)" % error_string(FileAccess.get_open_error())}
	var value: Variant = file.get_var(false)
	if not value is Dictionary or value.get("format", "") != FORMAT:
		return {"error": "The save file is damaged"}
	return {"save": value}


## Loads a slot into a new engine: {"engine": GalaxyEngine, "campaign": id} or {"error": String}.
static func load_slot(data: DataRegistry, slot: String) -> Dictionary:
	var r := read(slot)
	if r.has("error"):
		return r
	var out := from_dict(data, r["save"])
	if out.has("engine"):
		out["campaign"] = r["save"]["campaign"]
	return out


## [{"slot", "meta"}] for every readable save, newest first.
static func list() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var dir := DirAccess.open(DIR)
	if dir == null:
		return out
	for name in dir.get_files():
		if not name.ends_with(".save"):
			continue
		var slot := name.trim_suffix(".save")
		var r := read(slot)
		if r.has("save"):
			out.append({"slot": slot, "meta": r["save"].get("meta", {}),
					"modified": FileAccess.get_modified_time(path_for(slot))})
	out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a["modified"] > b["modified"])
	return out


static func delete(slot: String) -> void:
	DirAccess.remove_absolute(path_for(slot))
