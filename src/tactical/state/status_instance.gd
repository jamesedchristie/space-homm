class_name StatusInstance
extends RefCounted
## A status effect currently applied to a unit (e.g. "braced" with 1 turn left).
## `def` is the status definition from data/tactical/statuses/*.json.

var id: String
var def: Dictionary
## Turns left. Decremented at the start of the owner's turn; removed at 0.
var remaining: int
## Unit that applied it (for credit and for damage-over-time scaling).
var source_id: String


func _init(p_def: Dictionary = {}, p_remaining: int = 1, p_source_id: String = "") -> void:
	def = p_def
	id = p_def.get("id", "")
	remaining = p_remaining
	source_id = p_source_id


func has_flag(flag: String) -> bool:
	return flag in def.get("flags", [])
