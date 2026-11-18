class_name SoldierFigure
extends Node3D
## ทหารราบ (ทดลอง): ร่างคนตามกายวิภาค (โครง → กล้าม → ผิว) จากเครื่องมือ tools/soldier · ยังไม่มีชุดและปืน
## ตัวในห้องแต่งตัว (Figures kind builtin): เดินบนดาดฟ้า เป็นตัวผู้เล่นในห้องทดลองและภารกิจ และในการ์ด "ธรรมดา"
## สัญญาตัวละคร (ARENA_SPEC §9.1): 12 เมธอด + clip_event · ดาดฟ้า (PACK_SPEC §3) + deck_speeds · H6 H8 H9 แบบ KitFighter
## ไฟล์ทั้งหมดใน assets/figures/soldier/ (tools/soldier/import_stage.sh นำเข้า) · ท่า: clips.res ของทหารถ้ามี
## ไม่งั้นสำเนาท่าใน humanoid.res ที่แต่งข้อมือแล้ว (ผิวต่อเนื่องบิดเกือบรอบไม่ได้) · โครง 23 กระดูกของเกม + กระดูกช่วย
## ตัวขับกระดูกช่วย/ท่าแก้ทำงานใน mixer_applied (ไม่มี _process): hi/mid = กระดูกช่วย + ท่าแก้ · lo = กระดูกช่วย ·
## min = ไม่มีงานเพิ่ม ยืนนิ่งท่าเดียว · ดาดฟ้ายืนนิ่งทั้ง lo และ min · เมช วัสดุ ท่า เก็บ static ใช้ร่วมทุกตัว · ภาพล้วน
## บาดแผล (add_wound, โดน/ตายลงแผลสุ่มแบบมี seed ≤ 8 แผล ติดกระดูก): hi/mid = ผิวขาดเห็นเนื้อและกระดูก (inner_*.res
## ซ่อนจนแผลแรก) · lo = สีแผลบนผิว · min = ไม่มีเลย · อัปเดตตามท่าเฉพาะตอนมีแผล ล้างตอน setup / ลุกขึ้นใหม่

signal clip_event(kind: StringName)

const DIR := "res://assets/figures/soldier/"
const RIG := DIR + "rig.tscn"
const SKIN := DIR + "skin.res"
const MATERIAL := DIR + "body_material.tres"
const OWN_CLIPS := DIR + "clips.res"
const LIB_PATH := "res://assets/anim/humanoid.res"
const LEVELS: PackedStringArray = ["hi", "mid", "lo", "min"]
## งบสามเหลี่ยมของผิวต่อระดับ (1 พื้นผิว 1 draw) · crowd = ระดับฝูง (ถ้าขั้นปั้นทำมา ยังไม่มีที่ใช้)
const BUDGET := {"hi": 24000, "mid": 16000, "lo": 9000, "min": 5000, "crowd": 1500}
## โครง 23 กระดูกของเกม (assets/kits/CONTRACT.md §1) ที่ท่าใน humanoid.res ขับ
const GAME_BONES: PackedStringArray = ["pelvis", "spine", "chest", "neck", "head", "shoulderL", "elbowL", "wristL", "handL",
	"shoulderR", "elbowR", "wristR", "handR", "hipL", "kneeL", "ankleL", "toeL", "heelL", "hipR", "kneeR", "ankleR", "toeR", "heelR"]
const PLAYER_CLIPS := {"idle": ["idle"], "walk": ["walk"], "run": ["run"], "fire": ["fire"],
	"punch": ["bash_0", "bash_1", "bash_2"], "swing": ["thrust_0", "thrust_1", "thrust_2"], "hit": ["flinch"],
	"hit_heavy": ["flinch_heavy"], "die": ["die_back", "die_fwd", "die_spin"]}
const ENEMY_CLIPS := {"idle": ["idle"], "walk": ["walk"], "run": ["run"], "attack": ["bash_0", "bash_1", "bash_2"],
	"hit": ["flinch"], "hit_heavy": ["flinch_heavy"], "die": ["die_back", "die_fwd", "die_spin"]}
const LOOPS: Array[StringName] = [&"idle", &"walk", &"run"]
const BONES := {&"head": "head", &"chest": "chest", &"hand_r": "handR", &"hand_l": "handL"}
const BLEND := 0.15
const BLEND_DIE := 0.3
const DECK_RATE := 1.4           # ความเร็วบนดาดฟ้า = ความเร็วของท่า × S × ค่านี้ (แบบ KitWalker)
const RADIUS := 0.35
## ข้อมือ: การรวมมือ+ข้อมือหมุนได้ไม่เกิน (องศา) บิดรอบแกนแขน / พับ
const WRIST_TWIST := 45.0
const WRIST_SWING := 45.0
## ท่าเล็ง (แบบ KitFighter): ท่อนบนจากท่า fire ที่นัดแรก + อกก้มเงยตามกล้อง · ยิง = สะบัด 0.16 วิ
const AIM_BONES: PackedStringArray = ["chest", "neck", "head", "shoulderL", "elbowL", "wristL", "handL", "shoulderR",
	"elbowR", "wristR", "handR"]
const AIM_PITCH_K := 0.8
const MELEE_RATE := 1.8
const RECOIL_T := 0.16
const RECOIL_SPAN := 0.08
const MUZZLE_AHEAD := 0.35
const DODGE_LEAN := 0.35
const DODGE_DIP := 0.18
const FLASH_COLOUR := Color(1.0, 1.0, 1.0)
const TINT_COLOUR := Color(0.9, 0.08, 0.06)
## ตัวขับ (ค่าของขั้น 1 ใช้เมื่อ rig.tscn ไม่มี meta "soldier_rig" จาก rig.json ของขั้นปั้น)
const DRIVERS := {"clav_elev_k": 0.12, "clav_elev_max": 15.0, "clav_prot_k": 0.12, "twist_k": 0.5}
const KEYS := {"elbow": 120.0, "knee": 120.0, "hip_flex": 100.0, "hip_ext": 25.0}
const BIND_ELBOW := 8.0
const ARM_KEYS := {"bind": [0.573576436, -0.819152044, 0.0], "down": [0.087155743, -0.996194698, 0.0],
	"front": [0.0, 0.0, 1.0], "up": [0.342020143, 0.939692621, 0.0]}
## ท่าแก้ที่ตัวขับรู้จัก (ชื่อ + L/R)
const SHAPE_KINDS: PackedStringArray = ["shoulder_down", "shoulder_front", "shoulder_up", "elbow_flex", "knee_flex",
	"hip_flex", "hip_ext"]
