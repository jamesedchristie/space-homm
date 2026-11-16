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
##   "neutral_planets": n,
##   "terrain": {"nebula": [blobs, size], "asteroid_belt": [...], "rift": [...]},
##   "homes": {faction id: planet def without "at" (id/name/type/buildings/...)},
##   "fleets": [fleet defs without "at": placed next to the owner's home],
##   "heroes": [hero defs; "planet": "home" means the owner's home world],
##   "anomalies": [anomaly defs without "at"],
##   "planet_names": [...], "backdrops": [{"a", "b", "density"}]
## }

const EDGE := 1


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
		if not p.has("bodies") or not p["bodies"] is Array:
			p["bodies"] = _home_bodies(data, rng, p, homes[fid].get("buildings", []))
		planets.append(p)

	# Neutral planets: spread out, not too close to anything.
	var names: Array = gen.get("planet_names", []).duplicate()
	_shuffle(names, rng)
	for i in int(gen.get("neutral_planets", 6)):
		var at := _farthest(grid, w, h, occupied.keys(), occupied, rng, 4, 3)
		if at == Vector2i(-1, -1):
			break
		occupied[at] = true
		var name: String = names[i] if i < names.size() else "Planet %d" % (i + 1)
		planets.append({"id": name.to_snake_case(), "name": name, "at": [at.x, at.y], "star": SystemBuilder.random_star(data, rng),
				"bodies": SystemBuilder.random_bodies(data, rng, name.to_snake_case(), name)})
	out["planets"] = planets

	# Starting fleets next to their homes.
	var fleets: Array = []
	for f_def: Dictionary in gen.get("fleets", []):
		var home: Vector2i = home_at.get(f_def["owner"], Vector2i(EDGE, EDGE))
		var at := _free_near(grid, home, occupied, rng)
		occupied[at] = true
		var fleet := f_def.duplicate(true)
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
		var at := _farthest(grid, w, h, home_at.values(), occupied, rng, 6, 2)
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
	for kind: String in kinds:
		var blobs := int(spec[kind][0])
		var size := int(spec[kind][1])
		var cells: Array = []
		for b in blobs:
			var at := Vector2i(rng.randi_range(0, w - 1), rng.randi_range(0, h - 1))
			for s in size:
				if not occupied.has(at) and not _near_any(grid, at, home_at.values(), 2):
					occupied[at] = true
					cells.append([at.x, at.y])
				var options := grid.neighbors(grid.cell_from_layout(at))
				at = grid.layout_from_cell(options[rng.randi() % options.size()]) if not options.is_empty() else at
		terrain[kind] = cells
	out["map"] = {"grid": "hex", "width": w, "height": h, "terrain": terrain}
	if not _all_reachable(data, out, home_at[faction_order[0]]):
		terrain.erase("rift")

	var backdrops: Array = gen.get("backdrops", [])
	if not backdrops.is_empty():
		out["backdrop"] = backdrops[rng.randi() % backdrops.size()]
	return out


## A free layout cell as far as possible from `points` (one of the best few,
## at random), at least `min_dist` from them and `min_others` from anything
## occupied. Vector2i(-1, -1) if none.
## A home system: random bodies around a developed terran capital
## (colony + the template's buildings on it).
static func _home_bodies(data: DataRegistry, rng: RandomNumberGenerator, p: Dictionary, capital_buildings: Array) -> Array:
	var bodies := SystemBuilder.random_bodies(data, rng, p["id"], p.get("name", p["id"]), true)
	var out: Array = []
	for b in bodies:
		var entry := {"type": b["type"], "name": b["name"]}
		if b["type"] == "terran" and not out.any(func(x: Dictionary) -> bool: return x.has("buildings")):
			entry["name"] = p.get("name", b["name"])
			entry["buildings"] = ["colony"] + capital_buildings.filter(func(x: String) -> bool: return x != "colony")
		out.append(entry)
	return out


static func _farthest(grid: HexGrid, w: int, h: int, points: Array, occupied: Dictionary,
		rng: RandomNumberGenerator, top: int, min_others: int = 0) -> Vector2i:
	var scored: Array = []
	for y in range(EDGE, h - EDGE):
		for x in range(EDGE, w - EDGE):
			var at := Vector2i(x, y)
			if occupied.has(at):
				continue
			var d := 1 << 20
			for p: Vector2i in points:
				d = mini(d, _dist(grid, at, p))
			var crowd := 1 << 20
			for o: Vector2i in occupied:
				crowd = mini(crowd, _dist(grid, at, o))
			if crowd < min_others:
				continue
			scored.append([d + rng.randf() * 1.5, at])
	if scored.is_empty():
		return Vector2i(-1, -1)
	scored.sort_custom(func(a: Array, b: Array) -> bool: return a[0] > b[0])
	return scored[rng.randi() % mini(top, scored.size())][1]


static func _free_near(grid: HexGrid, at: Vector2i, occupied: Dictionary, rng: RandomNumberGenerator) -> Vector2i:
	var options: Array = []
	for n in grid.neighbors(grid.cell_from_layout(at)):
		var l := grid.layout_from_cell(n)
		if not occupied.has(l):
			options.append(l)
	if options.is_empty():
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
