extends "res://tests/testing.gd"
## core/battle/abilities.gd (BtAbilities, R1_PORT_SPEC §1.9, the registry part): FLAGS, WEAPON_KEYS, AURAS and ARMIES
## cover every field of types.json, every aura kind and every army; every handler names a real module function or one
## that a later (or parallel) wave writes (LATER); every handler that exists has a behavioural test in this file named
## test_<group>_<name> whose body calls it; the accessors read the data with the page's JavaScript truthiness.
## The wave-3 handlers (glory_heal, revive_one, wind_*, spawn_from, after_kills, refill_shields) are not written yet:
## once one exists, test_existing_handlers_have_behaviour_tests asks for its test here.

const TYPES_JSON := "res://data/types.json"
const SELF := "res://tests/unit/test_abilities.gd"
## Digest of every accessor over every datasheet plus the registry text (see _digest_scenario); changes only on purpose.
const PINNED_DIGEST := "01e902182e89e173"
## modules the registry may point to (R1_PORT_SPEC §1)
const MODULES := ["BtCombat", "BtAbilities", "BtSquads", "BtArmy", "BtPend", "BtTurn"]
## handlers that a later or parallel wave writes (wave number): they may be missing until then
const LATER := {
	"BtArmy.fit_list": 2, "BtArmy.fac_of": 2, "BtArmy.pts_of": 2, "BtArmy.slot_max": 2, "BtArmy.deploy": 2,
	"BtAbilities.glory_heal": 3, "BtAbilities.spawn_from": 3, "BtAbilities.after_kills": 3,
	"BtAbilities.refill_shields": 3, "BtAbilities.wind_turn": 3,
	"BtPend.finish_atk": 3, "BtPend.deal_damage": 3, "BtPend.apply_wnd": 3, "BtPend.apply_rez": 3,
	"BtPend.count_hits": 3, "BtPend.apply_hit": 3, "BtPend.apply_reroll": 3, "BtPend.mark_hit": 3,
	"BtTurn.start_turn": 4,
}
const SHOOT := BattleState.HOW_SHOOT
const FIGHT := BattleState.HOW_FIGHT
const OW := BattleState.HOW_OW

var raw_types: Array = []
var src := ""


func setup() -> void:
	var raw: Variant = JSON.parse_string(FileAccess.get_file_as_string(TYPES_JSON))
	raw_types = raw if raw is Array else []
	src = FileAccess.get_file_as_string(SELF)


# ------------------------------------------------------------------ helpers
func _st(round_no: int = 1) -> BattleState:
	var st := BattleState.make({"seed": 4, "w": 60, "teams": 3})
	st.round_no = round_no
	return st


func _sq(st: BattleState, id: String, k: String, side: int, pts: Array, hp: int = 0) -> BattleState.Squad:
	var t := GameData.ty(k)
	var s := st.add_squad(id, k, side, side, int(t.get("n", 1)), 0)
	for j: int in pts.size():
		var p: Array = pts[j]
		st.add_unit("%s.%d" % [id, j], s, hp if hp > 0 else int(t.get("w", 1)), int(p[0]), int(p[1]))
	return s


## First datasheet key in TYPES order for which pred(t) is true (hidden types skipped unless asked); "" if none.
func _find(pred: Callable, hidden: bool = false) -> String:
	for t: Dictionary in GameData.types():
		var k := str(t["k"])
		if (hidden or not GameData.is_hidden(k)) and bool(pred.call(t)):
			return k
	return ""


func _ti(k: String) -> int:
	return GameData.index_of(k)


func _key(d: Dictionary) -> String:
	return str(d.get("key", "?"))


## The script of a global class, or null while that module is not written.
func _module(cls: String) -> GDScript:
	for c: Dictionary in ProjectSettings.get_global_class_list():
		if str(c["class"]) == cls:
			return load(str(c["path"])) as GDScript
	return null


func _has(cls: String, fn: String) -> bool:
	var scr := _module(cls)
	if scr == null:
		return false
	for m: Dictionary in scr.get_script_method_list():
		if str(m["name"]) == fn:
			return true
	return false


## Every registry entry as [group, name, entry]: groups flag, weapon, aura, army.
func _entries() -> Array:
	var out: Array = []
	for pair: Array in [["flag", BtAbilities.FLAGS], ["weapon", BtAbilities.WEAPON_KEYS], ["aura", BtAbilities.AURAS], ["army", BtAbilities.ARMIES]]:
		var reg: Dictionary = pair[1]
		for k: Variant in reg:
			out.append([pair[0], str(k), str(reg[k])])
	return out


## The source of `func <name>(` in this file up to the next func ("" when absent).
func _body(name: String) -> String:
	var head := "\nfunc " + name + "("
	var i := src.find(head)
	if i < 0:
		return ""
	var j := src.find("\nfunc ", i + head.length())
	return src.substr(i, (j if j >= 0 else src.length()) - i)


## JavaScript truthiness of a raw JSON value.
func _js_truthy(v: Variant) -> bool:
	match typeof(v):
		TYPE_NIL:
			return false
		TYPE_BOOL:
			return bool(v)
		TYPE_INT, TYPE_FLOAT:
			return float(v) != 0.0
		TYPE_STRING:
			return str(v) != ""
	return true


