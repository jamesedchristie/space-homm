extends TestCase
## Species-specific names for homes, fleets, ships and heroes when the player
## picks a species other than the campaign's default.


func _hero(def: Dictionary, hero_id: String) -> Dictionary:
	for h: Dictionary in def["generate"]["heroes"]:
		if h["id"] == hero_id:
			return h
	return {}


func test_kesh_player_gets_kesh_names() -> void:
	var data := DataRegistry.get_default()
	var def := SpeciesNaming.with_player_species(data.campaigns["random_sector"], "kesh", data)
	var gen: Dictionary = def["generate"]
	assert_eq(gen["homes"]["patrol"]["name"], "Khorrak")
	assert_eq(gen["homes"]["patrol"]["id"], "haven", "ids are kept")
	var fleets: Array = gen["fleets"].filter(func(f: Dictionary) -> bool: return f["owner"] == "patrol")
	assert_eq(fleets[0]["name"], "Dominion Warband")
	assert_eq(fleets[1]["name"], "Dominion Hunters")
	assert_eq(_hero(def, "reyes")["name"], "Warlord Drakh")
	assert_eq(_hero(def, "reyes")["fleet"], "Dominion Warband", "hero follows the renamed fleet")
	assert_eq(_hero(def, "reyes")["class"], "vanguard", "class and gear are kept")
	assert_eq(_hero(def, "okafor")["gear"]["weapon"], "assault_rifle")
	# The swapped AI faction plays the player's original species.
	var kesh_ai: Dictionary = def["factions"].filter(func(f: Dictionary) -> bool: return f["id"] == "kesh")[0]
	assert_eq(kesh_ai["species"], "human")
	assert_eq(gen["homes"]["kesh"]["name"], "Haven")
	assert_eq(_hero(def, "drakh")["name"], "Cmdr. Ana Reyes")
	assert_eq(_hero(def, "drakh")["fleet"], "1st Patrol")
	# Other factions are untouched.
	assert_eq(gen["homes"]["veltari"]["name"], "Lumen")
	assert_eq(gen["homes"]["raiders"]["name"], "Rustholm")


func test_source_campaign_is_not_modified() -> void:
	var data := DataRegistry.get_default()
	SpeciesNaming.with_player_species(data.campaigns["random_sector"], "sorn", data)
	assert_eq(data.campaigns["random_sector"]["generate"]["homes"]["patrol"]["name"], "Haven")


func test_every_species_builds_a_valid_engine() -> void:
	var data := DataRegistry.get_default()
	for species_id: String in data.species:
		var def := SpeciesNaming.with_player_species(data.campaigns["random_sector"], species_id, data)
		var engine := GalaxyEngine.from_campaign(data, def, 1234)
		assert_true(engine != null, "engine for %s" % species_id)
		var home_name: String = data.species[species_id]["names"]["home"]
		var player_home: Planet = engine.state.planets["haven"]
		assert_eq(player_home.name, home_name)
		for h: Hero in engine.state.heroes.values():
			if h.owner == "patrol" and h.id == "reyes":
				assert_false(h.fleet_id.is_empty(), "commander still leads a fleet")
				assert_eq(engine.state.fleets[h.fleet_id].name, data.species[species_id]["names"]["fleets"][0])
