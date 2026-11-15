class_name GalaxyCommand
extends RefCounted
## Base class for strategic-layer commands. Like tactical commands, these are
## plain data submitted by the player's UI or the AI.
## Subclasses: MoveFleetCommand, EndFactionTurnCommand.

var faction_id: String


func type_name() -> String:
	return "galaxy_command"


func to_dict() -> Dictionary:
	return {"type": type_name(), "faction": faction_id}
