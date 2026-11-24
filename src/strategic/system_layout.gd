class_name SystemLayout
extends RefCounted
## Builds a SYSTEM-SCALE campaign from a template with a "system_generate" block:
## the campaign's hex map is one star system. The star burns in the centre cell
## (impassable "star" terrain, ringed by "corona"), and every body (planet, moon,
## belt body, dwarf) is its own Planet with exactly one body, so bodies are claimed
## one by one like Civ tiles. The result is an ordinary campaign definition (same
## schema as the hand-made ones), so GalaxyEngine, the AI and saves need nothing new.
## Pure and deterministic: the same template and seed always give the same system.
##
## "system_generate": {
##   "width", "height", "star": star type, "star_name": names bodies ("Sol III"),
##   "homeworld_name", "home_description", "home_owner": faction id,
##   "home_buildings": [ids], "home_pop": n,
##   "orbits": [{"radius": hex widths from the star, "type": id or [ids] (one is picked),
##               "chance"?: 0..1 (optional orbit), "home"?: true, "moons"?: [types], "moon_chance"?: 0..1
##               (for every moon after the first), "dwarf"?: true,
##               or "belt": true, "arc": [min, max] (share of the ring), "belt_bodies": [min, max]}],
##   "jump_points": [min, max] dormant gates at the map edge,
##   "dens": [{"faction", "where": "moon" | "outermost" | "belt", "description", "buildings": [ids]}],
##   "discoveries": {"count": [min, max], "kinds": [ids]},
##   "fleets": [fleet defs with "at": "home" | "near_home" | "den" (the owner's den)],
##   "civilians": [{"unit", "name", "owner", "at": "home" | "home_moon"}],
##   "heroes": [hero defs], "anomalies": [anomaly defs with "where": "outer_moon" | "outer_space", "chance"?],
##   "backdrop": {...}
## }
## The output also carries "system": {"star", "name", "at", "orbits": [radii], "belt": {radius, from, to}}
## for the presentation (orbit circles, the sun, the belt).

## Hex steps kept between bodies of different groups (a planet and its moons are one group).
const GAP := 3
const ATTEMPTS := 60
const ROMAN := ["I", "II", "III", "IV", "V", "VI", "VII", "VIII", "IX", "X", "XI", "XII", "XIII", "XIV"]
const MOON_LETTERS := ["a", "b", "c", "d"]
const BELT_LETTERS := ["A", "B", "C", "D", "E"]


static func generate(data: DataRegistry, template: Dictionary, seed_value: int) -> Dictionary:
	var gen: Dictionary = template["system_generate"]
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value * 7919 + 29
	var w := int(gen.get("width", 25))
	var h := int(gen.get("height", 17))
	var grid := HexGrid.new(w, h, data.galaxy_terrain)
	var center_layout := Vector2i(w / 2, h / 2)
	var layout: Dictionary = {}
	for attempt in ATTEMPTS:
		layout = _try_layout(data, gen, grid, center_layout, rng, GAP if attempt < ATTEMPTS / 2 else GAP - 1)
		if not layout.is_empty():
			break
	if layout.is_empty():
		push_error("SystemLayout: no valid layout for seed %d" % seed_value)
		layout = {"groups": [], "belt": [], "belt_spec": {}}
	var out := template.duplicate(true)
	out.erase("system_generate")
	out["generated"] = true
	out["scale"] = "system"
	_assemble(data, gen, out, grid, center_layout, layout, rng)
	return out


# --- Geometry -----------------------------------------------------------------

## Distance between two cells' centres in hex widths (a hex is 1 wide).
static func pixel_distance(grid: HexGrid, a: Vector2i, b: Vector2i) -> float:
	return grid.to_pixel(a, 1.0).distance_to(grid.to_pixel(b, 1.0)) / Hex.SQRT3


static func _angle(grid: HexGrid, center: Vector2i, c: Vector2i) -> float:
	var d := grid.to_pixel(c, 1.0) - grid.to_pixel(center, 1.0)
	return atan2(d.y, d.x)


## Cells whose centre lies within `tolerance` hex widths of the circle of `radius` round the star,
## at least `margin` cells inside the map edge.
static func _ring(grid: HexGrid, center: Vector2i, radius: float, tolerance: float, margin: int) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for c in grid.cells():
		var l := grid.layout_from_cell(c)
		if l.x < margin or l.y < margin or l.x >= grid.width - margin or l.y >= grid.height - margin:
			continue
		if absf(pixel_distance(grid, c, center) - radius) <= tolerance:
			out.append(c)
	return out


