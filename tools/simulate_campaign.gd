extends SceneTree
## Balance tool for the strategic layer: plays a campaign AI-vs-AI many times
## (all battles auto-resolved) and prints win rates, how games end, length,
## and economy figures for the major powers.
##   godot --headless --path . -s res://tools/simulate_campaign.gd -- --campaign=the_drift --runs=50
## Add --verbose for one line per run, --first=N to start at seed N (to split a big batch over processes).


func _initialize() -> void:
	var campaign_id := "the_drift"
	var runs := 30
	var verbose := false
	var first_seed := 1
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--campaign="):
			campaign_id = arg.trim_prefix("--campaign=")
		elif arg.begins_with("--runs="):
			runs = int(arg.trim_prefix("--runs="))
		elif arg == "--verbose":
			verbose = true
		elif arg.begins_with("--first="):
			first_seed = int(arg.trim_prefix("--first="))

	var data := DataRegistry.get_default()
	if not data.errors.is_empty():
		printerr("Content errors:\n  " + "\n  ".join(data.errors))
		quit(1)
		return

	var wins := {}
	var reasons := {}
	var turns := 0
	var max_turns := 0
	var battles := 0
	var missions := 0
	var totals := {}  # event type -> count over all runs
	var majors := 0
	var techs := 0
	var pop := 0
	var colonies := 0
	var credits_net := 0
	var upkeep := 0
	var wonders := 0
	var started := Time.get_ticks_msec()
	for i in runs:
		var engine := GalaxyEngine.from_campaign(data, campaign_id, first_seed + i)
		var result := CampaignAutoRunner.run(engine)
		var key: String = result["winner"] if result["winner"] != "" else "draw"
		wins[key] = wins.get(key, 0) + 1
		reasons[result["reason"]] = reasons.get(result["reason"], 0) + 1
		turns += result["turns"]
		max_turns = maxi(max_turns, result["turns"])
		battles += result["battles"]
		missions += result["missions"]
		for t: String in result["events"]:
			totals[t] = int(totals.get(t, 0)) + int(result["events"][t])
		var line := PackedStringArray()
		for f in engine.state.factions:
			if f.get("role", "major") != "major":
				continue
			var id: String = f["id"]
			var income := EmpireRules.income(engine, id)
			majors += 1
			techs += engine.state.known_techs(id).size()
			pop += EmpireRules.total_population(engine, id)
			colonies += EmpireRules.colony_count(engine, id)
			credits_net += int(income["credits"])
			upkeep += int(income["upkeep"])
			wonders += EmpireRules.megaprojects_of(engine, id).size()
			line.append("%s t%d p%d s%d c%+d" % [id, engine.state.known_techs(id).size(), EmpireRules.total_population(engine, id),
					engine.state.planets_of(id).size(), int(income["credits"])])
		if verbose:
			print("  seed %2d: %-8s %-11s turn %3d | %s" % [first_seed + i, key, result["reason"], result["turns"], " | ".join(line)])

	print("Campaign '%s', %d runs in %d ms" % [campaign_id, runs, Time.get_ticks_msec() - started])
	for key: String in wins:
		print("  %-10s %5.1f%%" % [key, 100.0 * wins[key] / runs])
	print("  endings: %s" % str(reasons))
	print("  avg turns %.1f (max %d), avg battles %.1f, avg missions %.1f" % [float(turns) / runs, max_turns,
			float(battles) / runs, float(missions) / runs])
	if majors > 0:
		print("  per major at the end: %.1f techs, %.1f pop in %.1f colonies, net credits %+.1f (upkeep %.1f), %.2f megaprojects" % [
				float(techs) / majors, float(pop) / majors, float(colonies) / majors, float(credits_net) / majors,
				float(upkeep) / majors, float(wonders) / majors])
	print("  per run: %.1f events answered, %.1f pop growths, %.1f megaprojects completed, %.1f budget crises" % [
			float(totals.get(GalaxyEvents.EVENT_RESOLVED, 0)) / runs, float(totals.get(GalaxyEvents.POP_GREW, 0)) / runs,
			float(totals.get(GalaxyEvents.MEGAPROJECT_COMPLETED, 0)) / runs, float(totals.get(GalaxyEvents.BUDGET_CRISIS, 0)) / runs])
	quit()
