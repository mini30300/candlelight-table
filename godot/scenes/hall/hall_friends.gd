class_name HallFriends
extends Node3D
## เพื่อนบนดาดฟ้า (NET_SPEC §6): ไข่ของเพื่อนทุกคนใน MultiMesh เดียว (Eggs, +1 draw call) สีตามช่องของเพื่อน
## วงแหวนใช้ MultiMesh Rings เดิมของห้อง (+0) · ชื่อเหนือหัววาดโดย FriendTags (2 มิติ) จาก heads()
## ท่าทางของเพื่อนมาจาก push_pose (ซม. / มิลลิเรเดียน ตาม NET_SPEC §2.2) ประทับเวลาที่มาถึงเครื่องนี้
## วาดช้ากว่าตัวอย่างล่าสุด 100 มิลลิวิ: เส้นตรงระหว่างตัวอย่าง หันทางสั้น · เลยตัวอย่างล่าสุดเดาต่อไม่เกิน 150 มิลลิวิ แล้วค้าง
## ห่างเกิน 3 ม. ย้ายทันที (เกิดใหม่ กลับจากอารีน่า) · ไม่มีตัวชน (เดินทะลุกันได้ ไม่มีงานฟิสิกส์)
## งานต่อเฟรม: _process เปิดเฉพาะตอนมีเพื่อนกำลังขยับ/รอตัวอย่าง แล้วปิดตัวเอง (แบบ HallAvatar) · ออฟไลน์ซ่อนทั้งโหนด
## ไฟล์นี้ไม่มีข้อความไทย (ชื่อเพื่อนเป็นชื่อที่ผู้เล่นตั้งเอง ไม่แปล)

## มีเพื่อนขยับในเฟรมนี้ (FriendTags วาดชื่อใหม่)
signal moved()

const MAX := 5
const DELAY_MS := 100        # วาดช้ากว่าตัวอย่างล่าสุด
const EXTRAP_MS := 150       # เดาต่อเลยตัวอย่างล่าสุดได้ไม่เกินนี้
const SNAP_M := 3.0          # ห่างเกินนี้ย้ายทันที
const KEEP := 3              # ตัวอย่างที่เก็บต่อคน
const SLOT_GAP := 0.9        # ระยะห่างจุดเกิดของแต่ละช่อง (ม.)
const EGG_H := 1.75
const HEAD_UP := 0.35        # ป้ายชื่ออยู่เหนือยอดไข่
const RING_R := 0.68         # = HallWorld.AVATAR_RING_R
const BOB_H := 0.06
const LEAN := 0.12
const WALK := 3.0
const RUN := 6.0
const MOVING := 0.05         # เร็วกว่านี้ (ม./วิ) ถือว่ากำลังเดิน (โยกตัว)
## จำนวนเหลี่ยมของไข่และการโยกตามระดับกราฟิก (เท่ากับ HallWorld.LEVELS)
const SIDES := {"hi": 14, "mid": 12, "lo": 10, "min": 8}
const BOBS := {"hi": true, "mid": true, "lo": false, "min": false}

var level := "mid"
var _world: Node3D
var _rings: Rings
var _eggs: MultiMeshInstance3D
var _friends: Dictionary = {}        # slot → {nm, colour, samples, pos, yaw, sp, ring, phase, done}
var _early: Dictionary = {}          # slot → ตัวอย่างที่มาก่อน set_friend
var _sides := 0
var _bob := true
var _last_ms := -1


func _ready() -> void:
	visible = not _friends.is_empty()
	set_process(false)


## ผูกกับห้อง (เรียกครั้งเดียวจาก HallWorld._ready): world = ห้อง, rings = MultiMesh วงแหวนของห้อง
func setup(world: Node3D, rings: Rings) -> void:
	_world = world
	_rings = rings
	visible = not _friends.is_empty()


