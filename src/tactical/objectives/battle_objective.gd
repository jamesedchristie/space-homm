class_name BattleObjective
extends RefCounted
## A victory condition. Missions differ from pitched battles mostly by their
## objectives (survive, reach an exit, protect a unit, ...), so they are
## pluggable and data-driven: {"type": "eliminate_all"}.

var def: Dictionary = {}


## Called once when the battle is built (e.g. to convert layout coordinates).
func setup(_state: BattleState) -> void:
	pass


## Cells the UI should highlight for this objective.
func marked_cells() -> Array[Vector2i]:
	return []


## Returns the winning team, BattleState.DRAW, or BattleState.NO_WINNER.
func evaluate(_state: BattleState) -> int:
	return BattleState.NO_WINNER


## Short text for the HUD, e.g. "Destroy all enemy ships".
func describe() -> String:
	return def.get("description", "")
