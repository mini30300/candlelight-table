extends "res://tests/testing.gd"
## core/battle/army.gd (BtArmy, R1_PORT_SPEC §1.5) against the page and by hand.
## Page samples: fixtures/army/page_samples.json, written by tools/record_army_objectives.js, which runs the page's own
## fitList / facOf / fitSkin / shareOf / baseCap / armyCap / slotMax / ptsOf / teamPts / hasUnits / mkPlayers / autoList /
## depCapacity / depSlots / depWhyNot / autoDep / deploy in Chromium. Its autoList draws from a PCG32 copy of core/rng.gd,
## so every port list must equal the page's algorithm exactly (with the two v10 SLOT_MAX guards patched in), and equal
## the unpatched page wherever no slot went past 99. Points compare to the 10 MI grid rounding of the page's doubles;
## samples whose page answer flips within the recorder's EPS are fragile (R1_PORT_SPEC §7 #2) and only counted.
## Hand cases: caps for 1..8 seats and spectator, the cheapest unit per army, the 99 cap at big budgets, hidden types
## never in a bot list, deploy ids / counts / facing / grid / no overlap, every dep_why_not key, auto_dep for 2/4/8 teams.

const FIX := "res://tests/unit/fixtures/army/page_samples.json"
## Digest of the fixed scenario in _digest_scenario (lists, deps, deployment); changes only on purpose.
const PINNED_DIGEST := "f19e7e6a74e4cade:9daf7e6b77b7af85"
var F: Dictionary = {}


func setup() -> void:
	var p: Variant = JSON.parse_string(FileAccess.get_file_as_string(FIX))
	if typeof(p) == TYPE_DICTIONARY:
		F = _iv(p)


# ---------------------------------------------------------------- helpers
## JSON numbers arrive as floats: whole ones become ints (deep); bools, strings and fractions stay as they are.
func _iv(v: Variant) -> Variant:
	match typeof(v):
		TYPE_FLOAT:
			var f: float = v
			return int(f) if f == floorf(f) and absf(f) < 1.0e18 else f
		TYPE_ARRAY:
			var out: Array = []
			for x: Variant in v:
				out.append(_iv(x))
			return out
		TYPE_DICTIONARY:
			var d := {}
			for k: Variant in v:
				d[k] = _iv(v[k])
			return d
	return v


## a packed raw list {n, v: [[i, value]]} back to the array the page got
func _raw(pk: Dictionary) -> Array:
	var out: Array = []
	out.resize(int(pk["n"]))
	out.fill(0)
	for e: Variant in pk["v"]:
		out[int(e[0])] = e[1]
	return out


## sparse [[i, n]] to a full list
func _list(sp: Array) -> PackedInt32Array:
	var out := PackedInt32Array()
	out.resize(GameData.count())
	for e: Variant in sp:
		out[int(e[0])] = int(e[1])
	return out


func _sparse(list: PackedInt32Array) -> Array:
	var out: Array = []
	for i: int in list.size():
		if list[i] != 0:
			out.append([i, list[i]])
	return out


func _max_slot(list: PackedInt32Array) -> int:
	var m := 0
	for v: int in list:
		m = maxi(m, v)
	return m


## a BattleState on a recorded field (props rebuilt as test_blocking does), seats [{team, list?, dep?, bot?}]
func _state(fname: String, setup: Dictionary, seats: Array) -> BattleState:
	var f: Dictionary = F["fields"][fname]
	var st := BattleState.make({"seed": f["seed"], "w": f["w"], "d": f["d"], "teams": setup["teams"],
		"perTeam": setup["perTeam"], "mode": setup["mode"], "budget": setup["budget"]})
	var items: Array[Dictionary] = []
	for r: Variant in f["props"]:
		items.append(BtBlocking.prep_one(str(r[0]), r[1], r[2], r[3], r[4], r[5], r[6], r[7]))
	st.set_props(items, true)
	for sv: Variant in seats:
		var s: Dictionary = sv
		var p := st.add_seat(int(s["team"]), "", bool(s.get("bot", false)), false, "")
		if s.has("list"):
			p.list = _list(s["list"])
		if s.get("dep") != null:
			var dp: Array = s["dep"]
			p.has_dep = true
			p.dep_x = dp[0]
			p.dep_z = dp[1]
	return st


func _plain(w: int, setup: Dictionary) -> BattleState:
	var s := {"seed": 7, "w": w, "teams": 2, "perTeam": 1, "mode": "pvp", "budget": 500}
	s.merge(setup, true)
	return BattleState.make(s)


## |port - page| within tol per axis (page values are MI doubles)
func _near(px: int, pz: int, qx: float, qz: float, tol: float) -> bool:
	return absf(float(px) - qx) <= tol + 0.000001 and absf(float(pz) - qz) <= tol + 0.000001


func _hidden_types() -> PackedInt64Array:
	var out := PackedInt64Array()
	for i: int in GameData.count():
		if GameData.is_hidden(GameData.key_at(i)):
			out.append(i)
	return out


# ---------------------------------------------------------------- page samples: lists, caps, points
func test_fixture_loaded() -> void:
	for k: String in ["fit_list", "fac_of", "auto_list", "deploy", "auto_dep", "dep_why_not", "dep_slots", "fields"]:
		assert_true(F.has(k), "fixture has " + k)
	var meta: Dictionary = F.get("meta", {})
	assert_eq(str(meta.get("app_ver", "")), "9.4", "fixture sampled from the 9.4 page")


func test_constants_match_data() -> void:
	var c: Dictionary = F["consts"]
	for k: String in ["SLOT_MAX", "SPEC_TOTAL", "DEP_FOE", "DEP_MATE", "OBJ_R", "VP_PER", "VP_CAP"]:
		assert_eq(GameData.const_int(k, -1), int(c[k]), "constants.json %s equals the page's" % k)
	# skins: the port's table, the page's SKINS and data/skins.json agree
	var raw: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://data/skins.json"))
	var file_n := {}
	if raw is Dictionary:
		for k: Variant in raw:
			file_n[str(k)] = (raw[k] as Array).size()
	var page_n := {}
	for e: Variant in F["skins"]:
		page_n[str(e[0])] = int(e[1])
	assert_eq(BtArmy.SKIN_N, file_n, "BtArmy.SKIN_N equals data/skins.json")
	assert_eq(BtArmy.SKIN_N, page_n, "and the page's SKINS")


func test_fit_list_matches_page() -> void:
	var bad: Array = []
	var cases: Array = F["fit_list"]
	for c: Variant in cases:
		var raw := _raw(c["raw"])
		var got := BtArmy.fit_list(raw)
		if got.size() != GameData.count() or _sparse(got) != c["out"]:
			bad.append([raw.size(), _sparse(got), c["out"]])
	assert_true(cases.size() >= 30, "%d fitList samples" % cases.size())
	assert_true(bad.is_empty(), "fit_list equals the page's fitList (length, clamps, |0 of big and negative ints, bools)", bad.slice(0, 3))


