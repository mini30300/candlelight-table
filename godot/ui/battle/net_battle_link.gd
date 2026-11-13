class_name NetBattleLink
extends Node
## ตัวเชื่อมการรบออนไลน์ (NET_SPEC §5.2): Net สร้างเป็นลูกตอน _ready (load ตามที่อยู่) · ฟัง Net.message ของการรบ
## เพื่อน: START → ตัวคุมเกมของเพื่อน + หน้ารบซ้อนบนหน้าปัจจุบัน · ส่ง ACT ACT_NO RESYNC SEAT END INTS HB ให้ตัวคุมเกม
## เจ้าห้อง: start_host (START + ตัวคุมเกมของเจ้าห้อง) · ส่ง ACT_REQ RESEND RESYNC_REQ DESYNC INTS_REQ LEAVE ให้ตัวคุมเกม
## · สมาชิกหลุด/กลับ → seat_gone / seat_back · ออกจากหน้ารบเอง = LEAVE ของเกมนั้น (ไม่เดาจาก where)
## · Timer นัดเดียวของ next_wake_ms (ตั้งเมื่อก้าวของเจ้าห้องรอเพื่อน) ไม่มีงานต่อเฟรม
## เพื่อน: ต่อใหม่อยู่ → ตัวคุมเกมรู้ (ป้าย) · ต่อใหม่ได้ → ล้างคำขอที่ค้าง · หลุดถาวร → จบเกมบนเครื่องนี้ (บอกเหตุตามจริง)

const BATTLE_SCREEN := "res://ui/screens/battle_screen.tscn"
const HOST_KINDS: PackedInt32Array = [NetProto.ACT_REQ, NetProto.RESEND, NetProto.RESYNC_REQ, NetProto.DESYNC, NetProto.INTS_REQ,
	NetProto.LEAVE]
const CLIENT_KINDS: PackedInt32Array = [NetProto.ACT, NetProto.ACT_NO, NetProto.RESYNC, NetProto.SEAT, NetProto.END,
	NetProto.INTS, NetProto.HB]

## เลขเกมในห้องนี้ (+1 ต่อ START)
var gen := 0
## เทส: ไม่เปิดหน้ารบเอง
var open_screens := true

var _runner: NetMatchRunner = null
var _wake: Timer
var _net: Node = null
var _woke_key := ""                 # รายการที่ปลุกไปแล้วตอนเลยเวลา (ไม่ปลุกซ้ำทุกเฟรมถ้าหน้ารบของเจ้าห้องไม่ปั๊ม)


func _ready() -> void:
	_wake = Timer.new()
	_wake.one_shot = true
	_wake.timeout.connect(_on_wake)
	add_child(_wake)
	_net = get_parent()
	if _net != null and _net.has_signal(&"message"):
		_net.connect(&"message", _on_message)
	if _net != null and _net.has_signal(&"members_changed"):
		_net.connect(&"members_changed", _on_members)
	if _net != null and _net.has_signal(&"lost"):
		_net.connect(&"lost", _on_lost)
	if _net != null and _net.has_signal(&"state_changed"):
		_net.connect(&"state_changed", _on_net_state)
	if _net != null and _net.has_signal(&"reconnected"):
		_net.connect(&"reconnected", _on_reconnected)


func current_runner() -> NetMatchRunner:
	return _runner


## ตัวคุมเกมหยุดแล้ว (ออกจากหน้ารบ)
func clear_runner() -> void:
	_runner = null
	_wake.stop()


## false = ไม่ได้ส่ง (ไม่ได้ออนไลน์ หรือกำลังต่อใหม่)
func _send(kind: int, body: Dictionary, to_slot: int) -> bool:
	if _net != null and _net.has_method("send"):
		return bool(_net.call("send", kind, body, to_slot))
	return false


func _my_slot() -> int:
	return int(_net.call("my_slot")) if _net != null and _net.has_method("my_slot") else 0


func _names() -> Dictionary:
	var out := {}
	if _net != null and _net.has_method("members"):
		for m: Dictionary in _net.call("members"):
			out[int(m["slot"])] = str(m.get("nm", ""))
	return out