const SHAPE_ZERO := 0.05         # น้ำหนักต่ำกว่านี้ = 0 (ไม่เสียรอบวาดท่าแก้)
const DOWN := Vector3(0.0, -1.0, 0.0)
## บาดแผล: ชั้นในจาก tools/soldier (inner_layers.py) · แผลสูงสุด (เกินแล้วทับแผลเก่าสุด)
const INNER := {"flesh": DIR + "inner_flesh.res", "bone": DIR + "inner_bone.res"}
const MAX_WOUNDS := 8
## ที่ลงแผลสุ่ม: กระดูก → น้ำหนักการสุ่ม (ลำตัวมากกว่าแขนขา ไม่ลงหัว มือ เท้า)
const WOUND_BONES := {&"chest": 3.0, &"spine": 3.0, &"pelvis": 1.0, &"shoulderL": 1.2, &"shoulderR": 1.2, &"elbowL": 0.8,
	&"elbowR": 0.8, &"hipL": 1.4, &"hipR": 1.4, &"kneeL": 0.9, &"kneeR": 0.9}
const TRUNK_BONES: Array[StringName] = [&"chest", &"spine", &"pelvis"]
## รัศมีแผล (ม. ต่ำ-สูง): โดน / ตายที่ลำตัว / ตายที่แขนขา
const WOUND_HIT := Vector2(0.032, 0.045)
const WOUND_DIE := Vector2(0.06, 0.085)
const WOUND_DIE_LIMB := Vector2(0.045, 0.06)
const WOUND_DEPTH := 0.3         # ศูนย์กลางแผลอยู่ใต้ผิว (เท่าของรัศมี)
const WOUND_SPOT_W := 0.8        # จุดลงแผล: จุดผิวที่กระดูกนั้นถือน้ำหนักอย่างน้อยเท่านี้ (ไม่ลงตรงข้อพับ)

static var _rig: PackedScene
static var _skin: Skin
static var _mat: ShaderMaterial
static var _mat_pv: ShaderMaterial
static var _mesh_cache: Dictionary = {}
static var _lib: AnimationLibrary
static var _lib_from := ""
static var _baked: Dictionary = {}
static var _drv: Dictionary = {}
static var _rules: Array = []      # [ดัชนี, ชนิด, ต้นทาง, ต้นทาง 2, ข้าง ±1] ของกระดูกช่วยที่ต้องขับ
static var _rules_ready := false
static var _scale := 1.0
static var _inner_cache: Dictionary = {}
static var _spots: Dictionary = {}

var role: StringName = &"player"
var level := "mid"
var weapon: StringName = &"none"
## ตัวขับ (ทำภาพ/เทส): ปิดกระดูกช่วยหรือท่าแก้ได้
var helpers_on := true
var correctives_on := true
var _built := false
var _model: Node3D
var _sk: Skeleton3D
var _mi: MeshInstance3D
var _ap: AnimationPlayer
var _clips: Dictionary = PLAYER_CLIPS
var _loop: StringName = &"idle"
var _loop_rate := 1.0
var _oneshot: StringName = &""
var _variant_next := -1
var _dead := false
var _still := false
var _still_wait := -1.0
var _still_due := false
var _manual := false
var _dt := 0.0
var _ev_prev := 0.0
var _cur_anim: Animation
var _rng := RandomNumberGenerator.new()
var _anchors: Dictionary = {}
var _muzzle: Marker3D
var _overlay: StandardMaterial3D
var _flash := 0.0
var _tele := 0.0
var _height := 1.78
var _idx: Dictionary = {}
var _shape_slots: Array = []     # [ดัชนี blend shape, ชนิด, ข้าง 0/1]
var _own_mat: ShaderMaterial     # ไฟของฉากโชว์ (set_light): วัสดุของตัวนี้เอง
var _own_pp := false
var _pitch := 0.0
var _fire_anim: Animation
var _aim_t := 0.26
var _aim_tracks: Dictionary = {}
var _recoil := -1.0
var _back := false
var _rest := Transform3D.IDENTITY
var _tw: Tween
var _last_dodge := Vector2.ZERO
var _own_lit := false            # _own_mat มาจาก set_light (ไม่ใช่เพื่อแผลอย่างเดียว)
var _wounds: Array = []          # [ชื่อกระดูก, ดัชนีกระดูก, ศูนย์กลางในกรอบกระดูก, รัศมี] เก่า → ใหม่
var _wound_next := 0             # ช่องที่ทับเมื่อครบ MAX_WOUNDS (เก่าสุด)
var _wrng := RandomNumberGenerator.new()
var _inner: Array = []           # [เนื้อ, กระดูก] MeshInstance3D (สร้างตอนแผลแรกบน hi/mid)
var _inner_mats: Array = []      # วัสดุชั้นในของตัวนี้เอง (ค่าแผล)
var _wound_updates := 0          # ครั้งที่ส่งตำแหน่งแผลให้เชดเดอร์ (เทส)


# ================= สัญญาตัวละคร =================

## opts: {"role" &"player"|&"enemy"|&"deck"|อื่น ๆ = ผู้เล่น, "level", "team_colour" (ไม่ใช้: สีผิวของตัวเอง), "seed"}
## + "manual" (เดินท่าด้วย step() ของฉาก เช่นการ์ดฮีโร่)
func setup(opts: Dictionary) -> void:
	if bool(opts.get("manual", false)):
		_manual = true
	role = StringName(str(opts.get("role", "player")))
	_clips = ENEMY_CLIPS if role == &"enemy" else PLAYER_CLIPS
	_rng.seed = int(opts.get("seed", 1))
	_wrng.seed = int(opts.get("seed", 1)) * 7919 + 104729
	level = str(opts.get("level", level))
	if not LEVELS.has(level):
		level = "mid"
	_build()
	_wounds.clear()
	_wound_next = 0
	apply_level(level)
	play(&"idle")


func metrics() -> Dictionary:
	return {"height": _height, "radius": RADIUS, "eye": _height * 0.934, "shoulder": _height * 0.812}


func clip_names() -> Dictionary:
	var out := {}
	for k in _clips:
		out[k] = PackedStringArray(_clips[k])
	return out


## เริ่มท่า: ท่าวนเปลี่ยนท่าวน · ท่าครั้งเดียวเล่นจากต้นแล้วกลับท่าวน (die ค้าง) · ยิง = สะบัดในท่าเล็ง · คืนความยาว (วิ)
func play(logical: StringName, speed: float = 1.0) -> float:
	match logical:
		&"fire":
			if _fire_anim == null:
				return 0.0
			if not _paused():
				_recoil = 0.0
			return RECOIL_T
		&"reload":
			return 0.0
		&"punch", &"swing":
			speed *= MELEE_RATE
	if _ap == null:
		return 0.0
	var names: Array = _clips.get(String(logical), [])
	if names.is_empty():
		return 0.0
	var idx := 0
	if names.size() > 1:
		idx = posmod(_variant_next, names.size()) if _variant_next >= 0 else _rng.randi_range(0, names.size() - 1)
	_variant_next = -1
	var clip := "humanoid/" + str(names[idx])
	if not _ap.has_animation(clip):
		return 0.0
	var anim := _ap.get_animation(clip)
	speed = maxf(speed, 0.01)
	if logical in LOOPS and (_dead or _oneshot == &"die"):
		clear_wounds()           # ลุกขึ้นใหม่ด้วยตัวเดิม (เกิดใหม่): แผลหาย
	_still = false
	_still_wait = -1.0
	_dead = false
	if logical in LOOPS:
		_oneshot = &""
		_loop = logical
		_loop_rate = speed
		_start(clip, speed, false)
	else:
		_oneshot = logical
		_start(clip, speed, true)
	match logical:
		&"hit", &"hit_heavy":
			_random_wound(WOUND_HIT * (1.25 if logical == &"hit_heavy" else 1.0), WOUND_HIT)
		&"die":
			for i in 2 + (_wrng.randi_range(0, 1) if level != "min" else 0):
				_random_wound(WOUND_DIE, WOUND_DIE_LIMB)
	return anim.length / speed


