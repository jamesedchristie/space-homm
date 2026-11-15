class_name EliminateAllObjective
extends BattleObjective
## {"type": "eliminate_all"}: the last team with living units wins.


func evaluate(state: BattleState) -> int:
	var alive := state.teams_alive()
	if alive.is_empty():
		return BattleState.DRAW
	if alive.size() == 1:
		return alive[0]
	return BattleState.NO_WINNER


func describe() -> String:
	return def.get("description", "Destroy all enemy forces")
