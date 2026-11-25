class_name GalaxyGenerator
extends RefCounted
## Builds a playable campaign definition from a template with a "generate"
## block, so every seed gives a different sector: home worlds spread apart,
## neutral planets with random types and names, nebula / asteroid / rift
## clusters, starting fleets beside their homes, mission sites in the
## contested middle. The result is an ordinary campaign dictionary (same
## schema as data/strategic/campaigns/the_drift.json), so the engine, AI and
## saves treat it like any hand-made campaign.
##
## "generate": {
##   "width", "height",
##   "neutral_planets": n, "spacing": minimum hexes between star systems (default 3),
##   "terrain": {"nebula": [blobs, size], "asteroid_belt": [...], "rift": [...]},
##              rifts grow as long, mostly straight walls (chokepoints); a wall
##              that would cut anything off from the first home is dropped.
##   "homes": {faction id: planet def without "at" (id/name/type/buildings/...)},
##   "fleets": [fleet defs without "at": placed next to the owner's home],
## Template level: "start": "colony_ship" makes every major power's home system start unclaimed
## (its "buildings" become the capital's, see Planet.capital), with its first fleet standing in the
## home system and the ships listed in "start_ships" (e.g. a colony ship and a constructor) waiting
## in the system, ready for orders (Planet.civilians).
##   "heroes": [hero defs; "planet": "home" means the owner's home world],
##   "anomalies": [anomaly defs without "at"],
##   "planet_names": [...], "backdrops": [{"a", "b", "density"}]
## }

const EDGE := 1
## Population of a home world's capital colony at the start.
const HOME_POP := 3


