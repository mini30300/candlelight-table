class_name EggGunner
extends Node3D
## ตัวผู้เล่นตั้งต้นของอารีน่า (ARENA_SPEC §6.6, สัญญาตัวละคร §9.1): ไข่สีทีมของดาดฟ้า + ถุงมือบรอนซ์ลอยสองข้าง
## (MultiMesh 2 ชิ้น = 1 draw call) ถือปืนไรเฟิลหรือดาบเลื่อยที่ออกแบบเอง (เมชเดียว = 1 draw call) ตราเทียนของเราเท่านั้น
## หน้าตัวอยู่ทาง +z (yaw 0) ขวามือของตัว = −x · ท่าทางสร้างด้วยโค้ด: idle walk run fire reload punch swing hit die
## play() คืนความยาวท่า · จังหวะเกมมาจาก ArenaData ไม่ใช่ความยาวท่า · แมกที่หล่นตอนบรรจุเป็นเมชแยก โชว์เฉพาะตอนบรรจุ
## เมธอดเสริม (§9.4): set_move_dir (H6 เอนตามทิศที่เดิน hi/mid) begin_switch (H7 ย่ออาวุธเก่า hi/mid)
## ฟันดาบสองจังหวะสลับกัน ใบผ่านหน้าตรงตอน 0.18 วิ · ถือดาบอยู่เห็นปืนสะพายหลัง (เมชแยก ไม่โชว์บน min)
## งานต่อเฟรม: _process เฉพาะตอนมีท่าครั้งเดียวกำลังเล่น ชักอาวุธ หรือโยกตัวตอนเดิน (hi/mid) แล้วปิดตัวเอง

signal clip_event(kind: StringName)

const FIGURE_API := ["setup", "metrics", "clip_names", "play", "set_move", "set_aim", "set_weapon", "set_flash",
	"set_telegraph", "muzzle", "anchor", "apply_level"]
const SIDES := {"hi": 14, "mid": 12, "lo": 10, "min": 8}
const HEIGHT := 1.75
const RADIUS := 0.35
const FIST_R := 0.11
const REST_R := Vector3(-0.42, 1.0, 0.18)
const REST_L := Vector3(0.42, 1.0, 0.18)
const GRIP_GUN := Vector3(-0.44, 1.24, 0.18)
const GRIP_SWORD := Vector3(-0.47, 1.0, 0.2)
const GUN_SUPPORT := Vector3(0.0, -0.035, 0.46)    # มือซ้ายประคองโครงลำกล้อง (พิกัดปืน)
const MAG_IN := Vector3(0.0, -0.1, 0.14)
const SWORD_TILT := -0.95                           # ดาบชี้ขึ้นหน้า
const PUNCH_OUT := 0.9
const LEAN := 0.15
const BOB_H := 0.05
const RECOIL := 0.06
## ท่าครั้งเดียว: ความยาว (วินาที)
const CLIPS := {"fire": 0.08, "reload": 1.6, "punch": 0.25, "swing": 0.45, "hit": 0.25, "die": 0.6}
const LOOPS := {"idle": 2.0, "walk": 0.8, "run": 0.55}
const BLADE := Color("8d949c")
const TEETH := Color("5d636b")
const GRIP_COL := Color("23262b")
## ท่าฟัน: [เวลา, ด้าม (พิกัดตัว), มุมดาบ (x = −เงย, y = หันไปซ้าย, z = หมุนให้สันฟันนำ), บิดไข่] ก่อน/หลังเป็นท่าตั้งดาบ
## A = ฟันเฉียงจากบนขวาลงล่างซ้าย · B = ฟันกวาดกลับจากซ้ายไปขวาระดับอก · ทั้งสองแบบใบดาบชี้ตรงหน้าตอน 0.18 วิ (จังหวะโดน)
const SWING_A := [[0.10, Vector3(-0.50, 1.32, 0.08), Vector3(-1.1, -2.3, -1.9), -0.25],
	[0.18, Vector3(-0.18, 1.05, 0.52), Vector3(0.15, 0.0, -1.9), 0.0],
	[0.26, Vector3(0.25, 0.85, 0.48), Vector3(0.6, 1.3, -1.9), 0.30]]
const SWING_B := [[0.10, Vector3(0.30, 1.12, 0.42), Vector3(-0.15, 2.2, 1.5), 0.25],
	[0.18, Vector3(-0.10, 1.15, 0.52), Vector3(-0.05, 0.0, 1.5), 0.0],
	[0.26, Vector3(-0.55, 1.18, 0.18), Vector3(-0.1, -2.0, 1.5), -0.30]]
