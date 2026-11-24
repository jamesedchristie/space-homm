extends SceneTree
## Balance tool: auto-resolves a scenario many times with different seeds and
## prints win rates, battle length and which ships survive.
##   godot --headless --path . -s res://tools/simulate_battles.gd -- --scenario=first_skirmish --runs=200
## Rock-paper-scissors check: equal-cost fleets of each role fight each other
## (ships bought with --budget credits+alloys; half the runs with sides swapped):
##   godot --headless --path . -s res://tools/simulate_battles.gd -- --matrix --runs=20 [--budget=360]
##   ... -- --matrix --units=interceptor,bomber,corvette,frigate,destroyer,cruiser   (one fleet per unit)
##   ... -- --matrix --col-budget=540   (column fleets get a bigger budget)

## Representative fleets per role for --matrix (cycled until the budget is spent).
const ROLE_FLEETS := {
	"strike": ["bomber", "bomber", "interceptor"],
	"escort": ["corvette", "frigate"],
	"capital": ["destroyer", "cruiser"],
}


func _initialize() -> void:
	var scenario_id := "first_skirmish"
	var runs := 100
	var matrix := false
	var budget := 360.0
	var unit_list := ""
	var col_budget := -1.0
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--scenario="):
			scenario_id = arg.trim_prefix("--scenario=")
		elif arg.begins_with("--runs="):
			runs = int(arg.trim_prefix("--runs="))
		elif arg == "--matrix":
			matrix = true
		elif arg.begins_with("--budget="):
			budget = float(arg.trim_prefix("--budget="))
		elif arg.begins_with("--col-budget="):
			col_budget = float(arg.trim_prefix("--col-budget="))
		elif arg.begins_with("--units="):
			unit_list = arg.trim_prefix("--units=")
			matrix = true

	var data := DataRegistry.get_default()
	if not data.errors.is_empty():
		printerr("Content errors:\n  " + "\n  ".join(data.errors))
		quit(1)
		return
	if matrix:
		var fleets := ROLE_FLEETS.duplicate()
		if not unit_list.is_empty():
			fleets = {}
			for id in unit_list.split(","):
				fleets[id] = [id]
		_matrix(data, fleets, budget, runs, col_budget if col_budget > 0.0 else budget)
		quit()
		return

	var wins := {}
	var total_rounds := 0
	var max_rounds := 0
	var survivors := {}
	var ability_uses := {}
	var started := Time.get_ticks_msec()
	for i in runs:
		var engine := BattleEngine.from_scenario(data, scenario_id, i + 1)
		var result := AutoResolver.resolve(engine)
		var key := str(result["winner"])
		wins[key] = wins.get(key, 0) + 1
		total_rounds += result["rounds"]
		max_rounds = maxi(max_rounds, result["rounds"])
		for u in engine.state.living_units():
			survivors[u.def_id] = survivors.get(u.def_id, 0) + 1
		for cmd: Dictionary in result["history"]:
			if cmd["type"] == "use_ability":
				ability_uses[cmd["ability"]] = ability_uses.get(cmd["ability"], 0) + 1

	print("Scenario '%s', %d runs in %d ms" % [scenario_id, runs, Time.get_ticks_msec() - started])
	for key: String in wins:
		var label := "draw" if key == str(BattleState.DRAW) else "team " + key
		print("  %-8s %5.1f%%" % [label, 100.0 * wins[key] / runs])
	print("  avg rounds %.1f (max %d)" % [float(total_rounds) / runs, max_rounds])
	print("  survivors per battle: %s" % _per_run(survivors, runs))
	print("  ability uses per battle: %s" % _per_run(ability_uses, runs))
	quit()


## Row fleet's win rate against each column fleet (equal cost).
## col_budget: the column fleets' budget (to see how much bigger a countered fleet must be).
func _matrix(data: DataRegistry, fleets: Dictionary, budget: float, runs: int, col_budget: float) -> void:
	var started := Time.get_ticks_msec()
	var names: Array = fleets.keys()
	print("Equal-cost fleets (budget %d credits+alloys, strategic resources x2), %d runs per pair:" % [budget, runs])
	if col_budget != budget:
		print("  (column fleets: budget %d)" % col_budget)
	for n: String in names:
		var ships := RoleRules.fleet_for_budget(data, fleets[n], budget)
		var parts := PackedStringArray()
		for s: Dictionary in ships:
			var max_hull := int(data.units[s["unit"]]["stats"]["max_hull"])
			parts.append(s["unit"] + ("" if int(s["hull"]) >= max_hull else " (%d%%)" % roundi(100.0 * int(s["hull"]) / max_hull)))
		print("  %-10s %s" % [n, ", ".join(parts)])
	var header := "  %-10s" % "row wins"
	for n: String in names:
		header += " %9s" % n
	print(header)
	for a: String in names:
		var line := "  %-10s" % a
		for b: String in names:
			if a == b:
				line += " %9s" % "-"
				continue
			var won := 0.0
			for i in runs:
				var fa := RoleRules.fleet_for_budget(data, fleets[a], budget)
				var fb := RoleRules.fleet_for_budget(data, fleets[b], col_budget)
				var a_west := i % 2 == 0
				var scenario := RoleRules.duel_scenario(data, fa if a_west else fb, fb if a_west else fa)
				var engine := BattleEngine.from_scenario(data, scenario, 1000 + i)
				AutoResolver.resolve(engine)
				var winner := engine.state.winner
				if winner == (0 if a_west else 1):
					won += 1.0
				elif winner == BattleState.DRAW:
					won += 0.5
			line += " %8d%%" % roundi(100.0 * won / runs)
		print(line)
	print("  (draws count half; %d ms)" % (Time.get_ticks_msec() - started))


func _per_run(counts: Dictionary, runs: int) -> String:
	var parts := PackedStringArray()
	for k: String in counts:
		parts.append("%s %.1f" % [k, float(counts[k]) / runs])
	return ", ".join(parts)