static func generate(data: DataRegistry, template: Dictionary, seed_value: int) -> Dictionary:
	var gen: Dictionary = template["generate"]
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value * 7919 + 17
	var w := int(gen.get("width", 18))
	var h := int(gen.get("height", 12))
	var grid := HexGrid.from_map({"width": w, "height": h}, data.galaxy_terrain)
	var out := template.duplicate(true)
	out.erase("generate")
	out["generated"] = true
	var occupied := {}  # layout Vector2i -> true

	# Home worlds, spread out: the player's on the west side, the rest as far
	# from every home so far as possible (with a little randomness).
	var homes: Dictionary = gen.get("homes", {})
	var home_at := {}
	var planets: Array = []
	var faction_order: Array = []
	for f: Dictionary in template.get("factions", []):
		if homes.has(f["id"]):
			faction_order.append(f["id"])
	for fid: String in faction_order:
		var at: Vector2i
		if home_at.is_empty():
			at = Vector2i(rng.randi_range(EDGE, maxi(EDGE, w / 5)), rng.randi_range(EDGE + 1, h - 2 - EDGE))
		else:
			at = _farthest(grid, w, h, home_at.values(), occupied, rng, 3)
		home_at[fid] = at
		occupied[at] = true
		var p: Dictionary = homes[fid].duplicate(true)
		p["at"] = [at.x, at.y]
		p["owner"] = fid
		if _starts_unfounded(template, fid):
			# The power arrives by colony ship: an unclaimed system that becomes its capital.
			p["owner"] = ""
			p["capital"] = {"faction": fid, "buildings": homes[fid].get("buildings", []), "pop": HOME_POP}
			var settlers: Array = []
			for unit_id: String in template.get("start_ships", []):
				settlers.append({"unit": unit_id, "name": _start_ship_name(data, unit_id), "owner": fid})
			p["civilians"] = settlers
			p.erase("buildings")
			if not p.has("bodies") or not p["bodies"] is Array:
				p["bodies"] = _home_bodies(data, rng, p, [], false)
		elif not p.has("bodies") or not p["bodies"] is Array:
			p["bodies"] = _home_bodies(data, rng, p, homes[fid].get("buildings", []))
		planets.append(p)

	# Neutral planets: spread out, not too close to anything.
	var names: Array = gen.get("planet_names", []).duplicate()
	_shuffle(names, rng)
	var spacing := int(gen.get("spacing", 3))
	for i in int(gen.get("neutral_planets", 6)):
		var at := _farthest(grid, w, h, occupied.keys(), occupied, rng, 6, spacing)
		if at == Vector2i(-1, -1):
			break
		occupied[at] = true
		var name: String = names[i] if i < names.size() else "Planet %d" % (i + 1)
		planets.append({"id": name.to_snake_case(), "name": name, "at": [at.x, at.y], "star": SystemBuilder.random_star(data, rng),
				"bodies": SystemBuilder.random_bodies(data, rng, name.to_snake_case(), name)})
	out["planets"] = planets

	# Hyperlanes (optional): systems joined by lanes; only lane hexes are open space,
	# everything else is void. lane_cells holds the open layout cells.
	var lane_cells := {}
	var lane_spec: Dictionary = gen.get("lanes", {})
	if not lane_spec.is_empty():
		out["lanes"] = _make_lanes(grid, planets, lane_spec, rng)
		for p: Dictionary in planets:
			lane_cells[Vector2i(int(p["at"][0]), int(p["at"][1]))] = true
		var by_id := {}
		for p: Dictionary in planets:
			by_id[p["id"]] = grid.cell_from_layout(Vector2i(int(p["at"][0]), int(p["at"][1])))
		for lane: Array in out["lanes"]:
			for c in grid.line(by_id[lane[0]], by_id[lane[1]]):
				lane_cells[grid.layout_from_cell(c)] = true
		_place_relic_gates(grid, planets, home_at.values(), int(lane_spec.get("relic_gates", 0)), rng)

	# Starting fleets next to their homes.
	var fleets: Array = []
	var landed := {}  # faction ids whose first fleet already stands in the home system
	for f_def: Dictionary in gen.get("fleets", []):
		var home: Vector2i = home_at.get(f_def["owner"], Vector2i(EDGE, EDGE))
		var fleet := f_def.duplicate(true)
		if _starts_unfounded(template, f_def["owner"]) and not landed.has(f_def["owner"]):
			# The first fleet starts in the home system itself, beside the settlers.
			landed[f_def["owner"]] = true
			fleet["at"] = [home.x, home.y]
			fleets.append(fleet)
			continue
		var at := _free_near(grid, home, occupied, rng, lane_cells)
		occupied[at] = true
		fleet["at"] = [at.x, at.y]
		fleets.append(fleet)
	out["fleets"] = fleets

	# Heroes: "planet": "home" -> the owner's home world.
	var heroes: Array = []
	for h_def: Dictionary in gen.get("heroes", []):
		var hero := h_def.duplicate(true)
		if hero.get("planet", "") == "home":
			hero["planet"] = homes[hero["owner"]]["id"]
		heroes.append(hero)
	out["heroes"] = heroes

	# Mission sites in the contested middle: at least 4 from every home.
	var anomalies: Array = []
	for a_def: Dictionary in gen.get("anomalies", []):
		var at := _farthest(grid, w, h, home_at.values(), occupied, rng, 6, 2, lane_cells)
		if at == Vector2i(-1, -1):
			continue
		occupied[at] = true
		var anomaly := a_def.duplicate(true)
		anomaly["at"] = [at.x, at.y]
		anomalies.append(anomaly)
	out["anomalies"] = anomalies

	# Terrain clusters; rifts are dropped again if they'd cut anything off.
	var terrain := {}
	var spec: Dictionary = gen.get("terrain", {})
	var kinds := spec.keys()
	kinds.sort()
	out["map"] = {"grid": "hex", "width": w, "height": h, "terrain": terrain}
	for kind: String in kinds:
		var blobs := int(spec[kind][0])
		var size := int(spec[kind][1])
		var impassable: bool = not data.galaxy_terrain.get(kind, {}).get("passable", true)
		if impassable and not lane_cells.is_empty():
			continue  # lane maps: the void is the wall
		terrain[kind] = []
		for b in blobs:
			var blob: Array = []
			var at := Vector2i(rng.randi_range(0, w - 1), rng.randi_range(0, h - 1))
			var heading := rng.randi() % 6
			for s in size:
				if not occupied.has(at) and not _near_any(grid, at, home_at.values(), 2) and grid.has_cell(grid.cell_from_layout(at)) \
						and (lane_cells.is_empty() or lane_cells.has(at)):
					occupied[at] = true
					blob.append([at.x, at.y])
				var options := grid.neighbors(grid.cell_from_layout(at))
				if options.is_empty():
					break
				# Walls keep their heading (with a little wander); clouds drift anywhere.
				if impassable and rng.randf() < 0.75:
					at = grid.layout_from_cell(options[heading % options.size()])
				else:
					if impassable:
						heading = (heading + (1 if rng.randf() < 0.5 else options.size() - 1)) % options.size()
					at = grid.layout_from_cell(options[rng.randi() % options.size()])
			terrain[kind].append_array(blob)
			if impassable and not _all_reachable(data, out, home_at[faction_order[0]]):
				# This wall cuts something off: drop it.
				for c: Array in blob:
					terrain[kind].erase(c)
					occupied.erase(Vector2i(int(c[0]), int(c[1])))
	for kind: String in terrain.keys():
		if terrain[kind].is_empty():
			terrain.erase(kind)
	if not lane_cells.is_empty():
		var void_cells: Array = []
		for y in h:
			for x in w:
				if not lane_cells.has(Vector2i(x, y)):
					void_cells.append([x, y])
		terrain["void"] = void_cells

	var backdrops: Array = gen.get("backdrops", [])
	if not backdrops.is_empty():
		out["backdrop"] = backdrops[rng.randi() % backdrops.size()]
	return out


