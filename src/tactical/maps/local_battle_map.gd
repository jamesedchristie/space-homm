class_name LocalBattleMap
extends RefCounted
## The tactical map for a battle in a SYSTEM-SCALE campaign (the strategic map is one star
## system): the battle is fought where the ships are, so the map is the local area round the
## battle cell, blown up. Every strategic hex within reach becomes a patch of tactical hexes
## (about PATCH hexes across, same pointy-top orientation, so the layout reads the same):
##   - a body (a Planet's cell) is a planet disc in the middle of its patch (1, 3 or 7 hexes
##     by body size; impassable, blocks sight); a belt body is a cluster of big rocks,
##   - the star and its corona are an impassable band of glare on the side they lie,
##   - asteroid-belt cells are bands of asteroids (impassable) and debris (2 AP, half cover),
##   - nebulae and storms are patches of nebula, everything else open space.
## Same output as SystemBattleMap (bodies for the 3D scenery, the star's direction,
## deployment "west" = attacker, "east" = defender), and its check() validates the result.
## The attacker deploys on the side it came from (the strategic cell it attacked from); a
## defender holding a body deploys in a crescent round it facing the attacker, otherwise near
## the centre. Pure and deterministic.

const WIDTH := 18
const HEIGHT := 13
## Tactical hexes per strategic hex (the patch a strategic cell becomes).
const PATCH := 3.4
const SLOTS := 6
const ATTEMPTS := 12
## How much of the map must stay open (glare and planets take more room than in SystemBattleMap).
const MIN_OPEN := 0.55

const PLANET := "planet"
const ASTEROID := "asteroid"
const DEBRIS := "debris"
const GLARE := "glare"
const NEBULA := "nebula"


## The local map for the pending battle at `cell` of a system-scale campaign. `from_cell` is the
## strategic cell the attacker came from; `defended` the Planet whose owner defends (or null).
static func build_for(engine: GalaxyEngine, cell: Vector2i, from_cell: Vector2i, defended: Planet) -> Dictionary:
	return build(engine.data, describe(engine, cell, from_cell, defended))


## The plain-data description of the area round `cell` that build() expands (kept separate so
## build() is testable without an engine):
## {"id", "name", "star": type, "cells": [{"at": [dq, dr] (axial offset from the battle cell),
##   "terrain": galaxy terrain id, "body"?: {"id", "type", "name", "colony"}}],
##  "star_at": [dq, dr] (offset of the star, any distance) or absent,
##  "from": [dq, dr] (offset the attacker came from) or absent (west), "defender_body": body id or ""}
static func describe(engine: GalaxyEngine, cell: Vector2i, from_cell: Vector2i, defended: Planet) -> Dictionary:
	var s := engine.state
	var grid := s.grid
	var system: Dictionary = engine.campaign.get("system", {})
	var cells: Array = []
	for c in grid.cells_within(cell, 3):
		var entry := {"at": [c.x - cell.x, c.y - cell.y], "terrain": grid.terrain_at(c)}
		var p := s.planet_at(c)
		if p != null and not p.bodies.is_empty():
			var b := p.main_body(engine.data)
			entry["body"] = {"id": b["id"], "type": b["type"], "name": b.get("name", p.name),
					"colony": "colony" in b.get("buildings", [])}
		cells.append(entry)
	var at := grid.layout_from_cell(cell)
	var desc := {"id": "%d_%d" % [at.x, at.y], "name": engine.location_name(cell),
			"star": system.get("star", "yellow"), "cells": cells,
			"defender_body": defended.main_body(engine.data)["id"] if defended != null and defended.cell == cell and not defended.bodies.is_empty() else ""}
	if system.has("at"):
		var star := grid.cell_from_layout(Vector2i(int(system["at"][0]), int(system["at"][1])))
		desc["star_at"] = [star.x - cell.x, star.y - cell.y]
	if from_cell != cell:
		desc["from"] = [from_cell.x - cell.x, from_cell.y - cell.y]
	return desc


