extends SceneTree
## Smoke test for the full game flow: runs the main scene with autoplay on
## and "watch battles" so battles involving the player are played on the real
## battle screen, then handed back to the galaxy. Passes if the campaign ends
## and at least one battle and one mission went through the battle screen.
##   godot --headless --path . -s res://tools/smoke_campaign.gd

var _game: Node
var _frames := 0
var _battles_seen := 0
var _missions_seen := 0
var _last_battle: Node


func _initialize() -> void:
	Engine.time_scale = 10.0  # animations and AI pauses run 10x faster
	_game = load("res://src/presentation/main.tscn").instantiate()
	root.add_child(_game)


func _process(_delta: float) -> bool:
	_frames += 1
	var galaxy: Node = _game.galaxy
	if _frames == 3:
		galaxy.rng_seed = 7
		galaxy.watch_battles = true
		galaxy.autoplay = true
		galaxy.start_campaign()
		# Ready Reyes for the derelict (recommended level 2) so the AI flies the
		# mission and the mission round trip is exercised too.
		var reyes: Hero = galaxy.engine.state.heroes["reyes"]
		reyes.level = 2
		reyes.xp = HeroProgression.xp_for_level(galaxy.engine.data, 2)
	if _game.battle != null and _game.battle != _last_battle:
		_last_battle = _game.battle
		_battles_seen += 1
		_game.battle.ai_step_delay = 0.0
		if _game.battle.engine != null and not _game.battle.engine.state.mission_id.is_empty():
			_missions_seen += 1
	var engine: GalaxyEngine = galaxy.engine
	if _frames > 3 and engine != null and engine.state.is_over and _game.battle == null:
		var winner: String = engine.state.winner
		print("Campaign finished on turn %d, winner '%s', %d battle(s) played on the battle screen (%d mission(s))" % [
				engine.state.turn_number, winner, _battles_seen, _missions_seen])
		quit(0 if _battles_seen > 0 and _missions_seen > 0 and winner != "" else 1)
	elif _frames > 200000:
		printerr("Campaign did not finish (turn %d)" % engine.state.turn_number)
		quit(1)
	return false
