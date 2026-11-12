extends "res://tests/testing.gd"
## SeatPlan (LOBBY_SPEC §3.1, §7.4): the setup panel's choices to the exact Battle.make setup and typed seats.
## Modes, team-major seats, one human at most, auto lists within the team budget, reproducible random armies, every
## validation code, table widths, rounds clamping, and never a "d" key. Pure (no display).


func _choice(teams: int, per: int, size: String, humans: Array = [], facs: Array = []) -> Dictionary:
	var c := SeatPlan.defaults(4242)
	c["teams"] = teams
	c["per_team"] = per
	c["size"] = size
	var seats: Array = []
	for k in teams * per:
		seats.append({"fac": str(facs[k]) if k < facs.size() else "", "human": humans.has(k)})
	c["seats"] = seats
	return c


func test_defaults_follow_the_spec() -> void:
	var c := SeatPlan.defaults(7)
	assert_eq([int(c["teams"]), int(c["per_team"]), str(c["size"]), str(c["theme"]), str(c["terrain"]), str(c["goal"]),
		int(c["rounds"]), int(c["budget"])], [2, 1, "m", "ruin", "hills", "obj", 5, 500], "defaults: 2 x 1, medium, ruin, hills, obj 5, 500")
	var seats: Array = c["seats"]
	assert_eq(seats.size(), 2, "defaults: two seats")
	assert_true(bool(seats[0]["human"]) and str(seats[0]["fac"]) == GameData.factions()[0], "defaults: seat 0 is you with the first army")
	assert_true(not bool(seats[1]["human"]) and str(seats[1]["fac"]) == "", "defaults: seat 1 is a bot with a random army")
	assert_eq(SeatPlan.validate(c), PackedStringArray(), "defaults are valid")


func test_modes_and_team_major_seats() -> void:
	var cases := [[2, 1, "s", "pvp"], [3, 1, "m", "ffa"], [4, 1, "m", "ffa"], [2, 2, "m", "team"], [3, 2, "l", "team"]]
	for cs in cases:
		var plan := SeatPlan.build(_choice(cs[0], cs[1], cs[2]))
		var setup: Dictionary = plan["setup"]
		var tag := "%dx%d" % [cs[0], cs[1]]
		assert_eq(PackedStringArray(plan["errors"]), PackedStringArray(), tag + ": valid")
		assert_eq(str(setup["mode"]), str(cs[3]), tag + ": mode " + str(cs[3]))
		assert_eq([int(setup["teams"]), int(setup["perTeam"])], [cs[0], cs[1]], tag + ": teams and perTeam")
		var seats: Array = plan["seats"]
		assert_eq(seats.size(), cs[0] * cs[1], tag + ": one seat per place")
		assert_eq(seats.get_typed_builtin(), TYPE_DICTIONARY, tag + ": seats is a typed Array[Dictionary]")
		var teams := []
		for k in seats.size():
			teams.append(int(seats[k]["team"]))
		var want := []
		for k in seats.size():
			want.append(k / int(cs[1]))
		assert_eq(teams, want, tag + ": team-major order (seat k in team k / per_team)")
		assert_false(setup.has("d"), tag + ": no depth key (Battle and TableView use depth_for)")
		var w := int(setup["w"])
		assert_true(w % 2 == 0 and w >= 24 and w <= 120, tag + ": table width %d is even and inside 24..120" % w)


func test_lists_are_full_and_within_the_budget() -> void:
	for cs in [[2, 1, "s", 300], [2, 1, "m", 500], [3, 2, "l", 1000], [4, 1, "m", 1500], [2, 2, "m", 500]]:
		var c := _choice(cs[0], cs[1], cs[2], [0])
		c["budget"] = cs[3]
		var plan := SeatPlan.build(c)
		var st := BattleState.make(plan["setup"])
		for sd: Dictionary in plan["seats"]:
			var p := st.add_seat(int(sd["team"]), "", bool(sd["bot"]), false, "")
			p.list = sd["list"]
		var share := BtArmy.share_of(st)
		var tag := "%dx%d %d pts" % [cs[0], cs[1], cs[3]]
		var over := []
		var empty := []
		for k in st.seats.size():
			if not BtArmy.has_units(st, k):
				empty.append(k)
			if BtArmy.pts_of(st, k) > share:
				over.append("seat %d: %d > %d" % [k, BtArmy.pts_of(st, k), share])
			assert_eq((plan["seats"][k]["list"] as PackedInt32Array).size(), GameData.count(), tag + ": seat %d list is in TYPES order" % k)
		assert_eq(empty, [], tag + ": every seat has an army list")
		assert_eq(over, [], tag + ": every list fits the share of the team budget")


