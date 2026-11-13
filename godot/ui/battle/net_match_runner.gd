class_name NetMatchRunner
extends MatchRunner
## ตัวคุมเกมออนไลน์ (NET_SPEC §4.3–§4.4) ไม่แก้ core/ และ match_runner.gd: สลับ b เป็น NetRec ก่อน start()
## เจ้าห้อง: ทุก act ที่บันทึก → Lockstep (ACT พร้อม dg) · ทอยเฉพาะที่ควรทอย (บอท ที่นั่งตัวเอง ที่นั่งที่หลุด เพื่อนที่เงียบนาน
## ทีละรายการ) · บอทรอเมื่อลูกเต๋าของเพื่อนค้าง · เล่นแทนที่นั่งที่หลุดด้วย pid ของที่นั่งนั้น · รอเพื่อน = wait_remote
## เพื่อน: ไม่เรียก bot_step / finished_act / flush · การกระทำของตัวเองส่งเป็น ACT_REQ ใช้เมื่อเจ้าห้องส่ง ACT กลับมาเท่านั้น
## เวลาเครื่อง (รอทอย 15 วินาที) อยู่ที่นี่ ไม่เข้าแกน · ลูกเต๋าของคนจริงจากสตรีม dice:<ที่นั่ง> ที่ seed จากเครื่องนี้

signal changed()
## เจ้าห้อง: ก้าวนี้รอเพื่อน (ตัวเชื่อมตั้ง Timer ปลุกตอนครบ 15 วินาทีของลูกเต๋าที่รอ)
signal waiting()

## คำขอที่เจ้าห้องตอบด้วยงานหนัก ต่อสมาชิกต่อเกม: เกินแล้วไม่ตอบ (ล็อกครั้งเดียว) · RESYNC_REQ เกิน = เล่นแทนที่นั่งนั้น
const ASK_MAX := {NetProto.RESYNC_REQ: 4, NetProto.INTS_REQ: 2, NetProto.RESEND: 16, NetProto.DESYNC: 8}
## RESEND ที่ย้อนไกลกว่านี้ตอบด้วย RESYNC ครั้งเดียว (แทน ACT ทีละอันเป็นร้อย)
const RESEND_MAX := 64


## Battle ของตัวคุมเกมออนไลน์: apply ส่ง act ที่บันทึกให้ Lockstep · flush ของเจ้าห้องใช้บริบทออนไลน์ ของเพื่อนไม่ทำอะไร
class NetRec extends MatchRunner.Rec:
	var host_mode := false
	## ตัวคุมเกมเจ้าของ (อ้างอ่อน: ไม่เป็นวงอ้างอิงกัน)
	var runner_ref: WeakRef
	## ตัวนับ (เทส): bot_step ที่ถูกเรียก
	var bot_steps := 0

	func apply(act: Dictionary) -> Array[Dictionary]:
		var n0 := actlog.size()
		var out := super(act)
		var r: Object = runner_ref.get_ref() if host_mode and runner_ref != null else null
		if last_error == "" and actlog.size() > n0 and r != null:
			r.call("_on_logged", actlog.at(actlog.last_seq()))
		return out

	## ไม่สนอาร์กิวเมนต์: เจ้าห้องทอยของที่ทอยได้ตาม net_here() (บอท ที่นั่งตัวเอง) แล้วดูรายการแรกที่ค้าง
	## ของที่นั่งเพื่อนที่หลุด หรือรอเกิน 15 วินาที: ทอยแทนเฉพาะรายการนั้น (bot:<ที่นั่ง> pid ของที่นั่ง) แล้ววนใหม่
	## (ไม่ทอยแทนรายการถัดไปของเพื่อนคนอื่นที่ยังอยู่) · เพื่อนคืน 0
	func flush(_force: bool, _here: Dictionary) -> int:
		var r: Object = runner_ref.get_ref() if host_mode and runner_ref != null else null
		if r == null:
			return 0
		var n := 0
		for guard: int in 400:
			n += super(false, r.call("net_here"))
			if last_error != "":
				break
			var p := Lockstep.first_live(st)
			if not bool(r.call("_host_rolls_for", p)):
				break
			var k := BtPend.roller_of(p)
			var acts := BtRoller.roll(st, p, BtBot.choice(st, p), st.rng("bot:%d" % k))
			if acts.is_empty():
				break
			var q := st.seat(k)
			var spid := q.pid if q != null else ""
			for a: Dictionary in acts:
				a["pid"] = spid
				apply(a)
				if last_error != "":
					return n
				n += 1
		return n

	func bot_step() -> String:
		bot_steps += 1
		return super()


