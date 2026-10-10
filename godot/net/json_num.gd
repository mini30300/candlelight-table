class_name JsonNum
extends RefCounted
## ตัวเลขบนสายของห้องโต๊ะรบ (ARCHITECTURE §5, R1_PORT_SPEC §2 และ §4): ชั้นนี้อยู่นอกแกน ใช้ float ได้
## ขาเข้า: JSON.parse_string ให้ตัวเลขทุกตัวเป็น float -> แปลงเป็น int ตามที่โปรโตคอลกำหนด ก่อนส่งให้แกน
##   (js_int ของแกนอ่าน float เป็น 0 ชั้นนี้จึงต้องทำก่อนเสมอ) เลขมีเศษหรือเกินช่วง = ผิด บอกเหตุผลใน err ไม่ปัดเป็นศูนย์เงียบ ๆ
##   จุด (to, x, z, dep) บนสายเป็นนิ้วสองตำแหน่ง -> MI (ร้อยส่วน x 10 ตรงพอดี); สตริงคงเป็นสตริง
## ขาออก: เขียน JSON เอง int ไม่มีจุด จุดเป็นทศนิยมจาก int (Dec) ไม่มี float ในข้อความเลย (float = ผิด)
## ฟังก์ชันขาเข้าเติมข้อความผิดลง err ("ทาง: เหตุผล (ค่า)") คนเรียกดูว่า err ยาวขึ้นไหม; act ที่ผิดได้ {}

## จำนวนเต็มที่ double แทนได้พอดี (2^53 - 1)
const SAFE := 9007199254740991
## เพดานพิกัดของ act (num ของ btPost: ±9999 นิ้ว) เป็นร้อยส่วน
const PT_MAX := 999900
## จุดลงสนาม: /dep ±200 นิ้ว, bots ใน state ±999 นิ้ว (ร้อยส่วน)
const DEP_MAX := 20000
const BOT_DEP_MAX := 99900
## เพดานของห้อง (worker.js): ช่องรายชื่อ BT_LIST_LEN, หน่วยต่อช่อง BT_SLOT_MAX, ทีม 0..7, ผู้เล่น BT_MAX_PLAYERS
const LIST_LEN := 512
const SLOT_MAX := 99
const TEAM_MAX := 7
const MAX_PLAYERS := 32
## ความคลาดของ float ที่ยอมเมื่อคูณเป็นร้อยส่วน (p > 0): ไม่เกิน 1e-8 หรือราวสี่ ulp ของค่า (ค่าทศนิยมจริงคลาดไม่ถึงนั้น)
## จำนวนเต็ม (p = 0) ต้องพอดีเป๊ะ
const EPS := 0.00000001
const REL := 0.000000000000001

## ชนิดช่องของ act กติกา: s = สตริง, pt = แถวจุด, c = พิกัดเดียว, d<N> = แถวลูกเต๋าไม่เกิน N, die = ลูกเดียว, bit = 0/1
const ACT_FIELDS := {
	"move": {"u": "s", "x": "c", "z": "c"},
	"endturn": {},
	"shoot": {"u": "s", "t": "s", "how": "s", "hit": "d60", "wound": "d60", "save": "d60"},
	"atk": {"u": "s", "t": "s", "how": "s", "hit": "d60"},
	"wnd": {"u": "s", "t": "s", "wound": "d60"},
	"sav": {"u": "s", "t": "s", "save": "d60", "gtg": "bit"},
	"heal": {"u": "s", "t": "s", "roll": "die"},
	"skip": {"u": "s", "ph": "s"},
	"done": {"ph": "s"},
	"smove": {"u": "s", "how": "s", "to": "pt", "x": "c", "z": "c"},
	"stay": {"u": "s"},
	"adv": {"u": "s", "roll": "die"},
	"rr": {"u": "s", "t": "s", "v": "die"},
	"shock": {"u": "s", "roll": "d2", "brave": "bit"},
	"chg": {"u": "s", "t": "s"},
	"ow": {"u": "s", "t": "s", "use": "bit"},
	"chr": {"u": "s", "t": "s", "roll": "d2", "rr": "bit", "keep": "bit"},
	"cmove": {"u": "s", "t": "s", "to": "pt"},
	"gren": {"u": "s", "t": "s", "roll": "d6"},
	"rez": {"u": "s", "roll": "d10"},
	"endph": {"ph": "s"},
}
## act ที่เซิร์ฟเวอร์สร้างเอง (ไม่ถึงแกน RoomClient จัดการ)
const ROOM_CODES := ["join", "leave", "team", "setup", "list", "dep", "state", "owner"]
## ช่อง int ของ setup: [ต่ำสุด, สูงสุด] (btSetup ของเซิร์ฟเวอร์ ห้องรุ่นเก่าอยู่ในช่วงนี้ด้วย)
const SETUP_INTS := {
	"seed": [1, 99999], "w": [24, 180], "d": [0, 180], "teams": [1, 8], "perTeam": [1, 4], "budget": [0, 40000],
	"clock": [0, 50], "rounds": [3, 10], "v": [0, 999],
}
## ลำดับคีย์ของ curSetup() หน้าเก่า (ขาออก)
const SETUP_KEYS := ["theme", "seed", "w", "terrain", "buildings", "density", "mode", "teams", "perTeam", "budget",
	"freeFire", "clock", "goal", "rounds", "v"]


