class_name BtBoard
extends RefCounted
## ภาพกระดานย่อ (R1_PORT_SPEC หัวข้อ board.gd และ §5) = boardState() / BT.board() ของหน้าเก่า 34068–34077 ทีละช่อง ลำดับคีย์เดียวกัน
## เจ้าของห้องส่งขึ้นห้อง (/board) ให้ Claude อ่าน และ oracle ใช้เทียบกับหน้าเก่า
## raw = false: x/z เป็นสิบส่วนของนิ้ว (int) ปัดแบบ toFixed(1) ของหน้าเก่า (Fx.to_fixed_1) ลบศูนย์กลายเป็นศูนย์
## raw = true: x/z เป็น MI ไม่ปัด (oracle กับเทสต์); จุดกลางหมู่เป็น BtSquads.center (js_round) ทั้งสองแบบ
## ไม่อยู่ในกระดาน: คิวรอทอย ธงอื่นของหมู่ ร่างที่รอลม ทิศหัน (digest ดูแลส่วนนั้น)


## ภาพกระดาน: หมู่ที่ยังอยู่ตามลำดับที่สร้าง โมเดลที่ยังอยู่ตามลำดับ units เจ้าของจุดยึดคิดใหม่ (refreshObj)
static func board(st: BattleState, raw: bool) -> Dictionary:
	var cp: Array = []
	for p: BattleState.Seat in st.seats:
		cp.append(p.cp)
	var obj: Array = []
	for o: BattleState.Obj in st.objs:
		obj.append({"n": o.n, "x": _pos(o.x, raw), "z": _pos(o.z, raw), "owner": BtObjectives.ctl(st, o)})
	var sqs: Array = []
	for s: BattleState.Squad in st.alive_squads():
		var c := BtSquads.center(s)
		sqs.append({"id": s.id, "pl": s.pl, "team": s.side, "k": s.k, "n": s.models.size(), "n0": s.n0,
			"x": _pos(c[0], raw), "z": _pos(c[1], raw), "moved": s.moved, "adv": s.adv, "fell": s.fell, "shot": s.shot,
			"chDone": s.ch_done, "charged": s.charged, "shaken": s.shaken, "engaged": BtSquads.is_engaged(st, s)})
	var us: Array = []
	for u: BattleState.Unit in st.units:
		us.append({"id": u.id, "sq": u.sq, "pl": u.pl, "team": u.side, "k": u.t, "hp": u.hp,
			"x": _pos(u.x, raw), "z": _pos(u.z, raw)})
	return {"v": Version.RULES_V, "turn": st.turn, "round": st.round_no, "phase": st.phase_name(), "over": st.over,
		"vp": Array(st.vp), "goal": BattleState.GOALS[st.goal], "rounds": st.max_round(), "cp": cp, "obj": obj,
		"squads": sqs, "units": us}


static func _pos(mi: int, raw: bool) -> int:
	return mi if raw else tenths(mi)


## +(mi/1000).toFixed(1) ของหน้าเก่าเป็นจำนวนสิบส่วน: ปัดแบบ toFixed (ค่าที่ double ตกใต้ครึ่งปัดลง) และ "-0.0" ได้ 0
static func tenths(mi: int) -> int:
	var s := Fx.to_fixed_1(mi)
	var neg := s.begins_with("-")
	var t := s.trim_prefix("-").replace(".", "").to_int()
	return -t if neg else t


## JSON ของกระดาน (raw = false) ไบต์ต่อไบต์เท่า JSON.stringify ของหน้าเก่า: ลำดับคีย์ตามที่ใส่
## ค่า int ของคีย์ x/z พิมพ์เป็นสิบส่วน (120 เป็น "12", 123 เป็น "12.3", -5 เป็น "-0.5") ค่าอื่นพิมพ์ตรง ๆ
static func to_json(b: Dictionary) -> String:
	return _val(b, "")


static func _val(v: Variant, key: String) -> String:
	match typeof(v):
		TYPE_DICTIONARY:
			var d: Dictionary = v
			var parts := PackedStringArray()
			for k: Variant in d:
				var ks := str(k)
				parts.append(_str(ks) + ":" + _val(d[k], ks))
			return "{" + ",".join(parts) + "}"
		TYPE_ARRAY, TYPE_PACKED_INT32_ARRAY, TYPE_PACKED_INT64_ARRAY, TYPE_PACKED_STRING_ARRAY:
			var parts := PackedStringArray()
			for x: Variant in v:
				parts.append(_val(x, ""))
			return "[" + ",".join(parts) + "]"
		TYPE_BOOL:
			return "true" if bool(v) else "false"
		TYPE_INT:
			var n: int = v
			return _tenths_text(n) if key == "x" or key == "z" else str(n)
		TYPE_STRING, TYPE_STRING_NAME:
			return _str(str(v))
	# ค่าอื่นไม่มีในกระดาน (JSON.stringify ของค่าที่เขียนไม่ได้ก็ได้ null)
	return "null"


## สิบส่วนเป็นตัวเลข JS: ไม่มีศูนย์ท้าย จำนวนเต็มไม่มีจุด
static func _tenths_text(t: int) -> String:
	var neg := t < 0
	var a := -t if neg else t
	# a ไม่ติดลบ หารตัดเศษ = ปัดลง
	var s := str(a / 10) if a % 10 == 0 else str(a / 10) + "." + str(a % 10)
	return "-" + s if neg else s


## สตริงแบบ JSON.stringify: หนีเฉพาะ " \ อักขระควบคุม และ surrogate ที่ไม่มีคู่ (ตัวพิมพ์เล็ก) ที่เหลือคงเดิม
static func _str(s: String) -> String:
	var out := "\""
	for i: int in s.length():
		var c := s.unicode_at(i)
		if c == 34:
			out += "\\\""
		elif c == 92:
			out += "\\\\"
		elif c == 8:
			out += "\\b"
		elif c == 9:
			out += "\\t"
		elif c == 10:
			out += "\\n"
		elif c == 12:
			out += "\\f"
		elif c == 13:
			out += "\\r"
		elif c < 32 or (c >= 55296 and c <= 57343):
			out += "\\u" + _hex4(c)
		else:
			out += String.chr(c)
	return out + "\""


static func _hex4(c: int) -> String:
	var out := ""
	for i: int in 4:
		out += Hash.HEX[(c >> ((3 - i) * 4)) & 15]
	return out
