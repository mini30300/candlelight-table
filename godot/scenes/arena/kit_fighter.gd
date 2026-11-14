class_name KitFighter
extends KitWalker
## ตัวผู้เล่นในอารีน่าจากชุดโมเดลเดิมของโต๊ะรบ (ARENA_SPEC §9.6): ตัวที่เลือกในห้องแต่งตัว (Figures kind kit)
## สัญญาตัวละคร §9.1 บน KitWalker (ท่า idle/walk/run ของ humanoid.res, ชุดสี H10 ผ่านตารางทาสี) · อาวุธอยู่ในเมชของชุดเอง
## ท่าเล็ง: ท่อนบน (อก คอ หัว แขน) ใช้ท่ายิงของอาวุธตัวเอง (fire / fire_heavy / ปืนพก) หยุดที่จังหวะนัดแรก ทับท่าขา
## ยิง = สะบัดสั้น ๆ ในท่าเดียวกัน (ไม่เล่นท่ายิงทั้งท่า ขายังเดินต่อ) · ต่อย = bash · ดาบ = ท่าฟันของชุด · ถอยหลัง = walk เล่นกลับ
## ไม่เดินเยื้อง (H9 false: A/D หมุนตัว) · พุ่งหลบ (H8) = เอนตัวย่อลงด้วย Tween เฉพาะตอนพุ่ง
## ระดับ min/lo: ยืนนิ่งท่าเดียวเหมือน KitWalker (ท่าเล็งวางครั้งเดียวตอนเปลี่ยน ไม่มีงานต่อเฟรม ไม่สะบัดตอนยิง)

## ท่ายิงตามชุด (ไม่มีในตาราง: ชุดถือปืน = fire, ชุดไม่มีปืน = ปืนพกมือขวา)
const FIRE_CLIP := {"cxw": "fire_heavy"}
## ท่าฟันของชุด (ไม่มีในตาราง = swing_0..2)
const SWORD_CLIPS := {"samurai": ["swing2_0", "swing2_1", "swing2_2"], "jackal": ["thrust_0", "thrust_1", "thrust_2"],
	"spartan": ["thrust_0", "thrust_1", "thrust_2"], "infantry": ["thrust_0", "thrust_1", "thrust_2"],
	"warrior": ["claw_0", "claw_1", "claw_2"], "rwar": ["claw_0", "claw_1", "claw_2"], "dabsong": ["twin"],
	"tafw": ["bash_0", "bash_1", "bash_2"]}
const PUNCH_CLIPS: Array = ["bash_0", "bash_1", "bash_2"]
const DIE_CLIPS: Array = ["die_back", "die_fwd", "die_spin"]
## กระดูกท่อนบนที่ท่าเล็งวางทับ
const AIM_BONES: PackedStringArray = ["chest", "neck", "head", "shoulderL", "elbowL", "wristL", "handL", "shoulderR",
	"elbowR", "wristR", "handR"]
const AIM_PITCH_K := 0.8         # ส่วนของมุมก้มเงยที่อกรับ
const MELEE_RATE := 1.8          # ท่าฟัน/ต่อยเร็วขึ้นให้จังหวะโดนใกล้ active ของอาวุธ
const RECOIL_T := 0.16
const RECOIL_SPAN := 0.08        # สะบัดไปข้างหน้าในท่ายิงกี่วิ
const MUZZLE_RIFLE := 0.35
const MUZZLE_PISTOL := 0.18
const DODGE_LEAN := 0.35
const DODGE_DIP := 0.18

var _weapon: StringName = &"none"
var _pitch := 0.0
var _fire_name := "fire"
var _fire_anim: Animation
var _aim_t := 0.28
var _aim_tracks: Dictionary = {}     # bone → track ของท่ายิง
var _recoil := -1.0
var _back := false
var _muzzle: Marker3D
var _rest := Transform3D.IDENTITY
var _tw: Tween
var _last_dodge := Vector2.ZERO


