extends TestCase
## LocalBattleMap: battles of a system-scale campaign, fought on the local area round the battle cell.

var _data: DataRegistry


func before_each() -> void:
	_data = Fixtures.registry()


## A description like LocalBattleMap.describe() makes: a body at the battle cell (offset 0,0),
## a moon next to it, belt cells to the east, the star two cells to the north-west.
func _desc(from: Array = [-1, 0], defender_body: String = "home") -> Dictionary:
	var cells: Array = []
	for c in Hex.within(Vector2i.ZERO, 3):
		var entry := {"at": [c.x, c.y], "terrain": ""}
		if c == Vector2i.ZERO:
			entry["body"] = {"id": "home", "type": "terran", "name": "Home", "colony": true}
		elif c == Vector2i(0, 1):
			entry["body"] = {"id": "moon", "type": "barren", "name": "Home a", "colony": false}
		elif c == Vector2i(2, -1):
			entry["body"] = {"id": "giant", "type": "gas_giant", "name": "Giant", "colony": false}
		elif c.x >= 2 and c.y >= 0:
			entry["terrain"] = "asteroid_belt"
		elif c == Vector2i(-1, -1):
			entry["terrain"] = "corona"
		elif c == Vector2i(-2, -2):
			entry["terrain"] = "star"
		cells.append(entry)
	return {"id": "t_1", "name": "Home", "star": "yellow", "cells": cells, "star_at": [-2, -2], "from": from,
			"defender_body": defender_body}


func _grid(map: Dictionary) -> TacticalGrid:
	return GridFactory.from_map(map, _data.terrain)


func _cells(grid: TacticalGrid, pairs: Array) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for p: Array in pairs:
		out.append(grid.cell_from_layout(Vector2i(int(p[0]), int(p[1]))))
	return out


func test_deterministic() -> void:
	var a := LocalBattleMap.build(_data, _desc())
	var b := LocalBattleMap.build(_data, _desc())
	assert_eq(var_to_str(a), var_to_str(b), "same place, same map")
	assert_true(a.get("local", false))
	assert_eq(a["width"], LocalBattleMap.WIDTH)
	assert_eq(SystemBattleMap.check(a, _data.terrain, LocalBattleMap.MIN_OPEN), "")


func test_bodies_are_impassable_discs_sized_by_body() -> void:
	var map := LocalBattleMap.build(_data, _desc())
	var grid := _grid(map)
	var sizes := {}
	for body: Dictionary in map["bodies"]:
		if body["kind"] != "planet":
			continue
		var cells := _cells(grid, body["cells"])
		sizes[body["id"]] = cells.size()
		for c in cells:
			assert_false(grid.is_passable(c), "%s is impassable" % body["id"])
			assert_true(grid.blocks_sight(c))
	assert_eq(sizes.get("home", 0), 3, "a terran world covers 3 hexes")
	assert_eq(sizes.get("moon", 0), 1, "a moon one")
	assert_true(int(sizes.get("giant", 0)) >= 4, "a gas giant the most")
	# The home world sits in the middle of the map.
	var home: Dictionary = map["bodies"].filter(func(b: Dictionary) -> bool: return b["id"] == "home")[0]
	assert_eq(home["center"], [LocalBattleMap.WIDTH / 2, LocalBattleMap.HEIGHT / 2])
	assert_true(home["colony"])


func test_star_glare_and_belt_bands() -> void:
	var map := LocalBattleMap.build(_data, _desc())
	var terrain: Dictionary = map["terrain"]
	assert_true(terrain.has("glare"), "the corona's patch is glare")
	assert_true(terrain.has("asteroid") or terrain.has("debris"), "the belt is rock and debris")
	assert_false(_data.terrain["glare"]["passable"])
	# Glare lies towards the star (north-west of the centre).
	var grid := _grid(map)
	var center := Hex.to_pixel(grid.cell_from_layout(Vector2i(LocalBattleMap.WIDTH / 2, LocalBattleMap.HEIGHT / 2)), 1.0)
	var toward := Vector2.ZERO
	for c in _cells(grid, terrain["glare"]):
		toward += Hex.to_pixel(c, 1.0) - center
	assert_true(toward.x < 0.0 and toward.y < 0.0)
	var dir: Array = map["star"]["dir"]
	assert_true(float(dir[0]) < 0.0 and float(dir[1]) < 0.0, "the scenery's star is that way too")


func test_attacker_enters_from_where_it_came() -> void:
	for from: Array in [[-1, 0], [1, 0], [0, 1], [1, -1]]:
		var map := LocalBattleMap.build(_data, _desc(from))
		var grid := _grid(map)
		var center := Hex.to_pixel(grid.cell_from_layout(Vector2i(LocalBattleMap.WIDTH / 2, LocalBattleMap.HEIGHT / 2)), 1.0)
		var dir := Hex.to_pixel(Vector2i(int(from[0]), int(from[1])), 1.0).normalized()
		var mean := Vector2.ZERO
		for c in _cells(grid, map["deployment"]["west"]):
			mean += Hex.to_pixel(c, 1.0) - center
		mean /= 6.0
		assert_true(mean.normalized().dot(dir) > 0.7, "attacker from %s deploys on that side" % str(from))
		assert_true(mean.length() > 4.0, "out near the edge")


func test_deployment_is_free_and_connected() -> void:
	for from: Array in [[-1, 0], [1, 1], [0, -1]]:
		for defender in ["home", ""]:
			var map := LocalBattleMap.build(_data, _desc(from, defender))
			assert_eq(SystemBattleMap.check(map, _data.terrain, LocalBattleMap.MIN_OPEN), "", "from %s, defender '%s'" % [str(from), defender])
			var grid := _grid(map)
			var defenders := _cells(grid, map["deployment"]["east"])
			assert_eq(defenders.size(), 6)
			if defender == "home":
				# A defender holding the world deploys hugging it.
				var disc := _cells(grid, map["bodies"].filter(func(b: Dictionary) -> bool: return b["id"] == "home")[0]["cells"])
				for c in defenders:
					var nearest := 99
					for d in disc:
						nearest = mini(nearest, grid.distance(c, d))
					assert_true(nearest <= 3)


func test_open_space_battle_without_bodies() -> void:
	var desc := {"id": "void", "name": "deep space", "star": "red", "cells": [], "from": [0, -1], "defender_body": ""}
	var map := LocalBattleMap.build(_data, desc)
	assert_eq(SystemBattleMap.check(map, _data.terrain, LocalBattleMap.MIN_OPEN), "")
	assert_true(map["terrain"].is_empty())
	assert_eq(map["name"], "Deep space")
	var scenario := {"id": "t", "map": map["id"], "map_def": map, "max_rounds": 5,
			"teams": [{"team": 0, "name": "A", "controller": "ai", "units": [{"unit": "test_dummy", "at": map["deployment"]["west"][0]}]},
					{"team": 1, "name": "B", "controller": "ai", "units": [{"unit": "test_dummy", "at": map["deployment"]["east"][0]}]}],
			"objectives": [{"type": "eliminate_all"}]}
	var battle := BattleEngine.from_scenario(_data, scenario, 3)
	assert_true(battle != null and battle.state.units.size() == 2)
