class_name NetProto
extends RefCounted
## ข้อความของห้องเล่นกับเพื่อนบน LAN (NET_SPEC §2): ล้วน static ไม่มีสถานะ ไม่มีข้อความไทย
## กรอบ: [ชนิด u8] + var_to_bytes(body) โดย body เป็น Dictionary คีย์ String
##   ยกเว้น POSE / POSE_STOP: [ชนิด] + var_to_bytes(PackedInt64Array [x, z, yaw, sp, run, t, s]) ให้อยู่ใต้เพดาน 96 ไบต์
## ขาเข้า: ดูขนาดเทียบเพดานของชนิดก่อนถอด, ถอดด้วย bytes_to_var (ไม่มี object), แล้วตรวจทุกช่องตามตาราง
##   ช่องเกินทิ้ง, ช่องผิดชนิด/เกินช่วง/ขาด = ไม่รับทั้งข้อความ ({error}) · ไม่มี float ที่ไหนเลย

## รุ่นโปรโตคอล: เปลี่ยนชนิดหรือช่องใดต้องขยับ (ประตูรุ่นไม่ให้รุ่นต่างกันเจอกัน)
const VERSION := 1
const GAME := "candlelight"

const HELLO := 1
const WELCOME := 2
const REFUSE := 3
const MEMBERS := 10
const WHERE := 11
const PICK := 12
const POSE := 13
const POSE_STOP := 14
const HB := 15
const BYE := 16
const SETUP := 20
const CLAIM := 21
const START := 22
const ACT_REQ := 23
const ACT := 24
const ACT_NO := 25
const RESEND := 26
const RESYNC_REQ := 27
const RESYNC := 28
const SEAT := 29
const DESYNC := 30
const INTS_REQ := 31
const INTS := 32
const END := 33
## เพื่อนออกจากหน้ารบเอง (ของเกม gen นี้): เจ้าห้องเล่นแทนที่นั่งนั้นจนจบเกม
const LEAVE := 34

## ชื่อของแต่ละชนิด (ล็อกและเทส)
const NAMES := {
	1: "HELLO", 2: "WELCOME", 3: "REFUSE", 10: "MEMBERS", 11: "WHERE", 12: "PICK", 13: "POSE", 14: "POSE_STOP",
	15: "HB", 16: "BYE", 20: "SETUP", 21: "CLAIM", 22: "START", 23: "ACT_REQ", 24: "ACT", 25: "ACT_NO",
	26: "RESEND", 27: "RESYNC_REQ", 28: "RESYNC", 29: "SEAT", 30: "DESYNC", 31: "INTS_REQ", 32: "INTS", 33: "END",
	34: "LEAVE",
}
## ทิศทาง: c = ลูกส่งหาเจ้าห้อง, h = เจ้าห้องส่งหาลูก, b = ทั้งสองทาง
const DIR := {
	1: "c", 2: "h", 3: "h", 10: "h", 11: "c", 12: "c", 13: "b", 14: "b", 15: "b", 16: "b", 20: "h", 21: "c",
	22: "h", 23: "c", 24: "h", 25: "h", 26: "c", 27: "c", 28: "h", 29: "h", 30: "c", 31: "c", 32: "h", 33: "h",
	34: "c",
}

## เพดานไบต์ทั้งข้อความ (รวมไบต์ชนิด)
const CAP := 65536
const CAPS := {POSE: 96, POSE_STOP: 96, HELLO: 1024, RESYNC: 1048576, INTS: 262144}
## ความลึกและจำนวนสูงสุดของค่าทั่วไป
const MAX_DEPTH := 8
const MAX_ITEMS := 4096
const MAX_ACTS := 6000
const MAX_INTS := 30000
const MAX_STR := 256
const NAME_MAX := 20

const WHERES := ["deck", "setup", "battle", "arena", "army", "settings", "menu"]
const ROOM_STS := ["deck", "setup", "battle"]
const BYE_KEYS := ["leave", "host_closed", "kicked"]
const NO_KEYS := ["stale", "not_yours", "not_now", "refused", "gone_seat"]
const RESYNC_WHYS := ["desync", "rejoin"]
const SEAT_ONS := ["gone", "back", "left"]
const END_WHYS := ["host_left_battle", "host_closed"]
## คีย์ของประตูรุ่น (ต้องตรงกับ NetGate.KEYS)
const REFUSE_KEYS := ["not_lan", "wrong_game", "wrong_net", "wrong_app", "wrong_rules", "full", "closing"]

