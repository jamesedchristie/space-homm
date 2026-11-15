class_name ChooseOptionCommand
extends BattleCommand
## Answer the trigger choice the battle is waiting on (state.pending_choice).

var option: int


func _init(p_unit_id: String = "", p_option: int = 0) -> void:
	unit_id = p_unit_id
	option = p_option


func type_name() -> String:
	return "choose_option"


func to_dict() -> Dictionary:
	return {"type": type_name(), "unit": unit_id, "option": option}
