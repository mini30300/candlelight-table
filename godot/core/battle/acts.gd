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
# apply(st, act, out) มาในคลื่นที่ 5 พร้อม battle.gd: รับ act ที่ผ่าน sanitize แล้ว เรียก BtPend/BtMoves/BtTurn ตามตาราง §4


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
