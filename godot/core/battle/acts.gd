class_name BtActs
extends RefCounted
## act ของโต๊ะรบ (R1_PORT_SPEC หัวข้อ acts.gd และ §4): รหัสที่รับ ตัวกรองแบบเดียวกับ btPost ของเซิร์ฟเวอร์ และรูปบนสาย
## รูปในแกน (core form): จุดเป็น MI ทุกเลขเป็น int; ตัวกรองรับรูปในแกนแล้วคืนรูปในแกน {} = ไม่รับ (เหมือน HTTP 400)
## บนสาย: จุด (to, x, z) เป็นร้อยส่วนของนิ้ว (int) ตัวพิมพ์ทศนิยมและการแปลงกลับอยู่ใน net/json_num.gd
## ค่าที่ไม่ใช่ตัวเลขในรูปในแกน (String, Array, null) นับเป็นไม่ใช่ตัวเลข: ได้ค่าตั้งต้นของช่องนั้น

## รหัสกติกา 19 ตัว (ลำดับตามตาราง §4) แล้วรหัสรุ่นเก่า endturn, move
const CODES := ["smove", "stay", "skip", "adv", "atk", "wnd", "sav", "rr", "shoot", "shock", "rez", "chg", "ow", "chr",
	"cmove", "gren", "heal", "done", "endph", "endturn", "move"]
## รหัสรุ่นเก่า (เซิร์ฟเวอร์ยังรับ หน้าเก่าไม่ส่ง)
const LEGACY := ["endturn", "move"]
## วิธีเดินของ smove
const MOVE_HOWS := ["move", "adv", "fb"]
## ลูกเต๋าต่อแถวไม่เกิน, จุดต่อแถวไม่เกิน, ความยาว id (หน่วย UTF-16 แบบ JS)
const MAX_DICE := 60
const MAX_PTS := 40
const MAX_ID := 20
## พิกัดไม่เกิน ±9999 นิ้ว (num ของเซิร์ฟเวอร์) เป็น MI
const MAX_MI := 9999000


## ตัวกรอง act แบบ btPost (worker.js action "act"): เก็บเฉพาะช่องของรหัสนั้น ตัด/หนีบค่า ตามลำดับคีย์ของเซิร์ฟเวอร์
## pid (String หรือ int) ผ่านไปด้วย (เซิร์ฟเวอร์ใส่ให้จากผู้ส่ง) ส่วน seq/ts ของห้องไม่ใช่ของแกน ทิ้ง
static func sanitize(raw: Dictionary) -> Dictionary:
	var code: Variant = raw.get("a")
	if typeof(code) != TYPE_STRING:
		return {}
	var act := {}
	match String(code):
		"move":
			act = {"a": "move", "u": _id(raw.get("u")), "x": _num(raw.get("x")), "z": _num(raw.get("z"))}
		"endturn":
			act = {"a": "endturn"}
		"shoot":
			act = {"a": "shoot", "u": _id(raw.get("u")), "t": _id(raw.get("t")), "how": _how(raw.get("how")),
				"hit": _dice(raw.get("hit"), MAX_DICE), "wound": _dice(raw.get("wound"), MAX_DICE),
				"save": _dice(raw.get("save"), MAX_DICE)}
		"atk":
			act = {"a": "atk", "u": _id(raw.get("u")), "t": _id(raw.get("t")), "how": _how(raw.get("how")),
				"hit": _dice(raw.get("hit"), MAX_DICE)}
		"wnd":
			act = {"a": "wnd", "u": _id(raw.get("u")), "t": _id(raw.get("t")), "wound": _dice(raw.get("wound"), MAX_DICE)}
		"sav":
			act = {"a": "sav", "u": _id(raw.get("u")), "t": _id(raw.get("t")), "save": _dice(raw.get("save"), MAX_DICE),
				"gtg": _bit(raw.get("gtg"))}
		"heal":
			act = {"a": "heal", "u": _id(raw.get("u")), "t": _id(raw.get("t")), "roll": _die(raw.get("roll"))}
		"skip":
			act = {"a": "skip", "u": _id(raw.get("u")), "ph": _ph(raw.get("ph"))}
		"done":
			act = {"a": "done", "ph": _ph(raw.get("ph"))}
		"smove":
			act = {"a": "smove", "u": _id(raw.get("u")), "how": _move_how(raw.get("how"))}
			# to เป็นอาร์เรย์ (ว่างก็ได้) เก็บ to; ไม่ใช่ก็เก็บ x, z (ไม่มีค่าได้ 0 = กลางโต๊ะ เหมือนเซิร์ฟเวอร์)
			if _is_arr(raw.get("to")):
				act["to"] = _pts(raw.get("to"))
			else:
				act["x"] = _num(raw.get("x"))
				act["z"] = _num(raw.get("z"))
		"stay":
			act = {"a": "stay", "u": _id(raw.get("u"))}
		"adv":
			act = {"a": "adv", "u": _id(raw.get("u")), "roll": _die(raw.get("roll"))}
		"rr":
			act = {"a": "rr", "u": _id(raw.get("u")), "t": _id(raw.get("t")), "v": _die(raw.get("v"))}
		"shock":
			act = {"a": "shock", "u": _id(raw.get("u")), "roll": _dice(raw.get("roll"), 2), "brave": _bit(raw.get("brave"))}
		"chg":
			act = {"a": "chg", "u": _id(raw.get("u")), "t": _id(raw.get("t"))}
		"ow":
			act = {"a": "ow", "u": _id(raw.get("u")), "t": _id(raw.get("t")), "use": _bit(raw.get("use"))}
		"chr":
			# rr กับ keep มีเสมอ (0/1)
			act = {"a": "chr", "u": _id(raw.get("u")), "t": _id(raw.get("t")), "roll": _dice(raw.get("roll"), 2),
				"rr": _bit(raw.get("rr")), "keep": _bit(raw.get("keep"))}
		"cmove":
			act = {"a": "cmove", "u": _id(raw.get("u")), "t": _id(raw.get("t")), "to": _pts(raw.get("to"))}
		"gren":
			act = {"a": "gren", "u": _id(raw.get("u")), "t": _id(raw.get("t")), "roll": _dice(raw.get("roll"), 6)}
		"rez":
			act = {"a": "rez", "u": _id(raw.get("u")), "roll": _dice(raw.get("roll"), 10)}
		"endph":
			act = {"a": "endph", "ph": _ph(raw.get("ph"))}
	if act.is_empty():
		return {}
	var pid: Variant = raw.get("pid")
	if typeof(pid) == TYPE_STRING or typeof(pid) == TYPE_INT:
		act["pid"] = pid
	return act