## ตัวเลขทศนิยม n / 10^p ที่เขียนจาก int (ขาออก)
class Dec:
	extends RefCounted
	var n: int
	var p: int


static func dec(n: int, p: int) -> Dec:
	var d := Dec.new()
	d.n = n
	d.p = p
	return d


# ---------------------------------------------------------------- ขาเข้า: ตัวเลขทีละค่า
## อ่าน JSON (ตัวเลขยังเป็น float) ผิดรูปได้ null และ err
static func parse(text: String, err: Array[String]) -> Variant:
	var j := JSON.new()
	if j.parse(text) != OK:
		err.append("json: %s (line %d)" % [j.get_error_message(), j.get_error_line()])
		return null
	return j.data


## ตัวเลขที่เป็นจำนวนเต็มพอดีในช่วง lo..hi -> int; ผิดได้ 0 และ err
static func int_of(v: Variant, lo: int, hi: int, path: String, err: Array[String]) -> int:
	return scaled(v, 0, lo, hi, path, err)


## ตัวเลขทศนิยมไม่เกิน p ตำแหน่ง -> int ของ v x 10^p ในช่วง lo..hi (หน่วยเดียวกับผล); ผิดได้ 0 และ err
static func scaled(v: Variant, p: int, lo: int, hi: int, path: String, err: Array[String]) -> int:
	var t := typeof(v)
	if t == TYPE_INT:
		var m: int = v
		# |m| <= 2^53 และ p <= 3 จึงคูณไม่ล้น int64
		if absi(m) > SAFE or p > 3:
			err.append("%s: out of range %d..%d (%s)" % [path, lo, hi, str(v)])
			return 0
		for i: int in p:
			m *= 10
		if m < lo or m > hi:
			err.append("%s: out of range %d..%d (%s)" % [path, lo, hi, str(v)])
			return 0
		return m
	if t != TYPE_FLOAT:
		err.append("%s: not a number (%s)" % [path, _show(v)])
		return 0
	var f: float = v
	if is_nan(f) or is_inf(f):
		err.append("%s: not a finite number (%s)" % [path, str(f)])
		return 0
	var x := f * _pow10(p)
	# ตรวจช่วงก่อนแปลงเป็น int (ค่าใหญ่เกิน int64 แปลงไม่ได้)
	if x < float(lo) - 0.5 or x > float(hi) + 0.5 or absf(x) > float(SAFE):
		err.append("%s: out of range %d..%d (%s)" % [path, lo, hi, str(f)])
		return 0
	var r := roundf(x)
	if (p == 0 and x != r) or absf(x - r) > maxf(EPS, absf(x) * REL):
		if p == 0:
			err.append("%s: not a whole number (%s)" % [path, str(f)])
		else:
			err.append("%s: more than %d decimals (%s)" % [path, p, str(f)])
		return 0
	var n := int(r)
	if n < lo or n > hi:
		err.append("%s: out of range %d..%d (%s)" % [path, lo, hi, str(f)])
		return 0
	return n


