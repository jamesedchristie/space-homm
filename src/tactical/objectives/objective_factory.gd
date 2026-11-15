class_name ObjectiveFactory
extends RefCounted
## Builds objectives from scenario JSON. Register new objective types here.


static func build(defs: Array) -> Array[BattleObjective]:
	var out: Array[BattleObjective] = []
	for d: Dictionary in defs:
		var o := create(d)
		if o != null:
			out.append(o)
	return out


static func create(d: Dictionary) -> BattleObjective:
	var o: BattleObjective
	match d.get("type", ""):
		"eliminate_all":
			o = EliminateAllObjective.new()
		"survive_rounds":
			o = SurviveRoundsObjective.new()
		"reach_cells":
			o = ReachCellsObjective.new()
		_:
			push_error("ObjectiveFactory: unknown objective type '%s'" % d.get("type", ""))
			return null
	o.def = d
	return o
