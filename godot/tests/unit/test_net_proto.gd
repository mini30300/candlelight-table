extends "res://tests/testing.gd"
## NetProto (NET_SPEC §2): every kind round-trips with a valid body, ints stay ints, PackedInt32Array survives, acts
## equal after ActLog.canon; floats, objects, oversize buffers (refused before decoding), unknown kinds, bad types,
## out-of-range ints, long strings, deep nesting and too many items are refused; extra keys are dropped; clean_name.

const DG := "0123456789abcdef"


func _act() -> Dictionary:
	return ActLog.canon({"pid": "n1", "a": "shoot", "u": "s1", "t": "s9", "how": "bolt", "hit": [6, 5, 1],
		"wound": [4], "save": []}, 3)


func _plan() -> Dictionary:
	var plan := SeatPlan.build(SeatPlan.defaults(7))
	var seats: Array = []
	for sd: Dictionary in plan["seats"]:
		seats.append(sd)
	return {"setup": plan["setup"], "seats": seats}


func _members() -> Array:
	return [{"slot": 0, "nm": "เจ้าห้อง", "where": "deck", "pick": "", "here": true},
		{"slot": 1, "nm": "เพื่อน", "where": "battle", "pick": "", "here": false}]


## one valid body per kind of §2.2
func _bodies() -> Dictionary:
	return {
		NetProto.HELLO: {"g": "candlelight", "np": 1, "app": Version.APP_VER, "rules": Version.RULES_V,
			"data": Version.DATA_HASH, "nm": "เพื่อน", "nid": "00112233aabbccdd"},
		NetProto.WELCOME: {"slot": 1, "host_nm": "เจ้าห้อง", "room_st": "deck", "members": _members(), "np": 1},
		NetProto.REFUSE: {"key": "wrong_app", "args": {"host": "a", "mine": "b"}},
		NetProto.MEMBERS: {"list": _members(), "room_st": "setup", "gen": 7},
		NetProto.WHERE: {"where": "arena"},
		NetProto.PICK: {"fac": ""},
		NetProto.POSE: {"x": -120, "z": 4999, "yaw": -3141, "sp": 350, "run": true, "t": 123456},
		NetProto.POSE_STOP: {"x": 5, "z": -5, "yaw": 0, "sp": 0, "run": false, "t": 9, "s": 3},
		NetProto.HB: {"seq": 12, "dg": DG, "gen": 2},
		NetProto.BYE: {"key": "leave"},
		NetProto.SETUP: {"open": true, "seats": [{"team": 0, "owner": 0, "fac": "greek"}, {"team": 1, "owner": -1, "fac": ""}]},
		NetProto.CLAIM: {"k": -1},
		NetProto.START: {"gen": 2, "plan": _plan(), "owners": [0, -1]},
		NetProto.ACT_REQ: {"gen": 2, "base": 2, "act": {"pid": "n1", "a": "smove", "u": "s1", "how": "move",
			"to": [[1000, 2000], [3000, -4000]], "x": 3000, "z": -4000}},
		NetProto.ACT: {"gen": 2, "seq": 3, "act": _act(), "dg": DG},
		NetProto.ACT_NO: {"gen": 2, "base": 4, "key": "stale"},
		NetProto.RESEND: {"gen": 2, "from": 4},
		NetProto.RESYNC_REQ: {"gen": 2, "why": "rejoin"},
		NetProto.RESYNC: {"gen": 2, "plan": _plan(), "owners": [0, 1], "acts": [_act()], "seq": 3, "dg": DG},
		NetProto.SEAT: {"gen": 2, "k": 1, "on": "gone"},
		NetProto.DESYNC: {"gen": 2, "seq": 8, "dg": DG, "n": 1},
		NetProto.INTS_REQ: {"gen": 2},
		NetProto.INTS: {"gen": 2, "seq": 8, "ints": PackedInt64Array([1, -2, 9007199254740993])},
		NetProto.END: {"gen": 2, "why": "host_left_battle"},
		NetProto.LEAVE: {"gen": 2},
	}


