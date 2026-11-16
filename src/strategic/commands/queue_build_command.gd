class_name QueueBuildCommand
extends GalaxyCommand
## Start building something in one of the faction's systems. The cost is paid
## up front; it completes after the item's build turns. kind: "building" | "unit".
## body_id: which body a building goes on ("" = the first body it fits).

var planet_id: String
var kind: String
var item_id: String
var body_id: String


func _init(p_faction_id: String = "", p_planet_id: String = "", p_kind: String = "", p_item_id: String = "",
		p_body_id: String = "") -> void:
	faction_id = p_faction_id
	planet_id = p_planet_id
	kind = p_kind
	item_id = p_item_id
	body_id = p_body_id


func type_name() -> String:
	return "queue_build"


func to_dict() -> Dictionary:
	return {"type": type_name(), "faction": faction_id, "planet": planet_id, "kind": kind, "item": item_id, "body": body_id}
