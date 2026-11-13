extends "res://tests/testing.gd"
## core/battle/combat.gd (BtCombat, R1_PORT_SPEC §1.7): wound_need, clamp_need, inf, count_at_least, total, shooters_of,
## pain_on, pact_on, marked, in_aura, atk_math, shot_why_not, can_heal, heal_why_not, charge_why_not, gren_why_not.
## Two kinds of checks: page samples (fixtures/combat/page_samples.json, written by tools/record_combat.js from the page's
## own functions run in Chromium, with a live cross-check against BT.atkMath / BT.why / BT.inAura on a started match)
## compared exactly, and hand cases: every modifier of atk_math, every why-not key in page order, and the range rules at
## their exact boundaries (shooting, auras, grenades and healing centre to centre; charging and engagement edge to edge).

const FIXTURE := "res://tests/unit/fixtures/combat/page_samples.json"
## Digest of a fixed scenario through every BtCombat function (see _digest_scenario); changes only on purpose.
const PINNED_DIGEST := "8ddb33d7b0347d2b"
const SHOOT := BattleState.HOW_SHOOT
const FIGHT := BattleState.HOW_FIGHT
const OW := BattleState.HOW_OW
const FAR_IN := 1000000000.0

var fx: Dictionary = {}


func setup() -> void:
	var raw: Variant = JSON.parse_string(FileAccess.get_file_as_string(FIXTURE))
	fx = raw if raw is Dictionary else {}


# ------------------------------------------------------------------ helpers
func _st(round_no: int = 1, turn: int = 0, free_fire: bool = false) -> BattleState:
	var st := BattleState.make({"seed": 5, "w": 60, "teams": 3, "freeFire": 1 if free_fire else 0})
	st.round_no = round_no
	st.turn = turn
	return st


## A squad of type k on side `side` with models at the given [x, z] points (MI) and hp (0 = the type's w).
func _sq(st: BattleState, id: String, k: String, side: int, pts: Array, hp: int = 0) -> BattleState.Squad:
	var t := GameData.ty(k)
	var s := st.add_squad(id, k, side, side, int(t.get("n", 1)), 0)
	for j: int in pts.size():
		var p: Array = pts[j]
		st.add_unit("%s.%d" % [id, j], s, hp if hp > 0 else int(t.get("w", 1)), int(p[0]), int(p[1]))
	return s


## First open datasheet (TYPES order, hidden types skipped) for which pred(t) is true; "" if none.
func _find(pred: Callable) -> String:
	for t: Dictionary in GameData.types():
		var k := str(t["k"])
		if not GameData.is_hidden(k) and bool(pred.call(t)):
			return k
	return ""


func _gun(k: String) -> Dictionary:
	return BtAbilities.gun(GameData.index_of(k))


func _mel(k: String) -> Dictionary:
	return BtAbilities.mel(GameData.index_of(k))


func _key(d: Dictionary) -> String:
	return str(d.get("key", "?"))


func _i(v: Variant) -> int:
	return int(v)


## The page's raw distance (inches, a double) against the port's exact d2: the 1e9 sentinel is FAR2 (an empty side).
func _dist_ok(d2: int, page_in: float) -> bool:
	if page_in == FAR_IN:
		return d2 == BattleState.FAR2
	return d2 != BattleState.FAR2 and absf(sqrt(float(d2)) - page_in * 1000.0) <= 0.000001


## The BattleState of one fixture world: squads in order with their flags and mark, units in the recorded global order.
func _world(w: Dictionary) -> BattleState:
	var g: Dictionary = w["g"]
	var st := BattleState.make({"seed": 1, "w": 60, "teams": 3, "freeFire": _i(g["ff"])})
	st.round_no = _i(g["round"])
	st.turn = _i(g["turn"])
	for sv: Variant in w["squads"]:
		var s: Dictionary = sv
		var q := st.add_squad(str(s["id"]), str(s["k"]), _i(s["side"]), _i(s["pl"]), _i(s["n0"]), 0)
		var f: Array = s["f"]
		q.moved = _i(f[0]) == 1
		q.adv = _i(f[1]) == 1
		q.fell = _i(f[2]) == 1
		q.still = _i(f[3]) == 1
		q.shot = _i(f[4]) == 1
		q.charged = _i(f[5]) == 1
		q.ch_done = _i(f[6]) == 1
		var mk := str(s["mk"])
		q.mk = st.mark_key() if mk == "cur" else (st.mark_key() - 16 if mk == "old" else -1)
	for uv: Variant in w["units"]:
		var u: Dictionary = uv
		st.add_unit(str(u["id"]), st.squad(str(u["sq"])), _i(u["hp"]), _i(u["x"]), _i(u["z"]))
	return st


# ------------------------------------------------------------------ page samples
func test_fixture_loaded() -> void:
	assert_true(fx.has("worlds") and fx.has("worlds_in") and fx.has("wound_need"), "fixture has worlds and tables")
	var live: Dictionary = fx.get("live_check", {})
	var bad: Array = live.get("bad", [1])
	assert_true(bad.is_empty() and _i(live.get("pairs", 0)) >= 100 and _i(live.get("in_range", 0)) >= 50 and _i(live.get("engaged", 0)) >= 10,
		"recorder's live cross-check: the cut functions equal BT.atkMath / BT.why / BT.inAura on a started match", live)
	var page: Dictionary = fx["page"]
	var c: Dictionary = page["consts"]
	for name: String in ["ENGAGE", "CHARGE_R", "AURA_R", "BLESS_INV", "REZ_AURA", "PAIN_ROUND", "GREN_R"]:
		assert_eq(GameData.const_int(name, -1), _i(c[name]), "constants.json %s equals the page's" % name)


func test_tables_match_page() -> void:
	var wn: Array = fx["wound_need"]
	var bad: Array = []
	for s: int in range(1, 25):
		for t: int in range(1, 25):
			if BtCombat.wound_need(s, t) != _i(wn[(s - 1) * 24 + t - 1]):
				bad.append([s, t, BtCombat.wound_need(s, t), wn[(s - 1) * 24 + t - 1]])
	assert_true(wn.size() == 576 and bad.is_empty(), "wound_need equals woundNeed for S, T = 1..24", bad.slice(0, 5))
	bad = []
	for pv: Variant in fx["clamp_need"]:
		var p: Array = pv
		if BtCombat.clamp_need(_i(p[0])) != _i(p[1]):
			bad.append(p)
	assert_true(bad.is_empty(), "clamp_need equals clampNeed for -3..10", bad)
	bad = []
	for cv: Variant in fx["count_sum"]:
		var c: Array = cv
		var arr: Array = c[0]
		var d := PackedInt32Array(arr)
		if BtCombat.count_at_least(d, _i(c[1])) != _i(c[2]) or BtCombat.total(d) != _i(c[3]):
			bad.append(c)
	assert_true((fx["count_sum"] as Array).size() >= 20 and bad.is_empty(), "count_at_least and total equal count and sum", bad)
	bad = []
	var rows: Array = fx["inf"]
	for rv: Variant in rows:
		var r: Array = rv
		var ti := GameData.index_of(str(r[0]))
		if ti < 0 or BtCombat.inf(ti) != (_i(r[1]) == 1):
			bad.append(r)
	assert_true(rows.size() == GameData.count() and bad.is_empty(), "inf equals the page's live INF for all %d datasheets" % rows.size(), bad)
	bad = []
	var st := _st()
	var pains := 0
	var pacts := 0
	for rv: Variant in fx["army"]:
		var r: Array = rv
		var ti := GameData.index_of(str(r[0]))
		var bits := _i(r[1])
		for rd: int in range(1, 6):
			st.round_no = rd
			if BtCombat.pain_on(st, ti) != ((bits & (1 << (rd - 1))) != 0):
				bad.append([r, rd])
			if BtCombat.pain_on(st, ti):
				pains += 1
		if BtCombat.pact_on(ti) != ((bits & 32) != 0):
			bad.append([r, "pact"])
		if BtCombat.pact_on(ti):
			pacts += 1
	assert_true(pains > 0 and pacts > 0 and bad.is_empty(), "pain_on (rounds 1..5) and pact_on equal painOn and pactOn for every datasheet", bad.slice(0, 5))