# ------------------------------------------------------------------ registry
func test_registry_covers_types_json() -> void:
	assert_eq(raw_types.size(), GameData.count(), "types.json read raw (%d datasheets)" % raw_types.size())
	var seen_flags := {}
	var seen_keys := {}
	var seen_auras := {}
	var missing: Array = []
	for tv: Variant in raw_types:
		var t: Dictionary = tv
		for k: Variant in t:
			var ks := str(k)
			if BtAbilities.STATS.has(ks):
				continue
			seen_flags[ks] = true
			if not BtAbilities.FLAGS.has(ks):
				missing.append("flag " + ks)
		for f: String in BtAbilities.STATS:
			if not t.has(f):
				missing.append("stat %s on %s" % [f, t["k"]])
		if t.has("aura"):
			seen_auras[str(t["aura"])] = true
			if not BtAbilities.AURAS.has(str(t["aura"])):
				missing.append("aura " + str(t["aura"]))
		for wn: String in ["gun", "mel"]:
			if not (t[wn] is Dictionary):
				continue
			var w: Dictionary = t[wn]
			for k: Variant in w:
				var ks := str(k)
				if BtAbilities.WEAPON_STATS.has(ks):
					continue
				seen_keys[ks] = true
				if not BtAbilities.WEAPON_KEYS.has(ks):
					missing.append("weapon key " + ks)
	assert_true(missing.is_empty(), "every datasheet field, weapon keyword and aura kind in types.json has a registry entry", missing)
	var stale: Array = []
	for k: Variant in BtAbilities.FLAGS:
		if not seen_flags.has(k):
			stale.append("flag " + str(k))
	for k: Variant in BtAbilities.WEAPON_KEYS:
		if not seen_keys.has(k):
			stale.append("weapon key " + str(k))
	for k: Variant in BtAbilities.AURAS:
		if not seen_auras.has(k):
			stale.append("aura " + str(k))
	assert_true(stale.is_empty(), "no registry entry is missing from the data (no stale names)", stale)
	var facs := GameData.factions()
	var no_army: Array = []
	for f: String in facs:
		if not BtAbilities.ARMIES.has(f):
			no_army.append(f)
	for k: Variant in BtAbilities.ARMIES:
		if not facs.has(str(k)):
			no_army.append("stale " + str(k))
	assert_true(facs.size() == 15 and no_army.is_empty(), "ARMIES has exactly the 15 armies of facs.json", no_army)
	assert_eq(seen_flags.size(), BtAbilities.FLAGS.size(), "%d datasheet flags registered" % seen_flags.size())
	assert_eq(seen_keys.size(), BtAbilities.WEAPON_KEYS.size(), "%d weapon keywords registered" % seen_keys.size())


func test_handlers_name_real_functions() -> void:
	var bad: Array = []
	var counts := {"none": 0, "exists": 0, "later": 0}
	for e: Array in _entries():
		var entry: String = e[2]
		if entry == "none":
			counts["none"] += 1
			continue
		var hs := BtAbilities.handlers(entry)
		if hs.is_empty() or ", ".join(hs) != entry:
			bad.append([e, "not a list of Class.func"])
		for h: String in hs:
			var parts := h.split(".")
			if parts.size() != 2 or not MODULES.has(parts[0]) or parts[1] == "":
				bad.append([e, h, "unknown module"])
				continue
			if _has(parts[0], parts[1]):
				counts["exists"] += 1
			elif LATER.has(h):
				counts["later"] += 1
			else:
				bad.append([e, h, "no such function and not listed for a later wave"])
	assert_true(bad.is_empty(), "every handler is a real function or a later wave's (%d exist, %d later, %d none)" % [counts["exists"], counts["later"], counts["none"]], bad)
	# a LATER entry that no registry entry uses is a typo
	var used := {}
	for e: Array in _entries():
		for h: String in BtAbilities.handlers(str(e[2])):
			used[h] = true
	var unused: Array = []
	for h: Variant in LATER:
		if not used.has(h):
			unused.append(h)
	assert_true(unused.is_empty(), "every LATER handler is used by the registry", unused)


func test_existing_handlers_have_behaviour_tests() -> void:
	var missing: Array = []
	var tested := 0
	for e: Array in _entries():
		var name := "test_%s_%s" % [e[0], e[1]]
		var body := _body(name)
		for h: String in BtAbilities.handlers(str(e[2])):
			var parts := h.split(".")
			if parts.size() != 2 or not _has(parts[0], parts[1]):
				continue
			var fn := parts[1]
			if body == "":
				missing.append("%s: %s exists, no %s" % [e[1], h, name])
			elif not (body.contains("." + fn + "(") or body.contains("\"" + fn + "\"")):
				missing.append("%s does not call %s" % [name, h])
			else:
				tested += 1
	assert_true(missing.is_empty(), "every existing handler has a behavioural test that calls it (%d checked)" % tested, missing)
	# and no behavioural test for a name the registry does not have
	var stray: Array = []
	var names := {}
	for e: Array in _entries():
		names["test_%s_%s" % [e[0], e[1]]] = true
	for m: Dictionary in get_method_list():
		var n := str(m["name"])
		for g: String in ["test_flag_", "test_weapon_", "test_aura_", "test_army_"]:
			if n.begins_with(g) and not names.has(n):
				stray.append(n)
	assert_true(stray.is_empty(), "every behavioural test belongs to a registry entry", stray)


func test_handlers_split() -> void:
	assert_eq(BtAbilities.handlers("none"), PackedStringArray(), "none has no handlers")
	assert_eq(BtAbilities.handlers(""), PackedStringArray(), "empty has no handlers")
	assert_eq(BtAbilities.handlers("BtCombat.atk_math"), PackedStringArray(["BtCombat.atk_math"]), "one handler")
	assert_eq(BtAbilities.handlers("BtCombat.shot_why_not, BtCombat.charge_why_not"),
		PackedStringArray(["BtCombat.shot_why_not", "BtCombat.charge_why_not"]), "two handlers, in order")


