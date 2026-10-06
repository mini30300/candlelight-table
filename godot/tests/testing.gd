extends RefCounted
## Minimal test base: a test script extends this and defines `func test_*()` methods.
## Each assertion prints an `ok`/`FAIL` line (like the repo's Playwright suites) and counts.

var passed := 0
var failed := 0


func assert_true(cond: bool, msg: String, detail: Variant = null) -> void:
	if cond:
		passed += 1
		print("ok    " + msg)
	else:
		failed += 1
		print("FAIL  " + msg + ("" if detail == null else " " + str(detail).left(1500)))


func assert_false(cond: bool, msg: String, detail: Variant = null) -> void:
	assert_true(not cond, msg, detail)


func assert_eq(a: Variant, b: Variant, msg: String) -> void:
	if a == b:
		passed += 1
		print("ok    " + msg)
	else:
		failed += 1
		print("FAIL  %s: expected %s, got %s" % [msg, str(b).left(500), str(a).left(500)])


func assert_ne(a: Variant, b: Variant, msg: String) -> void:
	if a != b:
		passed += 1
		print("ok    " + msg)
	else:
		failed += 1
		print("FAIL  %s: both are %s" % [msg, str(a).left(500)])


## Called by the runner; a test script may override it to prepare shared data.
func setup() -> void:
	pass
