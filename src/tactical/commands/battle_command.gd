class_name BattleCommand
extends RefCounted
## Base class for everything a controller (human UI or AI) can ask the engine
## to do. Commands are plain data; BattleEngine validates and applies them.
## Because players and AI submit the same commands, a battle can be replayed
## from its seed plus the command list.

var unit_id: String


func type_name() -> String:
	return "command"


func to_dict() -> Dictionary:
	return {"type": type_name(), "unit": unit_id}
