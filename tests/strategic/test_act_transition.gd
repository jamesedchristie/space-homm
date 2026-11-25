extends TestCase
## Act 1 -> Act 2: winning Solar Age continues in a hyperlane galaxy with the empire carried over.


## A Solar Age game, played a little, then won by the player.
func _won_act1() -> GalaxyEngine:
	var data := DataRegistry.get_default()
	var e := GalaxyEngine.from_campaign(data, "solar_age", 5)
	e.start()
	var player: String = e.state.factions[0]["id"]
	e.state.research[player]["known"].append_array(["improved_drives", "deep_space_sensors"])
	e.state.resources[player]["credits"] = 2000
	e.state.is_over = true
	e.state.winner = player
	e.state.victory_reason = VictoryRules.tech_reason(e)
	return e


func test_only_an_act1_win_continues() -> void:
	var e := _won_act1()
	var player: String = e.state.factions[0]["id"]
	assert_true(ActTransition.can_continue(e, player))
	e.state.winner = e.state.factions[1]["id"]
	assert_false(ActTransition.can_continue(e, player))
	var drift := GalaxyEngine.from_campaign(DataRegistry.get_default(), "the_drift", 1)
	drift.state.is_over = true
	drift.state.winner = player
	assert_false(ActTransition.can_continue(drift, player))


func test_act2_carries_the_empire_over() -> void:
	var act1 := _won_act1()
	var data := act1.data
	var player: String = act1.state.factions[0]["id"]
	var def := ActTransition.act2_campaign(data, act1, player)
	var e := GalaxyEngine.from_campaign(data, def, 3)
	e.start()
	var s := e.state
	assert_true(e.has_lanes(), "Act 2 is a lane galaxy")
	assert_false(e.is_system_scale())
	# The home system: named after the old one, with the old capital's colony and its pop.
	var home: Planet = s.planets_of(player)[0]
	assert_eq(home.name, str(act1.campaign["system"]["name"]))
	var old_home: Planet = act1.state.planets_of(player)[0]
	var old_pop := 0
	for b: Dictionary in old_home.bodies:
		old_pop = maxi(old_pop, int(b.get("pop", 0)))
	var pop := 0
	for b: Dictionary in home.bodies:
		pop = maxi(pop, int(b.get("pop", 0)))
	assert_eq(pop, old_pop)
	assert_true("shipyard" in home.buildings)
	# Techs (galaxy-scale ones) for everyone; a capped treasury.
	assert_true("improved_drives" in s.known_techs(player))
	assert_false("hyperdrive" in s.known_techs(player))
	for f: Dictionary in s.factions:
		if f.get("role", "major") == "major":
			assert_true("improved_drives" in s.known_techs(f["id"]), "%s should know the techs too" % f["id"])
			assert_false(s.planets_of(f["id"]).is_empty(), "%s should start founded" % f["id"])
	assert_true(int(s.resources[player]["credits"]) <= ActTransition.CARRY_CAP["credits"] + 200)
	# Fleets and heroes came along.
	var ships := 0
	for f: Fleet in act1.state.fleets_of(player):
		ships += f.ships.size()
	var now := 0
	for f: Fleet in s.fleets_of(player):
		now += f.ships.size()
	assert_eq(now, ships)
	for h: Hero in act1.state.heroes_of(player):
		assert_true(s.heroes.has(h.id), "%s should come along" % h.name)
		assert_eq(s.heroes[h.id].level, h.level)


func test_act2_plays() -> void:
	var act1 := _won_act1()
	var def := ActTransition.act2_campaign(act1.data, act1, act1.state.factions[0]["id"])
	var e := GalaxyEngine.from_campaign(act1.data, def, 4)
	var result := CampaignAutoRunner.run(e, 600)
	assert_true(result["commands"] > 100)
	assert_true(e.state.turn_number >= 5)


func test_every_fleet_gets_its_own_cell() -> void:
	var act1 := _won_act1()
	var player: String = act1.state.factions[0]["id"]
	var def := ActTransition.act2_campaign(act1.data, act1, player)
	# A big navy: eight fleets must still find room along the lanes round home.
	var extra: Array = []
	for i in 8:
		extra.append({"name": "Extra %d" % i, "owner": player, "ships": [{"unit": "interceptor"}]})
	def["generate"]["fleets"].append_array(extra)
	var e := GalaxyEngine.from_campaign(act1.data, def, 3)
	var cells := {}
	for f: Fleet in e.state.fleets.values():
		assert_false(cells.has(f.cell), "%s shares a cell" % f.name)
		cells[f.cell] = true
		assert_true(e.state.grid.is_passable(f.cell))