const SWING_GAP := 1.2      # ฟันครั้งก่อนเกินนี้ (วินาที) เริ่มที่ A ใหม่
const CUT_BLEND := 0.08     # ท่าใหม่ตัดท่าต่อย/ฟันกลางคัน: ผสมจากท่าเดิมช่วงนี้ (วินาที) ไม่กระตุก
## ปืนสะพายหลังตอนถือดาบ (พิกัดไข่): ด้ามกลางหลัง ลำกล้องเฉียงขึ้นไปทางไหล่ซ้าย ข้างปืนแนบหลัง
const STOW_AT := Vector3(0.0, 1.07, -0.455)
const STOW_UP := Vector3(0.55, 0.83, 0.0)

static var _mesh_cache: Dictionary = {}

var role: StringName = &"player"
var level := "mid"
var team_colour := Color(0.28, 0.52, 0.84)
var bob := true

var egg: MeshInstance3D
var gauntlets: MultiMeshInstance3D
var weapon_root: Node3D
var weapon_mesh: MeshInstance3D
var mag: MeshInstance3D
var muzzle_node: Marker3D
var stowed: MeshInstance3D
## เทสตั้งเวลาเอง (วินาที) · ติดลบ = เวลาเกมจากเฟรมฟิสิกส์ (ใช้เลือกท่าฟัน A/B เท่านั้น ไม่เกี่ยวกับกติกา)
var clock := -1.0

var _weapon: StringName = &"none"
var _pitch := 0.0
var _speed := 0.0
var _running := false
var _phase := 0.0
var _clip := ""
var _clip_t := 0.0
var _clip_len := 0.0
var _clip_speed := 1.0
var _dead := false
var _draw_t := 1.0          # 0..1 ชักอาวุธ (ขยายจากเล็ก)
var _flash := 0.0
var _fade := 1.0
var _sides := 0
var _anchors: Dictionary = {}
var _flash_mat: StandardMaterial3D
var _fade_mat: StandardMaterial3D
var _dir := Vector2(0.0, 1.0)   # H6 ทิศที่เดินในกรอบตัว (x ขวา, y หน้า)
var _stow := -1.0               # H7 0..1 ย่ออาวุธเก่าลง (−1 = ไม่ได้ย่อ)
var _stow_len := 0.15
var _last_switch: StringName = &""
var _arc: StringName = &"a"
var _swing_at := -INF
var _sw_grip := Vector3.ZERO    # ผลของ _swing_pose (ไม่สร้าง Array ทุกเฟรม)
var _sw_rot := Vector3.ZERO
var _sw_twist := 0.0
var _cut := false               # ท่าครั้งเดียวนี้ตัดท่าต่อย/ฟันกลางคัน: ผสมจากท่าล่าสุดช่วง CUT_BLEND
var _last_grip := Vector3.ZERO  # ท่าล่าสุดที่วาด
var _last_rot := Vector3.ZERO
var _last_twist := 0.0
var _last_left := Vector3.ZERO
var _last_lean := 0.0
var _cut_grip := Vector3.ZERO   # ท่าตอนถูกตัด (จุดเริ่มผสม)
var _cut_rot := Vector3.ZERO
var _cut_twist := 0.0
var _cut_left := Vector3.ZERO
var _cut_lean := 0.0


func _ready() -> void:
	_build_nodes()
	set_process(false)


## สัญญาตัวละคร: {"role", "level", "team_colour", "seed"}
func setup(opts: Dictionary) -> void:
	role = StringName(str(opts.get("role", "player")))
	team_colour = opts.get("team_colour", team_colour)
	_build_nodes()
	_sides = 0
	apply_level(str(opts.get("level", level)))


func metrics() -> Dictionary:
	return {"height": HEIGHT, "radius": RADIUS, "eye": 1.45, "shoulder": 1.1}


func clip_names() -> Dictionary:
	var out := {}
	for k in LOOPS:
		out[k] = PackedStringArray([k])
	for k in CLIPS:
		out[k] = PackedStringArray([k])
	return out


## เริ่มท่า logical (ท่าครั้งเดียวจบแล้วกลับท่าวน) คืนความยาวท่า (วินาที, หารด้วย speed) ไม่มีท่าคืน 0
func play(logical: StringName, speed: float = 1.0) -> float:
	var k := String(logical)
	speed = maxf(speed, 0.01)
	if LOOPS.has(k):
		if k == "idle":
			_dead = false
			_clip = ""
			_pose()
		return float(LOOPS[k]) / speed
	if not CLIPS.has(k):
		return 0.0
	if _dead and k != "die":
		return 0.0
	# ต่อย/ฟันยังไม่จบแล้วมีท่าใหม่ (ต่างชนิดกันตัดกันได้หลังจังหวะโดน §9.4): ผสมจากท่าล่าสุด ไม่ดีดกลับ
	_cut = (_clip == "swing" or _clip == "punch") and _clip_t < _clip_len and k != "die"
	if _cut:
		_cut_grip = _last_grip
		_cut_rot = _last_rot
		_cut_twist = _last_twist
		_cut_left = _last_left
		_cut_lean = _last_lean
	_clip = k
	_clip_t = 0.0
	_clip_speed = speed
	_clip_len = float(CLIPS[k])
	if k == "fire":
		clip_event.emit(&"shot")
	elif k == "swing":
		var now := clock if clock >= 0.0 else float(Engine.get_physics_frames()) / float(maxi(Engine.physics_ticks_per_second, 1))
		_arc = &"a" if now - _swing_at > SWING_GAP or _arc == &"b" else &"b"
		_swing_at = now
	set_process(true)
	_pose()
	return _clip_len / speed


