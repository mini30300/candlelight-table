class_name Lockstep
extends RefCounted
## การรบแบบล็อกสเต็ปบนแกนเดิม (NET_SPEC §4) ไม่มี Node ไม่รู้จักซ็อกเก็ต: ส่งผ่าน send.call(kind, body, to_slot) เท่านั้น
## เจ้าห้องเรียงทุก act (host_logged → คิว → end_burst ส่ง ACT พร้อม dg) ตรวจคำขอของเพื่อน (host_request / gate)
## เพื่อนใช้เฉพาะ ACT ของเจ้าห้องตามลำดับ seq (client_act) เทียบ digest ทุกครั้งที่มี dg ไม่ตรง = DESYNC ดัง ๆ ไม่เงียบ
## รหัสข้อความจาก NetProto (สัญญาข้ามแทร็ก §11.1 ข้อ 4) · เวลาเครื่องไม่เข้าแกน (ROLL_WAIT_MS ใช้ที่ตัวคุมเกม)

const DIGEST_EVERY := 8
const ROLL_WAIT_MS := 15000
## คำตอบลูกเต๋า (ต้องตรงกับรายการแรกที่รอทอยและผู้ทอยเป็นที่นั่งนี้)
const ROLL_CODES: PackedStringArray = ["wnd", "sav", "rr", "shock", "rez", "ow", "chr", "cmove"]
## การกระทำในตาของทีม (เฟสเดิน ยิง บุก)
const ACTION_CODES: PackedStringArray = ["smove", "stay", "skip", "adv", "atk", "shoot", "chg", "gren", "heal", "done"]
const MOVE_ONLY: PackedStringArray = ["smove", "stay", "adv"]
const HUMAN_PHASES: PackedInt32Array = [BattleState.PH_MOVE, BattleState.PH_SHOOT, BattleState.PH_CHARGE]
## บรรทัดล็อกที่เก็บไว้ในตัวนี้ (ล่าสุด) และบรรทัดคำขอที่ถูกปฏิเสธที่ส่งต่อให้ Log ต่อเกม (ไม่ให้คำขอรัว ๆ ไล่หลักฐานจริงออก)
const LOG_KEEP := 200
const REFUSE_LOG_MAX := 20

var send: Callable
var is_host := false
var my_slot := -1
var gen := 0
## เจ้าของที่นั่ง: ช่องของสมาชิก หรือ -1 (บอท)
var owners: Array = []
## ที่นั่งที่เจ้าห้องเล่นแทน (หลุด ออกจากเกม หรือไม่ตรงกันครั้งสุดท้าย): ที่นั่ง → "gone" | "left" | "desync"
var gone: Dictionary = {}
## เพื่อน: seq ล่าสุดที่ใช้แล้ว · ตรวจ digest ผ่านกี่ครั้ง · สถานะความตรงกัน
var checks := 0
var sync: StringName = &"ok"
var desync_n := 0
## บรรทัดล็อกของตัวนี้ (เทสอ่าน) ส่งต่อให้ Log ด้วยถ้ามี
var log_lines := PackedStringArray()
## รหัสของคำขอที่ปฏิเสธล่าสุด (เจ้าห้อง)
var last_no := ""

var _queue: Array[Dictionary] = []
var _buf: Dictionary = {}           # เพื่อน: seq → body ที่มาก่อนลำดับ
var _pending_ints := false
var _repaired_seq := -1             # เพื่อน: seq ที่ซ่อมด้วย RESYNC ได้ล่าสุด (-1 = ยังไม่เคย)
var _refused_n := 0                 # เจ้าห้อง: คำขอที่ปฏิเสธในเกมนี้


func _init(p_send: Callable, p_is_host: bool, p_my_slot: int, p_gen: int, p_owners: Array) -> void:
	send = p_send
	is_host = p_is_host
	my_slot = p_my_slot
	gen = p_gen
	owners = p_owners.duplicate()


## ที่นั่งของสมาชิกช่อง slot (-1 = ไม่มีที่นั่ง)
func seat_of(slot: int) -> int:
	if slot < 0:
		return -1
	return owners.find(slot)


func owner_of(k: int) -> int:
	return int(owners[k]) if k >= 0 and k < owners.size() else -1


# ------------------------------------------------------------------------------------------------ ประตูคำขอ

## รายการแรกที่ยังต้องทอย (แบบออฟไลน์: ไม่สนว่าใครทอย) หรือ null
static func first_live(st: BattleState) -> BattleState.Pend:
	return BtRoller.next(st, {"online": false})


