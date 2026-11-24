extends TestCase
## One-click standing orders for civilian ships (OrderShipCommand): a constructor or colony
## ship flies to a body over several turns on its own and gets to work on arrival.

var _data: DataRegistry


func before_each() -> void:
	_data = DataRegistry.get_default()


func _engine() -> GalaxyEngine:
	var e := GalaxyEngine.from_campaign(_data, "solar_age", 3)
	e.start()
	return e


## Ends turns (resolving events, skipping fights) until it's the player's turn again.
func _next_player_turn(e: GalaxyEngine) -> void:
	var guard := 0
	while guard < 50:
		guard += 1
		if e.has_pending_event():
			e.submit(ResolveEventCommand.new(e.current_faction_id(), 0))
			continue
		if e.has_pending_battle():
			e.auto_resolve_pending_battle()
			continue
		if e.has_pending_mission():
			e.decline_pending_mission()
			continue
		var was := e.current_faction_id()
		e.submit(EndFactionTurnCommand.new(was))
		if e.current_faction_id() == "patrol":
			if e.has_pending_event():
				e.submit(ResolveEventCommand.new("patrol", 0))
			return


func _constructor(e: GalaxyEngine) -> Dictionary:
	for p: Planet in e.state.planets.values():
		for c in p.civilians:
			if c["owner"] == "patrol" and Fleet.role_of(_data, c["unit"]) == "constructor":
				return c
	return {}


## The unclaimed body farthest from `from` where the constructor could build.
func _far_site(e: GalaxyEngine, from: Vector2i) -> Planet:
	var best: Planet = null
	for p: Planet in e.state.planets.values():
		if not p.owner.is_empty() or p.bodies.is_empty():
			continue
		if SystemRules.default_job(e, "patrol", p.bodies[0]).is_empty():
			continue
		if best == null or e.state.grid.distance(from, p.cell) > e.state.grid.distance(from, best.cell):
			best = p
	return best


func test_constructor_order_travels_and_builds() -> void:
	var e := _engine()
	e.state.resources["patrol"]["credits"] = 999
	e.state.resources["patrol"]["alloys"] = 999
	var ship := _constructor(e)
	var start: Planet = SystemRules.locate_ship(e, "patrol", ship["uid"])["planet"]
	var site := _far_site(e, start.cell)
	assert_true(site != null)
	var r := e.submit(OrderShipCommand.new("patrol", ship["uid"], site.id, site.bodies[0]["id"]))
	assert_true(r.ok, r.error)
	var where := SystemRules.locate_ship(e, "patrol", ship["uid"])
	assert_true(where.has("fleet"), "the ship took off in a fleet of its own")
	assert_false(where["fleet"].order.is_empty())
	var started := false
	for t in 15:
		_next_player_turn(e)
		var job := SystemRules.job_on_body(site, site.bodies[0]["id"])
		if not job.is_empty():
			started = true
			assert_eq(job["uid"], ship["uid"])
			break
	assert_true(started, "the constructor reached the site and started work on its own")


func test_colony_ship_order_founds_a_colony() -> void:
	var e := _engine()
	var colony_uid := ""
	for f in e.state.fleets_of("patrol"):
		for s in f.ships:
			if Fleet.role_of(_data, s["unit"]) == "colony":
				colony_uid = s["uid"]
	var target: Planet = null
	for p: Planet in e.state.planets.values():
		if p.owner.is_empty() and not p.bodies.is_empty() and EmpireRules.is_habitable(e, p.bodies[0]):
			target = p
	assert_true(target != null, "Solar Age has a marginal world to settle")
	var r := e.submit(OrderShipCommand.new("patrol", colony_uid, target.id, target.bodies[0]["id"], OrderShipCommand.FOUND))
	assert_true(r.ok, r.error)
	for t in 15:
		if target.owner == "patrol":
			break
		_next_player_turn(e)
	assert_eq(target.owner, "patrol", "the colony ship flew there and founded the colony")
	assert_true(target.has_colony())


func test_invalid_orders_are_refused() -> void:
	var e := _engine()
	var ship := _constructor(e)
	var home := e.state.home_planet("patrol")
	var habitable: Planet = null
	for p: Planet in e.state.planets.values():
		if p.owner.is_empty() and not p.bodies.is_empty() and EmpireRules.is_habitable(e, p.bodies[0]):
			habitable = p
	assert_false(e.submit(OrderShipCommand.new("patrol", ship["uid"], habitable.id, habitable.bodies[0]["id"],
			OrderShipCommand.FOUND)).ok, "a constructor can't found colonies")
	assert_false(e.submit(OrderShipCommand.new("patrol", "nope", home.id, home.bodies[0]["id"])).ok)


func test_manual_move_cancels_and_orders_are_saved() -> void:
	var e := _engine()
	e.state.resources["patrol"]["credits"] = 999
	e.state.resources["patrol"]["alloys"] = 999
	var ship := _constructor(e)
	var start: Planet = SystemRules.locate_ship(e, "patrol", ship["uid"])["planet"]
	var site := _far_site(e, start.cell)
	e.submit(OrderShipCommand.new("patrol", ship["uid"], site.id, site.bodies[0]["id"]))
	var fleet: Fleet = SystemRules.locate_ship(e, "patrol", ship["uid"])["fleet"]
	var loaded := GalaxySave.from_dict(_data, GalaxySave.to_dict(e, "solar_age"))
	var e2: GalaxyEngine = loaded["engine"]
	assert_eq(e2.state.fleets[fleet.id].order, fleet.order, "orders survive a save")
	_next_player_turn(e)
	fleet = SystemRules.locate_ship(e, "patrol", ship["uid"]).get("fleet")
	if fleet == null or fleet.order.is_empty():
		return  # already arrived and working: nothing to cancel
	fleet.moves_left = 1
	var reach := e.reachable_for(fleet.id)
	for c: Vector2i in reach:
		if c != fleet.cell and e.state.fleet_at(c) == null:
			assert_true(e.submit(MoveFleetCommand.new("patrol", fleet.id, c)).ok)
			break
	assert_true(fleet.order.is_empty(), "moving the fleet by hand drops its orders")