## ความเร็ว (ม./วิ) ตามทิศหน้า: เลือก idle/walk/run และจังหวะโยก (ทิศกลับเป็นเดินหน้า)
func set_move(speed: float, running: bool) -> void:
	_dir = Vector2(0.0, 1.0)
	_apply_move(speed, running)


## H6 (ARENA_SPEC §9.4): ทิศที่เดินจริงในกรอบตัว (ยาว 1 หรือศูนย์) · hi/mid เอนตามทิศ lo/min แค่จำไว้
func set_move_dir(local_dir: Vector2, speed: float, running: bool) -> void:
	_dir = local_dir
	_apply_move(speed, running)


func move_dir() -> Vector2:
	return _dir


func _apply_move(speed: float, running: bool) -> void:
	_speed = maxf(speed, 0.0)
	_running = running
	if bob and _speed > 0.05:
		set_process(true)
	elif _clip == "" and _draw_t >= 1.0:
		_phase = 0.0
		_pose()


## มุมเล็ง (เรเดียน, บวก = เงย): ปืนกับมือขวาก้มเงยตาม ไข่เอนตาม ±0.15
func set_aim(pitch: float) -> void:
	_pitch = pitch
	_pose()


## อาวุธในมือ: none / gun / sword (ชักใหม่ขยายจากเล็ก 0.2 วิบน hi/mid)
func set_weapon(id: StringName) -> void:
	if id == _weapon:
		return
	var was := _weapon
	_weapon = id
	if weapon_mesh != null:
		weapon_mesh.mesh = _weapon_mesh(id, true)
		weapon_root.visible = id != &"none"
		muzzle_node.position = Vector3(0.0, 0.035, 0.82) if id == &"gun" else Vector3(0.0, 0.0, 1.24)
	_stow = -1.0
	if id != &"none" and bob and was != id:
		_draw_t = 0.0
		set_process(true)
	else:
		_draw_t = 1.0
	if mag != null:
		mag.visible = false
	_pose()


func weapon() -> StringName:
	return _weapon


## H7 (ARENA_SPEC §9.4): เริ่มเปลี่ยนเป็น to · hi/mid ย่ออาวุธในมือลงใน holster วิ (set_weapon ขยายอันใหม่ตามมา)
## กลับใจมาอันที่ถืออยู่ = ขยายกลับ · lo/min ไม่ทำอะไร
func begin_switch(to: StringName, holster: float, _draw: float) -> void:
	_last_switch = to
	if not bob or _weapon == &"none":
		return
	if to == _weapon:
		if _stow >= 0.0:
			_draw_t = minf(_draw_t, 1.0 - _stow)
			_stow = -1.0
			set_process(true)
		return
	_stow = 0.0
	_stow_len = maxf(holster, 0.01)
	set_process(true)
	_pose()


func last_switch() -> StringName:
	return _last_switch


## ท่าฟันล่าสุด &"a" / &"b"
func swing_arc() -> StringName:
	return _arc


## แสงวาบตอนโดน 0..1 (ไข่สว่างขึ้น)
func set_flash(a: float) -> void:
	_flash = clampf(a, 0.0, 1.0)
	_update_material()


## ผู้เล่นไม่มีสีเตือน
func set_telegraph(_a: float) -> void:
	pass


## กล้องถูกบีบเข้าใกล้: ไข่จางลง (ส่วนเสริม ไม่อยู่ในสัญญา; ผู้เล่นเรียกถ้ามี)
func set_fade(a: float) -> void:
	a = clampf(a, 0.0, 1.0)
	if absf(a - _fade) < 0.01:
		return
	_fade = a
	_update_material()


func fade() -> float:
	return _fade


func muzzle() -> Node3D:
	return muzzle_node


func anchor(n: StringName) -> Node3D:
	return _anchors.get(n)


## ระดับกราฟิก: จำนวนเหลี่ยมของไข่ โยกตัวและชักอาวุธแบบนุ่มบน hi/mid
func apply_level(l: String) -> void:
	if not SIDES.has(l):
		l = "mid"
	level = l
	bob = l == "hi" or l == "mid"
	var sides := int(SIDES[l])
	if sides != _sides and egg != null:
		_sides = sides
		egg.mesh = _egg_mesh(team_colour, sides)
	if not bob:
		_draw_t = 1.0
		_phase = 0.0
		_stow = -1.0
	_pose()


## ท่าที่กำลังเล่น ("" = ท่าวน)
func clip() -> String:
	return _clip


func busy() -> bool:
	return is_processing()