func test_worlds_match_page() -> void:
	var ins: Array = fx["worlds_in"]
	var outs: Array = fx["worlds"]
	assert_eq(ins.size(), outs.size(), "one result per sampled world")
	var counts := {"squads": 0, "pairs": 0, "atk": 0, "shots": 0}
	var bad := {"aura": [], "marked": [], "atk_null": [], "atk": [], "who": [], "d": [], "shooters": [], "shot": [],
		"can_heal": [], "heal": [], "chg": [], "gren": []}
	for wi: int in ins.size():
		var st := _world(ins[wi])
		var wout: Dictionary = outs[wi]
		var aura: Array = wout["aura"]
		for i: int in aura.size():
			var s := st.squads[i]
			var bits := _i(aura[i])
			counts["squads"] += 1
			var kinds := ["hit", "ld", "bless", "rez", "veil"]
			for b: int in kinds.size():
				if BtCombat.in_aura(st, s, kinds[b]) != ((bits & (1 << b)) != 0):
					bad["aura"].append([wi, s.id, kinds[b]])
			if BtCombat.marked(st, s) != ((bits & 32) != 0):
				bad["marked"].append([wi, s.id])
		for pv: Variant in wout["pairs"]:
			var p: Array = pv
			var a := st.squads[_i(p[0])]
			var b := st.squads[_i(p[1])]
			counts["pairs"] += 1
			var atk: Array = p[2]
			for h: int in 3:
				var got := BtCombat.atk_math(st, a, b, h)
				var want: Variant = atk[h]
				if want == null:
					if not got.is_empty():
						bad["atk_null"].append([wi, a.id, b.id, h])
					continue
				if got.is_empty():
					bad["atk_null"].append([wi, a.id, b.id, h, "port has none"])
					continue
				var wa: Array = want
				counts["atk"] += 1
				if _i(wa[0]) > 0:
					counts["shots"] += 1
				var bits := (1 if got["tr"] else 0) | (2 if got["lh"] else 0) | (4 if got["dw"] else 0) | (8 if got["heel"] else 0) \
					| (16 if got["mk"] else 0) | (32 if got["melee"] else 0)
				var mine := [got["shots"], got["need"], got["wneed"], got["mod"], got["sv"], got["dmg"], got["su"], bits]
				var page := [_i(wa[0]), _i(wa[2]), _i(wa[3]), _i(wa[4]), _i(wa[5]), _i(wa[6]), _i(wa[7]), _i(wa[8])]
				if mine != page:
					bad["atk"].append([wi, a.id, b.id, h, mine, page])
				if Array(got["who"] as PackedStringArray) != (wa[1] as Array):
					bad["who"].append([wi, a.id, b.id, h, got["who"], wa[1]])
				if not _dist_ok(int(got["d2"]), float(wa[9])):
					bad["d"].append([wi, a.id, b.id, h, got["d2"], wa[9]])
			# shooters_of
			var gun := BtAbilities.gun(a.ti)
			if p[3] == null:
				if not gun.is_empty():
					bad["shooters"].append([wi, a.id, b.id, "page has no gun"])
			else:
				var sh := BtCombat.shooters_of(a, b, gun)
				var want_sh: Array = p[3]
				var ok := sh.size() == want_sh.size()
				for k: int in mini(sh.size(), want_sh.size()):
					var x: Array = want_sh[k]
					ok = ok and sh[k][0] == _i(x[0]) and _dist_ok(sh[k][1], float(x[1]))
				if not ok:
					bad["shooters"].append([wi, a.id, b.id, sh, want_sh])
			# why-nots
			var ws: Array = p[4]
			var got_s := BtCombat.shot_why_not(st, a, b)
			var sargs: Array = got_s["args"]
			var s_ok := _key(got_s) == str(ws[0])
			if s_ok and str(ws[0]) == "engaged":
				s_ok = sargs.size() == 1 and _i(sargs[0]) == _i(ws[1])
			elif s_ok and str(ws[0]) == "too_far":
				# [the port's floored nearest distance in MI, the range in inches]; the page shows its double to 0.1"
				s_ok = sargs.size() == 2 and _i(sargs[1]) == _i(ws[2]) and _i(sargs[0]) == BtSquads.dist_min(a, b) \
					and _dist_ok(BtSquads.dist2_min(a, b), float(ws[1]))
			elif s_ok:
				s_ok = sargs.is_empty()
			if not s_ok:
				bad["shot"].append([wi, a.id, b.id, got_s, ws])
			if BtCombat.can_heal(st, a, b) != (_i(p[5]) == 1):
				bad["can_heal"].append([wi, a.id, b.id])
			var wh: Array = p[6]
			var got_h := BtCombat.heal_why_not(st, a, b)
			var hargs: Array = got_h["args"]
			var h_ok := _key(got_h) == str(wh[0])
			if h_ok and str(wh[0]) == "too_far":
				h_ok = hargs.size() == 1 and _i(hargs[0]) == _i(wh[1])
			elif h_ok:
				h_ok = hargs.is_empty()
			if not h_ok:
				bad["heal"].append([wi, a.id, b.id, got_h, wh])
			var wc: Array = p[7]
			var got_c := BtCombat.charge_why_not(st, a, b)
			var cargs: Array = got_c["args"]
			var c_ok := _key(got_c) == str(wc[0])
			if c_ok and str(wc[0]) == "too_far":
				var e := _i(cargs[0]) if cargs.size() == 1 else -1
				var pe: float = float(wc[1])
				if pe == FAR_IN:
					c_ok = e == BattleState.FAR2
				else:
					# the port's edge is isqrt(d2) - ra - rb (floored); the page's is the exact double
					c_ok = cargs.size() == 1 and float(e) <= pe * 1000.0 + 0.000001 and float(e) > pe * 1000.0 - 1.000001
			elif c_ok:
				c_ok = cargs.is_empty()
			if not c_ok:
				bad["chg"].append([wi, a.id, b.id, got_c, wc])
			var wg: Array = p[8]
			var got_g := BtCombat.gren_why_not(st, a, b)
			if _key(got_g) != str(wg[0]) or not (got_g["args"] as Array).is_empty():
				bad["gren"].append([wi, a.id, b.id, got_g, wg])
	assert_true(counts["pairs"] >= 1000 and counts["atk"] >= 3000 and counts["shots"] >= 2000,
		"sampled %d squads, %d ordered pairs, %d attacks (%d with shots)" % [counts["squads"], counts["pairs"], counts["atk"], counts["shots"]])
	for k: String in bad:
		var list: Array = bad[k]
		assert_true(list.is_empty(), "page samples agree: " + k, list.slice(0, 5))


## Each why-not key and each atk_math modifier shows up in the page samples (the samples exercise every branch).
func test_samples_cover_every_branch() -> void:
	var seen := {}
	for wv: Variant in fx["worlds"]:
		var w: Dictionary = wv
		for pv: Variant in w["pairs"]:
			var p: Array = pv
			seen["shot:" + str((p[4] as Array)[0])] = true
			seen["heal:" + str((p[6] as Array)[0])] = true
			seen["chg:" + str((p[7] as Array)[0])] = true
			seen["gren:" + str((p[8] as Array)[0])] = true
			if _i(p[5]) == 1:
				seen["can_heal"] = true
			for h: int in 3:
				var m: Variant = (p[2] as Array)[h]
				if m != null:
					seen["mod%d" % _i((m as Array)[4])] = true
		for b: Variant in w["aura"]:
			for i: int in 6:
				if (_i(b) & (1 << i)) != 0:
					seen["aura%d" % i] = true
	var want := ["shot:", "shot:no_gun", "shot:own_side", "shot:already_shot", "shot:fell_back", "shot:advanced", "shot:engaged",
		"shot:target_engaged", "shot:too_far", "heal:", "heal:already_acted", "heal:nobody_hurt", "heal:too_far", "chg:",
		"chg:enemies_only", "chg:charge_done", "chg:advanced", "chg:fell_back", "chg:engaged", "chg:too_far", "gren:",
		"gren:not_infantry", "gren:already_shot", "gren:moved_fast", "gren:engaged", "gren:enemies_only", "gren:too_far",
		"can_heal", "mod-1", "mod0", "mod1", "aura0", "aura1", "aura2", "aura3", "aura4", "aura5"]
	var missing: Array = []
	for k: String in want:
		if not seen.has(k):
			missing.append(k)
	assert_true(missing.is_empty(), "the page samples reach every why-not key, every mod and every aura kind", missing)