var lockstep: Lockstep
var net_host := false
## ลูกเต๋าของเครื่องนี้ (0 = สุ่มจากเครื่องตอนเริ่ม)
var dice_seed := 0
## เพื่อน: ส่งคำขอแล้วยังไม่ได้คำตอบ
var in_flight := false
## เวลาปลอมของเทส (-1 = เวลาเครื่อง)
var fake_now := -1
## เหตุที่เจ้าห้องจบเกม (END) "" = ยังไม่จบแบบนั้น
var ended_why := ""
## เรื่องที่หน้าจอควรขึ้นป้าย: [{key, k|slot}] (ที่นั่งหลุด/กลับ/ออก คำขอช้าไป เครื่องเพื่อนไม่ตรง)
var notices: Array[Dictionary] = []
## ชื่อสมาชิกตามช่อง (ข้อความบนจอ) ตัวเชื่อมตั้งให้
var names: Dictionary = {}

var _req_base := -1
var _playing := -1
var _home := -1
var _first_key := ""
var _first_at := 0
var _resyncs := 0
var _asked: Dictionary = {}        # เจ้าห้อง: ช่อง:ชนิด → จำนวนคำของานหนักในเกมนี้
## สถานะ Net ล่าสุดที่ตัวเชื่อมบอก (เพื่อน: reconnecting = ขึ้นป้ายกำลังต่อใหม่)
var link_state: StringName = &"joined"


func _init(p: Dictionary) -> void:
	super(p)
	var nb := NetRec.new()
	nb.st = b.st
	nb.seed = b.seed
	b = nb


## ตัวคุมเกมของเจ้าห้อง: plan.human = ที่นั่งของเจ้าห้อง (-1 = ไม่นั่ง)
static func host(p: Dictionary, link: Lockstep, p_dice_seed: int = 0) -> NetMatchRunner:
	var r := NetMatchRunner.new(p)
	r.setup_net(true, link, p_dice_seed)
	return r


## ตัวคุมเกมของเพื่อน: my_seat = ที่นั่งของเครื่องนี้ (-1 = ดูอยู่)
static func client(p: Dictionary, my_seat: int, link: Lockstep, p_dice_seed: int = 0) -> NetMatchRunner:
	var q := p.duplicate()
	q["human"] = my_seat
	var r := NetMatchRunner.new(q)
	r.setup_net(false, link, p_dice_seed)
	return r


## ผูกกับ Lockstep (เรียกครั้งเดียวก่อน start)
func setup_net(is_host_mode: bool, link: Lockstep, p_dice_seed: int) -> void:
	net_host = is_host_mode
	lockstep = link
	dice_seed = p_dice_seed
	var nb := b as NetRec
	nb.host_mode = is_host_mode
	nb.runner_ref = weakref(self)


func start() -> Array[Dictionary]:
	var was := started
	var out := super()
	if not was and human >= 0:
		# ลูกเต๋าของคนจริงมาจากเครื่องนี้ (สถานะเครื่อง ไม่อยู่ใน digest)
		var sv := dice_seed if dice_seed != 0 else (randi() | 1)
		st.rngs["dice:%d" % human] = Rng.make("dice:%d" % human, sv)
	return out


func online() -> bool:
	return true


func is_net_host() -> bool:
	return net_host


func checks() -> int:
	return lockstep.checks if lockstep != null else 0


func sync_state() -> StringName:
	return lockstep.sync if lockstep != null else &"ok"


func gone_seats() -> PackedInt32Array:
	var out := PackedInt32Array()
	if lockstep != null:
		for k: int in lockstep.gone:
			out.append(k)
	out.sort()
	return out


func take_notices() -> Array[Dictionary]:
	var out := notices.duplicate()
	notices.clear()
	return out


func _now() -> int:
	return fake_now if fake_now >= 0 else Time.get_ticks_msec()