## ระดับกราฟิก: จำนวนเหลี่ยมไข่ (14 / 12 / 10 / 8) และโยกตัวเฉพาะ hi/mid
func apply_level(l: String) -> void:
	if not SIDES.has(l):
		l = "mid"
	level = l
	_bob = bool(BOBS[l])
	var sides := int(SIDES[l])
	if sides != _sides:
		_sides = sides
		if _eggs != null:
			_eggs.multimesh.mesh = HallBuilder.avatar_mesh(Color.WHITE, _sides)
	_layout()


## เพิ่ม/แก้เพื่อนช่อง slot (ชื่อ สี): คนใหม่ยืนที่ท่าที่มาก่อนหน้า (ถ้ามี) ไม่งั้นที่จุดเกิดของช่อง
func set_friend(slot: int, nm: String, colour: Color) -> void:
	if _friends.has(slot):
		var f: Dictionary = _friends[slot]
		f["nm"] = nm
		if f["colour"] != colour:
			f["colour"] = colour
			_rings.set_ring(int(f["ring"]), f["pos"], Vector3.UP, RING_R, colour)
			_layout()
		return
	if _friends.size() >= MAX:
		return
	var p := spawn_for(slot)
	var yaw := PI
	var samples: Array = []
	if _early.has(slot):
		var s: Dictionary = _early[slot]
		_early.erase(slot)
		p = Vector3(float(s["x"]), 0.0, float(s["z"]))
		yaw = float(s["yaw"])
		samples.append(s)
	var ring := _rings.add_ring(p, Vector3.UP, RING_R, colour) if _rings != null else -1
	_friends[slot] = {"nm": nm, "colour": colour, "samples": samples, "pos": p, "yaw": yaw, "sp": 0.0, "ring": ring,
		"phase": 0.0, "done": true}
	_ensure_eggs()
	_layout()
	moved.emit()


func remove_friend(slot: int) -> void:
	_early.erase(slot)
	if not _friends.has(slot):
		return
	var f: Dictionary = _friends[slot]
	if _rings != null:
		_rings.remove_ring(int(f["ring"]))
	_friends.erase(slot)
	_layout()
	moved.emit()


func clear() -> void:
	for slot in _friends.keys():
		remove_friend(slot)
	_early.clear()
	set_process(false)


## ท่าใหม่ของเพื่อน (POSE / POSE_STOP): {x, z: ซม., yaw: มิลลิเรเดียน, sp: ซม./วิ, run, t} ประทับเวลาที่มาถึง now_ms
func push_pose(slot: int, pose: Dictionary, now_ms: int) -> void:
	var s := {"x": float(int(pose.get("x", 0))) / 100.0, "z": float(int(pose.get("z", 0))) / 100.0,
		"yaw": float(int(pose.get("yaw", 0))) / 1000.0, "sp": float(int(pose.get("sp", 0))) / 100.0,
		"run": bool(pose.get("run", false)), "t": now_ms}
	if not _friends.has(slot):
		_early[slot] = s
		return
	var f: Dictionary = _friends[slot]
	var samples: Array = f["samples"]
	var p := Vector3(float(s["x"]), 0.0, float(s["z"]))
	if (f["pos"] as Vector3).distance_to(p) > SNAP_M:
		# ไกลเกิน: ย้ายทันที ทิ้งตัวอย่างเก่า
		samples.clear()
		f["pos"] = p
		f["yaw"] = float(s["yaw"])
	elif bool(f["done"]):
		# ยืนนิ่งอยู่: เริ่มเดินจากจุดที่ยืนตอนนี้ (ไม่กระโดดไปครึ่งทาง)
		var here := {"x": (f["pos"] as Vector3).x, "z": (f["pos"] as Vector3).z, "yaw": float(f["yaw"]), "sp": 0.0,
			"run": false, "t": now_ms - DELAY_MS}
		samples.clear()
		samples.append(here)
	samples.append(s)
	while samples.size() > KEEP:
		samples.pop_front()
	f["done"] = false
	_place(slot)
	_last_ms = now_ms
	set_process(true)


func friend_count() -> int:
	return _friends.size()


