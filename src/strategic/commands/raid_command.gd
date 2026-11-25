class_name RaidCommand
extends GalaxyCommand
## Planetarion-style raid: a warfleet blockading an enemy system strips it (credits and strategic
## resources into your stores, a development knocked offline) instead of waiting for troops. Takes the
## fleet's remaining moves; once per turn per system.

var fleet_id: String


func _init(p_faction_id: String = "", p_fleet_id: String = "") -> void:
	faction_id = p_faction_id
	fleet_id = p_fleet_id


func type_name() -> String:
	return "raid"


func to_dict() -> Dictionary:
	return {"type": type_name(), "faction": faction_id, "fleet": fleet_id}