## รูปบนสาย: จุดใน to และ x, z จาก MI เป็นร้อยส่วนของนิ้ว (int) แบบ +v.toFixed(2) ของหน้าเก่า ช่องอื่นคัดลอกตรง ๆ
## จุดบนตาราง 10 MI แปลงไปกลับได้ตรง (MI = ร้อยส่วน x 10)
static func to_wire(act: Dictionary) -> Dictionary:
	var out := {}
	for k: Variant in act:
		var v: Variant = act[k]
		if k == "to" and typeof(v) == TYPE_ARRAY:
			var pts: Array = []
			for q: Variant in v:
				if _is_arr(q) and _len(q) >= 2 and typeof(q[0]) == TYPE_INT and typeof(q[1]) == TYPE_INT:
					pts.append([hundredths(q[0]), hundredths(q[1])])
				else:
					pts.append(_copy(q))
			out[k] = pts
		elif (k == "x" or k == "z") and typeof(v) == TYPE_INT:
			out[k] = hundredths(v)
		else:
			out[k] = _copy(v)
	return out


## +(mi/1000).toFixed(2) ของหน้าเก่าเป็นจำนวนร้อยส่วน ("-0.00" ได้ 0)
static func hundredths(mi: int) -> int:
	var s := Fx.to_fixed_2(mi)
	var neg := s.begins_with("-")
	var h := s.trim_prefix("-").replace(".", "").to_int()
	return -h if neg else h


# ---------------------------------------------------------------- ตัวจ่าย act (netAct 34950–34980)
## netAct: ใช้ act รูปในแกน (ผ่าน sanitize แล้ว) ตามตาราง §4 · ตัวรับไม่ตรวจซ้ำ (เชื่อผู้ส่ง เหมือนหน้าเก่า)
## CP ของ rr/gtg/brave/gren หักในตัวรับก่อนตัวใช้ผลจะตรวจของมันเอง · หลังทุก act ตรวจจบนัด (checkOver ของตัวใช้ผล)
## รหัสที่ไม่รู้จักไม่ทำอะไร (Table ไม่รับตั้งแต่ก่อนบันทึก)
static func apply(st: BattleState, act: Dictionary, out: Array[Dictionary]) -> void:
	_dispatch(st, act, out)
	BtTurn.check_over(st, out)


