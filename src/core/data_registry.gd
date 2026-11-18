class_name DataRegistry
extends RefCounted
## Loads all game content (JSON under res://data) into plain dictionaries keyed
## by id, and validates cross-references (a unit's abilities exist, a scenario's
## map exists, ...).
##
## Content is data, mechanics are code: adding a ship, ability or scenario should
## only ever mean adding a JSON file.

const DEFAULT_ROOT := "res://data"

const VALID_TARGETS := ["self", "enemy", "ally", "friendly", "any_unit", "cell"]
const ITEM_SLOTS := ["weapon", "armor", "gadget"]
const TRIGGER_EFFECTS := ["effect", "spawn", "alert", "alarm", "reward"]
## Aptitudes used by mission skill checks.
const SKILLS := ["combat", "tech", "command"]
const VALID_AFFECTS := ["enemies", "allies", "all"]
const REQUIRED_UNIT_STATS := ["max_hull", "max_shields", "armor", "initiative", "max_ap"]

var units: Dictionary = {}
var abilities: Dictionary = {}
var statuses: Dictionary = {}
var damage_types: Dictionary = {}
var terrain: Dictionary = {}
var maps: Dictionary = {}
var scenarios: Dictionary = {}

# Strategic layer
var galaxy_terrain: Dictionary = {}
var body_types: Dictionary = {}
var star_types: Dictionary = {}
var species: Dictionary = {}
var discoveries: Dictionary = {}
var planet_traits: Dictionary = {}
var campaigns: Dictionary = {}

# Heroes and missions
var hero_classes: Dictionary = {}
var items: Dictionary = {}
var traits: Dictionary = {}
var progression: Dictionary = {}
var missions: Dictionary = {}

# Empire
var resources: Dictionary = {}
var buildings: Dictionary = {}
var techs: Dictionary = {}
## Tuning for population, upkeep, debt and events (data/empire/economy.json).
var economy: Dictionary = {}
## Tech eras: era number (as a string) -> {"name", "requires": {"era", "count"}}.
var eras: Dictionary = {}
var megaprojects: Dictionary = {}
## Galactic events (data/strategic/events.json).
var events: Dictionary = {}

# 3D model recipes (presentation only)
var models: Dictionary = {}

## Human-readable problems found while loading. Empty means all good.
var errors: PackedStringArray = []

static var _default: DataRegistry


## Shared registry loaded from res://data (loaded once, then cached).
static func get_default() -> DataRegistry:
	if _default == null:
		_default = DataRegistry.new()
		_default.load_from(DEFAULT_ROOT)
	return _default


func load_from(root: String) -> bool:
	errors.clear()
	_load_dir(root.path_join("tactical/units"), units)
	_load_dir(root.path_join("tactical/abilities"), abilities)
	_load_dir(root.path_join("tactical/statuses"), statuses)
	_load_dir(root.path_join("tactical/maps"), maps)
	_load_dir(root.path_join("scenarios"), scenarios)
	_load_keyed_file(root.path_join("tactical/damage_types.json"), damage_types)
	_load_keyed_file(root.path_join("tactical/terrain.json"), terrain)
	_load_keyed_file(root.path_join("strategic/terrain.json"), galaxy_terrain)
	_load_keyed_file(root.path_join("strategic/body_types.json"), body_types)
	_load_keyed_file(root.path_join("strategic/star_types.json"), star_types)
	_load_keyed_file(root.path_join("strategic/species.json"), species)
	_load_keyed_file(root.path_join("strategic/discoveries.json"), discoveries)
	_load_keyed_file(root.path_join("strategic/planet_traits.json"), planet_traits)
	_load_dir(root.path_join("strategic/campaigns"), campaigns)
	_load_keyed_file(root.path_join("heroes/classes.json"), hero_classes)
	_load_keyed_file(root.path_join("heroes/items.json"), items)
	_load_keyed_file(root.path_join("heroes/traits.json"), traits)
	var prog: Variant = JsonUtil.load_file(root.path_join("heroes/progression.json"))
	progression = prog if prog is Dictionary else {}
	_load_dir(root.path_join("missions"), missions)
	_load_keyed_file(root.path_join("empire/resources.json"), resources)
	_load_keyed_file(root.path_join("empire/buildings.json"), buildings)
	_load_keyed_file(root.path_join("empire/techs.json"), techs)
	_load_keyed_file(root.path_join("empire/eras.json"), eras)
	_load_keyed_file(root.path_join("empire/megaprojects.json"), megaprojects)
	_load_keyed_file(root.path_join("strategic/events.json"), events)
	var eco: Variant = JsonUtil.load_file(root.path_join("empire/economy.json"))
	economy = eco if eco is Dictionary else {}
	_load_keyed_file(root.path_join("models/models.json"), models)
	validate()
	return errors.is_empty()