## รหัส act ที่ตอบรายการรอทอยนี้ได้
static func _roll_codes_of(st: BattleState, p: BattleState.Pend) -> PackedStringArray:
	match p.kind:
		BattleState.K_ATK:
			if p.stage == BattleState.S_HIT:
				return PackedStringArray(["atk"])
			if p.stage == BattleState.S_WOUND:
				return PackedStringArray(["wnd", "rr"])
			if p.stage == BattleState.S_SAVE:
				return PackedStringArray(["sav"])
		BattleState.K_SHOCK:
			return PackedStringArray(["shock"])
		BattleState.K_REZ:
			return PackedStringArray(["rez"])
		BattleState.K_CHG:
			if p.stage == BattleState.S_OW:
				return PackedStringArray(["ow"])
			if p.stage == BattleState.S_MOVE:
				return PackedStringArray(["cmove"])
			return PackedStringArray(["chr"])
	return PackedStringArray()


## ประตูของเจ้าห้อง (§4.5): "" = ผ่าน หรือ not_now / not_yours · act ต้องถือ pid ของที่นั่งแล้ว (ผู้เรียกเขียนทับ)
static func gate(st: BattleState, seat: int, act: Dictionary) -> String:
	var q := st.seat(seat)
	if q == null or st.over or not st.on:
		return "not_yours" if q == null else "not_now"
	var code := str(act.get("a", ""))
	var p := first_live(st)
	var is_roll := ROLL_CODES.has(code) or (code == "atk" and p != null and p.kind == BattleState.K_ATK
		and p.stage == BattleState.S_HIT and str(act.get("u", "")) == p.u and str(act.get("t", "")) == p.t)
	if is_roll:
		if p == null or BtPend.roller_of(p) != seat:
			return "not_now"
		if not _roll_codes_of(st, p).has(code) or str(act.get("u", "")) != p.u:
			return "not_now"
		if act.has("t") and str(act["t"]) != p.t:
			return "not_now"
		return ""
	if not ACTION_CODES.has(code):
		return "not_yours"
	if act.has("u"):
		var s := st.squad(str(act["u"]))
		if s == null or s.pl != seat:
			return "not_yours"
	if p != null:
		return "not_now"
	if q.team != st.turn or not HUMAN_PHASES.has(st.phase) or q.done:
		return "not_now"
	if MOVE_ONLY.has(code) and st.phase != BattleState.PH_MOVE:
		return "not_now"
	if code == "chg" and st.phase != BattleState.PH_CHARGE:
		return "not_now"
	if code == "done" and str(act.get("ph", "")) != st.phase_name():
		return "not_now"
	return ""


# ------------------------------------------------------------------------------------------------ เจ้าห้อง

## act ที่เพิ่งบันทึกบนเครื่องเจ้าห้อง (รูปมาตรฐานจาก actlog) เข้าคิว · ทุก 8 seq และ act ที่จบเกมแนบ digest
func host_logged(act: Dictionary, b: Battle) -> void:
	var seq := int(act.get("seq", 0))
	var body := {"gen": gen, "seq": seq, "act": act}
	if seq % DIGEST_EVERY == 0 or b.st.over:
		body["dg"] = b.digest()
	_queue.append(body)


## จบหนึ่งช่วง (หลัง step หรือคำขอ): act สุดท้ายในคิวได้ digest ของสถานะตอนนี้ แล้วส่งทั้งคิวให้ทุกคน
func end_burst(b: Battle) -> void:
	if _queue.is_empty():
		return
	var last: Dictionary = _queue[_queue.size() - 1]
	if int(last["seq"]) == b.actlog.last_seq():
		last["dg"] = b.digest()
	var q := _queue
	_queue = []
	for body: Dictionary in q:
		send.call(NetProto.ACT, body, -1)


## คิวที่ยังไม่ได้ส่ง (เทส)
func queued() -> int:
	return _queue.size()


## ACT_REQ จากช่อง from_slot: "" = รับแล้ว (บันทึกผ่าน NetRec.apply ซึ่งเข้าคิวเอง) ไม่งั้นรหัสที่ตอบ ACT_NO ไปแล้ว
## ("gen" = ข้อความของเกมเก่า ทิ้งเงียบ)
func host_request(from_slot: int, body: Dictionary, b: Battle) -> String:
	if int(body.get("gen", -1)) != gen:
		return "gen"
	var base := int(body.get("base", -1))
	var seat := seat_of(from_slot)
	var key := ""
	var act: Dictionary = (body.get("act", {}) as Dictionary).duplicate(true) if body.get("act") is Dictionary else {}
	if seat < 0 or seat >= b.st.seats.size():
		key = "not_yours"
	elif gone.has(seat):
		key = "gone_seat"
	elif base != b.actlog.last_seq():
		key = "stale"
	else:
		var spid := b.st.seats[seat].pid
		# pid ในคำขอไม่ตรงกับที่นั่งของผู้ส่ง = ปลอม (เพื่อนส่ง pid ของตัวเองเสมอ)
		if act.has("pid") and str(act["pid"]) != spid:
			key = "not_yours"
		else:
			act.erase("seq")
			act["pid"] = spid
			key = gate(b.st, seat, act)
			if key == "":
				var n0 := b.actlog.size()
				b.apply(act)
				if b.last_error != "" or b.actlog.size() == n0:
					key = "refused"
	if key != "":
		last_no = key
		if key != "stale":
			_refused_n += 1
			if _refused_n <= REFUSE_LOG_MAX:
				_log("warn", "net battle: slot %d request %s refused (%s) at seq %d" % [from_slot, str(act.get("a", "")), key, b.actlog.last_seq()])
			elif _refused_n == REFUSE_LOG_MAX + 1:
				_log("warn", "net battle: more refused requests in this game are not logged")
		send.call(NetProto.ACT_NO, {"gen": gen, "base": clampi(base, 0, 100000), "key": key}, from_slot)
	return key