## HB ของการรบ (Net เรียกทุก 2 วินาที): ไม่มีเกม = {}
func hb_body() -> Dictionary:
	return {} if _runner == null else _runner.hb_body()


## เจ้าห้องเริ่มเกม: plan จาก NetSeats.build → START ถึงทุกคน → ตัวคุมเกมของเจ้าห้อง (ผู้เรียกเปิดหน้ารบ)
func start_host(plan: Dictionary, dice_seed: int = 0) -> NetMatchRunner:
	gen = (gen + 1) % 65536
	var owners: Array = plan.get("owners", [])
	_send(NetProto.START, {"gen": gen, "plan": Lockstep.plan_wire(plan), "owners": owners}, -1)
	var link := Lockstep.new(_send, true, 0, gen, owners)
	attach(NetMatchRunner.host(plan, link, dice_seed))
	# เพื่อนที่นั่งอยู่แต่หลุดอยู่ตอนเริ่ม (ช่องยังเก็บไว้): เจ้าห้องเล่นแทนตั้งแต่ต้น กลับมาเมื่อไรได้ที่นั่งคืน
	var here := _here_now()
	for k: int in owners.size():
		var s := int(owners[k])
		if s > 0 and not bool(here.get(s, false)):
			_runner.seat_gone(k, "gone")
	return _runner


## ใช้ตัวคุมเกมนี้: ป้ายชื่อ สัญญาณเปลี่ยน/รอ (ตั้ง Timer ปลุก)
func attach(r: NetMatchRunner) -> void:
	_runner = r
	_woke_key = ""
	_runner.names = _names()
	_runner.changed.connect(_after_change)
	_runner.waiting.connect(_arm_wake)
	if _net != null and _net.has_method("state"):
		_runner.link_state = StringName(str(_net.call("state")))


## เจ้าห้องออกจากการรบ: END ถึงทุกคน
func host_left() -> void:
	if _runner != null and _runner.is_net_host() and not _runner.is_over():
		_send(NetProto.END, {"gen": gen, "why": "host_left_battle"}, -1)
	clear_runner()


## เพื่อนออกจากหน้ารบเอง: LEAVE ของเกมนี้ (เจ้าห้องเล่นแทนจนจบเกม; gen เก่าที่มาช้าไม่โดนเกมใหม่) แล้วเลิกตัวคุมเกม
func client_left() -> void:
	if _runner != null and not _runner.is_net_host() and not _runner.is_over() and _runner.human >= 0:
		_send(NetProto.LEAVE, {"gen": gen}, -1)
	clear_runner()


func _on_message(from_slot: int, kind: int, body: Dictionary) -> void:
	var is_host := _net != null and _net.has_method("is_host") and bool(_net.call("is_host"))
	if kind == NetProto.START and not is_host:
		_client_start(body)
		return
	if _runner == null:
		if kind == NetProto.RESYNC and not is_host:
			_client_start(body, true)
		return
	if is_host and HOST_KINDS.has(kind):
		_runner.receive(kind, body, from_slot)
	elif not is_host and CLIENT_KINDS.has(kind):
		if kind == NetProto.RESYNC and int(body.get("gen", -1)) != gen:
			_client_start(body, true)
			return
		_runner.receive(kind, body, from_slot)


## START (หรือ RESYNC ของเกมที่เข้ากลับมา) บนเครื่องเพื่อน: ตัวคุมเกม + หน้ารบซ้อนบนหน้าปัจจุบัน (ผู้ชมได้หน้าดูอย่างเดียว)
func _client_start(body: Dictionary, from_resync: bool = false) -> void:
	gen = int(body.get("gen", 0))
	var owners: Array = body.get("owners", [])
	var slot := _my_slot()
	var plan := (body.get("plan", {}) as Dictionary).duplicate(true)
	var seat := owners.find(slot)
	var link := Lockstep.new(_send, false, slot, gen, owners)
	attach(NetMatchRunner.client(plan, seat, link))
	if from_resync:
		_runner.receive(NetProto.RESYNC, body, 0)
	if open_screens:
		_open_screen(plan)
	# หน้ารบเปิดไม่ได้ (หรือเทสไม่เปิด): เริ่มนัดเองให้ ACT ที่ตามมาไม่ตกบนโต๊ะที่ยังไม่เริ่ม
	if not _runner.started:
		_runner.start()