# ------------------------------------------------------------------ hand cases: numbers
func test_wound_table_hand_values() -> void:
	assert_eq(BtCombat.wound_need(8, 4), 2, "S at twice T wounds on 2")
	assert_eq(BtCombat.wound_need(9, 4), 2, "S above twice T wounds on 2")
	assert_eq(BtCombat.wound_need(5, 4), 3, "S above T wounds on 3")
	assert_eq(BtCombat.wound_need(7, 4), 3, "S below twice T but above T wounds on 3")
	assert_eq(BtCombat.wound_need(4, 4), 4, "S equal to T wounds on 4")
	assert_eq(BtCombat.wound_need(3, 4), 5, "S below T wounds on 5")
	assert_eq(BtCombat.wound_need(3, 5), 5, "S below T but more than half wounds on 5")
	assert_eq(BtCombat.wound_need(2, 4), 6, "S at half T wounds on 6")
	assert_eq(BtCombat.wound_need(2, 10), 6, "S far below T wounds on 6")
	assert_eq(BtCombat.clamp_need(1), 2, "a need never goes below 2")
	assert_eq(BtCombat.clamp_need(-4), 2, "even far below")
	assert_eq(BtCombat.clamp_need(7), 6, "a need never goes above 6")
	assert_eq(BtCombat.clamp_need(4), 4, "inside stays")


func test_count_and_total() -> void:
	var d := PackedInt32Array([1, 6, 3, 4, 6, 2])
	assert_eq(BtCombat.count_at_least(d, 4), 3, "three dice of 4 or more")
	assert_eq(BtCombat.count_at_least(d, 6), 2, "two sixes")
	assert_eq(BtCombat.count_at_least(d, 7), 0, "nothing reaches 7")
	assert_eq(BtCombat.count_at_least(d, 0), 6, "need 0 counts every die (torrent)")
	assert_eq(BtCombat.count_at_least(PackedInt32Array(), 3), 0, "no dice, no successes")
	assert_eq(BtCombat.total(d), 22, "the sum")
	assert_eq(BtCombat.total(PackedInt32Array()), 0, "the sum of nothing")


func test_inf() -> void:
	assert_true(BtCombat.inf(GameData.index_of("infantry")), "line infantry are foot soldiers")
	assert_false(BtCombat.inf(GameData.index_of("cavalry")), "riders are not")
	assert_false(BtCombat.inf(GameData.index_of("mech")), "a big machine is not")
	var veh := _find(func(t: Dictionary) -> bool: return t.has("veh"))
	assert_false(BtCombat.inf(GameData.index_of(veh)), "a vehicle is not")
	assert_false(BtCombat.inf(-1) or BtCombat.inf(GameData.count()), "outside the table is not")


func test_shooters_of_centre_to_centre() -> void:
	var st := _st()
	var gun := _gun("infantry")
	assert_eq(int(gun["rng"]), 24, "the infantry gun reaches 24 inches")
	var s := _sq(st, "0:0", "infantry", 0, [[0, 0], [0, -1000], [0, -2000]])
	# range is centre to centre: 24 inches + 1 MI from model 0 reaches, 25001 and 26001 from the others do not
	var t := _sq(st, "1:0", "mech", 1, [[0, 24001]])
	var sh := BtCombat.shooters_of(s, t, gun)
	assert_eq(sh.size(), 1, "only the front model reaches")
	assert_eq(sh[0], PackedInt64Array([0, 24001 * 24001]), "it is model 0 with its best d2")
	var t3 := _sq(st, "1:2", "mech", 1, [[0, 24002]])
	assert_eq(BtCombat.shooters_of(s, t3, gun).size(), 0, "24 inches + 2 MI is out, however big the target's base (r 1500)")
	# each shooter measures to its own nearest target model (here the far-side one for all three)
	var t4 := _sq(st, "1:3", "infantry", 1, [[0, 22999], [20000, -2000]])
	var sh4 := BtCombat.shooters_of(s, t4, gun)
	assert_eq(sh4.size(), 3, "all three reach")
	assert_eq(sh4[0], PackedInt64Array([0, 20000 * 20000 + 2000 * 2000]), "model 0: the (20000, -2000) model is nearer than (0, 22999)")
	assert_eq(sh4[1], PackedInt64Array([1, 20000 * 20000 + 1000 * 1000]), "model 1")
	assert_eq(sh4[2], PackedInt64Array([2, 20000 * 20000]), "model 2 straight across")
	var empty := _sq(st, "1:4", "infantry", 1, [])
	assert_eq(BtCombat.shooters_of(s, empty, gun).size(), 0, "an empty target is out of range")
	assert_eq(BtCombat.shooters_of(s, t, {}).size(), 0, "a weapon without rng reaches nobody")
	assert_eq(BtCombat.shooters_of(null, t, gun).size() + BtCombat.shooters_of(s, null, gun).size(), 0, "no squad, no shooters")
	var stacked := _sq(st, "1:5", "infantry", 1, [[0, 0]])
	assert_eq(BtCombat.shooters_of(s, stacked, gun)[0], PackedInt64Array([0, 0]), "zero distance is in range")


func test_pain_pact_marked() -> void:
	var de := _find(func(t: Dictionary) -> bool: return str(t["fac"]) == "de")
	var cx := _find(func(t: Dictionary) -> bool: return str(t["fac"]) == "cx")
	var st := _st(2)
	assert_false(BtCombat.pain_on(st, GameData.index_of(de)), "no pain in round 2")
	st.round_no = 3
	assert_true(BtCombat.pain_on(st, GameData.index_of(de)), "pain from round 3 (PAIN_ROUND)")
	st.round_no = 5
	assert_true(BtCombat.pain_on(st, GameData.index_of(de)), "and after")
	assert_false(BtCombat.pain_on(st, GameData.index_of("infantry")), "other armies feel no pain")
	assert_false(BtCombat.pain_on(st, -1), "nor an unknown type")
	assert_true(BtCombat.pact_on(GameData.index_of(cx)), "the cx army has the pact")
	assert_false(BtCombat.pact_on(GameData.index_of(de)) or BtCombat.pact_on(-1), "others do not")
	var t := _sq(st, "1:0", "infantry", 1, [[0, 0]])
	assert_false(BtCombat.marked(st, t), "a fresh squad is not marked (mk -1)")
	t.mk = st.mark_key()
	assert_true(BtCombat.marked(st, t), "marked this turn")
	st.turn = 1
	assert_false(BtCombat.marked(st, t), "the mark is gone next turn")
	st.turn = 0
	st.round_no = 6
	assert_false(BtCombat.marked(st, t), "and next round")
	assert_false(BtCombat.marked(st, null), "no squad is not marked")


func test_in_aura_boundary() -> void:
	var st := _st()
	assert_eq(BtAbilities.text(GameData.index_of("cmdr"), "aura"), "hit", "the commander carries the hit aura")
	var cmdr := _sq(st, "0:0", "cmdr", 0, [[0, 0]])
	var near := _sq(st, "0:1", "infantry", 0, [[6001, 0], [20000, 0]])
	var far := _sq(st, "0:2", "infantry", 0, [[0, 6002]])
	var diag := _sq(st, "0:3", "infantry", 0, [[-3600, -4801]])
	var foe := _sq(st, "1:0", "infantry", 1, [[10, 0]])
	assert_true(BtCombat.in_aura(st, cmdr, "hit"), "the bearer stands in its own aura")
	assert_true(BtCombat.in_aura(st, near, "hit"), "6 inches + 1 MI centre to centre is inside (nearest model)")
	assert_false(BtCombat.in_aura(st, far, "hit"), "6 inches + 2 MI is outside")
	assert_true(BtCombat.in_aura(st, diag, "hit"), "a diagonal of 6000.8 MI is inside")
	assert_false(BtCombat.in_aura(st, foe, "hit"), "another side never shares the aura")
	assert_false(BtCombat.in_aura(st, near, "ld"), "another kind is not this aura")
	assert_false(BtCombat.in_aura(st, near, ""), "an empty kind matches no squad (types without aura included)")
	assert_false(BtCombat.in_aura(st, null, "hit"), "no squad is in no aura")
	st.remove_unit(cmdr.models[0])
	assert_false(BtCombat.in_aura(st, near, "hit"), "a dead bearer gives no aura")
	st.free_fire = true
	_sq(st, "1:1", "cmdr", 1, [[0, 0]])
	assert_true(BtCombat.in_aura(st, foe, "hit"), "free fire: the other side's bearer helps its own side")
	assert_false(BtCombat.in_aura(st, near, "hit"), "and never ours: auras are per side")