## 0/1 (หรือ true/false) -> 0/1
static func bit_of(v: Variant, path: String, err: Array[String]) -> int:
	if typeof(v) == TYPE_BOOL:
		return 1 if bool(v) else 0
	return int_of(v, 0, 1, path, err)


## แปลงทั้งโครงสร้าง: ตัวเลขทุกตัวต้องเป็นจำนวนเต็มพอดี (|v| <= 2^53 - 1) สตริง bool null คงเดิม
static func intify(v: Variant, path: String, err: Array[String]) -> Variant:
	match typeof(v):
		TYPE_NIL, TYPE_BOOL, TYPE_STRING, TYPE_INT:
			return v
		TYPE_FLOAT:
			return int_of(v, -SAFE, SAFE, path, err)
		TYPE_ARRAY:
			var out: Array = []
			var a: Array = v
			for i: int in a.size():
				out.append(intify(a[i], "%s[%d]" % [path, i], err))
			return out
		TYPE_DICTIONARY:
			var out := {}
			var d: Dictionary = v
			for k: Variant in d:
				out[k] = intify(d[k], _key(path, k), err)
			return out
	err.append("%s: not a JSON value (%s)" % [path, _show(v)])
	return null


# ---------------------------------------------------------------- ขาเข้า: act
## act กติกาจากห้อง (รูปบนสายหลัง btPost: นิ้ว ตัวเลขเป็น float) -> รูปในแกน (จุดเป็น MI ทุกเลขเป็น int) ลำดับคีย์เดิม
## seq, ts ของห้องเป็น int; pid ต้องเป็นสตริง; ช่องอื่นที่ไม่รู้จักต้องเป็นจำนวนเต็ม; ผิดตรงไหนได้ {} ทั้ง act
## ไม่ได้กรองแทน BtActs.sanitize (ค่าตั้งต้น การตัด การหนีบ อยู่ที่นั่น) แค่ทำให้ตัวเลขเป็นของแกน
static func act_from_wire(raw: Variant, err: Array[String]) -> Dictionary:
	var n0 := err.size()
	if typeof(raw) != TYPE_DICTIONARY:
		err.append("act: not an object (%s)" % _show(raw))
		return {}
	var d: Dictionary = raw
	var code: Variant = d.get("a")
	if typeof(code) != TYPE_STRING:
		err.append("act.a: not a string (%s)" % _show(code))
		return {}
	var path := "act(" + str(code) + ")"
	var fields: Dictionary = ACT_FIELDS.get(code, {})
	var out := {}
	for k: Variant in d:
		var ks := str(k)
		var v: Variant = d[k]
		var p := _key(path, k)
		if typeof(k) != TYPE_STRING:
			err.append("%s: key is not a string" % p)
			continue
		if ks == "a" or ks == "pid":
			out[ks] = _str_of(v, p, err)
		elif ks == "seq" or ks == "ts":
			out[ks] = int_of(v, 0, SAFE, p, err)
		elif fields.has(ks):
			out[ks] = _field(str(fields[ks]), v, p, err)
		else:
			out[ks] = intify(v, p, err)
	return out if err.size() == n0 else {}


## act ใดก็ได้ในสตรีมของห้อง: act กติกาผ่าน act_from_wire, act ของเซิร์ฟเวอร์ (join/.../owner) ตามรูปของ btPush
## รหัสที่ไม่รู้จักแปลงแบบ intify; ผิดได้ {}
static func room_act(raw: Variant, err: Array[String]) -> Dictionary:
	if typeof(raw) != TYPE_DICTIONARY:
		err.append("act: not an object (%s)" % _show(raw))
		return {}
	var d: Dictionary = raw
	var code: Variant = d.get("a")
	if typeof(code) == TYPE_STRING and ACT_FIELDS.has(code):
		return act_from_wire(d, err)
	if typeof(code) != TYPE_STRING:
		err.append("act.a: not a string (%s)" % _show(code))
		return {}
	var n0 := err.size()
	var path := "act(" + str(code) + ")"
	var out := {}
	for k: Variant in d:
		var ks := str(k)
		var v: Variant = d[k]
		var p := _key(path, k)
		match ks:
			"a", "pid", "nm", "state":
				out[ks] = _str_of(v, p, err)
			"seq", "ts":
				out[ks] = int_of(v, 0, SAFE, p, err)
			"team":
				out[ks] = int_of(v, 0, TEAM_MAX, p, err)
			"setup":
				out[ks] = setup_from_wire(v, p, err)
			"list":
				out[ks] = list_from_wire(v, p, err)
			"sk":
				out[ks] = skin_from_wire(v, p, err)
			"dep":
				out[ks] = dep_from_wire(v, DEP_MAX, p, err)
			"bots":
				out[ks] = _seats_from_wire(v, BOT_DEP_MAX, p, err)
			"roster":
				out[ks] = _seats_from_wire(v, DEP_MAX, p, err)
			_:
				out[ks] = intify(v, p, err)
	return out if err.size() == n0 else {}