# ------------------------------------------------------------------------------------------------ เจ้าห้อง

func _on_logged(act: Dictionary) -> void:
	if lockstep != null:
		lockstep.host_logged(act, b)


## บริบทของ BtRoller บนเครื่องเจ้าห้อง: เจ้าของห้อง pid ของที่นั่งตัวเอง · since_ok false เสมอ (ทอยแทนเพื่อนทีละรายการใน
## NetRec.flush ผ่าน _host_rolls_for ไม่ให้ทั้งรอบ flush ทอยแทนทุกคนเพราะรายการแรกเลยเวลา)
func net_here() -> Dictionary:
	return {"online": true, "owner": true, "pid": _host_pid(), "since_ok": false}


## เจ้าห้องทอยแทนรายการแรกที่ค้างนี้ไหม: ของที่นั่งเพื่อน (ไม่ใช่บอท ไม่ใช่ของเจ้าห้อง) ที่หลุด หรือรอเกิน 15 วินาที
## เรียกทุกครั้งที่ flush (นับเวลาของรายการแรก ไม่มีรายการ = ล้าง)
func _host_rolls_for(p: BattleState.Pend) -> bool:
	var ok := _since_ok()
	if p == null or not ok or lockstep == null:
		return false
	var k := BtPend.roller_of(p)
	var q := st.seat(k)
	return q != null and not q.bot and not q.ai and lockstep.owner_of(k) > 0


func _host_pid() -> String:
	var h := _home if _playing >= 0 else human   # ระหว่างเล่นแทนที่นั่งอื่น human ถูกสลับชั่วคราว
	return st.seats[h].pid if h >= 0 and h < st.seats.size() else ""


func _since_ok() -> bool:
	var p := Lockstep.first_live(st)
	if p == null:
		_first_key = ""
		return false
	var k := BtPend.roller_of(p)
	# รายการเดิมขั้นเดิม: นับเวลาต่อ · เปลี่ยนรายการหรือขั้น: เริ่มนับใหม่
	var key := "%d|%d|%s|%s|%d" % [p.kind, p.stage, p.u, p.t, k]
	if key != _first_key:
		_first_key = key
		_first_at = _now()
	if lockstep != null and lockstep.gone.has(k):
		return true
	return _now() - _first_at >= Lockstep.ROLL_WAIT_MS


## ที่นั่งของคนจริงฝั่งเพื่อน (ไม่ใช่บอท ไม่ใช่เจ้าห้อง ไม่หลุด)
func _remote_live(k: int) -> bool:
	var q := st.seat(k)
	if q == null or q.bot or q.ai or k == human or lockstep == null:
		return false
	return lockstep.owner_of(k) > 0 and not lockstep.gone.has(k)


## ที่นั่งที่หลุดของทีมที่ถึงตา ในเฟสที่ต้องกด และยังไม่ได้กดจบ (-1 = ไม่มี)
func _gone_turn_seat() -> int:
	if lockstep == null or not HUMAN_PHASES.has(st.phase) or not st.pend.is_empty():
		return -1
	for q: BattleState.Seat in st.team_seats(st.turn):
		if lockstep.gone.has(q.id) and not q.bot and not q.done and q.id != human:
			return q.id
	return -1


## เล่นแทนที่นั่ง k หนึ่งก้าว (นโยบายของ auto_step ด้วยที่นั่งและ pid ของ k ลูกเต๋า bot:<k>)
func play_seat(k: int) -> String:
	var h := human
	var hp := pid
	var aut := auto_human
	_home = h
	human = k
	pid = st.seats[k].pid
	_playing = k
	var alive := _human_alive()
	var why := auto_step() if alive else end_phase()
	_playing = -1
	human = h
	pid = hp
	auto_human = aut
	return why


func _dice() -> Rng:
	if _playing >= 0:
		return st.rng("bot:%d" % _playing)
	return super()


## เกมรอเพื่อนคนไหนอยู่ (ทอยหรือกด) ในเครื่องเจ้าห้อง
func _remote_must_act() -> bool:
	var p := Lockstep.first_live(st)
	if p != null:
		return _remote_live(BtPend.roller_of(p))
	if not HUMAN_PHASES.has(st.phase):
		return false
	for q: BattleState.Seat in st.team_seats(st.turn):
		if _remote_live(q.id) and not q.done:
			return true
	return false