## A free layout cell as far as possible from `points` (one of the best few,
## at random), at least `min_dist` from them and `min_others` from anything
## occupied. Vector2i(-1, -1) if none.
## A home system: random bodies around a developed terran capital
## (colony + the template's buildings on it).
static func _home_bodies(data: DataRegistry, rng: RandomNumberGenerator, p: Dictionary, capital_buildings: Array,
		settled: bool = true) -> Array:
	var bodies := SystemBuilder.random_bodies(data, rng, p["id"], p.get("name", p["id"]), true)
	var out: Array = []
	var named := false
	for b in bodies:
		var entry := {"type": b["type"], "name": b["name"]}
		if b["type"] == "terran" and not named:
			named = true
			entry["name"] = p.get("name", b["name"])
			if settled:
				entry["buildings"] = ["colony"] + capital_buildings.filter(func(x: String) -> bool: return x != "colony")
				entry["pop"] = HOME_POP
		out.append(entry)
	return out


## Whether this faction starts without a colony, arriving by colony ship (major powers only).
static func _starts_unfounded(template: Dictionary, faction_id: String) -> bool:
	if template.get("start", "owned") != "colony_ship" or faction_id in template.get("founded", []):
		return false
	for f: Dictionary in template.get("factions", []):
		if f["id"] == faction_id:
			return f.get("role", "major") == "major"
	return false


static func _start_ship_name(data: DataRegistry, unit_id: String) -> String:
	return {"colony_ship": "Pioneer", "constructor": "Foreman", "troop_transport": "Garrison"}.get(unit_id,
			data.units.get(unit_id, {}).get("name", unit_id))


static func _farthest(grid: HexGrid, w: int, h: int, points: Array, occupied: Dictionary,
		rng: RandomNumberGenerator, top: int, min_others: int = 0, allowed: Dictionary = {}) -> Vector2i:
	# Two breadth-first distance maps instead of measuring every cell against
	# every point (the big sector made that the slowest part of generating).
	var to_points := _distance_map(grid, points)
	var to_occupied := _distance_map(grid, occupied.keys()) if min_others > 0 else {}
	var scored: Array = []
	for y in range(EDGE, h - EDGE):
		for x in range(EDGE, w - EDGE):
			var at := Vector2i(x, y)
			if occupied.has(at) or (not allowed.is_empty() and not allowed.has(at)):
				continue
			if min_others > 0 and int(to_occupied.get(at, 1 << 20)) < min_others:
				continue
			scored.append([int(to_points.get(at, 1 << 20)) + rng.randf() * 1.5, at])
	if scored.is_empty():
		return Vector2i(-1, -1)
	scored.sort_custom(func(a: Array, b: Array) -> bool: return a[0] > b[0])
	return scored[rng.randi() % mini(top, scored.size())][1]


## Hex steps (ignoring terrain) from the nearest of `sources`, for every layout cell.
static func _distance_map(grid: HexGrid, sources: Array) -> Dictionary:
	var dist := {}
	var frontier: Array[Vector2i] = []
	for s: Vector2i in sources:
		var c := grid.cell_from_layout(s)
		if grid.has_cell(c) and not dist.has(s):
			dist[s] = 0
			frontier.append(c)
	var i := 0
	while i < frontier.size():
		var c := frontier[i]
		i += 1
		var d := int(dist[grid.layout_from_cell(c)]) + 1
		for n in grid.neighbors(c):
			var l := grid.layout_from_cell(n)
			if not dist.has(l):
				dist[l] = d
				frontier.append(n)
	return dist


static func _free_near(grid: HexGrid, at: Vector2i, occupied: Dictionary, rng: RandomNumberGenerator,
		allowed: Dictionary = {}) -> Vector2i:
	var options: Array = []
	for n in grid.neighbors(grid.cell_from_layout(at)):
		var l := grid.layout_from_cell(n)
		if not occupied.has(l) and (allowed.is_empty() or allowed.has(l)):
			options.append(l)
	if options.is_empty():
		# Crowded: the nearest free (allowed) cell further out.
		var seen := {at: true}
		var frontier: Array[Vector2i] = [at]
		var i := 0
		while i < frontier.size() and i < 400:
			var l := frontier[i]
			i += 1
			for n in grid.neighbors(grid.cell_from_layout(l)):
				var nl := grid.layout_from_cell(n)
				if seen.has(nl) or not (allowed.is_empty() or allowed.has(nl)):
					continue
				seen[nl] = true
				if not occupied.has(nl):
					return nl
				frontier.append(nl)
		return at
	return options[rng.randi() % options.size()]