## ความเร็ว (ม./วิ ตามทิศหน้า): idle / walk / run และอัตราเล่น = ความเร็ว / (ความเร็วของท่า × S) เท้าจึงไม่ไถล
## set_move ตรง ๆ = เดินหน้าเสมอ (PACK_SPEC H6: ทิศกลับเป็น (0, 1))
func set_move(speed: float, running: bool) -> void:
	_back = false
	_move(speed, running)


func _move(speed: float, running: bool) -> void:
	if _ap == null or _dead:
		return
	var logical: StringName = &"idle" if speed < 0.05 else (&"run" if running else &"walk")
	var rate := 1.0
	if logical != &"idle":
		var clip := "humanoid/" + str(_clips[String(logical)][0])
		if _ap.has_animation(clip):
			rate = speed / maxf(float(_ap.get_animation(clip).get_meta("speed", 1.0)) * _scale, 0.01)
	_loop_rate = rate
	if _oneshot != &"":
		_loop = logical
		return
	if logical != _loop or (not _ap.is_playing() and not _still):
		_loop = logical
		_start("humanoid/" + str(_clips[String(logical)][0]), rate, false)
	elif not _still:
		_ap.speed_scale = rate
	if _back and _ap.is_playing() and logical != &"idle":
		_ap.speed_scale = -absf(_ap.speed_scale)
		_loop_rate = -absf(_loop_rate)


func set_aim(pitch: float) -> void:
	_pitch = pitch
	_refresh_still()


func set_weapon(id: StringName) -> void:
	weapon = id
	_refresh_still()


func set_flash(a: float) -> void:
	_flash = clampf(a, 0.0, 1.0)
	_update_overlay()


## สีแดงตอนง้าง (hi/mid/lo; min ไม่มี)
func set_telegraph(a: float) -> void:
	_tele = clampf(a, 0.0, 1.0)
	_update_overlay()


## จุดปากกระบอก: มือที่อยู่หน้าสุด + MUZZLE_AHEAD ไปทางหน้าตัว (วางตอนถาม ไม่มีงานต่อเฟรม) · ศัตรูไม่มี
func muzzle() -> Node3D:
	if role == &"enemy" or _sk == null:
		return null
	if _muzzle == null:
		_muzzle = Marker3D.new()
		_muzzle.name = "Muzzle"
		add_child(_muzzle)
	var hr := anchor(&"hand_r")
	var hl := anchor(&"hand_l")
	if hr == null or not hr.is_inside_tree():
		_muzzle.position = Vector3(0.0, _height * 0.72, 0.5)
		return _muzzle
	var fwd := global_basis.z.normalized()
	var h := hr
	if hl != null and hl.is_inside_tree() and (hl.global_position - hr.global_position).dot(fwd) > 0.0:
		h = hl
	_muzzle.global_position = h.global_position + fwd * MUZZLE_AHEAD
	return _muzzle


func anchor(name: StringName) -> Node3D:
	if _anchors.has(name):
		return _anchors[name]
	if _sk == null or not BONES.has(name) or _sk.find_bone(BONES[name]) < 0:
		return null
	var ba := BoneAttachment3D.new()
	ba.name = "Anchor_" + String(name)
	ba.bone_name = BONES[name]
	_sk.add_child(ba)
	_anchors[name] = ba
	return ba


func apply_level(l: String) -> void:
	level = l if LEVELS.has(l) else "mid"
	if not _built:
		return
	_set_mesh(level)
	_show_wounds()
	_update_overlay()
	if level == "min":
		_reset_helpers()
	if _ap == null:
		return
	if _still_level():
		if _oneshot == &"" and _loop == &"idle" and not _dead:
			_go_still()
	elif _still:
		_still = false
		_start("humanoid/" + str(_clips["idle"][0]), 1.0, false)


# ================= ตะขอเสริม (ไม่อยู่ใน FIGURE_API) =================

## (เดิน, วิ่ง) ม./วิ บนดาดฟ้าที่ท่าไม่ไถล (HallAvatar ใช้แทน 3 / 6)
func deck_speeds() -> Vector2:
	var lib := clip_library()
	if lib == null or not lib.has_animation(&"walk") or not lib.has_animation(&"run"):
		return Vector2(HallAvatar.WALK, HallAvatar.RUN)
	_load_static()
	return Vector2(float(lib.get_animation(&"walk").get_meta("speed", 1.0)) * _scale * DECK_RATE,
		float(lib.get_animation(&"run").get_meta("speed", 2.0)) * _scale * DECK_RATE)


## H9: ไม่เดินเยื้อง (A/D หมุนตัว) เพราะไม่มีท่าก้าวข้าง
func uses_strafe() -> bool:
	return false


## H6: ขาเดินหน้า (y ≥ −0.5) หรือถอยหลัง (walk เล่นกลับ ไม่วิ่งถอยหลัง)
func set_move_dir(local_dir: Vector2, speed: float, running: bool) -> void:
	_back = local_dir.y < -0.5 and speed >= 0.05
	_move(speed, running and not _back)


## H8: เอนไปทางที่พุ่ง ย่อลงแล้วตั้งตัวกลับใน duration วิ (Tween มีเฉพาะตอนพุ่ง)
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


## ไฟของฉากโชว์ (HeroLight): วัสดุของตัวนี้เอง ไม่แตะวัสดุที่ใช้ร่วม · per_pixel = คิดแสงต่อพิกเซลทุกระดับ
func set_light(sun_dir: Vector3, sun: Color, ambient: Color, per_pixel := true) -> void:
	_load_static()
	if _own_mat == null:
		_own_mat = _mat.duplicate() as ShaderMaterial
	_own_mat.set_shader_parameter("sun_dir", sun_dir)
	_own_mat.set_shader_parameter("sun_colour", Vector3(sun.r, sun.g, sun.b))
	_own_mat.set_shader_parameter("ambient_colour", Vector3(ambient.r, ambient.g, ambient.b))
	_own_pp = per_pixel
	_own_lit = true
	_sync_inner_light()
	if _built:
		_mi.material_override = _material_for(level)


## เทส/เครื่องมือ: เดินท่าเองด้วย step() แทนทุกเฟรม
func set_manual(on: bool) -> void:
	_manual = on
	if _ap != null:
		_ap.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL if on \
			else AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_IDLE


