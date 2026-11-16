class_name SplitFleetCommand
extends GalaxyCommand
## Detach some of a fleet's ships into a new fleet on an adjacent free system.
## The new fleet pays the move into that system from the old fleet's moves
## left; the commander (if any) stays with the old fleet.

var fleet_id: String
var ship_uids: Array[String] = []
var to: Vector2i


func _init(p_faction_id: String = "", p_fleet_id: String = "", p_ship_uids: Array[String] = [], p_to: Vector2i = Vector2i.ZERO) -> void:
	faction_id = p_faction_id
	fleet_id = p_fleet_id
	ship_uids = p_ship_uids
	to = p_to


func type_name() -> String:
	return "split_fleet"


func to_dict() -> Dictionary:
	return {"type": type_name(), "faction": faction_id, "fleet": fleet_id, "ships": ship_uids, "to": [to.x, to.y]}