func test_human_seat_and_armies() -> void:
	var plan := SeatPlan.build(_choice(2, 2, "m", [2], ["kn", "or", "gr", ""]))
	assert_eq(int(plan["human"]), 2, "the human seat index comes back")
	var bots := []
	var facs := []
	for sd: Dictionary in plan["seats"]:
		bots.append(bool(sd["bot"]))
		facs.append(str(sd["fac"]))
		assert_eq(str(sd["pid"]), "", "pid is empty (the human gets L<seat> at start)")
	assert_eq(bots, [true, true, false, true], "only the human seat is not a bot")
	assert_eq(facs.slice(0, 3), ["kn", "or", "gr"], "chosen armies are kept")
	assert_true(GameData.factions().has(str(facs[3])), "a random army is one of the 15 (%s)" % str(facs[3]))
	var watch := SeatPlan.build(_choice(2, 1, "s"))
	assert_eq(int(watch["human"]), -1, "no human seat: watch the bots (-1)")
	var b := Battle.make(plan["setup"], plan["seats"], {})
	b.start()
	assert_eq(b.last_error, "", "Battle.make + start take the plan as it is")
	assert_eq(b.st.seats[2].pid, "L2", "the human seat gets pid L2 at start")
	for k in 4:
		assert_eq(b.st.seats[k].fac, str(facs[k]), "seat %d plays its army" % k)
	assert_true(b.st.units.size() > 0, "the armies are deployed")


func test_random_armies_are_reproducible() -> void:
	var a := []
	var c := []
	for k in 6:
		a.append(SeatPlan.random_fac(k, 4242))
		c.append(SeatPlan.random_fac(k, 4242))
	assert_eq(a, c, "the same seed picks the same random armies")
	var p1 := SeatPlan.build(_choice(3, 2, "l"))
	var p2 := SeatPlan.build(_choice(3, 2, "l"))
	var l1 := []
	var l2 := []
	for k in 6:
		l1.append([p1["seats"][k]["fac"], p1["seats"][k]["list"]])
		l2.append([p2["seats"][k]["fac"], p2["seats"][k]["list"]])
	assert_eq(l1, l2, "the same choice builds the same armies and lists")
	var seen := {}
	for s in range(1, 40):
		seen[SeatPlan.random_fac(0, s)] = true
	assert_true(seen.size() >= 8, "random armies vary with the seed (%d of 15 seen)" % seen.size())


func test_every_validation_code() -> void:
	var cases := {
		"humans": _choice(2, 1, "m", [0, 1]),
		"seats": _choice(4, 2, "l"),
		"teams": _choice(5, 1, "l"),
		"per_team": _choice(2, 3, "l"),
		"small": _choice(3, 2, "m"),
		"army": _choice(2, 1, "m", [], ["kn", "no_such_army"]),
	}
	var bad_theme := _choice(2, 1, "m")
	bad_theme["theme"] = "moon"
	cases["theme"] = bad_theme
	var bad_terrain := _choice(2, 1, "m")
	bad_terrain["terrain"] = "lava"
	cases["terrain"] = bad_terrain
	var bad_goal := _choice(2, 1, "m")
	bad_goal["goal"] = "race"
	cases["goal"] = bad_goal
	var bad_budget := _choice(2, 1, "m")
	bad_budget["budget"] = 0
	cases["budget"] = bad_budget
	for code in cases:
		var errs := SeatPlan.validate(cases[code])
		assert_true(errs.has(code), "%s: validate returns it (%s)" % [code, str(errs)])
		assert_true(PackedStringArray(SeatPlan.build(cases[code])["errors"]).has(code), code + ": build carries it")
		var text := SeatPlan.error_text(code, cases[code])
		assert_true(text != code and text != "", code + ": has a message")
	assert_true(SeatPlan.validate(_choice(3, 2, "l")).is_empty(), "6 seats fit the large table")
	assert_true(SeatPlan.validate(_choice(2, 1, "s")).is_empty(), "2 seats fit the small table")
	assert_eq(SeatPlan.size_for(3), "m", "3 seats need the medium table")
	assert_eq(SeatPlan.size_for(6), "l", "6 seats need the large table")
	var was := I18n.english
	I18n.english = false
	var small := SeatPlan.error_text("small", _choice(3, 2, "m"))
	I18n.english = was
	assert_true(small.contains("6") and small.contains(SeatPlan.SIZE_NAMES["l"]), "the size message names the seats and the size (%s)" % small)


func test_rounds_and_goal() -> void:
	var c := _choice(2, 1, "m")
	c["rounds"] = 1
	assert_eq(int(SeatPlan.build(c)["setup"]["rounds"]), 3, "rounds below 3 clamp to 3")
	c["rounds"] = 99
	assert_eq(int(SeatPlan.build(c)["setup"]["rounds"]), 10, "rounds above 10 clamp to 10")
	c["goal"] = "kill"
	var kill: Dictionary = SeatPlan.build(c)["setup"]
	assert_eq(str(kill["goal"]), "kill", "fight to the last team")
	assert_false(kill.has("rounds"), "a kill game sends no rounds (it always allows 30)")
	assert_eq(BattleState.make(kill).max_round(), BattleState.KILL_ROUNDS, "a kill game allows 30 rounds")
	var seeded := SeatPlan.with_seed(c, 123456)
	assert_eq(int(seeded["seed"]), 99999, "seeds clamp to 1..99999")
	assert_eq(int(c["seed"]), 4242, "with_seed leaves the original choice alone")


func test_fit_seats() -> void:
	var c := _choice(2, 1, "m", [0])
	c["teams"] = 3
	c["per_team"] = 2
	SeatPlan.fit_seats(c)
	assert_eq((c["seats"] as Array).size(), 6, "fit_seats grows the seat list")
	assert_true(bool(c["seats"][0]["human"]) and not bool(c["seats"][5]["human"]), "new seats are bots")
	c["teams"] = 2
	c["per_team"] = 1
	SeatPlan.fit_seats(c)
	assert_eq((c["seats"] as Array).size(), 2, "fit_seats shrinks the seat list")
