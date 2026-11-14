class_name ArenaPlayer
extends CharacterBody3D
## ผู้เล่นในอารีน่า (ARENA_SPEC §5, §6.3, สัญญา §12.3): ตัวละครตามสัญญา §9.1 (ไข่ถือปืนของเราเป็นค่าตั้งต้น ถอดเปลี่ยนได้)
## walk = เดินแบบดาดฟ้า (กล้องตาม) · shoot = ยิงมุมมองบุคคลที่สาม (กล้องข้ามไหล่) · ทั้งสองโหมดตัวหันตามกล้องเสมอ (14 พ.ย.)
## เดสก์ท็อป: เมาส์เล็ง (จับเมาส์ตอนเข้า shoot) คลิกซ้ายยิง คลิกขวา/F ต่อย R บรรจุ 1/2/ล้อ เปลี่ยนอาวุธ · มือถือ: ArenaTouch ส่ง
## set_stick / aim_drag / press มา · ปืน: รังสีเล็งจากกล้องผ่านกลางจอ แล้วยิงจริงจากปากกระบอกไปจุดเล็ง (เสาบังได้จริง)
## ลอยตัวที่ y = 0 แคปซูล r 0.35 สูง 1.75 ชั้น 2 ชนชั้น 1 | 4 | 8 · ตัวเลขต่อสู้ทั้งหมดจาก ArenaData
## พุ่งหลบ: Space (ปุ่มจริง ทุกโหมด) หรือปุ่ม "หลบ" บนจอ = press(&"dodge") พุ่งตามทิศที่กด (ไม่กด = ถอยหลัง) ตัวเลขจาก
## ArenaData.DODGE คณิตจาก ArenaCombat · ชนเสา/ผนังด้วย move_and_slide · ช่วงต้นอมตะ · ตัวละครเสริม H8 begin_dodge
## H9 uses_strafe() false = ไม่เดินเยื้อง: ตัวยังหันตามกล้อง แต่ขาเดินหน้าทั้งตอนเดินหน้า/ข้าง ถอยหลังใช้ท่าถอย (ArenaCombat.leg_dir)
## งานต่อเฟรม: _physics_process เฉพาะตอนเดิน อาวุธยังนับเวลา (ArenaWeapons.busy) ล้ม/อมตะชั่วครู่ แสงวาบ พุ่ง/คูลดาวน์
## แล้วปิดตัวเอง

signal moved(pos: Vector3)
signal mode_changed(mode: StringName)
signal weapon_changed(id: StringName)
signal ammo_changed(in_mag: int, mag_size: int)
signal reload_changed(on: bool, seconds: float)
signal hp_changed(hp: int, hp_max: int)
signal hit_landed(info: Dictionary)
signal hurt(info: Dictionary)
signal downed()
signal revived()
## เป้าเล็งกลางจอชี้ที่ศัตรูหรือไม่ (ส่งเฉพาะตอนค่าเปลี่ยน; ส่วนเสริมของสัญญา ใช้ทำเป้าสีแดง)
signal aim_changed(on_beast: bool)
## พุ่งหลบ: &"dash" เริ่มพุ่ง, &"cool" พุ่งจบ (รอคูลดาวน์), &"ready" พุ่งได้อีก
signal dodge_changed(state: StringName)

const RADIUS := 0.35
const HEIGHT := 1.75
const RUN_STICK := 0.85
const STOP := 0.01
const MOVE_ACTIONS: Array[StringName] = [&"move_forward", &"move_back", &"move_left", &"move_right", &"run"]
const PLAYER_LAYER := 2
const BODY_MASK := 1 | 4 | 8
const SHOT_MASK := 1 | 4 | 8 | 16
const AIM_RANGE := 80.0
const CHEST := Vector3(0.0, 1.1, 0.0)
const FLASH_TIME := 0.12
const FADE_NEAR := 0.6
const FADE_FAR := 1.2
const FADE_MIN := 0.35
const EGG_GUNNER := "res://scenes/arena/egg_gunner.gd"
const ARENA_LAYOUT := "res://scenes/arena/arena_layout.gd"
const RESPAWN_FALLBACK := Vector3(0.0, 0.0, -12.5)
const DODGE_ACTION := &"dodge"

var world: Node3D
var level := "mid"
var touch := false
## สลับแบบนุ่ม สั่นกล้อง (hi/mid)
var smooth := true
var stick := Vector2.ZERO
var face := PI
var weapons := ArenaWeapons.new()

@onready var rig: ArenaCamera = $CameraRig
@onready var fx: ArenaFx = $Fx