func test_fit_list_hand() -> void:
	var n := GameData.count()
	var hidden := _hidden_types()
	assert_eq(hidden.size(), 2, "the data has two hidden types")
	var raw: Array = []
	raw.resize(n + 5)
	raw.fill(250)
	var got := BtArmy.fit_list(raw)
	assert_eq(got.size(), n, "a long list is cut to the TYPES length")
	var ok := true
	for i: int in n:
		ok = ok and got[i] == (1 if hidden.has(i) else 99)
	assert_true(ok, "every slot is clamped to 99, a hidden type to 1")
	assert_eq(BtArmy.fit_list([]).size(), n, "an empty list gives the full length")
	assert_eq(_sparse(BtArmy.fit_list([3, -4, 0, 99, 100])), [[0, 3], [3, 99], [4, 99]], "a short list: negatives to 0, the rest zero")
	var r2: Array = [0, 0, 0, 0, 0, 0]
	r2[0] = true
	r2[1] = false
	r2[2] = "7"
	r2[3] = null
	r2[4] = [5]
	r2[5] = 4294967301
	assert_eq(_sparse(BtArmy.fit_list(r2)), [[0, 1], [5, 5]], "bools count 1/0, non-integers 0, ints wrap to 32 bits as |0")
	assert_eq(BtArmy.js_int(-1), -1, "js_int keeps small negatives")
	assert_eq(BtArmy.js_int(2147483648), -2147483648, "2^31 wraps to -2^31")
	assert_eq(BtArmy.js_int(-2147483649), 2147483647, "-2^31 - 1 wraps to 2^31 - 1")


func test_fac_of_matches_page() -> void:
	var bad: Array = []
	var cases: Array = F["fac_of"]
	for c: Variant in cases:
		var raw := _raw(c["raw"])
		var got := BtArmy.fac_of(BtArmy.fit_list(raw), str(c["dflt"]))
		if got != str(c["out"]):
			bad.append([c["dflt"], got, c["out"]])
	assert_true(cases.size() >= 40, "%d facOf samples (the page reads the raw list, the port the fitted one)" % cases.size())
	assert_true(bad.is_empty(), "fac_of equals the page's facOf", bad.slice(0, 3))


func test_fac_of_hand() -> void:
	var sec := -1
	var lk := -1
	for i: int in _hidden_types():
		var t := GameData.types()[i]
		if t.has("sec"):
			sec = i
		if t.has("lk"):
			lk = i
	assert_true(sec >= 0 and lk >= 0, "one hidden type of each mark (sec, lk)")
	var only_sec := PackedInt32Array()
	only_sec.resize(GameData.count())
	only_sec[sec] = 1
	assert_eq(BtArmy.fac_of(only_sec, "kn"), "kn", "a hidden type marked sec never names the army: the default stays")
	assert_eq(BtArmy.fac_of(only_sec, ""), "mod", "and an empty default is mod")
	var with_lk := only_sec.duplicate()
	with_lk[lk] = 1
	assert_eq(BtArmy.fac_of(with_lk, "kn"), GameData.fac_of(GameData.key_at(lk)), "a hidden type marked lk names its army")
	var first := PackedInt32Array()
	first.resize(GameData.count())
	first[GameData.index_of("medic")] = 2
	first[GameData.index_of("hoplite")] = 1
	assert_eq(BtArmy.fac_of(first, "kn"), GameData.fac_of(GameData.key_at(mini(GameData.index_of("medic"), GameData.index_of("hoplite")))), "the first type in TYPES order with a squad names the army")
	assert_eq(BtArmy.fac_of(PackedInt32Array(), ""), "mod", "an empty list is mod")


func test_fit_skin() -> void:
	var bad: Array = []
	for c: Variant in F["fit_skin"]:
		var got := BtArmy.fit_skin(c["raw"])
		if got != c["out"]:
			bad.append([c["raw"], got, c["out"]])
	assert_true(bad.is_empty(), "fit_skin equals the page's fitSkin (%d samples)" % (F["fit_skin"] as Array).size(), bad)
	assert_eq(BtArmy.fit_skin({"loki": 1, "nobody": 1}), {"loki": 1}, "only units that have skins")
	assert_eq(BtArmy.fit_skin({"loki": 2}), {}, "an index past the last look is dropped")
	assert_eq(BtArmy.fit_skin({"loki": 0}), {}, "the default look is not stored")


func test_caps_match_page() -> void:
	var bad: Array = []
	for c: Variant in F["share"]:
		var st := _plain(48, {"budget": c[0], "perTeam": c[1]})
		if BtArmy.share_of(st) != int(c[2]):
			bad.append(["share", c, BtArmy.share_of(st)])
	for c: Variant in F["caps"]:
		var st := _plain(48, {"mode": c[0]})
		for k: int in int(c[1]):
			st.add_seat(0, "", false, false, "")
		if BtArmy.base_cap(st) != int(c[2]) or BtArmy.army_cap(st) != int(c[3]):
			bad.append(["caps", c, BtArmy.base_cap(st), BtArmy.army_cap(st)])
	for c: Variant in F["slot_max"]:
		var st := _plain(48, {"mode": c[0]})
		if BtArmy.slot_max(st, int(c[1])) != int(c[2]):
			bad.append(["slot", c, BtArmy.slot_max(st, int(c[1]))])
	assert_true(bad.is_empty(), "share_of, base_cap, army_cap and slot_max equal the page (%d samples)" % [(F["share"] as Array).size() + (F["caps"] as Array).size() + (F["slot_max"] as Array).size()], bad.slice(0, 5))


func test_caps_hand() -> void:
	var want := [250, 250, 166, 125, 100, 83, 71, 62]
	var bad: Array = []
	for n: int in range(1, 9):
		var st := _plain(48, {"mode": "pvp"})
		var sp := _plain(48, {"mode": "spectator"})
		for k: int in n:
			st.add_seat(0, "", false, false, "")
			sp.add_seat(0, "", true, false, "")
		if BtArmy.base_cap(st) != want[n - 1] or BtArmy.army_cap(st) != want[n - 1]:
			bad.append([n, BtArmy.base_cap(st), BtArmy.army_cap(st)])
		if BtArmy.base_cap(sp) != want[n - 1] or BtArmy.army_cap(sp) != 3000 / n:
			bad.append(["spectator", n, BtArmy.base_cap(sp), BtArmy.army_cap(sp)])
	assert_true(bad.is_empty(), "caps for 1..8 seats: min(250, 500 / seats); spectators may build 3000 / seats", bad)
	var none := _plain(48, {"mode": "spectator"})
	assert_eq([BtArmy.base_cap(none), BtArmy.army_cap(none)], [250, 1500], "no seats counts as two")
	var st := _plain(48, {"budget": 500, "perTeam": 3})
	assert_eq(BtArmy.share_of(st), 166, "share = budget / players per team, floored")
	st.budget = 50
	assert_eq(BtArmy.share_of(st), 40, "and never below 40")
	var h := _hidden_types()
	assert_eq([BtArmy.slot_max(st, h[0]), BtArmy.slot_max(st, h[1]), BtArmy.slot_max(st, 0)], [1, 1, 99], "slot_max: one of a hidden type, 99 otherwise")
	st.mode = "spectator"
	assert_eq([BtArmy.slot_max(st, h[0]), BtArmy.slot_max(st, -1), BtArmy.slot_max(st, GameData.count())], [99, 0, 0], "a spectator may build 99 of each; no such type gives 0")