# ------------------------------------------------------------------ accessors
func test_accessors_hand_values() -> void:
	var inf := _ti("infantry")
	assert_eq(str(BtAbilities.ty(inf)["k"]), "infantry", "ty by index")
	assert_true(BtAbilities.ty(-1).is_empty() and BtAbilities.ty(GameData.count()).is_empty(), "outside the table: {}")
	assert_eq(BtAbilities.num(inf, "T"), 3, "num reads T")
	assert_eq(BtAbilities.num(inf, "inv"), 0, "a missing field is 0")
	assert_eq(BtAbilities.num(_ti("medusa"), "inv"), 4, "medusa 4++")
	assert_eq(BtAbilities.num(inf, "fac"), 0, "a text field is not a number")
	assert_eq(BtAbilities.num(-1, "T"), 0, "no type, no number")
	assert_eq(BtAbilities.text(inf, "fac"), "mod", "text reads fac")
	assert_eq(BtAbilities.text(_ti("cmdr"), "aura"), "hit", "text reads the aura kind")
	assert_eq(BtAbilities.text(inf, "aura"), "", "no aura: empty")
	assert_eq(BtAbilities.text(inf, "T"), "", "a number is not text")
	assert_false(BtAbilities.flag(inf, "st"), "no st")
	assert_true(BtAbilities.flag(_ti("ninja"), "st"), "ninjas have st")
	assert_true(BtAbilities.flag(_ti("cmdr"), "aura"), "an aura kind is a true flag")
	assert_true(BtAbilities.flag(inf, "gun"), "a weapon object is true")
	assert_false(BtAbilities.flag(_ti("hoplite"), "gun"), "gun null is false")
	assert_false(BtAbilities.flag(-1, "st"), "no type, no flag")
	assert_true(BtAbilities.gun(_ti("hoplite")).is_empty(), "no gun: {}")
	var g := BtAbilities.gun(inf)
	assert_eq([BtAbilities.wnum(g, "rng"), BtAbilities.wnum(g, "a"), BtAbilities.wnum(g, "rf")], [24, 1, 1], "wnum reads rng, a, rf")
	assert_eq(BtAbilities.wnum(g, "nm"), 0, "a weapon name is not a number")
	assert_eq(BtAbilities.wnum(g, "po"), 0, "a missing keyword is 0")
	assert_true(BtAbilities.wflag(g, "rf") and not BtAbilities.wflag(g, "hv"), "wflag")
	assert_eq(BtAbilities.wnum({}, "a"), 0, "an empty weapon has nothing")
	assert_true(BtAbilities.wflag({"x": true}, "x") and BtAbilities.wnum({"x": true}, "x") == 1, "true counts as 1")
	assert_false(BtAbilities.wflag({"x": false}, "x") or BtAbilities.wflag({"x": 0}, "x") or BtAbilities.wflag({"x": ""}, "x"), "false, 0 and empty text are false")
	assert_true(BtAbilities.wflag({"x": {}}, "x") and BtAbilities.wflag({"x": []}, "x"), "objects and arrays are true, as in JavaScript")
	assert_eq(BtAbilities.wflag({"x": null}, "x"), false, "null is false")
	var every_mel := true
	for ti: int in GameData.count():
		every_mel = every_mel and not BtAbilities.mel(ti).is_empty()
	assert_true(every_mel, "every datasheet has a melee weapon")
	assert_true(BtAbilities.mel(-1).is_empty(), "no type, no weapon")


## flag/num/text agree with the raw JSON for every field of every datasheet (r is stored as r_mi by GameData).
func test_accessors_agree_with_raw_json() -> void:
	var bad: Array = []
	for i: int in raw_types.size():
		var t: Dictionary = raw_types[i]
		for k: Variant in t:
			var ks := str(k)
			if ks == "r":
				continue
			var v: Variant = t[k]
			if BtAbilities.flag(i, ks) != _js_truthy(v):
				bad.append([t["k"], ks, "flag"])
			if typeof(v) == TYPE_FLOAT and BtAbilities.num(i, ks) != int(v):
				bad.append([t["k"], ks, "num"])
			if typeof(v) == TYPE_STRING and BtAbilities.text(i, ks) != str(v):
				bad.append([t["k"], ks, "text"])
		for wn: String in ["gun", "mel"]:
			var w: Dictionary = BtAbilities.gun(i) if wn == "gun" else BtAbilities.mel(i)
			if not (t[wn] is Dictionary):
				if not w.is_empty():
					bad.append([t["k"], wn, "should be empty"])
				continue
			var rw: Dictionary = t[wn]
			for k: Variant in rw:
				var v: Variant = rw[k]
				if BtAbilities.wflag(w, str(k)) != _js_truthy(v):
					bad.append([t["k"], wn, k, "wflag"])
				if typeof(v) == TYPE_FLOAT and BtAbilities.wnum(w, str(k)) != int(v):
					bad.append([t["k"], wn, k, "wnum"])
		if BtAbilities.flag(i, "r_mi") != t.has("r"):
			bad.append([t["k"], "r_mi"])
	assert_true(bad.is_empty(), "every accessor equals the raw JSON value for all %d datasheets" % raw_types.size(), bad.slice(0, 8))


func test_digest_pinned() -> void:
	var a := _digest_scenario()
	assert_eq(a, _digest_scenario(), "the digest is stable within a run")
	assert_digest(a, PINNED_DIGEST, "BtAbilities accessor and registry digest is pinned")