func test_kinds_table() -> void:
	assert_eq(NetProto.VERSION, 1, "protocol version 1")
	var ids := {"HELLO": 1, "WELCOME": 2, "REFUSE": 3, "MEMBERS": 10, "WHERE": 11, "PICK": 12, "POSE": 13,
		"POSE_STOP": 14, "HB": 15, "BYE": 16, "SETUP": 20, "CLAIM": 21, "START": 22, "ACT_REQ": 23, "ACT": 24,
		"ACT_NO": 25, "RESEND": 26, "RESYNC_REQ": 27, "RESYNC": 28, "SEAT": 29, "DESYNC": 30, "INTS_REQ": 31,
		"INTS": 32, "END": 33, "LEAVE": 34}
	var bad := []
	for nm: String in ids:
		var consts: Dictionary = (NetProto as GDScript).get_script_constant_map()
		if consts.get(nm) != ids[nm] or NetProto.kind_name(ids[nm]) != nm or not NetProto.SCHEMAS.has(ids[nm]):
			bad.append(nm)
	assert_eq(bad, [], "every kind of §2.2 has its id, name and schema")
	# 25 since the review: LEAVE (a friend leaves the battle screen of game gen) replaces guessing from WHERE
	assert_eq(NetProto.NAMES.size(), 25, "25 kinds")
	assert_eq(NetProto.DIR[NetProto.LEAVE], "c", "LEAVE goes from a friend to the host")
	# what may arrive after authentication, checked on the kind byte and size before decoding
	assert_true(NetProto.from_member_ok(NetProto.ACT_REQ, 100) and NetProto.from_member_ok(NetProto.POSE, 40), "a member may send its kinds")
	assert_false(NetProto.from_member_ok(NetProto.RESYNC, 100), "a member may not send a host kind (RESYNC's 1 MiB cap is not its cap)")
	assert_false(NetProto.from_member_ok(NetProto.INTS, 100) or NetProto.from_member_ok(NetProto.HELLO, 100), "nor INTS, nor HELLO after authentication")
	assert_false(NetProto.from_member_ok(NetProto.ACT_REQ, NetProto.CAP + 1), "nothing over 64 KiB from a member")
	assert_true(NetProto.from_host_ok(NetProto.RESYNC) and NetProto.from_host_ok(NetProto.HB), "the host may send its kinds")
	assert_false(NetProto.from_host_ok(NetProto.ACT_REQ) or NetProto.from_host_ok(NetProto.WELCOME) or NetProto.from_host_ok(99), "not a member kind, not WELCOME, not unknown")
	assert_eq(NetProto.REFUSE_KEYS, NetGate.KEYS, "REFUSE keys are the gate's keys")


func test_round_trip_every_kind() -> void:
	var bodies := _bodies()
	assert_eq(bodies.size(), NetProto.NAMES.size(), "a body for every kind")
	for kind: int in bodies:
		var body: Dictionary = bodies[kind]
		var bytes := NetProto.encode(kind, body)
		assert_false(bytes.is_empty(), "%s encodes" % NetProto.kind_name(kind))
		assert_true(bytes.size() <= NetProto.cap_of(kind), "%s under its cap (%d bytes)" % [NetProto.kind_name(kind), bytes.size()])
		var m := NetProto.decode(bytes)
		assert_eq(m.get("kind"), kind, "%s decodes to its kind" % NetProto.kind_name(kind))
		assert_eq(m.get("body"), body, "%s body equal after the round trip" % NetProto.kind_name(kind))
	var start := NetProto.decode(NetProto.encode(NetProto.START, bodies[NetProto.START]))["body"] as Dictionary
	var l: Variant = start["plan"]["seats"][0]["list"]
	assert_eq(typeof(l), TYPE_PACKED_INT32_ARRAY, "a seat's army list stays a PackedInt32Array")
	assert_eq(typeof(start["gen"]), TYPE_INT, "ints stay int")
	var act := NetProto.decode(NetProto.encode(NetProto.ACT, bodies[NetProto.ACT]))["body"]["act"] as Dictionary
	assert_eq(act, ActLog.canon(act, 3), "an act equals its canonical form after the round trip")
	var pose := NetProto.encode(NetProto.POSE, bodies[NetProto.POSE])
	assert_true(pose.size() <= 96, "a pose is at most 96 bytes (%d)" % pose.size())
	var relayed: Dictionary = bodies[NetProto.POSE].duplicate()
	relayed["s"] = 5
	assert_true(NetProto.encode(NetProto.POSE, relayed).size() <= 96, "a relayed pose with s is at most 96 bytes")