func test_pts_match_page() -> void:
	var bad: Array = []
	for cv: Variant in F["pts"]:
		var c: Dictionary = cv
		var st := _plain(48, {"teams": c["teams"]})
		for sv: Variant in c["seats"]:
			var p := st.add_seat(int(sv["team"]), "", false, false, "")
			p.list = _list(sv["list"])
		var pts: Array = []
		var has: Array = []
		for k: int in st.seats.size():
			pts.append(BtArmy.pts_of(st, k))
			has.append(1 if BtArmy.has_units(st, k) else 0)
		var tp: Array = []
		for t: int in int(c["teams"]):
			tp.append(BtArmy.team_pts(st, t))
		var miss: Array = [BtArmy.pts_of(st, st.seats.size()), 1 if BtArmy.has_units(st, st.seats.size()) else 0]
		if pts != c["pts"] or has != c["has"] or tp != c["team_pts"] or miss != c["missing"]:
			bad.append([pts, c["pts"], has, c["has"], tp, c["team_pts"]])
	assert_true(bad.is_empty(), "pts_of, team_pts and has_units equal the page (%d worlds; hidden types free, but count as units)" % (F["pts"] as Array).size(), bad.slice(0, 3))


func test_mk_players_matches_page() -> void:
	var bad: Array = []
	for c: Variant in F["mk_players"]:
		var st := _plain(48, {"mode": c[0], "teams": c[1], "perTeam": c[2]})
		st.add_seat(5, "x", false, false, "old")
		BtArmy.mk_players(st)
		var got: Array = []
		for p: BattleState.Seat in st.seats:
			got.append([p.id, p.team, 1 if p.bot else 0])
			if p.pid != "" or p.ai or p.fac != "mod" or p.has_dep or p.cp != 0 or p.done or _max_slot(p.list) != 0 or p.list.size() != GameData.count():
				bad.append(["fresh seat", c, p.id])
		if got != c[3]:
			bad.append([c, got])
	assert_true(bad.is_empty(), "mk_players equals the page's mkPlayers (pve: other teams bots; spectator: all bots; old seats replaced)", bad.slice(0, 3))


# ---------------------------------------------------------------- page samples: autoList on v10 draws
func test_pcg_rows_match() -> void:
	var bad: Array = []
	for c: Variant in F["pcg"]:
		var g := Rng.make(str(c[1]), int(c[0]))
		var got: Array = []
		for i: int in 6:
			got.append(g.bounded(int(c[2])))
		if got != c[3]:
			bad.append([c, got])
	assert_true(bad.is_empty(), "the recorder's PCG32 copy draws what core/rng.gd draws", bad)


func test_auto_list_matches_page() -> void:
	var bad: Array = []
	var guards := 0
	var armies := {}
	var cases: Array = F["auto_list"]
	var t0 := Time.get_ticks_msec()
	for cv: Variant in cases:
		var rec: Dictionary = cv
		var c: Dictionary = rec["c"]
		var st := _plain(48, {"seed": c["seed"], "teams": c["teams"], "perTeam": c["perTeam"], "mode": c["mode"], "budget": c["budget"]})
		for k: int in int(c["n"]):
			st.add_seat(Fx.imod(k, int(c["teams"])), "", true, false, "")
		var pi: int = c["pi"]
		var dev: Rng = null
		if c.has("dev"):
			st.seats[pi].bot = false
			st.seats[pi].fac = str(c["fac_in"])
			dev = Rng.make(str(c["dev"][0]), int(c["dev"][1]))
		BtArmy.auto_list(st, pi, dev)
		var p := st.seats[pi]
		var v10: Dictionary = rec["v10"]
		var page: Dictionary = rec["page"]
		if _sparse(p.list) != v10["list"] or p.fac != str(v10["fac"]):
			bad.append(["list", c, p.fac, _sparse(p.list).slice(0, 6), v10["fac"], (v10["list"] as Array).slice(0, 6)])
		if dev != null and dev.draws != int(v10["draws"]):
			bad.append(["draws", c, dev.draws, v10["draws"]])
		if _max_slot(p.list) > 99 or int(v10["peak"]) > 99:
			bad.append(["over 99", c])
		# the page as it is differs from v10 only where some slot went past SLOT_MAX
		if page.has("list") != (int(page["peak"]) > 99):
			bad.append(["guards", c, page])
		if page.has("list"):
			guards += 1
		if dev == null:
			armies[p.fac] = true
	var ms := Time.get_ticks_msec() - t0
	assert_true(cases.size() >= 350, "%d autoList samples (%d seeded armies drawn, %d where the v10 guards bite), %d ms" % [cases.size(), armies.size(), guards, ms])
	assert_eq(armies.size(), 15, "the seeded samples draw all 15 armies")
	assert_true(guards >= 6, "the samples include lists the page pushed past 99")
	assert_true(bad.is_empty(), "auto_list equals the page's autoList on the same draws (list, army, number of draws)", bad.slice(0, 4))


func test_cheapest_unit_per_army() -> void:
	var want := {"gr": "archer", "mod": "medic", "kn": "knd2", "sw": "swripper", "rb": "rscarab", "or": "grot", "th": "musket",
		"jp": "yumi", "nr": "viking", "eg": "mummy", "md": "pike", "el": "elranger", "de": "desyren", "ta": "tadrone", "cx": "cxc"}
	var got := {}
	for fac: String in GameData.factions():
		got[fac] = GameData.key_at(BtArmy.cheapest(fac))
	assert_eq(got, want, "the cheapest unit of each army (first strict minimum of pts in the pool)")
	assert_eq(BtArmy.cheapest("zz"), -1, "an army with no pool has none")
	# a share no unit fits leaves one squad of the cheapest (the page's 'never an empty army')
	var st := _plain(48, {"budget": 40})
	st.add_seat(0, "", true, false, "")
	st.seats[0].fac = "nr"
	BtArmy.auto_list(st, 0, Rng.make("t", 1))
	assert_eq(_sparse(st.seats[0].list), [[GameData.index_of("viking"), 1]], "40 points buys nothing in nr: one squad of its cheapest")


