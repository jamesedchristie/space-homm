class_name CoverRules
extends RefCounted
## Directional cover, XCOM-style. Terrain with "cover": "half" | "full"
## protects units standing next to it from attacks coming from that side:
##   half cover: 30% less damage, full cover: 50% less.
## A unit that has cover nearby but none facing the attacker is flanked and
## takes 25% more. Area attacks (abilities with a radius) ignore cover.
## On square grids the sides facing the attacker are the orthogonal
## neighbours toward it (both when it's roughly diagonal); on hex grids it's
## the first cell on the line toward the attacker.

const HALF := "half"
const FULL := "full"
const MULTIPLIER := {"": 1.0, "half": 0.7, "full": 0.5, "flanked": 1.25}


## {"cover": "" | "half" | "full", "flanked": bool, "multiplier": float}
static func evaluate(state: BattleState, attacker_cell: Vector2i, target_cell: Vector2i) -> Dictionary:
	var out := {"cover": "", "flanked": false, "multiplier": 1.0}
	if attacker_cell == target_cell:
		return out
	var best := ""
	for side in facing_cells(state.grid, attacker_cell, target_cell):
		var level := cover_at(state, side)
		if level == FULL or (level == HALF and best == ""):
			best = level
	if best != "":
		out["cover"] = best
		out["multiplier"] = MULTIPLIER[best]
	elif _has_any_cover(state, target_cell):
		out["flanked"] = true
		out["multiplier"] = MULTIPLIER["flanked"]
	return out


static func cover_at(state: BattleState, cell: Vector2i) -> String:
	if not state.grid.has_cell(cell):
		return ""
	return state.grid.terrain_def(cell).get("cover", "")


## The target's neighbours that sit between it and the attacker.
static func facing_cells(grid: TacticalGrid, attacker_cell: Vector2i, target_cell: Vector2i) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	if grid is SquareGrid:
		var d := attacker_cell - target_cell
		var ax := absi(d.x)
		var ay := absi(d.y)
		if ax > 0 and ax * 2 >= ay:
			out.append(target_cell + Vector2i(signi(d.x), 0))
		if ay > 0 and ay * 2 >= ax:
			out.append(target_cell + Vector2i(0, signi(d.y)))
	else:
		var line := grid.line(target_cell, attacker_cell)
		if line.size() > 1:
			out.append(line[1])
	return out


static func _has_any_cover(state: BattleState, cell: Vector2i) -> bool:
	var sides: Array[Vector2i] = []
	if state.grid is SquareGrid:
		sides = [cell + Vector2i.LEFT, cell + Vector2i.RIGHT, cell + Vector2i.UP, cell + Vector2i.DOWN]
	else:
		sides = state.grid.neighbors(cell)
	for s in sides:
		if cover_at(state, s) != "":
			return true
	return false