# ------------------------------------------------------------------ hand cases: atk_math
func test_atk_math_shoot_basics_and_rf_half_range() -> void:
	var st := _st()
	var g := _gun("infantry")
	assert_true(int(g["rf"]) == 1 and int(g["a"]) == 1 and int(g["bs"]) == 4 and int(g["s"]) == 3, "infantry gun: a 1, bs 4, s 3, rf 1")
	var s := _sq(st, "0:0", "infantry", 0, [[0, 0], [0, -10000], [0, -20000]])
	var t := _sq(st, "1:0", "heavy", 1, [[0, 12001]])
	var m := BtCombat.atk_math(st, s, t, SHOOT)
	assert_eq(m["shots"], 3, "half range + 1 MI gives rf (1 + 1), 22001 gives 1, 32001 is out")
	assert_eq(Array(m["who"] as PackedStringArray), ["0:0.0", "0:0.1"], "who: the shooters in models order")
	assert_eq(m["need"], 4, "bs 4, no modifier")
	assert_eq(m["wneed"], 5, "S3 against T4 wounds on 5")
	assert_eq(m["sv"], 3, "heavy save 3+ with ap 0")
	assert_eq(m["dmg"], 1, "damage 1")
	assert_eq(m["su"], 0, "no sustained hits")
	assert_false(m["melee"] or m["tr"] or m["lh"] or m["dw"] or m["heel"] or m["mk"], "no keyword flags")
	assert_eq(m["mod"], 0, "mod 0")
	assert_eq(m["d2"], 12001 * 12001, "d2 is the squads' nearest pair")
	var keys: Array = m.keys()
	assert_eq(keys, ["melee", "shots", "need", "wneed", "mod", "sv", "dmg", "su", "tr", "lh", "dw", "heel", "mk", "who", "d2"], "result keys in the spec's order")
	var t2 := _sq(st, "1:1", "heavy", 1, [[0, 12002]])
	assert_eq(BtCombat.atk_math(st, s, t2, SHOOT)["shots"], 2, "half range + 2 MI: no rf")
	var t3 := _sq(st, "1:2", "heavy", 1, [[0, 11000], [0, 30000]])
	assert_eq(BtCombat.atk_math(st, s, t3, SHOOT)["shots"], 2 + 1, "each shooter's own nearest target model decides rf (11000: 2, 21000: 1, 31000: out)")
	# an odd range (9 inches) is centre to centre too: 9001 in, 9002 out
	assert_eq(int(_gun("peltast")["rng"]), 9, "the peltast throws 9 inches")
	var pel := _sq(st, "0:1", "peltast", 0, [[60000, 0]])
	var in9 := _sq(st, "1:3", "heavy", 1, [[69001, 0]])
	var out9 := _sq(st, "1:4", "heavy", 1, [[60000, -9002]])
	assert_eq(BtCombat.atk_math(st, pel, in9, SHOOT)["shots"], 1, "9 inches + 1 MI is in range")
	var none := BtCombat.atk_math(st, pel, out9, SHOOT)
	assert_eq([none.is_empty(), none.get("shots", -1), (none.get("who", PackedStringArray()) as PackedStringArray).size()], [false, 0, 0],
		"9 inches + 2 MI: a result with 0 shots and nobody shooting (mk_atk then makes no attack)")


func test_atk_math_no_weapon_and_empty() -> void:
	var st := _st()
	var hop := _sq(st, "0:0", "hoplite", 0, [[0, 0]])
	var t := _sq(st, "1:0", "infantry", 1, [[3000, 0]])
	assert_true(BtCombat.atk_math(st, hop, t, SHOOT).is_empty(), "no gun: no shooting result ({})")
	assert_true(BtCombat.atk_math(st, hop, t, OW).is_empty(), "no gun: no overwatch result")
	assert_false(BtCombat.atk_math(st, hop, t, FIGHT).is_empty(), "every type fights")
	var dead := _sq(st, "1:1", "infantry", 1, [])
	var m := BtCombat.atk_math(st, hop, dead, FIGHT)
	assert_eq(m["shots"], int(_mel("hoplite")["a"]), "melee shots do not depend on the target being alive")
	assert_eq(m["d2"], BattleState.FAR2, "d2 to an empty squad is FAR2")
	assert_eq(BtCombat.atk_math(st, _sq(st, "0:1", "infantry", 0, [[0, 0]]), dead, SHOOT)["shots"], 0, "shooting at an empty squad: 0 shots")
	assert_eq(BtCombat.atk_math(st, _sq(st, "0:2", "infantry", 0, []), t, FIGHT)["shots"], 0, "an empty attacker: 0 shots")
	assert_true(BtCombat.atk_math(st, null, t, FIGHT).is_empty() and BtCombat.atk_math(st, hop, null, FIGHT).is_empty(), "no squad: {}")


func test_atk_math_heavy_still() -> void:
	var st := _st()
	assert_true(BtAbilities.wflag(_gun("archer"), "hv") and int(_gun("archer")["bs"]) == 4, "archers: hv, bs 4")
	var s := _sq(st, "0:0", "archer", 0, [[0, 0]])
	var t := _sq(st, "1:0", "infantry", 1, [[10000, 0]])
	s.still = true
	assert_eq([BtCombat.atk_math(st, s, t, SHOOT)["mod"], BtCombat.atk_math(st, s, t, SHOOT)["need"]], [1, 3], "standing still: +1, need 3")
	assert_eq(BtCombat.atk_math(st, s, t, OW)["mod"], 1, "hv counts for overwatch too (need stays 6)")
	assert_eq(BtCombat.atk_math(st, s, t, OW)["need"], 6, "overwatch hits on 6 only")
	assert_eq(BtCombat.atk_math(st, s, t, FIGHT)["mod"], 0, "hv is a gun keyword: no melee bonus")
	s.still = false
	assert_eq([BtCombat.atk_math(st, s, t, SHOOT)["mod"], BtCombat.atk_math(st, s, t, SHOOT)["need"]], [0, 4], "after moving: need 4")


func test_atk_math_auras_hit_veil_bless() -> void:
	var st := _st()
	var veil := _find(func(t: Dictionary) -> bool: return str(t.get("aura", "")) == "veil")
	var s := _sq(st, "0:0", "infantry", 0, [[0, 0]])
	var t := _sq(st, "1:0", "infantry", 1, [[10000, 0]])
	_sq(st, "0:1", "cmdr", 0, [[-6001, 0]])
	var m := BtCombat.atk_math(st, s, t, SHOOT)
	assert_eq([m["mod"], m["need"]], [1, 3], "a hit aura 6 inches + 1 MI away: +1, need 3")
	assert_eq(BtCombat.atk_math(st, s, t, FIGHT)["mod"], 1, "the hit aura helps in melee too")
	assert_eq(BtCombat.atk_math(st, s, t, OW)["mod"], 1, "and in overwatch (need stays 6)")
	# veil around the target: shooting -1, melee and overwatch untouched
	var vq := _sq(st, "1:1", veil, 1, [[16000, 0]])
	m = BtCombat.atk_math(st, s, t, SHOOT)
	assert_eq(m["mod"], 0, "hit +1 and veil -1 cancel")
	assert_eq(BtCombat.atk_math(st, s, t, FIGHT)["mod"], 1, "veil does not protect in melee")
	assert_eq(BtCombat.atk_math(st, s, t, OW)["mod"], 1, "nor against overwatch")
	st.remove_unit(vq.models[0])
	assert_eq(BtCombat.atk_math(st, s, t, SHOOT)["mod"], 1, "a dead veil bearer protects nobody")
	# bless around the target: invulnerable 5+ when it is better
	var sn := _sq(st, "0:2", "sniper", 0, [[0, 30000]])
	assert_eq(int(_gun("sniper")["ap"]), 2, "the sniper has ap 2")
	var tb := _sq(st, "1:2", "infantry", 1, [[0, 40000]])
	assert_eq(BtCombat.atk_math(st, sn, tb, SHOOT)["sv"], 7, "infantry save 5 + ap 2 = 7 (no save)")
	_sq(st, "1:3", "templar", 1, [[6001, 40000]])
	assert_eq(BtCombat.atk_math(st, sn, tb, SHOOT)["sv"], 5, "blessed: invulnerable 5+ (BLESS_INV)")
	var med := _sq(st, "1:4", "medusa", 1, [[0, 42000]])
	assert_eq(int(GameData.ty("medusa")["inv"]), 4, "medusa has her own 4++")
	assert_eq(BtCombat.atk_math(st, sn, med, SHOOT)["sv"], 4, "blessing never worsens a better invulnerable save")