func test_auto_list_pure_function() -> void:
	var a := _plain(48, {"seed": 4242, "teams": 3, "budget": 1500})
	var b := _plain(48, {"seed": 4242, "teams": 3, "budget": 1500})
	for k: int in 3:
		a.add_seat(k, "", true, false, "")
		b.add_seat(k, "", false, false, "")
	BtArmy.auto_list(a, 1, null)
	BtArmy.auto_list(a, 1, null)
	BtArmy.auto_list(b, 1, null)
	assert_eq([a.seats[1].fac, a.seats[1].list], [b.seats[1].fac, b.seats[1].list], "seeded: the same (seed, seat, setup) gives the same list, bot or not, called once or twice")
	# each seat and each seed has its own stream: over eight seats (or seeds) the armies differ
	var by_seat := {}
	var by_seed := {}
	for k: int in 8:
		var s1 := _plain(48, {"seed": 4242, "teams": 2, "budget": 1500})
		var s2 := _plain(48, {"seed": 4242 + 1000 * k, "teams": 2, "budget": 1500})
		for q: int in 8:
			s1.add_seat(Fx.imod(q, 2), "", true, false, "")
			s2.add_seat(Fx.imod(q, 2), "", true, false, "")
		BtArmy.auto_list(s1, k, null)
		BtArmy.auto_list(s2, 1, null)
		by_seat[str([s1.seats[k].fac, s1.seats[k].list])] = true
		by_seed[str([s2.seats[1].fac, s2.seats[1].list])] = true
	assert_true(by_seat.size() >= 4 and by_seed.size() >= 4, "eight seats give %d different lists, eight seeds %d" % [by_seat.size(), by_seed.size()])
	var d0 := a.digest()
	BtArmy.auto_list(a, 9, null)
	assert_eq(a.digest(), d0, "no such seat: nothing changes")
	assert_true(a.rngs.is_empty(), "the seeded stream is not kept in the state (fresh per call)")
	# dev: the seat's army, draws from the device stream
	a.seats[0].fac = "zz"
	var dev := Rng.make("ui", 5)
	BtArmy.auto_list(a, 0, dev)
	assert_eq(a.seats[0].fac, "mod", "dev: an unknown army becomes mod")
	assert_true(dev.draws > 0, "dev: the draws come from the device stream")


func test_slot_cap_99() -> void:
	# the page gave 220 squads of one type here (seed 10, budget 10000, two seats of one, mod)
	var st := _plain(48, {"seed": 10, "budget": 10000})
	st.add_seat(0, "", false, false, "")
	st.add_seat(1, "", true, false, "")
	st.seats[0].fac = "mod"
	BtArmy.auto_list(st, 0, Rng.make("dev:mod", 10))
	var peak := -1
	for cv: Variant in F["auto_list"]:
		var c: Dictionary = cv["c"]
		if c.get("dev", []) == ["dev:mod", 10] and int(c["budget"]) == 10000:
			peak = int(cv["page"]["peak"])
	assert_true(peak > 99, "on these draws the page itself filled %d squads of one type" % peak)
	assert_true(_max_slot(st.seats[0].list) <= 99, "the port stops at 99 (and the upgrades never pass it): %d" % _max_slot(st.seats[0].list))
	var bad: Array = []
	for fac: String in GameData.factions():
		for budget: int in [10000, 27000, 40000]:
			var s2 := _plain(48, {"seed": 3, "budget": budget})
			s2.add_seat(0, "", false, false, "")
			s2.seats[0].fac = fac
			BtArmy.auto_list(s2, 0, Rng.make("cap", budget))
			BtArmy.auto_list(s2, 0, null)
			if _max_slot(s2.seats[0].list) > 99:
				bad.append([fac, budget])
	assert_true(bad.is_empty(), "no slot above 99 for any army at 10000 / 27000 / 40000 points (fill and upgrades)", bad)


func test_hidden_types_never_in_bot_lists() -> void:
	var hidden := _hidden_types()
	var seen := 0
	var bad: Array = []
	for seed: int in range(1, 41):
		for budget: int in [200, 1000, 5000]:
			var st := _plain(48, {"seed": seed * 7919, "budget": budget, "teams": 4})
			for k: int in 4:
				st.add_seat(k, "", true, false, "")
			for k: int in 4:
				BtArmy.auto_list(st, k, null)
				seen += 1
				for h: int in hidden:
					if st.seats[k].list[h] != 0:
						bad.append([seed, budget, k])
	for fac: String in GameData.factions():
		var st := _plain(48, {"budget": 3000})
		st.add_seat(0, "", false, false, "")
		st.seats[0].fac = fac
		BtArmy.auto_list(st, 0, Rng.make(fac, 9))
		for h: int in hidden:
			if st.seats[0].list[h] != 0:
				bad.append([fac])
	assert_true(bad.is_empty(), "hidden types never appear in a bot list (%d seeded lists, 15 armies)" % seen, bad.slice(0, 3))


# ---------------------------------------------------------------- page samples: deployment points
func test_dep_capacity_matches_page() -> void:
	var bad: Array = []
	for c: Variant in F["dep_capacity"]:
		if BtArmy.dep_capacity(int(c[0]), int(c[1])) != int(c[2]):
			bad.append([c, BtArmy.dep_capacity(int(c[0]), int(c[1]))])
	assert_true(bad.is_empty(), "dep_capacity equals the page's depCapacity (w - 5 formula kept)", bad)


func test_dep_slots_matches_page() -> void:
	var bad: Array = []
	var pts := 0
	for c: Variant in F["dep_slots"]:
		var st := _plain(int(c[0]), {"d": c[1]})
		var got := BtArmy.dep_slots(st)
		var want: Array = c[2]
		if got.size() != want.size():
			bad.append([c[0], c[1], got.size(), want.size()])
			continue
		for i: int in want.size():
			pts += 1
			var q: Array = want[i]
			# the page's double rounded to 10 MI: within 5 MI, on the grid
			if not _near(got[i][0], got[i][1], float(q[0]), float(q[1]), 5.0) or Fx.imod(got[i][0], 10) != 0 or Fx.imod(got[i][1], 10) != 0:
				bad.append([c[0], c[1], i, got[i], q])
	assert_true(bad.is_empty(), "dep_slots equals the page's depSlots to the 10 MI grid (%d slots)" % pts, bad.slice(0, 4))
	var odd := _plain(26, {"d": 18})
	assert_eq(BtArmy.dep_slots(odd), [PackedInt64Array([-10000, -6000]), PackedInt64Array([10000, -6000])], "one row: it sits at -D (the page's corner quirk, kept)")
	assert_eq(BtArmy.dep_slots(_plain(5, {"d": 5})).size(), 0, "a table too small for any slot has none")


func test_dep_why_not_matches_page() -> void:
	var bad: Array = []
	var n := 0
	var fragile := 0
	var keys := {}
	for cv: Variant in F["dep_why_not"]:
		var c: Dictionary = cv
		var st := _state(str(c["field"]), c["setup"], c["seats"])
		for qv: Variant in c["q"]:
			var q: Array = qv
			var got := BtArmy.dep_why_not(st, int(q[0]), int(q[1]), int(q[2]))
			if int(q[5]) == 0:
				fragile += 1
				continue
			n += 1
			var args: Array = got["args"]
			var want_args: Array = [] if int(q[4]) < 0 else [q[4]]
			keys[got["key"]] = true
			if got["key"] != str(q[3]) or args != want_args:
				bad.append([c["field"], q, got])
	assert_true(n >= 600, "%d robust depWhyNot samples (%d fragile counted)" % [n, fragile])
	assert_eq(keys.size(), 5, "the samples hold every key: '', edge, blocked, mate, foe")
	assert_true(bad.is_empty(), "dep_why_not equals the page's depWhyNot (key and seat / team)", bad.slice(0, 4))