## Re-checks every cross-reference. Call again after adding content in code
## (tests do this when they register fixtures).
func validate() -> PackedStringArray:
	for id: String in units:
		var def: Dictionary = units[id]
		var stats: Dictionary = def.get("stats", {})
		for stat: String in REQUIRED_UNIT_STATS:
			if not stats.has(stat):
				_err("unit '%s': missing stat '%s'" % [id, stat])
		for ability_id in def.get("abilities", []):
			if not abilities.has(ability_id):
				_err("unit '%s': unknown ability '%s'" % [id, ability_id])

	for id: String in abilities:
		var def: Dictionary = abilities[id]
		var target: String = def.get("target", "enemy")
		if target not in VALID_TARGETS:
			_err("ability '%s': invalid target '%s'" % [id, target])
		if def.has("affects") and def["affects"] not in VALID_AFFECTS:
			_err("ability '%s': invalid affects '%s'" % [id, def["affects"]])
		_validate_effects("ability '%s'" % id, def.get("effects", []))

	for id: String in statuses:
		_validate_effects("status '%s'" % id, statuses[id].get("on_turn_start", []))

	for id: String in maps:
		var def: Dictionary = maps[id]
		if not def.has("width") or not def.has("height"):
			_err("map '%s': needs width and height" % id)
		for terrain_id: String in def.get("terrain", {}):
			if not terrain.has(terrain_id):
				_err("map '%s': unknown terrain '%s'" % [id, terrain_id])

	for id: String in scenarios:
		var def: Dictionary = scenarios[id]
		if not maps.has(def.get("map", "")):
			_err("scenario '%s': unknown map '%s'" % [id, def.get("map", "")])
		for team_def: Dictionary in def.get("teams", []):
			for unit_entry: Dictionary in team_def.get("units", []):
				if not units.has(unit_entry.get("unit", "")):
					_err("scenario '%s': unknown unit '%s'" % [id, unit_entry.get("unit", "")])

	for id: String in galaxy_terrain:
		_validate_battle_map("galaxy terrain '%s'" % id, galaxy_terrain[id])
	for id: String in discoveries:
		for o: Dictionary in discoveries[id].get("outcomes", []):
			var r: Dictionary = o.get("rewards", {})
			if r.has("ship") and not units.has(r["ship"]):
				_err("discovery '%s': unknown ship '%s'" % [id, r["ship"]])
			if r.has("item") and not items.has(r["item"]):
				_err("discovery '%s': unknown item '%s'" % [id, r["item"]])
	for id: String in campaigns:
		# Generated sectors: check what the generator makes from a couple of seeds.
		if campaigns[id].has("generate"):
			for test_seed in [1, 2]:
				_validate_campaign("%s (seed %d)" % [id, test_seed], GalaxyGenerator.generate(self, campaigns[id], test_seed))
		else:
			_validate_campaign(id, campaigns[id])

	for id: String in hero_classes:
		var def: Dictionary = hero_classes[id]
		for stat: String in REQUIRED_UNIT_STATS:
			if not def.get("stats", {}).has(stat):
				_err("hero class '%s': missing stat '%s'" % [id, stat])
		for level: String in def.get("skills", {}):
			for ability_id in def["skills"][level]:
				if not abilities.has(ability_id):
					_err("hero class '%s': unknown skill '%s'" % [id, ability_id])
		if def.has("command_status") and not statuses.has(def["command_status"]):
			_err("hero class '%s': unknown command_status '%s'" % [id, def["command_status"]])
	for id: String in items:
		if items[id].get("slot", "") not in ITEM_SLOTS:
			_err("item '%s': slot must be one of %s" % [id, ITEM_SLOTS])
		for ability_id in items[id].get("abilities", []):
			if not abilities.has(ability_id):
				_err("item '%s': unknown ability '%s'" % [id, ability_id])
	for id: String in missions:
		_validate_mission(id, missions[id])
	_validate_empire()
	for id: String in units:
		var model: String = units[id].get("visual", {}).get("model", "")
		if not model.is_empty() and not models.has(model):
			_err("unit '%s': unknown model '%s'" % [id, model])
	for id: String in species:
		var ability: String = species[id].get("squad_ability", "")
		if not ability.is_empty() and not abilities.has(ability):
			_err("species '%s': unknown squad ability '%s'" % [id, ability])
		var names: Dictionary = species[id].get("names", {})
		for key: String in ["fleets", "heroes", "ship_names"]:
			if names.has(key) and (not names[key] is Array or names[key].is_empty()):
				_err("species '%s': names.%s must be a non-empty list" % [id, key])
		for e: Dictionary in species[id].get("effects", []):
			if e.get("type", "") == "ship_status" and not statuses.has(e.get("status", "")):
				_err("species '%s': unknown status '%s'" % [id, e.get("status", "")])
	for id: String in models:
		var base: String = models[id].get("base", "")
		if not base.is_empty() and not models.has(base):
			_err("model '%s': unknown base '%s'" % [id, base])
	return errors


