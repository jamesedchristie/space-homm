class_name UseAbilityCommand
extends BattleCommand
## Use an ability. The target is always a cell: for unit-targeted abilities it
## is the target unit's cell; for self-targeted abilities the user's own cell.

var ability_id: String
var target: Vector2i


func _init(p_unit_id: String = "", p_ability_id: String = "", p_target: Vector2i = Vector2i.ZERO) -> void:
	unit_id = p_unit_id
	ability_id = p_ability_id
	target = p_target


func type_name() -> String:
	return "use_ability"


func to_dict() -> Dictionary:
	return {"type": type_name(), "unit": unit_id, "ability": ability_id, "target": [target.x, target.y]}
