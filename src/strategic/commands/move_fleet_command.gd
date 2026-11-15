class_name MoveFleetCommand
extends GalaxyCommand
## Move a fleet toward `to`. If `to` holds a visible enemy fleet, this is an
## attack. Hidden enemy fleets on the way intercept the move and start a battle.

var fleet_id: String
var to: Vector2i


func _init(p_faction_id: String = "", p_fleet_id: String = "", p_to: Vector2i = Vector2i.ZERO) -> void:
	faction_id = p_faction_id
	fleet_id = p_fleet_id
	to = p_to


func type_name() -> String:
	return "move_fleet"


func to_dict() -> Dictionary:
	return {"type": type_name(), "faction": faction_id, "fleet": fleet_id, "to": [to.x, to.y]}