# --- Layout -------------------------------------------------------------------

## One attempt: places every orbit's bodies. Returns {"groups": [{"orbit", "cells": [planet, moons...],
## "types": [...], "home", "dwarf", "kind": "planet" | "belt_body"}], "belt": [cells], "belt_spec"} or {}.
static func _try_layout(data: DataRegistry, gen: Dictionary, grid: HexGrid, center_layout: Vector2i,
		rng: RandomNumberGenerator, gap: int) -> Dictionary:
	var center := grid.cell_from_layout(center_layout)
	var blocked := {center: true}  # star and corona: no bodies there
	for c in grid.neighbors(center):
		blocked[c] = true
	var groups: Array[Dictionary] = []
	var body_cells: Dictionary = {}  # cell -> group index
	var belt: Array[Vector2i] = []
	var belt_spec: Dictionary = {}
	var orbits: Array = gen.get("orbits", [])
	for oi in orbits.size():
		var orbit: Dictionary = orbits[oi]
		var optional := orbit.has("chance")
		if optional and rng.randf() >= float(orbit["chance"]):
			continue
		var radius := float(orbit.get("radius", 3.0))
		if orbit.get("belt", false):
			var placed := _place_belt(grid, center, orbit, radius, rng, blocked, body_cells, gap, groups.size())
			if placed.is_empty():
				if optional:
					continue
				return {}
			belt = placed["cells"]
			belt_spec = {"radius": radius, "from": placed["from"], "to": placed["to"]}
			for c: Vector2i in placed["bodies"]:
				groups.append({"orbit": oi, "radius": radius, "cells": [c] as Array[Vector2i], "types": ["asteroid_belt"],
						"home": false, "dwarf": false, "kind": "belt_body"})
				body_cells[c] = groups.size() - 1
			for c in belt:
				blocked[c] = true
			continue
		var type := _pick_type(orbit.get("type", "barren"), rng)
		var moon_types: Array[String] = []
		var listed_moons: Array = orbit.get("moons", [])
		for mi in listed_moons.size():
			if mi > 0 and orbit.has("moon_chance") and rng.randf() >= float(orbit["moon_chance"]):
				continue
			moon_types.append(_pick_type(listed_moons[mi], rng))
		var margin := 1 if moon_types.is_empty() else 2
		var candidates := _ring(grid, center, radius, 0.5, margin)
		var options: Array[Dictionary] = []
		for c in candidates:
			if blocked.has(c) or body_cells.has(c) or not _clear_of(grid, c, body_cells, gap):
				continue
			var moons := _moon_cells(grid, c, moon_types.size(), blocked, body_cells, gap, rng)
			if moons.size() < moon_types.size():
				continue
			options.append({"cell": c, "moons": moons})
		if options.is_empty():
			if optional:
				continue
			return {}
		var pick: Dictionary = options[rng.randi() % options.size()]
		var cells: Array[Vector2i] = [pick["cell"]]
		cells.append_array(pick["moons"])
		var types: Array[String] = [type]
		types.append_array(moon_types)
		groups.append({"orbit": oi, "radius": radius, "cells": cells, "types": types, "home": orbit.get("home", false),
				"dwarf": orbit.get("dwarf", false), "kind": "planet"})
		for c in cells:
			body_cells[c] = groups.size() - 1
	return {"groups": groups, "belt": belt, "belt_spec": belt_spec}


static func _pick_type(spec: Variant, rng: RandomNumberGenerator) -> String:
	if spec is Array:
		var list: Array = spec
		return str(list[rng.randi() % list.size()]) if not list.is_empty() else "barren"
	return str(spec)


## No body of another group within `gap - 1` steps of `c`.
static func _clear_of(grid: HexGrid, c: Vector2i, body_cells: Dictionary, gap: int) -> bool:
	for other: Vector2i in body_cells:
		if grid.distance(c, other) < gap:
			return false
	return true


