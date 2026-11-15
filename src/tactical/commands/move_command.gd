class_name MoveCommand
extends BattleCommand
## Move the active unit to a reachable cell, spending AP equal to path cost.

var to: Vector2i


func _init(p_unit_id: String = "", p_to: Vector2i = Vector2i.ZERO) -> void:
	unit_id = p_unit_id
	to = p_to


func type_name() -> String:
	return "move"


func to_dict() -> Dictionary:
	return {"type": type_name(), "unit": unit_id, "to": [to.x, to.y]}