var _figure: Node3D
var _mode: StringName = &"walk"
var _hp := 100
var _hp_max := 100
var _input_on := true
var _paused := false
var _vel := Vector3.ZERO
var _invuln := 0.0
var _down := 0.0
var _flash := 0.0
var _recapture := false
var _aim_dirty := false
var _aim_beast := false
var _captured := false
var _alpha := 1.0
var _fig_dir := false        # ตัวละครมี set_move_dir (H6) · ตรวจครั้งเดียวตอน setup ไม่ใช่ทุกเฟรม
var _fig_switch := false     # ตัวละครมี begin_switch (H7)
var _fig_dodge := false      # ตัวละครมี begin_dodge (H8)
var _strafe := true          # H9 uses_strafe() (ไม่มี = เดินเยื้องได้)
var _dodge_t := -1.0         # เวลาที่พุ่งไปแล้ว (ติดลบ = ไม่ได้พุ่ง)
var _dodge_dir := Vector3.ZERO
var _since_dodge := INF      # เวลานับจากพุ่งครั้งก่อนจบ
var _fire_held := false      # ปุ่มยิงยังกดอยู่ (คืนไกปืนหลังพุ่งจบ)
var _saw_loop := 0


func _ready() -> void:
	motion_mode = CharacterBody3D.MOTION_MODE_FLOATING
	collision_layer = PLAYER_LAYER
	collision_mask = BODY_MASK
	disable_mode = CollisionObject3D.DISABLE_MODE_KEEP_ACTIVE
	rotation.y = face
	_hp_max = int(ArenaData.PLAYER["hp"])
	_hp = _hp_max
	ensure_dodge_action()
	rig.arm_settled.connect(_on_arm)
	rig.turned.connect(_on_turned)
	fx.view = rig.camera
	fx.reseed(int(ArenaData.RANGE["seed"]))
	visibility_changed.connect(func() -> void:
		if not is_visible_in_tree():
			_release_mouse()
			_saw_sound(false)
		else:
			_saw_sound(weapons.current == &"sword"))
	set_physics_process(false)


## ปุ่มพุ่งหลบ: Space ตามตำแหน่งปุ่มจริง (physical) · โปรเจกต์มีแอคชัน dodge อยู่แล้วก็ใช้ของเดิม
static func ensure_dodge_action() -> void:
	if InputMap.has_action(DODGE_ACTION):
		return
	InputMap.add_action(DODGE_ACTION)
	var k := InputEventKey.new()
	k.physical_keycode = KEY_SPACE
	InputMap.action_add_event(DODGE_ACTION, k)


## ตั้งค่าตอนโลกสร้างผู้เล่น: {"level", "team_colour", "touch": bool, "figure": Node3D}
func setup(w: Node3D, opts: Dictionary) -> void:
	world = w
	touch = bool(opts.get("touch", false))
	var fig: Node3D = opts.get("figure")
	if fig == null:
		var s: Script = load(EGG_GUNNER)
		fig = s.new() if s != null else Node3D.new()
	if _figure != null and _figure != fig:
		_figure.queue_free()
	_figure = fig
	if fig.get_parent() == null:
		fig.name = "Figure"
		add_child(fig)
	if fig.has_method("setup"):
		fig.call("setup", {"role": &"player", "level": str(opts.get("level", level)),
			"team_colour": opts.get("team_colour", Color(0.28, 0.52, 0.84)), "seed": int(ArenaData.RANGE["seed"])})
	fig.rotation = Vector3.ZERO
	_fig_dir = fig.has_method("set_move_dir")
	_fig_switch = fig.has_method("begin_switch")
	_fig_dodge = fig.has_method("begin_dodge")
	_strafe = not fig.has_method("uses_strafe") or bool(fig.call("uses_strafe"))
	apply_level(str(opts.get("level", level)))
	_call_fig("set_weapon", [&"none"])
	_call_fig("play", [&"idle", 1.0])


func apply_level(l: String) -> void:
	level = l
	smooth = l == "hi" or l == "mid"
	rig.smooth = smooth
	fx.apply_level(l)
	_call_fig("apply_level", [l])


## เปิด/ปิดโหมดปุ่มบนจอ (มือถือไม่จับเมาส์)
func set_touch(on: bool) -> void:
	touch = on
	if on:
		_release_mouse()
	elif _mode == &"shoot" and not _paused:
		_capture()


func camera() -> Camera3D:
	return rig.camera


func camera_rig() -> Node3D:
	return rig


func figure() -> Node3D:
	return _figure


func mode() -> StringName:
	return _mode


