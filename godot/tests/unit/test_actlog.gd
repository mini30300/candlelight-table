extends "res://tests/testing.gd"
## core/actlog.gd: sequence numbering, validation (ints only), canonical JSON and the snapshot / JSON round trips.


func test_append_assigns_sequence() -> void:
	var log := ActLog.new()
	assert_eq(log.last_seq(), 0, "empty log has seq 0")
	assert_eq(log.append({"a": "smove", "pid": "p1", "sid": "0:1", "pts": [[1000, 2000], [1500, 2500]]}), 1, "first act gets seq 1")
	assert_eq(log.append({"a": "done", "pid": 2}), 2, "second act gets seq 2 (int pid accepted)")
	assert_eq(log.append({"seq": 3, "a": "endph", "pid": "p1"}), 3, "an act carrying the right seq is accepted")
	assert_eq(log.last_seq(), 3, "last_seq")
	assert_eq(log.size(), 3, "size")
	assert_eq(log.error, "", "no error after accepted acts")
	var a1 := log.at(1)
	assert_eq(a1["seq"], 1, "at(1) carries seq")
	assert_eq(a1["pid"], "p1", "at(1) carries pid")
	assert_eq(a1["pts"][1][0], 1500, "nested arrays survive")
	assert_eq(log.at(9), {}, "unknown seq gives an empty act")
	assert_eq(log.at(0), {}, "seq 0 gives an empty act")


func test_rejects_bad_acts() -> void:
	var log := ActLog.new()
	log.append({"a": "nop", "pid": "p1"})
	assert_eq(log.append({"seq": 5, "a": "nop", "pid": "p1"}), -1, "a wrong seq is refused")
	assert_eq(log.error, "bad_seq", "error names the seq")
	assert_eq(log.append({"seq": "2", "a": "nop", "pid": "p1"}), -1, "a string seq is refused")
	assert_eq(log.append({"pid": "p1"}), -1, "missing a")
	assert_eq(log.error, "bad_a", "error names a")
	assert_eq(log.append({"a": "", "pid": "p1"}), -1, "empty a")
	assert_eq(log.append({"a": 7, "pid": "p1"}), -1, "non-string a")
	assert_eq(log.append({"a": "nop"}), -1, "missing pid")
	assert_eq(log.error, "bad_pid", "error names pid")
	assert_eq(log.append({"a": "nop", "pid": 1.5}), -1, "a decimal pid is refused")
	assert_eq(log.append({"a": "nop", "pid": 1, "v": 1.5}), -1, "a decimal value is refused")
	assert_eq(log.error, "bad_value", "error names the value")
	assert_eq(log.append({"a": "nop", "pid": 1, "v": [1, [2, 2.5]]}), -1, "a nested decimal is refused")
	assert_eq(log.append({"a": "nop", "pid": 1, "v": null}), -1, "null is refused")
	assert_eq(log.append({"a": "nop", "pid": 1, "v": {1: 2}}), -1, "a non-string dictionary key is refused")
	assert_eq(log.append({"a": "nop", "pid": 1, "v": Vector2(1, 2)}), -1, "an engine type is refused")
	assert_eq(log.size(), 1, "nothing refused was appended")
	assert_eq(log.append({"a": "nop", "pid": 1, "ok": true, "n": -5, "big": 4503599627370496, "d": {"x": [1, "s", false]}}), 2, "ints, bools, strings and nested containers are accepted")


func test_since() -> void:
	var log := ActLog.new()
	for i: int in 3:
		log.append({"a": "nop", "pid": i})
	assert_eq(log.since(0).size(), 3, "since(0) gives everything")
	var tail := log.since(2)
	assert_eq(tail.size(), 1, "since(2) gives one act")
	assert_eq(tail[0]["seq"], 3, "since(2) starts at seq 3")
	assert_eq(log.since(3).size(), 0, "since(last) is empty")
	assert_eq(log.since(-4).size(), 3, "a negative since gives everything")
	tail[0]["pid"] = 99
	assert_eq(log.at(3)["pid"], 2, "since() returns copies")