func _validate_empire() -> void:
	for id: String in buildings:
		var def: Dictionary = buildings[id]
		if def.has("requires_tech") and not techs.has(def["requires_tech"]):
			_err("building '%s': unknown tech '%s'" % [id, def["requires_tech"]])
		if def.has("defense_unit") and not units.has(def["defense_unit"]):
			_err("building '%s': unknown defense unit '%s'" % [id, def["defense_unit"]])
		for k: String in def.get("cost", {}).keys() + def.get("yields", {}).keys():
			if not resources.has(k):
				_err("building '%s': unknown resource '%s'" % [id, k])
	for id: String in techs:
		var def: Dictionary = techs[id]
		for req: String in def.get("requires", []):
			if not techs.has(req):
				_err("tech '%s': unknown prerequisite '%s'" % [id, req])
		for e: Dictionary in def.get("effects", []):
			match e.get("type", ""):
				"ship_status":
					if not statuses.has(e.get("status", "")):
						_err("tech '%s': unknown status '%s'" % [id, e.get("status", "")])
				"unlock_building":
					if not buildings.has(e.get("building", "")):
						_err("tech '%s': unknown building '%s'" % [id, e.get("building", "")])
				"unlock_unit":
					if not units.has(e.get("unit", "")):
						_err("tech '%s': unknown unit '%s'" % [id, e.get("unit", "")])
				"unlock_megaproject":
					if not megaprojects.has(e.get("megaproject", "")):
						_err("tech '%s': unknown megaproject '%s'" % [id, e.get("megaproject", "")])
				"yield":
					if not resources.has(e.get("resource", "")):
						_err("tech '%s': unknown resource '%s'" % [id, e.get("resource", "")])
				"empire_modifier":
					pass
				"body_bonus":
					_validate_body_bonus(id, e)
				_:
					_err("tech '%s': unknown effect type '%s'" % [id, e.get("type", "")])
	for id: String in units:
		var req: String = units[id].get("strategic", {}).get("requires_tech", "")
		if not req.is_empty() and not techs.has(req):
			_err("unit '%s': unknown tech '%s'" % [id, req])
	for id: String in techs:
		var era: int = int(techs[id].get("era", 1))
		if not eras.has(str(era)):
			_err("tech '%s': unknown era %d" % [id, era])
		for req: String in techs[id].get("requires", []):
			if int(techs.get(req, {}).get("era", 1)) > era:
				_err("tech '%s' (era %d) requires '%s' of a later era" % [id, era, req])
	for id: String in eras:
		var need: Dictionary = eras[id].get("requires", {})
		if not need.is_empty() and not eras.has(str(int(need.get("era", 0)))):
			_err("era '%s': requires unknown era %s" % [id, need.get("era", "")])
	for id: String in megaprojects:
		var def: Dictionary = megaprojects[id]
		if not techs.has(def.get("requires_tech", "")):
			_err("megaproject '%s': unknown tech '%s'" % [id, def.get("requires_tech", "")])
		if def.get("scope", "empire") not in ["empire", "galaxy"]:
			_err("megaproject '%s': scope must be empire or galaxy" % id)
		for k: String in def.get("cost", {}).keys() + def.get("yields", {}).keys():
			if not resources.has(k):
				_err("megaproject '%s': unknown resource '%s'" % [id, k])
	for id: String in events:
		EventRules.validate_event(self, id, events[id])
	for id: String in campaigns:
		var def: Dictionary = campaigns[id]
		for p: Dictionary in def.get("planets", []):
			for b: String in p.get("buildings", []):
				if not buildings.has(b):
					_err("campaign '%s': planet '%s' has unknown building '%s'" % [id, p.get("id", ""), b])