## `count` free neighbours of a planet cell for its moons (not next to each other if it can be helped).
static func _moon_cells(grid: HexGrid, planet: Vector2i, count: int, blocked: Dictionary, body_cells: Dictionary,
		gap: int, rng: RandomNumberGenerator) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	if count == 0:
		return out
	var free: Array[Vector2i] = []
	for n in Hex.neighbors(planet):
		var l := grid.layout_from_cell(n)
		if not grid.has_cell(n) or l.x < 1 or l.y < 1 or l.x >= grid.width - 1 or l.y >= grid.height - 1:
			continue
		if blocked.has(n) or body_cells.has(n) or not _clear_of(grid, n, body_cells, gap):
			continue
		free.append(n)
	if free.size() < count:
		return out
	var start := rng.randi() % free.size()
	out.append(free[start])
	for k in range(1, free.size()):
		if out.size() >= count:
			break
		var c := free[(start + k) % free.size()]
		var apart := true
		for m in out:
			if grid.distance(c, m) <= 1:
				apart = false
		if apart:
			out.append(c)
	for c in free:  # crowded: neighbouring moons are allowed after all
		if out.size() >= count:
			break
		if c not in out:
			out.append(c)
	return out


## An arc of the ring at `radius`: asteroid-belt terrain, with a few belt bodies spread along it.
static func _place_belt(grid: HexGrid, center: Vector2i, orbit: Dictionary, radius: float, rng: RandomNumberGenerator,
		blocked: Dictionary, body_cells: Dictionary, gap: int, _groups: int) -> Dictionary:
	var arc_range: Array = orbit.get("arc", [0.5, 0.5])
	var share := rng.randf_range(float(arc_range[0]), float(arc_range[1]))
	var from := rng.randf_range(-PI, PI)
	var span := share * TAU
	var cells: Array[Vector2i] = []
	for c in _ring(grid, center, radius, 0.55, 0):
		if blocked.has(c) or body_cells.has(c):
			continue
		var a := fposmod(_angle(grid, center, c) - from, TAU)
		if a <= span:
			cells.append(c)
	if cells.size() < 6:
		return {}
	cells.sort_custom(func(a: Vector2i, b: Vector2i) -> bool:
		return fposmod(_angle(grid, center, a) - from, TAU) < fposmod(_angle(grid, center, b) - from, TAU))
	var counts: Array = orbit.get("belt_bodies", [2, 3])
	var want := rng.randi_range(int(counts[0]), int(counts[counts.size() - 1]))
	var bodies: Array[Vector2i] = []
	var taken := body_cells.duplicate()
	for k in want:
		# Spread along the arc: aim for the k-th of `want` equal stretches, nudged at random.
		var target := int((float(k) + 0.5 + rng.randf_range(-0.25, 0.25)) / float(want) * cells.size())
		var best := Vector2i(-999, -999)
		var best_off := 1 << 20
		for i in cells.size():
			var c := cells[i]
			var l := grid.layout_from_cell(c)
			if l.x < 1 or l.y < 1 or l.x >= grid.width - 1 or l.y >= grid.height - 1:
				continue
			if absi(i - target) < best_off and _clear_of(grid, c, taken, gap):
				best_off = absi(i - target)
				best = c
		if best.x != -999:
			bodies.append(best)
			taken[best] = -1
	if bodies.size() < int(counts[0]):
		return {}
	return {"cells": cells, "bodies": bodies, "from": from, "to": from + span}


# --- Assembly -----------------------------------------------------------------

