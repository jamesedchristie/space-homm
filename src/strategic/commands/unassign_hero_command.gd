class_name UnassignHeroCommand
extends GalaxyCommand
## Relieve a fleet's commander. The fleet must be at one of the faction's
## planets; the hero stays there.

var hero_id: String


func _init(p_faction_id: String = "", p_hero_id: String = "") -> void:
	faction_id = p_faction_id
	hero_id = p_hero_id


func type_name() -> String:
	return "unassign_hero"


func to_dict() -> Dictionary:
	return {"type": type_name(), "faction": faction_id, "hero": hero_id}
