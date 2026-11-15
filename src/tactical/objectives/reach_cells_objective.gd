class_name ReachCellsObjective
extends BattleObjective
## {"type": "reach_cells", "team": 0, "cells": [[c, r], ...]}: `team` wins as
## soon as one of its living units stands on any of the cells.

var _cells: Array[Vector2i] = []


func setup(state: BattleState) -> void:
	_cells.clear()
	for pos: Array in def.get("cells", []):
		_cells.append(state.grid.cell_from_layout(Vector2i(int(pos[0]), int(pos[1]))))


func marked_cells() -> Array[Vector2i]:
	return _cells


func evaluate(state: BattleState) -> int:
	var team := int(def.get("team", 0))
	for u in state.living_units(team):
		if u.cell in _cells:
			return team
	return BattleState.NO_WINNER


func describe() -> String:
	return def.get("description", "Reach the objective")
