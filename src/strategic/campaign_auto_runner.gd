class_name CampaignAutoRunner
extends RefCounted
## Plays a campaign headlessly: GalaxyAI for every faction, every battle
## auto-resolved. Used by tests and tools/simulate_campaign.gd.


## Returns {"winner", "turns", "commands", "battles"}.
static func run(engine: GalaxyEngine, max_commands: int = 5000) -> Dictionary:
	var ai := GalaxyAI.new()
	if engine.state.turn_number == 0:
		engine.start()
	var commands := 0
	var battles := 0
	while not engine.state.is_over and commands < max_commands:
		if engine.has_pending_battle():
			engine.auto_resolve_pending_battle()
			battles += 1
			continue
		var cmd := ai.decide(engine)
		var result := engine.submit(cmd)
		if not result.ok:
			push_warning("CampaignAutoRunner: rejected %s (%s)" % [cmd.to_dict(), result.error])
			engine.submit(EndFactionTurnCommand.new(engine.current_faction_id()))
		commands += 1
	return {
		"winner": engine.state.winner,
		"turns": engine.state.turn_number,
		"commands": commands,
		"battles": battles,
	}
