class_name CommandResult
extends RefCounted
## What BattleEngine.submit() returns: success plus the events that happened
## (for the presentation layer to animate), or failure with a reason.

var ok: bool
var error: String
var events: Array[Dictionary] = []


static func success(p_events: Array[Dictionary]) -> CommandResult:
	var r := CommandResult.new()
	r.ok = true
	r.events = p_events
	return r


static func failure(p_error: String) -> CommandResult:
	var r := CommandResult.new()
	r.ok = false
	r.error = p_error
	return r
