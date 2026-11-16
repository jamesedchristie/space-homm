class_name OddsEstimator
extends RefCounted
## Estimates how often a battle goes a team's way under auto-resolve by
## playing copies of it to the end (different seeds, AI on every side).
## On desktop the runs go to WorkerThreadPool; on single-threaded builds
## (the Web export) call step() once per frame instead.
##   var odds := OddsEstimator.new(data, scenario, team, 12)
##   odds.start()
##   ... each frame: odds.step(); show odds.wins / odds.completed ...
##   when odds.is_done(): odds.finish()

var runs := 12
var wins := 0
var completed := 0

var _data: DataRegistry
var _scenario: Dictionary
var _team := 0
var _seed_base := 0
var _mutex := Mutex.new()
var _task := -1
var _next := 0


func _init(data: DataRegistry, scenario: Dictionary, team: int, p_runs: int = 12, seed_base: int = 9001) -> void:
	_data = data
	_scenario = scenario.duplicate(true)
	_team = team
	runs = p_runs
	_seed_base = seed_base


static func threaded() -> bool:
	return OS.get_name() != "Web" and OS.get_processor_count() > 1


func start() -> void:
	EffectRegistry.known_types()  # build the shared effect table before threads read it
	if threaded():
		_task = WorkerThreadPool.add_group_task(_run_one, runs, -1, true, "Auto-resolve odds")


## Single-threaded fallback: runs one simulation. Safe to call when threaded (no-op).
func step() -> void:
	if _task != -1 or _next >= runs:
		return
	_run_one(_next)
	_next += 1


func is_done() -> bool:
	_mutex.lock()
	var done := completed >= runs
	_mutex.unlock()
	return done


## Releases the worker task. Call once is_done() (it then returns at once).
func finish() -> void:
	if _task != -1:
		WorkerThreadPool.wait_for_group_task_completion(_task)
		_task = -1


## Win share so far (0..1), or -1 before the first result.
func ratio() -> float:
	_mutex.lock()
	var r := float(wins) / completed if completed > 0 else -1.0
	_mutex.unlock()
	return r


func _run_one(index: int) -> void:
	var battle := BattleEngine.from_scenario(_data, _scenario.duplicate(true), _seed_base + index * 7919)
	AutoResolver.resolve(battle)
	_mutex.lock()
	completed += 1
	if battle.state.winner == _team:
		wins += 1
	_mutex.unlock()