func _process(delta: float) -> void:
	var active := false
	if _clip != "":
		_clip_t += delta * _clip_speed
		if _clip_t >= _clip_len:
			if _clip == "die":
				_dead = true
				_clip_t = _clip_len
				clip_event.emit(&"thud")
			_clip = ""
		else:
			active = true
	if _draw_t < 1.0:
		_draw_t = minf(_draw_t + delta / 0.2, 1.0)
		active = active or _draw_t < 1.0
	if _stow >= 0.0 and _stow < 1.0:
		_stow = minf(_stow + delta / _stow_len, 1.0)
		active = active or _stow < 1.0
	if bob and _speed > 0.05 and not _dead:
		_phase += delta * _speed * (3.2 if _running else 2.8)
		active = true
	else:
		_phase = 0.0
	_pose()
	if not active:
		set_process(false)


# ---- ท่าทาง ----

func _pose() -> void:
	if egg == null:
		return
	var t := _clip_t
	var lean := clampf(-_pitch * 0.25, -LEAN, LEAN)
	var tip := 0.0
	var bob_y := 0.0
	var roll := 0.0
	var twist := 0.0
	if bob and _phase > 0.0:
		bob_y = absf(sin(_phase)) * BOB_H * minf(_speed / 3.0, 1.0)
		# H6: เอนหน้า/หลังตามทิศ y และเอียงยอดไข่ไปทางที่เดินตามทิศ x (ขวามือ = −x ของตัว → หมุน z บวก)
		var k := minf(_speed / 5.0, 1.0)
		var d := _dir if _dir != Vector2.ZERO else Vector2(0.0, 1.0)
		lean += 0.08 * k * d.y
		roll = 0.10 * k * d.x
	var aim_fwd := Vector3(0.0, sin(_pitch), cos(_pitch))
	# อาวุธและมือขวา
	var grip := GRIP_GUN if _weapon == &"gun" else GRIP_SWORD
	var rot := Vector3(-_pitch, 0.0, 0.0)
	if _weapon == &"sword":
		rot = Vector3(SWORD_TILT - _pitch * 0.5, -0.12, 0.0)
	var recoil := 0.0
	var mag_pos := MAG_IN
	var mag_on := false
	var left := REST_L
	var right := REST_R
	var punch := 0.0
	var lean_c := 0.0   # เอนจากท่าครั้งเดียว
	if _dead or _clip == "die":
		var s := 1.0 if _dead else smoothstep(0.0, 1.0, t / CLIPS["die"])
		tip = 1.45 * s
		bob_y = 0.0
	match _clip:
		"fire":
			recoil = RECOIL * (1.0 - t / CLIPS["fire"])
		"reload":
			var e := smoothstep(0.0, 0.25, t) * (1.0 - smoothstep(1.35, 1.6, t))
			rot.x += 0.45 * e
			if t > 0.15 and t < 1.35:
				mag_on = true
				if t < 0.5:
					mag_pos = MAG_IN + Vector3(0.0, -0.38 * smoothstep(0.15, 0.5, t), 0.0)
				elif t < 0.9:
					mag_pos = MAG_IN + Vector3(0.0, -0.38, 0.0)
				else:
					mag_pos = MAG_IN + Vector3(0.0, -0.38 * (1.0 - smoothstep(0.9, 1.3, t)), 0.0)
		"punch":
			punch = sin(PI * clampf(t / CLIPS["punch"], 0.0, 1.0))
			lean_c = LEAN * punch
		"swing":
			_swing_pose(t, grip, rot)
			grip = _sw_grip
			rot = _sw_rot
			twist = _sw_twist
			lean_c = 0.08 * sin(PI * clampf((t - 0.08) / 0.2, 0.0, 1.0))
		"hit":
			lean_c = -0.22 * sin(PI * clampf(t / CLIPS["hit"], 0.0, 1.0))
	var cut_k := 1.0
	if _cut:
		if _clip != "" and t < CUT_BLEND:
			cut_k = smoothstep(0.0, CUT_BLEND, t)
			grip = _cut_grip.lerp(grip, cut_k)
			rot = _cut_rot.lerp(rot, cut_k)
			twist = lerpf(_cut_twist, twist, cut_k)
			lean_c = lerpf(_cut_lean, lean_c, cut_k)
		else:
			_cut = false
	lean += lean_c
	var wb := Basis.from_euler(rot)
	var scale_k := 0.05 + 0.95 * smoothstep(0.0, 1.0, _draw_t)
	if _stow >= 0.0:
		scale_k *= 1.0 - 0.95 * smoothstep(0.0, 1.0, _stow)
	var wpos := grip + Vector3(0.0, bob_y, 0.0) - wb.z * recoil
	if tip > 0.0:
		wpos = wpos.lerp(Vector3(grip.x * 1.4, 0.2, grip.z), tip / 1.45)
	weapon_root.transform = Transform3D(wb.scaled(Vector3.ONE * scale_k), wpos)
	if _weapon != &"none":
		right = wpos
	if _weapon == &"gun" and punch <= 0.0:
		var sup := weapon_root.transform * GUN_SUPPORT
		left = sup
		if mag_on and t > 0.7:
			left = weapon_root.transform * (mag_pos + Vector3(0.0, -0.05, 0.0))
	left += Vector3(0.0, bob_y, 0.0)
	if _weapon == &"none":
		right += Vector3(0.0, bob_y, 0.0)
	if punch > 0.0:
		left = REST_L.lerp(Vector3(0.12, 1.05, 0.25), punch) + aim_fwd * PUNCH_OUT * punch
	if cut_k < 1.0:
		left = _cut_left.lerp(left, cut_k)
	_last_grip = grip
	_last_rot = rot
	_last_twist = twist
	_last_left = left
	_last_lean = lean_c
	if tip > 0.0:
		var k := tip / 1.45
		left = left.lerp(Vector3(0.55, 0.15, 0.1), k)
		right = right.lerp(Vector3(-0.55, 0.15, 0.1), k)
	egg.position = Vector3(0.0, bob_y, 0.0)
	if _dead or _clip == "die":
		roll = 0.0
	egg.rotation = Vector3(lean, twist, tip + roll)
	stowed.visible = _weapon == &"sword" and level != "min" and _stow < 0.0
	var mm := gauntlets.multimesh
	mm.set_instance_transform(0, Transform3D(Basis.from_euler(Vector3(-_pitch if _weapon == &"gun" else 0.0, 0.0, 0.0)), right))
	mm.set_instance_transform(1, Transform3D(Basis.from_euler(Vector3(-_pitch * punch, 0.0, 0.0)), left))
	weapon_mesh.mesh = _weapon_mesh(_weapon, not mag_on)
	mag.visible = mag_on and _weapon == &"gun"
	if mag.visible:
		mag.position = mag_pos
	(_anchors[&"hand_r"] as Node3D).position = right
	(_anchors[&"hand_l"] as Node3D).position = left