func step(dt: float) -> void:
	if _ap != null and _manual:
		_dt = dt
		_ap.advance(dt)
		if _still_due:
			_still_due = false
			_go_still()


## ท่าถัดไปที่มีหลายแบบใช้แบบนี้ (ไม่อยู่ในสัญญา)
func set_variant(i: int) -> void:
	_variant_next = i


func skeleton() -> Skeleton3D:
	return _sk


func body() -> MeshInstance3D:
	return _mi


func animation_player() -> AnimationPlayer:
	return _ap


func is_still() -> bool:
	return _still


func playing_clip() -> String:
	return String(_ap.current_animation) if _ap != null else ""


func weapon_clip() -> String:
	return "fire" if _fire_anim != null else ""


func aiming() -> bool:
	return _aim_on()


func moving_back() -> bool:
	return _back and _ap != null and _ap.speed_scale < 0.0


func dodging() -> bool:
	return _tw != null and _tw.is_valid() and _tw.is_running()


func last_dodge() -> Vector2:
	return _last_dodge


## ชื่อท่าแก้ของเมชระดับนี้ที่ตัวขับรู้จัก / ไม่รู้จัก (เทสตรวจหลังนำเข้าขั้นปั้นใหม่)
func shape_names() -> PackedStringArray:
	var out := PackedStringArray()
	if _mi != null and _mi.mesh != null:
		for i in _mi.mesh.get_blend_shape_count():
			out.append(String(_mi.mesh.get_blend_shape_name(i)))
	return out


func active_shapes() -> int:
	var n := 0
	if _mi != null and _mi.mesh != null:
		for i in _mi.mesh.get_blend_shape_count():
			if _mi.get_blend_shape_value(i) > 0.0:
				n += 1
	return n


# ================= บาดแผล (ภาพล้วน ไม่เกี่ยวกับกติกา) =================

## แผลที่กระดูก bone (ชื่อกระดูกในโครง) ศูนย์กลาง local_offset ในกรอบกระดูก รัศมี radius ม. · คืน true = ลงแผลแล้ว
## ติดกระดูก (ตามท่าทุกเฟรมตอนมีแผล) · ครบ MAX_WOUNDS แล้วทับแผลเก่าสุด · min ไม่มีแผลเลย (ไม่เก็บ ไม่มีงานต่อเฟรม)
func add_wound(bone: StringName, local_offset: Vector3, radius: float) -> bool:
	if not _built or level == "min" or radius <= 0.0:
		return false
	var bi := int(_idx.get(String(bone), -1))
	if bi < 0:
		return false
	var w := [bone, bi, local_offset, radius]
	if _wounds.size() < MAX_WOUNDS:
		_wounds.append(w)
	else:
		_wounds[_wound_next] = w
		_wound_next = (_wound_next + 1) % MAX_WOUNDS
	_show_wounds()
	return true


func clear_wounds() -> void:
	_wounds.clear()
	_wound_next = 0
	_show_wounds()


func wound_count() -> int:
	return _wounds.size()


## แผลทั้งหมด [{bone, offset, radius}] (เทส: seed เดิมได้ตำแหน่งเดิม)
func wounds() -> Array:
	var out := []
	for w: Array in _wounds:
		out.append({"bone": w[0], "offset": w[2], "radius": w[3]})
	return out


## ศูนย์กลางแผล i ในพิกัดโลกตามท่าปัจจุบัน
func wound_point(i: int) -> Vector3:
	if i < 0 or i >= _wounds.size() or _sk == null:
		return Vector3.ZERO
	var w: Array = _wounds[i]
	return _sk.global_transform * (_sk.get_bone_global_pose(int(w[1])) * (w[2] as Vector3))


## ชั้นในที่สร้างแล้ว [เนื้อ, กระดูก] (ว่าง = ยังไม่เคยมีแผลบน hi/mid)
func inner_layers() -> Array:
	return _inner.duplicate()


func wound_updates() -> int:
	return _wound_updates


## จุดผิวที่ลงแผลได้ของกระดูก bone ที่หันไปทาง dir (กรอบโครงตอนผูก) มากสุด: [ศูนย์กลางในกรอบกระดูก, นอร์มอล] (เทส/ภาพ)
static func wound_spot(bone: StringName, dir: Vector3) -> Array:
	var list: Array = wound_spots().get(bone, [])
	var best := []
	var score := -INF
	var bp := _skin.get_bind_pose(_bind_index(bone)) if _skin != null else Transform3D.IDENTITY
	for s: Array in list:
		var d := (bp.basis.inverse() * (s[1] as Vector3)).dot(dir.normalized())
		if d > score:
			score = d
			best = s
	return best


# ================= ข้อมูลร่วม (static) =================

## ผิวของระดับ l (hi/mid/lo/min หรือ crowd) · null = ไม่มีไฟล์
static func body_mesh(l: String) -> ArrayMesh:
	if not _mesh_cache.has(l):
		var p := DIR + "body_%s.res" % l
		_mesh_cache[l] = load(p) as ArrayMesh if ResourceLoader.exists(p) else null
	return _mesh_cache[l]


## ชั้นในของแผล "flesh" / "bone" (โหลดตอนแผลแรกบน hi/mid) · null = ไม่มีไฟล์
static func inner_mesh(l: String) -> ArrayMesh:
	if not _inner_cache.has(l):
		var p: String = INNER.get(l, "")
		_inner_cache[l] = load(p) as ArrayMesh if p != "" and ResourceLoader.exists(p) else null
	return _inner_cache[l]


## จุดลงแผลต่อกระดูกใน WOUND_BONES: จุดยอดของ body_min ที่กระดูกนั้นถือน้ำหนัก ≥ WOUND_SPOT_W
## {กระดูก: [[จุดในกรอบกระดูก, นอร์มอลในกรอบกระดูก], ...]} ตามลำดับจุดยอด (กำหนดแน่นอน) · คิดครั้งเดียว
static func wound_spots() -> Dictionary:
	if not _spots.is_empty():
		return _spots
	_load_static()
	var m := body_mesh("min")
	if m == null or _skin == null:
		return _spots
	var arr := m.surface_get_arrays(0)
	var pos: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
	var nrm: PackedVector3Array = arr[Mesh.ARRAY_NORMAL]
	var bones: PackedInt32Array = arr[Mesh.ARRAY_BONES]
	var wts: PackedFloat32Array = arr[Mesh.ARRAY_WEIGHTS]
	var per := bones.size() / maxi(pos.size(), 1)
	for v in pos.size():
		var top := -1
		var tw := -1.0
		for k in per:
			if wts[v * per + k] > tw:
				tw = wts[v * per + k]
				top = bones[v * per + k]
		if tw < WOUND_SPOT_W or top < 0 or top >= _skin.get_bind_count():
			continue
		var name := StringName(_skin.get_bind_name(top))
		if not WOUND_BONES.has(name):
			continue
		var bp := _skin.get_bind_pose(top)
		if not _spots.has(name):
			_spots[name] = []
		_spots[name].append([bp * pos[v], (bp.basis * nrm[v]).normalized()])
	return _spots


