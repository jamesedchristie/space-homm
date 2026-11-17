class_name SpeciesNaming
extends RefCounted
## Renames a faction's home system, starting fleets, ships and heroes to match
## a species ("names" in data/strategic/species.json). Used when the player
## picks a species other than the campaign's default, so a Kesh player doesn't
## start at "Haven" under "Cmdr. Ana Reyes". Works on a campaign definition
## (hand-made "planets"/"fleets"/"heroes", or a template's "generate" block)
## before the engine is built, so it needs no presentation code.


## A copy of the campaign where the player's faction plays `species_id`: the
## faction takes the species' empire name and names (home, fleets, heroes), and
## an AI major that had that species swaps to the player's original one (with
## its names). Returns the copy; the campaign is unchanged.
static func with_player_species(campaign: Dictionary, species_id: String, data: DataRegistry) -> Dictionary:
	var def: Dictionary = campaign.duplicate(true)
	var player: Dictionary = {}
	for f: Dictionary in def["factions"]:
		if f.get("controller", "") == "player":
			player = f
	if player.is_empty() or player.get("species", "") == species_id or not data.species.has(species_id):
		return def
	var original: String = player.get("species", "")
	for f: Dictionary in def["factions"]:
		if f != player and f.get("species", "") == species_id and f.get("role", "major") == "major":
			f["species"] = original
			if data.species.has(original):
				f["name"] = data.species[original]["empire_name"]
			apply(def, f["id"], original, data)
	player["species"] = species_id
	player["name"] = data.species[species_id]["empire_name"]
	apply(def, player["id"], species_id, data)
	return def


## Renames everything `faction_id` starts with. Hero ids, classes and gear are
## kept; heroes' "fleet" references follow the renamed fleets. Species without
## naming data leave the definition untouched.
static func apply(def: Dictionary, faction_id: String, species_id: String, data: DataRegistry) -> void:
	var names: Dictionary = data.species.get(species_id, {}).get("names", {})
	if names.is_empty():
		return
	_rename_home(def, faction_id, names)
	var fleet_names := _rename_fleets(def, faction_id, names)
	_rename_heroes(def, faction_id, names, fleet_names)


## The container holding "fleets"/"heroes"/"planets" lists: the template's
## "generate" block when there is one, else the definition itself.
static func _lists(def: Dictionary, key: String) -> Array:
	var out: Array = []
	if def.has(key):
		out.append(def[key])
	if def.get("generate", {}).has(key):
		out.append(def["generate"][key])
	return out


static func _rename_home(def: Dictionary, faction_id: String, names: Dictionary) -> void:
	var home_name: String = names.get("home", "")
	if home_name.is_empty():
		return
	var homes: Dictionary = def.get("generate", {}).get("homes", {})
	if homes.has(faction_id):
		_rename_planet(homes[faction_id], home_name, names)
	for planets: Array in _lists(def, "planets"):
		for p: Dictionary in planets:
			if p.get("owner", "") == faction_id:
				_rename_planet(p, home_name, names)
				break  # the first system they own is their home


static func _rename_planet(planet: Dictionary, home_name: String, names: Dictionary) -> void:
	var old_name: String = planet.get("name", "")
	planet["name"] = home_name
	if names.has("home_description") and planet.has("description"):
		planet["description"] = names["home_description"]
	for b: Dictionary in planet.get("bodies", []):
		if b.get("name", "") == old_name:
			b["name"] = home_name


## Returns {old fleet name: new fleet name}. Ships take names from the
## species' ship_names in order.
static func _rename_fleets(def: Dictionary, faction_id: String, names: Dictionary) -> Dictionary:
	var fleet_names: Array = names.get("fleets", [])
	var ship_names: Array = names.get("ship_names", [])
	var map := {}
	var n := 0
	var ship_i := 0
	for fleets: Array in _lists(def, "fleets"):
		for f: Dictionary in fleets:
			if f.get("owner", "") != faction_id:
				continue
			var old_name: String = f.get("name", "")
			var new_name: String = old_name
			if n < fleet_names.size():
				new_name = fleet_names[n]
			elif not fleet_names.is_empty():
				new_name = "%s %d" % [fleet_names[0], n + 1]
			n += 1
			f["name"] = new_name
			map[old_name] = new_name
			for ship: Dictionary in f.get("ships", []):
				if not ship_names.is_empty():
					ship["name"] = ship_names[ship_i % ship_names.size()]
					ship_i += 1
	return map


static func _rename_heroes(def: Dictionary, faction_id: String, names: Dictionary, fleet_names: Dictionary) -> void:
	var hero_names: Array = names.get("heroes", [])
	var n := 0
	for heroes: Array in _lists(def, "heroes"):
		for h: Dictionary in heroes:
			if h.get("owner", "") != faction_id:
				continue
			if n < hero_names.size():
				h["name"] = hero_names[n]
			n += 1
			if fleet_names.has(h.get("fleet", "")):
				h["fleet"] = fleet_names[h["fleet"]]
