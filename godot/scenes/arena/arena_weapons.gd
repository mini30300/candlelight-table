class_name ArenaWeapons
extends RefCounted
## สถานะอาวุธของผู้เล่นในอารีน่า (ARENA_SPEC §5.2, §6.3): ปืนไรเฟิล (ยิงรัว) ดาบเลื่อย (ฟันซ้ำตามคูลดาวน์) หมัด (ทุกอาวุธ)
## ตัวเลขทั้งหมดจาก ArenaData ผ่าน ArenaCombat ไม่มีตัวเลขต่อสู้ในไฟล์นี้ · ไม่มี Node ไม่มีฟิสิกส์: เทสด้วยเวลาปลอมได้
## เวลาเดินจาก delta ที่ส่งเข้า tick() เท่านั้น (ไม่อ่าน Time) · กด/ปล่อยคืนเหตุการณ์ที่เกิดทันที tick() คืนเหตุการณ์ตามเวลา
## เหตุการณ์ = {"type": StringName, "id": StringName}: shot (กระสุนออก), reload_start, reload_done, reload_cancel,
## melee_start (เริ่มต่อย/ฟัน), melee_hit (จังหวะโดน หลังกด active วิ), weapon (อาวุธในมือเปลี่ยน id = อันใหม่)
## เปลี่ยนอาวุธ: เก็บ holster วิ แล้วชัก draw วิ (ระหว่างนั้นยิงไม่ได้ การบรรจุที่ค้างอยู่ถูกยกเลิก)
## แมกหมดตอนยังกดยิงค้าง = บรรจุเองทันที (ปุ่มยิงบนมือถือไม่เงียบเหมือนปืนขัด) · แมกว่างแล้วกดยิงใหม่ = บรรจุเอง
## (เช่นหลังการบรรจุถูกยกเลิกด้วยการเปลี่ยนอาวุธ) · R บรรจุได้ทุกเมื่อที่แมกไม่เต็ม

const GUN := &"gun"
const SWORD := &"sword"
const PUNCH := &"punch"
const NONE := &"none"

var now := 0.0
var current: StringName = NONE
var in_mag := 0
var mag_size := 0
var trigger := false

var _reload_left := 0.0
var _switch_left := 0.0
var _switch_to: StringName = NONE
var _last := {}                 # id → เวลาที่ใช้ครั้งล่าสุด (ตามจังหวะ ไม่ใช่เฟรม: อัตรายิงไม่ตกตามเฟรม)
var _pending: Array[Dictionary] = []   # จังหวะโดนของหมัด/ดาบที่รออยู่ {"id", "at"}


func _init() -> void:
	mag_size = ArenaCombat.full_mag("gun")
	in_mag = mag_size


## ชักอาวุธจากมือเปล่า (เข้าโหมดยิง): ชัก draw วิ ระหว่างนั้นยังยิงไม่ได้
func draw(id: StringName) -> Array[Dictionary]:
	var ev: Array[Dictionary] = []
	_cancel_reload(ev)
	current = id
	_switch_to = id
	_switch_left = _draw_time()
	_pending.clear()
	ev.append({"type": &"weapon", "id": id})
	return ev


## เก็บอาวุธทันที (กลับโหมดเดิน ล้ม): ยกเลิกทุกอย่างที่ค้าง
func holster() -> Array[Dictionary]:
	var ev: Array[Dictionary] = []
	_cancel_reload(ev)
	trigger = false
	_pending.clear()
	_switch_left = 0.0
	_switch_to = NONE
	if current != NONE:
		current = NONE
		ev.append({"type": &"weapon", "id": NONE})
	return ev


## กด/ปล่อยไกปืน (ปุ่มยิง): แมกหมดตอนกด = เริ่มบรรจุ
func set_trigger(on: bool) -> Array[Dictionary]:
	var ev: Array[Dictionary] = []
	var was := trigger
	trigger = on and current != NONE
	if trigger and not was and current == GUN and in_mag <= 0:
		ev.append_array(reload())
	return ev


## บรรจุกระสุน (R หรือแมกหมดแล้วกดยิง)
func reload() -> Array[Dictionary]:
	var ev: Array[Dictionary] = []
	if current != GUN or reloading() or switching() or in_mag >= mag_size:
		return ev
	_reload_left = float(ArenaCombat.weapon("gun")["reload"])
	ev.append({"type": &"reload_start", "id": GUN})
	return ev


## ต่อย (ใช้ได้ทุกอาวุธในโหมดยิง ตามคูลดาวน์ของหมัด)
func melee() -> Array[Dictionary]:
	var ev: Array[Dictionary] = []
	if current == NONE or switching() or not _pending.is_empty():
		return ev
	if not ArenaCombat.can_fire(now, float(_last.get(PUNCH, -INF)), "punch"):
		return ev
	_start_melee(PUNCH, ev)
	return ev


## เปลี่ยนเป็นอาวุธ id (gun / sword): เก็บแล้วชัก ยกเลิกการบรรจุ
func switch_to(id: StringName) -> Array[Dictionary]:
	var ev: Array[Dictionary] = []
	if current == NONE or id == NONE:
		return ev
	if (switching() and _switch_to == id) or (not switching() and current == id):
		return ev
	_cancel_reload(ev)
	_pending.clear()
	_switch_to = id
	_switch_left = _holster_time() + _draw_time()
	return ev


