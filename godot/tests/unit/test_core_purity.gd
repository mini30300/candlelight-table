extends "res://tests/testing.gd"
## The core purity lint (ARCHITECTURE §2): every script under res://core/** is integer-only and engine-free.
## Forbidden anywhere in a file, comments and strings included: the WORDS below (plain substrings) and the
## float-maths calls in FN_RE as whole words followed by "(" (so `isqrt(` and `js_round(` pass while `sqrt(` and
## `round(` fail). A numeric literal with a decimal point is forbidden outside string literals (Version.APP_VER
## may say "0.1"). The planted fixture under tests/unit/fixtures/purity_bad proves the scanner bites.

const CORE_DIR := "res://core"
const BAD_DIR := "res://tests/unit/fixtures/purity_bad"
const WORDS := [
	"float", "Vector2", "Vector3", "Vector4", "Transform", "Quaternion", "Basis", "Plane", "Color(",
	"randf", "randi", "randomize", "rand_from_seed", "RandomNumberGenerator",
	"Time.", "OS.", "Engine.", "Node", "get_tree", "get_node", "await", "signal", "%f", "%.",
]
const FN_RE := "\\b(sin|cos|tan|asin|acos|atan|atan2|sqrt|pow|lerp|exp|log|floor|ceil|round|fmod|fposmod|snapped|ease|smoothstep|inverse_lerp|remap|deg_to_rad|rad_to_deg|seed|wrapf|clampf|minf|maxf|absf|signf|cubic_interpolate|bezier_interpolate|move_toward|pingpong|is_equal_approx|is_zero_approx)\\("
var fn_re := RegEx.create_from_string(FN_RE)
var dec_re := RegEx.create_from_string("\\d\\.\\d")
var str_re := RegEx.create_from_string("\"(?:[^\"\\\\]|\\\\.)*\"|'(?:[^'\\\\]|\\\\.)*'")


## Replaces every string literal on the line with spaces of the same length (keeps columns).
func _blank_strings(line: String) -> String:
	var out := line
	var m := str_re.search(out)
	while m != null:
		out = out.substr(0, m.get_start()) + " ".repeat(m.get_end() - m.get_start()) + out.substr(m.get_end())
		m = str_re.search(out, m.get_end())
	return out


## Scans one script's text; returns "label:line: token" for every hit.
func scan_text(text: String, label: String) -> Array[String]:
	var hits: Array[String] = []
	var lines := text.split("\n")
	for i: int in lines.size():
		var line: String = lines[i]
		var where := "%s:%d" % [label, i + 1]
		for w: String in WORDS:
			if line.contains(w):
				hits.append(where + ": " + w)
		var fm := fn_re.search(line)
		if fm != null:
			hits.append(where + ": " + fm.get_string())
		var dm := dec_re.search(_blank_strings(line))
		if dm != null:
			hits.append(where + ": decimal literal " + dm.get_string())
	return hits


## Every .gd file under a folder, recursively, sorted.
func _gd_files(path: String) -> PackedStringArray:
	var out := PackedStringArray()
	var dir := DirAccess.open(path)
	if dir == null:
		return out
	for f in dir.get_files():
		if f.ends_with(".gd"):
			out.append(path + "/" + f)
	for d in dir.get_directories():
		out.append_array(_gd_files(path + "/" + d))
	out.sort()
	return out


func test_core_is_pure() -> void:
	var files := _gd_files(CORE_DIR)
	assert_true(files.size() >= 7, "found %d scripts under %s" % [files.size(), CORE_DIR])
	var hits: Array[String] = []
	for f: String in files:
		var src := FileAccess.get_file_as_string(f)
		assert_true(src.length() > 0, "read " + f)
		hits.append_array(scan_text(src, f))
	assert_true(hits.is_empty(), "no forbidden token in core/** (file:line: token)", hits)


func test_core_scripts_are_refcounted_and_named() -> void:
	var bad := []
	for f: String in _gd_files(CORE_DIR):
		var src := FileAccess.get_file_as_string(f)
		if not src.begins_with("class_name ") or not src.contains("\nextends RefCounted\n"):
			bad.append(f)
	assert_true(bad.is_empty(), "every core script starts with class_name and extends RefCounted", bad)


func test_planted_fixture_is_flagged() -> void:
	var files := _gd_files(BAD_DIR)
	assert_true(files.size() >= 1, "the fixture folder holds a planted script")
	var hits: Array[String] = []
	for f: String in files:
		hits.append_array(scan_text(FileAccess.get_file_as_string(f), f))
	var joined := "\n".join(hits)
	assert_true(joined.contains(": float"), "the planted float is flagged", hits)
	assert_true(joined.contains("decimal literal 1.5"), "the planted decimal literal is flagged", hits)
	assert_true(joined.contains(": sin("), "the planted sin( is flagged", hits)


func test_scanner_rules() -> void:
	assert_eq(scan_text("var x := 1\nvar y: int = x * 2", "t").size(), 0, "plain integer code passes")
	assert_eq(scan_text("var x := 1.5", "t").size(), 1, "a decimal literal is flagged")
	assert_eq(scan_text("const V := \"ใหม่ 0.1\"", "t").size(), 0, "a decimal point inside a string literal passes")
	assert_eq(scan_text("# ใช้ Node ไม่ได้", "t").size(), 1, "a forbidden word in a comment is flagged")
	assert_eq(scan_text("var s := \"float\"", "t").size(), 1, "a forbidden word inside a string is flagged")
	assert_eq(scan_text("var r := Fx.isqrt(n)", "t").size(), 0, "isqrt( passes")
	assert_eq(scan_text("var r := sqrt(n)", "t").size(), 1, "sqrt( is flagged")
	assert_eq(scan_text("var r := Fx.js_round(x, 2)", "t").size(), 0, "js_round( passes")
	assert_eq(scan_text("var r := round(x)", "t").size(), 1, "round( is flagged")
	assert_eq(scan_text("var r := lerp(a, b, t)", "t").size(), 1, "lerp( is flagged")
	assert_eq(scan_text("var t := Time.get_ticks_msec()", "t").size(), 1, "Time. is flagged")
	assert_eq(scan_text("var v := Vector2(1, 2)", "t").size(), 1, "Vector2 is flagged")
	assert_eq(scan_text("var n := randi() % 6", "t").size(), 1, "randi is flagged")
	assert_eq(scan_text("signal done", "t").size(), 1, "signal is flagged")
	assert_eq(scan_text("await x", "t").size(), 1, "await is flagged")
	assert_true(scan_text("print(\"%.2f\" % x)", "t").size() >= 1, "a printf decimal format is flagged")
	assert_eq(scan_text("var p := \"a.b\" + \"1.\" + str(1) + \".\"", "t").size(), 0, "dots without digits on both sides pass")
	assert_eq(scan_text("var x := 1.5\nvar y := 2.5", "t").size(), 2, "one hit per line")
	assert_eq(scan_text("var x := 1.5", "core/x.gd")[0], "core/x.gd:1: decimal literal 1.5", "hits name file, line and token")