func _digest_scenario() -> String:
	var v := PackedInt64Array()
	for e: Array in _entries():
		v.append(Hash.fnv1a64_str("%s|%s|%s" % e))
	var flags: Array = BtAbilities.FLAGS.keys()
	var wkeys: Array = BtAbilities.WEAPON_STATS + BtAbilities.WEAPON_KEYS.keys()
	for ti: int in range(-1, GameData.count() + 1):
		for k: Variant in flags:
			v.append(1 if BtAbilities.flag(ti, str(k)) else 0)
			v.append(BtAbilities.num(ti, str(k)))
		for k: String in BtAbilities.STATS:
			v.append(BtAbilities.num(ti, k))
		v.append(Hash.fnv1a64_str(BtAbilities.text(ti, "aura") + "|" + BtAbilities.text(ti, "fac")))
		for w: Dictionary in [BtAbilities.gun(ti), BtAbilities.mel(ti)]:
			v.append(w.size())
			for k: Variant in wkeys:
				v.append(BtAbilities.wnum(w, str(k)))
				v.append(1 if BtAbilities.wflag(w, str(k)) else 0)
	return Hash.digest_hex(v)


# ------------------------------------------------------------------ behaviour: datasheet flags
func test_flag_ac() -> void:
	var st := _st()
	assert_true(BtAbilities.flag(_ti("hound"), "ac") and not BtAbilities.flag(_ti("hoplite"), "ac"), "hounds have ac, hoplites do not")
	var a := _sq(st, "0:0", "hound", 0, [[0, 0]])
	var b := _sq(st, "0:1", "hoplite", 0, [[20000, 0]])
	_sq(st, "1:0", "infantry", 1, [[0, 6000]])
	var t2 := _sq(st, "1:1", "infantry", 1, [[20000, 6000]])
	a.adv = true
	b.adv = true
	assert_eq(_key(BtCombat.charge_why_not(st, a, st.squad("1:0"))), "", "ac: charges after advancing")
	assert_eq(_key(BtCombat.charge_why_not(st, b, t2)), "advanced", "without ac: no charge after advancing")


func test_flag_aoc() -> void:
	var st := _st()
	var sn := _sq(st, "0:0", "sniper", 0, [[0, 0]])
	var kn := _sq(st, "1:0", "knight", 1, [[0, 10000]])
	var hv := _sq(st, "1:1", "heavy", 1, [[10000, 0]])
	assert_true(BtAbilities.flag(kn.ti, "aoc") and not BtAbilities.flag(hv.ti, "aoc"), "knights have aoc, heavies do not (both save 3)")
	assert_eq(BtCombat.atk_math(st, sn, kn, SHOOT)["sv"], 4, "aoc: ap 2 hits as ap 1 (save 4)")
	assert_eq(BtCombat.atk_math(st, sn, hv, SHOOT)["sv"], 5, "no aoc: ap 2 (save 5)")


func test_flag_aura() -> void:
	var st := _st()
	var s := _sq(st, "0:0", "infantry", 0, [[0, 0]])
	assert_false(BtCombat.in_aura(st, s, "hit"), "no bearer, no aura")
	var c := _sq(st, "0:1", "cmdr", 0, [[0, 6000]])
	assert_true(BtCombat.in_aura(st, s, "hit"), "a hit bearer within 6 inches")
	assert_false(BtCombat.in_aura(st, s, "veil"), "only its own kind")
	st.remove_unit(c.models[0])
	assert_false(BtCombat.in_aura(st, s, "hit"), "gone with the bearer")


func test_flag_ca() -> void:
	var st := _st()
	var t := _sq(st, "1:0", "heavy", 1, [[0, 2000]])
	var boys := _sq(st, "0:0", "boy", 0, [[0, 0]])
	var foot := _sq(st, "0:1", "infantry", 0, [[1000, 0]])
	boys.charged = true
	foot.charged = true
	assert_eq(BtCombat.atk_math(st, boys, t, FIGHT)["shots"], int(BtAbilities.mel(boys.ti)["a"]) + 1, "ca and charged: +1 attack per model")
	assert_eq(BtCombat.atk_math(st, foot, t, FIGHT)["shots"], int(BtAbilities.mel(foot.ti)["a"]), "no ca: no extra attack")
	boys.charged = false
	assert_eq(BtCombat.atk_math(st, boys, t, FIGHT)["shots"], int(BtAbilities.mel(boys.ti)["a"]), "ca without charging: nothing")


func test_flag_fly() -> void:
	var st := _st()
	var fly := _find(func(q: Dictionary) -> bool: return q.has("fly") and not q.has("ttn") and not q.has("ac") and q["gun"] is Dictionary and str(q["fac"]) != "de")
	var f := _sq(st, "0:0", fly, 0, [[0, 0]])
	var g := _sq(st, "0:1", "infantry", 0, [[30000, 0]])
	var t := _sq(st, "1:0", "infantry", 1, [[0, 8000]])
	var t2 := _sq(st, "1:1", "infantry", 1, [[30000, 8000]])
	f.fell = true
	g.fell = true
	assert_eq(_key(BtCombat.shot_why_not(st, f, t)), "", "fly: shoots after falling back")
	assert_eq(_key(BtCombat.shot_why_not(st, g, t2)), "fell_back", "without fly: no")
	assert_eq(_key(BtCombat.charge_why_not(st, f, t)), "", "fly: charges after falling back")
	assert_eq(_key(BtCombat.charge_why_not(st, g, t2)), "fell_back", "without fly: no")