func test_atk_math_stealth_and_clamp() -> void:
	var st := _st()
	var a := _sq(st, "0:0", "archer", 0, [[0, 0]])
	var nj := _sq(st, "1:0", "ninja", 1, [[10000, 0]])
	assert_true(BtAbilities.flag(nj.ti, "st"), "ninjas have st")
	a.still = false
	var m := BtCombat.atk_math(st, a, nj, SHOOT)
	assert_eq([m["mod"], m["need"]], [-1, 5], "shooting at st: -1, need 5")
	assert_eq(BtCombat.atk_math(st, a, nj, OW)["mod"], 0, "st does not count against overwatch")
	assert_eq(BtCombat.atk_math(st, a, nj, FIGHT)["mod"], 0, "nor in melee")
	a.still = true
	assert_eq(BtCombat.atk_math(st, a, nj, SHOOT)["mod"], 0, "hv still +1 and st -1 cancel")
	_sq(st, "0:1", "cmdr", 0, [[0, 3000]])
	nj.mk = st.mark_key()
	m = BtCombat.atk_math(st, a, nj, SHOOT)
	assert_eq([m["mod"], m["need"]], [1, 3], "hv +1, aura +1, marked +1, st -1 = 2, clamped to +1")
	var far_veil := _sq(st, "1:1", _find(func(t: Dictionary) -> bool: return str(t.get("aura", "")) == "veil"), 1, [[10000, 6000]])
	a.still = false
	nj.mk = -1
	st.remove_unit(st.squad("0:1").models[0])
	m = BtCombat.atk_math(st, a, nj, SHOOT)
	assert_eq([m["mod"], m["need"]], [-1, 5], "st -1 and veil -1 = -2, clamped to -1")
	assert_eq(far_veil.models.size(), 1, "veil bearer placed")


func test_atk_math_pain_from_round_three() -> void:
	var de := _find(func(t: Dictionary) -> bool: return str(t["fac"]) == "de" and t["mel"] is Dictionary and int(t["mel"]["ws"]) == 3 and t["gun"] is Dictionary)
	var ws := int(_mel(de)["ws"])
	var bs := int(_gun(de)["bs"])
	for rd: int in [1, 2, 3, 4]:
		var st := _st(rd)
		var s := _sq(st, "0:0", de, 0, [[0, 0]])
		var t := _sq(st, "1:0", "infantry", 1, [[2000, 0]])
		var on := rd >= 3
		assert_eq(BtCombat.atk_math(st, s, t, FIGHT)["need"], ws - 1 if on else ws, "round %d: melee need %d" % [rd, ws - 1 if on else ws])
		assert_eq(BtCombat.atk_math(st, s, t, SHOOT)["mod"], 0, "round %d: pain never helps shooting" % rd)
		assert_eq(BtCombat.atk_math(st, s, t, SHOOT)["need"], BtCombat.clamp_need(bs), "round %d: shooting need is bs" % rd)


func test_atk_math_marked() -> void:
	var st := _st(2, 1)
	var s := _sq(st, "0:0", "infantry", 0, [[0, 0]])
	var t := _sq(st, "1:0", "heavy", 1, [[5000, 0]])
	t.mk = st.mark_key()
	assert_eq(BtCombat.atk_math(st, s, t, SHOOT)["mod"], 1, "shooting at a marked target: +1")
	assert_eq(BtCombat.atk_math(st, s, t, OW)["mod"], 0, "overwatch does not use the mark")
	assert_eq(BtCombat.atk_math(st, s, t, FIGHT)["mod"], 0, "melee does not use the mark")
	t.mk = st.mark_key() - 1
	assert_eq(BtCombat.atk_math(st, s, t, SHOOT)["mod"], 0, "an old mark is gone")


func test_atk_math_poison() -> void:
	var st := _st()
	var po := _find(func(t: Dictionary) -> bool: return t["gun"] is Dictionary and int(t["gun"].get("po", 0)) == 3 and int(t["gun"]["s"]) == 2)
	var s := _sq(st, "0:0", po, 0, [[0, 0]])
	var foot := _sq(st, "1:0", "infantry", 1, [[5000, 0]])
	var mech := _sq(st, "1:1", "mech", 1, [[0, 5000]])
	var cav := _sq(st, "1:2", "cavalry", 1, [[-5000, 0]])
	assert_eq(BtCombat.atk_math(st, s, foot, SHOOT)["wneed"], 3, "S2 vs T3 would be 5; poison 3+ against foot soldiers")
	assert_eq(BtCombat.atk_math(st, s, mech, SHOOT)["wneed"], 6, "poison does nothing to a machine (not inf): S2 vs T10 = 6")
	assert_eq(BtCombat.atk_math(st, s, cav, SHOOT)["wneed"], 6, "nor to riders (not inf): S2 vs T5 = 6")
	# melee poison 4+ with S4 against T3: the normal 3+ is better and stays
	var mp := _find(func(t: Dictionary) -> bool: return t["mel"] is Dictionary and int(t["mel"].get("po", 0)) == 4 and int(t["mel"]["s"]) == 4)
	var ms := _sq(st, "0:1", mp, 0, [[0, -3000]])
	assert_eq(BtCombat.atk_math(st, ms, foot, FIGHT)["wneed"], 3, "melee poison 4+ never makes a 3+ worse")
	var lo := _sq(st, "1:3", "levy", 1, [[0, -4000]])
	assert_eq(int(GameData.ty("levy")["T"]), 3, "levy toughness 3")
	assert_eq(BtCombat.atk_math(st, s, lo, SHOOT)["wneed"], 3, "poison 3+ against any foot soldier")


func test_atk_math_lance_and_fury() -> void:
	var st := _st()
	assert_true(BtAbilities.wflag(_mel("cavalry"), "la") and int(_mel("cavalry")["s"]) == 5, "cavalry lances: la, S5")
	var cav := _sq(st, "0:0", "cavalry", 0, [[0, 0], [2200, 0]])
	var t := _sq(st, "1:0", "heavy", 1, [[0, 3000]])
	assert_eq(BtCombat.atk_math(st, cav, t, FIGHT)["wneed"], 3, "S5 vs T4: 3")
	cav.charged = true
	assert_eq(BtCombat.atk_math(st, cav, t, FIGHT)["wneed"], 2, "charged with a lance: 2")
	var hammer := _sq(st, "0:1", "infantry", 0, [[0, -3000]])
	hammer.charged = true
	assert_eq(BtCombat.atk_math(st, hammer, t, FIGHT)["wneed"], BtCombat.wound_need(3, 4), "no lance: charging changes nothing")
	# fury: ca and charged adds one attack per model
	assert_true(BtAbilities.flag(GameData.index_of("boy"), "ca") and int(_mel("boy")["a"]) == 2, "the boys have ca, 2 attacks")
	var boys := _sq(st, "0:2", "boy", 0, [[0, 9000], [1700, 9000], [3400, 9000]])
	assert_eq(BtCombat.atk_math(st, boys, t, FIGHT)["shots"], 6, "not charged: 3 x 2")
	boys.charged = true
	assert_eq(BtCombat.atk_math(st, boys, t, FIGHT)["shots"], 9, "charged: 3 x (2 + 1)")
	assert_eq(Array(BtCombat.atk_math(st, boys, t, FIGHT)["who"] as PackedStringArray), ["0:2.0", "0:2.1", "0:2.2"], "every model fights")
	assert_eq(BtCombat.atk_math(st, boys, t, SHOOT)["shots"], 3, "fury is melee only (3 pistols, 1 each)")
	cav.charged = false
	assert_eq(BtCombat.atk_math(st, cav, t, FIGHT)["shots"], 2 * int(_mel("cavalry")["a"]), "cavalry without ca: no extra attack")


func test_atk_math_aoc_and_inv() -> void:
	var st := _st()
	var inf := _sq(st, "0:0", "infantry", 0, [[0, 0]])
	var sn := _sq(st, "0:1", "sniper", 0, [[0, 1000]])
	var kn := _sq(st, "1:0", "knight", 1, [[0, 10000]])
	assert_true(BtAbilities.flag(kn.ti, "aoc") and int(GameData.ty("knight")["sv"]) == 3, "knights: aoc, save 3")
	assert_eq(BtCombat.atk_math(st, inf, kn, SHOOT)["sv"], 3, "ap 0 - 1 floors at 0: save stays 3")
	assert_eq(BtCombat.atk_math(st, sn, kn, SHOOT)["sv"], 4, "ap 2 - 1 = 1: save 4")
	var med := _sq(st, "1:1", "medusa", 1, [[10000, 0]])
	assert_eq(int(GameData.ty("medusa")["sv"]), 5, "medusa armour 5")
	assert_eq(BtCombat.atk_math(st, inf, med, SHOOT)["sv"], 4, "invulnerable 4++ is better than armour 5")
	assert_eq(BtCombat.atk_math(st, sn, med, SHOOT)["sv"], 4, "ap cannot touch the invulnerable save")
	var hv := _sq(st, "1:2", "heavy", 1, [[-10000, 0]])
	assert_eq(BtCombat.atk_math(st, _sq(st, "0:2", "mech", 0, [[-12000, 0]]), hv, SHOOT)["sv"], 6, "mech ap 3 on armour 3, no invulnerable: 6")
	var dmr := _find(func(t: Dictionary) -> bool: return int(t["sv"]) == 7 and int(t.get("inv", 0)) == 5)
	assert_eq(BtCombat.atk_math(st, inf, _sq(st, "1:3", dmr, 1, [[0, -10000]]), SHOOT)["sv"], 5, "no armour (7) but 5++")


