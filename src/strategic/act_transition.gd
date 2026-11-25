class_name ActTransition
extends RefCounted
## Act 1 -> Act 2. When the player wins Solar Age (Hyperdrive), the game goes on in a generated
## hyperlane galaxy (the Random Sector template) with the player's empire carried over: the home
## system as it stands (every body, its deposits, traits, developments and population), known techs,
## part of the treasury, warfleets, civilian ships, heroes and items. The rival empires arrive just
## as far along: founded capitals and the same techs. Pure: builds a campaign definition that
## GalaxyEngine.from_campaign generates from a seed.

const TEMPLATE := "random_sector"
## How much of the Act 1 treasury makes the jump (the rest paid for the voyage).
const CARRY_CAP := {"credits": 500, "alloys": 400, "volatiles": 60, "rare_elements": 60, "exotic_matter": 30}
## Bodies of the old home system that come along at most (owned ones first).
const MAX_BODIES := 8


## Whether this finished campaign continues into Act 2 for `player`.
static func can_continue(engine: GalaxyEngine, player: String) -> bool:
	return engine.is_system_scale() and engine.state.is_over and engine.state.winner == player \
			and engine.state.victory_reason == VictoryRules.tech_reason(engine) \
			and engine.data.campaigns.has(TEMPLATE)


static func act2_campaign(data: DataRegistry, act1: GalaxyEngine, player: String) -> Dictionary:
	var s := act1.state
	var species: String = s.faction(player).get("species", "")
	var def: Dictionary = data.campaigns[TEMPLATE].duplicate(true)
	if not species.is_empty():
		def = SpeciesNaming.with_player_species(def, species, data)
	def["name"] = "Act 2: The Reach"
	def["act"] = 2
	def["description"] = "Act 2: through the jump points into a galaxy of hyperlanes."
	var majors: Array = []
	for f: Dictionary in def["factions"]:
		if f.get("role", "major") == "major":
			majors.append(f["id"])
	def["founded"] = majors
	var gen: Dictionary = def["generate"]

	# The home system, carried over.
	var system: Dictionary = act1.campaign.get("system", {})
	var home: Dictionary = gen["homes"][player]
	var name: String = system.get("name", home.get("name", "Home"))
	home["name"] = name
	home["id"] = name.to_snake_case()
	home["star"] = system.get("star", "yellow")
	home["description"] = "Your home system, where the Solar Age began."
	home.erase("buildings")
	var owned: Array = []
	var other: Array = []
	var civilians: Array = []
	for p: Planet in s.planets.values():
		for b: Dictionary in p.bodies:
			var entry := {"type": b["type"], "name": b["name"], "traits": (b.get("traits", []) as Array).duplicate(),
					"deposits": (b.get("deposits", {}) as Dictionary).duplicate()}
			if p.owner == player:
				entry["buildings"] = (b.get("buildings", []) as Array).duplicate()
				if "colony" in entry["buildings"]:
					entry["pop"] = int(b.get("pop", Planet.START_POP))
				owned.append(entry)
			elif data.body_types.has(b["type"]):
				other.append(entry)
		for c: Dictionary in p.civilians:
			if c.get("owner", p.owner) == player:
				civilians.append({"unit": c["unit"], "name": c.get("name", c["unit"]), "owner": player})
	# The capital first (the engine treats the first colony as the home planet).
	owned.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return int(a.get("pop", -1)) > int(b.get("pop", -1)))
	var bodies := owned.slice(0, MAX_BODIES)
	bodies.append_array(other.slice(0, maxi(MAX_BODIES - bodies.size(), 0)))
	home["bodies"] = bodies
	home["civilians"] = civilians

	# Fleets and heroes.
	var fleets: Array = (gen.get("fleets", []) as Array).filter(func(f: Dictionary) -> bool: return f["owner"] != player)
	var fleet_names := {}
	for f: Fleet in s.fleets_of(player):
		var ships: Array = []
		for ship: Dictionary in f.ships:
			ships.append({"unit": ship["unit"], "name": ship.get("name", ship["unit"]), "hull": int(ship.get("hull", 1))})
		if ships.is_empty():
			continue
		fleets.append({"name": f.name, "owner": player, "ships": ships})
		fleet_names[f.id] = f.name
	gen["fleets"] = fleets
	var heroes: Array = (gen.get("heroes", []) as Array).filter(func(h: Dictionary) -> bool: return h["owner"] != player)
	for h: Hero in s.heroes_of(player):
		if h.status in [Hero.DEAD, Hero.CAPTURED]:
			continue
		var h_def := {"id": h.id, "name": h.name, "class": h.class_id, "owner": player, "level": h.level, "xp": h.xp,
				"traits": h.traits.duplicate(), "gear": h.gear.duplicate(), "loyalty": h.loyalty}
		if fleet_names.has(h.fleet_id):
			h_def["fleet"] = fleet_names[h.fleet_id]
		else:
			h_def["planet"] = "home"
		heroes.append(h_def)
	gen["heroes"] = heroes

	# Techs, treasury and items. Rivals know what we know (minus Act 1's system-only techs).
	var techs: Array = []
	for t: String in s.known_techs(player):
		if data.techs.has(t) and data.techs[t].get("scale", "galaxy") == "galaxy":
			techs.append(t)
	var tech_table := {}
	for fid: String in majors:
		tech_table[fid] = techs.duplicate()
	def["techs"] = tech_table
	var stock: Dictionary = s.resources.get(player, {})
	var carried := {}
	for k: String in CARRY_CAP:
		carried[k] = mini(int(stock.get(k, 0)), int(CARRY_CAP[k]))
	var resources: Dictionary = def.get("resources", {})
	for fid: String in majors:
		var base: Dictionary = resources.get(fid, {})
		var mine := carried.duplicate()
		for k: String in base:
			mine[k] = maxi(int(mine.get(k, 0)), int(base[k]))
		resources[fid] = mine
	def["resources"] = resources
	var inventory: Dictionary = def.get("inventory", {})
	inventory[player] = (s.inventory.get(player, []) as Array).duplicate()
	def["inventory"] = inventory

	def["briefing"] = ("[b]Act 2: the Reach.[/b] The jump points of %s open onto a web of hyperlanes. Ships "
			+ "travel only along the lanes, so junctions and chokepoints matter. Every system is charted, but what "
			+ "drifts along the lanes and where the fleets are still needs scouting.\n\nYour home system came with "
			+ "you: its colonies, developments and stores, your fleets and your commanders. You are not alone: the "
			+ "[b]Vel'tari Concord[/b] and the [b]Kesh Dominion[/b] have reached the stars too, raiders prowl "
			+ "the lanes and the Free Traders deal with whoever treats them well.\n\nThree ancient [b]relic gates[/b] "
			+ "(gold rings) link to each other: a fleet at one can jump to any other. Research [b]Gate Engineering[/b] "
			+ "to build your own Jump Gates.\n\n[b]Goal:[/b] outgrow, outwit or outfight your rivals.") % name
	return def