# ---------------------------------------------------------------- ขาเข้า: ห้อง setup รายชื่อ จุดลงสนาม
## setup ของห้อง (btSetup) -> รูปของ BattleState.make: density (0.05..2.5) เป็น density_h (ร้อยส่วน) ช่องอื่นเป็น int
## bool คงเป็น bool; ช่องที่ไม่รู้จักแปลงแบบ intify
static func setup_from_wire(raw: Variant, path: String, err: Array[String]) -> Dictionary:
	if typeof(raw) != TYPE_DICTIONARY:
		err.append("%s: not an object (%s)" % [path, _show(raw)])
		return {}
	var d: Dictionary = raw
	var out := {}
	for k: Variant in d:
		var ks := str(k)
		var v: Variant = d[k]
		var p := _key(path, k)
		if ks == "density":
			out["density_h"] = scaled(v, 2, 5, 250, p, err)
		elif SETUP_INTS.has(ks):
			var r: Array = SETUP_INTS[ks]
			out[ks] = int_of(v, int(r[0]), int(r[1]), p, err)
		elif ks == "buildings" or ks == "freeFire":
			if typeof(v) == TYPE_BOOL:
				out[ks] = v
			else:
				out[ks] = bit_of(v, p, err) != 0
		elif ks == "theme" or ks == "terrain" or ks == "mode" or ks == "goal":
			out[ks] = _str_of(v, p, err)
		else:
			out[ks] = intify(v, p, err)
	return out


## รายชื่อกองทัพ (btList): แถว int 0..99 ไม่เกิน 512 ช่อง
static func list_from_wire(raw: Variant, path: String, err: Array[String]) -> Array:
	var out: Array = []
	if typeof(raw) != TYPE_ARRAY:
		err.append("%s: not an array (%s)" % [path, _show(raw)])
		return out
	var a: Array = raw
	if a.size() > LIST_LEN:
		err.append("%s: more than %d slots (%d)" % [path, LIST_LEN, a.size()])
		return out
	for i: int in a.size():
		out.append(int_of(a[i], 0, SLOT_MAX, "%s[%d]" % [path, i], err))
	return out


## สกินที่เลือก (btSkins): {ชนิดหน่วย: 1..9}
static func skin_from_wire(raw: Variant, path: String, err: Array[String]) -> Dictionary:
	var out := {}
	if typeof(raw) != TYPE_DICTIONARY:
		err.append("%s: not an object (%s)" % [path, _show(raw)])
		return out
	var d: Dictionary = raw
	for k: Variant in d:
		out[str(k)] = int_of(d[k], 1, 9, _key(path, k), err)
	return out


## จุดลงสนาม: null ได้ [] ; [x, z] นิ้วสองตำแหน่ง -> [x, z] MI (lim เป็นร้อยส่วน)
static func dep_from_wire(raw: Variant, lim: int, path: String, err: Array[String]) -> Array:
	if typeof(raw) == TYPE_NIL:
		return []
	if typeof(raw) != TYPE_ARRAY or (raw as Array).size() != 2:
		err.append("%s: not null or [x, z] (%s)" % [path, _show(raw)])
		return []
	var a: Array = raw
	return [10 * scaled(a[0], 2, -lim, lim, path + "[0]", err), 10 * scaled(a[1], 2, -lim, lim, path + "[1]", err)]


