class_name EndTurnCommand
extends BattleCommand
## End the active unit's turn. Unspent AP is lost.


func _init(p_unit_id: String = "") -> void:
	unit_id = p_unit_id


func type_name() -> String:
	return "end_turn"
