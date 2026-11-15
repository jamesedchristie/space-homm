class_name TestCase
extends RefCounted
## Minimal test base class (no addon needed). Any method starting with
## "test_" in a tests/**/test_*.gd file extending this is run by run_tests.gd.
## Assertions record failures and keep going (GDScript has no exceptions).

var failures: PackedStringArray = []
var _current := ""


func before_each() -> void:
	pass


func assert_true(condition: bool, message: String = "") -> void:
	if not condition:
		_fail("expected true. %s" % message)


func assert_false(condition: bool, message: String = "") -> void:
	if condition:
		_fail("expected false. %s" % message)


func assert_eq(actual: Variant, expected: Variant, message: String = "") -> void:
	if typeof(actual) != typeof(expected) and not (_is_number(actual) and _is_number(expected)):
		_fail("expected %s (%s), got %s (%s). %s" % [expected, type_string(typeof(expected)),
				actual, type_string(typeof(actual)), message])
	elif actual != expected:
		_fail("expected %s, got %s. %s" % [expected, actual, message])


func assert_ne(actual: Variant, unexpected: Variant, message: String = "") -> void:
	if actual == unexpected:
		_fail("did not expect %s. %s" % [unexpected, message])


func assert_near(actual: float, expected: float, tolerance: float = 0.001, message: String = "") -> void:
	if absf(actual - expected) > tolerance:
		_fail("expected %f ± %f, got %f. %s" % [expected, tolerance, actual, message])


func _fail(message: String) -> void:
	failures.append("%s: %s" % [_current, message])


func _is_number(v: Variant) -> bool:
	return typeof(v) == TYPE_INT or typeof(v) == TYPE_FLOAT