## walk ↔ shoot (โลกเรียกตามเส้นยิงพร้อมระยะกันสั่น): ชัก/เก็บปืน สลับกล้อง จับ/ปล่อยเมาส์
func set_mode(m: StringName) -> void:
	if m == _mode:
		return
	_mode = m
	if m == &"shoot":
		rig.set_shoulder(true, not smooth)
		_face_camera()
		_handle(weapons.draw(&"gun"))
		_capture()
	else:
		_handle(weapons.holster())
		rig.set_shoulder(false, not smooth)
		_release_mouse()
		_call_fig("set_aim", [0.0])
		_set_aim_beast(false)
	rig.follow(global_position)
	mode_changed.emit(m)
	ammo_changed.emit(weapons.in_mag, weapons.mag_size)
	set_physics_process(true)


func set_stick(v: Vector2) -> void:
	stick = v
	set_physics_process(true)


## เล็งด้วยนิ้ว (พิกเซลของ canvas)
func aim_drag(rel: Vector2) -> void:
	if not aim_active():
		return
	rig.look(-rel.x * ArenaCamera.TOUCH_LOOK, -rel.y * ArenaCamera.TOUCH_LOOK)
	_on_look()


## ปุ่มบนจอ/คีย์: fire (กดค้าง), melee, reload, weapon (สลับ), weapon_1, weapon_2, dodge (ทุกโหมด)
## ระหว่างพุ่งปุ่มอื่นไม่ทำงาน (กดยิงค้างไว้ = ยิงต่อหลังพุ่งจบ)
func press(action: StringName, on: bool) -> void:
	if action == &"fire":
		_fire_held = on
	if action == DODGE_ACTION:
		if on:
			dodge()
		return
	if not on:
		if action == &"fire":
			_handle(weapons.set_trigger(false))
		return
	if not _input_on or _paused or _down > 0.0 or _mode != &"shoot" or dodging():
		return
	if action == &"fire" and weapons.current == &"gun" and weapons.in_mag <= 0 and not weapons.trigger:
		ArenaSound.play(self, "empty")
	var was_sw := weapons.switching()
	var was_held := weapons.held()
	match action:
		&"fire":
			_handle(weapons.set_trigger(true))
		&"melee":
			_handle(weapons.melee())
		&"reload":
			_handle(weapons.reload())
		&"weapon":
			_handle(weapons.cycle())
		&"weapon_1":
			_handle(weapons.switch_to(&"gun"))
		&"weapon_2":
			_handle(weapons.switch_to(&"sword"))
	# H7: บอกตัวละครตอนเริ่มเปลี่ยนอาวุธ (เริ่มใหม่ หรือกลับใจไปอีกอัน) set_weapon ยังมาหลัง holster วิเหมือนเดิม
	if _fig_switch and weapons.switching() and (not was_sw or weapons.held() != was_held):
		_figure.call("begin_switch", weapons.held(), float(ArenaData.PLAYER["holster"]), float(ArenaData.PLAYER["draw"]))
	set_physics_process(true)


## พุ่งหลบตามทิศที่กด (ไม่กด = ถอยหลังจากทิศที่ตัวหัน) · คืน true เมื่อได้พุ่ง
func dodge() -> bool:
	if not _input_on or _paused or not ArenaCombat.can_dodge(_since_dodge, 0.0, is_alive(), dodging()):
		return false
	var iv := input_vector()
	var w := -Vector3(sin(face), 0.0, cos(face))
	if iv.length() >= 0.1:
		var d := ArenaCombat.dodge_dir(iv)
		w = rig.right_flat() * d.x + rig.forward_flat() * d.y
		w = Vector3(w.x, 0.0, w.z).normalized()
	_dodge_dir = w
	_dodge_t = 0.0
	_handle(weapons.set_trigger(false))
	if _fig_dodge:
		_figure.call("begin_dodge", ArenaCombat.leg_dir(local_dir(w, face), _strafe), float(ArenaData.DODGE["time"]))
	fx.dust(global_position, -w)
	ArenaSound.play(self, "dodge", global_position + Vector3(0.0, 0.6, 0.0))
	dodge_changed.emit(&"dash")
	set_physics_process(true)
	return true


func dodging() -> bool:
	return _dodge_t >= 0.0


## เวลาที่เหลือก่อนพุ่งได้อีก (วิ) 0 = พร้อม
func dodge_wait() -> float:
	var d := ArenaData.DODGE
	if dodging():
		return maxf(float(d["time"]) - _dodge_t, 0.0) + float(d["cooldown"])
	return maxf(float(d["cooldown"]) - _since_dodge, 0.0)


## 0..1 ของวงคูลดาวน์ (1 = พร้อม)
func dodge_ready_ratio() -> float:
	var d := ArenaData.DODGE
	return 1.0 - dodge_wait() / (float(d["time"]) + float(d["cooldown"]))


## H9: ตัวละครเดินเยื้องได้ไหม (ไข่ = ได้)
func strafes() -> bool:
	return _strafe