func test_floats_refused() -> void:
	assert_true(NetProto.encode(NetProto.CLAIM, {"k": 1.0}).is_empty(), "a float field does not encode")
	var raw := PackedByteArray([NetProto.CLAIM])
	raw.append_array(var_to_bytes({"k": 1.0}))
	assert_true(NetProto.decode(raw).has("error"), "a float field does not decode")
	var act := {"pid": "n1", "a": "adv", "u": "s1", "roll": 3.5}
	assert_true(NetProto.encode(NetProto.ACT_REQ, {"gen": 1, "base": 0, "act": act}).is_empty(), "a float inside an act is refused")
	var deep := {"pid": "n1", "a": "smove", "u": "s1", "to": [[1, [2.0]]]}
	assert_true(NetProto.encode(NetProto.ACT_REQ, {"gen": 1, "base": 0, "act": deep}).is_empty(), "a nested float is refused")
	var raw2 := PackedByteArray([NetProto.POSE])
	raw2.append_array(var_to_bytes(PackedFloat64Array([1, 2, 3, 4, 0, 5, -1])))
	assert_true(NetProto.decode(raw2).has("error"), "a float pose array is refused")


func test_objects_refused() -> void:
	var raw := PackedByteArray([NetProto.WHERE])
	raw.append_array(var_to_bytes_with_objects({"where": RefCounted.new()}))
	assert_true(NetProto.decode(raw).has("error"), "an object payload is refused")
	var raw2 := PackedByteArray([NetProto.WHERE])
	raw2.append_array(var_to_bytes_with_objects(RefCounted.new()))
	assert_true(NetProto.decode(raw2).has("error"), "an object body is refused")


func test_oversize_refused_before_decoding() -> void:
	var big := PackedByteArray()
	big.resize(2 * 1024 * 1024)
	big[0] = NetProto.ACT
	var t0 := Time.get_ticks_usec()
	var m := NetProto.decode(big)
	var us := Time.get_ticks_usec() - t0
	assert_eq(m.get("error"), "size", "a 2 MiB buffer is refused for its size")
	assert_true(us < 20000, "refused without decoding it (%d us)" % us)
	big[0] = NetProto.RESYNC
	assert_eq(NetProto.decode(big).get("error"), "size", "RESYNC is capped at 1 MiB")
	var pose := PackedByteArray([NetProto.POSE])
	pose.resize(97)
	assert_eq(NetProto.decode(pose).get("error"), "size", "a 97-byte pose is refused")
	var long_name := "x".repeat(300)
	assert_true(NetProto.encode(NetProto.PICK, {"fac": long_name}).is_empty(), "a long string does not encode")


func test_bad_messages_refused() -> void:
	assert_eq(NetProto.decode(PackedByteArray()).get("error"), "short", "empty buffer")
	assert_eq(NetProto.decode(PackedByteArray([99, 0, 0, 0, 0])).get("error"), "kind", "unknown kind")
	assert_true(NetProto.encode(99, {}).is_empty(), "unknown kind does not encode")
	var junk := PackedByteArray([NetProto.WHERE, 1, 2, 3, 250, 251])
	assert_true(NetProto.decode(junk).has("error"), "junk bytes")
	var cases := [
		[NetProto.WHERE, {"where": "kitchen"}, "a where outside the list"],
		[NetProto.WHERE, {}, "a missing field"],
		[NetProto.CLAIM, {"k": 6}, "seat 6 is out of range"],
		[NetProto.CLAIM, {"k": "1"}, "a string where an int belongs"],
		[NetProto.POSE, {"x": 5001, "z": 0, "yaw": 0, "sp": 0, "run": false, "t": 0}, "x beyond 50 m"],
		[NetProto.POSE, {"x": 0, "z": 0, "yaw": 0, "sp": 2001, "run": false, "t": 0}, "speed beyond 20 m/s"],
		[NetProto.HB, {"seq": 1, "dg": "0123456789ABCDEF"}, "an upper-case digest"],
		[NetProto.HB, {"seq": 100001}, "seq beyond 100000"],
		[NetProto.ACT, {"gen": 70000, "seq": 1, "act": _act()}, "gen beyond 65535"],
		[NetProto.ACT, {"gen": 1, "seq": 1, "act": {"pid": "n1", "a": "fly"}}, "an unknown act code"],
		[NetProto.ACT, {"gen": 1, "seq": 1, "act": {"pid": "n1"}}, "an act without a"],
		[NetProto.ACT, {"gen": 1, "seq": 1, "act": {"pid": "n1", "a": "adv", "x": PackedInt32Array([1])}}, "a packed array inside an act"],
		[NetProto.SETUP, {"open": true, "seats": [{"team": 0, "owner": 9, "fac": ""}]}, "owner beyond slot 5"],
		[NetProto.BYE, {"key": "bored"}, "a BYE key outside the list"],
		[NetProto.MEMBERS, {"list": [{"slot": 0, "nm": "x".repeat(21), "where": "deck", "pick": "", "here": true}],
			"room_st": "deck", "gen": 0}, "a 21-character member name"],
	]
	for c: Array in cases:
		assert_true(NetProto.encode(c[0], c[1]).is_empty(), "refused: " + str(c[2]))
		var raw := PackedByteArray([c[0]])
		raw.append_array(var_to_bytes(c[1]))
		assert_true(NetProto.decode(raw).has("error"), "refused on decode: " + str(c[2]))


