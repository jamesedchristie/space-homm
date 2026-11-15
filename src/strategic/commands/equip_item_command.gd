class_name EquipItemCommand
extends GalaxyCommand
## Equip an item from the faction's inventory into a hero's slot (the old item
## goes back to the inventory). item_id "" just unequips the slot.

var hero_id: String
var slot: String
var item_id: String


func _init(p_faction_id: String = "", p_hero_id: String = "", p_slot: String = "", p_item_id: String = "") -> void:
	faction_id = p_faction_id
	hero_id = p_hero_id
	slot = p_slot
	item_id = p_item_id


func type_name() -> String:
	return "equip_item"


func to_dict() -> Dictionary:
	return {"type": type_name(), "faction": faction_id, "hero": hero_id, "slot": slot, "item": item_id}
