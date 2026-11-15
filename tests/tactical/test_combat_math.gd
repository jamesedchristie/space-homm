extends TestCase

const FLAT := {"vs_shields": 1.0, "vs_hull": 1.0}
const KINETIC := {"vs_shields": 0.5, "vs_hull": 1.25}


func test_shields_absorb_first() -> void:
	var r := CombatMath.resolve(10.0, 20, 0, FLAT)
	assert_eq(r["shield_damage"], 10)
	assert_eq(r["hull_damage"], 0)


func test_overflow_hits_hull_minus_armor() -> void:
	var r := CombatMath.resolve(30.0, 20, 3, FLAT)
	assert_eq(r["shield_damage"], 20)
	assert_eq(r["hull_damage"], 7)


func test_damage_type_multipliers() -> void:
	# Kinetic: 20 raw does 10 to shields; with 5 shields, 10 raw depletes them
	# and the remaining 10 raw does 12.5 -> 12 or 13 to hull.
	assert_eq(CombatMath.resolve(20.0, 100, 0, KINETIC)["shield_damage"], 10)
	var r := CombatMath.resolve(20.0, 5, 0, KINETIC)
	assert_eq(r["shield_damage"], 5)
	assert_true(r["hull_damage"] == 12 or r["hull_damage"] == 13)


func test_armor_never_reduces_below_one() -> void:
	assert_eq(CombatMath.resolve(5.0, 0, 50, FLAT)["hull_damage"], 1)


func test_bypass_and_ignore_armor() -> void:
	var r := CombatMath.resolve(10.0, 50, 4, FLAT, true, true)
	assert_eq(r["shield_damage"], 0)
	assert_eq(r["hull_damage"], 10)


func test_status_modifiers() -> void:
	var data := Fixtures.registry()
	var u := BattleUnit.from_def("u", data.units["test_dummy"], 0, Vector2i.ZERO)
	assert_near(u.get_stat("damage_taken"), 1.0)
	u.statuses.append(StatusInstance.new(data.statuses["braced"], 1))
	assert_near(u.get_stat("damage_taken"), 0.75)
	u.statuses.append(StatusInstance.new(data.statuses["evasive"], 1))
	assert_near(u.get_stat("damage_taken"), 0.45)
