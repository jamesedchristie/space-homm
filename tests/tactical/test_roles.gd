extends TestCase
## Ship classes and counters (RoleRules, data/tactical/roles.json): strike craft beat
## capital ships, escorts beat strike craft, capital ships beat escorts.

const ROLE_FLEETS := {
	"strike": ["bomber", "bomber", "interceptor"],
	"escort": ["corvette", "frigate"],
	"capital": ["destroyer", "cruiser"],
}


func test_triangle_multipliers() -> void:
	var data := DataRegistry.get_default()
	for target: String in RoleRules.COUNTER:
		var hunter: String = RoleRules.COUNTER[target]
		var up := RoleRules.multiplier_for(data, hunter, "", target)
		var down := RoleRules.multiplier_for(data, target, "", hunter)
		assert_true(up > 1.0, "%s should hit %s hard (x%s)" % [hunter, target, up])
		assert_true(down < up, "%s should not hit %s back as hard (x%s vs x%s)" % [target, hunter, down, up])


func test_classless_units_are_unaffected() -> void:
	var data := DataRegistry.get_default()
	var marine: Dictionary = data.units["marine"]
	assert_eq(RoleRules.multiplier(data, data.units["bomber"], marine), 1.0)
	assert_eq(RoleRules.multiplier(data, marine, data.units["cruiser"]), 1.0)
	assert_eq(RoleRules.summary(data, marine), "")


func test_warships_have_classes_and_summaries() -> void:
	var data := DataRegistry.get_default()
	for id: String in ["bomber", "interceptor", "corvette", "frigate", "ion_frigate", "destroyer", "cruiser", "battleship"]:
		var def: Dictionary = data.units[id]
		assert_true(RoleRules.class_of(def) in RoleRules.ROLES, "%s needs a role" % id)
		assert_ne(RoleRules.summary(data, def), "", "%s needs a counter summary" % id)


func test_ai_builds_the_counter() -> void:
	var data := DataRegistry.get_default()
	var options := ["interceptor", "bomber", "corvette", "frigate", "destroyer", "cruiser"]
	for enemy_class: String in RoleRules.COUNTER:
		var pick := GalaxyAI.choose_warship(data, options, {enemy_class: 100.0}, {})
		var cls := RoleRules.class_of(data.units[pick])
		assert_eq(cls, RoleRules.COUNTER[enemy_class], "against %s the AI built %s" % [enemy_class, pick])


func test_ai_keeps_a_mixed_navy() -> void:
	var data := DataRegistry.get_default()
	var options := ["interceptor", "bomber", "corvette", "frigate", "destroyer", "cruiser"]
	# A balanced enemy and a navy of nothing but strike craft: build something else.
	var pick := GalaxyAI.choose_warship(data, options, {"strike": 100.0, "escort": 100.0, "capital": 100.0}, {"strike": 1000.0})
	assert_ne(RoleRules.class_of(data.units[pick]), "strike", "picked %s" % pick)


func test_equal_cost_duels_follow_the_triangle() -> void:
	var data := DataRegistry.get_default()
	for target: String in RoleRules.COUNTER:
		var hunter: String = RoleRules.COUNTER[target]
		var a := RoleRules.fleet_for_budget(data, ROLE_FLEETS[hunter], 360.0)
		var b := RoleRules.fleet_for_budget(data, ROLE_FLEETS[target], 360.0)
		var engine := BattleEngine.from_scenario(data, RoleRules.duel_scenario(data, a, b), 1001)
		AutoResolver.resolve(engine)
		assert_eq(engine.state.winner, 0, "%s should beat %s at equal cost" % [hunter, target])