func set_input_enabled(on: bool) -> void:
	_input_on = on
	rig.input_enabled = on
	if not on:
		stick = Vector2.ZERO
	else:
		set_physics_process(true)   # ปุ่มที่กดค้างไว้ตอนจอมืดเดินได้ทันที (ไม่มีอะไรกด = หลับในติ๊กเดียว)
		_handle(weapons.set_trigger(false))
		rig.reset_input()


## หยุดเกม: ผู้เล่น กล้อง เอฟเฟกต์ ตัวละครหยุดคิด (ตัวชนยังอยู่) ปล่อยเมาส์; เล่นต่อ: คลิกซ้ายครั้งถัดไปแค่จับเมาส์ ไม่ยิง
func set_paused(on: bool) -> void:
	if on == _paused:
		return
	_paused = on
	_handle(weapons.set_trigger(false))
	var pm := Node.PROCESS_MODE_DISABLED if on else Node.PROCESS_MODE_INHERIT
	rig.process_mode = pm
	fx.process_mode = pm
	if _figure != null:
		_figure.process_mode = pm
	if on:
		stick = Vector2.ZERO
		rig.reset_input()
		_release_mouse()
		_saw_sound(false)
		_fire_held = false
		set_physics_process(false)
	else:
		_recapture = _mode == &"shoot" and not touch
		_saw_sound(weapons.current == &"sword")
		set_physics_process(true)


func paused() -> bool:
	return _paused


## วางตัวทันที: กล้องหัน cam_yaw ตัวหันตามกล้องเสมอ (_face_yaw คงไว้ให้ผู้เรียกเดิม ไม่ใช้แล้ว)
func place(p: Vector3, _face_yaw: float, cam_yaw: float) -> void:
	global_position = Vector3(p.x, 0.0, p.z)
	_vel = Vector3.ZERO
	_fire_held = false
	if dodging():
		_end_dodge()
	velocity = Vector3.ZERO
	face = wrapf(cam_yaw, -PI, PI) + PI
	rotation.y = face
	rig.set_view(cam_yaw, rig.pitch if _mode == &"shoot" else ArenaCamera.WALK_PITCH, ArenaCamera.WALK_ARM)
	rig.snap(global_position)
	if _mode == &"shoot":
		_face_camera()
	moved.emit(global_position)


## โดนตี (กรงเล็บของศัตรู): อมตะ 0.4 วิหลังโดน · HP 0 = ล้ม 2 วิแล้วลุกที่จุดเกิดใหม่พร้อม HP เต็ม
func take_hit(hit: Dictionary) -> Dictionary:
	if dodging() and ArenaCombat.dodge_invulnerable(_dodge_t):
		return {"applied": 0, "hp": _hp, "killed": false, "dodged": true}
	if _down > 0.0 or _invuln > 0.0 or _hp <= 0:
		return {"applied": 0, "hp": _hp, "killed": false}
	var r: Dictionary = ArenaCombat.apply(_hp, int(hit.get("amount", 0)))
	_hp = int(r["hp"])
	var applied := int(r["applied"])
	_invuln = float(ArenaData.PLAYER["invuln"])
	_flash = FLASH_TIME
	_call_fig("set_flash", [1.0])
	hp_changed.emit(_hp, _hp_max)
	hurt.emit({"amount": applied, "from": hit.get("from", global_position)})
	if bool(r["killed"]):
		_go_down()
	else:
		_call_fig("play", [&"hit", 1.0])
	set_physics_process(true)
	return {"applied": applied, "hp": _hp, "killed": bool(r["killed"])}


## รีเซ็ต: HP เต็ม แมกเต็ม (ล้มอยู่ก็ลุกทันทีที่เดิม)
func heal_full() -> void:
	_hp = _hp_max
	_handle(weapons.refill())
	if _down > 0.0:
		_down = 0.0
		_call_fig("play", [&"idle", 1.0])
		set_input_enabled(true)
		revived.emit()
	hp_changed.emit(_hp, _hp_max)
	ammo_changed.emit(weapons.in_mag, weapons.mag_size)


func is_alive() -> bool:
	return _hp > 0 and _down <= 0.0


func is_downed() -> bool:
	return _down > 0.0


func hp() -> int:
	return _hp


func hp_max() -> int:
	return _hp_max


func weapon() -> StringName:
	return weapons.current


func ammo() -> Vector2i:
	return weapons.ammo()


func aim_active() -> bool:
	return _mode == &"shoot" and not _paused and _input_on


func aim_on_beast() -> bool:
	return _aim_beast