## สถานะห้อง (btPublic: GET /:code และ room ของ create/join): setup, players, seq, acts ทีละตัว
## act ที่ผิดไม่ทำให้ทั้งห้องผิด: แทนด้วย {seq, a, bad: เหตุผล} (เลข seq ยังเดินต่อได้) และเหตุผลลง err ด้วย
## board (ภาพกระดานของเจ้าของห้อง) x/z เป็นสิบส่วน (int) ช่องอื่นแบบ intify
static func room_from_wire(raw: Variant, err: Array[String]) -> Dictionary:
	if typeof(raw) != TYPE_DICTIONARY:
		err.append("room: not an object (%s)" % _show(raw))
		return {}
	var d: Dictionary = raw
	var out := {}
	for k: Variant in d:
		var ks := str(k)
		var v: Variant = d[k]
		var p := _key("room", k)
		match ks:
			"code", "kind", "state", "ownerPid":
				out[ks] = v if typeof(v) == TYPE_NIL else _str_of(v, p, err)
			"seq":
				out[ks] = int_of(v, 0, SAFE, p, err)
			"seats":
				out[ks] = int_of(v, 0, MAX_PLAYERS, p, err)
			"setup":
				out[ks] = setup_from_wire(v, p, err)
			"players":
				out[ks] = _players_from_wire(v, p, err)
			"board":
				out[ks] = null if typeof(v) == TYPE_NIL else _board_from_wire(v, p, err)
			"acts":
				out[ks] = _acts_from_wire(v, p, err)
			_:
				out[ks] = intify(v, p, err)
	return out


static func _players_from_wire(raw: Variant, path: String, err: Array[String]) -> Array:
	var out: Array = []
	if typeof(raw) != TYPE_ARRAY:
		err.append("%s: not an array (%s)" % [path, _show(raw)])
		return out
	var a: Array = raw
	for i: int in a.size():
		var pp := "%s[%d]" % [path, i]
		if typeof(a[i]) != TYPE_DICTIONARY:
			err.append("%s: not an object (%s)" % [pp, _show(a[i])])
			continue
		var pd: Dictionary = a[i]
		var o := {}
		for k: Variant in pd:
			var ks := str(k)
			var v: Variant = pd[k]
			var p := _key(pp, k)
			match ks:
				"pid", "nm":
					o[ks] = _str_of(v, p, err)
				"team":
					o[ks] = int_of(v, 0, TEAM_MAX, p, err)
				"list":
					o[ks] = list_from_wire(v, p, err)
				"sk":
					o[ks] = skin_from_wire(v, p, err)
				"dep":
					o[ks] = dep_from_wire(v, DEP_MAX, p, err)
				_:
					o[ks] = intify(v, p, err)
		out.append(o)
	return out


## bots / roster ของ act state: [{pid?, team, list, sk?, dep}]
static func _seats_from_wire(raw: Variant, lim: int, path: String, err: Array[String]) -> Array:
	var out: Array = []
	if typeof(raw) != TYPE_ARRAY:
		err.append("%s: not an array (%s)" % [path, _show(raw)])
		return out
	var a: Array = raw
	if a.size() > MAX_PLAYERS:
		err.append("%s: more than %d seats (%d)" % [path, MAX_PLAYERS, a.size()])
		return out
	for i: int in a.size():
		var pp := "%s[%d]" % [path, i]
		if typeof(a[i]) != TYPE_DICTIONARY:
			err.append("%s: not an object (%s)" % [pp, _show(a[i])])
			continue
		var sd: Dictionary = a[i]
		var o := {}
		for k: Variant in sd:
			var ks := str(k)
			var v: Variant = sd[k]
			var p := _key(pp, k)
			match ks:
				"pid":
					o[ks] = _str_of(v, p, err)
				"team":
					o[ks] = int_of(v, 0, TEAM_MAX, p, err)
				"list":
					o[ks] = list_from_wire(v, p, err)
				"sk":
					o[ks] = skin_from_wire(v, p, err)
				"dep":
					o[ks] = dep_from_wire(v, lim, p, err)
				_:
					o[ks] = intify(v, p, err)
		out.append(o)
	return out


