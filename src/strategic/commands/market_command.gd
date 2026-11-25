class_name MarketCommand
extends GalaxyCommand
## Buy (amount > 0) or sell (amount < 0) a strategic resource at the market (TradeRules).

var resource: String
var amount: int


func _init(p_faction_id: String = "", p_resource: String = "", p_amount: int = 0) -> void:
	faction_id = p_faction_id
	resource = p_resource
	amount = p_amount


func type_name() -> String:
	return "market"


func to_dict() -> Dictionary:
	return {"type": type_name(), "faction": faction_id, "resource": resource, "amount": amount}