func _validate_body_bonus(tech_id: String, e: Dictionary) -> void:
	for t: String in e.get("body_types", []):
		if not body_types.has(t):
			_err("tech '%s': unknown body type '%s'" % [tech_id, t])
	var categories: Array[String] = []
	for def: Dictionary in body_types.values():
		categories.append(def.get("category", ""))
	for c: String in e.get("categories", []):
		if c not in categories:
			_err("tech '%s': unknown body category '%s'" % [tech_id, c])
	if e.has("building") and not buildings.has(e["building"]):
		_err("tech '%s': unknown building '%s'" % [tech_id, e["building"]])
	for k: String in e.get("yields", {}):
		if not resources.has(k):
			_err("tech '%s': unknown resource '%s'" % [tech_id, k])
	if e.get("yields", {}).is_empty() and int(e.get("colony_slots", 0)) == 0 and int(e.get("pop_cap", 0)) == 0 \
			and float(e.get("growth", 0.0)) == 0.0:
		_err("tech '%s': body_bonus gives nothing (needs yields, colony_slots, pop_cap or growth)" % tech_id)


func _validate_mission(id: String, def: Dictionary) -> void:
	var owner := "mission '%s'" % id
	var map_def: Dictionary = maps.get(def.get("map", ""), {})
	if map_def.is_empty():
		_err("%s: unknown map '%s'" % [owner, def.get("map", "")])
	elif map_def.get("deployment", {}).get("squad", []).size() < int(def.get("squad_size", 4)):
		_err("%s: map '%s' needs at least %d deployment.squad slots" % [owner, def["map"], int(def.get("squad_size", 4))])
	if not units.has(def.get("marine_unit", "marine")):
		_err("%s: unknown marine_unit '%s'" % [owner, def.get("marine_unit", "marine")])
	for e: Dictionary in def.get("enemies", []):
		if not units.has(e.get("unit", "")):
			_err("%s: unknown enemy unit '%s'" % [owner, e.get("unit", "")])
	for item_id in def.get("rewards", {}).get("items", []):
		if not items.has(item_id):
			_err("%s: unknown reward item '%s'" % [owner, item_id])
	var follow_up: String = def.get("on_failure", {}).get("mission", "")
	if not follow_up.is_empty() and not missions.has(follow_up):
		_err("%s: unknown follow-up mission '%s'" % [owner, follow_up])
	for trigger: Dictionary in def.get("triggers", []):
		if trigger.has("round") == trigger.has("cells"):
			_err("%s: trigger '%s' needs either cells or a round" % [owner, trigger.get("id", "")])
		if trigger.has("round") and trigger.has("choices"):
			_err("%s: timed trigger '%s' can't offer choices" % [owner, trigger.get("id", "")])
		var all_effects: Array = trigger.get("effects", []).duplicate()
		for choice: Dictionary in trigger.get("choices", []):
			all_effects.append_array(choice.get("effects", []))
			all_effects.append_array(choice.get("fail_effects", []))
			if choice.has("check") and choice["check"].get("skill", "") not in SKILLS:
				_err("%s: trigger '%s' checks unknown skill '%s' (use %s)" % [owner, trigger.get("id", ""),
						choice["check"].get("skill", ""), ", ".join(SKILLS)])
		for fx: Dictionary in all_effects:
			var kind: String = fx.get("type", "")
			if kind not in TRIGGER_EFFECTS:
				_err("%s: trigger '%s' has unknown effect '%s'" % [owner, trigger.get("id", ""), kind])
			elif kind == "spawn":
				for entry: Dictionary in fx.get("units", []):
					if not units.has(entry.get("unit", "")):
						_err("%s: trigger spawns unknown unit '%s'" % [owner, entry.get("unit", "")])
			elif kind == "reward":
				for item_id in fx.get("items", []):
					if not items.has(item_id):
						_err("%s: trigger rewards unknown item '%s'" % [owner, item_id])
				if fx.has("trait") and not traits.has(fx["trait"]):
					_err("%s: trigger grants unknown trait '%s'" % [owner, fx["trait"]])
			elif kind == "effect":
				_validate_effects(owner, [fx.get("effect", {})])