func test_canonical_json() -> void:
	var log := ActLog.new()
	log.append({"sid": "0:1", "pid": "p1", "pts": [[1000, 2000]], "a": "smove", "z": {"b": 1, "a": 2}})
	var want := '{"seq":1,"acts":[{"seq":1,"pid":"p1","a":"smove","pts":[[1000,2000]],"sid":"0:1","z":{"a":2,"b":1}}]}'
	assert_eq(log.to_json(), want, "keys seq, pid, a first, then sorted (nested too), no spaces, ints only")
	var other := ActLog.new()
	other.append({"z": {"a": 2, "b": 1}, "a": "smove", "pts": [[1000, 2000]], "pid": "p1", "sid": "0:1"})
	assert_eq(other.to_json(), want, "the same act given in another key order makes the same JSON")
	assert_eq(ActLog.new().to_json(), '{"seq":0,"acts":[]}', "empty log JSON")


func test_json_round_trip() -> void:
	var log := ActLog.new()
	log.append({"a": "smove", "pid": "p1", "sid": "0:1", "pts": [[1000, 2000], [-1500, 2500]]})
	log.append({"a": "atk", "pid": "p2", "x": -7, "dice": [6, 1, 3], "flag": true, "big": 4503599627370496})
	log.append({"a": "done", "pid": 3, "d": {"k": [{"q": 1}]}})
	var copy := ActLog.new()
	assert_true(copy.from_json(log.to_json()), "from_json accepts to_json output")
	assert_eq(copy.to_json(), log.to_json(), "JSON survives the round trip")
	assert_eq(copy.snapshot(), log.snapshot(), "snapshots are equal")
	var a2 := copy.at(2)
	assert_eq(typeof(a2["x"]), TYPE_INT, "numbers come back as ints, not floats")
	assert_eq(typeof(a2["dice"][0]), TYPE_INT, "array numbers come back as ints")
	assert_eq(a2["big"], 4503599627370496, "2^52 survives exactly")
	assert_eq(typeof(copy.at(3)["pid"]), TYPE_INT, "an int pid stays an int")
	assert_eq(typeof(a2["flag"]), TYPE_BOOL, "bools stay bools")
	var before := copy.to_json()
	assert_false(copy.from_json('{"seq":1,"acts":[{"seq":1,"pid":1,"a":"x","v":1.5}]}'), "a non-integral number is refused")
	assert_eq(copy.error, "bad_value", "error names the value")
	assert_false(copy.from_json("not json"), "garbage is refused")
	assert_eq(copy.error, "bad_json", "error names the JSON")
	assert_false(copy.from_json('{"seq":2,"acts":[{"seq":1,"pid":1,"a":"x"}]}'), "a seq that disagrees with the acts is refused")
	assert_false(copy.from_json('{"seq":1,"acts":[{"seq":2,"pid":1,"a":"x"}]}'), "an act with a gap in seq is refused")
	assert_false(copy.from_json('[1,2]'), "a non-object document is refused")
	assert_eq(copy.to_json(), before, "a refused document leaves the log unchanged")


func test_snapshot_restore() -> void:
	var log := ActLog.new()
	log.append({"a": "nop", "pid": "p1", "pts": [[1, 2]]})
	log.append({"a": "nop", "pid": "p2"})
	var snap := log.snapshot()
	assert_eq(snap["seq"], 2, "snapshot seq")
	snap["acts"][0]["pts"][0][0] = 99
	assert_eq(log.at(1)["pts"][0][0], 1, "snapshot is a deep copy")
	var other := ActLog.new()
	assert_true(other.restore(log.snapshot()), "restore accepts a snapshot")
	assert_eq(other.to_json(), log.to_json(), "restored log equals the original")
	assert_eq(other.append({"a": "nop", "pid": "p3"}), 3, "appending continues after restore")
	assert_false(other.restore({"seq": 1, "acts": [{"a": "nop"}]}), "a snapshot with a bad act is refused")
	assert_eq(other.error, "bad_pid", "error from the bad act")
	assert_eq(other.size(), 3, "a refused restore leaves the log unchanged")
	assert_false(other.restore({"acts": "nope"}), "acts must be an array")
	assert_false(other.restore({}), "an empty dictionary is refused")
	other.clear()
	assert_eq(other.size(), 0, "clear empties the log")
	assert_eq(other.append({"a": "nop", "pid": 1}), 1, "seq restarts at 1 after clear")
	var acts := log.acts()
	acts[0]["pid"] = "zzz"
	assert_eq(log.at(1)["pid"], "p1", "acts() returns copies")
