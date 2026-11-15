class_name SurviveRoundsObjective
extends BattleObjective
## {"type": "survive_rounds", "team": 0, "rounds": 8}: `team` wins if any of
## its units are still alive once `rounds` full rounds have passed.


func evaluate(state: BattleState) -> int:
	var team := int(def.get("team", 0))
	if state.round_number > int(def.get("rounds", 10)) and not state.living_units(team).is_empty():
		return team
	return BattleState.NO_WINNER


func describe() -> String:
	return def.get("description", "Survive %d rounds" % int(def.get("rounds", 10)))
