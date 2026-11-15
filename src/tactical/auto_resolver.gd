class_name AutoResolver
extends RefCounted
## Plays a battle to the end with AI on every side, with no presentation.
## This is the auto-resolve for low-stakes battles and missions, and the
## basis of tools/simulate_battles.gd for balance testing.


## Runs a battle to completion. Calls engine.start() unless already started.
## Returns {"winner", "rounds", "commands", "history": [command dicts]}.
static func resolve(engine: BattleEngine, ai: RuleBasedAI = null, max_commands: int = 20000) -> Dictionary:
	if ai == null:
		ai = RuleBasedAI.new()
	if engine.state.round_number == 0:
		engine.start()
	var history: Array[Dictionary] = []
	while not engine.state.is_over and history.size() < max_commands:
		var cmd := ai.decide(engine)
		var result := engine.submit(cmd)
		if not result.ok:
			push_warning("AutoResolver: AI command rejected (%s); ending turn" % result.error)
			cmd = EndTurnCommand.new(engine.state.active_unit_id)
			engine.submit(cmd)
		history.append(cmd.to_dict())
	return {
		"winner": engine.state.winner,
		"rounds": engine.state.round_number,
		"commands": history.size(),
		"history": history,
	}