static func build(data: DataRegistry, desc: Dictionary, extra_seed: int = 0) -> Dictionary:
	var base_seed := hash(str(desc.get("id", ""))) ^ (extra_seed * 2654435761)
	var rng := RandomNumberGenerator.new()
	for attempt in ATTEMPTS:
		rng.seed = base_seed + attempt * 7919
		var map := _try(data, desc, rng, attempt >= ATTEMPTS / 2)
		if not map.is_empty() and SystemBattleMap.check(map, data.terrain, MIN_OPEN).is_empty():
			return map
	# Last resort: the bodies only (no belts, glare or nebulae), which always deploys.
	rng.seed = base_seed
	var plain := _try(data, desc, rng, true, true)
	if not plain.is_empty() and SystemBattleMap.check(plain, data.terrain, MIN_OPEN).is_empty():
		return plain
	var open := {"grid": "hex", "width": WIDTH, "height": HEIGHT, "terrain": {}, "bodies": [],
			"deployment": {"west": SystemBattleMap._west_slots(HEIGHT), "east": SystemBattleMap._east_slots(WIDTH, HEIGHT)}}
	_finish(open, data, desc)
	return open


# --- Layout -----------------------------------------------------------------

static func _center() -> Vector2i:
	return Hex.oddr_to_axial(Vector2i(WIDTH / 2, HEIGHT / 2))


static func _in_grid(c: Vector2i) -> bool:
	var l := Hex.axial_to_oddr(c)
	return l.x >= 0 and l.y >= 0 and l.x < WIDTH and l.y < HEIGHT


## The strategic offset (axial) a tactical cell lies in.
static func _strategic_of(c: Vector2i) -> Vector2i:
	return Hex.from_pixel(Hex.to_pixel(c - _center(), 1.0), PATCH)


## The tactical cell at the middle of a strategic offset's patch.
static func _patch_center(offset: Vector2i) -> Vector2i:
	return Hex.from_pixel(Hex.to_pixel(offset, PATCH), 1.0) + _center()


