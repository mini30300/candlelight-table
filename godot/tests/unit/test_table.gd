extends "res://tests/testing.gd"
## core/table.gd: the base table validates and logs acts, emits events, advances with a guard, digests its
## state ints and survives snapshot/restore; a subclass proves the override hooks.


## A tiny rules set on top of Table: "inc" adds to a counter, "run" makes advance() step n times.
class Counter extends Table:
	var count: int = 0
	var steps: int = 0
	var target: int = 0

	func codes() -> PackedStringArray:
		return PackedStringArray(["nop", "inc", "run"])

	func _on_act(act: Dictionary) -> Array[Dictionary]:
		var a := String(act["a"])
		if a == "inc":
			count += int(act.get("n", 1))
			var out: Array[Dictionary] = [Events.make(Events.Id.LOG_LINE, {"key": "inc", "args": [count]})]
			return out
		if a == "run":
			target = steps + int(act.get("n", 0))
			var none: Array[Dictionary] = []
			return none
		return super(act)

	func _advance_step(out: Array[Dictionary]) -> bool:
		if steps >= target:
			return false
		steps += 1
		out.append(Events.make(Events.Id.PHASE, {"ph": steps}))
		return true

	func state_ints() -> PackedInt64Array:
		var v := super()
		v.append(count)
		v.append(steps)
		return v


func _ids(evs: Array[Dictionary]) -> Array:
	var out: Array = []
	for e: Dictionary in evs:
		out.append(Events.name_of(Events.id_of(e)))
	return out


func test_version_constants() -> void:
	assert_eq(Version.RULES_V, 10, "rules version 10")
	assert_eq(Version.PROTO, "bt", "protocol name")
	assert_true(Version.APP_VER.length() > 0, "APP_VER is set: " + Version.APP_VER)
	assert_eq(typeof(Version.DATA_HASH), TYPE_STRING, "DATA_HASH is a string (empty until the data lint fills it)")
	assert_eq(Table.new().rules_v, Version.RULES_V, "a table carries the rules version")


func test_apply_nop() -> void:
	var t := Table.new(7)
	assert_eq(t.seed, 7, "seed from the constructor")
	var d0 := t.digest()
	assert_eq(d0.length(), 16, "digest is 16 hex characters")
	var evs := t.apply({"a": "nop", "pid": "p1"})
	assert_eq(_ids(evs), ["LOG_LINE"], "nop emits one log line")
	assert_eq(evs[0]["key"], "nop", "log line key")
	assert_eq(evs[0]["args"], [1], "log line carries the seq")
	assert_eq(t.actlog.size(), 1, "the act was logged")
	assert_eq(t.actlog.at(1)["seq"], 1, "with seq 1")
	assert_eq(t.applied, 1, "applied counts")
	assert_eq(t.last_error, "", "no error")
	assert_ne(t.digest(), d0, "the digest changes after an act")
	assert_eq(Events.name_of(Events.Id.DESYNC), "DESYNC", "event names resolve")
	assert_eq(Events.name_of(99), "?", "unknown event id")
	assert_eq(Events.make(Events.Id.OVER, {"result": 1, "e": 5}), {"e": int(Events.Id.OVER), "result": 1}, "make() reserves the e key")


func test_rejects_bad_acts() -> void:
	var t := Table.new(1)
	var evs := t.apply({"a": "fly", "pid": "p1"})
	assert_eq(_ids(evs), ["BAD_ACT"], "an unknown code gives BAD_ACT")
	assert_eq(evs[0]["key"], "bad_code", "key bad_code")
	assert_eq(evs[0]["seq"], 1, "the seq the table wanted")
	assert_eq(evs[0]["a"], "fly", "the offending code")
	assert_eq(t.last_error, "bad_code", "last_error is set")
	assert_eq(t.actlog.size(), 0, "nothing logged")
	evs = t.apply({"a": "nop"})
	assert_eq(evs[0]["key"], "bad_pid", "missing pid")
	evs = t.apply({"a": 5, "pid": 1})
	assert_eq(evs[0]["key"], "bad_a", "non-string code")
	evs = t.apply({"a": "nop", "pid": 1, "seq": 4})
	assert_eq(evs[0]["key"], "bad_seq", "wrong seq")
	evs = t.apply({"a": "nop", "pid": 1, "x": 1.5})
	assert_eq(evs[0]["key"], "bad_value", "decimal payload")
	assert_eq(t.applied, 0, "nothing applied")
	assert_eq(t.apply({"a": "nop", "pid": 1, "seq": 1})[0]["key"], "nop", "the right seq is accepted afterwards")
	assert_eq(t.last_error, "", "last_error clears on success")