func step() -> Dictionary:
	if not started:
		start()
	if net_host:
		var r := _host_step()
		lockstep.end_burst(b)
		if str(r["state"]) == "wait_remote":
			waiting.emit()
		return r
	return _client_step()


func _host_step() -> Dictionary:
	if st.over:
		return _res("over", 0)
	var n0 := b.actlog.size()
	if not st.pend.is_empty():
		b.flush(false, HERE)
		if b.actlog.size() != n0:
			return _res("over" if st.over else "acted", 0)
	# ลูกเต๋าของเพื่อนยังค้าง: บอทรอก่อน (แบบหน้าเก่า และแบบออฟไลน์ที่ทอยหมดก่อนบอทขยับ)
	if Lockstep.first_live(st) == null and (b.bot_step() != "" or b.actlog.size() != n0):
		return _res("over" if st.over else "acted", 0)
	if st.over:
		return _res("over", 0)
	var g := _gone_turn_seat()
	if g >= 0:
		play_seat(g)
		if b.actlog.size() != n0:
			return _res("over" if st.over else "acted", 0)
	# ลูกเต๋าที่ค้างเป็นของเพื่อน (เจ้าห้องทอยไม่ได้): ไม่สั่งอะไรต่อ ไปดูว่ารอใคร
	if Lockstep.first_live(st) == null and is_human_turn():
		if not _human_alive():
			end_phase()   # ไม่มีหมู่เหลือให้สั่ง: กดจบเฟสแทน
		elif auto_human:
			auto_step()
		else:
			return _res("wait_human", 0)
		if b.actlog.size() != n0:
			return _res("over" if st.over else "acted", 0)
	var e := BtBot.finished_act(st)
	if not e.is_empty():
		e["pid"] = ""
		b.apply(e)
		return _res("over" if st.over else "acted", 0)
	b.flush(false, HERE)
	if b.actlog.size() != n0:
		return _res("over" if st.over else "acted", 0)
	if st.over:
		return _res("over", 0)
	if _remote_must_act():
		return _res("wait_remote", 0)
	return _res("stuck", 0)


## มิลลิวินาทีจนถึงเวลาที่เจ้าห้องจะทอยแทนเพื่อนที่เงียบ (0 = ไม่มีอะไรรอ, 1 = เลยเวลาแล้ว)
func next_wake_ms() -> int:
	if not net_host or st.over:
		return 0
	var p := Lockstep.first_live(st)
	if p == null or not _remote_live(BtPend.roller_of(p)):
		return 0
	_since_ok()   # รายการที่รอเปลี่ยนตั้งแต่ flush ล่าสุด: เริ่มนับตอนนี้
	return maxi(1, _first_at + Lockstep.ROLL_WAIT_MS - _now())


## ลูกเต๋าของเพื่อนที่รออยู่เลย 15 วินาทีแล้ว (ก้าวถัดไปของเจ้าห้องทอยแทน)
func roll_overdue() -> bool:
	return next_wake_ms() > 0 and _now() - _first_at >= Lockstep.ROLL_WAIT_MS


## รายการที่กำลังนับเวลา (ตัวเชื่อมใช้ไม่ปลุกซ้ำทุกเฟรมเมื่อเลยเวลาแล้วแต่หน้ารบไม่ปั๊ม)
func wake_key() -> String:
	return _first_key


## ที่นั่งที่หลุด: เจ้าห้องเล่นแทนด้วย pid ของที่นั่ง (ไม่เปลี่ยน bot) · why = gone | left | desync
## ที่นั่งที่หลุดชั่วคราว (gone) แล้วออกเองหรือไม่ตรงถาวร: เปลี่ยนเป็นแบบไม่คืน
func seat_gone(k: int, why: String = "gone") -> void:
	if lockstep == null or k < 0 or k >= st.seats.size():
		return
	if lockstep.gone.has(k) and (why == "gone" or str(lockstep.gone[k]) != "gone"):
		return
	lockstep.gone[k] = why
	if net_host:
		lockstep.send.call(NetProto.SEAT, {"gen": lockstep.gen, "k": k, "on": "left" if why == "left" else "gone"}, -1)
	notices.append({"key": "left" if why == "left" else "gone", "k": k})
	changed.emit()