func test_auto_dep_matches_page() -> void:
	var bad: Array = []
	var n := 0
	var fragile := 0
	for cv: Variant in F["auto_dep"]:
		var c: Dictionary = cv
		var st := _state(str(c["field"]), c["setup"], c["seats"])
		var big := false
		for t: int in st.teams:
			big = big or st.team_seats(t).size() > 4
		for ov: Variant in c["out"]:
			var o: Array = ov
			var pi: int = o[0]
			var got := BtArmy.auto_dep(st, pi)
			if Fx.imod(got[0], 10) != 0 or Fx.imod(got[1], 10) != 0:
				bad.append(["grid", c["field"], o, got])
			if int(o[4]) == 1:
				n += 1
				# the page's double rounded to the grid; a team above four turns its ring by Q16 trig (one step either way)
				if not _near(got[0], got[1], float(o[1]), float(o[2]), 15.0 if big else 5.0):
					bad.append([c["field"], c["setup"], o, got])
			else:
				fragile += 1
			# both sides continue from the page's point on the grid (as the recorder did)
			var p := st.seats[pi]
			p.has_dep = true
			p.dep_x = 10 * Fx.js_round(roundi(float(o[1]) * 1000.0), 10000)
			p.dep_z = 10 * Fx.js_round(roundi(float(o[2]) * 1000.0), 10000)
	assert_true(n >= 75, "%d robust autoDep samples (%d fragile counted)" % [n, fragile])
	assert_true(bad.is_empty(), "auto_dep equals the page's autoDep to the 10 MI grid", bad.slice(0, 4))


# ---------------------------------------------------------------- page samples: deploy
func test_deploy_matches_page() -> void:
	var bad: Array = []
	var cmp := 0
	var fragile := 0
	var flipped := 0
	var skipped := 0
	var worst_slot := 0.0
	var worst_res := 0.0
	for cv: Variant in F["deploy"]:
		var c: Dictionary = cv
		var st := _state(str(c["field"]), c["setup"], c["seats"])
		var given: Array = []
		for p: BattleState.Seat in st.seats:
			given.append(p.has_dep)
		var ev: Array[Dictionary] = []
		BtArmy.deploy(st, ev)
		# seats and their points: given ones untouched, the rest within the grid rounding of the page's autoDep
		var deps: Array = c["deps"]
		var auto: Array = c["auto"]
		var ai := 0
		var diverged := false
		for k: int in st.seats.size():
			var p := st.seats[k]
			if deps[k] == null:
				if p.has_dep:
					bad.append(["dep written for an empty army", c["field"], k])
				continue
			var q: Array = deps[k]
			if bool(given[k]):
				if p.dep_x != int(q[0]) or p.dep_z != int(q[1]):
					bad.append(["given dep changed", c["field"], k])
			else:
				var robust := int(auto[ai]) == 1
				ai += 1
				if not robust:
					diverged = true
					print("      deploy %s: seat %d's autoDep is fragile, its models are not compared" % [c["field"], k])
				elif not _near(p.dep_x, p.dep_z, float(q[0]), float(q[1]), 5.0):
					bad.append(["auto dep", c["field"], k, [p.dep_x, p.dep_z], q])
		# squads: the same ids, kinds, sides, seats, sizes, shields, in the same order; facing to the table centre
		var sq_rows: Array = c["squads"]
		if st.squads.size() != sq_rows.size():
			bad.append(["squad count", c["field"], st.squads.size(), sq_rows.size()])
			continue
		var slot_of := {}
		for i: int in sq_rows.size():
			var row: Array = sq_rows[i]
			var s := st.squads[i]
			if [s.id, s.k, s.side, s.pl, s.n0, s.vs] != row.slice(0, 6):
				bad.append(["squad", c["field"], [s.id, s.k, s.side, s.pl, s.n0, s.vs], row.slice(0, 6)])
			var p := st.seats[s.pl]
			var face: float = row[8]
			var flen := Fx.isqrt(p.dep_x * p.dep_x + p.dep_z * p.dep_z)
			var ftol := 0.5 + (1000.0 / float(flen) if flen > 0 else 0.0) + 0.000001
			if absf(float(s.fx) - 1000.0 * sin(face)) > ftol or absf(float(s.fz) - 1000.0 * cos(face)) > ftol:
				bad.append(["facing", c["field"], s.id, [s.fx, s.fz], face])
			slot_of[s.id] = row[9]
		# models: ids, hp, then position = the port's slot + the free-spot offset; when the page took the same candidate
		# the offsets differ only by their rounding (near rings 5 MI, wide rings 15 MI)
		var rows: Array = c["models"]
		if st.units.size() != rows.size():
			bad.append(["model count", c["field"], st.units.size(), rows.size()])
			continue
		var j_of := {}
		for mi: int in rows.size():
			var r: Array = rows[mi]
			var u := st.units[mi]
			if u.id != str(r[0]) or u.sq != str(r[1]) or u.hp != int(r[2]):
				bad.append(["model", c["field"], u.id, r.slice(0, 3)])
				continue
			if Fx.imod(u.x, 10) != 0 or Fx.imod(u.z, 10) != 0:
				bad.append(["grid", c["field"], u.id, u.x, u.z])
			if diverged:
				skipped += 1
				continue
			var s := st.squad(u.sq)
			var j: int = j_of.get(u.sq, 0)
			j_of[u.sq] = j + 1
			var cc := _centre(st, s)
			var ps: PackedInt64Array = BtSquads.formation(s.n0, cc[0], cc[1], s.fx, s.fz, BtSquads.radius_of(s.ti))[j]
			var qs: Array = (slot_of[u.sq] as Array)[j]
			worst_slot = maxf(worst_slot, maxf(absf(float(ps[0]) - float(qs[0])), absf(float(ps[1]) - float(qs[1]))))
			var rx := float(u.x - int(ps[0])) - (float(r[3]) - float(qs[0]))
			var rz := float(u.z - int(ps[1])) - (float(r[4]) - float(qs[1]))
			var tol := 5.0 if int(r[5]) <= 1 + BtOffsets.FREESPOT_NEAR.size() else 15.0
			var same := absf(rx) <= tol + 0.000001 and absf(rz) <= tol + 0.000001
			if int(r[6]) == 0:
				fragile += 1
				if not same:
					flipped += 1
					diverged = true
					print("      deploy %s: model %d/%d %s took another candidate (page n %d), offset gap [%.1f, %.1f]" % [c["field"], mi, rows.size(), u.id, r[5], rx, rz])
				continue
			cmp += 1
			worst_res = maxf(worst_res, maxf(absf(rx), absf(rz)))
			if not same:
				bad.append(["position", c["field"], u.id, [u.x, u.z], [r[3], r[4]], [rx, rz], r[5]])
		# one log line per placed seat
		var placed := 0
		for p: BattleState.Seat in st.seats:
			if BtArmy.has_units(st, p.id):
				placed += 1
		if ev.size() != placed:
			bad.append(["events", c["field"], ev.size(), placed])
	print("      deploy: %d robust models compared, %d fragile (%d took another candidate), %d after a divergence; worst slot gap %.1f MI, worst offset gap %.1f MI" % [cmp, fragile, flipped, skipped, worst_slot, worst_res])
	assert_true(cmp >= 400, "%d robust deploy positions compared against the page before any divergence" % cmp)
	assert_true(worst_slot <= 35.0, "every v10 slot is within 35 MI of the page's (the recorder's 40 MI covers the candidate shift)")
	assert_true(bad.is_empty(), "deploy equals the page's deploy: ids, order, hp, facing, points to the grid rounding", bad.slice(0, 4))