## ชนิดช่อง: ["int", lo, hi] ["bool"] ["intbool"] ["false"] ["str", ยาวสุด] ["enum", [...]] ["hex", จำนวนตัว]
##   ["obj", schema] ["list", ชนิดของสมาชิก, จำนวนสุด] ["i32s", จำนวนสุด] ["i64s", จำนวนสุด] ["act"] ["clean"] ["args"]
## คีย์ขึ้นต้น "?" = ไม่บังคับ
const _GEN := ["int", 0, 65535]
const _SEQ := ["int", 0, 100000]
const _SLOT := ["int", 0, 5]
const _DG := ["hex", 16]
const _MEMBER := {"slot": _SLOT, "nm": ["str", NAME_MAX], "where": ["enum", WHERES], "pick": ["str", 24],
	"here": ["bool"]}
const _SETUP_SEAT := {"team": ["int", 0, 3], "owner": ["int", -1, 5], "fac": ["str", 24]}
## setup ของ SeatPlan.build (และช่องที่ BattleState.make อ่านได้)
const _PLAN_SETUP := {"?seed": ["int", 1, 99999], "?w": ["int", 1, 1000], "?d": ["int", 1, 1000],
	"?teams": ["int", 1, 4], "?perTeam": ["int", 1, 2], "?goal": ["str", 16], "?budget": ["int", 1, 1000000],
	"?theme": ["str", 24], "?terrain": ["str", 24], "?buildings": ["intbool"], "?density_h": ["int", 0, 100000],
	"?mode": ["str", 8], "?freeFire": ["intbool"], "?rounds": ["int", 0, 100], "?clock": ["int", 0, 100000000]}
const _PLAN_SEAT := {"team": ["int", 0, 3], "bot": ["bool"], "?ai": ["false"], "pid": ["str", NAME_MAX],
	"nm": ["str", NAME_MAX], "fac": ["str", 24], "list": ["i32s", 512], "?skin": ["clean"], "?dep": ["clean"]}
const _PLAN := {"setup": ["obj", _PLAN_SETUP], "seats": ["list", ["obj", _PLAN_SEAT], 6]}
const _OWNERS := ["list", ["int", -1, 5], 6]
## ท่าทาง: ซม. ซม. มิลลิเรเดียน ซม./วินาที วิ่ง เวลาของผู้ส่ง (ms) และช่องที่เจ้าห้องเติมตอนส่งต่อ
const _POSE := {"x": ["int", -5000, 5000], "z": ["int", -5000, 5000], "yaw": ["int", -7000, 7000],
	"sp": ["int", 0, 2000], "run": ["bool"], "t": ["int", 0, 9223372036854775807], "?s": _SLOT}