## สลับไปอีกอาวุธ (ล้อเมาส์ ปุ่มอาวุธบนจอ)
func cycle() -> Array[Dictionary]:
	return switch_to(other())


## อาวุธที่อยู่ในมือ (หรือกำลังชักขึ้นมา) · NONE ในโหมดเดิน
func held() -> StringName:
	return _switch_to if switching() else current


## อาวุธอีกอัน (ชื่อบนปุ่มอาวุธ)
func other() -> StringName:
	var cur := _switch_to if switching() else current
	return SWORD if cur == GUN else GUN


## เติมแมกเต็ม (รีเซ็ต ลุกขึ้น)
func refill() -> Array[Dictionary]:
	var ev: Array[Dictionary] = []
	_cancel_reload(ev)
	in_mag = mag_size
	return ev


func reloading() -> bool:
	return _reload_left > 0.0


func switching() -> bool:
	return _switch_left > 0.0


## 0..1 ของการบรรจุที่กำลังทำ (0 = ไม่ได้บรรจุ)
func reload_progress() -> float:
	if not reloading():
		return 0.0
	var t := float(ArenaCombat.weapon("gun")["reload"])
	return clampf(1.0 - _reload_left / t, 0.0, 1.0)


func reload_left() -> float:
	return maxf(_reload_left, 0.0)


func ammo() -> Vector2i:
	return Vector2i(in_mag, mag_size)


## ยังมีอะไรต้องนับเวลา (ไกค้าง บรรจุ เปลี่ยนอาวุธ จังหวะโดนที่รอ): ผู้เล่นเปิดงานต่อเฟรมเฉพาะตอนนี้
func busy() -> bool:
	return trigger or reloading() or switching() or not _pending.is_empty()


## เดินเวลา dt วินาที คืนเหตุการณ์ที่ถึงเวลา
func tick(dt: float) -> Array[Dictionary]:
	var ev: Array[Dictionary] = []
	now += dt
	if _switch_left > 0.0:
		var before := _switch_left
		_switch_left -= dt
		var draw_t := _draw_time()
		if before > draw_t and _switch_left <= draw_t and current != _switch_to:
			current = _switch_to
			ev.append({"type": &"weapon", "id": current})
		if _switch_left <= 0.0:
			_switch_left = 0.0
			if current != _switch_to:
				current = _switch_to
				ev.append({"type": &"weapon", "id": current})
	if _reload_left > 0.0:
		_reload_left -= dt
		if _reload_left <= 0.0:
			_reload_left = 0.0
			in_mag = mag_size
			ev.append({"type": &"reload_done", "id": GUN})
	var keep: Array[Dictionary] = []
	for p in _pending:
		if now >= float(p["at"]) - 0.0001:
			ev.append({"type": &"melee_hit", "id": p["id"]})
		else:
			keep.append(p)
	_pending = keep
	if trigger and not switching():
		if current == GUN and not reloading() and in_mag > 0:
			if ArenaCombat.can_fire(now + 0.0001, float(_last.get(GUN, -INF)), "gun"):
				_mark(GUN)
				in_mag = ArenaCombat.after_shot(in_mag)
				ev.append({"type": &"shot", "id": GUN})
				if ArenaCombat.needs_reload(in_mag):
					ev.append_array(reload())
		elif current == GUN and not reloading() and ArenaCombat.needs_reload(in_mag):
			ev.append_array(reload())
		elif current == SWORD and _pending.is_empty():
			if ArenaCombat.can_fire(now + 0.0001, float(_last.get(SWORD, -INF)), "sword"):
				_start_melee(SWORD, ev)
	return ev


## เป้าที่ฟัน/ต่อยโดน: targets = [{"node", "id", "pos": Vector2, "r": float}] ผ่าน ArenaCombat.melee_hits (กรวยหน้า)
static func melee_targets_hit(id: String, origin: Vector2, face_yaw: float, targets: Array) -> Array:
	var out := []
	for t in targets:
		if ArenaCombat.melee_hits(id, origin, face_yaw, t["pos"], float(t["r"])):
			out.append(t)
	return out


# ---- ภายใน ----

func _start_melee(id: StringName, ev: Array[Dictionary]) -> void:
	_last[id] = now
	_pending.append({"id": id, "at": now + float(ArenaCombat.weapon(String(id))["active"])})
	ev.append({"type": &"melee_start", "id": id})


## จังหวะยิงต่อเนื่อง: ยิงติดกันนับจากจังหวะก่อน (ไม่ใช่เฟรม) ให้ได้ 8 นัด/วิ แม้เฟรมไม่ลงตัว
func _mark(id: StringName) -> void:
	var iv := ArenaCombat.fire_interval(String(id))
	var l := float(_last.get(id, -INF))
	_last[id] = l + iv if now - l < iv * 2.0 else now


func _cancel_reload(ev: Array[Dictionary]) -> void:
	if _reload_left > 0.0:
		_reload_left = 0.0
		ev.append({"type": &"reload_cancel", "id": GUN})


func _draw_time() -> float:
	return float(ArenaData.PLAYER["draw"])


func _holster_time() -> float:
	return float(ArenaData.PLAYER["holster"])