static func _bind_index(bone: StringName) -> int:
	if _skin != null:
		for i in _skin.get_bind_count():
			if _skin.get_bind_name(i) == bone:
				return i
	return -1


## ท่าของทหาร (ใช้ร่วมทุกตัว): clips.res ของขั้นปั้นถ้ามี ไม่งั้นสำเนาท่าที่ใช้จาก humanoid.res แต่งข้อมือ (ease_wrists)
## humanoid.res เองไม่ถูกแตะ (ชุดโมเดลอื่นใช้ร่วม) · ไม่มีทั้งสองไฟล์ = null (ยืนท่าพักของโครง)
static func clip_library() -> AnimationLibrary:
	if _lib != null:
		return _lib
	if ResourceLoader.exists(OWN_CLIPS):
		_lib = load(OWN_CLIPS) as AnimationLibrary
		_lib_from = OWN_CLIPS
	elif ResourceLoader.exists(LIB_PATH):
		var src := load(LIB_PATH) as AnimationLibrary
		if src != null:
			var lib := AnimationLibrary.new()
			var used := {}
			for m in [PLAYER_CLIPS, ENEMY_CLIPS]:
				for k in m:
					for n in m[k]:
						used[n] = true
			for n in used:
				if src.has_animation(n):
					var a := (src.get_animation(n) as Animation).duplicate(true) as Animation
					ease_wrists(a)
					lib.add_animation(n, a)
			_lib = lib
			_lib_from = LIB_PATH
	_baked.clear()
	if _lib != null:
		for n in _lib.get_animation_list():
			var a := _lib.get_animation(n)
			for t in a.get_track_count():
				if a.track_get_type(t) == Animation.TYPE_BLEND_SHAPE:
					_baked["@shapes"] = true
				else:
					var p := String(a.track_get_path(t))
					if p.begins_with("Skeleton3D:"):
						_baked[p.substr(11)] = true
	return _lib


static func clip_source() -> String:
	clip_library()
	return _lib_from


## ข้อมือของผิวต่อเนื่อง: ท่าที่ปรับอาวุธของชุดโมเดลแข็งหมุนมือ/ข้อมือเกือบรอบ (ผิวบิดเป็นหนาม)
## รวม wrist·hand ไว้ที่ wrist แล้วจำกัดการบิดรอบแกนแขนและการพับ · hand ไม่หมุน · ตัดแทร็กตำแหน่งมือ/ข้อมือ (ตำแหน่งพัก)
static func ease_wrists(a: Animation) -> void:
	for sd in ["L", "R"]:
		var tw := a.find_track(NodePath("Skeleton3D:wrist" + sd), Animation.TYPE_ROTATION_3D)
		var th := a.find_track(NodePath("Skeleton3D:hand" + sd), Animation.TYPE_ROTATION_3D)
		if tw >= 0:
			for k in a.track_get_key_count(tw):
				var qw: Quaternion = a.track_get_key_value(tw, k)
				var qh := a.rotation_track_interpolate(th, a.track_get_key_time(tw, k)) if th >= 0 else Quaternion.IDENTITY
				a.track_set_key_value(tw, k, limit_turn((qw * qh).normalized(), WRIST_TWIST, WRIST_SWING))
		if th >= 0:
			for k in a.track_get_key_count(th):
				a.track_set_key_value(th, k, Quaternion.IDENTITY)
		for b in ["wrist" + sd, "hand" + sd]:
			var tp := a.find_track(NodePath("Skeleton3D:" + b), Animation.TYPE_POSITION_3D)
			if tp >= 0:
				a.remove_track(tp)


## แยก q เป็นพับ (swing) × บิดรอบแกน Y ของกระดูก (twist) แล้วจำกัดแต่ละส่วนไม่เกินองศาที่ให้
static func limit_turn(q: Quaternion, twist_max: float, swing_max: float) -> Quaternion:
	var tw := Quaternion(0.0, q.y, 0.0, q.w)
	tw = Quaternion.IDENTITY if tw.length_squared() < 1e-12 else tw.normalized()
	var sw := q * tw.inverse()
	return (_clamp_turn(sw, swing_max) * _clamp_turn(tw, twist_max)).normalized()


## มุมหมุนของ q (องศา, 0..180)
static func turn_deg(q: Quaternion) -> float:
	return rad_to_deg(2.0 * acos(clampf(absf(q.w), 0.0, 1.0)))


## ส่วนบิดรอบแกน Y ของ q (องศา, −180..180)
static func twist_deg(q: Quaternion) -> float:
	var tw := Quaternion(0.0, q.y, 0.0, q.w)
	if tw.length_squared() < 1e-12:
		return 0.0
	tw = tw.normalized()
	return wrapf(rad_to_deg(2.0 * atan2(tw.y, tw.w)), -180.0, 180.0)


## กฎของกระดูกช่วยชื่อ name (พ่อ parent): [ชนิด, กระดูกต้นทาง, ต้นทาง 2] · ชนิด "" = ไม่รู้จัก (คงท่าพัก)
## half = ครึ่งมุมของข้อ · upper_twist = หมุนกลับครึ่งหนึ่งของการบิดต้นแขน · fore_twist = รับการบิดข้อมือ+มือส่วนหนึ่ง
## clavicle = ไหล่ยก/ยื่นตามทิศต้นแขน
static func helper_rule(name: String, parent: String) -> Array:
	var side := name.right(1)
	if side != "L" and side != "R":
		return ["", "", ""]
	if name.begins_with("clavicle"):
		return ["clavicle", "shoulder" + side, ""]
	var h := name.find("_half")
	if h > 0:
		return ["half", name.substr(0, h) + side, ""]
	if name.contains("twist"):
		if parent.begins_with("shoulder"):
			return ["upper_twist", parent, ""]
		if parent.begins_with("elbow"):
			return ["fore_twist", "wrist" + side, "hand" + side]
	return ["", "", ""]


## กระดูกช่วยทั้งหมดของโครงกับกฎ [{bone, parent, kind, src, src2}] (เทสตรวจว่ารู้จักครบ)
static func helper_rules() -> Array:
	_load_static()
	var out := []
	var root := _rig.instantiate()
	var sk := root.get_node_or_null("Skeleton3D") as Skeleton3D
	if sk != null:
		for i in sk.get_bone_count():
			var n := sk.get_bone_name(i)
			if GAME_BONES.has(n):
				continue
			var par := sk.get_bone_name(sk.get_bone_parent(i)) if sk.get_bone_parent(i) >= 0 else ""
			var r := helper_rule(n, par)
			out.append({"bone": n, "parent": par, "kind": r[0], "src": r[1], "src2": r[2]})
	root.free()
	return out


## ท่าแก้ชื่อ s ตัวขับรู้จักไหม (ชนิดใน SHAPE_KINDS + L/R)
static func shape_known(s: String) -> bool:
	return SHAPE_KINDS.has(s.left(s.length() - 1)) and (s.ends_with("L") or s.ends_with("R"))