## ท่าฟัน ณ เวลา t -> _sw_grip (ด้าม) _sw_rot (มุมดาบ) _sw_twist (บิดไข่) · ด้ามเลื่อนรอบแกนไข่ (มุม รัศมี ความสูง)
## จึงไม่ผ่านเข้าในตัวไข่ · ช่วงง้างและกลับท่าค่อย ๆ เร่ง-ผ่อน ช่วงฟันเร่งเข้าหาจังหวะโดนแล้วผ่อนหลังโดน
## ช่วง i: ท่าตั้ง -> คีย์ 0 -> 1 -> 2 -> ท่าตั้ง (อ่านจากค่าคงที่ตรง ๆ ไม่สร้าง Array ทุกเฟรม แม้บน min)
func _swing_pose(t: float, guard: Vector3, guard_rot: Vector3) -> void:
	var keys: Array = SWING_A if _arc == &"a" else SWING_B
	var n := keys.size()
	var i := 0
	while i < n and t >= float(keys[i][0]):
		i += 1
	var ta := 0.0
	var pa := guard
	var ra := guard_rot
	var wa := 0.0
	if i > 0:
		var ka: Array = keys[i - 1]
		ta = ka[0]
		pa = ka[1]
		ra = ka[2]
		wa = ka[3]
	var tb: float = CLIPS["swing"]
	var pb := guard
	var rb := guard_rot
	var wb := 0.0
	if i < n:
		var kb: Array = keys[i]
		tb = kb[0]
		pb = kb[1]
		rb = kb[2]
		wb = kb[3]
	var s := clampf((t - ta) / (tb - ta), 0.0, 1.0)
	if i == 1:
		s = s * s
	elif i == 2:
		s = 1.0 - (1.0 - s) * (1.0 - s)
	else:
		s = smoothstep(0.0, 1.0, s)
	var ang := lerpf(atan2(pa.x, pa.z), atan2(pb.x, pb.z), s)
	var rad := lerpf(Vector2(pa.x, pa.z).length(), Vector2(pb.x, pb.z).length(), s)
	_sw_grip = Vector3(sin(ang) * rad, lerpf(pa.y, pb.y, s), cos(ang) * rad)
	_sw_rot = ra.lerp(rb, s)
	_sw_twist = lerpf(wa, wb, s)


func _update_material() -> void:
	if egg == null:
		return
	if _flash <= 0.001 and _fade >= 0.999:
		egg.material_override = HallBuilder.material()
		stowed.material_override = egg.material_override
		return
	if _flash > 0.001:
		if _flash_mat == null:
			_flash_mat = HallBuilder.material().duplicate() as StandardMaterial3D
			_flash_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		var k := 1.0 + 2.2 * _flash
		_flash_mat.albedo_color = Color(k, k, k, _fade)
		egg.material_override = _flash_mat
		stowed.material_override = _flash_mat
		return
	if _fade_mat == null:
		_fade_mat = HallBuilder.material().duplicate() as StandardMaterial3D
		_fade_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_fade_mat.albedo_color = Color(1.0, 1.0, 1.0, _fade)
	egg.material_override = _fade_mat
	stowed.material_override = _fade_mat