## ตรวจเป้าเล็งใหม่ในเฟรมฟิสิกส์ถัดไป (โลกเรียกเมื่อศัตรูขยับ เปลี่ยนสถานะ ล้ม หรือรีเซ็ต)
func refresh_aim() -> void:
	if _mode != &"shoot":
		return
	_aim_dirty = true
	set_physics_process(true)


## รังสีเล็งจากกล้องผ่านกลางจอ 80 ม. (ไม่ชนตัวเอง): {"from", "to", "point", "collider"}
func aim_ray() -> Dictionary:
	var o := rig.aim_origin()
	var d := rig.aim_dir()
	var to := o + d * AIM_RANGE
	var r := _ray(o, to)
	return {"from": o, "to": to, "point": r.get("position", to), "collider": r.get("collider")}


## ทิศที่ผู้เล่นสั่ง (x = ขวา, y = หน้า) ความยาวไม่เกิน 1: จอยก่อน ไม่งั้นปุ่ม
func input_vector() -> Vector2:
	if not _input_on or _paused or _down > 0.0:
		return Vector2.ZERO
	var v := stick
	if v == Vector2.ZERO:
		v = Vector2(_strength(&"move_right") - _strength(&"move_left"), _strength(&"move_forward") - _strength(&"move_back"))
	return v.limit_length(1.0)


func running() -> bool:
	return stick.length() > RUN_STICK or (InputMap.has_action(&"run") and Input.is_action_pressed(&"run"))


func speed() -> float:
	return Vector2(_vel.x, _vel.z).length()


## H6 (ARENA_SPEC §9.4): ทิศความเร็วจริงในกรอบตัวละครที่หัน face_yaw (x = ขวามือของตัว = −X ของตัว, y = หน้า +Z)
## ยาว 1 หรือศูนย์เมื่อช้ากว่า 0.05 ม./วิ
static func local_dir(vel: Vector3, face_yaw: float) -> Vector2:
	var v := Vector2(vel.x, vel.z)
	if v.length() < 0.05:
		return Vector2.ZERO
	var fwd := Vector2(sin(face_yaw), cos(face_yaw))
	var right := Vector2(-cos(face_yaw), sin(face_yaw))
	return Vector2(v.dot(right), v.dot(fwd)).normalized()


## H6: ตัวละครที่มี set_move_dir ได้ทิศด้วย (แทน set_move) ไม่มีก็ได้ set_move แบบเดิม
static func move_figure(fig: Object, has_dir: bool, dir: Vector2, spd: float, run: bool) -> void:
	if fig == null:
		return
	if has_dir:
		fig.call("set_move_dir", dir, spd, run)
	elif fig.has_method("set_move"):
		fig.call("set_move", spd, run)


## เมาส์ถูกจับอยู่ (เล็งด้วยเมาส์แบบเกมยิง)
func mouse_captured() -> bool:
	return _captured


## ตัวเลขสำหรับเทสและ ArenaWorld.counts()
func counts() -> Dictionary:
	return {"mode": _mode, "weapon": weapons.current, "fx_additive": fx.additive, "fx_alive": fx.alive(),
		"figure_alpha": _alpha, "captured": _captured}


# ---- อินพุต ----

func _unhandled_input(event: InputEvent) -> void:
	if not _input_on or _paused:
		return
	for a in MOVE_ACTIONS:
		if InputMap.has_action(a) and event.is_action(a):
			set_physics_process(true)
			break
	if InputMap.has_action(DODGE_ACTION) and event.is_action_pressed(DODGE_ACTION) and not event.is_echo():
		if not is_visible_in_tree():
			return             # อารีน่าที่โหลดไว้แต่ซ่อน: ปล่อย Space ให้หน้าอื่น
		press(DODGE_ACTION, true)
		get_viewport().set_input_as_handled()
		return
	if _mode != &"shoot":
		return
	if event is InputEventMouse and (event as InputEvent).device == InputEvent.DEVICE_ID_EMULATION:
		return
	if event is InputEventMouseMotion:
		# เล็งด้วยเมาส์เฉพาะตอนจับเมาส์อยู่ (หลังเล่นต่อ เคอร์เซอร์ที่ยังว่างไม่หมุนกล้อง) · ใช้พิกเซลจอจริง
		# (screen_relative) ความไวจึงเท่ากันทุกขนาดหน้าต่าง; นิ้วบนจอใช้พิกัด canvas ผ่าน aim_drag
		if aim_active() and _captured:
			var rel := (event as InputEventMouseMotion).screen_relative
			rig.look(-rel.x * ArenaCamera.LOOK_SPEED, -rel.y * ArenaCamera.LOOK_SPEED)
			_on_look()
		return
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if _recapture and mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT:
			_recapture = false
			_capture()
			get_viewport().set_input_as_handled()
			return
		if mb.pressed and (mb.button_index == MOUSE_BUTTON_WHEEL_UP or mb.button_index == MOUSE_BUTTON_WHEEL_DOWN):
			press(&"weapon", true)
			get_viewport().set_input_as_handled()
			return
	if event.is_echo():
		return
	if InputMap.has_action(&"fire") and event.is_action(&"fire"):
		press(&"fire", event.is_pressed())
		get_viewport().set_input_as_handled()
	elif InputMap.has_action(&"melee") and event.is_action_pressed(&"melee"):
		press(&"melee", true)
		get_viewport().set_input_as_handled()
	elif InputMap.has_action(&"reload") and event.is_action_pressed(&"reload"):
		press(&"reload", true)
		get_viewport().set_input_as_handled()
	elif InputMap.has_action(&"weapon_1") and event.is_action_pressed(&"weapon_1"):
		press(&"weapon_1", true)
		get_viewport().set_input_as_handled()
	elif InputMap.has_action(&"weapon_2") and event.is_action_pressed(&"weapon_2"):
		press(&"weapon_2", true)
		get_viewport().set_input_as_handled()