func _validate_campaign(id: String, def: Dictionary) -> void:
	var owner := "campaign '%s'" % id
	var map_def: Dictionary = def.get("map", {})
	if not map_def.has("width") or not map_def.has("height"):
		_err("%s: map needs width and height" % owner)
	for terrain_id: String in map_def.get("terrain", {}):
		if not galaxy_terrain.has(terrain_id):
			_err("%s: unknown galaxy terrain '%s'" % [owner, terrain_id])
	_validate_battle_map(owner, def)
	var faction_ids: Array = []
	for f: Dictionary in def.get("factions", []):
		faction_ids.append(f.get("id", ""))
		if not f.get("species", "").is_empty() and not species.has(f["species"]):
			_err("%s: faction '%s' has unknown species '%s'" % [owner, f.get("id", ""), f["species"]])
		if f.get("role", "major") not in ["major", "barbarian", "minor"]:
			_err("%s: faction '%s' has unknown role '%s'" % [owner, f.get("id", ""), f["role"]])
	for p: Dictionary in def.get("planets", []):
		if p.has("star") and not star_types.has(p["star"]):
			_err("%s: system '%s' has unknown star '%s'" % [owner, p.get("name", ""), p["star"]])
		var listed: Variant = p.get("bodies", "random")
		if listed is Array:
			for b: Dictionary in listed:
				if not body_types.has(b.get("type", "")):
					_err("%s: system '%s' has a body of unknown type '%s'" % [owner, p.get("name", ""), b.get("type", "")])
				for building_id: String in b.get("buildings", []):
					if not buildings.has(building_id):
						_err("%s: system '%s' has unknown building '%s'" % [owner, p.get("name", ""), building_id])
				for t: String in b.get("traits", []):
					if not planet_traits.has(t):
						_err("%s: system '%s' has unknown trait '%s'" % [owner, p.get("name", ""), t])
		if p.get("owner", "") != "" and p["owner"] not in faction_ids:
			_err("%s: planet '%s' has unknown owner '%s'" % [owner, p.get("name", ""), p["owner"]])
	var fleet_names: Array = []
	for fl: Dictionary in def.get("fleets", []):
		fleet_names.append(fl.get("name", ""))
	var planet_ids: Array = []
	for p: Dictionary in def.get("planets", []):
		planet_ids.append(p.get("id", ""))
	for h: Dictionary in def.get("heroes", []):
		var hero := "%s: hero '%s'" % [owner, h.get("id", "")]
		if not hero_classes.has(h.get("class", "")):
			_err("%s has unknown class '%s'" % [hero, h.get("class", "")])
		if h.get("owner", "") not in faction_ids:
			_err("%s has unknown owner '%s'" % [hero, h.get("owner", "")])
		if h.has("fleet") and h["fleet"] not in fleet_names:
			_err("%s commands unknown fleet '%s'" % [hero, h["fleet"]])
		if h.has("planet") and h["planet"] not in planet_ids:
			_err("%s is at unknown planet '%s'" % [hero, h["planet"]])
		for slot: String in h.get("gear", {}):
			var item: Dictionary = items.get(h["gear"][slot], {})
			if item.is_empty() or item.get("slot", "") != slot:
				_err("%s: '%s' is not a %s item" % [hero, h["gear"][slot], slot])
		for trait_id in h.get("traits", []):
			if not traits.has(trait_id):
				_err("%s has unknown trait '%s'" % [hero, trait_id])
	for faction_id: String in def.get("inventory", {}):
		for item_id in def["inventory"][faction_id]:
			if not items.has(item_id):
				_err("%s: inventory has unknown item '%s'" % [owner, item_id])
	for a: Dictionary in def.get("anomalies", []):
		if not missions.has(a.get("mission", "")):
			_err("%s: anomaly '%s' has unknown mission '%s'" % [owner, a.get("id", ""), a.get("mission", "")])
	for fl: Dictionary in def.get("fleets", []):
		if fl.get("owner", "") not in faction_ids:
			_err("%s: fleet '%s' has unknown owner '%s'" % [owner, fl.get("name", ""), fl.get("owner", "")])
		for ship: Dictionary in fl.get("ships", []):
			if not units.has(ship.get("unit", "")):
				_err("%s: fleet '%s' has unknown unit '%s'" % [owner, fl.get("name", ""), ship.get("unit", "")])