func test_flag_heal() -> void:
	var st := _st()
	var med := _sq(st, "0:0", "medic", 0, [[0, 0]])
	var inf := _sq(st, "0:1", "infantry", 0, [[1000, 0]])
	var hurt := _sq(st, "0:2", "heavy", 0, [[0, 2000]], 1)
	assert_true(BtCombat.can_heal(st, med, hurt), "a healer heals a hurt friend in range")
	assert_eq(_key(BtCombat.heal_why_not(st, med, hurt)), "", "allowed")
	assert_false(BtCombat.can_heal(st, inf, hurt), "a squad without heal cannot")
	assert_eq(BtCombat.heal_why_not(st, inf, hurt), {"key": "too_far", "args": [0]}, "and the page calls it too far [0]")
	var elrange := _find(func(q: Dictionary) -> bool: return int(q.get("heal", 0)) == 6)
	var far := _sq(st, "0:3", elrange, 0, [[0, 40000]])
	var hurt6 := _sq(st, "0:4", "heavy", 0, [[0, 46001]], 1)
	assert_true(BtCombat.can_heal(st, far, hurt6), "heal 6: 6 inches + 1 MI")
	assert_false(BtCombat.can_heal(st, med, _sq(st, "0:5", "heavy", 0, [[0, -4000]], 1)), "heal 3: 4 inches is too far")


func test_flag_heel() -> void:
	var st := _st()
	var s := _sq(st, "0:0", "infantry", 0, [[0, 0]])
	var heel := _find(func(q: Dictionary) -> bool: return q.has("heel"))
	assert_true(BtCombat.atk_math(st, s, _sq(st, "1:0", heel, 1, [[0, 5000]]), SHOOT)["heel"], "a heel target: the attack carries heel")
	assert_false(BtCombat.atk_math(st, s, _sq(st, "1:1", "heavy", 1, [[5000, 0]]), FIGHT)["heel"], "others do not")


func test_flag_inf() -> void:
	var bad: Array = []
	for t: Dictionary in GameData.types():
		var ti := _ti(str(t["k"]))
		if BtCombat.inf(ti) != (int(t["inf"]) == 1):
			bad.append(t["k"])
	assert_true(bad.is_empty(), "BtCombat.inf reads the exported inf of every datasheet", bad)
	var st := _st()
	var cav := _sq(st, "0:0", "cavalry", 0, [[0, 0]])
	assert_false(BtCombat.inf(cav.ti), "riders are not foot soldiers")
	assert_eq(_key(BtCombat.gren_why_not(st, _sq(st, "0:1", "mech", 0, [[0, 3000]]), _sq(st, "1:0", "infantry", 1, [[0, 6000]]))), "not_infantry", "a non-inf squad throws no grenade")


func test_flag_inv() -> void:
	var st := _st()
	var mech := _sq(st, "0:0", "mech", 0, [[0, 0]])
	var med := _sq(st, "1:0", "medusa", 1, [[0, 10000]])
	var inf := _sq(st, "1:1", "infantry", 1, [[10000, 0]])
	assert_eq(BtCombat.atk_math(st, mech, med, SHOOT)["sv"], 4, "inv 4 caps ap 3 on armour 5")
	assert_eq(BtCombat.atk_math(st, mech, inf, SHOOT)["sv"], 7, "no inv: armour 5 + ap 3 is capped at 7 (no save)")


func test_flag_r() -> void:
	assert_eq(BtSquads.radius_of(_ti("cavalry")), 1100, "r 1.1 inches is 1100 MI")
	assert_eq(BtSquads.radius_of(_ti("mech")), 1500, "r 1.5 inches is 1500 MI")
	assert_eq(BtSquads.radius_of(_ti("infantry")), 800, "no r: 800")
	assert_eq(BtAbilities.num(_ti("mech"), "r_mi"), 1500, "GameData keeps r as r_mi")


func test_flag_st() -> void:
	var st := _st()
	var s := _sq(st, "0:0", "infantry", 0, [[0, 0]])
	var nj := _sq(st, "1:0", "ninja", 1, [[0, 10000]])
	var inf := _sq(st, "1:1", "infantry", 1, [[10000, 0]])
	assert_eq(BtCombat.atk_math(st, s, nj, SHOOT)["mod"], -1, "st: -1 to be hit by shooting")
	assert_eq(BtCombat.atk_math(st, s, inf, SHOOT)["mod"], 0, "no st: 0")
	assert_eq(BtCombat.atk_math(st, s, nj, FIGHT)["mod"], 0, "st does nothing in melee")


func test_flag_ttn() -> void:
	var st := _st()
	var ttn := _find(func(q: Dictionary) -> bool: return q.has("ttn") and q["gun"] is Dictionary and not q.has("fly"))
	var r := BtSquads.radius_of(_ti(ttn))
	var big := _sq(st, "0:0", ttn, 0, [[0, 0]])
	var foe := _sq(st, "1:0", "infantry", 1, [[r + 800 + 500, 0]])
	var t := _sq(st, "1:1", "infantry", 1, [[0, r + 12000]])
	assert_true(BtSquads.is_engaged(st, big), "the titan is engaged")
	assert_eq(_key(BtCombat.shot_why_not(st, big, t)), "", "ttn: shoots while engaged")
	var foot := _sq(st, "0:1", "infantry", 0, [[60000, 0]])
	_sq(st, "1:2", "infantry", 1, [[62100, 0]])
	assert_eq(_key(BtCombat.shot_why_not(st, foot, _sq(st, "1:3", "infantry", 1, [[60000, 10000]]))), "engaged", "without ttn: no")
	st.remove_unit(foe.models[0])
	big.fell = true
	assert_eq(_key(BtCombat.shot_why_not(st, big, t)), "", "ttn: shoots after falling back")
	assert_eq(_key(BtCombat.charge_why_not(st, big, t)), "", "ttn: charges after falling back")


