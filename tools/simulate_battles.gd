extends SceneTree
## Balance tool: auto-resolves a scenario many times with different seeds and
## prints win rates, battle length and which ships survive.
##   godot --headless --path . -s res://tools/simulate_battles.gd -- --scenario=first_skirmish --runs=200


func _initialize() -> void:
	var scenario_id := "first_skirmish"
	var runs := 100
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--scenario="):
			scenario_id = arg.trim_prefix("--scenario=")
		elif arg.begins_with("--runs="):
			runs = int(arg.trim_prefix("--runs="))

	var data := DataRegistry.get_default()
	if not data.errors.is_empty():
		printerr("Content errors:\n  " + "\n  ".join(data.errors))
		quit(1)
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


func _per_run(counts: Dictionary, runs: int) -> String:
	var parts := PackedStringArray()
	for k: String in counts:
		parts.append("%s %.1f" % [k, float(counts[k]) / runs])
	return ", ".join(parts)