## Every robust model again, without the cascade: each one is placed by the port (spec centre, formation, free_spot)
## into the page's world as it stood (the page's earlier models at their points to the nearest MI), so a borderline
## flip earlier in the scenario does not hide the rest.
func test_deploy_replay_matches_page() -> void:
	var bad: Array = []
	var cmp := 0
	var fragile := 0
	var flipped := 0
	for cv: Variant in F["deploy"]:
		var c: Dictionary = cv
		var st := _state(str(c["field"]), c["setup"], c["seats"])
		var deps: Array = c["deps"]
		for k: int in st.seats.size():
			if deps[k] != null:
				var p := st.seats[k]
				p.has_dep = true
				p.dep_x = 10 * Fx.js_round(roundi(float(deps[k][0]) * 1000.0), 10000)
				p.dep_z = 10 * Fx.js_round(roundi(float(deps[k][1]) * 1000.0), 10000)
		var rows: Array = c["models"]
		var mi := 0
		for sv: Variant in c["squads"]:
			var row: Array = sv
			var s := st.add_squad(str(row[0]), str(row[1]), int(row[2]), int(row[3]), int(row[4]), int(row[5]))
			var p := st.seats[s.pl]
			var f := Fx.norm1000(-p.dep_x, -p.dep_z)
			if f[0] == 0 and f[1] == 0:
				f = PackedInt64Array([0, -1000])
			s.fx = f[0]
			s.fz = f[1]
			var cc := _centre(st, s)
			var r := BtSquads.radius_of(s.ti)
			var slots := BtSquads.formation(s.n0, cc[0], cc[1], s.fx, s.fz, r)
			var page_slots: Array = row[9]
			for j: int in slots.size():
				var m: Array = rows[mi]
				mi += 1
				var sp := BtBlocking.free_spot(st, slots[j][0], slots[j][1], null, PackedInt64Array(), 0, r)
				var qs: Array = page_slots[j]
				var rx := float(sp[0] - slots[j][0]) - (float(m[3]) - float(qs[0]))
				var rz := float(sp[1] - slots[j][1]) - (float(m[4]) - float(qs[1]))
				var tol := 5.0 if int(m[5]) <= 1 + BtOffsets.FREESPOT_NEAR.size() else 15.0
				var same := absf(rx) <= tol + 0.000001 and absf(rz) <= tol + 0.000001
				if int(m[6]) == 0:
					fragile += 1
					if not same:
						flipped += 1
				else:
					cmp += 1
					if not same:
						bad.append([c["field"], m[0], [sp[0], sp[1]], [m[3], m[4]], [rx, rz]])
				# the world follows the page
				st.add_unit(str(m[0]), s, int(m[2]), roundi(float(m[3])), roundi(float(m[4])))
	print("      deploy replay: %d robust models, %d fragile (%d took another candidate)" % [cmp, fragile, flipped])
	assert_true(cmp >= 1100, "%d robust deploy positions replayed against the page" % cmp)
	assert_true(bad.is_empty(), "each robust model lands where the page put it (to the grid rounding), placed in the page's world", bad.slice(0, 4))


## the centre of a squad as the spec places it (the dep, then rings of six around it), from the squad's index in its seat
func _centre(st: BattleState, s: BattleState.Squad) -> PackedInt64Array:
	var p := st.seats[s.pl]
	var i := int(s.id.split(":")[1])
	if i == 0:
		return PackedInt64Array([p.dep_x, p.dep_z])
	var ring := 1 + (i - 1) / 6
	var th := Fx.idiv(Fx.imod(i - 1, 6) * FieldProps.TWO_PI, 6) + ring * BtOffsets.DEP_ANG_STEP
	return PackedInt64Array([p.dep_x + 10 * Fx.js_round(FieldProps.cos_q(th) * ring * 520, 65536),
		p.dep_z + 10 * Fx.js_round(FieldProps.sin_q(th) * ring * 520, 65536)])


# ---------------------------------------------------------------- hand cases: deployment points
## an open w-inch table (depth as the page) with seats [team, dep or null]
func _open(w: int, seats: Array, setup: Dictionary = {}) -> BattleState:
	var s := {"seed": 11, "w": w, "teams": 2, "perTeam": 1}
	s.merge(setup, true)
	var st := BattleState.make(s)
	for sv: Variant in seats:
		var r: Array = sv
		var p := st.add_seat(int(r[0]), "", false, false, "")
		if r[1] != null:
			p.has_dep = true
			p.dep_x = int(r[1][0])
			p.dep_z = int(r[1][1])
	return st


func _why(st: BattleState, pi: int, x: int, z: int) -> Array:
	var d := BtArmy.dep_why_not(st, pi, x, z)
	return [d["key"], d["args"]]