static func _assemble(data: DataRegistry, gen: Dictionary, out: Dictionary, grid: HexGrid, center_layout: Vector2i,
		layout: Dictionary, rng: RandomNumberGenerator) -> void:
	var center := grid.cell_from_layout(center_layout)
	var star_name: String = gen.get("star_name", "Sol")
	var star_type: String = gen.get("star", "yellow")
	var groups: Array = layout["groups"]
	# Names: planets (and the dwarf) numbered outwards; moons lettered after their planet; belt bodies lettered.
	var numeral := 0
	var belt_n := 0
	var planets: Array = []
	var by_cell: Dictionary = {}  # layout Vector2i -> planet def
	var home_group: Dictionary = {}
	var group_planets: Array = []  # per group: [planet defs]
	for g: Dictionary in groups:
		var defs: Array = []
		var cells: Array = g["cells"]
		var types: Array = g["types"]
		var main_name := ""
		var main_desc := ""
		if g["kind"] == "belt_body":
			main_name = "%s Belt %s" % [star_name, BELT_LETTERS[mini(belt_n, BELT_LETTERS.size() - 1)]]
			belt_n += 1
			main_desc = "A large body of the asteroid belt, rich in metals."
		else:
			main_name = "%s %s" % [star_name, ROMAN[mini(numeral, ROMAN.size() - 1)]]
			numeral += 1
			if g["home"]:
				main_name = gen.get("homeworld_name", main_name)
			main_desc = _describe(data, types[0], g)
		for i in cells.size():
			var name := main_name if i == 0 else "%s %s" % [main_name, MOON_LETTERS[mini(i - 1, MOON_LETTERS.size() - 1)]]
			var l := grid.layout_from_cell(cells[i])
			var p := {"id": name.to_snake_case().replace("'", ""), "name": name, "at": [l.x, l.y], "star": star_type,
					"description": main_desc if i == 0 else "A moon of %s." % main_name,
					"bodies": [{"type": types[i], "name": name}]}
			if i > 0:
				p["moon_of"] = defs[0]["id"]
			defs.append(p)
			by_cell[l] = p
		group_planets.append(defs)
		if g["home"]:
			home_group = {"defs": defs, "group": g}

	# The homeworld: owned, settled, with its starting buildings.
	var home_def: Dictionary = {}
	if not home_group.is_empty():
		home_def = home_group["defs"][0]
		var owner: String = gen.get("home_owner", "")
		home_def["owner"] = owner
		home_def["sensor"] = 3
		home_def["description"] = gen.get("home_description", home_def["description"])
		var home_body: Dictionary = home_def["bodies"][0]
		home_body["buildings"] = (gen.get("home_buildings", ["colony"]) as Array).duplicate()
		home_body["pop"] = int(gen.get("home_pop", 3))
	# The homeworld comes first, so it is its owner's home planet (heroes return there).
	if not home_def.is_empty():
		planets.append(home_def)
	for defs: Array in group_planets:
		for p: Dictionary in defs:
			if p != home_def:
				planets.append(p)

	# Dens: fortified bases of the hostile factions.
	var dens: Dictionary = {}  # faction id -> planet def
	var used: Dictionary = {}  # planet ids taken by a den or anomaly
	if not home_def.is_empty():
		used[home_def["id"]] = true
		for p: Dictionary in home_group["defs"]:
			used[p["id"]] = true
	for den: Dictionary in gen.get("dens", []):
		var site := _den_site(grid, center, planets, den.get("where", "outermost"), used)
		if site.is_empty():
			continue
		used[site["id"]] = true
		site["owner"] = den["faction"]
		site["sensor"] = 3
		site["description"] = den.get("description", site["description"])
		site["bodies"][0]["buildings"] = (den.get("buildings", ["outpost"]) as Array).duplicate()
		dens[den["faction"]] = site
	out["planets"] = planets

	# Terrain: the star, its corona, the belt, the dormant jump points.
	var terrain := {"star": [[center_layout.x, center_layout.y]], "corona": []}
	for c in grid.neighbors(center):
		var l := grid.layout_from_cell(c)
		terrain["corona"].append([l.x, l.y])
	var belt_cells: Array = layout["belt"]
	if not belt_cells.is_empty():
		terrain["asteroid_belt"] = []
		for c: Vector2i in belt_cells:
			var l := grid.layout_from_cell(c)
			terrain["asteroid_belt"].append([l.x, l.y])
	var occupied: Dictionary = {}  # layout -> true: bodies, belt, star, corona
	for p: Dictionary in planets:
		occupied[Vector2i(int(p["at"][0]), int(p["at"][1]))] = true
	for kind: String in terrain:
		for pair: Array in terrain[kind]:
			occupied[Vector2i(int(pair[0]), int(pair[1]))] = true
	var jumps := _jump_points(grid, center, gen.get("jump_points", [2, 3]), planets, rng)
	if not jumps.is_empty():
		terrain["jump_point"] = []
		for l: Vector2i in jumps:
			terrain["jump_point"].append([l.x, l.y])
			occupied[l] = true
	out["map"] = {"grid": "hex", "width": grid.width, "height": grid.height, "terrain": terrain}

	# Fleets, civilians and heroes.
	var fleets: Array = []
	var home_l := Vector2i(int(home_def["at"][0]), int(home_def["at"][1])) if not home_def.is_empty() else center_layout
	var fleet_cells: Dictionary = {}
	for f_def: Dictionary in gen.get("fleets", []):
		var fleet: Dictionary = f_def.duplicate(true)
		var at := home_l
		match str(f_def.get("at", "home")):
			"near_home":
				at = _free_near(grid, home_l, occupied, fleet_cells, rng)
			"den":
				var den: Dictionary = dens.get(f_def["owner"], {})
				if den.is_empty():
					continue  # no den, no fleet
				at = Vector2i(int(den["at"][0]), int(den["at"][1]))
		if fleet_cells.has(at):
			at = _free_near(grid, at, occupied, fleet_cells, rng)
		fleet_cells[at] = true
		fleet["at"] = [at.x, at.y]
		fleets.append(fleet)
	out["fleets"] = fleets
	for c_def: Dictionary in gen.get("civilians", []):
		var target: Dictionary = home_def
		if str(c_def.get("at", "home")) == "home_moon" and home_group.get("defs", []).size() > 1:
			target = home_group["defs"][1]
		if target.is_empty():
			continue
		var list: Array = target.get("civilians", [])
		list.append({"unit": c_def["unit"], "name": c_def.get("name", ""), "owner": c_def.get("owner", "")})
		target["civilians"] = list
	out["heroes"] = (gen.get("heroes", []) as Array).duplicate(true)

	# Anomalies (missions): on an outer moon, or out in the dark.
	var anomalies: Array = []
	var anomaly_cells: Dictionary = {}
	for a_def: Dictionary in gen.get("anomalies", []):
		if a_def.has("chance") and rng.randf() >= float(a_def["chance"]):
			continue
		var at := Vector2i(-1, -1)
		if a_def.get("where", "") == "outer_moon":
			var site := _den_site(grid, center, planets, "moon", used)
			if site.is_empty():
				site = _den_site(grid, center, planets, "outermost", used)
			if not site.is_empty():
				used[site["id"]] = true
				at = Vector2i(int(site["at"][0]), int(site["at"][1]))
		else:
			at = _free_cell(grid, center, occupied, anomaly_cells, 6.5, 2, rng)
		if at.x < 0:
			continue
		anomaly_cells[at] = true
		var anomaly: Dictionary = a_def.duplicate(true)
		anomaly.erase("where")
		anomaly.erase("chance")
		anomaly["at"] = [at.x, at.y]
		anomalies.append(anomaly)
	out["anomalies"] = anomalies

	# Discoveries: one-time finds scattered through the system.
	var spec: Dictionary = gen.get("discoveries", {})
	var counts: Array = spec.get("count", [0, 0])
	var kinds: Array = spec.get("kinds", [])
	var finds: Array = []
	var find_cells: Dictionary = anomaly_cells.duplicate()
	for f_cell: Vector2i in fleet_cells:
		find_cells[f_cell] = true
	if not kinds.is_empty():
		var n := rng.randi_range(int(counts[0]), int(counts[counts.size() - 1]))
		for i in n:
			var at := _free_cell(grid, center, occupied, find_cells, 3.5, 3, rng)
			if at.x < 0:
				break
			find_cells[at] = true
			finds.append({"kind": kinds[i % kinds.size()] if i < kinds.size() else kinds[rng.randi() % kinds.size()],
					"at": [at.x, at.y]})
	out["discoveries"] = finds

	var orbit_radii: Array = []
	for g: Dictionary in groups:
		if g["kind"] == "planet" and float(g["radius"]) not in orbit_radii:
			orbit_radii.append(float(g["radius"]))
	out["system"] = {"star": star_type, "name": star_name, "at": [center_layout.x, center_layout.y],
			"orbits": orbit_radii, "belt": layout.get("belt_spec", {})}
	if gen.has("backdrop"):
		out["backdrop"] = gen["backdrop"]