func _open_screen(plan: Dictionary) -> void:
	var app := get_node_or_null(^"/root/App")
	if app == null or not ResourceLoader.exists(BATTLE_SCREEN):
		return
	var top: Node = app.call("current") if app.has_method("current") else null
	var scr: Node = null
	if top != null and top.has_method("begin") and str(top.scene_file_path) == BATTLE_SCREEN:
		scr = top
	else:
		scr = app.call("push", load(BATTLE_SCREEN))
	if scr != null and scr.has_method("begin"):
		scr.call("begin", plan, _runner)


func _after_change() -> void:
	_arm_wake()


## Timer นัดเดียวถึงเวลาที่เจ้าห้องทอยแทนเพื่อนที่เงียบ · เลยเวลาแล้วและปลุกไปแล้ว: ไม่ตั้งซ้ำ (ก้าวถัดไปของหน้ารบทอยเอง)
func _arm_wake() -> void:
	if _runner == null:
		return
	var ms := _runner.next_wake_ms()
	if ms <= 0:
		_wake.stop()
		return
	if _runner.roll_overdue() and _runner.wake_key() == _woke_key:
		return
	_wake.start(ms / 1000.0)


func _on_wake() -> void:
	if _runner != null:
		if _runner.roll_overdue():
			_woke_key = _runner.wake_key()
		_runner.changed.emit()


## สถานะ Timer ปลุก (เทส): วินาทีที่เหลือ หรือ -1 = ไม่ได้ตั้ง
func wake_left() -> float:
	return -1.0 if _wake.is_stopped() else _wake.time_left


func _here_now() -> Dictionary:
	var out := {}
	if _net != null and _net.has_method("members"):
		for m: Dictionary in _net.call("members"):
			out[int(m["slot"])] = bool(m.get("here", true))
	return out


## เจ้าห้อง: สมาชิกหลุด (here = false หรือหายไป) → ที่นั่งหลุด · กลับมา → คืนที่นั่ง (RESYNC)
## ระหว่างรบ Net เก็บช่องที่มีที่นั่งไว้ให้เจ้าของเดิมเท่านั้น (คนใหม่ได้ช่องอื่น) จึงคืนที่นั่งตามช่องได้
## ออกจากหน้ารบเองมาเป็น LEAVE (ไม่ดูจาก where: WHERE กับ START สวนกันได้)
func _on_members() -> void:
	if _runner == null or not _runner.is_net_host() or _runner.is_over():
		return
	var now := _here_now()
	_runner.names = _names()
	var lk := _runner.lockstep
	for k: int in lk.owners.size():
		var s := int(lk.owners[k])
		if s <= 0:
			continue
		if not bool(now.get(s, false)):
			_runner.seat_gone(k, "gone")
		elif str(lk.gone.get(k, "")) == "gone":
			# กลับมา (ต่อใหม่ หรือเปิดแอปใหม่ด้วย nid เดิม แม้ช่องเคยหมดเวลา): RESYNC แล้วคืนที่นั่ง
			_runner.seat_back(k)


## เพื่อน: หลุดถาวร · host_left = เจ้าห้องปิดห้อง · อื่น ๆ (ต่อใหม่ไม่สำเร็จ ข้อความเสีย) = การเชื่อมต่อของเครื่องนี้หลุด
func _on_lost(key: String) -> void:
	if _runner != null and not _runner.is_net_host():
		_runner.ended_why = "host_closed" if key == "host_left" else "lost"
		_runner.changed.emit()


func _on_net_state(s: StringName) -> void:
	if _runner != null:
		_runner.link_state = s
		if not _runner.is_net_host():
			_runner.changed.emit()


## เพื่อน: ต่อใหม่ได้ คำขอที่ส่งไปก่อนหลุดอาจหาย: ล้างแล้วให้หน้ารบปั๊มต่อ (เจ้าห้องส่ง RESYNC เองถ้าเคยนับว่าหลุด)
func _on_reconnected() -> void:
	if _runner != null and not _runner.is_net_host():
		_runner.in_flight = false
		_runner.changed.emit()
