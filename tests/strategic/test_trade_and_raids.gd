extends TestCase
## Phase 6: trade agreements, the Free Traders' market and Planetarion-style raids.


func _sector() -> GalaxyEngine:
	var e := GalaxyEngine.from_campaign(DataRegistry.get_default(), "random_sector", 2)
	e.start()
	return e


func _meet(e: GalaxyEngine, a: String, b: String) -> void:
	e.state.met[GalaxyState.relation_key(a, b)] = e.state.turn_number


func test_trade_agreement_pays_and_ends_with_war() -> void:
	var e := _sector()
	var s := e.state
	var a := "patrol"
	var b := "veltari"
	_meet(e, a, b)
	s.set_relation(a, b, "peace")
	DiplomacyRules.change_opinion(s, b, a, -100)
	var low := e.submit(DiplomacyCommand.new(a, b, "propose_trade"))
	assert_true(low.ok, low.error)
	assert_false(TradeRules.has_pact(s, a, b), "they don't like us enough")
	DiplomacyRules.change_opinion(s, b, a, 200)
	var before := EmpireRules.trade_income(e, a)
	assert_true(e.submit(DiplomacyCommand.new(a, b, "propose_trade")).ok)
	assert_true(TradeRules.has_pact(s, a, b))
	assert_eq(EmpireRules.trade_income(e, a), before + TradeRules.pact_income(e, a, b))
	assert_true(TradeRules.pact_income(e, a, b) >= TradeRules.PACT_CREDITS)
	assert_false(e.submit(DiplomacyCommand.new(a, b, "propose_trade")).ok, "already trading")
	assert_true(e.submit(DiplomacyCommand.new(a, b, "declare_war")).ok)
	assert_false(TradeRules.has_pact(s, a, b), "war ends trade")


func test_market_buys_and_sells() -> void:
	var e := _sector()
	var s := e.state
	var stock: Dictionary = s.resources["patrol"]
	stock["volatiles"] = 30
	stock["credits"] = 500
	assert_false(e.submit(MarketCommand.new("patrol", "volatiles", -10)).ok, "no market before meeting the traders")
	_meet(e, "patrol", "traders")
	var price := TradeRules.price(e, "volatiles")
	assert_true(price > 0)
	assert_true(e.submit(MarketCommand.new("patrol", "volatiles", -10)).ok)
	assert_eq(int(stock["volatiles"]), 20)
	assert_eq(int(stock["credits"]), 500 + 10 * price)
	assert_true(e.submit(MarketCommand.new("patrol", "volatiles", 5)).ok)
	assert_eq(int(stock["volatiles"]), 25)
	assert_eq(int(stock["credits"]), 500 + 10 * price - int(ceil(5 * price * TradeRules.BUY_MARKUP)))
	assert_false(e.submit(MarketCommand.new("patrol", "volatiles", -999)).ok, "can't sell what you don't have")
	assert_false(e.submit(MarketCommand.new("patrol", "credits", -5)).ok, "credits aren't a commodity")


func test_raid_a_blockaded_system() -> void:
	var e := _sector()
	var s := e.state
	var target: Planet = null
	for p: Planet in s.planets.values():
		if p.owner.is_empty() and p.bodies.size() >= 2:
			target = p
			break
	target.owner = "veltari"
	target.add_building(target.bodies[0]["id"], "colony")
	target.add_building(target.bodies[1]["id"], "mining_base")
	s.set_relation("patrol", "veltari", "war")
	s.resources["veltari"]["credits"] = 300
	var fleet: Fleet = null
	for f: Fleet in s.fleets_of("patrol"):
		if not f.is_civilian_only(e.data):
			fleet = f
			break
	fleet.cell = target.cell
	fleet.moves_left = 2
	assert_false(e.validate(RaidCommand.new("patrol", fleet.id)).is_empty(), "no blockade yet")
	target.blockade = "patrol"
	var credits := int(s.resources["patrol"]["credits"])
	var result := e.submit(RaidCommand.new("patrol", fleet.id))
	assert_true(result.ok, result.error)
	assert_true(int(s.resources["patrol"]["credits"]) > credits, "loot")
	assert_true(int(s.resources["veltari"]["credits"]) < 300)
	assert_eq(fleet.moves_left, 0)
	assert_true(EmpireRules.is_offline(e, target.bodies[1]), "the mine is knocked offline")
	assert_eq(target.owner, "veltari", "a raid doesn't take the system")
	fleet.moves_left = 2
	assert_false(e.validate(RaidCommand.new("patrol", fleet.id)).is_empty(), "once per turn")


func test_pacts_and_raids_survive_a_save() -> void:
	var e := _sector()
	e.state.trade_pacts[GalaxyState.relation_key("veltari", "kesh")] = 3
	e.state.raided["haven"] = 2
	var e2: GalaxyEngine = GalaxySave.from_dict(e.data, GalaxySave.to_dict(e, "random_sector"))["engine"]
	assert_true(TradeRules.has_pact(e2.state, "kesh", "veltari"))
	assert_eq(int(e2.state.raided["haven"]), 2)