static func _describe(data: DataRegistry, type: String, g: Dictionary) -> String:
	if g.get("dwarf", false):
		return "A dwarf planet in the cold outer dark."
	var category: String = data.body_types.get(type, {}).get("category", "")
	var radius := float(g.get("radius", 0.0))
	match category:
		"habitable":
			return "A marginal world: a Colony Ship could make it home."
		"gas":
			return "A gas giant, with a family of moons."
		"rock":
			return "An inner rocky world, baked by the sun." if radius < 4.0 else "A rocky world."
		"ice":
			return "An icy world far from the sun."
	return ""


## A planet def for a den or mission site: "moon" (a moon of the outermost gas giant), "belt" (a belt
## body) or "outermost" (the farthest body). Skips `used` ids.
static func _den_site(grid: HexGrid, center: Vector2i, planets: Array, where: String, used: Dictionary) -> Dictionary:
	var best: Dictionary = {}
	var best_d := -1.0
	for p: Dictionary in planets:
		if used.has(p["id"]) or not p.get("owner", "").is_empty():
			continue
		var type: String = p["bodies"][0]["type"]
		var ok := true
		match where:
			"moon":
				ok = p.has("moon_of")
			"belt":
				ok = type == "asteroid_belt"
		if not ok:
			continue
		var d := pixel_distance(grid, grid.cell_from_layout(Vector2i(int(p["at"][0]), int(p["at"][1]))), center)
		if d > best_d:
			best_d = d
			best = p
	if best.is_empty() and where != "outermost":
		return _den_site(grid, center, planets, "outermost", used)
	return best


