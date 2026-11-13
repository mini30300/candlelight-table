extends "res://tests/testing.gd"
## NetSeats (NET_SPEC §5.1, §12.2): defaults for 1–6 members (5–6 members: 3 teams × 2, since §5.1's 4 × 2 would be
## 8 seats, over SeatPlan.MAX_SEATS); the owner button order (bot → you → friends not yet
## seated → bot); seat claims (a bot seat is taken and the previous seat freed; someone else's seat, the host's seat or an
## out-of-range k is ignored; −1 frees); member_twice and member_gone; build gives bot = false, pid "n<slot>" and the
## member's name for owned seats, "" for bots, the same army lists as SeatPlan.build for the same seed, owners per seat.

func _members(n: int) -> Array:
	var out: Array = []
	for s in n:
		out.append({"slot": s, "nm": "ผู้เล่น%d" % s, "where": &"deck", "pick": "", "here": true})
	return out


func test_defaults_for_one_to_six_members() -> void:
	var want := {1: [2, 1], 2: [2, 1], 3: [3, 1], 4: [4, 1], 5: [3, 2], 6: [3, 2]}
	for n in range(1, 7):
		var c := NetSeats.defaults(_members(n), 77)
		assert_eq([int(c["teams"]), int(c["per_team"])], want[n], "%d members → teams × per team" % n)
		var seats: Array = c["seats"]
		assert_eq(seats.size(), SeatPlan.seat_count(c), "%d members: one row per seat" % n)
		for k in seats.size():
			assert_eq(int(seats[k]["owner"]), k if k < n else -1, "%d members: seat %d owner" % [n, k])
		assert_eq(PackedStringArray(NetSeats.validate(c, _members(n))), PackedStringArray(), "%d members: the defaults are valid" % n)
	var m := _members(2)
	m[1]["pick"] = "eg"
	var c2 := NetSeats.defaults(m, 5)
	assert_eq(str(c2["seats"][1]["fac"]), "eg", "a member's wished army is used")
	assert_eq(str(c2["seats"][0]["fac"]), str(SeatPlan.defaults(5)["seats"][0]["fac"]), "otherwise the offline default")


func test_owner_cycle_order() -> void:
	var mem := _members(3)
	var c := NetSeats.defaults(_members(1), 3)   # 2 seats: you, bot
	NetSeats.fit(c)
	assert_eq(NetSeats.owner_of(c, 1), -1, "seat 1 starts as a bot")
	var seen: Array = []
	for i in 5:
		var nx := NetSeats.next_owner(c, 1, mem)
		NetSeats.set_owner(c, 1, nx)
		seen.append(nx)
	# seat 0 is "you" (slot 0): cycling seat 1 → you (moves you here) → friend 1 → friend 2 → bot → you
	assert_eq(seen, [0, 1, 2, -1, 0], "bot → you → each friend not yet seated → bot")
	NetSeats.set_owner(c, 0, 1)
	NetSeats.set_owner(c, 1, -1)
	assert_eq(NetSeats.next_owner(c, 1, mem), 0, "bot → you")
	NetSeats.set_owner(c, 1, 0)
	assert_eq(NetSeats.next_owner(c, 1, mem), 2, "friend 1 sits elsewhere: skipped")


func test_claims() -> void:
	var mem := _members(3)
	var c := NetSeats.defaults(_members(1), 3)
	c["teams"] = 2
	c["per_team"] = 2
	NetSeats.fit(c)   # seat 0 you, seats 1-3 bots
	assert_true(NetSeats.claim(c, 1, 2), "friend 1 claims bot seat 2")
	assert_eq(NetSeats.owner_of(c, 2), 1, "seat 2 is friend 1's")
	assert_true(NetSeats.claim(c, 1, 3), "friend 1 moves to seat 3")
	assert_eq([NetSeats.owner_of(c, 2), NetSeats.owner_of(c, 3)], [-1, 1], "the previous seat became a bot")
	assert_false(NetSeats.claim(c, 2, 3), "a seat owned by someone else is ignored")
	assert_false(NetSeats.claim(c, 2, 0), "the host's seat is ignored")
	assert_false(NetSeats.claim(c, 2, 4), "an out-of-range seat is ignored")
	assert_false(NetSeats.claim(c, 2, 9), "a far out-of-range seat is ignored")
	assert_false(NetSeats.claim(c, 0, 1), "the host does not claim (it uses the owner button)")
	assert_true(NetSeats.claim(c, 1, -1), "−1 frees friend 1's seat")
	assert_eq(NetSeats.owner_of(c, 3), -1, "seat 3 is a bot again")
	assert_false(NetSeats.claim(c, 1, -1), "−1 with no seat changes nothing")
	var body := NetSeats.seats_body(c)
	assert_eq(body.size(), 4, "SETUP lists 4 seats")
	assert_eq(body[2], {"team": 1, "owner": -1, "fac": str(c["seats"][2]["fac"])}, "a SETUP seat is {team, owner, fac}")
	assert_true(not NetProto.encode(NetProto.SETUP, {"open": true, "seats": body}).is_empty(), "the SETUP body passes the codec")