## RESEND: ACT ตั้งแต่ from ถึงล่าสุด ส่งให้ช่องเดียว (act สุดท้ายมี dg)
func host_resend(from_slot: int, from_seq: int, b: Battle) -> void:
	var last := b.actlog.last_seq()
	for s: int in range(maxi(1, from_seq), last + 1):
		var body := {"gen": gen, "seq": s, "act": b.actlog.at(s)}
		if s == last:
			body["dg"] = b.digest()
		send.call(NetProto.ACT, body, from_slot)


## RESYNC: บันทึกทั้งเกมของเครื่องเจ้าห้อง
func resync_body(plan: Dictionary, b: Battle) -> Dictionary:
	return {"gen": gen, "plan": plan_wire(plan), "owners": owners.duplicate(), "acts": b.actlog.acts(),
		"seq": b.actlog.last_seq(), "dg": b.digest()}


## แผนที่ส่งบนสาย: setup + seats เท่านั้น (human ของแต่ละเครื่องตั้งเอง)
static func plan_wire(plan: Dictionary) -> Dictionary:
	var seats: Array = []
	for sd: Variant in plan.get("seats", []):
		if sd is Dictionary:
			var d := {}
			for k: String in ["team", "bot", "pid", "nm", "fac", "list"]:
				if (sd as Dictionary).has(k):
					d[k] = (sd as Dictionary)[k]
			seats.append(d)
	return {"setup": (plan.get("setup", {}) as Dictionary).duplicate(true), "seats": seats}


## สร้างโต๊ะใหม่จาก RESYNC: Battle.make → start → replay (into = โต๊ะที่จะใส่ เช่น NetRec ของตัวคุมเกม)
static func rebuild(body: Dictionary, into: Battle = null) -> Battle:
	var plan: Dictionary = body.get("plan", {})
	var seats: Array[Dictionary] = []
	for sd: Variant in plan.get("seats", []):
		if sd is Dictionary:
			seats.append((sd as Dictionary).duplicate(true))
	var base := Battle.make(plan.get("setup", {}), seats, {})
	var b: Battle = into if into != null else base
	if into != null:
		into.st = base.st
		into.seed = base.seed
	b.start()
	b.replay(body.get("acts", []))
	return b


# ------------------------------------------------------------------------------------------------ เพื่อน

## ACT จากเจ้าห้อง: ใช้ตามลำดับ (ซ้ำทิ้ง ขาดเก็บไว้แล้วขอ RESEND) เทียบ dg · คืนเหตุการณ์ (มี DESYNC เมื่อไม่ตรง)
func client_act(body: Dictionary, b: Battle) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if int(body.get("gen", -1)) != gen or sync != &"ok":
		return out
	var seq := int(body.get("seq", 0))
	var last := b.actlog.last_seq()
	if seq <= last:
		return out
	if seq > last + 1:
		if _buf.is_empty():
			_log("warn", "net battle: gap at seq %d (have %d), asking again" % [seq, last])
			send.call(NetProto.RESEND, {"gen": gen, "from": last + 1}, -1)
		_buf[seq] = body
		return out
	out.append_array(_apply_one(body, b))
	while sync == &"ok" and _buf.has(b.actlog.last_seq() + 1):
		var nb: Dictionary = _buf[b.actlog.last_seq() + 1]
		_buf.erase(b.actlog.last_seq() + 1)
		out.append_array(_apply_one(nb, b))
	if sync != &"ok":
		_buf.clear()
	return out


func _apply_one(body: Dictionary, b: Battle) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var act: Dictionary = body.get("act", {})
	var seq := int(body["seq"])
	var n0 := b.actlog.size()
	b.apply(act)
	if b.last_error != "" or b.actlog.size() != n0 + 1:
		out.append(_desync(seq, b.digest(), str(body.get("dg", "")), "refused " + b.last_error))
		return out
	if body.has("dg"):
		out.append_array(check(seq, str(body["dg"]), b))
	return out