## Dormant gates on cells at the map edge, spread round the system and away from every body.
static func _jump_points(grid: HexGrid, center: Vector2i, counts: Array, planets: Array,
		rng: RandomNumberGenerator) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	if counts.is_empty():
		return out
	var n := rng.randi_range(int(counts[0]), int(counts[counts.size() - 1]))
	var edge: Array[Vector2i] = []
	for c in grid.cells():
		var l := grid.layout_from_cell(c)
		if l.x != 0 and l.y != 0 and l.x != grid.width - 1 and l.y != grid.height - 1:
			continue
		var clear := true
		for p: Dictionary in planets:
			if grid.distance(c, grid.cell_from_layout(Vector2i(int(p["at"][0]), int(p["at"][1])))) < 3:
				clear = false
		if clear:
			edge.append(c)
	var start := rng.randf_range(-PI, PI)
	for k in n:
		var want := start + TAU * float(k) / float(n) + rng.randf_range(-0.25, 0.25)
		var best := Vector2i(-999, -999)
		var best_err := INF
		for c in edge:
			var err := absf(angle_difference(_angle(grid, center, c), want))
			var spaced := true
			for o in out:
				if grid.distance(c, grid.cell_from_layout(o)) < 8:
					spaced = false
			if spaced and err < best_err:
				best_err = err
				best = c
		if best.x != -999:
			out.append(grid.layout_from_cell(best))
	return out


## A free neighbour of `at` (layout) for a starting fleet: not a body, the belt or the star.
static func _free_near(grid: HexGrid, at: Vector2i, occupied: Dictionary, taken: Dictionary,
		rng: RandomNumberGenerator) -> Vector2i:
	var options: Array[Vector2i] = []
	for n in grid.neighbors(grid.cell_from_layout(at)):
		var l := grid.layout_from_cell(n)
		if not occupied.has(l) and not taken.has(l):
			options.append(l)
	if options.is_empty():
		return at
	return options[rng.randi() % options.size()]


## A random free cell at least `min_radius` hex widths from the star and `spacing` steps from
## anything in `taken` (and not next to a body or on the belt).
static func _free_cell(grid: HexGrid, center: Vector2i, occupied: Dictionary, taken: Dictionary, min_radius: float,
		spacing: int, rng: RandomNumberGenerator) -> Vector2i:
	var options: Array[Vector2i] = []
	for c in grid.cells():
		var l := grid.layout_from_cell(c)
		if occupied.has(l) or taken.has(l) or pixel_distance(grid, c, center) < min_radius:
			continue
		if l.x < 1 or l.y < 1 or l.x >= grid.width - 1 or l.y >= grid.height - 1:
			continue
		var ok := true
		for n in grid.neighbors(c):
			if occupied.has(grid.layout_from_cell(n)):  # not right beside a body, the belt or the star
				ok = false
				break
		for t: Vector2i in taken:
			if grid.distance(c, grid.cell_from_layout(t)) < spacing:
				ok = false
		if ok:
			options.append(l)
	if options.is_empty():
		return Vector2i(-1, -1)
	return options[rng.randi() % options.size()]