func test_validate_member_errors() -> void:
	var c := NetSeats.defaults(_members(3), 9)
	c["seats"][2]["owner"] = 1
	assert_true(NetSeats.validate(c, _members(3)).has("member_twice"), "a member on two seats → member_twice")
	c["seats"][2]["owner"] = 2
	assert_true(NetSeats.validate(c, _members(2)).has("member_gone"), "an owner no longer in the room → member_gone")
	assert_true(NetSeats.drop_gone(c, _members(2)), "drop_gone turns the gone member's seat into a bot")
	assert_eq(NetSeats.owner_of(c, 2), -1, "seat 2 is a bot")
	assert_eq(PackedStringArray(NetSeats.validate(c, _members(2))), PackedStringArray(), "valid again")
	assert_false(NetSeats.validate(c, _members(2)).has("humans"), "several members are not SeatPlan's one-human error")
	assert_eq(NetSeats.error_text("member_twice", c), I18n.t("เพื่อนคนหนึ่งนั่งได้ที่เดียว"), "member_twice text")
	assert_eq(NetSeats.error_text("teams", c), SeatPlan.error_text("teams", c), "other codes use SeatPlan's text")


func test_build_plan() -> void:
	var mem := _members(3)
	var c := NetSeats.defaults(_members(3), 4242)   # 3 teams × 1: slots 0, 1, 2
	c["teams"] = 2
	c["per_team"] = 2
	NetSeats.fit(c)
	NetSeats.set_owner(c, 3, 2)
	NetSeats.set_owner(c, 2, -1)
	var plan := NetSeats.build(c, mem)
	assert_eq(PackedStringArray(plan["errors"]), PackedStringArray(), "the plan is valid")
	assert_eq(plan["owners"], [0, 1, -1, 2], "owners per seat")
	assert_eq(int(plan["human"]), 0, "the host sits at seat 0")
	var seats: Array = plan["seats"]
	assert_eq([seats[0]["bot"], seats[0]["pid"], seats[0]["nm"]], [false, "n0", "ผู้เล่น0"], "seat 0: the host")
	assert_eq([seats[1]["bot"], seats[1]["pid"], seats[1]["nm"]], [false, "n1", "ผู้เล่น1"], "seat 1: friend 1")
	assert_eq([seats[2]["bot"], seats[2]["pid"], seats[2]["nm"]], [true, "", ""], "seat 2: a bot")
	assert_eq([seats[3]["bot"], seats[3]["pid"], seats[3]["nm"]], [false, "n2", "ผู้เล่น2"], "seat 3: friend 2")
	assert_eq(NetSeats.pid_of(4), "n4", "pid_of")
	var off := c.duplicate(true)
	for sd: Dictionary in off["seats"]:
		sd["human"] = false
	var ref := SeatPlan.build(off)
	assert_eq(plan["setup"], ref["setup"], "the same setup as SeatPlan.build")
	for k in 4:
		assert_eq(seats[k]["list"], ref["seats"][k]["list"], "seat %d: the same army list as SeatPlan.build" % k)
		assert_eq(seats[k]["fac"], ref["seats"][k]["fac"], "seat %d: the same army as SeatPlan.build" % k)
	var start := {"gen": 1, "plan": Lockstep.plan_wire(plan), "owners": plan["owners"]}
	assert_true(not NetProto.encode(NetProto.START, start).is_empty(), "the START body passes the codec")
	var b := Battle.make(plan["setup"], _typed(seats), {})
	b.start()
	assert_eq([b.st.seats[0].pid, b.st.seats[1].pid, b.st.seats[2].pid, b.st.seats[3].pid], ["n0", "n1", "", "n2"],
		"start_match keeps the online pids (no local L<seat>)")


## Review: the host builds its runner from its in-memory plan, clients from the decoded START plan, and the codec drops
## setup keys it does not know. Every key SeatPlan.build puts in a setup must be one the codec keeps, and both plans
## must give the same game (digest after start).
func test_wire_plan_keeps_the_whole_setup() -> void:
	var known := {}
	for k: String in (NetProto as GDScript).get_script_constant_map()["_PLAN_SETUP"]:
		known[k.trim_prefix("?")] = true
	var bad := []
	for seed_v: int in [5, 77, 4242]:
		for goal: String in ["obj", "kill"]:
			var c := NetSeats.defaults(_members(3), seed_v)
			c["goal"] = goal
			var plan := NetSeats.build(c, _members(3))
			for k: String in plan["setup"]:
				if not known.has(k):
					bad.append(k)
			var m := NetProto.decode(NetProto.encode(NetProto.START, {"gen": 1, "plan": Lockstep.plan_wire(plan), "owners": plan["owners"]}))
			var wire: Dictionary = m["body"]["plan"]
			var a := Battle.make(plan["setup"], _typed(plan["seats"]), {})
			var b := Battle.make(wire["setup"], _typed(wire["seats"]), {})
			a.start()
			b.start()
			assert_digest(b.digest(), a.digest(), "seed %d %s: the decoded START plan gives the host's game" % [seed_v, goal])
	assert_eq(bad, [], "every setup key of SeatPlan.build survives the START codec")


func _typed(a: Array) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for d: Dictionary in a:
		out.append(d.duplicate(true))
	return out