## น้ำหนักท่าแก้จากท่าข้อ (สูตรเดียวกับ tools/soldier/py/correctives.py): rot = ชื่อกระดูก → Quaternion
## คืน {ชื่อท่าแก้: น้ำหนัก 0..1}
static func shape_weights(rot: Dictionary) -> Dictionary:
	_load_static()
	var out := {}
	var keys: Dictionary = _drv["arm_keys"]
	for sd in ["L", "R"]:
		var sx := 1.0 if sd == "L" else -1.0
		var d: Vector3 = (rot["shoulder" + sd] as Quaternion) * DOWN
		d.x *= sx
		for k in ["down", "front", "up"]:
			var r := _ang(keys["bind"], keys[k])
			out["shoulder_%s%s" % [k, sd]] = _ease(1.0 - _ang(d, keys[k]) / r)
		var th := _ang((rot["elbow" + sd] as Quaternion) * DOWN, DOWN)
		out["elbow_flex" + sd] = clampf((th - float(_drv["bind_elbow"])) / (float(_drv["elbow"]) - float(_drv["bind_elbow"])), 0.0, 1.0)
		out["knee_flex" + sd] = clampf(_ang((rot["knee" + sd] as Quaternion) * DOWN, DOWN) / float(_drv["knee"]), 0.0, 1.0)
		var t: Vector3 = (rot["hip" + sd] as Quaternion) * DOWN
		var phi := rad_to_deg(atan2(t.z, -t.y))
		out["hip_flex" + sd] = clampf(phi / float(_drv["hip_flex"]), 0.0, 1.0)
		out["hip_ext" + sd] = clampf(-phi / float(_drv["hip_ext"]), 0.0, 1.0)
	return out


static func _ang(a: Vector3, b: Vector3) -> float:
	return rad_to_deg(acos(clampf(a.normalized().dot(b.normalized()), -1.0, 1.0)))


static func _ease(x: float) -> float:
	x = clampf(x, 0.0, 1.0)
	return x * x * (3.0 - 2.0 * x)


static func _clamp_turn(q: Quaternion, max_deg: float) -> Quaternion:
	if q.w < 0.0:
		q = -q
	var a := 2.0 * acos(clampf(q.w, -1.0, 1.0))
	if a <= deg_to_rad(max_deg) or a < 1e-6:
		return q
	return Quaternion.IDENTITY.slerp(q, deg_to_rad(max_deg) / a)


static func _load_static() -> void:
	if _rig != null:
		return
	_rig = load(RIG) as PackedScene
	_skin = load(SKIN) as Skin
	_mat = load(MATERIAL) as ShaderMaterial
	if _mat != null:
		_mat_pv = _mat.duplicate() as ShaderMaterial
		_mat_pv.set_shader_parameter("per_vertex", true)
	# ค่าคงที่ของตัวขับ: meta ของราก rig.tscn (rig.json ของขั้นปั้น) ทับค่าของขั้น 1
	_drv = DRIVERS.duplicate()
	_drv["arm_keys"] = {}
	for k in ARM_KEYS:
		_drv["arm_keys"][k] = _vec(ARM_KEYS[k])
	_drv.merge(KEYS)
	_drv["bind_elbow"] = BIND_ELBOW
	if _rig == null:
		return
	var root := _rig.instantiate()
	var sk := root.get_node_or_null("Skeleton3D") as Skeleton3D
	if sk != null:
		_scale = sk.motion_scale
	var m: Variant = root.get_meta("soldier_rig", {})
	if m is Dictionary:
		var md: Dictionary = m
		for k in (md.get("drivers", {}) as Dictionary):
			_drv[k] = float(md["drivers"][k])
		for k in (md.get("keys", {}) as Dictionary):
			_drv[k] = float(md["keys"][k])
		if (md.get("bind_angles", {}) as Dictionary).has("elbow_flexion"):
			_drv["bind_elbow"] = float(md["bind_angles"]["elbow_flexion"])
		for k in (md.get("arm_keys", {}) as Dictionary):
			_drv["arm_keys"][k] = _vec(md["arm_keys"][k])
	root.free()


static func _vec(a: Variant) -> Vector3:
	return Vector3(float(a[0]), float(a[1]), float(a[2])) if a is Array and (a as Array).size() >= 3 else Vector3.ZERO


# ================= ภายใน =================

func _build() -> void:
	if _built:
		return
	_load_static()
	if _rig == null:
		return
	_model = _rig.instantiate() as Node3D
	_model.name = "Model"
	add_child(_model)
	_sk = _model.get_node("Skeleton3D") as Skeleton3D
	for i in _sk.get_bone_count():
		_idx[_sk.get_bone_name(i)] = i
	_mi = MeshInstance3D.new()
	_mi.name = "Body"
	_mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_sk.add_child(_mi)
	_mi.skeleton = NodePath("..")
	_mi.skin = _skin
	_rest = _model.transform
	_built = true
	var lib := clip_library()
	_ready_rules()
	if lib == null:
		_set_mesh(level)
		return
	_ap = AnimationPlayer.new()
	_ap.name = "AnimationPlayer"
	_model.add_child(_ap)
	_ap.root_node = NodePath("..")
	_ap.add_animation_library("humanoid", lib)
	if _manual:
		_ap.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
	_ap.mixer_applied.connect(_on_applied)
	_ap.animation_finished.connect(_on_finished)
	var fire := "humanoid/fire"
	_fire_anim = _ap.get_animation(fire) if _ap.has_animation(fire) else null
	_aim_tracks.clear()
	if _fire_anim != null:
		var ev: Array = _fire_anim.get_meta("events", [])
		_aim_t = maxf(float(ev[0].get("t", 0.28)) - 0.02, 0.0) if not ev.is_empty() else _fire_anim.length * 0.3
		for b in AIM_BONES:
			var bi := _sk.find_bone(b)
			var tr := _fire_anim.find_track(NodePath("Skeleton3D:" + b), Animation.TYPE_ROTATION_3D)
			if bi >= 0 and tr >= 0:
				_aim_tracks[bi] = tr
	_set_mesh(level)


## กฎกระดูกช่วยที่ต้องขับ (ครั้งเดียวต่อโปรแกรม หลังโหลดท่า: กระดูกที่ชุดท่ามีแทร็กเองแล้วไม่ต้องขับ)
func _ready_rules() -> void:
	if _rules_ready:
		return
	_rules_ready = true
	_rules = []
	for r in helper_rules():
		var b := int(_idx.get(r["bone"], -1))
		var s := int(_idx.get(r["src"], -1))
		if b >= 0 and s >= 0 and str(r["kind"]) != "" and not _baked.has(r["bone"]):
			_rules.append([b, str(r["kind"]), s, int(_idx.get(r["src2"], -1)), 1.0 if str(r["bone"]).ends_with("L") else -1.0])