## Galaxy locations name the tactical map their battles are fought on; that
## map must exist and have deployment slots for both sides.
func _validate_battle_map(owner: String, def: Dictionary) -> void:
	var key := "default_battle_map" if def.has("default_battle_map") else "battle_map"
	if not def.has(key):
		return
	var map_def: Dictionary = maps.get(def[key], {})
	if map_def.is_empty():
		_err("%s: unknown battle map '%s'" % [owner, def[key]])
	elif not map_def.get("deployment", {}).has("west") or not map_def.get("deployment", {}).has("east"):
		_err("%s: battle map '%s' needs deployment.west and deployment.east" % [owner, def[key]])


func _validate_effects(owner: String, effects: Array) -> void:
	for effect: Dictionary in effects:
		if not effect.has("type"):
			_err("%s: effect without 'type'" % owner)
			continue
		if effect["type"] == "damage" and not damage_types.has(effect.get("damage_type", "")):
			_err("%s: unknown damage_type '%s'" % [owner, effect.get("damage_type", "")])
		if effect["type"] == "apply_status" and not statuses.has(effect.get("status", "")):
			_err("%s: unknown status '%s'" % [owner, effect.get("status", "")])


func _load_dir(path: String, target: Dictionary) -> void:
	var files := JsonUtil.list_files(path)
	for file in files:
		var parsed: Variant = JsonUtil.load_file(file)
		if not parsed is Dictionary:
			_err("%s: expected a JSON object" % file)
			continue
		var def: Dictionary = parsed
		var id: String = def.get("id", file.get_file().get_basename())
		if target.has(id):
			_err("%s: duplicate id '%s'" % [file, id])
		def["id"] = id
		target[id] = def


func _load_keyed_file(path: String, target: Dictionary) -> void:
	var parsed: Variant = JsonUtil.load_file(path)
	if not parsed is Dictionary:
		_err("%s: expected a JSON object keyed by id" % path)
		return
	for id: String in parsed:
		var def: Dictionary = parsed[id]
		def["id"] = id
		target[id] = def


func _err(message: String) -> void:
	if message not in errors:
		errors.append(message)
