class_name SystemBattleMap
extends RefCounted
## Builds the tactical map for a battle fought INSIDE a star system: the star
## off one edge, planets and moons as impassable discs, an asteroid belt as a
## curved band of rock and debris. Same Dictionary format as
## data/tactical/maps/*.json (so BattleEngine.from_scenario can take it as the
## scenario's "map_def"), plus presentation extras:
##   "star":   {"type", "side": "north", "dir": [x, y]}  (the star lies off the grid that way; dir is a unit vector in grid pixel space)
##   "bodies": [{"id", "type", "name", "kind": "planet"|"belt", "cells": [[col,row]...],
##               "center": [col,row], "radius": float (hex sizes), "colony": bool}]
## Pure and deterministic: the same system (and seed) always gives the same map.
## The attacker deploys on the west edge (the open side). A defender that owns
## a colony deploys in a crescent hugging the colony body, otherwise on the
## east edge. Every layout is checked: deployment slots are free and connected
## and every passable cell is reachable; otherwise another layout is tried and,
## as a last resort, the system is drawn without obstacles.

const SLOTS := 6
## Hex distance kept between two bodies (leaves a lane two hexes wide).
const MIN_GAP := 3
## Columns on each side kept free of terrain (deployment zones).
const EDGE_COLS := 3
const ATTEMPTS := 90

const PLANET := "planet"
const ASTEROID := "asteroid"
const DEBRIS := "debris"


## The map for a battle in `planet`'s system. defending: the system's owner
## defends (its fleet and platforms deploy around its colony).
static func build(data: DataRegistry, planet: Planet, defending: bool = true, extra_seed: int = 0) -> Dictionary:
	var colony_id := ""
	if defending:
		var best := -1
		for b: Dictionary in planet.bodies:
			if "colony" in b.get("buildings", []) and int(b.get("pop", 1)) > best:
				best = int(b.get("pop", 1))
				colony_id = b["id"]
	return build_for(data, planet.id, planet.name, planet.star, planet.bodies, colony_id, extra_seed)


## Same from plain data (standalone scenarios and tests). bodies: [{"id", "type", "name"?}].
static func build_for(data: DataRegistry, system_id: String, system_name: String, star: String, bodies: Array,
		colony_body_id: String = "", extra_seed: int = 0) -> Dictionary:
	var width := 16
	var height := 11
	if bodies.size() >= 5:
		width = 18
		height = 12
	var base_seed := hash(system_id) ^ (extra_seed * 2654435761)
	var rng := RandomNumberGenerator.new()
	for attempt in ATTEMPTS:
		rng.seed = base_seed + attempt * 7919
		var map := _try_layout(data, rng, width, height, bodies, colony_body_id, attempt / 30)
		if map.is_empty():
			continue
		_finish(map, data, system_id, system_name, star, rng)
		if check(map, data.terrain).is_empty():
			return map
	# Last resort: no obstacles at all, the system is only scenery.
	rng.seed = base_seed
	var open := {"grid": "hex", "width": width, "height": height, "terrain": {}, "bodies": [],
			"deployment": {"west": _west_slots(height), "east": _east_slots(width, height)}}
	_finish(open, data, system_id, system_name, star, rng)
	return open


# --- Layout -----------------------------------------------------------------

