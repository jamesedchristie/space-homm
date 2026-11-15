class_name DiplomacyCommand
extends GalaxyCommand
## action: "propose_peace" (the target answers by DiplomacyRules),
##         "declare_war", or "gift" (credits, improves the target's opinion).

var target: String
var action: String


func _init(p_faction_id: String = "", p_target: String = "", p_action: String = "") -> void:
	faction_id = p_faction_id
	target = p_target
	action = p_action


func type_name() -> String:
	return "diplomacy"


func to_dict() -> Dictionary:
	return {"type": type_name(), "faction": faction_id, "target": target, "action": action}
