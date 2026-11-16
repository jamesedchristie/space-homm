extends TestCase
## OddsEstimator: auto-resolve win share from simulated copies of a battle.


func _lopsided() -> Dictionary:
	# Three dummies against one: team 0 should win every time.
	return Fixtures.scenario("test_open", [[0, "test_dummy", 0, 0], [0, "test_dummy", 0, 2], [0, "test_dummy", 0, 4],
			[1, "test_fast_dummy", 6, 2]])


func test_step_by_step() -> void:
	var odds := OddsEstimator.new(Fixtures.registry(), _lopsided(), 0, 4)
	# Drive the single-threaded path explicitly.
	for i in 4:
		odds._run_one(i)
	assert_true(odds.is_done())
	assert_eq(odds.completed, 4)
	assert_near(odds.ratio(), 1.0)
	var loser := OddsEstimator.new(Fixtures.registry(), _lopsided(), 1, 3)
	for i in 3:
		loser._run_one(i)
	assert_near(loser.ratio(), 0.0)


func test_start_runs_everything() -> void:
	var odds := OddsEstimator.new(Fixtures.registry(), _lopsided(), 0, 6)
	assert_eq(odds.ratio(), -1.0, "no results yet")
	odds.start()
	var guard := 0
	while not odds.is_done() and guard < 100000:
		guard += 1
		odds.step()  # no-op when threaded
		OS.delay_usec(100)
	odds.finish()
	assert_eq(odds.completed, 6)
	assert_near(odds.ratio(), 1.0)