static func _near_any(grid: HexGrid, at: Vector2i, points: Array, radius: int) -> bool:
	for p: Vector2i in points:
		if _dist(grid, at, p) <= radius:
			return true
	return false


static func _dist(grid: HexGrid, a: Vector2i, b: Vector2i) -> int:
	return grid.distance(grid.cell_from_layout(a), grid.cell_from_layout(b))


## Every planet and mission site reachable from the player's home.
static func _all_reachable(data: DataRegistry, campaign: Dictionary, from: Vector2i) -> bool:
	var grid := HexGrid.from_map(campaign["map"], data.galaxy_terrain)
	var field := Pathfinding.distance_field(grid, [grid.cell_from_layout(from)])
	for list_key in ["planets", "anomalies", "fleets"]:
		for item: Dictionary in campaign.get(list_key, []):
			var c := grid.cell_from_layout(Vector2i(int(item["at"][0]), int(item["at"][1])))
			if not field.has(c):
				return false
	return true


static func _shuffle(arr: Array, rng: RandomNumberGenerator) -> void:
	for i in range(arr.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var t = arr[i]
		arr[i] = arr[j]
		arr[j] = t


# --- Hyperlanes ---------------------------------------------------------------

## Lanes between systems ([planet id, planet id] pairs): the relative neighbourhood graph of the
## systems (connected, no crossings, mostly short hops), plus a few extra non-crossing lanes up to
## `max_length` hexes long (chance `extra` each) so the network has loops and alternative routes.
static func _make_lanes(grid: HexGrid, planets: Array, spec: Dictionary, rng: RandomNumberGenerator) -> Array:
	var n := planets.size()
	var px: Array[Vector2] = []
	for p: Dictionary in planets:
		px.append(grid.to_pixel(grid.cell_from_layout(Vector2i(int(p["at"][0]), int(p["at"][1]))), 1.0))
	var edges: Array = []
	for i in n:
		for j in range(i + 1, n):
			edges.append([px[i].distance_to(px[j]), i, j])
	edges.sort_custom(func(a: Array, b: Array) -> bool: return a[0] < b[0])
	var kept: Array = []
	var rest: Array = []
	for e: Array in edges:
		var i: int = e[1]
		var j: int = e[2]
		var ok := true
		for k in n:
			if k != i and k != j and maxf(px[i].distance_to(px[k]), px[j].distance_to(px[k])) < float(e[0]) - 0.001:
				ok = false
				break
		if ok:
			kept.append(e)
		else:
			rest.append(e)
	var extra := float(spec.get("extra", 0.25))
	var max_len := float(spec.get("max_length", 8)) * sqrt(3.0)  # hexes -> pixels at size 1
	for e: Array in rest:
		if float(e[0]) > max_len or rng.randf() >= extra:
			continue
		var a: Vector2 = px[e[1]]
		var b: Vector2 = px[e[2]]
		var clear := true
		for k in n:
			if k != e[1] and k != e[2] and Geometry2D.get_closest_point_to_segment(px[k], a, b).distance_to(px[k]) < 2.2:
				clear = false  # would graze another system
				break
		for f: Array in kept:
			if clear and not (f[1] in [e[1], e[2]] or f[2] in [e[1], e[2]]) \
					and Geometry2D.segment_intersects_segment(a, b, px[f[1]], px[f[2]]) != null:
				clear = false
		if clear:
			kept.append(e)
	var out: Array = []
	for e: Array in kept:
		out.append([planets[e[1]]["id"], planets[e[2]]["id"]])
	return out


## Marks `count` neutral systems, far from the homes and from each other, as holding a relic gate.
static func _place_relic_gates(grid: HexGrid, planets: Array, homes: Array, count: int, rng: RandomNumberGenerator) -> void:
	var chosen: Array = homes.duplicate()
	for g in count:
		var best: Dictionary = {}
		var best_d := -1.0
		for p: Dictionary in planets:
			if p.get("owner", "") != "" or p.has("capital") or p.get("relic_gate", false):
				continue
			var at := Vector2i(int(p["at"][0]), int(p["at"][1]))
			var d := 1.0e9
			for c: Vector2i in chosen:
				d = minf(d, _dist(grid, at, c))
			d += rng.randf() * 2.0
			if d > best_d:
				best_d = d
				best = p
		if best.is_empty():
			return
		best["relic_gate"] = true
		chosen.append(Vector2i(int(best["at"][0]), int(best["at"][1])))