func _set_mesh(l: String) -> void:
	var m := body_mesh(l)
	_mi.mesh = m
	_mi.material_override = _material_for(l)
	_shape_slots.clear()
	if m == null:
		return
	_height = maxf(m.get_aabb().end.y, 1.0)
	for i in m.get_blend_shape_count():
		_mi.set_blend_shape_value(i, 0.0)
		var nm := String(m.get_blend_shape_name(i))
		if shape_known(nm):
			_shape_slots.append([i, nm.left(nm.length() - 1), 0 if nm.ends_with("L") else 1])


func _material_for(l: String) -> ShaderMaterial:
	var pv := l == "lo" or l == "min"
	if _own_mat != null and (_own_lit or l != "min"):
		_own_mat.set_shader_parameter("per_vertex", pv and not _own_pp)
		return _own_mat
	return _mat_pv if pv else _mat


## ระดับที่ยืนนิ่งท่าเดียว: min ทุกบทบาท · ดาดฟ้า lo ด้วย (PACK_SPEC §3.2)
func _still_level() -> bool:
	return level == "min" or (role == &"deck" and level == "lo")


func _paused() -> bool:
	return _still and _ap != null and not _ap.is_playing()


func _aim_on() -> bool:
	return weapon == &"gun" and _fire_anim != null and not _dead and _oneshot == &"" and not _aim_tracks.is_empty()


## ยืนนิ่งอยู่แล้วท่าเล็งเปลี่ยน: วางท่าใหม่ครั้งเดียว (seek ลงกระดูก → _on_applied)
func _refresh_still() -> void:
	if _paused():
		_ap.seek(0.0, true)


func _start(clip: String, speed: float, from_start: bool) -> void:
	_cur_anim = _ap.get_animation(clip)
	_still = false
	if from_start and _ap.current_animation == clip:
		_ap.seek(0.0, true)
	if from_start:
		_ap.play(clip, BLEND_DIE if _oneshot == &"die" else BLEND, speed)
		_ap.speed_scale = 1.0
	else:
		_ap.play(clip, BLEND)
		_ap.speed_scale = speed
	_ev_prev = 0.0
	if _still_level() and clip.ends_with("/" + str(_clips["idle"][0])) and _oneshot == &"":
		_still_wait = BLEND


## หยุดนิ่งที่เฟรมแรกของ idle: AnimationPlayer ไม่เล่น
func _go_still() -> void:
	var clip := "humanoid/" + str(_clips["idle"][0])
	if not _ap.has_animation(clip):
		return
	if _ap.current_animation != clip:
		_ap.play(clip)
	_cur_anim = _ap.get_animation(clip)
	_still = true
	_still_wait = -1.0
	_ap.seek(0.0, true)
	_ap.pause()


func _on_applied() -> void:
	var dt := _dt if _manual else get_process_delta_time()
	_dt = 0.0
	if _aim_on():
		_aim_pose(dt)
	var anim: Animation = _ap.get_animation(_ap.current_animation) if _ap.current_animation != "" else _cur_anim
	if anim != null and _oneshot != &"":
		var pos := _ap.current_animation_position
		for e in anim.get_meta("events", []):
			var t := float(e.get("t", -1.0))
			if t > _ev_prev and t <= pos:
				clip_event.emit(StringName(str(e.get("kind", ""))))
		_ev_prev = pos
	if level != "min":
		_drive()
		if not _wounds.is_empty():
			_update_wounds()
	if _still_wait >= 0.0:
		_still_wait -= dt
		if _still_wait < 0.0 and _still_level() and _oneshot == &"" and _loop == &"idle" and not _dead:
			# หยุดนิ่งนอกการวางท่า (ไม่เรียก seek ซ้อนใน mixer_applied): manual = ท้าย step() · ปกติ = deferred
			if _manual:
				_still_due = true
			else:
				_go_still.call_deferred()


func _on_finished(_anim_name: StringName) -> void:
	if _oneshot == &"":
		return
	if _oneshot == &"die":
		_dead = true
		return
	_oneshot = &""
	_start("humanoid/" + str(_clips[String(_loop)][0]), _loop_rate if _loop != &"idle" else 1.0, false)


## ท่าเล็ง: ท่อนบนจากท่า fire (สะบัดตอนยิง) แล้วอกก้มเงยตามกล้อง
func _aim_pose(dt: float) -> void:
	var t := _aim_t
	if _recoil >= 0.0:
		_recoil += dt
		if _recoil >= RECOIL_T:
			_recoil = -1.0
		else:
			t += RECOIL_SPAN * sin(PI * _recoil / RECOIL_T)
	for bi: int in _aim_tracks:
		_sk.set_bone_pose_rotation(bi, _fire_anim.rotation_track_interpolate(_aim_tracks[bi], t))
	var c := _sk.find_bone("chest")
	if c < 0 or absf(_pitch) < 0.001:
		return
	var par := _sk.get_bone_parent(c)
	var pq := _sk.get_bone_global_pose(par).basis.get_rotation_quaternion() if par >= 0 else Quaternion.IDENTITY
	var r := Quaternion(Vector3.RIGHT, -_pitch * AIM_PITCH_K)
	_sk.set_bone_pose_rotation(c, (pq.inverse() * r * pq * _sk.get_bone_pose_rotation(c)).normalized())


## ตัวขับ: กระดูกช่วย (hi/mid/lo) แล้วท่าแก้ (hi/mid ที่เมชมี blend shape) จากท่าข้อที่วางเสร็จแล้ว
func _drive() -> void:
	if helpers_on:
		for r: Array in _rules:
			var q := _sk.get_bone_pose_rotation(int(r[2]))
			var out := Quaternion.IDENTITY
			match str(r[1]):
				"half":
					out = Quaternion.IDENTITY.slerp(q, 0.5)
				"upper_twist":
					var tw := Quaternion(0.0, q.y, 0.0, q.w)
					tw = Quaternion.IDENTITY if tw.length_squared() < 1e-12 else tw.normalized()
					out = Quaternion.IDENTITY.slerp(tw.inverse(), float(_drv["twist_k"]))
				"fore_twist":
					var qc := q * (_sk.get_bone_pose_rotation(int(r[3])) if int(r[3]) >= 0 else Quaternion.IDENTITY)
					var tw := Quaternion(0.0, qc.y, 0.0, qc.w)
					tw = Quaternion.IDENTITY if tw.length_squared() < 1e-12 else tw.normalized()
					out = Quaternion.IDENTITY.slerp(tw, float(_drv["twist_k"]))
				"clavicle":
					var sx := float(r[4])
					var d := q * DOWN
					var elev := rad_to_deg(acos(clampf(-d.y, -1.0, 1.0)))
					var a := minf(float(_drv["clav_elev_max"]), float(_drv["clav_elev_k"]) * maxf(0.0, elev - 30.0))
					var b := float(_drv["clav_prot_k"]) * rad_to_deg(asin(clampf(d.z, -1.0, 1.0)))
					out = Quaternion(Vector3.UP, deg_to_rad(-sx * b)) * Quaternion(Vector3.BACK, deg_to_rad(sx * a))
			_sk.set_bone_pose_rotation(int(r[0]), out)
	if not correctives_on or _shape_slots.is_empty() or _baked.has("@shapes") or level == "lo":
		return
	var rot := {}
	for b in ["shoulderL", "shoulderR", "elbowL", "elbowR", "hipL", "hipR", "kneeL", "kneeR"]:
		rot[b] = _sk.get_bone_pose_rotation(int(_idx[b]))
	var w := shape_weights(rot)
	for s: Array in _shape_slots:
		var v := float(w.get(str(s[1]) + ("L" if int(s[2]) == 0 else "R"), 0.0))
		if v < SHAPE_ZERO:
			v = 0.0
		if absf(_mi.get_blend_shape_value(int(s[0])) - v) > 0.002 or (v == 0.0 and _mi.get_blend_shape_value(int(s[0])) != 0.0):
			_mi.set_blend_shape_value(int(s[0]), v)