func test_flag_sec() -> void:
	var sec := _ti(_find(func(q: Dictionary) -> bool: return q.has("sec"), true))
	assert_true(sec >= 0 and BtAbilities.flag(sec, "sec") and GameData.is_hidden(GameData.key_at(sec)), "one hidden datasheet carries sec")
	_hidden_army_checks(sec, ["fit_list", "fac_of", "pts_of", "slot_max"])


func test_flag_lk() -> void:
	var lk := _ti(_find(func(q: Dictionary) -> bool: return q.has("lk"), true))
	assert_true(lk >= 0 and BtAbilities.flag(lk, "lk") and BtAbilities.text(lk, "lk") != "", "one hidden datasheet carries lk (an army code)")
	_hidden_army_checks(lk, ["fit_list", "pts_of", "slot_max"])


## The hidden-type rules of BtArmy (spec §1 army) named in fns: one per list (fit_list, slot_max outside spectator mode),
## free of points (pts_of), and a sec type never sets the army (fac_of). Calls go by name: army.gd is written by a
## parallel wave and may not exist in this checkout.
func _hidden_army_checks(hid: int, fns: Array) -> void:
	var open := _ti("infantry")
	var army := _module("BtArmy")
	if army == null:
		print("info  BtArmy is not written yet: its hidden-type rules are checked once it exists")
		return
	if fns.has("fit_list") and _has("BtArmy", "fit_list"):
		var raw: Array = []
		raw.resize(GameData.count())
		raw.fill(0)
		raw[hid] = 5
		raw[open] = 5
		var got: PackedInt32Array = army.call("fit_list", raw)
		assert_eq([got[hid], got[open]], [1, 5], "fit_list: a hidden type is clamped to one, an open one is not")
	if fns.has("fac_of") and _has("BtArmy", "fac_of"):
		var list := PackedInt32Array()
		list.resize(GameData.count())
		list[hid] = 1
		assert_eq(str(army.call("fac_of", list, "gr")), "gr", "fac_of skips a sec type")
	if fns.has("pts_of") and _has("BtArmy", "pts_of"):
		var st := BattleState.make({"seed": 4, "w": 60, "teams": 2})
		var p := st.add_seat(0, "A", false, false, "")
		p.list[hid] = 1
		p.list[open] = 2
		assert_eq(int(army.call("pts_of", st, 0)), 2 * int(GameData.ty("infantry")["pts"]), "pts_of: a hidden type is free of points")
	if fns.has("slot_max") and _has("BtArmy", "slot_max"):
		var st := BattleState.make({"seed": 4, "w": 60, "teams": 2, "mode": "pvp"})
		assert_eq([int(army.call("slot_max", st, hid)), int(army.call("slot_max", st, open))], [1, GameData.const_int("SLOT_MAX")], "slot_max: one hidden squad per player")


func test_flag_vsh() -> void:
	var vsh := _ti(_find(func(q: Dictionary) -> bool: return q.has("vsh")))
	assert_true(vsh >= 0 and BtAbilities.num(vsh, "vsh") > 0, "a datasheet with shield layers")
	if not _has("BtArmy", "deploy"):
		print("info  BtArmy.deploy is not written yet: the starting shield layers are checked once it exists")
		return
	var army := _module("BtArmy")
	var st := BattleState.make({"seed": 4, "w": 60, "teams": 2})
	var p := st.add_seat(0, "A", false, false, "")
	p.list[vsh] = 1
	p.list[_ti("infantry")] = 1
	p.has_dep = true
	p.dep_x = 0
	p.dep_z = -20000
	var out: Array[Dictionary] = []
	army.call("deploy", st, out)
	var got := {}
	for s: BattleState.Squad in st.squads:
		got[s.k] = s.vs
	assert_eq([got.get(GameData.key_at(vsh), -1), got.get("infantry", -1)], [BtAbilities.num(vsh, "vsh"), 0], "deploy: squads start with vsh layers (0 without)")


# ------------------------------------------------------------------ behaviour: weapon keywords
func test_weapon_rf() -> void:
	var st := _st()
	var s := _sq(st, "0:0", "infantry", 0, [[0, 0]])
	assert_eq(BtCombat.atk_math(st, s, _sq(st, "1:0", "heavy", 1, [[0, 12001]]), SHOOT)["shots"], 2, "rf 1 within half range: 2 shots")
	assert_eq(BtCombat.atk_math(st, s, _sq(st, "1:1", "heavy", 1, [[12002, 0]]), SHOOT)["shots"], 1, "beyond: 1")
	var a := _sq(st, "0:1", "archer", 0, [[0, -30000]])
	assert_eq(BtCombat.atk_math(st, a, _sq(st, "1:2", "heavy", 1, [[0, -29000]]), SHOOT)["shots"], 1, "no rf: 1 even point blank")


func test_weapon_as() -> void:
	var st := _st()
	var a := _sq(st, "0:0", "enemy", 0, [[0, 0]])
	var b := _sq(st, "0:1", "infantry", 0, [[30000, 0]])
	a.adv = true
	b.adv = true
	assert_eq(_key(BtCombat.shot_why_not(st, a, _sq(st, "1:0", "infantry", 1, [[0, 8000]]))), "", "as: shoots after advancing")
	assert_eq(_key(BtCombat.shot_why_not(st, b, _sq(st, "1:1", "infantry", 1, [[30000, 8000]]))), "advanced", "no as: no")


