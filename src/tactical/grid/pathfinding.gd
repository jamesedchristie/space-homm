class_name Pathfinding
extends RefCounted
## Grid-agnostic movement search (Dijkstra; terrain can cost more than 1 AP).


## All cells reachable from `start` within `budget` movement cost.
## `is_blocked(cell) -> bool` adds dynamic blockers such as other units.
## `is_terminal(cell) -> bool` (optional) marks cells that can be entered but
## not passed through, e.g. an enemy fleet you can attack but not fly past.
## Returns { cell: {"cost": int, "from": Vector2i} }, including start (cost 0).
static func reachable(grid: TacticalGrid, start: Vector2i, budget: int, is_blocked: Callable,
		is_terminal: Callable = Callable()) -> Dictionary:
	var result := {start: {"cost": 0, "from": start}}
	var frontier: Array[Vector2i] = [start]
	while not frontier.is_empty():
		var best_i := 0
		for i in range(1, frontier.size()):
			if result[frontier[i]]["cost"] < result[frontier[best_i]]["cost"]:
				best_i = i
		var current: Vector2i = frontier[best_i]
		frontier.remove_at(best_i)
		if current != start and is_terminal.is_valid() and is_terminal.call(current):
			continue
		var base_cost: int = result[current]["cost"]
		for n in grid.neighbors(current):
			if not grid.is_passable(n) or is_blocked.call(n):
				continue
			var cost := base_cost + grid.move_cost(n)
			if cost > budget:
				continue
			if not result.has(n) or cost < result[n]["cost"]:
				result[n] = {"cost": cost, "from": current}
				if not frontier.has(n):
					frontier.append(n)
	return result


## Path from the search start to `target` (both inclusive), or [] if unreachable.
static func path_to(reach: Dictionary, target: Vector2i) -> Array[Vector2i]:
	var path: Array[Vector2i] = []
	if not reach.has(target):
		return path
	var current := target
	path.append(current)
	while reach[current]["from"] != current:
		current = reach[current]["from"]
		path.append(current)
	path.reverse()
	return path


## Movement cost from any of `sources` to every passable cell, ignoring units.
## Used by AI to approach targets around obstacles.
static func distance_field(grid: TacticalGrid, sources: Array[Vector2i]) -> Dictionary:
	var dist := {}
	var frontier: Array[Vector2i] = []
	for s in sources:
		dist[s] = 0
		frontier.append(s)
	while not frontier.is_empty():
		var best_i := 0
		for i in range(1, frontier.size()):
			if dist[frontier[i]] < dist[frontier[best_i]]:
				best_i = i
		var current: Vector2i = frontier[best_i]
		frontier.remove_at(best_i)
		for n in grid.neighbors(current):
			if not grid.is_passable(n):
				continue
			var cost: int = dist[current] + grid.move_cost(n)
			if not dist.has(n) or cost < dist[n]:
				dist[n] = cost
				if not frontier.has(n):
					frontier.append(n)
	return dist