func has_friend(slot: int) -> bool:
	return _friends.has(slot)


func friend_pos(slot: int) -> Vector3:
	return (_friends[slot]["pos"] as Vector3) if _friends.has(slot) else Vector3.ZERO


func slots() -> PackedInt32Array:
	var out := PackedInt32Array(_friends.keys())
	out.sort()
	return out


## จุดเหนือหัวของเพื่อนทุกคน (ป้ายชื่อของ FriendTags)
func heads() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var xf := global_transform if is_inside_tree() else transform
	for slot in slots():
		var f: Dictionary = _friends[slot]
		out.append({"slot": slot, "nm": str(f["nm"]), "pos": xf * ((f["pos"] as Vector3) + Vector3(0.0, EGG_H + HEAD_UP, 0.0))})
	return out


func counts() -> Dictionary:
	var shown := 0
	if _eggs != null and _eggs.visible and visible:
		shown = _eggs.multimesh.visible_instance_count
	return {"friends": _friends.size(), "eggs_visible": shown, "processing": is_processing(),
		"capacity": _eggs.multimesh.instance_count if _eggs != null else 0}


## จุดเกิดของช่อง slot บนดาดฟ้า: แถวเดียวกันที่ z 5 ห่างกัน 0.9 ม. (x −2.25 … 2.25)
static func spawn_for(slot: int) -> Vector3:
	return HallLayout.SPAWN + Vector3((float(slot) - 2.5) * SLOT_GAP, 0.0, 0.0)


## ท่าที่วาดตอน now_ms จากตัวอย่าง [{x, z, yaw, sp, t}] (เรียงตามเวลาที่มาถึง; ฟังก์ชันบริสุทธิ์)
## คืน {x, z, yaw, sp, moving, done}: done = ไม่มีอะไรเปลี่ยนอีกจนกว่าจะมีตัวอย่างใหม่
static func interp(samples: Array, now_ms: int) -> Dictionary:
	if samples.is_empty():
		return {"x": 0.0, "z": 0.0, "yaw": 0.0, "sp": 0.0, "moving": false, "done": true}
	var rt := now_ms - DELAY_MS
	var last: Dictionary = samples[samples.size() - 1]
	var first: Dictionary = samples[0]
	if rt <= int(first["t"]):
		# ยังไม่ถึงตัวอย่างแรก: ยืนที่ตัวอย่างแรก (ตัวอย่างเดียวที่หยุดแล้ว = นิ่งเลย)
		var still := samples.size() == 1 and float(first["sp"]) <= 0.0
		return {"x": float(first["x"]), "z": float(first["z"]), "yaw": float(first["yaw"]), "sp": 0.0,
			"moving": false, "done": still}
	if rt >= int(last["t"]):
		var ahead := mini(rt - int(last["t"]), EXTRAP_MS)
		var sp := float(last["sp"])
		var yaw := float(last["yaw"])
		var d := sp * float(ahead) / 1000.0
		var done := sp <= 0.0 or rt - int(last["t"]) >= EXTRAP_MS
		return {"x": float(last["x"]) + sin(yaw) * d, "z": float(last["z"]) + cos(yaw) * d, "yaw": yaw,
			"sp": 0.0 if done else sp, "moving": not done and sp > MOVING, "done": done}
	for i in range(samples.size() - 1):
		var a: Dictionary = samples[i]
		var b: Dictionary = samples[i + 1]
		var ta := int(a["t"])
		var tb := int(b["t"])
		if rt >= ta and rt <= tb:
			var k := 0.0 if tb <= ta else float(rt - ta) / float(tb - ta)
			var sp := lerpf(float(a["sp"]), float(b["sp"]), k)
			return {"x": lerpf(float(a["x"]), float(b["x"]), k), "z": lerpf(float(a["z"]), float(b["z"]), k),
				"yaw": lerp_angle(float(a["yaw"]), float(b["yaw"]), k), "sp": sp, "moving": sp > MOVING, "done": false}
	return {"x": float(last["x"]), "z": float(last["z"]), "yaw": float(last["yaw"]), "sp": 0.0, "moving": false, "done": true}