# ---- โหนดและเมช ----

func _build_nodes() -> void:
	if egg != null:
		return
	egg = MeshInstance3D.new()
	egg.name = "Egg"
	egg.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	egg.material_override = HallBuilder.material()
	add_child(egg)
	gauntlets = MultiMeshInstance3D.new()
	gauntlets.name = "Gauntlets"
	gauntlets.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	gauntlets.material_override = HallBuilder.material()
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = fist_mesh()
	mm.instance_count = 2
	gauntlets.multimesh = mm
	add_child(gauntlets)
	weapon_root = Node3D.new()
	weapon_root.name = "Weapon"
	add_child(weapon_root)
	weapon_mesh = MeshInstance3D.new()
	weapon_mesh.name = "WeaponMesh"
	weapon_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	weapon_mesh.material_override = HallBuilder.material()
	weapon_root.add_child(weapon_mesh)
	mag = MeshInstance3D.new()
	mag.name = "Mag"
	mag.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mag.material_override = HallBuilder.material()
	mag.mesh = mag_mesh()
	mag.visible = false
	weapon_root.add_child(mag)
	muzzle_node = Marker3D.new()
	muzzle_node.name = "Muzzle"
	muzzle_node.position = Vector3(0.0, 0.035, 0.82)
	weapon_root.add_child(muzzle_node)
	weapon_root.visible = false
	stowed = MeshInstance3D.new()
	stowed.name = "Stowed"
	stowed.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	stowed.material_override = HallBuilder.material()
	stowed.mesh = rifle_mesh(true)
	var up := STOW_UP.normalized()
	var side := Vector3(0.0, 0.0, -1.0)
	stowed.transform = Transform3D(Basis(side, up.cross(side), up), STOW_AT)
	stowed.visible = false
	egg.add_child(stowed)
	for a in [[&"head", Vector3(0.0, 1.6, 0.0)], [&"chest", Vector3(0.0, 1.1, 0.0)], [&"hand_r", REST_R], [&"hand_l", REST_L]]:
		var m := Marker3D.new()
		m.name = "Anchor_" + String(a[0])
		m.position = a[1]
		add_child(m)
		_anchors[a[0]] = m
	egg.mesh = _egg_mesh(team_colour, int(SIDES.get(level, 12)))


static func _egg_mesh(team: Color, sides: int) -> ArrayMesh:
	var key := "egg|%s|%d" % [team.to_html(false), sides]
	if not _mesh_cache.has(key):
		_mesh_cache[key] = HallBuilder.avatar_mesh(team, sides)
	return _mesh_cache[key]


static func _weapon_mesh(id: StringName, with_mag: bool) -> ArrayMesh:
	match id:
		&"gun":
			return rifle_mesh(with_mag)
		&"sword":
			return sword_mesh()
	return null


## แสงอบง่าย ๆ ทิศเดียวจากบนหน้า (วัสดุไม่รับแสง)
static func _shade(g: PropsLayer.Geo) -> void:
	var l := Vector3(0.35, 0.85, 0.4).normalized()
	var cols := g.c
	for i in cols.size():
		var f := 0.6 + 0.4 * clampf(g.n[i].dot(l) * 0.5 + 0.5, 0.0, 1.0)
		var c := cols[i]
		cols[i] = Color(c.r * f, c.g * f, c.b * f, 1.0)
	g.c = cols


## ท่อ 8 เหลี่ยมตามแกน z (มีฝา) ศูนย์กลาง (x, y) จาก z0 ถึง z1
static func _zprism(g: PropsLayer.Geo, x: float, y: float, z0: float, z1: float, r: float, sides: int, col: Color, caps := true) -> void:
	var a0: Array[Vector3] = []
	var a1: Array[Vector3] = []
	for i in sides:
		var a := TAU * (i + 0.5) / sides
		a0.append(Vector3(x + cos(a) * r, y + sin(a) * r, z0))
		a1.append(Vector3(x + cos(a) * r, y + sin(a) * r, z1))
	for i in sides:
		var k := (i + 1) % sides
		var mid := (a0[i] + a0[k]) * 0.5 - Vector3(x, y, z0)
		g.poly([a0[i], a0[k], a1[k], a1[i]], col, mid)
	if caps:
		g.poly(a0, col * 0.8, Vector3.FORWARD)
		g.poly(a1, col * 0.9, Vector3.BACK)


