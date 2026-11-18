class_name CivilianCommand
extends GalaxyCommand
## An order for a civilian ship (colony ship, constructor) in a system: the
## system map level. The ship is either deployed in the system or still in a
## fleet parked at it (the order deploys it).
##
## action:
##   "move"   go to body `body_id` (instant) so it waits there
##   "job"    a constructor starts building `item_id` (a development) on body `body_id`
##   "found"  a colony ship founds a colony on body `body_id` (and is used up)
##   "depart" a deployed ship leaves the system: joins the fleet in orbit or forms a new one
##   "cancel" a constructor drops its job (half the cost comes back)

const MOVE := "move"
const JOB := "job"
const FOUND := "found"
const DEPART := "depart"
const CANCEL := "cancel"

var planet_id: String
var ship_uid: String
var action: String
var body_id: String
var item_id: String


func _init(p_faction_id: String = "", p_planet_id: String = "", p_ship_uid: String = "", p_action: String = MOVE,
		p_body_id: String = "", p_item_id: String = "") -> void:
	faction_id = p_faction_id
	planet_id = p_planet_id
	ship_uid = p_ship_uid
	action = p_action
	body_id = p_body_id
	item_id = p_item_id


func type_name() -> String:
	return "civilian"


func to_dict() -> Dictionary:
	return {"type": type_name(), "faction": faction_id, "planet": planet_id, "ship": ship_uid, "action": action,
			"body": body_id, "item": item_id}