func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT or what == NOTIFICATION_EXIT_TREE:
		_release_mouse()
		_fire_held = false     # ปล่อยเมาส์หายระหว่างสลับหน้าต่าง ไม่ยิงต่อเองหลังพุ่ง


# ---- ต่อเฟรม ----

func _physics_process(delta: float) -> void:
	if _paused:
		set_physics_process(false)
		return
	if _down > 0.0:
		_down -= delta
		if _down <= 0.0:
			_revive()
	if _invuln > 0.0:
		_invuln = maxf(_invuln - delta, 0.0)
	if _flash > 0.0:
		_flash = maxf(_flash - delta, 0.0)
		_call_fig("set_flash", [_flash / FLASH_TIME])
	_handle(weapons.tick(delta))
	var iv := input_vector()
	var want := Vector3.ZERO
	if iv.length_squared() > 0.0001:
		var m := rig.right_flat() * iv.x + rig.forward_flat() * iv.y
		var top := float(ArenaData.PLAYER["run"] if running() else ArenaData.PLAYER["walk"])
		want = m.limit_length(1.0) * top
	var cool := float(ArenaData.DODGE["cooldown"])
	if dodging():
		# พุ่ง: ระยะต่อเฟรมจากเส้นโค้งความเร็ว (ArenaCombat) ทิศคงที่ ชนแล้วไถลตามผนัง
		var t0 := _dodge_t
		_dodge_t += delta
		_vel = _dodge_dir * ((ArenaCombat.dodge_travel(_dodge_t) - ArenaCombat.dodge_travel(t0)) / maxf(delta, 0.0001))
		want = _vel
		if _dodge_t >= float(ArenaData.DODGE["time"]):
			_end_dodge()
	else:
		if _since_dodge < cool:
			_since_dodge += delta
			if _since_dodge >= cool:
				dodge_changed.emit(&"ready")
		_vel = _vel.lerp(want, 1.0 - exp(-float(ArenaData.PLAYER["accel"]) * delta))
	var moving := true
	if want == Vector3.ZERO and _vel.length() < STOP:
		_vel = Vector3.ZERO
		velocity = Vector3.ZERO
		moving = false
	else:
		velocity = _vel
		move_and_slide()
		_vel = Vector3(velocity.x, 0.0, velocity.z)
		global_position.y = 0.0
	move_figure(_figure, _fig_dir, ArenaCombat.leg_dir(local_dir(_vel, face), _strafe), speed(), running())
	if moving:
		rig.follow(global_position)
		moved.emit(global_position)
		_aim_dirty = _aim_dirty or _mode == &"shoot"
	if _aim_dirty:
		_aim_dirty = false
		_update_aim_target()
	if not moving and not weapons.busy() and _down <= 0.0 and _invuln <= 0.0 and _flash <= 0.0 and not dodging() \
			and _since_dodge >= cool:
		set_physics_process(false)


# ---- ภายใน ----

func _handle(events: Array[Dictionary]) -> void:
	for e in events:
		var id: StringName = e["id"]
		match e["type"]:
			&"shot":
				_fire_gun()
			&"reload_start":
				_call_fig("play", [&"reload", 1.0])
				ArenaSound.play(self, "reload", global_position + CHEST)
				reload_changed.emit(true, weapons.reload_left())
			&"reload_done":
				reload_changed.emit(false, 0.0)
				ammo_changed.emit(weapons.in_mag, weapons.mag_size)
			&"reload_cancel":
				_call_fig("play", [&"idle", 1.0])
				reload_changed.emit(false, 0.0)
			&"melee_start":
				_call_fig("play", [&"punch" if id == &"punch" else &"swing", 1.0])
				ArenaSound.play(self, "punch" if id == &"punch" else "saw_rev", global_position + CHEST)
			&"melee_hit":
				_melee_hit(id)
			&"weapon":
				_saw_sound(id == &"sword")
				_call_fig("set_weapon", [id])
				_call_fig("set_aim", [rig.pitch if id != &"none" else 0.0])
				weapon_changed.emit(id)
				ammo_changed.emit(weapons.in_mag, weapons.mag_size)


