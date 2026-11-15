extends SceneTree
## Smoke test for the battle screen: loads the main scene with autoplay on and
## fast AI, lets it run, and reports whether the battle finished.
##   godot --headless --path . -s res://tools/smoke_battle_screen.gd

var _screen: Node
var _frames := 0


func _initialize() -> void:
	var scene: PackedScene = load("res://src/presentation/tactical/battle_screen.tscn")
	_screen = scene.instantiate()
	_screen.rng_seed = 99
	_screen.ai_step_delay = 0.0
	root.add_child(_screen)
	_screen.autoplay = true


func _process(_delta: float) -> bool:
	_frames += 1
	if _frames == 2:
		_screen._toggle_autoplay()  # re-enable after the initial human turn starts
		_screen._toggle_autoplay()
	var engine: BattleEngine = _screen.engine
	if engine != null and engine.state.is_over:
		print("Battle finished after %d frames: %s, round %d" % [_frames, EventFormatter.result_text(engine), engine.state.round_number])
		quit(0)
	elif _frames > 60000:
		printerr("Battle did not finish (round %d)" % engine.state.round_number)
		quit(1)
	return false