func test_dep_why_not_hand() -> void:
	# 60 x 44: the margin is 3 inches, so |x| <= 27000 and |z| <= 19000; a mate at (-20000, 0), a foe at (20000, 0)
	var st := _open(60, [[0, null], [0, [-20000, 0]], [1, [20000, 0]]])
	assert_eq(_why(st, 0, 27000, 19000), ["", []], "exactly 3 inches from both edges is allowed")
	assert_eq(_why(st, 0, -27000, -19000), ["", []], "and at the other corner")
	assert_eq(_why(st, 0, 27001, 0), ["edge", []], "1 MI further is off the table (x)")
	assert_eq(_why(st, 0, 0, -19001), ["edge", []], "and on z")
	assert_eq(_why(st, 0, -15000, 0), ["", []], "a team-mate exactly 5 inches away is allowed (strict <)")
	assert_eq(_why(st, 0, -15010, 0), ["mate", [1]], "4.99 inches from a team-mate: mate, with that seat")
	assert_eq(_why(st, 0, 0, 0), ["", []], "a foe exactly 20 inches away is allowed")
	assert_eq(_why(st, 0, 10, 0), ["foe", [1]], "19.99 inches from a foe: foe, with its team")
	assert_eq(_why(st, 0, 0, 12000), ["", []], "a diagonal foe at (20000, 0) from (0, 12000) is 23.3 inches away: allowed")
	# near a mate and a foe at once: the first seat in order wins; a seat without a dep is skipped
	var two := _open(60, [[0, null], [0, [-20000, 0]], [1, [-20000, 4000]]])
	assert_eq(_why(two, 0, -20000, 2000), ["mate", [1]], "near a mate (seat 1) and a foe (seat 2): seat order, mate")
	two.seats[1].has_dep = false
	assert_eq(_why(two, 0, -20000, 2000), ["foe", [1]], "the mate without a dep is skipped: foe, team 1")
	two.seats[0].has_dep = true
	two.seats[0].dep_x = -20000
	two.seats[0].dep_z = 2000
	assert_eq(_why(two, 0, -20000, 2000)[0], "foe", "the asking seat's own dep never counts")
	two.seats[1].has_dep = true
	assert_eq(_why(two, 9, -20000, 1000), ["foe", [0]], "no such seat: every dep counts as another team's (seat 0 first)")
	# a building 10 inches square at (5000, 10000), blocked for |dx| < 5700: its middle is blocked all round
	var items: Array[Dictionary] = [BtBlocking.prep_one("building", 5000, 10000, 0, 10000, 0, 10000, 10000)]
	st.set_props(items, true)
	assert_eq(_why(st, 2, 5000, 10000), ["blocked", []], "inside a big building: blocked")
	assert_true(BtBlocking.block_at(st, 10690, 10000) and not BtBlocking.block_at(st, 10710, 10000), "the building's edge is where the test expects")
	assert_eq(_why(st, 2, 8500, 10000), ["", []], "blocked there, but ground 2.5 inches away: allowed (roomToLand)")
	var wide: Array[Dictionary] = [BtBlocking.prep_one("building", 25000, 0, 0, 40000, 0, 40000, 40000)]
	st.set_props(wide, true)
	assert_eq(_why(st, 0, 27010, 0), ["edge", []], "off the table and inside a building: edge first")
	assert_eq(_why(st, 0, 15000, 0), ["blocked", []], "blocked comes before a foe that is too close")


func test_auto_dep_hand() -> void:
	var bad: Array = []
	var illegal: Array = []
	for teams: int in [2, 4, 8]:
		for per: int in range(1, 5):
			var n := teams * per
			var w := 48
			while BtArmy.dep_capacity(w, FieldTerrain.depth_for(w)) < n and w < 180:
				w += 2
			var st := BattleState.make({"seed": 5, "w": w, "teams": teams, "perTeam": per, "mode": "team"})
			BtArmy.mk_players(st)
			var slots := BtArmy.dep_slots(st)
			for p: BattleState.Seat in st.seats:
				var before := [p.has_dep, p.dep_x, p.dep_z]
				var d := BtArmy.auto_dep(st, p.id)
				if [p.has_dep, p.dep_x, p.dep_z] != before:
					bad.append(["auto_dep wrote the seat", teams, per])
				if Fx.imod(d[0], 10) != 0 or Fx.imod(d[1], 10) != 0 or absi(d[0]) > w * 500 - 3000 or absi(d[1]) > st.d * 500 - 3000:
					bad.append(["grid or table", teams, per, p.id, d])
				var mates := st.team_seats(p.team)
				var c := slots[Fx.imod(Fx.js_round(p.team * slots.size(), teams), slots.size())]
				if mates[0] == p and BtArmy.dep_why_not(st, p.id, c[0], c[1])["key"] == "" and d != c:
					bad.append(["the first of a team takes its team slot when that is legal", teams, per, p.id, d, c])
				if BtArmy.dep_why_not(st, p.id, d[0], d[1])["key"] != "":
					illegal.append([teams, per, w, p.id, BtArmy.dep_why_not(st, p.id, d[0], d[1])])
				p.has_dep = true
				p.dep_x = d[0]
				p.dep_z = d[1]
	assert_true(bad.is_empty(), "auto_dep for 2/4/8 teams x 1-4 seats: on the grid, on the table, the seat untouched, team slots first", bad.slice(0, 4))
	assert_true(illegal.is_empty(), "and every dep is legal on a table grown as the page grows it", illegal.slice(0, 4))
	# a team of six (an online room where everyone joined one team): the ring turns by sixths
	var st6 := BattleState.make({"seed": 5, "w": 100, "teams": 2, "perTeam": 4, "mode": "team"})
	for k: int in 6:
		st6.add_seat(0, "", false, false, "")
	for k: int in 4:
		st6.add_seat(1, "", true, false, "")
	var ok6 := true
	for p: BattleState.Seat in st6.seats:
		var d := BtArmy.auto_dep(st6, p.id)
		ok6 = ok6 and Fx.imod(d[0], 10) == 0 and Fx.imod(d[1], 10) == 0 and BtArmy.dep_why_not(st6, p.id, d[0], d[1])["key"] == ""
		p.has_dep = true
		p.dep_x = d[0]
		p.dep_z = d[1]
	assert_true(ok6, "a team of six gets legal deps on the grid")
	assert_eq(BtArmy.auto_dep(st6, 99), PackedInt64Array([0, 0]), "no such seat: [0, 0]")
	# nowhere legal (8 seats on a 24 inch table): the team slot comes back
	var tiny := BattleState.make({"seed": 5, "w": 24, "teams": 4, "perTeam": 2, "mode": "team"})
	BtArmy.mk_players(tiny)
	var last := PackedInt64Array()
	for p: BattleState.Seat in tiny.seats:
		last = BtArmy.auto_dep(tiny, p.id)
		p.has_dep = true
		p.dep_x = last[0]
		p.dep_z = last[1]
	var ts := BtArmy.dep_slots(tiny)
	assert_eq(last, ts[Fx.imod(Fx.js_round(3 * ts.size(), 4), ts.size())], "no legal point anywhere: the team slot itself")