## Places the bodies; returns {} when no valid placement was found. `shrink`
## makes the discs smaller on later attempts.
static func _try_layout(data: DataRegistry, rng: RandomNumberGenerator, width: int, height: int, bodies: Array,
		colony_body_id: String, shrink: int) -> Dictionary:
	var solids: Array[Dictionary] = []
	var belts: Array[Dictionary] = []
	for b: Dictionary in bodies:
		if b["type"] == "asteroid_belt":
			belts.append(b)
		else:
			solids.append(b)

	var xs: Array[int] = []
	var n := solids.size()
	for i in n:
		xs.append(roundi(lerpf(4.0, float(width - 5), (float(i) + 0.5) / float(n))))
	for i in range(n - 1, 0, -1):  # shuffle
		var j := rng.randi_range(0, i)
		var t := xs[i]
		xs[i] = xs[j]
		xs[j] = t
	var colony_index := -1
	for i in n:
		if solids[i]["id"] == colony_body_id:
			colony_index = i
	if colony_index >= 0:  # the colony sits in the defender's (east) half
		var max_i := 0
		for i in n:
			if xs[i] > xs[max_i]:
				max_i = i
		var t := xs[colony_index]
		xs[colony_index] = xs[max_i]
		xs[max_i] = t

	var occupied: Dictionary = {}  # axial -> true (planet discs)
	var entries: Array[Dictionary] = []
	var terrain: Dictionary = {PLANET: [], ASTEROID: [], DEBRIS: []}
	var taken: Dictionary = {}  # axial -> true (any terrain)
	var colony_cells: Array[Vector2i] = []
	for i in n:
		var b := solids[i]
		var count := _cell_count(data, b["type"])
		if shrink >= 1 and count == 7:
			count = 3
		if shrink >= 2:
			count = 1
		var cells: Array[Vector2i] = []
		var anchor := Vector2i.ZERO
		var ok := false
		for attempt in 16:
			var col := clampi(xs[i] + rng.randi_range(-1, 1), EDGE_COLS + 1, width - EDGE_COLS - 2)
			if attempt > 8:
				col = rng.randi_range(EDGE_COLS + 1, width - EDGE_COLS - 2)
			var row := rng.randi_range(1, height - 2)
			anchor = Hex.oddr_to_axial(Vector2i(col, row))
			cells = _shape(anchor, count)
			if _fits(cells, occupied, width, height):
				ok = true
				break
		if not ok:
			return {}
		for c in cells:
			occupied[c] = true
			taken[c] = true
			terrain[PLANET].append(_pair(c))
		var is_colony: bool = b["id"] == colony_body_id
		if is_colony:
			colony_cells = cells
		entries.append({"id": b["id"], "type": b["type"], "name": b.get("name", ""), "kind": "planet",
				"cells": _pairs(cells), "center": _pair(anchor), "radius": _radius(count), "colony": is_colony})
		if b["type"] == "gas_giant":
			# A broken ring of debris round the giant.
			for c in _ring(anchor, 2):
				if not _in_bounds(Hex.axial_to_oddr(c), width, height) or taken.has(c) or rng.randf() < 0.3:
					continue
				taken[c] = true
				terrain[DEBRIS].append(_pair(c))

	for b in belts:
		var belt := _belt(rng, width, height, occupied)
		if belt.is_empty():
			return {}
		var cells: Array[Vector2i] = []
		for c in belt:
			if taken.has(c):
				continue
			taken[c] = true
			cells.append(c)
			terrain[ASTEROID if rng.randf() < 0.3 else DEBRIS].append(_pair(c))
		entries.append({"id": b["id"], "type": b["type"], "name": b.get("name", ""), "kind": "belt",
				"cells": _pairs(cells), "center": _pair(cells[cells.size() / 2]), "radius": 0.0, "colony": false})

	var west := _west_slots(height)
	var east: Array = _east_slots(width, height)
	if not colony_cells.is_empty():
		east = _crescent(colony_cells, taken, west, width, height)
		if east.size() < SLOTS:
			return {}
	var out_terrain := {}
	for id: String in terrain:
		if not (terrain[id] as Array).is_empty():
			out_terrain[id] = terrain[id]
	return {"grid": "hex", "width": width, "height": height, "terrain": out_terrain, "bodies": entries,
			"deployment": {"west": west, "east": east}}