func _fire_gun() -> void:
	var w: Dictionary = ArenaCombat.weapon("gun")
	var aim := aim_ray()
	var from := _muzzle_point()
	var point: Vector3 = aim["point"]
	var dir := (point - from)
	if dir.length_squared() < 0.0001:
		dir = rig.aim_dir()
	dir = dir.normalized()
	var reach := minf(from.distance_to(point) + 0.1, float(w["range"]))
	# รังสีเล็งยิงอยู่แล้ว: อัปเดตเป้าแดงฟรี (ศัตรูเดินเข้าเป้าตอนยืนยิงนิ่ง ๆ)
	var at := _target_of(aim["collider"])
	_set_aim_beast(not at.is_empty() and StringName(str(at.get("id", ""))) == &"beast")
	var r := _ray(from, from + dir * reach)
	var to: Vector3 = r.get("position", from + dir * minf(from.distance_to(point), float(w["range"])))
	fx.shot(from, to, not r.is_empty(), r.get("normal", -dir))
	ArenaSound.play(self, "gun", from)
	rig.shake(ArenaCamera.KICK_M, ArenaCamera.KICK_TIME)
	_call_fig("play", [&"fire", 1.0])
	ammo_changed.emit(weapons.in_mag, weapons.mag_size)
	if r.is_empty():
		return
	var t := _target_of(r.get("collider"))
	if t.is_empty():
		return
	var hit := {"amount": int(w["damage"]), "kind": &"gun", "point": to, "dir": dir, "from": from,
		"knockback": float(w["knockback"]), "stagger": bool(w["stagger"])}
	var res: Variant = (t["node"] as Object).call("take_hit", hit)
	_landed(res, to, t, &"gun")


func _melee_hit(id: StringName) -> void:
	if world == null or not world.has_method("melee_targets"):
		return
	var w: Dictionary = ArenaCombat.weapon(String(id))
	var origin := Vector2(global_position.x, global_position.z)
	var targets: Array = world.call("melee_targets")
	for t in ArenaWeapons.melee_targets_hit(String(id), origin, face, targets):
		var tp: Vector2 = t["pos"]
		var d2 := tp - origin
		var dir := Vector3(d2.x, 0.0, d2.y)
		dir = dir.normalized() if dir.length_squared() > 0.0001 else -Vector3(sin(face + PI), 0.0, cos(face + PI))
		var point := Vector3(tp.x, 1.2, tp.y) - dir * float(t["r"])
		var hit := {"amount": int(w["damage"]), "kind": id, "point": point, "dir": dir, "from": global_position,
			"knockback": float(w["knockback"]), "stagger": bool(w["stagger"])}
		var node: Object = t.get("node")
		if node == null or not node.has_method("take_hit"):
			continue
		var res: Variant = node.call("take_hit", hit)
		fx.impact(point, -dir)
		ArenaSound.play(self, "punch_hit" if id == &"punch" else "saw_hit", point)
		rig.shake()
		_landed(res, point, t, id)


func _landed(res: Variant, point: Vector3, t: Dictionary, kind: StringName) -> void:
	var r: Dictionary = res if res is Dictionary else {}
	hit_landed.emit({"point": point, "amount": int(r.get("applied", 0)), "target": StringName(str(t.get("id", ""))),
		"kind": kind, "killed": bool(r.get("killed", false))})


## {"node", "id"} ของสิ่งที่ collider เป็นส่วนหนึ่ง (โลกบอก) หรือ {}
func _target_of(collider: Variant) -> Dictionary:
	if collider == null or world == null or not world.has_method("hit_target"):
		return {}
	var t: Variant = world.call("hit_target", collider)
	if not t is Dictionary or (t as Dictionary).is_empty() or (t as Dictionary).get("node") == null:
		return {}
	return t


## จุดเริ่มกระสุน: ปากกระบอก (ถ้าปากกระบอกจมในผนัง/เสา เริ่มจากอกแทน ไม่ยิงทะลุของ)
func _muzzle_point() -> Vector3:
	var chest := global_position + CHEST
	var m: Node3D = _figure.call("muzzle") if _figure != null and _figure.has_method("muzzle") else null
	if m == null or not m.is_inside_tree():
		return chest
	var p := m.global_position
	if not _ray(chest, p).is_empty():
		return chest
	return p


