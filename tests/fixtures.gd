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
	}
	data.units["test_fast_dummy"] = {
		"id": "test_fast_dummy", "name": "Fast Dummy",
		"stats": {"max_hull": 50, "max_shields": 20, "armor": 0, "initiative": 9, "max_ap": 4},
		"abilities": ["test_zap"],
	}
	data.maps["test_open"] = {"id": "test_open", "grid": "hex", "width": 10, "height": 6}
	data.maps["test_wall"] = {
		"id": "test_wall", "grid": "hex", "width": 10, "height": 6,
		"terrain": {"asteroid": [[2, 0], [2, 1], [2, 2], [2, 3], [2, 4]]},
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
