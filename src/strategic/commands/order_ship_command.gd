class_name OrderShipCommand
extends GalaxyCommand
## A standing order for a civilian ship, Civ-worker style: "go to that body and
## build X there" (constructor) or "go and found a colony there" (colony ship).
## The ship leaves wherever it is (deployed in a system or riding in a fleet),
## travels on its own over as many turns as it takes, and carries out the job on
## arrival. A plain move order for the fleet cancels it.

const JOB := "job"
const FOUND := "found"

var ship_uid: String
var planet_id: String
var body_id: String
var action: String
## Building id for a JOB ("" = the best development for that body).
var item_id: String


func _init(p_faction_id: String = "", p_ship_uid: String = "", p_planet_id: String = "", p_body_id: String = "",
		p_action: String = JOB, p_item_id: String = "") -> void:
	faction_id = p_faction_id
	ship_uid = p_ship_uid
	planet_id = p_planet_id
	body_id = p_body_id
	action = p_action
	item_id = p_item_id


func type_name() -> String:
	return "order_ship"


func to_dict() -> Dictionary:
	return {"type": type_name(), "faction": faction_id, "ship": ship_uid, "planet": planet_id, "body": body_id,
			"action": action, "item": item_id}
