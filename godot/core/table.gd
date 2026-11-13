class_name Table
extends RefCounted
## ฐานของโต๊ะ (ARCHITECTURE §4): สถานะเปลี่ยนได้ทาง apply(act) เท่านั้น ทุก act ถูกบันทึก และ advance() ตามทุกครั้ง
## คลาสลูก (โต๊ะรบ, โต๊ะ D&D) override codes(), _on_act(), _advance_step(), state_ints(), snapshot()/restore()

## จำนวนก้าวสูงสุดของ advance() ต่อหนึ่งครั้ง (กันวนไม่รู้จบ)
const ADVANCE_GUARD := 60

var seed: int = 0
var rules_v: int = Version.RULES_V
## บันทึก act ตามลำดับ
var actlog: ActLog = ActLog.new()
var turn: int = 0
var round_no: int = 0
var phase: int = 0
var over: int = 0
## จำนวน act ที่ใช้แล้ว
var applied: int = 0
## เหตุผลที่ apply/restore ล่าสุดไม่รับ ("" = รับ)
var last_error: String = ""


func _init(p_seed: int = 0) -> void:
	seed = p_seed


## รหัส act ที่โต๊ะนี้รับ (ฐานรับแค่ "nop")
func codes() -> PackedStringArray:
	return PackedStringArray(["nop"])


## ใช้ act หนึ่งรายการ: ตรวจ → บันทึก → _on_act → advance; คืนเหตุการณ์ทั้งหมด
## act ที่ผิดได้ BAD_ACT {key, seq ที่ต้องการ, a} และไม่ถูกบันทึก
func apply(act: Dictionary) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var err := _check(act)
	if err == "":
		var seq := actlog.append(act)
		if seq < 0:
			err = actlog.error
		else:
			applied += 1
			last_error = ""
			out.append_array(_on_act(actlog.at(seq)))
			out.append_array(advance())
			return out
	last_error = err
	out.append(Events.make(Events.Id.BAD_ACT, {"key": err, "seq": actlog.last_seq() + 1, "a": str(act.get("a", ""))}))
	return out


## ตรวจรหัส act ก่อนบันทึก (pid/seq/ค่า ตรวจใน ActLog.append)
func _check(act: Dictionary) -> String:
	if not act.has("a") or typeof(act["a"]) != TYPE_STRING:
		return "bad_a"
	if not codes().has(String(act["a"])):
		return "bad_code"
	return ""


## กติกาของ act ที่บันทึกแล้ว (รูปมาตรฐาน มี seq); ฐานรู้จักแค่ nop
func _on_act(act: Dictionary) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if String(act["a"]) == "nop":
		out.append(Events.make(Events.Id.LOG_LINE, {"key": "nop", "args": [int(act["seq"])]}))
	return out


## เดินสถานะต่อจนนิ่ง (ไม่เกิน ADVANCE_GUARD ก้าว) คืนเหตุการณ์ที่เกิด
func advance() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var guard := 0
	while guard < ADVANCE_GUARD and _advance_step(out):
		guard += 1
	if guard >= ADVANCE_GUARD:
		out.append(Events.make(Events.Id.LOG_LINE, {"key": "advance_guard", "args": [guard]}))
	return out


## หนึ่งก้าวของ advance: คืน true ถ้ามีอะไรเปลี่ยนและต้องเดินต่อ (ฐานไม่มีอะไรให้เดิน)
func _advance_step(_out: Array[Dictionary]) -> bool:
	return false


## ใช้ act หลายรายการตามลำดับ (เช่นตอนเข้าห้องช้า) คืนจำนวนที่ใช้ได้ หยุดที่รายการแรกที่ผิด
func replay(acts: Array) -> int:
	var n := 0
	for a: Variant in acts:
		if typeof(a) != TYPE_DICTIONARY:
			last_error = "bad_act"
			return n
		apply(a)
		if last_error != "":
			return n
		n += 1
	return n


## สถานะเป็นอาร์เรย์ int ตามลำดับคงที่ (คลาสลูกต่อท้าย); digest คิดจากอันนี้
func state_ints() -> PackedInt64Array:
	return PackedInt64Array([rules_v, seed, actlog.last_seq(), applied, turn, round_no, phase, over])


## FNV-1a 64 ของ state_ints() เป็นฐานสิบหก 16 ตัว เทียบกันข้ามเครื่องได้
func digest() -> String:
	return Hash.digest_hex(state_ints())


## ภาพรวมสถานะ (int ล้วน) รวมบันทึก act สำหรับเก็บลงเครื่องหรือส่งให้คนเข้าห้องช้า
func snapshot() -> Dictionary:
	return {
		"v": rules_v, "seed": seed, "turn": turn, "round": round_no, "phase": phase, "over": over,
		"applied": applied, "log": actlog.snapshot(),
	}


## คืนค่าจาก snapshot(); รุ่นกติกาต้องตรง ผิดรูปคืน false และไม่แก้อะไร
func restore(d: Dictionary) -> bool:
	for k: String in ["v", "seed", "turn", "round", "phase", "over", "applied"]:
		if not d.has(k) or typeof(d[k]) != TYPE_INT:
			last_error = "bad_snapshot"
			return false
	if not d.has("log") or typeof(d["log"]) != TYPE_DICTIONARY:
		last_error = "bad_snapshot"
		return false
	if int(d["v"]) != rules_v:
		last_error = "bad_version"
		return false
	var fresh := ActLog.new()
	if not fresh.restore(d["log"]):
		last_error = fresh.error
		return false
	seed = int(d["seed"])
	turn = int(d["turn"])
	round_no = int(d["round"])
	phase = int(d["phase"])
	over = int(d["over"])
	applied = int(d["applied"])
	actlog = fresh
	last_error = ""
	return true