func setup(opts: Dictionary) -> void:
	super.setup(opts)
	if _kit == "" or _kit == "egg" or _sk == null:
		return
	_rest = _model.transform
	var e: Dictionary = _manifest().get(_kit, {})
	_fire_name = str(FIRE_CLIP.get(_kit, "fire" if str(e.get("hold", "")) == "gun" else "fire_pistol_r"))
	_clips = {"idle": ["idle"], "walk": ["walk"], "run": ["run"], "punch": PUNCH_CLIPS,
		"swing": SWORD_CLIPS.get(_kit, ["swing_0", "swing_1", "swing_2"]), "hit": ["flinch"], "hit_heavy": ["flinch_heavy"],
		"die": DIE_CLIPS, "fire": [_fire_name]}
	var clip := "%s/%s" % [_lib_name, _fire_name]
	_fire_anim = _ap.get_animation(clip) if _ap.has_animation(clip) else null
	_aim_tracks.clear()
	if _fire_anim != null:
		var ev: Array = _fire_anim.get_meta("events", [])
		_aim_t = maxf(float(ev[0].get("t", 0.28)) - 0.02, 0.0) if not ev.is_empty() else _fire_anim.length * 0.3
		for b in AIM_BONES:
			var bi := _sk.find_bone(b)
			var tr := _fire_anim.find_track(NodePath("Skeleton3D:" + b), Animation.TYPE_ROTATION_3D)
			if bi >= 0 and tr >= 0:
				_aim_tracks[bi] = tr


func metrics() -> Dictionary:
	return {"height": _height, "radius": float(ArenaData.PLAYER["radius"]), "eye": _height * 0.88, "shoulder": _height * 0.78}


## H9: ไม่เดินเยื้อง (A/D หมุนตัว)
func uses_strafe() -> bool:
	return false


## ยิง = สะบัดในท่าเล็ง (ไม่เปลี่ยนท่าขา) · ต่อย/ฟันเร็วขึ้น MELEE_RATE · reload ไม่มีท่า
func play(logical: StringName, speed: float = 1.0) -> float:
	match logical:
		&"fire":
			if _fire_anim == null:
				return 0.0
			if not _paused_pose():
				_recoil = 0.0
			return RECOIL_T
		&"reload":
			return 0.0
		&"punch", &"swing":
			speed *= MELEE_RATE
	var d := super.play(logical, speed)
	_refresh_still()
	return d


## H6: ขาเดินหน้า (y ≥ −0.5) หรือถอยหลัง (walk เล่นกลับ ไม่วิ่งถอยหลัง)
func set_move_dir(local_dir: Vector2, speed: float, running: bool) -> void:
	_back = local_dir.y < -0.5 and speed >= 0.05
	set_move(speed, running and not _back)


func set_move(speed: float, running: bool) -> void:
	super.set_move(speed, running)
	if _ap != null and _back and _oneshot == &"" and _ap.is_playing():
		_ap.speed_scale = -absf(_ap.speed_scale)
		_loop_rate = -absf(_loop_rate)


func set_weapon(id: StringName) -> void:
	_weapon = id
	_refresh_still()


func set_aim(pitch: float) -> void:
	_pitch = pitch
	_refresh_still()


## H8: เอนไปทางที่พุ่ง ย่อลงแล้วตั้งตัวกลับใน duration วิ
func begin_dodge(local_dir: Vector2, duration: float) -> void:
	_last_dodge = local_dir
	if _model == null or not is_inside_tree():
		return
	if _tw != null and _tw.is_valid():
		_tw.kill()
	var lean := DODGE_LEAN * (-1.0 if local_dir.y < 0.0 else 1.0)
	_tw = create_tween()
	_tw.tween_method(_dodge_pose.bind(lean), 0.0, 1.0, duration * 0.3).set_ease(Tween.EASE_OUT)
	_tw.tween_method(_dodge_pose.bind(lean), 1.0, 0.0, duration * 0.7).set_ease(Tween.EASE_IN_OUT)


func dodging() -> bool:
	return _tw != null and _tw.is_valid() and _tw.is_running()


func last_dodge() -> Vector2:
	return _last_dodge


