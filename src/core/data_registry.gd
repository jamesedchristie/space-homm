class_name DataRegistry
extends RefCounted
## Loads all game content (JSON under res://data) into plain dictionaries keyed
## by id, and validates cross-references (a unit's abilities exist, a scenario's
## map exists, ...).
##
## Content is data, mechanics are code: adding a ship, ability or scenario should
## only ever mean adding a JSON file.

const DEFAULT_ROOT := "res://data"

const VALID_TARGETS := ["self", "enemy", "ally", "any_unit", "cell"]
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
var planet_types: Dictionary = {}
var campaigns: Dictionary = {}

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
	_load_keyed_file(root.path_join("strategic/planet_types.json"), planet_types)
	_load_dir(root.path_join("strategic/campaigns"), campaigns)
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
	for id: String in planet_types:
		_validate_battle_map("planet type '%s'" % id, planet_types[id])
	for id: String in campaigns:
		_validate_campaign(id, campaigns[id])
	return errors


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
	for p: Dictionary in def.get("planets", []):
		if not planet_types.has(p.get("type", "")):
			_err("%s: planet '%s' has unknown type '%s'" % [owner, p.get("name", ""), p.get("type", "")])
		if p.get("owner", "") != "" and p["owner"] not in faction_ids:
			_err("%s: planet '%s' has unknown owner '%s'" % [owner, p.get("name", ""), p["owner"]])
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