const SCHEMAS := {
	HELLO: {"?g": ["str", 32], "?np": ["int", 0, 65535], "?app": ["str", 32], "?rules": ["int", 0, 100000000],
		"?data": ["str", 64], "?nm": ["str", 64], "?nid": ["str", 32]},
	WELCOME: {"slot": _SLOT, "host_nm": ["str", NAME_MAX], "room_st": ["enum", ROOM_STS],
		"members": ["list", ["obj", _MEMBER], 6], "?np": ["int", 0, 65535]},
	REFUSE: {"key": ["enum", REFUSE_KEYS], "args": ["args"]},
	MEMBERS: {"list": ["list", ["obj", _MEMBER], 6], "room_st": ["enum", ROOM_STS], "gen": _GEN},
	WHERE: {"where": ["enum", WHERES]},
	PICK: {"fac": ["str", 24]},
	POSE: _POSE,
	POSE_STOP: _POSE,
	HB: {"?seq": _SEQ, "?dg": _DG, "?gen": _GEN},
	BYE: {"key": ["enum", BYE_KEYS]},
	SETUP: {"open": ["bool"], "seats": ["list", ["obj", _SETUP_SEAT], 6]},
	CLAIM: {"k": ["int", -1, 5]},
	START: {"gen": _GEN, "plan": ["obj", _PLAN], "owners": _OWNERS},
	ACT_REQ: {"gen": _GEN, "base": _SEQ, "act": ["act"]},
	ACT: {"gen": _GEN, "seq": ["int", 1, 100000], "act": ["act"], "?dg": _DG},
	ACT_NO: {"gen": _GEN, "base": _SEQ, "key": ["enum", NO_KEYS]},
	RESEND: {"gen": _GEN, "from": _SEQ},
	RESYNC_REQ: {"gen": _GEN, "why": ["enum", RESYNC_WHYS]},
	RESYNC: {"gen": _GEN, "plan": ["obj", _PLAN], "owners": _OWNERS, "acts": ["list", ["act"], MAX_ACTS],
		"seq": _SEQ, "dg": _DG},
	SEAT: {"gen": _GEN, "k": ["int", 0, 5], "on": ["enum", SEAT_ONS]},
	DESYNC: {"gen": _GEN, "seq": _SEQ, "dg": _DG, "n": ["int", 1, 2]},
	INTS_REQ: {"gen": _GEN},
	INTS: {"gen": _GEN, "seq": _SEQ, "ints": ["i64s", MAX_INTS]},
	END: {"gen": _GEN, "why": ["enum", END_WHYS]},
	LEAVE: {"gen": _GEN},
}
## ลำดับช่องของท่าทางบนสาย
const POSE_FIELDS := ["x", "z", "yaw", "sp", "run", "t", "s"]
## คีย์ args ของ REFUSE ที่รับ
const ARGS_KEYS := ["host", "mine", "n", "max", "port"]


static func is_kind(kind: int) -> bool:
	return NAMES.has(kind)


static func kind_name(kind: int) -> String:
	return str(NAMES.get(kind, "?%d" % kind))


static func cap_of(kind: int) -> int:
	return int(CAPS.get(kind, CAP))


## ชนิดที่เพื่อนส่งหาเจ้าห้องได้หลังยืนยันตัว (ไม่ใช่ของเจ้าห้อง ไม่ใช่ HELLO) และขนาดไม่เกิน 64 KiB
## เจ้าห้องดูไบต์แรกและขนาดก่อนถอด: ชนิดของเจ้าห้องมีเพดานใหญ่กว่า (RESYNC 1 MiB) ห้ามให้เพื่อนใช้เพดานนั้น
static func from_member_ok(kind: int, size: int) -> bool:
	var d := str(DIR.get(kind, ""))
	return (d == "c" or d == "b") and kind != HELLO and size <= CAP


## ชนิดที่เจ้าห้องส่งหาเพื่อนได้หลังยืนยันตัว (ไม่ใช่ของเพื่อน ไม่ใช่ WELCOME/REFUSE ที่มากับการยืนยันตัว)
static func from_host_ok(kind: int) -> bool:
	var d := str(DIR.get(kind, ""))
	return (d == "h" or d == "b") and kind > REFUSE


## ข้อความเป็นไบต์; body ผิดตาราง (หรือใหญ่เกินเพดาน) ได้อาร์เรย์ว่าง
static func encode(kind: int, body: Dictionary) -> PackedByteArray:
	if not is_kind(kind):
		return PackedByteArray()
	var clean := check(kind, body)
	if clean.has("error"):
		return PackedByteArray()
	var out := PackedByteArray([kind])
	if kind == POSE or kind == POSE_STOP:
		var ints := PackedInt64Array()
		for f: String in POSE_FIELDS:
			var v: Variant = clean["body"].get(f, -1)
			ints.append((1 if v else 0) if typeof(v) == TYPE_BOOL else int(v))
		out.append_array(var_to_bytes(ints))
	else:
		out.append_array(var_to_bytes(clean["body"]))
	if out.size() > cap_of(kind):
		return PackedByteArray()
	return out


