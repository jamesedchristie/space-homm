class_name Fixtures
extends RefCounted
## Shared test helpers: the real content registry plus test-only definitions
## with round numbers, and a builder for small inline scenarios.


## Real content from res://data plus "dummy" units and "zap" abilities whose
## numbers are fixed, so engine tests don't break when content is rebalanced.
static func registry() -> DataRegistry:
	var data := DataRegistry.new()
	data.load_from(DataRegistry.DEFAULT_ROOT)
	data.damage_types["test_flat"] = {"id": "test_flat", "vs_shields": 1.0, "vs_hull": 1.0}
	data.abilities["test_zap"] = {
		"id": "test_zap", "name": "Zap", "ap_cost": 2, "target": "enemy", "range": [1, 3],
		"requires_los": true,
		"effects": [{"type": "damage", "amount": 10, "damage_type": "test_flat"}],
	}
	data.abilities["test_stun"] = {
		"id": "test_stun", "name": "Stun", "ap_cost": 1, "cooldown": 2, "target": "enemy", "range": [1, 5],
		"effects": [{"type": "apply_status", "status": "disabled", "duration": 1}],
	}
	data.abilities["test_bomb"] = {
		"id": "test_bomb", "name": "Bomb", "ap_cost": 1, "target": "cell", "range": [0, 6], "radius": 1,
		"effects": [{"type": "damage", "amount": 1000, "damage_type": "test_flat"}],
	}
	data.units["test_dummy"] = {
		"id": "test_dummy", "name": "Dummy",
		"stats": {"max_hull": 50, "max_shields": 20, "armor": 0, "initiative": 5, "max_ap": 4},
		"abilities": ["test_zap", "test_stun", "test_bomb", "brace_shields"],
		"strategic": {"speed": 3, "sensor": 1},
	}
	data.units["test_fast_dummy"] = {
		"id": "test_fast_dummy", "name": "Fast Dummy",
		"stats": {"max_hull": 50, "max_shields": 20, "armor": 0, "initiative": 9, "max_ap": 4},
		"abilities": ["test_zap"],
		"strategic": {"speed": 5, "sensor": 3},
	}
	data.maps["test_open"] = {"id": "test_open", "grid": "hex", "width": 10, "height": 6}
	data.maps["test_wall"] = {
		"id": "test_wall", "grid": "hex", "width": 10, "height": 6,
		"terrain": {"asteroid": [[2, 0], [2, 1], [2, 2], [2, 3], [2, 4]]},
	}
	# 8x6 square room with a wall segment and one crate.
	data.maps["test_room"] = {
		"id": "test_room", "grid": "square", "width": 8, "height": 6,
		"terrain": {"wall": [[3, 0], [3, 1], [3, 2], [3, 3]], "crates": [[6, 5]]},
		"deployment": {"squad": [[0, 4], [0, 5], [1, 5]]},
	}
	data.validate()
	return data


## units: [[team, unit_def_id, col, row], ...]
static func scenario(map_id: String, units: Array, objectives: Array = []) -> Dictionary:
	var teams := {}
	for entry: Array in units:
		var team: int = entry[0]
		if not teams.has(team):
			teams[team] = {"team": team, "controller": "ai", "units": []}
		teams[team]["units"].append({"unit": entry[1], "at": [entry[2], entry[3]]})
	var def := {"id": "test", "map": map_id, "teams": teams.values()}
	if not objectives.is_empty():
		def["objectives"] = objectives
	return def


static func engine(map_id: String, units: Array, rng_seed: int = 12345, objectives: Array = []) -> BattleEngine:
	return BattleEngine.from_scenario(registry(), scenario(map_id, units, objectives), rng_seed)


## Small 10x6 galaxy: faction "a" (player) vs "b" (ai), one planet each plus a
## neutral one in the middle. fleets: [[owner, unit_def_id, col, row], ...]
static func campaign(fleets: Array, extra: Dictionary = {}) -> Dictionary:
	var fleet_defs: Array = []
	for f: Array in fleets:
		fleet_defs.append({"name": "%s fleet %d" % [f[0], fleet_defs.size()], "owner": f[0],
				"at": [f[2], f[3]], "ships": [{"unit": f[1], "name": "%s ship %d" % [f[0], fleet_defs.size()]}]})
	var def := {
		"id": "test_campaign",
		"default_battle_map": "open_space",
		"map": {"grid": "hex", "width": 10, "height": 6, "terrain": {"nebula": [[5, 0]]}},
		"factions": [{"id": "a", "controller": "player"}, {"id": "b", "controller": "ai"}],
		"planets": [
			{"id": "home_a", "at": [0, 5], "owner": "a", "star": "yellow",
				"bodies": [{"type": "terran", "buildings": ["colony"]}, {"type": "barren"}, {"type": "gas_giant"}]},
			{"id": "home_b", "at": [9, 5], "owner": "b", "star": "red",
				"bodies": [{"type": "desert", "buildings": ["colony"]}, {"type": "asteroid_belt"}]},
			{"id": "middle", "at": [5, 3], "star": "white", "bodies": [{"type": "ice_moon"}, {"type": "arctic"}]},
		],
		"fleets": fleet_defs,
	}
	def.merge(extra, true)
	return def


static func galaxy(fleets: Array, extra: Dictionary = {}, rng_seed: int = 99) -> GalaxyEngine:
	var e := GalaxyEngine.from_campaign(registry(), campaign(fleets, extra), rng_seed)
	e.start()
	return e