## กำปั้นถุงมือบรอนซ์ 8 เหลี่ยม r 0.11 (หน้า +z) ข้อนิ้วทองเหลือง ข้อมือเหล็ก
static func fist_mesh() -> ArrayMesh:
	if _mesh_cache.has("fist"):
		return _mesh_cache["fist"]
	var g := PropsLayer.Geo.new()
	_zprism(g, 0.0, 0.0, -0.08, 0.07, FIST_R, 8, HallBuilder.BRONZE)
	for i in 4:
		var x := -0.06 + i * 0.04
		g.box(Vector3(x, 0.035, 0.085), Vector3(0.016, 0.03, 0.02), HallBuilder.BRASS)
	_zprism(g, 0.0, 0.0, -0.15, -0.08, 0.075, 8, HallBuilder.STEEL_DARK)
	g.box(Vector3(0.0, 0.0, -0.115), Vector3(0.085, 0.022, 0.012), HallBuilder.BRASS)
	_shade(g)
	var m := g.mesh()
	_mesh_cache["fist"] = m
	return m


## ปืนไรเฟิลของเรา (พิกัดปืน: ด้ามที่จุดกำเนิด ลำกล้องไป +z): โครงทองเหลือง 0.5 × 0.12 × 0.09 ลำกล้องเหล็ก 0.45 ม.
## ในปลอกระบายความร้อนเจาะร่อง แมกกล่องสั้น พานท้ายโครงโปร่งมีตราเปลวเทียนทองเหลือง
static func rifle_mesh(with_mag: bool = true) -> ArrayMesh:
	var key := "rifle|%s" % with_mag
	if _mesh_cache.has(key):
		return _mesh_cache[key]
	var g := PropsLayer.Geo.new()
	var brass := HallBuilder.BRASS
	var steel := HallBuilder.STEEL
	var dark := HallBuilder.STEEL_DARK
	# ด้ามจับ เอียงไปหลังนิดหนึ่ง
	g.poly([Vector3(-0.022, -0.02, 0.03), Vector3(0.022, -0.02, 0.03), Vector3(0.022, -0.14, -0.02), Vector3(-0.022, -0.14, -0.02)], GRIP_COL, Vector3.BACK)
	g.poly([Vector3(-0.022, -0.02, -0.03), Vector3(0.022, -0.02, -0.03), Vector3(0.022, -0.14, -0.07), Vector3(-0.022, -0.14, -0.07)], GRIP_COL, Vector3.FORWARD)
	g.poly([Vector3(-0.022, -0.02, 0.03), Vector3(-0.022, -0.02, -0.03), Vector3(-0.022, -0.14, -0.07), Vector3(-0.022, -0.14, -0.02)], GRIP_COL * 0.9, Vector3.LEFT)
	g.poly([Vector3(0.022, -0.02, 0.03), Vector3(0.022, -0.02, -0.03), Vector3(0.022, -0.14, -0.07), Vector3(0.022, -0.14, -0.02)], GRIP_COL * 0.9, Vector3.RIGHT)
	# โครงปืน (receiver) และราง
	g.box(Vector3(0.0, 0.03, 0.08), Vector3(0.045, 0.06, 0.25), brass, 0.0, true)
	g.box(Vector3(0.0, 0.096, 0.08), Vector3(0.016, 0.008, 0.21), dark)
	g.box(Vector3(0.0, 0.03, 0.08), Vector3(0.047, 0.012, 0.18), HallBuilder.BRONZE)
	# ศูนย์หน้า/หลัง
	g.box(Vector3(0.0, 0.115, -0.08), Vector3(0.012, 0.014, 0.012), dark)
	g.box(Vector3(0.0, 0.112, 0.3), Vector3(0.006, 0.014, 0.008), dark)
	# ปลอกระบายความร้อนเจาะร่อง + ลำกล้อง + ปากลำกล้อง
	_zprism(g, 0.0, 0.035, 0.33, 0.63, 0.046, 8, steel)
	for side in [-1.0, 1.0]:
		for i in 4:
			var z := 0.37 + i * 0.065
			g.box(Vector3(side * 0.043, 0.035, z), Vector3(0.006, 0.018, 0.022), Color("101114"))
	_zprism(g, 0.0, 0.035, 0.63, 0.78, 0.025, 8, dark)
	_zprism(g, 0.0, 0.035, 0.76, 0.82, 0.034, 8, brass)
	# แมกกล่องสั้น
	if with_mag:
		_mag_geo(g, MAG_IN)
	# พานท้ายโครงโปร่ง + แผ่นท้าย + ตราเทียน
	g.box(Vector3(0.0, 0.06, -0.33), Vector3(0.014, 0.012, 0.16), dark)
	HallBuilder.tube(g, Vector3(0.0, -0.03, -0.17), Vector3(0.0, -0.065, -0.49), 0.012, 6, dark)
	g.box(Vector3(0.0, 0.0, -0.5), Vector3(0.026, 0.075, 0.016), brass)
	for side in [-1.0, 1.0]:
		HallBuilder.emblem(g, Vector3(side * 0.016, 0.005, -0.32), Vector3(0.0, 0.0, 1.0), Vector3(side, 0.0, 0.0), 0.042,
			brass, HallBuilder.WAX, HallBuilder.LAMP_AMBER, 12)
	_shade(g)
	var m := g.mesh()
	_mesh_cache[key] = m
	return m