## ไบต์เป็น {kind, body} หรือ {error}; ดูขนาดก่อนถอดเสมอ
static func decode(bytes: PackedByteArray) -> Dictionary:
	if bytes.size() < 2:
		return {"error": "short"}
	var kind := int(bytes[0])
	if not is_kind(kind):
		return {"error": "kind"}
	if bytes.size() > cap_of(kind):
		return {"error": "size"}
	var v: Variant = bytes_to_var(bytes.slice(1))
	if kind == POSE or kind == POSE_STOP:
		if typeof(v) != TYPE_PACKED_INT64_ARRAY:
			return {"error": "type"}
		var ints: PackedInt64Array = v
		if ints.size() != POSE_FIELDS.size():
			return {"error": "type"}
		var d := {}
		for i: int in POSE_FIELDS.size():
			var f: String = POSE_FIELDS[i]
			if f == "run":
				if ints[i] != 0 and ints[i] != 1:
					return {"error": "range run"}
				d[f] = ints[i] == 1
			elif f == "s":
				if ints[i] >= 0:
					d[f] = ints[i]
			else:
				d[f] = ints[i]
		v = d
	if typeof(v) != TYPE_DICTIONARY:
		return {"error": "type"}
	var c := check(kind, v)
	if c.has("error"):
		return c
	return {"kind": kind, "body": c["body"]}


## ตรวจ body ตามตารางของชนิด: {body: สำเนาที่ตัดช่องเกินแล้ว} หรือ {error}
static func check(kind: int, body: Dictionary) -> Dictionary:
	var schema: Dictionary = SCHEMAS.get(kind, {})
	if not SCHEMAS.has(kind):
		return {"error": "kind"}
	var out := {}
	var err := _obj(body, schema, out, 1)
	if err != "":
		return {"error": "%s: %s" % [kind_name(kind), err]}
	return {"body": out}


static func _obj(d: Dictionary, schema: Dictionary, out: Dictionary, depth: int) -> String:
	if depth > MAX_DEPTH:
		return "deep"
	for k: Variant in d:
		if typeof(k) != TYPE_STRING:
			return "key"
	for key: String in schema:
		var opt := key.begins_with("?")
		var name := key.trim_prefix("?")
		if not d.has(name):
			if opt:
				continue
			return "missing " + name
		var r: Array = [null]
		var e := _field(d[name], schema[key], depth + 1, r)
		if e != "":
			return name + " " + e
		out[name] = r[0]
	return ""


## ตรวจค่าเดียว ใส่ค่าที่ใช้ได้ลง r[0]; คืน "" เมื่อผ่าน
static func _field(v: Variant, spec: Array, depth: int, r: Array) -> String:
	if depth > MAX_DEPTH + 1:
		return "deep"
	var t := typeof(v)
	match str(spec[0]):
		"int":
			if t != TYPE_INT:
				return "type"
			if int(v) < int(spec[1]) or int(v) > int(spec[2]):
				return "range"
			r[0] = v
		"bool":
			if t != TYPE_BOOL:
				return "type"
			r[0] = v
		"false":
			if t != TYPE_BOOL or bool(v):
				return "type"
			r[0] = v
		"intbool":
			if t == TYPE_BOOL:
				r[0] = v
			elif t == TYPE_INT and (int(v) == 0 or int(v) == 1):
				r[0] = v
			else:
				return "type"
		"str":
			if t != TYPE_STRING:
				return "type"
			if String(v).length() > int(spec[1]):
				return "long"
			r[0] = v
		"enum":
			if t != TYPE_STRING or not (spec[1] as Array).has(v):
				return "value"
			r[0] = v
		"hex":
			if t != TYPE_STRING or not is_hex(v, int(spec[1])):
				return "hex"
			r[0] = v
		"obj":
			if t != TYPE_DICTIONARY:
				return "type"
			var o := {}
			var e := _obj(v, spec[1], o, depth)
			if e != "":
				return e
			r[0] = o
		"list":
			if t != TYPE_ARRAY:
				return "type"
			var arr: Array = v
			if arr.size() > int(spec[2]):
				return "items"
			var out: Array = []
			for x: Variant in arr:
				var rr: Array = [null]
				var e := _field(x, spec[1], depth + 1, rr)
				if e != "":
					return "[] " + e
				out.append(rr[0])
			r[0] = out
		"i32s":
			if t != TYPE_PACKED_INT32_ARRAY or (v as PackedInt32Array).size() > int(spec[1]):
				return "type"
			r[0] = v
		"i64s":
			if t != TYPE_PACKED_INT64_ARRAY or (v as PackedInt64Array).size() > int(spec[1]):
				return "type"
			r[0] = v
		"act":
			var e := _act(v, depth)
			if e != "":
				return e
			r[0] = v
		"clean":
			if not clean_value(v, depth, false):
				return "value"
			r[0] = v
		"args":
			if t != TYPE_DICTIONARY:
				return "type"
			var o := {}
			for k: Variant in v:
				if typeof(k) != TYPE_STRING or not ARGS_KEYS.has(k):
					continue
				var x: Variant = v[k]
				if typeof(x) == TYPE_INT or (typeof(x) == TYPE_STRING and String(x).length() <= 64):
					o[k] = x
				else:
					return "args"
			r[0] = o
		_:
			return "spec"
	return ""