static func _acts_from_wire(raw: Variant, path: String, err: Array[String]) -> Array:
	var out: Array = []
	if typeof(raw) != TYPE_ARRAY:
		err.append("%s: not an array (%s)" % [path, _show(raw)])
		return out
	var a: Array = raw
	for i: int in a.size():
		var mine: Array[String] = []
		var act := room_act(a[i], mine)
		if mine.is_empty():
			out.append(act)
			continue
		var pp := "%s[%d]" % [path, i]
		for m: String in mine:
			err.append(pp + " " + m)
		# เก็บ seq ไว้ให้นับต่อได้ (seq ที่อ่านไม่ได้ = ทิ้งทั้งตัว)
		var seq_err: Array[String] = []
		var seq := -1
		var code := ""
		if typeof(a[i]) == TYPE_DICTIONARY:
			var ad: Dictionary = a[i]
			seq = int_of(ad.get("seq"), 0, SAFE, pp + ".seq", seq_err)
			code = str(ad.get("a")) if typeof(ad.get("a")) == TYPE_STRING else ""
		if seq_err.is_empty() and seq >= 0:
			out.append({"seq": seq, "a": code, "bad": mine[0]})
	return out


## ภาพกระดาน (btBoard): x, z เป็นสิบส่วน (±2000) ทุกที่ ตัวเลขอื่นต้องเป็นจำนวนเต็ม
static func _board_from_wire(v: Variant, path: String, err: Array[String]) -> Variant:
	match typeof(v):
		TYPE_ARRAY:
			var out: Array = []
			var a: Array = v
			for i: int in a.size():
				out.append(_board_from_wire(a[i], "%s[%d]" % [path, i], err))
			return out
		TYPE_DICTIONARY:
			var out := {}
			var d: Dictionary = v
			for k: Variant in d:
				var ks := str(k)
				if (ks == "x" or ks == "z") and typeof(d[k]) != TYPE_STRING:
					out[ks] = scaled(d[k], 1, -2000, 2000, _key(path, k), err)
				else:
					out[ks] = _board_from_wire(d[k], _key(path, k), err)
			return out
	return intify(v, path, err)


## ช่องหนึ่งของ act กติกาตามชนิดใน ACT_FIELDS
static func _field(kind: String, v: Variant, path: String, err: Array[String]) -> Variant:
	match kind:
		"s":
			return _str_of(v, path, err)
		"c":
			return 10 * scaled(v, 2, -PT_MAX, PT_MAX, path, err)
		"die":
			return int_of(v, 1, 6, path, err)
		"bit":
			return bit_of(v, path, err)
		"pt":
			return _pts_of(v, path, err)
	# d<N>: แถวลูกเต๋า 1..6 ไม่เกิน N ลูก
	var cap := kind.substr(1).to_int()
	var out: Array = []
	if typeof(v) != TYPE_ARRAY:
		err.append("%s: not an array (%s)" % [path, _show(v)])
		return out
	var a: Array = v
	if a.size() > cap:
		err.append("%s: more than %d dice (%d)" % [path, cap, a.size()])
		return out
	for i: int in a.size():
		out.append(int_of(a[i], 1, 6, "%s[%d]" % [path, i], err))
	return out


## แถวจุด [[x, z], ...] ไม่เกิน 40 จุด นิ้วสองตำแหน่ง -> MI
static func _pts_of(v: Variant, path: String, err: Array[String]) -> Array:
	var out: Array = []
	if typeof(v) != TYPE_ARRAY:
		err.append("%s: not an array (%s)" % [path, _show(v)])
		return out
	var a: Array = v
	if a.size() > BtActs.MAX_PTS:
		err.append("%s: more than %d points (%d)" % [path, BtActs.MAX_PTS, a.size()])
		return out
	for i: int in a.size():
		var pp := "%s[%d]" % [path, i]
		if typeof(a[i]) != TYPE_ARRAY or (a[i] as Array).size() != 2:
			err.append("%s: not [x, z] (%s)" % [pp, _show(a[i])])
			continue
		var q: Array = a[i]
		out.append([10 * scaled(q[0], 2, -PT_MAX, PT_MAX, pp + "[0]", err),
			10 * scaled(q[1], 2, -PT_MAX, PT_MAX, pp + "[1]", err)])
	return out