func test_atk_math_torrent_overwatch_blast() -> void:
	var st := _st()
	var fl := _sq(st, "0:0", "flamer", 0, [[0, 0], [1700, 0]])
	assert_true(BtAbilities.wflag(_gun("flamer"), "tr"), "flamers are torrent")
	var t := _sq(st, "1:0", "ninja", 1, [[0, 5000]])
	var m := BtCombat.atk_math(st, fl, t, SHOOT)
	assert_eq([m["need"], m["tr"]], [0, true], "torrent: need 0, tr set (even against st)")
	assert_eq(m["mod"], -1, "the modifier is still worked out")
	assert_eq(BtCombat.atk_math(st, fl, t, OW)["need"], 0, "torrent overwatch also hits automatically")
	var inf := _sq(st, "0:1", "infantry", 0, [[0, -2000]])
	assert_eq(BtCombat.atk_math(st, inf, t, OW)["need"], 6, "overwatch hits on 6s only")
	assert_eq(BtCombat.atk_math(st, inf, t, OW)["shots"], 1 + 1, "overwatch still gets rf inside half range")
	# blast: a + one per five models in the target
	var bl := _find(func(t: Dictionary) -> bool: return t["gun"] is Dictionary and int(t["gun"].get("bl", 0)) == 1 and int(t["n"]) == 1)
	var a := int(_gun(bl)["a"])
	var rng := int(_gun(bl)["rng"])
	var bs := _sq(st, "0:2", bl, 0, [[0, -40000]])
	var pts: Array = []
	for i: int in 10:
		pts.append([i * 1700, -40000 + rng * 1000 - 5000])
	var levy := _sq(st, "1:1", "levy", 1, pts)
	assert_eq(BtCombat.atk_math(st, bs, levy, SHOOT)["shots"], a + 2, "ten targets: +2")
	st.remove_unit(levy.models[0])
	assert_eq(BtCombat.atk_math(st, bs, levy, SHOOT)["shots"], a + 1, "nine targets: +1")
	for i: int in 5:
		st.remove_unit(levy.models[0])
	assert_eq(BtCombat.atk_math(st, bs, levy, SHOOT)["shots"], a, "four targets: +0")
	var two := _sq(st, "0:3", bl, 0, [[3000, -40000]])
	var many: Array = []
	for i: int in 15:
		many.append([i * 1000, -40000 + 3000])
	assert_eq(BtCombat.atk_math(st, two, _sq(st, "1:2", "levy", 1, many), SHOOT)["shots"], a + 3, "fifteen targets: +3 (one per five)")


func test_atk_math_carried_keywords() -> void:
	var st := _st()
	var t := _sq(st, "1:0", "infantry", 1, [[0, 5000]])
	var cx := _find(func(q: Dictionary) -> bool: return str(q["fac"]) == "cx" and q["gun"] is Dictionary and int(q["gun"].get("su", 0)) == 0)
	var c := _sq(st, "0:0", cx, 0, [[0, 0]])
	assert_eq(BtCombat.atk_math(st, c, t, FIGHT)["su"], 1, "the pact: melee sixes give an extra hit (su 1)")
	assert_eq(BtCombat.atk_math(st, c, t, SHOOT)["su"], 0, "but not when shooting")
	var hmg := _sq(st, "0:1", "hmg", 0, [[0, -1000]])
	assert_eq(BtCombat.atk_math(st, hmg, t, SHOOT)["su"], 1, "a weapon with su keeps it")
	assert_eq(BtCombat.atk_math(st, _sq(st, "0:2", "samurai", 0, [[0, 2000]]), t, FIGHT)["lh"], true, "lh carried")
	var md := _sq(st, "0:3", "medusa", 0, [[0, -2000]])
	assert_eq([BtCombat.atk_math(st, md, t, SHOOT)["dw"], BtCombat.atk_math(st, md, t, SHOOT)["dmg"]], [true, 3], "dw and damage 3 carried")
	assert_eq(BtCombat.atk_math(st, md, _sq(st, "1:1", "achil", 1, [[0, 6000]]), SHOOT)["heel"], true, "heel comes from the defender")
	assert_eq(BtCombat.atk_math(st, md, t, SHOOT)["heel"], false, "others have none")
	var mk := _find(func(q: Dictionary) -> bool: return q["gun"] is Dictionary and int(q["gun"].get("mk", 0)) == 1)
	var mks := _sq(st, "0:4", mk, 0, [[0, 3000]])
	assert_true(BtCombat.atk_math(st, mks, t, SHOOT)["mk"], "a designator marks when shooting")
	assert_false(BtCombat.atk_math(st, mks, t, OW)["mk"], "not in overwatch")
	assert_false(BtCombat.atk_math(st, mks, t, FIGHT)["mk"], "not in melee")
	assert_eq(BtCombat.atk_math(st, md, t, FIGHT)["dmg"], int(_mel("medusa")["d"]), "melee uses the melee weapon's damage")
	assert_eq(BtCombat.atk_math(st, md, t, FIGHT)["dw"], false, "and its keywords (no dw in melee)")


# ------------------------------------------------------------------ hand cases: why-nots in page order
func test_shot_why_not_order() -> void:
	var st := _st()
	var hop := _sq(st, "0:0", "hoplite", 0, [[0, 0]])
	var mate := _sq(st, "0:1", "infantry", 0, [[3000, 0]])
	var s := _sq(st, "0:2", "infantry", 0, [[0, 10000]])
	var t := _sq(st, "1:0", "heavy", 1, [[0, 20000]])
	assert_eq(_key(BtCombat.shot_why_not(st, s, t)), "", "a clear shot")
	assert_eq(BtCombat.shot_why_not(st, s, t)["args"], [], "no args when allowed")
	hop.shot = true
	assert_eq(_key(BtCombat.shot_why_not(st, hop, mate)), "no_gun", "no gun comes first (before own side and already shot)")
	s.shot = true
	s.fell = true
	s.adv = true
	assert_eq(_key(BtCombat.shot_why_not(st, s, mate)), "own_side", "own side before already shot")
	assert_eq(_key(BtCombat.shot_why_not(st, s, s)), "own_side", "never at itself")
	assert_eq(_key(BtCombat.shot_why_not(st, s, null)), "own_side", "no target: own_side (canTarget fails)")
	assert_eq(_key(BtCombat.shot_why_not(st, s, t)), "already_shot", "already shot before fell back")
	s.shot = false
	assert_eq(_key(BtCombat.shot_why_not(st, s, t)), "fell_back", "fell back before advanced")
	s.fell = false
	assert_eq(_key(BtCombat.shot_why_not(st, s, t)), "advanced", "advanced without an assault weapon")
	st.free_fire = true
	assert_eq(_key(BtCombat.shot_why_not(st, s, mate)), "advanced", "free fire: a team-mate is a target")
	st.free_fire = false
	s.adv = false
	t.models[0].z = 34002
	var far := BtCombat.shot_why_not(st, s, t)
	assert_eq(far, {"key": "too_far", "args": [24002, 24]}, "24 inches + 2 MI: too far [dist MI, range in]")
	t.models[0].z = 34001
	assert_eq(_key(BtCombat.shot_why_not(st, s, t)), "", "24 inches + 1 MI: allowed")


