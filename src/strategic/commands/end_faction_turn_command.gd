class_name EndFactionTurnCommand
extends GalaxyCommand
## End the current faction's turn; the next faction moves.


func _init(p_faction_id: String = "") -> void:
	faction_id = p_faction_id


func type_name() -> String:
	return "end_faction_turn"