static func _str_of(v: Variant, path: String, err: Array[String]) -> String:
	if typeof(v) == TYPE_STRING:
		return str(v)
	err.append("%s: not a string (%s)" % [path, _show(v)])
	return ""


static func _key(path: String, k: Variant) -> String:
	return path + "." + str(k)


static func _show(v: Variant) -> String:
	return ("null" if typeof(v) == TYPE_NIL else str(v)).left(60)


static func _pow10(p: int) -> float:
	var x := 1.0
	for i: int in p:
		x *= 10.0
	return x


# ---------------------------------------------------------------- ขาออก
## act รูปในแกน -> รูปบนสาย: BtActs.to_wire (MI เป็นร้อยส่วน) แล้วห่อ to/x/z เป็น Dec สองตำแหน่ง (ข้อความ 12.34)
static func act_to_wire(act: Dictionary) -> Dictionary:
	var w := BtActs.to_wire(act)
	for k: String in ["x", "z"]:
		if typeof(w.get(k)) == TYPE_INT:
			w[k] = dec(int(w[k]), 2)
	if typeof(w.get("to")) == TYPE_ARRAY:
		var pts: Array = []
		for q: Variant in w["to"]:
			if typeof(q) == TYPE_ARRAY and (q as Array).size() == 2 and typeof(q[0]) == TYPE_INT and typeof(q[1]) == TYPE_INT:
				pts.append([dec(int(q[0]), 2), dec(int(q[1]), 2)])
			else:
				pts.append(q)
		w["to"] = pts
	return w


## เนื้อ POST /:code/act แบบ netSend ของหน้าเก่า: {"pid":…,"act":…} ผิด (มี float) ได้ "" และ err
## จุดต้องอยู่บนตาราง 10 MI: เครื่องผู้ส่งใช้ act ของตัวเองก่อนส่ง จุดนอกตารางจะถูกปัดบนสาย เครื่องอื่นเห็นไม่ตรง จึงไม่ส่ง
static func act_body(pid: String, act: Dictionary, err: Array[String]) -> String:
	var n0 := err.size()
	for k: String in ["x", "z"]:
		if typeof(act.get(k)) == TYPE_INT and int(act[k]) % 10 != 0:
			err.append("act.%s: off the 10 MI grid (%d)" % [k, int(act[k])])
	if typeof(act.get("to")) == TYPE_ARRAY:
		var pts: Array = act["to"]
		for i: int in pts.size():
			var q: Variant = pts[i]
			if typeof(q) == TYPE_ARRAY and _len(q) == 2:
				for j: int in 2:
					if typeof(q[j]) == TYPE_INT and int(q[j]) % 10 != 0:
						err.append("act.to[%d][%d]: off the 10 MI grid (%d)" % [i, j, int(q[j])])
	if err.size() != n0:
		return ""
	return stringify({"pid": pid, "act": act_to_wire(act)}, err)


## setup รูปในแกน (BattleState.setup_dict หรือของ UI) -> curSetup() ของหน้าเก่า: density จาก density_h, bool จริง,
## ไม่มี d (เซิร์ฟเวอร์คิดเอง) v = รุ่นกติกา; คีย์ตามลำดับของหน้าเก่า คีย์ที่ไม่มีข้าม
static func setup_to_wire(setup: Dictionary) -> Dictionary:
	var out := {}
	for k: String in SETUP_KEYS:
		match k:
			"density":
				if setup.has("density_h"):
					out[k] = dec(int(setup["density_h"]), 2)
			"buildings", "freeFire":
				if setup.has(k):
					var v: Variant = setup[k]
					out[k] = bool(v) if typeof(v) == TYPE_BOOL else int(v) != 0
			"v":
				out[k] = Version.RULES_V
			_:
				if setup.has(k):
					out[k] = setup[k]
	return out


## จุดลงสนาม MI -> [x, z] บนสาย (ร้อยส่วนแบบ toFixed(2) เหมือนจุดของ act); ไม่มีจุดได้ null
static func dep_to_wire(dep: Variant) -> Variant:
	if typeof(dep) == TYPE_PACKED_INT64_ARRAY or typeof(dep) == TYPE_ARRAY:
		if _len(dep) == 2 and typeof(dep[0]) == TYPE_INT and typeof(dep[1]) == TYPE_INT:
			return [dec(BtActs.hundredths(dep[0]), 2), dec(BtActs.hundredths(dep[1]), 2)]
	return null