static func _dispatch(st: BattleState, act: Dictionary, out: Array[Dictionary]) -> void:
	var code := str(act.get("a", ""))
	var u := _str(act.get("u"))
	var s := st.squad(u)
	var t := st.squad(_str(act.get("t")))
	match code:
		"smove":
			if s == null or s.moved:
				return
			var to: Array = _arr(act.get("to"))
			if to.is_empty() and typeof(act.get("x")) == TYPE_INT and typeof(act.get("z")) == TYPE_INT:
				# Claude ส่งแค่จุด: ทุกเครื่องวางแผนเอง
				to = BtMoves.pts(BtMoves.plan_move(st, s, int(act["x"]), int(act["z"])))
			if not to.is_empty():
				BtMoves.apply_smove(st, s, to, _str(act.get("how")), out)
		"stay":
			if s != null:
				s.moved = true
		"skip":
			if s != null:
				var ph := _str(act.get("ph"))
				if ph == "":
					ph = st.phase_name()
				if ph == "shoot":
					s.shot = true
				elif ph == "charge":
					s.ch_done = true
				else:
					s.moved = true
		"adv":
			if s != null and not s.adv:
				BtPend.apply_adv(st, s, _roll1(act.get("roll")), out)
		"atk":
			if s == null or t == null:
				return
			var p := BtPend.pend_at(st, s.id, t.id, BattleState.K_ATK)
			if p == null or p.stage != BattleState.S_HIT:
				if p != null:
					# ขั้นไม่ตรง: สร้างการโจมตีใหม่เหมือนหน้าเก่า
					_say(st, out, "atk_new", [s.id, t.id, BattleState.STAGES[p.stage]])
				p = BtPend.mk_atk(st, s, t, _how_i(act.get("how")))
			if p != null:
				BtPend.apply_hit(st, p, _arr(act.get("hit")), out)
		"shoot":
			if s != null and t != null:
				BtPend.apply_whole(st, s, t, _arr(act.get("hit")), _arr(act.get("wound")), _arr(act.get("save")),
					_how_i(act.get("how")), out)
		"rr":
			var p := _pend_t(st, act, u, BattleState.K_ATK)
			if p != null and p.stage == BattleState.S_WOUND and not p.rr and BtStrats.use(st, "rr", p.att, out):
				BtPend.apply_reroll(st, p, _int(act.get("v")), out)
		"wnd":
			var p := _pend_t(st, act, u, BattleState.K_ATK)
			if p != null:
				BtPend.apply_wnd(st, p, _arr(act.get("wound")), out)
		"sav":
			var p := _pend_t(st, act, u, BattleState.K_ATK)
			if p != null and p.stage == BattleState.S_SAVE:
				var g := _bit(act.get("gtg")) == 1 and BtStrats.use(st, "gtg", p.def, out)
				BtPend.apply_sav(st, p, _arr(act.get("save")), g, out)
		"shock":
			var p := BtPend.pend_at(st, u, "", BattleState.K_SHOCK)
			if p != null:
				var b := _bit(act.get("brave")) == 1 and BtStrats.use(st, "brave", p.att, out)
				BtPend.apply_shock(st, p, _arr(act.get("roll")), b, out)
		"rez":
			var p := BtPend.pend_at(st, u, "", BattleState.K_REZ)
			if p != null:
				BtPend.apply_rez(st, p, _arr(act.get("roll")), out)
		"chg":
			if s != null and t != null and not s.ch_done:
				BtPend.declare_charge(st, s, t, out)
		"ow":
			var p := _pend_t(st, act, u, BattleState.K_CHG)
			if p != null:
				BtPend.apply_ow(st, p, _bit(act.get("use")) == 1, out)
		"chr":
			var p := _pend_t(st, act, u, BattleState.K_CHG)
			if p == null:
				return
			BtPend.chg_ready(st, p)
			if _bit(act.get("keep")) == 1:
				BtPend.keep_charge(st, p, out)
				return
			if _bit(act.get("rr")) == 1:
				if p.stage == BattleState.S_CHRR and BtStrats.use(st, "rr", p.att, out):
					BtPend.apply_charge(st, p, _arr(act.get("roll")), true, out)
				return
			BtPend.apply_charge(st, p, _arr(act.get("roll")), false, out)
		"cmove":
			var p := _pend_t(st, act, u, BattleState.K_CHG)
			if p != null:
				BtPend.apply_cmove(st, p, _arr(act.get("to")), out)
		"gren":
			if s != null and t != null and BtStrats.use(st, "gren", s.pl, out):
				BtPend.apply_gren(st, s, t, _arr(act.get("roll")), out)
		"heal":
			if s != null and t != null:
				BtPend.apply_heal(st, s, t, _roll1(act.get("roll")), out)
		"done":
			var pid: Variant = act.get("pid")
			var pi := st.pid_index(str(pid)) if typeof(pid) == TYPE_STRING else -1
			if pi >= 0:
				BtTurn.player_done(st, pi, _str(act.get("ph")), out)
		"endph":
			var ph := _str(act.get("ph"))
			if ph == "" or ph == st.phase_name():
				BtTurn.next_phase(st, out)
		"endturn":
			# เครื่องรุ่นเก่า
			if st.phase != BattleState.PH_CMD and st.phase != BattleState.PH_FIGHT:
				BtTurn.next_phase(st, out)
		"move":
			pass