func _ray(a: Vector3, b: Vector3) -> Dictionary:
	if not is_inside_tree():
		return {}
	var space := get_world_3d().direct_space_state
	if space == null:
		return {}
	var q := PhysicsRayQueryParameters3D.create(a, b, SHOT_MASK, [get_rid()])
	q.collide_with_areas = true
	q.collide_with_bodies = true
	return space.intersect_ray(q)


func _update_aim_target() -> void:
	if _mode != &"shoot":
		_set_aim_beast(false)
		return
	var t := _target_of(aim_ray().get("collider"))
	_set_aim_beast(not t.is_empty() and StringName(str(t.get("id", ""))) == &"beast")


func _set_aim_beast(on: bool) -> void:
	if on == _aim_beast:
		return
	_aim_beast = on
	aim_changed.emit(on)


## เล็งเปลี่ยน: ตัวหันตามกล้อง ปืนก้มเงยตาม จุดหมุนกล้องเยื้องขวาตาม yaw ใหม่
func _on_look() -> void:
	_face_camera()
	rig.follow(global_position)
	_aim_dirty = true
	set_physics_process(true)


func _face_camera() -> void:
	face = rig.yaw + PI
	rotation.y = face
	_call_fig("set_aim", [rig.pitch])


## กล้องหมุน (ลากจอ/เมาส์ทั้งสองโหมด): ตัวหันตาม (ไม่แตะท่าเล็ง) · ตามนุ่มที่ yaw ไม่เปลี่ยนจบที่การเทียบค่าเดียว
func _on_turned() -> void:
	var f := rig.yaw + PI
	if f != face:
		face = f
		rotation.y = f


func _end_dodge() -> void:
	_dodge_t = -1.0
	_since_dodge = 0.0
	dodge_changed.emit(&"cool")
	if _fire_held and _mode == &"shoot" and is_alive() and _input_on and not _paused:
		_handle(weapons.set_trigger(true))


## เสียงดาบเลื่อยเดินเบาตอนถืออยู่ (หยุดเมื่อเก็บ หยุดเกม หรือซ่อนหน้า)
func _saw_sound(on: bool) -> void:
	if on and _saw_loop == 0 and not _paused and is_visible_in_tree():
		_saw_loop = ArenaSound.loop(self, "saw_idle")
	elif not on and _saw_loop != 0:
		ArenaSound.stop(self, _saw_loop)
		_saw_loop = 0


func _go_down() -> void:
	if dodging():
		_end_dodge()
	_down = float(ArenaData.PLAYER["down_time"])
	_handle(weapons.set_trigger(false))
	stick = Vector2.ZERO
	_vel = Vector3.ZERO
	_call_fig("play", [&"die", 1.0])
	downed.emit()


func _revive() -> void:
	_down = 0.0
	_hp = _hp_max
	_handle(weapons.refill())
	_call_fig("play", [&"idle", 1.0])
	place(_respawn(), PI, 0.0)
	hp_changed.emit(_hp, _hp_max)
	ammo_changed.emit(weapons.in_mag, weapons.mag_size)
	revived.emit()


func _respawn() -> Vector3:
	if ResourceLoader.exists(ARENA_LAYOUT):
		var s := load(ARENA_LAYOUT) as Script
		if s != null:
			var c: Dictionary = s.get_script_constant_map()
			if c.has("RESPAWN"):
				return c["RESPAWN"]
	return RESPAWN_FALLBACK


func _capture() -> void:
	if touch or _paused or _mode != &"shoot" or not is_inside_tree() or not is_visible_in_tree():
		return
	_captured = true
	_recapture = false
	if DisplayServer.get_name() != "headless":
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _release_mouse() -> void:
	if not _captured:
		return
	_captured = false
	if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


## แขนกล้องถูกบีบสั้นกว่า 1.2 ม.: ไข่จางลง (ถึง 0.35 ที่ 0.6 ม.) ถ้าตัวละครทำได้
func _on_arm(length: float) -> void:
	var a := clampf(FADE_MIN + (1.0 - FADE_MIN) * (length - FADE_NEAR) / (FADE_FAR - FADE_NEAR), FADE_MIN, 1.0)
	if absf(a - _alpha) < 0.04 and not (a == 1.0 and _alpha != 1.0):
		return
	_alpha = a
	_call_fig("set_fade", [a])


func figure_alpha() -> float:
	return _alpha


func _call_fig(method: StringName, args: Array) -> Variant:
	if _figure == null or not _figure.has_method(method):
		return null
	return _figure.callv(method, args)


func _strength(a: StringName) -> float:
	return Input.get_action_strength(a) if InputMap.has_action(a) else 0.0