## เทียบ digest ของเจ้าห้องที่ seq นี้ (ACT หรือ HB) · คืน [DESYNC] เมื่อไม่ตรง
func check(seq: int, dg: String, b: Battle) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if sync != &"ok" or seq != b.actlog.last_seq() or dg == "":
		return out
	var mine := b.digest()
	if mine == dg:
		checks += 1
	else:
		out.append(_desync(seq, mine, dg, "digest"))
	return out


## ไม่ตรงกับเจ้าห้อง: เหตุการณ์ DESYNC ล็อก error แจ้งเจ้าห้อง ครั้งแรกขอเกมใหม่ ครั้งที่สองขอเลขสถานะไว้ดีบัก
## ครั้งที่สอง = ไม่ตรงอีกทันทีหลังซ่อม (ภายใน 2 ช่วง digest) · ซ่อมได้แล้วเล่นไปนานกว่านั้น นับเป็นครั้งแรกใหม่
func _desync(seq: int, mine: String, host_dg: String, why: String) -> Dictionary:
	if desync_n > 0 and _repaired_seq >= 0 and seq > _repaired_seq + 2 * DIGEST_EVERY:
		desync_n = 0
	desync_n += 1
	var n := mini(desync_n, 2)
	_log("error", "desync gen=%d seq=%d local=%s host=%s (%s, %d)" % [gen, seq, mine, host_dg, why, n])
	var dg := mine if NetProto.is_hex(mine, 16) else "0000000000000000"
	send.call(NetProto.DESYNC, {"gen": gen, "seq": clampi(seq, 0, 100000), "dg": dg, "n": n}, -1)
	if n == 1:
		sync = &"desync"
		send.call(NetProto.RESYNC_REQ, {"gen": gen, "why": "desync"}, -1)
	else:
		sync = &"desync_final"
		_pending_ints = true
		send.call(NetProto.INTS_REQ, {"gen": gen}, -1)
	return Events.make(Events.Id.DESYNC, {"seq": seq, "local_digest": mine, "remote_digest": host_dg})


## หลังสร้างโต๊ะใหม่จาก RESYNC: digest ตรง → กลับมาเล่น ไม่ตรง → ไม่ตรงครั้งที่สอง (ถาวร)
func after_resync(body: Dictionary, b: Battle) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	_buf.clear()
	var mine := b.digest()
	var dg := str(body.get("dg", ""))
	if mine == dg and b.actlog.last_seq() == int(body.get("seq", -1)):
		sync = &"ok"
		checks += 1
		_repaired_seq = b.actlog.last_seq()
		_log("info", "net battle: resync gen=%d seq=%d matches the host" % [gen, b.actlog.last_seq()])
	else:
		desync_n = maxi(desync_n, 1)
		_repaired_seq = -1   # เกมจากเจ้าห้องเองยังไม่ตรง: ครั้งที่สองเสมอ
		out.append(_desync(b.actlog.last_seq(), mine, dg, "resync"))
	return out


## INTS ของเจ้าห้อง (หลังไม่ตรงครั้งที่สอง): ล็อกตำแหน่งแรกใน state_ints() ที่ต่างกันพร้อมค่าทั้งสอง · คืนตำแหน่ง (-1 = ไม่ต่าง)
func client_ints(body: Dictionary, b: Battle) -> int:
	if int(body.get("gen", -1)) != gen:
		return -1
	_pending_ints = false
	var host_v: PackedInt64Array = PackedInt64Array(body.get("ints", PackedInt64Array()))
	var mine := b.state_ints()
	var n := maxi(host_v.size(), mine.size())
	for i: int in n:
		var a := host_v[i] if i < host_v.size() else -1
		var c := mine[i] if i < mine.size() else -1
		if a != c or i >= host_v.size() or i >= mine.size():
			_log("error", "desync ints gen=%d host seq=%d mine seq=%d first index %d: host %d mine %d" % [gen, int(body.get("seq", 0)),
				b.actlog.last_seq(), i, a, c])
			return i
	_log("error", "desync ints gen=%d: no difference in %d values" % [gen, n])
	return -1


func waiting_ints() -> bool:
	return _pending_ints


func _log(level: String, msg: String) -> void:
	log_lines.append("%s %s" % [level, msg])
	if log_lines.size() > LOG_KEEP:
		log_lines = log_lines.slice(log_lines.size() - LOG_KEEP)
	var loop := Engine.get_main_loop()
	var lg: Node = (loop as SceneTree).root.get_node_or_null(^"Log") if loop is SceneTree else null
	if lg != null and lg.has_method(level):
		lg.call(level, msg)