# ---------------------------------------------------------------- hand cases: deploy
func test_deploy_hand() -> void:
	var inf := GameData.index_of("infantry")
	var med := GameData.index_of("medic")
	var hvy := GameData.index_of("heavy")
	var st := _open(48, [[0, [-15000, -8000]], [0, null], [1, null], [1, [0, 0]]])
	st.seats[0].list[inf] = 2
	st.seats[0].list[med] = 1
	st.seats[2].list[hvy] = 1
	st.seats[3].list[med] = 1
	var ev: Array[Dictionary] = []
	BtArmy.deploy(st, ev)
	var ids: Array = []
	for s: BattleState.Squad in st.squads:
		ids.append([s.id, s.k, s.side, s.pl, s.n0, s.vs])
	var first := "infantry" if inf < med else "medic"
	assert_eq(ids.size(), 5, "three squads for seat 0, one each for seats 2 and 3; the empty seat 1 places none")
	assert_eq((ids[0] as Array).slice(0, 2), ["0:0", first], "squads in TYPES order x count: first the earlier type")
	assert_eq([ids[3][0], ids[3][1], ids[3][2], ids[3][3]], ["2:0", "heavy", 1, 2], "squad id is <seat>:<i>, side the team, pl the seat")
	assert_false(st.seats[1].has_dep, "an empty army is skipped: no dep is made for it")
	assert_true(st.seats[2].has_dep, "a missing dep is made by auto_dep and written to the seat")
	var fresh := _open(48, [[0, [-15000, -8000]], [0, null], [1, null], [1, [0, 0]]])
	assert_eq(PackedInt64Array([st.seats[2].dep_x, st.seats[2].dep_z]), BtArmy.auto_dep(fresh, 2), "the point auto_dep gives with the earlier deps in place")
	# facing: towards the table centre; a dep on the centre faces -z (the page's atan2(-0, -0))
	var f0 := Fx.norm1000(15000, 8000)
	assert_eq([st.squads[0].fx, st.squads[0].fz], [f0[0], f0[1]], "a squad faces the table centre")
	assert_eq([st.squads[4].fx, st.squads[4].fz], [0, -1000], "a dep on the centre faces -z")
	# models: ids, hp, counts; squad 0 stands in formation on the dep (open table)
	var s0 := st.squads[0]
	assert_eq(s0.models.size(), s0.n0, "a squad has n0 models")
	var slots := BtSquads.formation(s0.n0, -15000, -8000, s0.fx, s0.fz, BtSquads.radius(s0))
	var at: Array[PackedInt64Array] = []
	for m: BattleState.Unit in s0.models:
		at.append(PackedInt64Array([m.x, m.z]))
	assert_eq(at, slots, "the first squad stands in formation round the dep")
	assert_eq([s0.models[0].id, s0.models[0].hp, s0.models[0].side, s0.models[0].pl], ["0:0.0", int(GameData.ty(first)["w"]), 0, 0], "model id <squad>.<j>, hp = w")
	assert_true(s0.still and not s0.moved and not s0.shot and s0.ch_tgt == "", "flags start as resetSq leaves them")
	# the next squads of seat 0 stand on the first ring, 5200 MI from the dep
	var s1 := st.squads[1]
	var c1 := _centre(st, s1)
	var sl1 := BtSquads.formation(s1.n0, c1[0], c1[1], s1.fx, s1.fz, BtSquads.radius(s1))
	assert_eq([s1.models[0].x, s1.models[0].z], [sl1[0][0], sl1[0][1]], "squad 1 stands on the first ring (R = 1, angle DEP_ANG_STEP)")
	assert_true(absi(Fx.isqrt(Fx.dist2(c1[0], c1[1], -15000, -8000)) - 5200) <= 10, "the first ring is 5200 MI from the dep")
	# every model on the grid, no two bases overlap
	var grid := true
	var overlap := 0
	for i: int in st.units.size():
		var a := st.units[i]
		grid = grid and Fx.imod(a.x, 10) == 0 and Fx.imod(a.z, 10) == 0
		for j: int in range(i + 1, st.units.size()):
			var b := st.units[j]
			var rr := BtSquads.radius_of(a.ti) + BtSquads.radius_of(b.ti)
			if Fx.dist2(a.x, a.z, b.x, b.z) < rr * rr:
				overlap += 1
	assert_true(grid, "every deployed model is on the 10 MI grid")
	assert_eq(overlap, 0, "no two bases overlap")
	# events and log: one line per placed seat
	var lines: Array = []
	for e: Dictionary in ev:
		lines.append([Events.name_of(Events.id_of(e)), e["key"], e["args"]])
	var m0 := st.squads[0].models.size() + st.squads[1].models.size() + st.squads[2].models.size()
	assert_eq(lines, [["LOG_LINE", "deployed", [0, 3, m0]], ["LOG_LINE", "deployed", [2, 1, st.squads[3].models.size()]],
		["LOG_LINE", "deployed", [3, 1, 1]]], "one LOG_LINE deployed [seat, squads, models] per placed seat")
	assert_eq(st.log_lines.size(), 3, "and the same lines in the log")
	# a second deploy on a board that has squads does nothing
	var d0 := st.digest()
	BtArmy.deploy(st, ev)
	assert_eq(st.digest(), d0, "deploy on a board that already has squads changes nothing")
	assert_eq(ev.size(), 3, "and says nothing")


func test_deploy_crowded_table() -> void:
	# two full armies on a 24 inch table: the rings and the wide pass, still on the grid; shields and models from data
	var st := _open(24, [[0, null], [1, null]], {"budget": 1500})
	BtArmy.auto_list(st, 0, null)
	BtArmy.auto_list(st, 1, null)
	var ev: Array[Dictionary] = []
	BtArmy.deploy(st, ev)
	var grid := true
	var inside := 0
	var lim_x := st.w * 500 - 1200
	var lim_z := st.d * 500 - 1200
	for u: BattleState.Unit in st.units:
		grid = grid and Fx.imod(u.x, 10) == 0 and Fx.imod(u.z, 10) == 0
		if absi(u.x) <= lim_x and absi(u.z) <= lim_z:
			inside += 1
	var vs_ok := true
	for s: BattleState.Squad in st.squads:
		vs_ok = vs_ok and s.vs == int(GameData.ty(s.k).get("vsh", 0)) and s.models.size() == s.n0
	assert_true(st.units.size() >= 100, "a crowded table places %d models" % st.units.size())
	assert_true(grid, "all on the grid, even the outer rings")
	# (on an over-full table a slot beyond the widest ring keeps its own point, as on the page; not here)
	assert_eq(inside, st.units.size(), "every model found ground 1.2 inches inside the table")
	assert_true(vs_ok, "every squad has its full models and its shield layers")


# ---------------------------------------------------------------- pinned digest
func test_digest_pinned() -> void:
	var a := _digest_scenario()
	assert_eq(a, _digest_scenario(), "the scenario digest is stable within a run")
	assert_digest(a, PINNED_DIGEST, "BtArmy scenario digest is pinned")


## lists for 3 seeds x 3 seats (seeded) and 3 seeds x 3 armies (device streams), then a team game on a ruin field:
## mk_players, auto_list, auto_dep through deploy; the digest of the lists, then the BattleState digest
func _digest_scenario() -> String:
	var v := PackedInt64Array()
	for seed: int in [1, 2, 3]:
		var st := BattleState.make({"seed": seed, "w": 48, "teams": 3, "budget": 1000})
		BtArmy.mk_players(st)
		for k: int in 3:
			BtArmy.auto_list(st, k, null)
			v.append(Hash.fnv1a64_str(st.seats[k].fac))
			v.append_array(PackedInt64Array(Array(st.seats[k].list)))
		for fac: String in ["gr", "kn", "ta"]:
			st.seats[0].fac = fac
			BtArmy.auto_list(st, 0, Rng.make("dev:" + fac, seed))
			v.append_array(PackedInt64Array(Array(st.seats[0].list)))
	var g := BattleState.make({"seed": 77, "w": 60, "teams": 3, "perTeam": 2, "mode": "team", "budget": 1200})
	var fp := FieldProps.generate(FieldTerrain.make(60, FieldTerrain.depth_for(60), "ruin", "hills", 77), true, 1000)
	g.set_props(BtBlocking.prep_field(fp), false)
	BtArmy.mk_players(g)
	for p: BattleState.Seat in g.seats:
		BtArmy.auto_list(g, p.id, null)
	var ev: Array[Dictionary] = []
	BtArmy.deploy(g, ev)
	return Hash.digest_hex(v) + ":" + g.digest()