## Builds one layout, or {} if deployment didn't fit. `sparse`: thinner belts (later attempts);
## `plain`: bodies only.
static func _try(data: DataRegistry, desc: Dictionary, rng: RandomNumberGenerator, sparse: bool, plain: bool = false) -> Dictionary:
	var by_offset := {}
	for entry: Dictionary in desc.get("cells", []):
		by_offset[Vector2i(int(entry["at"][0]), int(entry["at"][1]))] = entry
	var kinds := {}  # tactical axial -> terrain id ("" = open)
	var belt_cells := {}  # tactical axial -> true (cells of a belt patch, for the scenery)
	var cells: Array[Vector2i] = []
	for row in HEIGHT:
		for col in WIDTH:
			cells.append(Hex.oddr_to_axial(Vector2i(col, row)))
	# Terrain of each patch.
	for c in cells:
		var offset := _strategic_of(c)
		var entry: Dictionary = by_offset.get(offset, {})
		var t: String = entry.get("terrain", "")
		var kind := ""
		match t:
			"star", "corona":
				if offset != Vector2i.ZERO and not plain:
					kind = GLARE
			"asteroid_belt":
				belt_cells[c] = true
				if not plain:
					var roll := rng.randf()
					if roll < (0.12 if sparse else 0.22):
						kind = ASTEROID
					elif roll < 0.6:
						kind = DEBRIS
			"nebula", "ion_storm":
				if not plain and rng.randf() < 0.5:
					kind = NEBULA
		kinds[c] = kind
	# Bodies: a disc in the middle of their patch.
	var bodies: Array = []
	var disc_cells := {}
	var defender_disc: Array[Vector2i] = []
	for offset: Vector2i in by_offset:
		var entry: Dictionary = by_offset[offset]
		if not entry.has("body"):
			continue
		var b: Dictionary = entry["body"]
		var anchor := _patch_center(offset)
		if not _in_grid(anchor):
			continue
		var belt_body: bool = b["type"] == "asteroid_belt"
		var count := 3 if belt_body else _cell_count(data, b["type"])
		var shape := _shape(anchor, count)
		var disc: Array[Vector2i] = []
		for c in shape:
			if _in_grid(c) and _strategic_of(c) == offset:
				disc.append(c)
		if disc.is_empty():
			continue
		for c in disc:
			kinds[c] = ASTEROID if belt_body else PLANET
			disc_cells[c] = true
		# Clear a ring of open space round a world so it stands clear of belts and glare.
		for c in disc:
			for n in Hex.neighbors(c):
				if kinds.has(n) and not disc_cells.has(n) and kinds[n] in [ASTEROID, DEBRIS, NEBULA]:
					kinds[n] = ""
		if b["id"] == desc.get("defender_body", ""):
			defender_disc = disc
		var pairs: Array = []
		for c in disc:
			pairs.append(_pair(c))
		bodies.append({"id": b["id"], "type": b["type"], "name": b.get("name", ""), "kind": "belt" if belt_body else "planet",
				"cells": pairs, "center": _pair(anchor), "radius": 0.0 if belt_body else SystemBattleMap._radius(count),
				"colony": bool(b.get("colony", false))})
	# A belt also shows as a band of drifting rock in the scenery.
	if not belt_cells.is_empty() and not plain:
		var band: Array = []
		for c: Vector2i in belt_cells:
			if kinds.get(c, "") in [ASTEROID, DEBRIS]:
				band.append(_pair(c))
		if not band.is_empty():
			bodies.append({"id": "belt", "type": "asteroid_belt", "name": "Asteroid belt", "kind": "belt", "cells": band,
					"center": band[band.size() / 2], "radius": 0.0, "colony": false})

	# Deployment: the attacker on the side it came from, the defender round its body or the centre.
	var dir := Vector2(-1, 0)
	if desc.has("from"):
		var f := Hex.to_pixel(Vector2i(int(desc["from"][0]), int(desc["from"][1])), 1.0)
		if f.length() > 0.01:
			dir = f.normalized()
	var center_px := Hex.to_pixel(_center(), 1.0)
	var half := Vector2(float(WIDTH) * Hex.SQRT3 / 2.0 - 1.2, float(HEIGHT) * 1.5 / 2.0 - 1.0)
	var reach := minf(half.x / maxf(absf(dir.x), 0.01), half.y / maxf(absf(dir.y), 0.01))
	var entry_px := center_px + dir * reach
	var attacker := _nearest_free(cells, kinds, entry_px, {}, SLOTS)
	if attacker.size() < SLOTS:
		return {}
	var taken := {}
	for c in attacker:
		taken[c] = true
	var defender: Array[Vector2i] = []
	if not defender_disc.is_empty():
		defender = _crescent(defender_disc, cells, kinds, taken, dir)
	else:
		# Mid-board, a little back from the attacker, so there is room to close in.
		defender = _nearest_free(cells, kinds, center_px - dir * 1.5, taken, SLOTS)
	if defender.size() < SLOTS:
		return {}

	# Pockets nobody can reach (rocks walling off a corner) are filled in.
	var seen := {attacker[0]: true}
	var queue: Array[Vector2i] = [attacker[0]]
	while not queue.is_empty():
		var c: Vector2i = queue.pop_back()
		for n in Hex.neighbors(c):
			if kinds.has(n) and not seen.has(n) and _passable(data, kinds[n]):
				seen[n] = true
				queue.append(n)
	for c in defender:
		if not seen.has(c):
			return {}
	for c in cells:
		if _passable(data, kinds[c]) and not seen.has(c):
			kinds[c] = GLARE if _near_kind(c, kinds, GLARE) else ASTEROID

	var terrain := {}
	for c in cells:
		var k: String = kinds[c]
		if k.is_empty():
			continue
		if not terrain.has(k):
			terrain[k] = []
		terrain[k].append(_pair(c))
	var map := {"grid": "hex", "width": WIDTH, "height": HEIGHT, "terrain": terrain, "bodies": bodies,
			"deployment": {"west": _pairs(attacker), "east": _pairs(defender)}}
	_finish(map, data, desc)
	return map