func test_shot_why_not_flyers_titans_assault_elves() -> void:
	var st := _st()
	var t := _sq(st, "1:0", "infantry", 1, [[0, 10000]])
	var fly := _find(func(q: Dictionary) -> bool: return q.has("fly") and not q.has("ttn") and q["gun"] is Dictionary and not int(q["gun"].get("as", 0)) and str(q["fac"]) != "el")
	var f := _sq(st, "0:0", fly, 0, [[0, 0]])
	f.fell = true
	assert_eq(_key(BtCombat.shot_why_not(st, f, t)), "", "a flyer shoots after falling back")
	f.adv = true
	assert_eq(_key(BtCombat.shot_why_not(st, f, t)), "advanced", "but not after advancing (no assault weapon)")
	var asn := _sq(st, "0:1", "enemy", 0, [[2000, 0]])
	assert_true(BtAbilities.wflag(_gun("enemy"), "as"), "this gun is an assault weapon")
	asn.adv = true
	assert_eq(_key(BtCombat.shot_why_not(st, asn, t)), "", "an assault weapon shoots after advancing")
	asn.fell = true
	assert_eq(_key(BtCombat.shot_why_not(st, asn, t)), "fell_back", "but not after falling back")
	var el := _find(func(q: Dictionary) -> bool: return str(q["fac"]) == "el" and q["gun"] is Dictionary and not int(q["gun"].get("as", 0)) and not q.has("fly"))
	var e := _sq(st, "0:2", el, 0, [[-2000, 0]])
	e.adv = true
	assert_eq(_key(BtCombat.shot_why_not(st, e, t)), "", "space elves shoot after advancing (army rule)")
	var ttn := _find(func(q: Dictionary) -> bool: return q.has("ttn") and q["gun"] is Dictionary)
	var big := _sq(st, "0:3", ttn, 0, [[5000, 0]])
	big.fell = true
	assert_eq(_key(BtCombat.shot_why_not(st, big, t)), "", "a titan shoots after falling back")
	big.adv = true
	assert_eq(_key(BtCombat.shot_why_not(st, big, t)), "" if BtAbilities.wflag(_gun(ttn), "as") else "advanced", "but advancing still needs an assault weapon")


func test_shot_why_not_engagement() -> void:
	var st := _st()
	# s (infantry, r 800) engaged with e: edge exactly 1 inch + 1 MI (centres 2601 apart)
	var s := _sq(st, "0:0", "infantry", 0, [[0, 0]])
	var e := _sq(st, "1:0", "infantry", 1, [[2601, 0]])
	var t := _sq(st, "1:1", "heavy", 1, [[0, 10000]])
	assert_eq(BtCombat.shot_why_not(st, s, t), {"key": "engaged", "args": [0]}, "engaged: cannot shoot (no pistol)")
	assert_eq(BtCombat.shot_why_not(st, s, e), {"key": "engaged", "args": [0]}, "not even the squad it is engaged with")
	e.models[0].x = 2602
	assert_eq(_key(BtCombat.shot_why_not(st, s, t)), "", "edge 1 inch + 2 MI is not engaged")
	e.models[0].x = 2601
	var p := _sq(st, "0:1", "medic", 0, [[0, -20000]])
	assert_true(BtAbilities.wflag(_gun("medic"), "pi"), "the medic carries a pistol")
	var pe := _sq(st, "1:2", "infantry", 1, [[2601, -20000]])
	assert_eq(_key(BtCombat.shot_why_not(st, p, pe)), "", "a pistol shoots the squad it is engaged with")
	assert_eq(BtCombat.shot_why_not(st, p, t), {"key": "engaged", "args": [1]}, "but nobody else [pistol 1]")
	var ttn := _find(func(q: Dictionary) -> bool: return q.has("ttn") and q["gun"] is Dictionary)
	var r := BtSquads.radius_of(GameData.index_of(ttn))
	var big := _sq(st, "0:2", ttn, 0, [[40000, 0]])
	_sq(st, "1:3", "infantry", 1, [[40000 + r + 800 + 500, 0]])
	var near_t := _sq(st, "1:4", "infantry", 1, [[40000, 9000]])
	assert_true(BtSquads.is_engaged(st, big), "the titan is engaged")
	assert_eq(_key(BtCombat.shot_why_not(st, big, near_t)), "", "a titan shoots while engaged")
	# the target fights a squad of our side: no shot, unless we are engaged ourselves (that check is skipped then)
	var free := _sq(st, "0:3", "infantry", 0, [[-30000, 0]])
	var fighting := _sq(st, "1:5", "heavy", 1, [[-30000, 15000]])
	var ours := _sq(st, "0:4", "infantry", 0, [[-30000, 15000 + 2601]])
	assert_eq(_key(BtCombat.shot_why_not(st, free, fighting)), "target_engaged", "the target is in melee with our side (edge 1 inch + 1 MI)")
	ours.models[0].z = 15000 + 2602
	assert_eq(_key(BtCombat.shot_why_not(st, free, fighting)), "", "edge 1 inch + 2 MI: free to shoot")
	ours.models[0].z = 15000 + 2601
	var other := _sq(st, "2:0", "heavy", 2, [[-30000, -15000]])
	_sq(st, "1:6", "infantry", 1, [[-30000, -15000 - 2601]])
	assert_eq(_key(BtCombat.shot_why_not(st, free, other)), "", "a target in melee with a third side may be shot")
	assert_eq(_key(BtCombat.shot_why_not(st, p, fighting)), "engaged", "an engaged shooter gets engaged, never target_engaged")


func test_heal_order() -> void:
	var st := _st()
	assert_eq(int(GameData.ty("medic")["heal"]), 3, "the medic heals within 3 inches")
	var med := _sq(st, "0:0", "medic", 0, [[0, 0]])
	var hurt := _sq(st, "0:1", "heavy", 0, [[3001, 0]], 1)
	var whole := _sq(st, "0:2", "heavy", 0, [[0, 3001], [1700, 3001], [3400, 3001]])
	var short := _sq(st, "0:3", "infantry", 0, [[0, -3001]])
	var foe := _sq(st, "1:0", "heavy", 1, [[-3001, 0]], 1)
	assert_true(BtCombat.can_heal(st, med, hurt), "a hurt friend 3 inches + 1 MI away")
	assert_eq(BtCombat.heal_why_not(st, med, hurt), {"key": "", "args": []}, "allowed")
	assert_false(BtCombat.can_heal(st, med, whole), "nobody hurt, nobody lost")
	assert_eq(_key(BtCombat.heal_why_not(st, med, whole)), "nobody_hurt", "nobody_hurt")
	assert_true(BtCombat.can_heal(st, med, short), "a squad that lost models can be healed (1 of 5 left)")
	hurt.models[0].x = 3002
	assert_false(BtCombat.can_heal(st, med, hurt), "3 inches + 2 MI is too far (centre to centre)")
	assert_eq(BtCombat.heal_why_not(st, med, hurt), {"key": "too_far", "args": [3]}, "too far [heal in]")
	assert_false(BtCombat.can_heal(st, med, foe), "never the enemy")
	assert_eq(_key(BtCombat.heal_why_not(st, med, foe)), "too_far", "the page then says too far (it has no other reason)")
	assert_true(BtCombat.can_heal(st, med, med) == false, "the medic itself is not hurt")
	med.models[0].hp = 1
	assert_true(BtCombat.can_heal(st, med, med), "a hurt medic heals itself (distance 0)")
	med.fell = true
	assert_false(BtCombat.can_heal(st, med, short), "not after falling back")
	assert_eq(_key(BtCombat.heal_why_not(st, med, short)), "too_far", "the page reports too far for that too")
	med.fell = false
	med.shot = true
	assert_eq(_key(BtCombat.heal_why_not(st, med, short)), "already_acted", "already acted comes before the rest")
	assert_eq(_key(BtCombat.heal_why_not(st, med, whole)), "already_acted", "even when nobody is hurt")
	var inf := _sq(st, "0:4", "infantry", 0, [[0, 1000]])
	assert_false(BtCombat.can_heal(st, inf, short), "not a healer")
	assert_eq(BtCombat.heal_why_not(st, inf, short), {"key": "too_far", "args": [0]}, "a non-healer gets too_far [0] (page parity)")
	assert_eq(_key(BtCombat.heal_why_not(st, inf, null)), "nobody_hurt", "no target: nobody to heal")
	var empty := _sq(st, "0:5", "heavy", 0, [])
	med.shot = false
	assert_false(BtCombat.can_heal(st, med, empty), "a wiped squad is out of reach")