static func _finish(map: Dictionary, data: DataRegistry, system_id: String, system_name: String, star: String,
		rng: RandomNumberGenerator) -> void:
	var star_def: Dictionary = data.star_types.get(star, {})
	var star_color := Color(star_def.get("color", "#ffd88a"))
	# The star lies beyond the far (north) edge, roughly north: off to the sides it would sit
	# behind a deployment zone.
	var angle := rng.randf_range(-0.45, 0.45)
	var dir := Vector2(sin(angle), -cos(angle))
	map["id"] = "system_%s" % system_id
	map["name"] = "%s System" % system_name
	map["system"] = true
	map["star"] = {"type": star, "side": "north", "dir": [dir.x, dir.y]}
	map["backdrop"] = {"a": "#14224f", "b": star_color.darkened(0.78).to_html(false), "density": 0.45}


## Hexes covered by a body: 1 (moons, rocks, small and mid worlds) or 3 (the largest worlds
## and gas giants). Worlds are small next to their star (which burns far beyond the board).
static func _cell_count(data: DataRegistry, type: String) -> int:
	var size := float(data.body_types.get(type, {}).get("size", 0.6))
	return 3 if size >= 1.0 else 1


## Sphere radius (in hex sizes: 1.0 = a hex's corner radius) that fits inside the disc.
static func _radius(count: int) -> float:
	return 1.15 if count >= 3 else 0.62


static func _shape(anchor: Vector2i, count: int) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	match count:
		1:
			out.append(anchor)
		3:
			out.append_array([anchor, anchor + Vector2i(1, 0), anchor + Vector2i(0, 1)])
		_:
			out.append_array(Hex.within(anchor, 1))
	return out


static func _ring(center: Vector2i, radius: int) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for c in Hex.within(center, radius):
		if Hex.distance(c, center) == radius:
			out.append(c)
	return out


## Inside the grid and outside the deployment columns.
static func _in_bounds(layout: Vector2i, width: int, height: int) -> bool:
	return layout.x >= EDGE_COLS and layout.x < width - EDGE_COLS and layout.y >= 0 and layout.y < height


## Disc cells inside the playable area and far enough from other discs.
static func _fits(cells: Array[Vector2i], occupied: Dictionary, width: int, height: int) -> bool:
	for c in cells:
		var lc := Hex.axial_to_oddr(c)
		if lc.x < EDGE_COLS + 1 or lc.x > width - EDGE_COLS - 2 or lc.y < 1 or lc.y > height - 2:
			return false
		for o: Vector2i in occupied:
			if Hex.distance(c, o) < MIN_GAP:
				return false
	return true


## A curved band of belt cells (axial) crossing part of the height.
static func _belt(rng: RandomNumberGenerator, width: int, height: int, occupied: Dictionary) -> Array[Vector2i]:
	for _try in 12:
		var cx := rng.randi_range(EDGE_COLS + 2, width - EDGE_COLS - 3)
		var length := rng.randi_range(height / 2 - 1, height * 2 / 3)
		var top := rng.randf() < 0.5
		var amp := rng.randi_range(1, 3) * (1 if rng.randf() < 0.5 else -1)
		var out: Array[Vector2i] = []
		var seen := {}
		var good := true
		for k in length:
			var row := k if top else height - 1 - k
			var col := cx + roundi(float(amp) * sin(PI * float(k) / float(maxi(length - 1, 1))))
			var cols: Array[int] = [col]
			if rng.randf() < 0.6:
				cols.append(col + 1)
			for cc in cols:
				var c := Hex.oddr_to_axial(Vector2i(cc, row))
				if not _in_bounds(Vector2i(cc, row), width, height) or seen.has(c):
					continue
				for o: Vector2i in occupied:
					if Hex.distance(c, o) < 2:
						good = false
				seen[c] = true
				out.append(c)
		if good and out.size() >= 5:
			return out
	return []


static func _pair(axial: Vector2i) -> Array:
	var l := Hex.axial_to_oddr(axial)
	return [l.x, l.y]


static func _pairs(cells: Array[Vector2i]) -> Array:
	var out: Array = []
	for c in cells:
		out.append(_pair(c))
	return out