## ที่นั่งกลับมา: RESYNC ให้เจ้าของ แล้ว SEAT back · ที่นั่งที่ออกเองหรือไม่ตรงถาวรไม่คืนจนจบเกม
func seat_back(k: int) -> void:
	if lockstep == null or not lockstep.gone.has(k) or str(lockstep.gone[k]) != "gone":
		return
	lockstep.end_burst(b)
	var slot := lockstep.owner_of(k)
	lockstep.gone.erase(k)
	if net_host and slot > 0:
		lockstep.send.call(NetProto.RESYNC, lockstep.resync_body(plan, b), slot)
		lockstep.send.call(NetProto.SEAT, {"gen": lockstep.gen, "k": k, "on": "back"}, -1)
	notices.append({"key": "back", "k": k})
	changed.emit()


## HB ของการรบ: เจ้าห้อง {seq, dg, gen} · เพื่อน {seq, gen} (gen: HB ของเกมเก่าไม่ถูกเทียบกับเกมใหม่)
func hb_body() -> Dictionary:
	var g := lockstep.gen if lockstep != null else 0
	if net_host:
		return {"seq": b.actlog.last_seq(), "dg": b.digest(), "gen": g}
	return {"seq": b.actlog.last_seq(), "gen": g}


# ------------------------------------------------------------------------------------------------ เพื่อน

func _client_step() -> Dictionary:
	if st.over:
		return _res("over", 0)
	if in_flight or sync_state() != &"ok" or ended_why != "":
		return _res("wait_remote", 0)
	if human < 0 or lockstep.gone.has(human):
		return _res("wait_remote", 0)   # ดูอยู่ หรือเจ้าห้องเล่นแทนที่นั่งนี้อยู่: ไม่ส่งคำขอ
	var p := Lockstep.first_live(st)
	if p != null:
		var here := {"online": true, "owner": false, "pid": pid}
		if BtRoller.rolls_here(st, BtPend.roller_of(p), here):
			var acts := BtRoller.roll(st, p, BtBot.choice(st, p), st.rng("dice:%d" % human))
			if not acts.is_empty():
				_human_act(acts[0])
		return _res("wait_remote", 0)
	if is_human_turn():
		# คำสั่งของเครื่องนี้ไปเป็นคำขอ: บันทึกไม่โตจนกว่าเจ้าห้องตอบ จึงรอเสมอ
		if not _human_alive():
			end_phase()
		elif auto_human:
			auto_step()
		else:
			return _res("wait_human", 0)
	return _res("wait_remote", 0)


func _human_act(a: Dictionary) -> String:
	if net_host:
		return super(a)
	if in_flight:
		return "busy"
	if lockstep == null or human < 0 or lockstep.gone.has(human):
		return "not_now"
	a["pid"] = pid
	a.erase("seq")
	_req_base = b.actlog.last_seq()
	var sent: Variant = lockstep.send.call(NetProto.ACT_REQ, {"gen": lockstep.gen, "base": _req_base, "act": a}, -1)
	if sent is bool and not sent:
		return "not_now"   # กำลังต่อใหม่: ไม่ได้ส่ง จึงไม่ค้างรอคำตอบ
	in_flight = true
	return ""


## เพื่อน: ตาของเครื่องนี้ (ที่นั่งที่เจ้าห้องเล่นแทนอยู่ไม่นับ) · เจ้าห้องเหมือนเดิม (เล่นแทนที่นั่งอื่นด้วย human ชั่วคราว)
func is_human_turn() -> bool:
	if not net_host and lockstep != null and lockstep.gone.has(human):
		return false
	return super()


func can_select(s: BattleState.Squad) -> bool:
	if in_flight or sync_state() != &"ok" or (not net_host and lockstep != null and lockstep.gone.has(human)):
		return false
	return super(s)


## เพื่อน: เจ้าห้องเล่นแทนที่นั่งของเครื่องนี้อยู่ (หลุด/ออก/ไม่ตรง)
func my_seat_gone() -> bool:
	return not net_host and human >= 0 and lockstep != null and lockstep.gone.has(human)