func test_weapon_pi() -> void:
	var st := _st()
	var med := _sq(st, "0:0", "medic", 0, [[0, 0]])
	var e := _sq(st, "1:0", "infantry", 1, [[2000, 0]])
	var inf := _sq(st, "0:1", "infantry", 0, [[30000, 0]])
	var e2 := _sq(st, "1:1", "infantry", 1, [[32000, 0]])
	assert_eq(_key(BtCombat.shot_why_not(st, med, e)), "", "pi: a pistol shoots the squad it is engaged with")
	assert_eq(BtCombat.shot_why_not(st, inf, e2), {"key": "engaged", "args": [0]}, "no pi: engaged")


func test_weapon_hv() -> void:
	var st := _st()
	var a := _sq(st, "0:0", "archer", 0, [[0, 0]])
	var b := _sq(st, "0:1", "infantry", 0, [[0, 1000]])
	var t := _sq(st, "1:0", "heavy", 1, [[0, 15000]])
	assert_eq(BtCombat.atk_math(st, a, t, SHOOT)["mod"], 1, "hv standing still: +1")
	assert_eq(BtCombat.atk_math(st, b, t, SHOOT)["mod"], 0, "no hv: 0")
	a.still = false
	assert_eq(BtCombat.atk_math(st, a, t, SHOOT)["mod"], 0, "hv after moving: 0")


func test_weapon_su() -> void:
	var st := _st()
	var t := _sq(st, "1:0", "heavy", 1, [[0, 10000]])
	assert_eq(BtCombat.atk_math(st, _sq(st, "0:0", "hmg", 0, [[0, 0]]), t, SHOOT)["su"], 1, "su carried into the attack")
	assert_eq(BtCombat.atk_math(st, _sq(st, "0:1", "infantry", 0, [[1000, 0]]), t, SHOOT)["su"], 0, "no su: 0")


func test_weapon_tr() -> void:
	var st := _st()
	var t := _sq(st, "1:0", "heavy", 1, [[0, 6000]])
	var m := BtCombat.atk_math(st, _sq(st, "0:0", "flamer", 0, [[0, 0]]), t, SHOOT)
	assert_eq([m["tr"], m["need"]], [true, 0], "tr: hits automatically (need 0)")
	var n := BtCombat.atk_math(st, _sq(st, "0:1", "infantry", 0, [[1000, 0]]), t, SHOOT)
	assert_eq([n["tr"], n["need"]], [false, 4], "no tr: rolls bs")


func test_weapon_lh() -> void:
	var st := _st()
	var t := _sq(st, "1:0", "heavy", 1, [[0, 2000]])
	assert_true(BtCombat.atk_math(st, _sq(st, "0:0", "samurai", 0, [[0, 0]]), t, FIGHT)["lh"], "lh carried (melee)")
	assert_false(BtCombat.atk_math(st, _sq(st, "0:1", "hoplite", 0, [[1000, 0]]), t, FIGHT)["lh"], "no lh")


func test_weapon_dw() -> void:
	var st := _st()
	var t := _sq(st, "1:0", "heavy", 1, [[0, 10000]])
	assert_true(BtCombat.atk_math(st, _sq(st, "0:0", "medusa", 0, [[0, 0]]), t, SHOOT)["dw"], "dw carried")
	assert_false(BtCombat.atk_math(st, _sq(st, "0:1", "sniper", 0, [[1000, 0]]), t, SHOOT)["dw"], "no dw")


func test_weapon_bl() -> void:
	var st := _st()
	var bl := _find(func(q: Dictionary) -> bool: return q["gun"] is Dictionary and int(q["gun"].get("bl", 0)) == 1 and int(q["n"]) == 1)
	var a := int(BtAbilities.gun(_ti(bl))["a"])
	var pts: Array = []
	for i: int in 10:
		pts.append([i * 1700, 10000])
	var t := _sq(st, "1:0", "levy", 1, pts)
	assert_eq(BtCombat.atk_math(st, _sq(st, "0:0", bl, 0, [[0, 0]]), t, SHOOT)["shots"], a + 2, "bl against ten: +2")
	assert_eq(BtCombat.atk_math(st, _sq(st, "0:1", "archer", 0, [[0, 1000]]), t, SHOOT)["shots"], 1, "no bl: no bonus")


func test_weapon_po() -> void:
	var st := _st()
	var po := _find(func(q: Dictionary) -> bool: return q["gun"] is Dictionary and int(q["gun"].get("po", 0)) == 3 and int(q["gun"]["s"]) == 2)
	var s := _sq(st, "0:0", po, 0, [[0, 0]])
	var t := _sq(st, "1:0", "infantry", 1, [[0, 6000]])
	var mech := _sq(st, "1:1", "mech", 1, [[6000, 0]])
	assert_eq(BtCombat.wound_need(2, 3), 5, "S2 against T3 would wound on 5")
	assert_eq(BtCombat.atk_math(st, s, t, SHOOT)["wneed"], 3, "po 3 against a foot soldier: 3+")
	assert_eq(BtCombat.atk_math(st, s, mech, SHOOT)["wneed"], BtCombat.wound_need(2, 10), "against a machine (not inf) the plain table stands")


func test_weapon_mk() -> void:
	var st := _st()
	var mk := _find(func(q: Dictionary) -> bool: return q["gun"] is Dictionary and int(q["gun"].get("mk", 0)) == 1)
	var t := _sq(st, "1:0", "heavy", 1, [[0, 8000]])
	assert_true(BtCombat.atk_math(st, _sq(st, "0:0", mk, 0, [[0, 0]]), t, SHOOT)["mk"], "mk: the shot marks")
	assert_false(BtCombat.atk_math(st, _sq(st, "0:1", "infantry", 0, [[1000, 0]]), t, SHOOT)["mk"], "no mk")