func test_deep_and_many_refused() -> void:
	var v: Variant = 1
	for i: int in 12:
		v = [v]
	var act := {"pid": "n1", "a": "smove", "u": "s1", "to": v}
	assert_true(NetProto.encode(NetProto.ACT_REQ, {"gen": 1, "base": 0, "act": act}).is_empty(), "nesting deeper than 8 is refused")
	var many: Array = []
	many.resize(4097)
	many.fill(1)
	var act2 := {"pid": "n1", "a": "smove", "u": "s1", "to": many}
	assert_true(NetProto.encode(NetProto.ACT_REQ, {"gen": 1, "base": 0, "act": act2}).is_empty(), "an array over 4096 items is refused")
	var seats: Array = []
	for i: int in 7:
		seats.append({"team": 0, "owner": -1, "fac": ""})
	assert_true(NetProto.encode(NetProto.SETUP, {"open": true, "seats": seats}).is_empty(), "seven SETUP seats are refused")
	var acts: Array = []
	acts.resize(6001)
	acts.fill(_act())
	var body := {"gen": 1, "plan": _plan(), "owners": [0, 1], "acts": acts, "seq": 6001, "dg": DG}
	assert_true(NetProto.encode(NetProto.RESYNC, body).is_empty(), "a RESYNC over 6000 acts is refused")
	var many_acts: Array = []
	for i: int in 750:
		many_acts.append(ActLog.canon({"pid": "n%d" % (i % 4), "a": "shoot", "u": "s%d" % (i % 40), "t": "s%d" % (i % 37),
			"how": "rifle", "hit": [6, 5, 4, 3, 2, 1], "wound": [5, 4, 3], "save": [2, 1]}, i + 1))
	var full := {"gen": 1, "plan": _plan(), "owners": [0, 1], "acts": many_acts, "seq": 750, "dg": DG}
	var bytes := NetProto.encode(NetProto.RESYNC, full)
	assert_false(bytes.is_empty(), "a 750-act RESYNC encodes (%d bytes)" % bytes.size())
	assert_eq(NetProto.decode(bytes).get("body", {}).get("acts", []).size(), 750, "and decodes")


func test_extra_keys_dropped() -> void:
	var raw := PackedByteArray([NetProto.WHERE])
	raw.append_array(var_to_bytes({"where": "deck", "evil": "rm -rf", "x": [1, 2]}))
	assert_eq(NetProto.decode(raw).get("body"), {"where": "deck"}, "extra keys are dropped")
	var seat := {"team": 0, "owner": 0, "fac": "", "secret": 1}
	var m := NetProto.decode(NetProto.encode(NetProto.SETUP, {"open": false, "seats": [seat], "more": 1}))
	assert_eq(m.get("body"), {"open": false, "seats": [{"team": 0, "owner": 0, "fac": ""}]}, "nested extra keys are dropped too")


func test_clean_name() -> void:
	assert_eq(NetProto.clean_name("  สมชาย  "), "สมชาย", "trimmed")
	assert_eq(NetProto.clean_name("a\nb\tc\u0007d"), "a b cd", "newlines and tabs become one space, control characters go")
	assert_eq(NetProto.clean_name("a     b"), "a b", "spaces collapse")
	assert_eq(NetProto.clean_name("x".repeat(40)), "x".repeat(20), "40 characters become 20")
	assert_eq(NetProto.clean_name(""), "", "empty stays empty")
	assert_eq(NetProto.clean_name(" \n\t "), "", "only spaces is empty")
	assert_eq(NetProto.clean_name("a\u202Eb\u200Bc"), "abc", "direction overrides and zero-width characters go")
	assert_eq(NetProto.clean_name("[b]bold[/b]"), "[b]bold[/b]", "plain text kept as typed (shown in Labels only)")
	assert_eq(NetProto.clean_name("a{max}b{name}"), "amaxbname", "braces go (names are put into String.format templates)")
	assert_true(NetProto.is_hex("00ff", 4) and not NetProto.is_hex("00FF", 4) and not NetProto.is_hex("0f", 4), "is_hex")