## ข้อความของการรบที่ตัวเชื่อมส่งมา (ตรวจรูปแบบแล้วโดย NetProto)
func receive(kind: int, body: Dictionary, from_slot: int) -> void:
	if lockstep == null:
		return
	var g := int(body.get("gen", lockstep.gen))
	if g != lockstep.gen:
		return
	if net_host:
		_host_receive(kind, body, from_slot)
	else:
		_client_receive(kind, body)


## คำของานหนักของช่องนี้ยังอยู่ในโควตาของเกมนี้ไหม (เกินครั้งแรกล็อกหนึ่งบรรทัด)
func _ask_ok(from_slot: int, kind: int) -> bool:
	var key := "%d:%d" % [from_slot, kind]
	var n := int(_asked.get(key, 0)) + 1
	_asked[key] = n
	var cap := int(ASK_MAX.get(kind, 1000000))
	if n == cap + 1:
		lockstep._log("warn", "net battle: slot %d asked for %s too often in this game; ignoring it" % [from_slot, NetProto.kind_name(kind)])
	return n <= cap


func _host_receive(kind: int, body: Dictionary, from_slot: int) -> void:
	if ASK_MAX.has(kind) and not _ask_ok(from_slot, kind):
		if kind == NetProto.RESYNC_REQ and int(_asked["%d:%d" % [from_slot, kind]]) == int(ASK_MAX[kind]) + 1:
			seat_gone(lockstep.seat_of(from_slot), "desync")   # ซ่อมไม่จบ: เจ้าห้องเล่นแทนจนจบเกม (ดัง ไม่เงียบ)
		return
	match kind:
		NetProto.ACT_REQ:
			var key := lockstep.host_request(from_slot, body, b)
			lockstep.end_burst(b)
			if key == "" or key == "refused":
				changed.emit()
		NetProto.RESEND:
			lockstep.end_burst(b)
			var from := int(body.get("from", 1))
			if b.actlog.last_seq() - from + 1 > RESEND_MAX:
				if _ask_ok(from_slot, NetProto.RESYNC_REQ):
					lockstep.send.call(NetProto.RESYNC, lockstep.resync_body(plan, b), from_slot)
			else:
				lockstep.host_resend(from_slot, from, b)
		NetProto.RESYNC_REQ:
			lockstep.end_burst(b)
			lockstep.send.call(NetProto.RESYNC, lockstep.resync_body(plan, b), from_slot)
		NetProto.LEAVE:
			# เพื่อนออกจากหน้ารบเองในเกมนี้ (gen ตรงแล้ว): เล่นแทนจนจบเกม
			if not st.over:
				seat_gone(lockstep.seat_of(from_slot), "left")
		NetProto.DESYNC:
			var n := int(body.get("n", 1))
			lockstep._log("error", "desync reported by %s (slot %d) gen=%d seq=%d theirs=%s mine=%s n=%d" % [
				str(names.get(from_slot, "")), from_slot, lockstep.gen, int(body.get("seq", 0)), str(body.get("dg", "")),
				b.digest() if int(body.get("seq", 0)) == b.actlog.last_seq() else "-", n])
			notices.append({"key": "desync", "slot": from_slot})
			if n >= 2:
				seat_gone(lockstep.seat_of(from_slot), "desync")
			changed.emit()
		NetProto.INTS_REQ:
			lockstep.send.call(NetProto.INTS, {"gen": lockstep.gen, "seq": b.actlog.last_seq(), "ints": b.state_ints()}, from_slot)


