class_name SetResearchCommand
extends GalaxyCommand
## Choose the technology the faction's research points go into.

var tech_id: String


func _init(p_faction_id: String = "", p_tech_id: String = "") -> void:
	faction_id = p_faction_id
	tech_id = p_tech_id


func type_name() -> String:
	return "set_research"


func to_dict() -> Dictionary:
	return {"type": type_name(), "faction": faction_id, "tech": tech_id}