## pendAt(a.u, a.t, kind): ไม่มีช่อง t = เป้าไหนก็ได้ · t "" ไม่ตรงกับรายการใด (หน้าเก่าเทียบ P.t === "")
static func _pend_t(st: BattleState, act: Dictionary, u: String, kind: int) -> BattleState.Pend:
	if not act.has("t") or act["t"] == null:
		return BtPend.pend_at(st, u, "", kind)
	var t := _str(act["t"])
	if t == "":
		return null
	return BtPend.pend_at(st, u, t, kind)


static func _str(v: Variant) -> String:
	return str(v) if typeof(v) == TYPE_STRING or typeof(v) == TYPE_STRING_NAME else ""


static func _int(v: Variant) -> int:
	return int(v) if typeof(v) == TYPE_INT else 0


## roll|0 || 1: ไม่ใช่ตัวเลขหรือศูนย์ได้ 1 (ตัวใช้ผลตัดค่านอก 1..6 เป็น 1 เอง)
static func _roll1(v: Variant) -> int:
	var r := _int(v)
	return r if r != 0 else 1


## แถวจาก act (ไม่ใช่อาร์เรย์ได้ [])
static func _arr(v: Variant) -> Array:
	if typeof(v) == TYPE_ARRAY:
		return v
	if _is_arr(v):
		return Array(v)
	return []


## a.how || 'shoot' เป็นเลข HOW_*
static func _how_i(v: Variant) -> int:
	var i := BattleState.HOWS.find(_str(v))
	return i if i >= 0 else BattleState.HOW_SHOOT


static func _say(st: BattleState, out: Array[Dictionary], key: String, args: Array) -> void:
	st.say(key, args)
	out.append(Events.make(Events.Id.LOG_LINE, {"key": key, "args": args.duplicate()}))


# ---------------------------------------------------------------- ตัวกรองทีละช่อง (แบบ worker.js)
## Array.isArray: อาร์เรย์ของ JSON (และอาร์เรย์แบบแพ็กที่ใช้ในเทสต์)
static func _is_arr(v: Variant) -> bool:
	var t := typeof(v)
	return t == TYPE_ARRAY or t == TYPE_PACKED_INT32_ARRAY or t == TYPE_PACKED_INT64_ARRAY


## Number(v) || 0 หนีบ ±9999 นิ้ว: int เป็น MI อยู่แล้ว, bool เป็น 1 นิ้วหรือ 0, อย่างอื่นได้ 0
static func _num(v: Variant) -> int:
	match typeof(v):
		TYPE_INT:
			return Fx.clampi(v, -MAX_MI, MAX_MI)
		TYPE_BOOL:
			return Fx.MI if bool(v) else 0
	return 0


## ลูกเต๋าหนึ่งลูกแบบ one/dice ของเซิร์ฟเวอร์: int หนีบ 1..6 (0 ได้ 1) ที่ไม่ใช่ตัวเลขได้ 1
static func _die(v: Variant) -> int:
	if typeof(v) == TYPE_INT:
		return Fx.clampi(v, 1, 6)
	return 1


## แถวลูกเต๋า: ไม่ใช่อาร์เรย์ได้ [] ตัดที่ 60 แล้วตัดที่ cap (2, 6, 10 หรือ 60)
static func _dice(v: Variant, cap: int) -> Array:
	var out: Array = []
	if not _is_arr(v):
		return out
	var n := mini(mini(MAX_DICE, cap), _len(v))
	for i: int in n:
		out.append(_die(v[i]))
	return out