func test_weapon_la() -> void:
	var st := _st()
	var t := _sq(st, "1:0", "heavy", 1, [[0, 2000]])
	var cav := _sq(st, "0:0", "cavalry", 0, [[0, 0]])
	var mino := _find(func(q: Dictionary) -> bool: return not q["mel"].has("la") and int(q["mel"]["s"]) == 5 and q.has("ca") == false)
	var plain := _sq(st, "0:1", mino, 0, [[1000, 0]])
	cav.charged = true
	plain.charged = true
	assert_eq(BtCombat.atk_math(st, cav, t, FIGHT)["wneed"], 2, "la and charged: S5 vs T4 wounds on 2")
	assert_eq(BtCombat.atk_math(st, plain, t, FIGHT)["wneed"], 3, "S5 without la: 3")


# ------------------------------------------------------------------ behaviour: auras
func test_aura_hit() -> void:
	var st := _st()
	var s := _sq(st, "0:0", "infantry", 0, [[0, 0]])
	var t := _sq(st, "1:0", "heavy", 1, [[0, 15000]])
	assert_eq(BtCombat.atk_math(st, s, t, SHOOT)["need"], 4, "alone: 4+")
	_sq(st, "0:1", "cmdr", 0, [[-5000, 0]])
	assert_eq(BtCombat.atk_math(st, s, t, SHOOT)["need"], 3, "next to a hit bearer: 3+")


func test_aura_veil() -> void:
	var st := _st()
	var s := _sq(st, "0:0", "infantry", 0, [[0, 0]])
	var t := _sq(st, "1:0", "heavy", 1, [[0, 15000]])
	_sq(st, "1:1", _find(func(q: Dictionary) -> bool: return str(q.get("aura", "")) == "veil"), 1, [[5000, 15000]])
	assert_eq(BtCombat.atk_math(st, s, t, SHOOT)["need"], 5, "a target next to a veil bearer: 5+")
	assert_eq(BtCombat.atk_math(st, s, t, OW)["need"], 6, "overwatch is untouched (6)")


func test_aura_bless() -> void:
	var st := _st()
	var s := _sq(st, "0:0", "sniper", 0, [[0, 0]])
	var t := _sq(st, "1:0", "infantry", 1, [[0, 15000]])
	assert_eq(BtCombat.atk_math(st, s, t, SHOOT)["sv"], 7, "ap 2 on armour 5: no save")
	_sq(st, "1:1", "templar", 1, [[5000, 15000]])
	assert_eq(BtCombat.atk_math(st, s, t, SHOOT)["sv"], GameData.const_int("BLESS_INV"), "blessed: BLESS_INV")


# ------------------------------------------------------------------ behaviour: army rules
func test_army_el() -> void:
	var st := _st()
	var el := _find(func(q: Dictionary) -> bool: return str(q["fac"]) == "el" and q["gun"] is Dictionary and not q["gun"].has("as"))
	var e := _sq(st, "0:0", el, 0, [[0, 0]])
	var b := _sq(st, "0:1", "infantry", 0, [[30000, 0]])
	e.adv = true
	b.adv = true
	assert_eq(_key(BtCombat.shot_why_not(st, e, _sq(st, "1:0", "infantry", 1, [[0, 8000]]))), "", "space elves shoot after advancing")
	assert_eq(_key(BtCombat.shot_why_not(st, b, _sq(st, "1:1", "infantry", 1, [[30000, 8000]]))), "advanced", "others need an assault weapon")


func test_army_de() -> void:
	var de := _find(func(q: Dictionary) -> bool: return str(q["fac"]) == "de" and not q.has("ac") and not q.has("fly") and int(q["mel"]["ws"]) == 3)
	for rd: int in [2, 3]:
		var st := _st(rd)
		var s := _sq(st, "0:0", de, 0, [[0, 0]])
		# edge 1400 MI: in charge range, not engaged
		var t := _sq(st, "1:0", "heavy", 1, [[0, 3000]])
		var on := rd >= GameData.const_int("PAIN_ROUND")
		assert_eq(BtCombat.pain_on(st, s.ti), on, "round %d: pain %s" % [rd, "on" if on else "off"])
		assert_eq(BtCombat.atk_math(st, s, t, FIGHT)["mod"], 1 if on else 0, "round %d: melee hit modifier" % rd)
		assert_eq(BtCombat.atk_math(st, s, t, SHOOT)["mod"], 0, "round %d: never for shooting" % rd)
		s.adv = true
		assert_eq(_key(BtCombat.charge_why_not(st, s, t)), "" if on else "advanced", "round %d: charge after advancing" % rd)


func test_army_cx() -> void:
	var st := _st()
	var cx := _find(func(q: Dictionary) -> bool: return str(q["fac"]) == "cx" and q["gun"] is Dictionary and not q["gun"].has("su"))
	var s := _sq(st, "0:0", cx, 0, [[0, 0]])
	var t := _sq(st, "1:0", "heavy", 1, [[0, 2000]])
	assert_true(BtCombat.pact_on(s.ti) and not BtCombat.pact_on(_ti("infantry")), "the pact belongs to the cx army")
	assert_eq(BtCombat.atk_math(st, s, t, FIGHT)["su"], 1, "pact: melee su 1")
	assert_eq(BtCombat.atk_math(st, s, t, SHOOT)["su"], 0, "not when shooting")
	assert_eq(BtCombat.atk_math(st, _sq(st, "0:1", "infantry", 0, [[1000, 0]]), t, FIGHT)["su"], 0, "others: 0")