func test_charge_why_not_order() -> void:
	var st := _st(2)
	var s := _sq(st, "0:0", "infantry", 0, [[0, 0]])
	var mate := _sq(st, "0:1", "infantry", 0, [[0, 5000]])
	# edge to edge: two 800 bases, edge exactly 12 inches + 1 MI at 13601 centres
	var t := _sq(st, "1:0", "infantry", 1, [[13601, 0]])
	assert_eq(BtCombat.charge_why_not(st, s, t), {"key": "", "args": []}, "edge 12 inches + 1 MI: allowed")
	t.models[0].x = 13602
	assert_eq(BtCombat.charge_why_not(st, s, t), {"key": "too_far", "args": [13602 - 1600]}, "edge 12 inches + 2 MI: too far [edge MI]")
	t.models[0].x = 13601
	s.ch_done = true
	s.adv = true
	s.fell = true
	assert_eq(_key(BtCombat.charge_why_not(st, s, mate)), "enemies_only", "own side first")
	st.free_fire = true
	assert_eq(_key(BtCombat.charge_why_not(st, s, mate)), "enemies_only", "free fire never allows charging a team-mate")
	st.free_fire = false
	assert_eq(_key(BtCombat.charge_why_not(st, s, null)), "enemies_only", "no target")
	assert_eq(_key(BtCombat.charge_why_not(st, s, t)), "charge_done", "charge done before advanced")
	s.ch_done = false
	assert_eq(_key(BtCombat.charge_why_not(st, s, t)), "advanced", "advanced before fell back")
	s.adv = false
	assert_eq(_key(BtCombat.charge_why_not(st, s, t)), "fell_back", "fell back before engaged")
	s.fell = false
	_sq(st, "2:0", "infantry", 2, [[0, -2601]])
	assert_eq(_key(BtCombat.charge_why_not(st, s, t)), "engaged", "engaged with anyone (a third side) before range")
	# who may charge after advancing or falling back
	var ac := _sq(st, "0:2", "hound", 0, [[-40000, 0]])
	var t2 := _sq(st, "1:1", "infantry", 1, [[-40000, 5000]])
	ac.adv = true
	assert_eq(_key(BtCombat.charge_why_not(st, ac, t2)), "", "ac charges after advancing")
	var de := _find(func(q: Dictionary) -> bool: return str(q["fac"]) == "de" and not q.has("ac") and not q.has("fly"))
	var d := _sq(st, "0:3", de, 0, [[40000, 0]])
	var t3 := _sq(st, "1:2", "infantry", 1, [[40000, 5000]])
	d.adv = true
	assert_eq(_key(BtCombat.charge_why_not(st, d, t3)), "advanced", "dark elves in round 2: no")
	st.round_no = 3
	assert_eq(_key(BtCombat.charge_why_not(st, d, t3)), "", "from round 3 (pain) they charge after advancing")
	d.adv = false
	d.fell = true
	assert_eq(_key(BtCombat.charge_why_not(st, d, t3)), "fell_back", "pain does not help after falling back")
	var fly := _find(func(q: Dictionary) -> bool: return q.has("fly") and not q.has("ac") and str(q["fac"]) != "de")
	var f := _sq(st, "0:4", fly, 0, [[0, 40000]])
	var t4 := _sq(st, "1:3", "infantry", 1, [[0, 45000]])
	f.fell = true
	assert_eq(_key(BtCombat.charge_why_not(st, f, t4)), "", "a flyer charges after falling back")
	f.adv = true
	assert_eq(_key(BtCombat.charge_why_not(st, f, t4)), "advanced", "but not after advancing")


func test_gren_why_not_order() -> void:
	var st := _st()
	var s := _sq(st, "0:0", "infantry", 0, [[0, 0]])
	var t := _sq(st, "1:0", "heavy", 1, [[8001, 0]])
	var mate := _sq(st, "0:1", "heavy", 0, [[0, 3000]])
	assert_eq(BtCombat.gren_why_not(st, s, t), {"key": "", "args": []}, "8 inches + 1 MI centre to centre: allowed")
	t.models[0].x = 8002
	assert_eq(BtCombat.gren_why_not(st, s, t), {"key": "too_far", "args": []}, "8 inches + 2 MI: too far")
	t.models[0].x = 8001
	assert_eq(_key(BtCombat.gren_why_not(st, _sq(st, "0:2", "cavalry", 0, [[0, -5000]]), t)), "not_infantry", "riders have no grenades")
	assert_eq(_key(BtCombat.gren_why_not(st, _sq(st, "0:3", "hoplite", 0, [[0, -8000]]), t)), "not_infantry", "nor foot soldiers without a gun")
	assert_eq(_key(BtCombat.gren_why_not(st, null, t)), "not_infantry", "no squad")
	s.shot = true
	s.adv = true
	assert_eq(_key(BtCombat.gren_why_not(st, s, mate)), "already_shot", "already shot before moved fast and own side")
	s.shot = false
	assert_eq(_key(BtCombat.gren_why_not(st, s, mate)), "moved_fast", "advanced")
	s.adv = false
	s.fell = true
	assert_eq(_key(BtCombat.gren_why_not(st, s, t)), "moved_fast", "fell back")
	s.fell = false
	var e := _sq(st, "2:0", "infantry", 2, [[-2601, 0]])
	assert_eq(_key(BtCombat.gren_why_not(st, s, mate)), "engaged", "engaged before own side")
	st.remove_unit(e.models[0])
	assert_eq(_key(BtCombat.gren_why_not(st, s, mate)), "enemies_only", "own side")
	st.free_fire = true
	assert_eq(_key(BtCombat.gren_why_not(st, s, mate)), "enemies_only", "even in free fire")
	assert_eq(_key(BtCombat.gren_why_not(st, s, t)), "", "the enemy in range")


func test_no_state_change() -> void:
	var st := _st(3, 1, true)
	var s := _sq(st, "0:0", "cmdr", 0, [[0, 0]])
	var t := _sq(st, "1:0", "infantry", 1, [[3000, 0], [4700, 0]], 1)
	var h := _sq(st, "1:1", "medic", 1, [[3000, 2000]])
	var before := st.digest()
	for how: int in [SHOOT, FIGHT, OW]:
		BtCombat.atk_math(st, s, t, how)
		BtCombat.atk_math(st, t, s, how)
	BtCombat.shot_why_not(st, s, t)
	BtCombat.charge_why_not(st, s, t)
	BtCombat.gren_why_not(st, s, t)
	BtCombat.heal_why_not(st, h, t)
	BtCombat.can_heal(st, h, t)
	BtCombat.in_aura(st, s, "hit")
	BtCombat.shooters_of(s, t, BtAbilities.gun(s.ti))
	assert_eq(st.digest(), before, "every BtCombat function only reads the state")


# ------------------------------------------------------------------ digest
func test_digest_pinned() -> void:
	var a := _digest_scenario()
	assert_eq(a, _digest_scenario(), "the scenario digest is stable within a run")
	assert_digest(a, PINNED_DIGEST, "BtCombat scenario digest is pinned")


## Every BtCombat function over the first twelve fixture worlds plus the wound table, folded into one FNV-1a 64 digest
## (ints only: atk_math fields, who as unit indexes, why-not keys hashed with their args).
func _digest_scenario() -> String:
	var v := PackedInt64Array()
	for s: int in range(1, 13):
		for t: int in range(1, 13):
			v.append(BtCombat.wound_need(s, t))
	var ins: Array = fx["worlds_in"]
	for wi: int in mini(12, ins.size()):
		var st := _world(ins[wi])
		for a: BattleState.Squad in st.squads:
			for kind: String in ["hit", "ld", "bless", "rez", "veil"]:
				v.append(1 if BtCombat.in_aura(st, a, kind) else 0)
			v.append(1 if BtCombat.marked(st, a) else 0)
			v.append(1 if BtCombat.pain_on(st, a.ti) else 0)
			v.append(1 if BtCombat.pact_on(a.ti) else 0)
			v.append(1 if BtCombat.inf(a.ti) else 0)
			for b: BattleState.Squad in st.squads:
				for how: int in [SHOOT, FIGHT, OW]:
					var m := BtCombat.atk_math(st, a, b, how)
					if m.is_empty():
						v.append(-1)
						continue
					for k: String in ["shots", "need", "wneed", "mod", "sv", "dmg", "su", "d2"]:
						v.append(int(m[k]))
					for k: String in ["melee", "tr", "lh", "dw", "heel", "mk"]:
						v.append(1 if m[k] else 0)
					for id: String in (m["who"] as PackedStringArray):
						v.append(st.unit_index(id))
				for x: PackedInt64Array in BtCombat.shooters_of(a, b, BtAbilities.gun(a.ti)):
					v.append_array(x)
				for d: Dictionary in [BtCombat.shot_why_not(st, a, b), BtCombat.heal_why_not(st, a, b),
						BtCombat.charge_why_not(st, a, b), BtCombat.gren_why_not(st, a, b)]:
					v.append(Hash.fnv1a64_str(str(d["key"])))
					for x: Variant in (d["args"] as Array):
						v.append(int(x))
				v.append(1 if BtCombat.can_heal(st, a, b) else 0)
	return Hash.digest_hex(v)
