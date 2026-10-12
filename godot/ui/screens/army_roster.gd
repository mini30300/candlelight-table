class_name ArmyRoster
extends RefCounted
## รายชื่อกองทัพของหน้าจัดทัพ: จำนวนหมู่ต่อช่องของ TYPES (ลำดับเดียวกับรายชื่อที่ส่งข้ามเครื่อง) + กองทัพ + งบ
## มีแค่การนับแต้มกับการสุ่มแบบง่าย — เพดานตัวหมาก งบทีม และ autoList จริงมากับแกนกติกา (core/battle/army.gd)
## หน่วยลับไม่ขึ้นในรายชื่อ สุ่มไม่ได้ และไม่นับแต้ม

const CONSTANTS_PATH := "res://data/constants.json"
const DEFAULT_BUDGET := 1000
## กองทัพเริ่มต้นเมื่อยังไม่ได้เลือก (facOf ของหน้าเก่า)
const DEFAULT_FAC := "mod"
const RANDOM_STREAM := "armies"
## สุ่มไม่เกินเท่านี้หมู่ (กันวนไม่จบเมื่องบใหญ่มาก)
const RANDOM_PICKS := 120

var fac := ""
var budget := DEFAULT_BUDGET
var counts := PackedInt32Array()

static var _budgets := PackedInt32Array()


func _init(start_fac: String = "") -> void:
	counts.resize(GameData.count())
	counts.fill(0)
	var facs := GameData.factions()
	if facs.has(start_fac):
		fac = start_fac
	elif facs.has(DEFAULT_FAC):
		fac = DEFAULT_FAC
	elif not facs.is_empty():
		fac = facs[0]
	budget = default_budget()


## ขั้นงบทั้งหมดจาก constants.json BUDGETS (เรียงจากน้อยไปมาก)
static func budgets() -> PackedInt32Array:
	if _budgets.is_empty():
		var data: Variant = null
		if FileAccess.file_exists(CONSTANTS_PATH):
			data = JSON.parse_string(FileAccess.get_file_as_string(CONSTANTS_PATH))
		if data is Dictionary and data.get("BUDGETS") is Array:
			for v in data["BUDGETS"]:
				if typeof(v) == TYPE_FLOAT or typeof(v) == TYPE_INT:
					_budgets.append(int(v))
		if _budgets.is_empty():
			_budgets.append(DEFAULT_BUDGET)
	return _budgets


## งบเริ่มต้น 1000 (หรือขั้นที่ใกล้ที่สุดถ้าไม่มีในรายการ)
static func default_budget() -> int:
	var list := budgets()
	var best := list[0]
	for b in list:
		if absi(b - DEFAULT_BUDGET) < absi(best - DEFAULT_BUDGET):
			best = b
	return best


## หมู่ละไม่เกินเท่านี้ (เพดานของรายชื่อที่ส่งขึ้นห้อง)
static func slot_max() -> int:
	return GameData.const_int("SLOT_MAX", 99)


## หน่วยที่จัดได้ของกองทัพนี้ ตามลำดับ TYPES (ของกองนั้นกับของทุกกอง "*") — ไม่มีหน่วยลับเด็ดขาด
static func units_of(army: String) -> PackedStringArray:
	var out := PackedStringArray()
	for t: Dictionary in GameData.types():
		var f := str(t.get("fac", ""))
		var k := str(t.get("k", ""))
		if (f == army or f == "*") and not GameData.is_hidden(k):
			out.append(k)
	return out


## เปลี่ยนกองทัพ: หน่วยของกองอื่นออกจากรายชื่อ (กองหนึ่งมีได้แค่ชุดเดียว เหมือนหน้าเก่า); คืน false ถ้าไม่เปลี่ยน
func set_fac(army: String) -> bool:
	if army == fac or not GameData.factions().has(army):
		return false
	fac = army
	for i in counts.size():
		var f := str(GameData.types()[i].get("fac", ""))
		if f != army and f != "*":
			counts[i] = 0
	return true


func can_take(k: String) -> bool:
	return GameData.index_of(k) >= 0 and not GameData.is_hidden(k) and units_of(fac).has(k)


func count_of(k: String) -> int:
	var i := GameData.index_of(k)
	return counts[i] if i >= 0 else 0


## เพิ่ม/ลดหมู่ของหน่วย k (0..slot_max); คืน true เมื่อจำนวนเปลี่ยน
func add(k: String, delta: int) -> bool:
	if not can_take(k):
		return false
	var i := GameData.index_of(k)
	var n := clampi(counts[i] + delta, 0, slot_max())
	if n == counts[i]:
		return false
	counts[i] = n
	return true


func clear() -> void:
	counts.fill(0)


## แต้มรวมของรายชื่อ (หน่วยลับไม่นับ)
func points() -> int:
	var sum := 0
	for i in counts.size():
		if counts[i] > 0 and not GameData.is_hidden(GameData.key_at(i)):
			sum += counts[i] * int(GameData.types()[i].get("pts", 0))
	return sum


## จำนวนตัวหมากทั้งกอง
func models() -> int:
	var sum := 0
	for i in counts.size():
		if counts[i] > 0:
			sum += counts[i] * int(GameData.types()[i].get("n", 0))
	return sum


func squads() -> int:
	var sum := 0
	for c in counts:
		sum += c
	return sum


func is_over() -> bool:
	return points() > budget


func is_empty() -> bool:
	return squads() == 0


## ตั้งงบเป็นค่าที่มีในรายการ BUDGETS; คืน false ถ้าไม่มี
func set_budget(b: int) -> bool:
	if not budgets().has(b):
		return false
	budget = b
	return true


## ขยับงบขึ้น/ลงหนึ่งขั้น; คืน false เมื่อสุดทางแล้ว
func step_budget(dir: int) -> bool:
	var list := budgets()
	var i := list.find(budget)
	var j := clampi((i if i >= 0 else 0) + signi(dir), 0, list.size() - 1)
	if list[j] == budget:
		return false
	budget = list[j]
	return true


## รายชื่อแบบที่ส่งข้ามเครื่อง: จำนวนหมู่ต่อช่อง TYPES
func list() -> PackedInt32Array:
	return counts.duplicate()


## สุ่มกองแบบง่ายจาก seed (สตรีม "armies"): หยิบหน่วยจากคลังของบอท (GameData.pool) ที่ยังจ่ายไหวทีละหมู่
## จนไม่มีหน่วยไหนพอดีงบ — seed เดียวกันได้กองเดียวกันทุกครั้ง; ไม่ใช่ autoList ของกติกา
func random_fill(seed_v: int) -> void:
	clear()
	var rng := Rng.make(RANDOM_STREAM, seed_v)
	var allowed := units_of(fac)
	var pool := PackedStringArray()
	for k in GameData.pool(fac):
		if allowed.has(k) and not pool.has(k):
			pool.append(k)
	if pool.is_empty():
		pool = allowed
	var left := budget
	var cap := slot_max()
	for _pick in RANDOM_PICKS:
		var fit := PackedStringArray()
		for k in pool:
			var i := GameData.index_of(k)
			if int(GameData.types()[i].get("pts", 0)) <= left and counts[i] < cap:
				fit.append(k)
		if fit.is_empty():
			break
		var take := GameData.index_of(fit[rng.bounded(fit.size())])
		counts[take] += 1
		left -= int(GameData.types()[take].get("pts", 0))