## หนึ่งเฟรมของการเคลื่อนที่ (เทสเรียกเองด้วยเวลาปลอม): ย้ายเพื่อนที่ยังไม่นิ่ง แล้วปิดงานต่อเฟรมเมื่อทุกคนนิ่ง
func step(now_ms: int) -> void:
	var dt := 0.0 if _last_ms < 0 else clampf(float(now_ms - _last_ms) / 1000.0, 0.0, 0.25)
	_last_ms = now_ms
	var any := false
	var busy := false
	for slot in _friends:
		var f: Dictionary = _friends[slot]
		if bool(f["done"]):
			continue
		var r := interp(f["samples"], now_ms)
		var p := Vector3(float(r["x"]), 0.0, float(r["z"]))
		var changed := p.distance_squared_to(f["pos"]) > 0.000001 or absf(wrapf(float(r["yaw"]) - float(f["yaw"]), -PI, PI)) > 0.0005
		f["pos"] = p
		f["yaw"] = float(r["yaw"])
		f["sp"] = float(r["sp"]) if bool(r["moving"]) else 0.0
		f["phase"] = float(f["phase"]) + dt * float(f["sp"]) * 2.8
		f["done"] = bool(r["done"])
		if bool(r["done"]):
			f["sp"] = 0.0
			f["phase"] = 0.0
		if changed or bool(r["done"]):
			_place(slot)
			any = true
		if not bool(r["done"]):
			busy = true
	if any:
		moved.emit()
	if not busy:
		set_process(false)


func _process(_delta: float) -> void:
	step(Time.get_ticks_msec())


# ---- ภายใน ----

func _ensure_eggs() -> void:
	if _eggs != null:
		return
	_eggs = MultiMeshInstance3D.new()
	_eggs.name = "Eggs"
	_eggs.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_eggs.material_override = HallBuilder.material()
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	if _sides == 0:
		_sides = int(SIDES.get(level, 12))
	mm.mesh = HallBuilder.avatar_mesh(Color.WHITE, _sides)
	mm.instance_count = MAX
	mm.visible_instance_count = 0
	_eggs.multimesh = mm
	add_child(_eggs)


## จัดดัชนีไข่ใหม่ตามลำดับช่อง (มีไม่เกิน 5) แล้วโชว์เท่าจำนวนเพื่อน; ไม่มีเพื่อน = ซ่อนทั้งโหนด
func _layout() -> void:
	visible = not _friends.is_empty()
	if _eggs == null:
		return
	var i := 0
	for slot in slots():
		var f: Dictionary = _friends[slot]
		f["idx"] = i
		# ไข่สร้างเป็นสีขาว: สีช่องผสมขาว 40 % ให้ใกล้ไข่ของตัวเอง (สีทีม 60 % + งาช้าง)
		_eggs.multimesh.set_instance_color(i, (f["colour"] as Color).lerp(Color.WHITE, 0.4))
		_place(slot)
		i += 1
	_eggs.multimesh.visible_instance_count = i


func _place(slot: int) -> void:
	var f: Dictionary = _friends[slot]
	var p: Vector3 = f["pos"]
	if _rings != null:
		_rings.set_ring(int(f["ring"]), p, Vector3.UP, RING_R, f["colour"])
	if _eggs == null or not f.has("idx"):
		return
	var b := Basis(Vector3.UP, float(f["yaw"]))
	var off := Vector3.ZERO
	var sp := float(f["sp"])
	if _bob and sp > MOVING:
		off.y = absf(sin(float(f["phase"]))) * BOB_H * minf(sp / WALK, 1.0)
		b = b * Basis(Vector3.RIGHT, LEAN * minf(sp / RUN, 1.0))
	_eggs.multimesh.set_instance_transform(int(f["idx"]), Transform3D(b, p + off))