## จุดปากกระบอก: มือที่อยู่หน้าสุด + ระยะลำกล้องไปทางหน้าตัว (วางตอนถาม ไม่มีงานต่อเฟรม)
func muzzle() -> Node3D:
	if _sk == null:
		return null
	if _muzzle == null:
		_muzzle = Marker3D.new()
		_muzzle.name = "Muzzle"
		add_child(_muzzle)
	var hr := anchor(&"hand_r")
	var hl := anchor(&"hand_l")
	if hr == null or not hr.is_inside_tree():
		_muzzle.position = Vector3(0.0, _height * 0.62, 0.5)
		return _muzzle
	var fwd := global_basis.z.normalized()
	var h := hr
	var off := MUZZLE_PISTOL
	if _fire_name != "fire_pistol_r":
		off = MUZZLE_RIFLE
		if hl != null and hl.is_inside_tree() and (hl.global_position - hr.global_position).dot(fwd) > 0.0:
			h = hl
	_muzzle.global_position = h.global_position + fwd * off
	return _muzzle


func weapon_clip() -> String:
	return _fire_name


func aiming() -> bool:
	return _aim_on()


func moving_back() -> bool:
	return _back and _ap != null and _ap.speed_scale < 0.0


# ---- ภายใน ----

func _aim_on() -> bool:
	return _weapon == &"gun" and _fire_anim != null and not _dead and _oneshot == &"" and not _aim_tracks.is_empty()


## ยืนนิ่ง (min/lo) แล้วท่าเล็งเปลี่ยน: วางท่าใหม่ครั้งเดียว (seek ลงกระดูก → _on_applied)
func _refresh_still() -> void:
	if _paused_pose():
		_ap.seek(0.0, true)


## ท่าหยุดนิ่งอยู่ (AnimationPlayer ไม่เล่น: min/lo ตอนยืน)
func _paused_pose() -> bool:
	return _still and _ap != null and not _ap.is_playing()


## ท่าเล็งทับหลังท่าลงกระดูก (แทนท่าโพสของชุดตอนเล็ง: ใช้ hold แบบของท่ายิง) · ไม่เล็ง = แบบ KitBeast
func _on_applied() -> void:
	if not _aim_on():
		super._on_applied()
		return
	var dt := _dt if _manual else get_process_delta_time()
	_dt = 0.0
	var t := _aim_t
	if _recoil >= 0.0:
		_recoil += dt
		if _recoil >= RECOIL_T:
			_recoil = -1.0
		else:
			t += RECOIL_SPAN * sin(PI * _recoil / RECOIL_T)
	for bi: int in _aim_tracks:
		_sk.set_bone_pose_rotation(bi, _fire_anim.rotation_track_interpolate(_aim_tracks[bi], t))
	if not _hold.is_empty():
		# ท่านิ่ง (min/lo) วางครั้งเดียว: น้ำหนัก hold ไปถึงเป้าทันที
		_apply_holds(_fire_anim, HOLD_EASE if _paused_pose() else dt)
	_pitch_chest()
	if _still_wait >= 0.0:
		_still_wait -= dt
		if _still_wait < 0.0 and level == "min" and _oneshot == &"" and _loop == &"idle" and not _dead:
			_go_still.call_deferred()


## ก้มเงยที่อก: หมุนรอบแกนซ้าย-ขวาของตัว (+X ของชุด) ในพื้นที่โมเดล
func _pitch_chest() -> void:
	var c := _sk.find_bone("chest")
	if c < 0 or absf(_pitch) < 0.001:
		return
	var par := _sk.get_bone_parent(c)
	var pq := _sk.get_bone_global_pose(par).basis.get_rotation_quaternion() if par >= 0 else Quaternion.IDENTITY
	var r := Quaternion(Vector3.RIGHT, -_pitch * AIM_PITCH_K)
	var q := pq.inverse() * r * pq * _sk.get_bone_pose_rotation(c)
	_sk.set_bone_pose_rotation(c, q.normalized())


func _dodge_pose(f: float, lean: float) -> void:
	if _model == null:
		return
	var tf := Transform3D(Basis(Vector3.RIGHT, lean * f), Vector3(0.0, -DODGE_DIP * f, 0.0))
	_model.transform = tf * _rest