## แถวจุด: ไม่ใช่อาร์เรย์ได้ [] ไม่เกิน 40 จุด จุดที่ไม่ใช่อาร์เรย์ได้ [0, 0] ช่องที่ขาดได้ 0
static func _pts(v: Variant) -> Array:
	var out: Array = []
	if not _is_arr(v):
		return out
	var n := mini(MAX_PTS, _len(v))
	for i: int in n:
		var q: Variant = v[i]
		if not _is_arr(q):
			out.append([0, 0])
			continue
		var m := _len(q)
		out.append([_num(q[0]) if m > 0 else 0, _num(q[1]) if m > 1 else 0])
	return out


## ความยาวของอาร์เรย์ (ไม่ใช่อาร์เรย์ได้ 0)
static func _len(v: Variant) -> int:
	match typeof(v):
		TYPE_ARRAY:
			var a: Array = v
			return a.size()
		TYPE_PACKED_INT32_ARRAY:
			var a: PackedInt32Array = v
			return a.size()
		TYPE_PACKED_INT64_ARRAY:
			var a: PackedInt64Array = v
			return a.size()
	return 0


## clampStr(v, 20) = String(v ?? "").slice(0, 20): นับหน่วย UTF-16 แบบ JS (อักขระนอก BMP นับสอง ถ้าถูกตัดกลางคู่ก็ทิ้งทั้งตัว)
static func _id(v: Variant) -> String:
	var s := _js_str(v)
	var units := 0
	var i := 0
	while i < s.length():
		var w := 2 if s.unicode_at(i) > 65535 else 1
		if units + w > MAX_ID:
			break
		units += w
		i += 1
	return s.substr(0, i)


## String(v) ของ JS บนค่ารูปในแกน: null ได้ "" (ชั้นนอกสุดจาก ?? ส่วนในอาร์เรย์จาก join) อาร์เรย์คั่นด้วยจุลภาค
static func _js_str(v: Variant) -> String:
	match typeof(v):
		TYPE_NIL:
			return ""
		TYPE_STRING, TYPE_STRING_NAME:
			return str(v)
		TYPE_INT:
			return str(int(v))
		TYPE_BOOL:
			return "true" if bool(v) else "false"
		TYPE_ARRAY, TYPE_PACKED_INT32_ARRAY, TYPE_PACKED_INT64_ARRAY, TYPE_PACKED_STRING_ARRAY:
			var parts := PackedStringArray()
			for x: Variant in v:
				parts.append(_js_str(x))
			return ",".join(parts)
		TYPE_DICTIONARY:
			return "[object Object]"
	return str(v)


## ความจริงแบบ JS (raw.gtg ? 1 : 0): null/false/0/"" เป็นเท็จ อาร์เรย์และ Dictionary เป็นจริงแม้ว่าง
static func _bit(v: Variant) -> int:
	match typeof(v):
		TYPE_NIL:
			return 0
		TYPE_BOOL:
			return 1 if bool(v) else 0
		TYPE_INT:
			return 1 if int(v) != 0 else 0
		TYPE_STRING, TYPE_STRING_NAME:
			return 1 if str(v) != "" else 0
	return 1


## เฟส: ชื่อใน PHASES เท่านั้น อย่างอื่นได้ ""
static func _ph(v: Variant) -> String:
	if typeof(v) == TYPE_STRING and BattleState.PHASES.has(v):
		return str(v)
	return ""


## วิธีโจมตีของ atk/shoot: shoot/fight/ow อย่างอื่นได้ shoot
static func _how(v: Variant) -> String:
	if typeof(v) == TYPE_STRING and BattleState.HOWS.has(v):
		return str(v)
	return "shoot"


## วิธีเดินของ smove: move/adv/fb อย่างอื่นได้ move
static func _move_how(v: Variant) -> String:
	if typeof(v) == TYPE_STRING and MOVE_HOWS.has(v):
		return str(v)
	return "move"


## สำเนาลึก (Array/Dictionary ไม่ใช้ร่วมกับ act เดิม)
static func _copy(v: Variant) -> Variant:
	if typeof(v) == TYPE_ARRAY or typeof(v) == TYPE_DICTIONARY:
		return v.duplicate(true)
	return v