func test_digest_is_deterministic() -> void:
	var a := Table.new(42)
	var b := Table.new(42)
	var c := Table.new(43)
	for i: int in 3:
		a.apply({"a": "nop", "pid": "p%d" % i})
		b.apply({"a": "nop", "pid": "p%d" % i})
		c.apply({"a": "nop", "pid": "p%d" % i})
	assert_eq(a.digest(), b.digest(), "same seed and acts give the same digest")
	assert_ne(a.digest(), c.digest(), "another seed gives another digest")
	assert_eq(Array(a.state_ints()), [10, 42, 3, 3, 0, 0, 0, 0], "state ints: rules_v, seed, seq, applied, turn, round, phase, over")
	assert_eq(a.digest(), Hash.digest_hex(a.state_ints()), "digest is the FNV-1a 64 of the state ints")


func test_snapshot_restore() -> void:
	var a := Table.new(5)
	for i: int in 3:
		a.apply({"a": "nop", "pid": i})
	a.turn = 2
	a.round_no = 1
	a.phase = 3
	var snap := a.snapshot()
	assert_eq(snap["log"]["seq"], 3, "snapshot carries the act log")
	assert_eq(snap["round"], 1, "snapshot carries the round")
	var b := Table.new()
	assert_true(b.restore(snap), "restore accepts the snapshot")
	assert_eq(b.digest(), a.digest(), "restored table has the same digest")
	assert_eq(b.seed, 5, "restored seed")
	assert_eq(b.turn, 2, "restored turn")
	assert_eq(b.phase, 3, "restored phase")
	var ea := a.apply({"a": "nop", "pid": "x"})
	var eb := b.apply({"a": "nop", "pid": "x"})
	assert_eq(ea, eb, "both continue with the same events")
	assert_eq(b.actlog.last_seq(), 4, "seq continues after restore")
	assert_eq(b.digest(), a.digest(), "digests stay equal after the next act")
	var bad := snap.duplicate(true)
	bad["v"] = 9
	assert_false(b.restore(bad), "another rules version is refused")
	assert_eq(b.last_error, "bad_version", "error names the version")
	assert_false(b.restore({"seed": 1}), "an incomplete snapshot is refused")
	assert_eq(b.last_error, "bad_snapshot", "error names the snapshot")
	assert_eq(b.actlog.last_seq(), 4, "a refused restore leaves the table unchanged")


func test_replay() -> void:
	var a := Table.new(3)
	var acts: Array = [{"a": "nop", "pid": 1}, {"a": "nop", "pid": 2}, {"a": "bad", "pid": 1}, {"a": "nop", "pid": 1}]
	assert_eq(a.replay(acts), 2, "replay stops at the first bad act")
	assert_eq(a.last_error, "bad_code", "and reports it")
	assert_eq(a.actlog.last_seq(), 2, "two acts logged")
	var b := Table.new(3)
	assert_eq(b.replay(b.actlog.acts()), 0, "replaying nothing applies nothing")
	assert_eq(b.replay(a.actlog.acts()), 2, "replaying a log with seq numbers works")
	assert_eq(b.digest(), a.digest(), "replay reproduces the digest")
	assert_eq(b.replay([7]), 0, "a non-dictionary stops the replay")
	assert_eq(b.last_error, "bad_act", "and is reported")


func test_subclass_hooks_and_advance_guard() -> void:
	var t := Counter.new(1)
	var fresh := Counter.new(1)
	assert_eq(_ids(t.apply({"a": "inc", "pid": 1, "n": 5})), ["LOG_LINE"], "inc emits its log line")
	assert_eq(t.count, 5, "inc added 5")
	assert_ne(t.digest(), fresh.digest(), "the subclass state ints change the digest")
	assert_eq(t.state_ints().size(), 10, "subclass appends two ints")
	var evs := t.apply({"a": "run", "pid": 1, "n": 3})
	assert_eq(_ids(evs), ["PHASE", "PHASE", "PHASE"], "advance() steps three times after run 3")
	assert_eq(evs[2]["ph"], 3, "steps are numbered")
	assert_eq(t.steps, 3, "three steps taken")
	assert_eq(t.advance(), [], "advance() is idle once nothing changes")
	evs = t.apply({"a": "run", "pid": 1, "n": 1000})
	assert_eq(evs.size(), Table.ADVANCE_GUARD + 1, "the guard stops advance() after 60 steps and logs it")
	assert_eq(_ids(evs).back(), "LOG_LINE", "the last event is the guard log line")
	assert_eq(evs.back()["key"], "advance_guard", "guard key")
	assert_eq(t.steps, 3 + Table.ADVANCE_GUARD, "exactly 60 more steps")
	var u := Counter.new(1)
	assert_eq(u.replay(t.actlog.acts()), 3, "a fresh subclass table replays the log")
	assert_eq(u.digest(), t.digest(), "and reaches the same digest")
	var more := t.advance()
	assert_eq(more.size(), Table.ADVANCE_GUARD + 1, "a later advance() continues (the guard is per call)")
	assert_ne(u.digest(), t.digest(), "an extra advance() call is state that a replay cannot see")
	assert_eq(_ids(t.apply({"a": "nop", "pid": 1}))[0], "LOG_LINE", "the base nop still works through super()")
	assert_eq(t.apply({"a": "fly", "pid": 1})[0]["key"], "bad_code", "codes() of the subclass gate the acts")
