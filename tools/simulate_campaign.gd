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
	## Strategic resources of the majors at the end: resource -> [stock, income, deposits tapped], summed.
	var strategic := {}
	for k in DepositRules.strategic(data):
		strategic[k] = [0, 0, 0]
	## turn -> systems owned by all majors, summed (and how many majors were counted)
	var sample_sum := {30: 0, 60: 0}
	var sample_n := {30: 0, 60: 0}
	var started := Time.get_ticks_msec()
	for i in runs:
		var engine := GalaxyEngine.from_campaign(data, campaign_id, first_seed + i)
		var result := CampaignAutoRunner.run(engine, 5000, [30, 60] as Array[int])
		var key: String = result["winner"] if result["winner"] != "" else "draw"
		wins[key] = wins.get(key, 0) + 1
		reasons[result["reason"]] = reasons.get(result["reason"], 0) + 1
		turns += result["turns"]
		max_turns = maxi(max_turns, result["turns"])
		battles += result["battles"]
		missions += result["missions"]
		for t: String in result["events"]:
			totals[t] = int(totals.get(t, 0)) + int(result["events"][t])
		for t: int in sample_sum:
			if result["samples"].has(t):
				for f in engine.state.factions:
					if f.get("role", "major") == "major" and result["samples"][t].has(f["id"]):
						sample_sum[t] += int(result["samples"][t][f["id"]])
						sample_n[t] += 1
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
			var strat := PackedStringArray()
			for k: String in strategic:
				var stock := int(engine.state.resources[id].get(k, 0))
				strategic[k][0] += stock
				strategic[k][1] += int(income.get(k, 0))
				for p in engine.state.planets_of(id):
					for b in p.bodies:
						if DepositRules.is_tapped(data, b, k):
							strategic[k][2] += 1
				strat.append("%s%d%+d" % [k.substr(0, 1), stock, int(income.get(k, 0))])
			line.append("%s t%d p%d s%d c%+d %s" % [id, engine.state.known_techs(id).size(), EmpireRules.total_population(engine, id),
					engine.state.planets_of(id).size(), int(income["credits"]), " ".join(strat)])
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
		var parts := PackedStringArray()
		for k: String in strategic:
			parts.append("%s %.1f (%+.1f/turn from %.1f deposits)" % [k, float(strategic[k][0]) / majors,
					float(strategic[k][1]) / majors, float(strategic[k][2]) / majors])
		print("  strategic per major at the end: %s; %.1f research waits per run" % [", ".join(parts),
				float(totals.get(GalaxyEvents.RESEARCH_WAITING, 0)) / runs])
	print("  systems owned per major: turn 30 %.2f, turn 60 %.2f" % [float(sample_sum[30]) / maxf(sample_n[30], 1), float(sample_sum[60]) / maxf(sample_n[60], 1)])
	print("  system layer per run: %.1f colonies founded, %.1f systems claimed, %.1f developments built, %.1f blockades, %.1f invasions, %.1f systems captured, %.1f civilian fleets destroyed" % [
			float(totals.get(GalaxyEvents.COLONY_FOUNDED, 0)) / runs, float(totals.get(GalaxyEvents.SYSTEM_CLAIMED, 0)) / runs,
			float(totals.get(GalaxyEvents.JOB_COMPLETED, 0)) / runs, float(totals.get(GalaxyEvents.BLOCKADE_STARTED, 0)) / runs,
			float(totals.get(GalaxyEvents.SYSTEM_INVADED, 0)) / runs, float(totals.get(GalaxyEvents.PLANET_CAPTURED, 0)) / runs,
			float(totals.get(GalaxyEvents.FLEET_DESTROYED, 0)) / runs])
	print("  per run: %.1f events answered, %.1f pop growths, %.1f megaprojects completed, %.1f budget crises" % [
			float(totals.get(GalaxyEvents.EVENT_RESOLVED, 0)) / runs, float(totals.get(GalaxyEvents.POP_GREW, 0)) / runs,
			float(totals.get(GalaxyEvents.MEGAPROJECT_COMPLETED, 0)) / runs, float(totals.get(GalaxyEvents.BUDGET_CRISIS, 0)) / runs])
	quit()