static func _len(v: Variant) -> int:
	if typeof(v) == TYPE_ARRAY:
		return (v as Array).size()
	if typeof(v) == TYPE_PACKED_INT64_ARRAY:
		return (v as PackedInt64Array).size()
	return 0


## JSON แบบ JSON.stringify ของ JS ไม่มีช่องว่าง ลำดับคีย์ตามที่ใส่: int ไม่มีจุด Dec เป็นทศนิยมสั้นสุด
## float หรือค่าที่เขียนไม่ได้ = ผิด ได้ "" และ err (ไม่มีวันเขียน float ลงสาย)
static func stringify(v: Variant, err: Array[String]) -> String:
	var n0 := err.size()
	var s := _w(v, "$", err)
	return s if err.size() == n0 else ""


static func _w(v: Variant, path: String, err: Array[String]) -> String:
	match typeof(v):
		TYPE_NIL:
			return "null"
		TYPE_BOOL:
			return "true" if bool(v) else "false"
		TYPE_INT:
			var n: int = v
			if absi(n) > SAFE:
				err.append("%s: int beyond 2^53 (%d)" % [path, n])
			return str(n)
		TYPE_STRING, TYPE_STRING_NAME:
			return quote(str(v))
		TYPE_DICTIONARY:
			var d: Dictionary = v
			var parts := PackedStringArray()
			for k: Variant in d:
				if typeof(k) != TYPE_STRING and typeof(k) != TYPE_STRING_NAME:
					err.append("%s: key is not a string (%s)" % [path, str(k)])
					continue
				parts.append(quote(str(k)) + ":" + _w(d[k], _key(path, k), err))
			return "{" + ",".join(parts) + "}"
		TYPE_ARRAY, TYPE_PACKED_INT32_ARRAY, TYPE_PACKED_INT64_ARRAY, TYPE_PACKED_STRING_ARRAY:
			var parts := PackedStringArray()
			var i := 0
			for x: Variant in v:
				parts.append(_w(x, "%s[%d]" % [path, i], err))
				i += 1
			return "[" + ",".join(parts) + "]"
		TYPE_OBJECT:
			if v is Dec:
				var dv: Dec = v
				if absi(dv.n) > SAFE or dv.p < 0 or dv.p > 15:
					err.append("%s: decimal out of range (%d, %d)" % [path, dv.n, dv.p])
					return "0"
				return dec_text(dv.n, dv.p)
		TYPE_FLOAT:
			err.append("%s: float on the wire (%s)" % [path, str(v)])
			return "0"
	err.append("%s: cannot write (%s)" % [path, _show(v)])
	return "null"


## n / 10^p เป็นตัวเลข JS สั้นสุด: ไม่มีศูนย์ท้าย จำนวนเต็มไม่มีจุด ศูนย์ไม่มีเครื่องหมาย (1234, 2 -> 12.34; -5, 2 -> -0.05)
static func dec_text(n: int, p: int) -> String:
	var neg := n < 0
	var s := str(-n if neg else n)
	if p > 0:
		s = s.lpad(p + 1, "0")
		var ip := s.substr(0, s.length() - p)
		var fp := s.substr(s.length() - p)
		while fp.ends_with("0"):
			fp = fp.left(fp.length() - 1)
		s = ip if fp == "" else ip + "." + fp
	return "-" + s if neg else s


## สตริงแบบ JSON.stringify ของ JS: หนีเฉพาะ " \ อักขระควบคุม (ชื่อสั้นหรือ \u00xx ตัวเล็ก) ที่เหลือคงเดิม
static func quote(s: String) -> String:
	var out := "\""
	for i: int in s.length():
		var c := s.unicode_at(i)
		match c:
			34:
				out += "\\\""
			92:
				out += "\\\\"
			8:
				out += "\\b"
			9:
				out += "\\t"
			10:
				out += "\\n"
			12:
				out += "\\f"
			13:
				out += "\\r"
			_:
				if c < 32 or (c >= 55296 and c <= 57343):
					out += "\\u%04x" % c
				else:
					out += String.chr(c)
	return out + "\""
