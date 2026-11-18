class_name CampaignAutoRunner
extends RefCounted
## Plays a campaign headlessly: GalaxyAI for every faction, every battle and
## mission auto-resolved. Used by tests and tools/simulate_campaign.gd.


## Returns {"winner", "reason", "turns", "commands", "battles", "missions", "events": {event type: count}}.
static func run(engine: GalaxyEngine, max_commands: int = 5000) -> Dictionary:
	var ai := GalaxyAI.new()
	if engine.state.turn_number == 0:
		engine.start()
	var commands := 0
	var battles := 0
	var missions := 0
	var counts := {}
	while not engine.state.is_over and commands < max_commands:
		if engine.has_pending_battle():
			_count(counts, engine.auto_resolve_pending_battle())
			battles += 1
			continue
		if engine.has_pending_mission():
			_count(counts, engine.auto_resolve_pending_mission())
			missions += 1
			continue
		var cmd := ai.decide(engine)
		var result := engine.submit(cmd)
		if not result.ok:
			push_warning("CampaignAutoRunner: rejected %s (%s)" % [cmd.to_dict(), result.error])
			result = engine.submit(EndFactionTurnCommand.new(engine.current_faction_id()))
		_count(counts, result.events)
		commands += 1
	return {
		"winner": engine.state.winner,
		"reason": engine.state.victory_reason,
		"turns": engine.state.turn_number,
		"commands": commands,
		"battles": battles,
		"missions": missions,
		"events": counts,
	}


static func _count(counts: Dictionary, events: Array[Dictionary]) -> void:
	for e in events:
		counts[e["type"]] = int(counts.get(e["type"], 0)) + 1
