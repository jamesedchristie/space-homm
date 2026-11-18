class_name ResolveEventCommand
extends GalaxyCommand
## Answer the galactic event the faction has been offered: pick one of its
## choices by index (see EventRules.choices).

var choice: int


func _init(p_faction_id: String = "", p_choice: int = 0) -> void:
	faction_id = p_faction_id
	choice = p_choice


func type_name() -> String:
	return "resolve_event"


func to_dict() -> Dictionary:
	return {"type": type_name(), "faction": faction_id, "choice": choice}