static func _passable(data: DataRegistry, kind: String) -> bool:
	return kind.is_empty() or bool(data.terrain.get(kind, {}).get("passable", true))


static func _near_kind(c: Vector2i, kinds: Dictionary, kind: String) -> bool:
	for n in Hex.within(c, 2):
		if kinds.get(n, "") == kind:
			return true
	return false


## Up to `count` open cells nearest to a pixel point (not in `taken`).
static func _nearest_free(cells: Array[Vector2i], kinds: Dictionary, at: Vector2, taken: Dictionary, count: int) -> Array[Vector2i]:
	var options: Array[Vector2i] = []
	for c in cells:
		if kinds[c].is_empty() and not taken.has(c):
			options.append(c)
	options.sort_custom(func(a: Vector2i, b: Vector2i) -> bool:
		var da := Hex.to_pixel(a, 1.0).distance_squared_to(at)
		var db := Hex.to_pixel(b, 1.0).distance_squared_to(at)
		if absf(da - db) > 0.0001:
			return da < db
		return a.y < b.y or (a.y == b.y and a.x < b.x))
	return options.slice(0, count)


## Open cells hugging a body's disc, those facing the attacker (towards `dir`) first.
static func _crescent(disc: Array[Vector2i], cells: Array[Vector2i], kinds: Dictionary, taken: Dictionary, dir: Vector2) -> Array[Vector2i]:
	var centroid := Vector2.ZERO
	for c in disc:
		centroid += Hex.to_pixel(c, 1.0)
	centroid /= float(disc.size())
	var out: Array[Vector2i] = []
	for d in range(1, 4):
		var ring: Array[Vector2i] = []
		for c in cells:
			if not kinds[c].is_empty() or taken.has(c) or c in out:
				continue
			var nearest := 99
			for o in disc:
				nearest = mini(nearest, Hex.distance(c, o))
			if nearest == d:
				ring.append(c)
		ring.sort_custom(func(a: Vector2i, b: Vector2i) -> bool:
			var fa := (Hex.to_pixel(a, 1.0) - centroid).normalized().dot(dir)
			var fb := (Hex.to_pixel(b, 1.0) - centroid).normalized().dot(dir)
			if absf(fa - fb) > 0.001:
				return fa > fb
			return a.y < b.y or (a.y == b.y and a.x < b.x))
		for c in ring:
			if out.size() < SLOTS:
				out.append(c)
		if out.size() >= SLOTS:
			break
	return out


static func _finish(map: Dictionary, data: DataRegistry, desc: Dictionary) -> void:
	var star_type: String = desc.get("star", "yellow")
	var star_def: Dictionary = data.star_types.get(star_type, {})
	var star_color := Color(star_def.get("color", "#ffd88a"))
	var dir := Vector2(0, -1)
	if desc.has("star_at"):
		var s := Hex.to_pixel(Vector2i(int(desc["star_at"][0]), int(desc["star_at"][1])), 1.0)
		if s.length() > 0.01:
			dir = s.normalized()
	map["id"] = "local_%s" % desc.get("id", "")
	var place: String = desc.get("name", "")
	map["name"] = "Deep space" if place.is_empty() or place == "deep space" else "Near %s" % place
	map["system"] = true
	map["local"] = true
	map["star"] = {"type": star_type, "side": "local", "dir": [dir.x, dir.y]}
	map["backdrop"] = {"a": "#14224f", "b": star_color.darkened(0.78).to_html(false), "density": 0.45}


## Hexes a body covers: 7 for gas giants, 3 for the big worlds, 1 for the rest.
static func _cell_count(data: DataRegistry, type: String) -> int:
	var size := float(data.body_types.get(type, {}).get("size", 0.6))
	if size >= 1.3:
		return 7
	return 3 if size >= 0.85 else 1


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


static func _pair(axial: Vector2i) -> Array:
	var l := Hex.axial_to_oddr(axial)
	return [l.x, l.y]


static func _pairs(cells: Array[Vector2i]) -> Array:
	var out: Array = []
	for c in cells:
		out.append(_pair(c))
	return out