# --- Deployment ---------------------------------------------------------------

## Attacker slots on the west edge, centred on the middle row.
static func _west_slots(height: int) -> Array:
	var c := height / 2
	return [[1, c], [1, c - 2], [1, c + 2], [0, c - 1], [0, c + 1], [1, clampi(c - 4, 0, height - 1)]]


static func _east_slots(width: int, height: int) -> Array:
	var c := height / 2
	return [[width - 2, c], [width - 2, c - 2], [width - 2, c + 2], [width - 1, c - 1], [width - 1, c + 1],
			[width - 2, clampi(c - 4, 0, height - 1)]]


## Free cells closest to the colony disc, those facing the attacker (west) first.
static func _crescent(disc: Array[Vector2i], taken: Dictionary, west: Array, width: int, height: int) -> Array:
	var blocked := taken.duplicate()
	for p: Array in west:
		blocked[Hex.oddr_to_axial(Vector2i(int(p[0]), int(p[1])))] = true
	var centroid := Vector2.ZERO
	for c in disc:
		centroid += Hex.to_pixel(c, 1.0)
	centroid /= float(disc.size())
	var out: Array = []
	for d in range(1, 4):
		var group: Array[Vector2i] = []
		var seen := {}
		for c in disc:
			for nb in _ring(c, d):
				var lc := Hex.axial_to_oddr(nb)
				if seen.has(nb) or blocked.has(nb) or lc.x < 0 or lc.x >= width or lc.y < 0 or lc.y >= height:
					continue
				var nearest := 99
				for o in disc:
					nearest = mini(nearest, Hex.distance(nb, o))
				if nearest == d:
					seen[nb] = true
					group.append(nb)
		group.sort_custom(func(a: Vector2i, b: Vector2i) -> bool:
			var fa := (Hex.to_pixel(a, 1.0) - centroid).normalized().x
			var fb := (Hex.to_pixel(b, 1.0) - centroid).normalized().x
			if absf(fa - fb) > 0.001:
				return fa < fb
			return a.y < b.y or (a.y == b.y and a.x < b.x))
		for c in group:
			if out.size() < SLOTS:
				out.append(_pair(c))
		if out.size() >= SLOTS:
			break
	return out


# --- Validation ---------------------------------------------------------------

## "" if the map is playable, else why not: slots inside the grid, free,
## distinct; every passable cell reachable from the attacker's deployment.
static func check(map_def: Dictionary, terrain_defs: Dictionary) -> String:
	var grid := GridFactory.from_map(map_def, terrain_defs)
	var slots: Array[Vector2i] = []
	for side: String in ["west", "east"]:
		var list: Array = map_def["deployment"][side]
		if list.size() < SLOTS:
			return "%s deployment has %d slots" % [side, list.size()]
		for p: Array in list:
			var c := grid.cell_from_layout(Vector2i(int(p[0]), int(p[1])))
			if not grid.has_cell(c):
				return "%s slot %s is off the grid" % [side, str(p)]
			if not grid.is_passable(c) or grid.terrain_at(c) != "":
				return "%s slot %s is blocked" % [side, str(p)]
			if c in slots:
				return "slot %s used twice" % str(p)
			slots.append(c)
	var seen := {slots[0]: true}
	var queue: Array[Vector2i] = [slots[0]]
	while not queue.is_empty():
		var c: Vector2i = queue.pop_back()
		for nb in grid.neighbors(c):
			if not seen.has(nb) and grid.is_passable(nb):
				seen[nb] = true
				queue.append(nb)
	var passable := 0
	for c in grid.cells():
		if grid.is_passable(c):
			passable += 1
			if not seen.has(c):
				return "cell %s is unreachable" % str(grid.layout_from_cell(c))
	if float(passable) < 0.7 * float(grid.cells().size()):
		return "too little open space (%d of %d)" % [passable, grid.cells().size()]
	return ""