func _client_receive(kind: int, body: Dictionary) -> void:
	match kind:
		NetProto.ACT:
			var evs := lockstep.client_act(body, b)
			b.note(evs)
			if in_flight and int(body.get("seq", 0)) > _req_base:
				var a: Dictionary = body.get("act", {})
				if str(a.get("pid", "")) == pid and pid != "":
					in_flight = false
			changed.emit()
		NetProto.ACT_NO:
			# คำตอบของคำขอล่าสุดเท่านั้น (คำตอบเก่าที่มาช้าไม่ล้างคำขอใหม่)
			if in_flight and int(body.get("base", -1)) == _req_base:
				in_flight = false
			var key := str(body.get("key", ""))
			if key == "stale":
				notices.append({"key": "stale"})
			elif key == "gone_seat":
				if human >= 0 and not lockstep.gone.has(human):
					lockstep.gone[human] = "gone"
					notices.append({"key": "mine"})
			else:
				lockstep._log("warn", "net battle: my request was refused (%s)" % key)
			changed.emit()
		NetProto.RESYNC:
			_rebuild(body)
			changed.emit()
		NetProto.SEAT:
			var k := int(body.get("k", -1))
			var on := str(body.get("on", ""))
			if on == "back":
				lockstep.gone.erase(k)
			else:
				lockstep.gone[k] = on
			notices.append({"key": "mine" if k == human and on != "back" else on, "k": k})
			changed.emit()
		NetProto.END:
			ended_why = str(body.get("why", "host_left_battle"))
			changed.emit()
		NetProto.INTS:
			lockstep.client_ints(body, b)
			changed.emit()
		NetProto.HB:
			if body.has("dg") and int(body.get("seq", -1)) == b.actlog.last_seq():
				b.note(lockstep.check(int(body["seq"]), str(body["dg"]), b))
				if sync_state() != &"ok":
					changed.emit()


## สร้างโต๊ะใหม่จาก RESYNC (เกมที่ไม่ตรง หรือเข้ากลับมาใหม่) เก็บสตรีมลูกเต๋าของเครื่องนี้ไว้
func _rebuild(body: Dictionary) -> void:
	var dice: Variant = st.rngs.get("dice:%d" % human) if human >= 0 else null
	if body.has("owners"):
		lockstep.owners = (body["owners"] as Array).duplicate()
	var plan_wire: Dictionary = body.get("plan", {})
	var keep := b.evs.duplicate()
	var nb := NetRec.new()
	Lockstep.rebuild(body, nb)
	# เหตุการณ์ของการเล่นซ้ำไม่ขึ้นจอ ที่ยังไม่มีใครอ่าน (เช่น DESYNC) เก็บไว้
	nb.evs = keep
	nb.runner_ref = weakref(self)
	b = nb
	st = nb.st
	started = true
	in_flight = false
	_resyncs += 1
	if human >= 0 and human < st.seats.size():
		pid = st.seats[human].pid
		if dice != null:
			st.rngs["dice:%d" % human] = dice
		else:
			# เข้ากลับมาใหม่ (ตัวคุมเกมใหม่): seed จากเครื่องนี้ ไม่ใช่จาก seed ของโต๊ะที่ทุกคนรู้
			st.rngs["dice:%d" % human] = Rng.make("dice:%d" % human, dice_seed if dice_seed != 0 else (randi() | 1))
	if not plan_wire.is_empty():
		var p2 := plan.duplicate()
		p2["setup"] = plan_wire.get("setup", {})
		p2["seats"] = plan_wire.get("seats", [])
		plan = p2
	b.note(lockstep.after_resync(body, b))


func resyncs() -> int:
	return _resyncs


## ชื่อที่เกมรออยู่ (ทอยหรือกด) "" = เจ้าห้องหรือบอท (หน้าจอแสดงว่า เจ้าห้อง)
func waiting_for() -> PackedStringArray:
	var out := PackedStringArray()
	if st.over or lockstep == null:
		return out
	var p := Lockstep.first_live(st)
	if p != null:
		var k := BtPend.roller_of(p)
		if k != human:
			out.append(_seat_name(k))
		return out
	if not HUMAN_PHASES.has(st.phase):
		out.append("")
		return out
	for q: BattleState.Seat in st.team_seats(st.turn):
		if q.id == human:
			continue
		if q.bot or lockstep.gone.has(q.id) or lockstep.owner_of(q.id) == 0:
			if not out.has(_seat_name(q.id)) and (not q.done or q.bot):
				out.append(_seat_name(q.id))
		elif not q.done and not out.has(q.nm):
			out.append(q.nm)
	return out


func _seat_name(k: int) -> String:
	var q := st.seat(k)
	if q == null or q.bot or lockstep == null or lockstep.gone.has(k) or lockstep.owner_of(k) <= 0:
		return ""
	return q.nm