## act แบบ ActLog._clean (int bool String Array Dictionary) และ a ต้องเป็นรหัสของ BtActs
static func _act(v: Variant, depth: int) -> String:
	if typeof(v) != TYPE_DICTIONARY:
		return "type"
	var d: Dictionary = v
	if typeof(d.get("a")) != TYPE_STRING or not BtActs.CODES.has(d["a"]):
		return "code"
	if d.has("seq") and typeof(d["seq"]) != TYPE_INT:
		return "seq"
	if d.has("pid") and typeof(d["pid"]) != TYPE_STRING and typeof(d["pid"]) != TYPE_INT:
		return "pid"
	if not clean_value(d, depth, false):
		return "value"
	return ""


## ค่าทั่วไปที่รับได้: int bool String Array Dictionary(คีย์ String) และ (packed = true) PackedInt32/64Array
## ลึกไม่เกิน MAX_DEPTH, อาร์เรย์ไม่เกิน MAX_ITEMS, สตริงไม่เกิน MAX_STR; float และ object ไม่รับ
static func clean_value(v: Variant, depth: int = 1, packed: bool = true) -> bool:
	if depth > MAX_DEPTH + 1:
		return false
	match typeof(v):
		TYPE_INT, TYPE_BOOL:
			return true
		TYPE_STRING:
			return String(v).length() <= MAX_STR
		TYPE_PACKED_INT32_ARRAY:
			return packed and (v as PackedInt32Array).size() <= MAX_ITEMS
		TYPE_PACKED_INT64_ARRAY:
			return packed and (v as PackedInt64Array).size() <= MAX_ITEMS
		TYPE_ARRAY:
			var arr: Array = v
			if arr.size() > MAX_ITEMS:
				return false
			for x: Variant in arr:
				if not clean_value(x, depth + 1, packed):
					return false
			return true
		TYPE_DICTIONARY:
			var d: Dictionary = v
			if d.size() > MAX_ITEMS:
				return false
			for k: Variant in d:
				if typeof(k) != TYPE_STRING or String(k).length() > MAX_STR:
					return false
				if not clean_value(d[k], depth + 1, packed):
					return false
			return true
	return false


## สตริงฐานสิบหกตัวเล็กยาว n ตัวพอดี
static func is_hex(s: String, n: int) -> bool:
	if s.length() != n:
		return false
	for i: int in s.length():
		var c := s.unicode_at(i)
		if not ((c >= 48 and c <= 57) or (c >= 97 and c <= 102)):
			return false
	return true


## ชื่อผู้เล่นเป็นข้อความล้วน: ตัดอักขระควบคุม/ขึ้นบรรทัด/ตัวกำหนดทิศ, ตัดช่องว่างหัวท้าย, ช่องว่างซ้อนเหลือหนึ่ง, ไม่เกิน 20 ตัว
## ตัด { } ด้วย (ชื่อไปอยู่ในแม่แบบที่ String.format เติม เช่น "{name}" แล้วต่อด้วย {max} ห้ามถูกเติมซ้ำ)
static func clean_name(s: String) -> String:
	var out := ""
	var space := false
	for i: int in s.length():
		var c := s.unicode_at(i)
		var ws := c == 32 or c == 9 or c == 10 or c == 13 or c == 0x3000 or c == 0xA0
		if ws:
			space = out != ""
			continue
		if c < 32 or (c >= 0x7F and c <= 0x9F) or (c >= 0x200B and c <= 0x200F) or (c >= 0x202A and c <= 0x202E) \
				or (c >= 0x2066 and c <= 0x2069) or c == 0xFEFF or c == 0x2028 or c == 0x2029 or c == 123 or c == 125:
			continue
		if space:
			out += " "
			space = false
		out += String.chr(c)
	return out.left(NAME_MAX).strip_edges()
