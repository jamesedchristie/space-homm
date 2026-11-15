class_name AssignHeroCommand
extends GalaxyCommand
## Put a hero in command of a fleet. The hero must be waiting at a planet and
## the fleet must be at that same planet with no commander.

var hero_id: String
var fleet_id: String


func _init(p_faction_id: String = "", p_hero_id: String = "", p_fleet_id: String = "") -> void:
	faction_id = p_faction_id
	hero_id = p_hero_id
	fleet_id = p_fleet_id


func type_name() -> String:
	return "assign_hero"


func to_dict() -> Dictionary:
	return {"type": type_name(), "faction": faction_id, "hero": hero_id, "fleet": fleet_id}
