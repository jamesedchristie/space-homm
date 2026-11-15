extends SceneTree
## Balance tool for the strategic layer: plays a campaign AI-vs-AI many times
## (all battles auto-resolved) and prints win rates, length and battle counts.
##   godot --headless --path . -s res://tools/simulate_campaign.gd -- --campaign=the_drift --runs=50


func _initialize() -> void:
	var campaign_id := "the_drift"
	var runs := 30
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--campaign="):
			campaign_id = arg.trim_prefix("--campaign=")
		elif arg.begins_with("--runs="):
			runs = int(arg.trim_prefix("--runs="))

	var data := DataRegistry.get_default()
	if not data.errors.is_empty():
		printerr("Content errors:\n  " + "\n  ".join(data.errors))
		quit(1)
		return

	var wins := {}
	var turns := 0
	var max_turns := 0
	var battles := 0
	var missions := 0
	var started := Time.get_ticks_msec()
	for i in runs:
		var result := CampaignAutoRunner.run(GalaxyEngine.from_campaign(data, campaign_id, i + 1))
		var key: String = result["winner"] if result["winner"] != "" else "draw"
		wins[key] = wins.get(key, 0) + 1
		turns += result["turns"]
		max_turns = maxi(max_turns, result["turns"])
		battles += result["battles"]
		missions += result["missions"]

	print("Campaign '%s', %d runs in %d ms" % [campaign_id, runs, Time.get_ticks_msec() - started])
	for key: String in wins:
		print("  %-10s %5.1f%%" % [key, 100.0 * wins[key] / runs])
	print("  avg turns %.1f (max %d), avg battles %.1f, avg missions %.1f" % [float(turns) / runs, max_turns,
			float(battles) / runs, float(missions) / runs])
	quit()