static func _mag_geo(g: PropsLayer.Geo, at: Vector3) -> void:
	g.box(at + Vector3(0.0, -0.01, 0.0), Vector3(0.03, 0.07, 0.04), HallBuilder.STEEL_DARK, 0.0, true)
	g.box(at + Vector3(0.0, -0.01, 0.0), Vector3(0.032, 0.012, 0.042), HallBuilder.BRASS)


## แมกที่หล่นตอนบรรจุ (เมชแยก พิกัดแมกอยู่ที่จุดกำเนิด)
static func mag_mesh() -> ArrayMesh:
	if _mesh_cache.has("mag"):
		return _mesh_cache["mag"]
	var g := PropsLayer.Geo.new()
	_mag_geo(g, Vector3.ZERO)
	_shade(g)
	var m := g.mesh()
	_mesh_cache["mag"] = m
	return m


## ดาบเลื่อยของเรา (พิกัดดาบ: ด้ามที่จุดกำเนิด ใบไป +z): ใบเหล็ก 1.0 ม. ฟัน 18 ซี่ตามสันบน (ไม่ขยับ)
## ห้องมอเตอร์ทรงกล่อง ช่องระบายทองเหลือง ตราเทียนของเรา ด้ามจับ
static func sword_mesh() -> ArrayMesh:
	if _mesh_cache.has("sword"):
		return _mesh_cache["sword"]
	var g := PropsLayer.Geo.new()
	var brass := HallBuilder.BRASS
	HallBuilder.tube(g, Vector3(0.0, 0.0, -0.13), Vector3(0.0, 0.0, 0.03), 0.022, 8, GRIP_COL)
	g.box(Vector3(0.0, 0.0, -0.145), Vector3(0.03, 0.03, 0.02), brass, 0.0, true)
	# ห้องมอเตอร์
	g.box(Vector3(0.0, 0.0, 0.12), Vector3(0.05, 0.075, 0.09), HallBuilder.STEEL, 0.0, true)
	for side in [-1.0, 1.0]:
		for i in 3:
			g.box(Vector3(side * 0.052, 0.035 - i * 0.03, 0.15), Vector3(0.004, 0.008, 0.045), brass)
		HallBuilder.emblem(g, Vector3(side * 0.053, -0.035, 0.08), Vector3(0.0, 0.0, 1.0), Vector3(side, 0.0, 0.0), 0.03,
			brass, HallBuilder.WAX, HallBuilder.LAMP_AMBER, 10)
	# กระบัง
	g.box(Vector3(0.0, 0.0, 0.22), Vector3(0.065, 0.095, 0.014), HallBuilder.BRONZE, 0.0, true)
	# ใบดาบ (ปลายเฉียง)
	var z0 := 0.23
	var z1 := 1.23
	var h := 0.045
	var w := 0.01
	for side in [-1.0, 1.0]:
		g.poly([Vector3(side * w, -h, z0), Vector3(side * w, h, z0), Vector3(side * w, h, z1 - 0.06), Vector3(side * w, -h * 0.2, z1),
			Vector3(side * w, -h, z1 - 0.02)], BLADE, Vector3(side, 0.0, 0.0))
	g.poly([Vector3(-w, -h, z0), Vector3(w, -h, z0), Vector3(w, -h, z1 - 0.02), Vector3(-w, -h, z1 - 0.02)], BLADE * 0.8, Vector3.DOWN)
	g.poly([Vector3(-w, h, z0), Vector3(w, h, z0), Vector3(w, h, z1 - 0.06), Vector3(-w, h, z1 - 0.06)], TEETH, Vector3.UP)
	# ฟัน 18 ซี่ตามสันบน
	var n := 18
	var span := (z1 - 0.06 - z0) / n
	for i in n:
		var a := z0 + i * span
		var tip := Vector3(0.0, h + 0.032, a + span * 0.75)
		for side in [-1.0, 1.0]:
			g.poly([Vector3(side * w * 0.8, h, a), Vector3(side * w * 0.8, h, a + span), tip + Vector3(side * w * 0.3, 0.0, 0.0)],
				TEETH, Vector3(side, 0.2, 0.0))
	# แถบโซ่ใบเลื่อยสีเข้มตามสัน
	for side in [-1.0, 1.0]:
		g.poly([Vector3(side * (w + 0.001), h - 0.012, z0), Vector3(side * (w + 0.001), h, z0), Vector3(side * (w + 0.001), h, z1 - 0.06),
			Vector3(side * (w + 0.001), h - 0.012, z1 - 0.06)], TEETH * 0.7, Vector3(side, 0.0, 0.0))
	_shade(g)
	var m := g.mesh()
	_mesh_cache["sword"] = m
	return m
