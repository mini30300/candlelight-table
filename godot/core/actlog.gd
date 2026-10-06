class_name ActLog
extends RefCounted
## บันทึก act ตามลำดับ (ARCHITECTURE §4): แต่ละรายการ {seq, pid, a, ...} seq เริ่ม 1 และต่อเนื่อง
## ค่าใน act เป็น int / String / bool / Array / Dictionary เท่านั้น (JSON ไม่มีทศนิยม) ทุกเครื่องจึงได้ JSON เดียวกัน

var _acts: Array[Dictionary] = []
## เหตุผลที่ append/restore/from_json ล่าสุดไม่รับ ("" = รับ)
var error: String = ""
var _bad := false


## จำนวน act
func size() -> int:
	return _acts.size()


## seq ล่าสุด (0 เมื่อว่าง)
func last_seq() -> int:
	return _acts.size()


## เพิ่ม act: ต้องมี a (String ไม่ว่าง) และ pid (int หรือ String); seq ถ้ามีต้องเท่ากับ last_seq()+1 ไม่มีก็เติมให้
## คืน seq ที่ได้ หรือ -1 ถ้าไม่รับ (ดู error)
func append(act: Dictionary) -> int:
	var seq := last_seq() + 1
	error = _why_bad(act, seq)
	if error != "":
		return -1
	_acts.append(canon(act, seq))
	return seq


func _why_bad(act: Dictionary, want_seq: int) -> String:
	if not act.has("a") or typeof(act["a"]) != TYPE_STRING or String(act["a"]).is_empty():
		return "bad_a"
	if not act.has("pid") or (typeof(act["pid"]) != TYPE_INT and typeof(act["pid"]) != TYPE_STRING):
		return "bad_pid"
	if act.has("seq") and (typeof(act["seq"]) != TYPE_INT or int(act["seq"]) != want_seq):
		return "bad_seq"
	if not _clean(act):
		return "bad_value"
	return ""


## ค่าที่อนุญาต: int, bool, String และ Array/Dictionary ของค่าที่อนุญาต (คีย์เป็น String)
static func _clean(v: Variant) -> bool:
	match typeof(v):
		TYPE_INT, TYPE_BOOL, TYPE_STRING:
			return true
		TYPE_ARRAY:
			for x: Variant in v:
				if not _clean(x):
					return false
			return true
		TYPE_DICTIONARY:
			for k: Variant in v:
				if typeof(k) != TYPE_STRING or not _clean(v[k]):
					return false
			return true
	return false


## รูปมาตรฐานของ act: คีย์ seq, pid, a ก่อน ที่เหลือเรียงตามชื่อ (ซ้อนในก็เรียง) JSON จึงเท่ากันทุกเครื่อง
static func canon(act: Dictionary, seq: int) -> Dictionary:
	var out := {"seq": seq, "pid": act["pid"], "a": act["a"]}
	var keys: Array = act.keys()
	keys.sort()
	for k: Variant in keys:
		if k == "seq" or k == "pid" or k == "a":
			continue
		out[k] = _canon_value(act[k])
	return out


static func _canon_value(v: Variant) -> Variant:
	match typeof(v):
		TYPE_ARRAY:
			var arr: Array = []
			for x: Variant in v:
				arr.append(_canon_value(x))
			return arr
		TYPE_DICTIONARY:
			var d := {}
			var keys: Array = v.keys()
			keys.sort()
			for k: Variant in keys:
				d[k] = _canon_value(v[k])
			return d
	return v


## สำเนา act ทั้งหมด (แก้สำเนาไม่กระทบบันทึก)
func acts() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for a: Dictionary in _acts:
		out.append(a.duplicate(true))
	return out


## act ที่ seq นั้น ({} ถ้าไม่มี)
func at(seq: int) -> Dictionary:
	if seq < 1 or seq > _acts.size():
		return {}
	return _acts[seq - 1].duplicate(true)


## act ที่ seq มากกว่า since_seq (เหมือน ?since= ของเซิร์ฟเวอร์)
func since(since_seq: int) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var i := maxi(since_seq, 0)
	while i < _acts.size():
		out.append(_acts[i].duplicate(true))
		i += 1
	return out


## ล้างบันทึก
func clear() -> void:
	_acts.clear()
	error = ""


## {"seq": last_seq, "acts": [...]} สำเนาลึก
func snapshot() -> Dictionary:
	return {"seq": last_seq(), "acts": acts()}


## คืนค่าจาก snapshot(): ตรวจทุก act ก่อน ถ้าผิดคืน false และไม่แก้ของเดิม
func restore(d: Dictionary) -> bool:
	error = ""
	if not d.has("acts") or typeof(d["acts"]) != TYPE_ARRAY:
		error = "bad_snapshot"
		return false
	var fresh: Array[Dictionary] = []
	for a: Variant in d["acts"]:
		if typeof(a) != TYPE_DICTIONARY:
			error = "bad_snapshot"
			return false
		var want := fresh.size() + 1
		var why := _why_bad(a, want)
		if why != "":
			error = why
			return false
		fresh.append(canon(a, want))
	if d.has("seq") and (typeof(d["seq"]) != TYPE_INT or int(d["seq"]) != fresh.size()):
		error = "bad_seq"
		return false
	_acts = fresh
	return true


## JSON ของ snapshot() (ไม่มีช่องว่าง ไม่มีทศนิยม; ไม่ให้ stringify เรียงคีย์ เพราะ canon เรียงไว้แล้ว)
func to_json() -> String:
	return JSON.stringify(snapshot(), "", false)


## อ่าน JSON จาก to_json(): JSON ของ Godot อ่านตัวเลขเป็นทศนิยม จึงแปลงกลับเป็น int ทั้งโครงสร้าง; ผิดรูปคืน false
func from_json(s: String) -> bool:
	var parser := JSON.new()
	if parser.parse(s) != OK or typeof(parser.data) != TYPE_DICTIONARY:
		error = "bad_json"
		return false
	_bad = false
	var d: Variant = _intify(parser.data)
	if _bad:
		error = "bad_value"
		return false
	return restore(d)


## แปลงตัวเลขที่เป็นจำนวนเต็มพอดีเป็น int ทั้งโครงสร้าง; มีเศษหรือ null ตั้ง _bad
func _intify(v: Variant) -> Variant:
	match typeof(v):
		TYPE_INT, TYPE_BOOL, TYPE_STRING:
			return v
		TYPE_ARRAY:
			var arr: Array = []
			for x: Variant in v:
				arr.append(_intify(x))
			return arr
		TYPE_DICTIONARY:
			var d := {}
			for k: Variant in v:
				d[k] = _intify(v[k])
			return d
		TYPE_NIL:
			_bad = true
			return 0
	# ที่เหลือคือตัวเลขจาก JSON: รับเฉพาะที่เป็นจำนวนเต็มพอดี
	var i := int(v)
	if i != v:
		_bad = true
	return i