func _reset_helpers() -> void:
	if _sk == null:
		return
	for r: Array in _rules:
		_sk.set_bone_pose_rotation(int(r[0]), Quaternion.IDENTITY)
	if _mi != null and _mi.mesh != null:
		for i in _mi.mesh.get_blend_shape_count():
			_mi.set_blend_shape_value(i, 0.0)


func _update_overlay() -> void:
	if _mi == null:
		return
	var tint := _tele if level != "min" else 0.0
	var mat: StandardMaterial3D = null
	if _flash > 0.0 or tint > 0.0:
		if _overlay == null:
			_overlay = StandardMaterial3D.new()
			_overlay.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
			_overlay.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		if _flash > 0.0:
			_overlay.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
			_overlay.albedo_color = Color(FLASH_COLOUR, 0.85 * _flash)
		else:
			_overlay.blend_mode = BaseMaterial3D.BLEND_MODE_MIX
			_overlay.albedo_color = Color(TINT_COLOUR, 0.4 * tint)
		mat = _overlay
	_mi.material_overlay = mat


func _dodge_pose(f: float, lean: float) -> void:
	if _model == null:
		return
	_model.transform = Transform3D(Basis(Vector3.RIGHT, lean * f), Vector3(0.0, -DODGE_DIP * f, 0.0)) * _rest


## แผลสุ่มแบบมี seed (_wrng): กระดูกตามน้ำหนัก WOUND_BONES แล้วจุดผิวของกระดูกนั้น ศูนย์กลางลึกใต้ผิว WOUND_DEPTH
## trunk = ช่วงรัศมีที่ลำตัว · limb = ที่แขนขา · min ไม่สุ่ม (ไม่มีแผลเลย)
func _random_wound(trunk: Vector2, limb: Vector2) -> bool:
	if not _built or level == "min":
		return false
	var spots := wound_spots()
	var total := 0.0
	for b: StringName in WOUND_BONES:
		if spots.has(b):
			total += float(WOUND_BONES[b])
	if total <= 0.0:
		return false
	var x := _wrng.randf() * total
	var pick: StringName = &""
	for b: StringName in WOUND_BONES:
		if not spots.has(b):
			continue
		pick = b
		x -= float(WOUND_BONES[b])
		if x <= 0.0:
			break
	var list: Array = spots[pick]
	var s: Array = list[_wrng.randi_range(0, list.size() - 1)]
	var rr := trunk if TRUNK_BONES.has(pick) else limb
	var rad := lerpf(rr.x, rr.y, _wrng.randf())
	return add_wound(pick, (s[0] as Vector3) - (s[1] as Vector3) * rad * WOUND_DEPTH, rad)


## สภาพแผลตามระดับ: hi/mid = วัสดุของตัวเอง (ทิ้งผิวในแผล) + ชั้นในเห็น · lo = สีแผลบนผิว ไม่มีชั้นใน
## min หรือไม่มีแผล = วัสดุร่วม ชั้นในซ่อน (visible = false ไม่มีต้นทุน)
func _show_wounds() -> void:
	if not _built or _mat == null:
		return
	var on := not _wounds.is_empty() and level != "min"
	var cut := on and (level == "hi" or level == "mid")
	if on and _own_mat == null:
		_own_mat = _mat.duplicate() as ShaderMaterial
	elif _wounds.is_empty() and _own_mat != null and not _own_lit:
		_own_mat = null
	if cut and _inner.is_empty():
		_make_inner()
	for mi: MeshInstance3D in _inner:
		mi.visible = cut
	_mi.material_override = _material_for(level)
	_update_wounds()


## ส่งศูนย์กลาง (กรอบโครง) + การหมุนของกระดูกของแต่ละแผลให้เชดเดอร์ (ทุกเฟรมเฉพาะตอนมีแผล · min ไม่มี)
func _update_wounds() -> void:
	var n := _wounds.size() if level != "min" else 0
	var c := PackedVector4Array()
	var q := PackedVector4Array()
	c.resize(MAX_WOUNDS)
	q.resize(MAX_WOUNDS)
	for i in n:
		var w: Array = _wounds[i]
		var g := _sk.get_bone_global_pose(int(w[1]))
		var p := g * (w[2] as Vector3)
		var r := g.basis.get_rotation_quaternion()
		c[i] = Vector4(p.x, p.y, p.z, float(w[3]))
		q[i] = Vector4(r.x, r.y, r.z, r.w)
	var mats: Array = []
	if _own_mat != null:
		mats.append(_own_mat)
	if level == "hi" or level == "mid":
		mats.append_array(_inner_mats)
	for m: ShaderMaterial in mats:
		m.set_shader_parameter("wound_count", n)
		m.set_shader_parameter("wounds", c)
		m.set_shader_parameter("wound_rot", q)
	if _own_mat != null:
		_own_mat.set_shader_parameter("wound_mode", 2 if level == "hi" or level == "mid" else 1)
	if n > 0:
		_wound_updates += 1


## ชั้นในของตัวนี้ (ผูกโครงและ Skin เดียวกับผิว) วัสดุของตัวเอง · สร้างครั้งเดียวตอนแผลแรกบน hi/mid
func _make_inner() -> void:
	for l in ["flesh", "bone"]:
		var m := inner_mesh(l)
		var base := m.surface_get_material(0) as ShaderMaterial if m != null else null
		if base == null:
			continue
		var mi := MeshInstance3D.new()
		mi.name = "Inner_" + l
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mi.mesh = m
		var mat := base.duplicate() as ShaderMaterial
		mi.material_override = mat
		_sk.add_child(mi)
		mi.skeleton = NodePath("..")
		mi.skin = _skin
		_inner.append(mi)
		_inner_mats.append(mat)
	_sync_inner_light()


## ไฟของชั้นใน = ไฟของผิว (ไฟเริ่มของวัสดุร่วม หรือไฟฉากโชว์จาก set_light)
func _sync_inner_light() -> void:
	var src := _own_mat if _own_mat != null else _mat
	if src == null:
		return
	for k in ["sun_dir", "sun_colour", "ambient_colour"]:
		var v: Variant = src.get_shader_parameter(k)
		if v != null:
			for m: ShaderMaterial in _inner_mats:
				m.set_shader_parameter(k, v)
