extends "res://scenes/campaign/hero_base.gd"
## ฉากในตัวของ "ยากมาก": อัศวินเงินถือง้าว (ชุด pike_halb สำรอง naginata แล้ว kblade) เอเลี่ยนตัวเล็ก 3–4 ตัววิ่งเข้าหา
## (ชุด hound สำรอง gaunt) ถึงตัวแล้วเขาหมุนตัวเต็มรอบพร้อมท่า swing_1 ฟันล้มทั้งหมด (ทางดาบเรืองแสง คลื่นกระแทกบนพื้น)
## ศัตรูเล่นท่า die_* กระเด็นออก จมหายลงพื้น แล้ววนใหม่ทุก LOOP วิ · ทุกอย่างเป็นฟังก์ชันของเวลา t (seek ได้ ท่าเดิมทุกครั้ง)
## hi/mid/lo: วนเล่น (lo เอเลี่ยน 3 ตัว) · min: ภาพนิ่งจังหวะฟัน (poster_t)
## หมุนตัวคิดในไทม์ไลน์ของฉากเอง (ไม่ใช้ Tween) จึงหยุด/seek ได้ตรงเฟรม
## สัญญาฉาก (CampaignHeroes): setup(ctx) สร้างทุกอย่างเองรวม Camera3D (current) · set_active(on) หยุด/เล่นต่อ

const FOV := 34.0
const KNIGHT_KITS: PackedStringArray = ["pike_halb", "naginata", "kblade"]
const ALIEN_KITS: PackedStringArray = ["hound", "gaunt"]
const SILVER := Color("c9ccd4")
const SILVER_2 := Color("8f97a8")      # ผ้า/เกล็ด: เงินหม่น (สเปกใช้ 3b4250 แต่ชุด pike_halb เกือบทั้งตัวเป็นผ้า จะดูมืดเกินไป)
const SUN_DIR := Vector3(-0.5, 0.8, 0.6)
const SUN := Color(0.9, 0.9, 0.95)
const AMBIENT := Color(0.16, 0.17, 0.2)
const RIM_KNIGHT := Color(0.7, 0.82, 1.0)
const RIM_ALIEN := Color(0.75, 0.3, 0.95)
const LOOP := 4.0
const SPIN_AT := 1.3          # เริ่มหมุน
const SPIN_T := 0.45          # หมุนเต็มรอบในกี่วิ
const SWING_RATE := 1.25      # ความเร็วท่า swing_1 (ใบผ่านราว 0.35 วิหลังเริ่ม)
const CUT_AT := 1.5           # ตัวแรกล้ม
const CUT_GAP := 0.055
const RUN_FROM := 5.2         # ระยะเริ่มวิ่ง (ม.)
const CONTACT := 1.35         # ระยะถึงตัว
const ARRIVE := 1.45
const SINK_AT := 2.75
const SINK_T := 0.5
const FLASH_T := 0.12
const DIE_RATE := 1.5
const KNOCK := 0.6            # กระเด็นออก (ม.)
## มุมที่เอเลี่ยนวิ่งมา (องศาจาก +Z ไป +X; กล้องอยู่ด้าน +Z) เรียงตามทางหมุนของดาบ
const ANGLES_4: Array[float] = [75.0, -80.0, -135.0, 140.0]
const ANGLES_3: Array[float] = [75.0, -80.0, 180.0]

var knight: Node3D
var aliens: Array[Node3D] = []
var _rims: Array[ShaderMaterial] = []
var _dirs: Array[Vector3] = []
var _dead: Array[bool] = []
var _swung := false
var _trail: MeshInstance3D
var _trail_mat: StandardMaterial3D
var _wave: MeshInstance3D
var _centre := Vector3(0.0, 0.9, 0.0)


func _build() -> void:
	camera = HeroKit.camera(self, FOV)
	HeroKit.environment(self, Color(0.01, 0.012, 0.016))
	HeroKit.backdrop(camera, Color(0.07, 0.09, 0.1), Color(0.008, 0.01, 0.014), Color(0.17, 0.21, 0.22),
		Vector2(0.5, 0.42), 0.8, 0.8)
	HeroKit.sun(self, SUN_DIR, SUN, 1.0)
	HeroKit.floor_disc(self, 9.0, Color(0.05, 0.055, 0.065), 0.6)
	var pool := HeroKit.glow(self, 0, Color(0.5, 0.6, 0.7), 0.35, Vector2(5.0, 5.0), true)
	pool.name = "Pool"
	pool.position.y = 0.01
	knight = HeroKit.kit_figure(KNIGHT_KITS, "fighter")
	add_child(knight)
	HeroKit.setup_figure(knight, 21)
	HeroKit.paint(knight, SILVER, SILVER_2)
	knight.call("set_weapon", &"none")
	HeroLight.apply(knight, SUN_DIR, SUN, AMBIENT)
	HeroKit.rim(knight, RIM_KNIGHT, 2.4, 1.1, Vector3(1.0, 0.4, 0.0), SUN_DIR)
	figs.append(knight)
	var angles := ANGLES_3 if level == "lo" else ANGLES_4
	for i in angles.size():
		var a := HeroKit.kit_figure(ALIEN_KITS, "beast")
		add_child(a)
		HeroKit.setup_figure(a, 31 + i)
		HeroLight.apply(a, SUN_DIR, SUN, AMBIENT)
		_rims.append(HeroKit.rim(a, RIM_ALIEN, 2.4, 0.6, Vector3.ZERO, SUN_DIR))
		var r := deg_to_rad(angles[i])
		_dirs.append(Vector3(sin(r), 0.0, cos(r)))
		aliens.append(a)
		_dead.append(false)
		figs.append(a)
	_build_trail()
	_wave = HeroKit.glow(self, 3, Color(0.75, 0.85, 1.0), 0.0, Vector2(1.0, 1.0), true)
	_wave.name = "Wave"
	_wave.position.y = 0.03
	_wave.visible = false


## ทางดาบ: วงแหวนแบนเกือบรอบ (300°) ปลายนำสว่าง หางจาง (สีจุดยอด) บวกสี
func _build_trail() -> void:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var seg := 32
	var span := deg_to_rad(170.0)
	for i in seg:
		var a0 := span * float(i) / seg
		var a1 := span * float(i + 1) / seg
		var k0 := pow(1.0 - float(i) / seg, 2.0)
		var k1 := pow(1.0 - float(i + 1) / seg, 2.0)
		var pts := [Vector3(sin(a0) * 1.6, 0.0, cos(a0) * 1.6), Vector3(sin(a0) * 2.05, 0.0, cos(a0) * 2.05),
			Vector3(sin(a1) * 2.05, 0.0, cos(a1) * 2.05), Vector3(sin(a1) * 1.6, 0.0, cos(a1) * 1.6)]
		var cols := [Color(0.5, 0.7, 1.0, 0.0), Color(1.0, 1.0, 1.0, k0), Color(1.0, 1.0, 1.0, k1), Color(0.5, 0.7, 1.0, 0.0)]
		for idx in [0, 1, 2, 0, 2, 3]:
			st.set_color(cols[idx])
			st.add_vertex(pts[idx])
	_trail_mat = StandardMaterial3D.new()
	_trail_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_trail_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_trail_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	_trail_mat.vertex_color_use_as_albedo = true
	_trail_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	_trail_mat.no_depth_test = false
	_trail_mat.disable_fog = true
	# แกนเอียงตายตัว (ทางดาบเฉียงหันหากล้อง) ทางดาบหมุนรอบแกนนี้
	var pivot := Node3D.new()
	pivot.name = "TrailPivot"
	pivot.position.y = 1.1
	pivot.rotation = Vector3(0.22, 0.0, -0.16)
	add_child(pivot)
	_trail = MeshInstance3D.new()
	_trail.name = "Trail"
	_trail.mesh = st.commit()
	_trail.material_override = _trail_mat
	_trail.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_trail.visible = false
	pivot.add_child(_trail)


func _layout() -> void:
	if camera == null:
		return
	var tall := aspect < 1.0
	var half := Vector2(1.55, 1.6) if tall else Vector2(2.15, 1.2)
	HeroKit.frame(camera, _centre, half, aspect, Vector3(0.3, 0.24, 1.0))


func _reset() -> void:
	_swung = false
	if knight != null:
		knight.rotation.y = 0.25
		knight.call("play", &"idle", 1.0)
	for i in aliens.size():
		var a := aliens[i]
		_dead[i] = false
		a.visible = true
		a.call("play", &"run", 1.0)
		a.call("set_move", (RUN_FROM - CONTACT) / ARRIVE, true)
		_place(i, 0.0)
		_rim_flash(i, 0.0)
	if _trail != null:
		_trail.visible = false
	if _wave != null:
		_wave.visible = false


func _tick(_dt: float) -> void:
	if t >= LOOP:
		var keep := t - LOOP
		_reset()
		t = keep
	# อัศวิน: หมุนเต็มรอบพร้อมท่าฟัน
	if knight != null:
		if not _swung and t >= SPIN_AT:
			_swung = true
			if knight.has_method("set_variant"):
				knight.call("set_variant", 1)
			knight.call("play", &"swing", SWING_RATE / KitFighter.MELEE_RATE)
		var f := clampf((t - SPIN_AT) / SPIN_T, 0.0, 1.0)
		knight.rotation.y = 0.25 - TAU * (f * f * (3.0 - 2.0 * f))
	# ทางดาบตามมุมตัว จางหลังหมุนจบ
	if _trail != null:
		var on := t >= SPIN_AT + 0.04 and t < SPIN_AT + SPIN_T + 0.16
		_trail.visible = on
		if on:
			_trail.rotation.y = knight.rotation.y + 0.9
			var fade := clampf(1.0 - (t - SPIN_AT - SPIN_T) / 0.16, 0.0, 1.0)
			_trail_mat.albedo_color = Color(1.0, 1.0, 1.0, fade)
	# คลื่นกระแทกบนพื้น
	if _wave != null:
		var w := (t - SPIN_AT - 0.2) / 0.5
		_wave.visible = w >= 0.0 and w <= 1.0
		if _wave.visible:
			var r := lerpf(1.2, 4.8, w)
			_wave.scale = Vector3(r, 1.0, r)
			(_wave.material_override as ShaderMaterial).set_shader_parameter("strength", 0.9 * (1.0 - w) * (1.0 - w))
	for i in aliens.size():
		var cut := CUT_AT + CUT_GAP * i
		if not _dead[i] and t >= cut:
			_dead[i] = true
			aliens[i].call("set_variant", i % 3)
			aliens[i].call("play", &"die", DIE_RATE)
		_place(i, t)
		_rim_flash(i, clampf(1.0 - (t - cut) / FLASH_T, 0.0, 1.0) if t >= cut else 0.0)


## ที่ของเอเลี่ยน i ตอนเวลา tt: วิ่งเข้า → ถึงตัว → กระเด็นออก → จมลงพื้น
func _place(i: int, tt: float) -> void:
	var a := aliens[i]
	var d := _dirs[i]
	var start := 0.08 * i
	var arrive := ARRIVE + 0.04 * i
	var cut := CUT_AT + CUT_GAP * i
	var dist := RUN_FROM
	if tt >= start:
		dist = lerpf(RUN_FROM, CONTACT, clampf((tt - start) / (arrive - start), 0.0, 1.0))
	if tt >= cut:
		var k := clampf((tt - cut) / 0.4, 0.0, 1.0)
		dist = CONTACT + KNOCK * (1.0 - (1.0 - k) * (1.0 - k))
	var y := 0.0
	if tt >= SINK_AT:
		y = -1.1 * clampf((tt - SINK_AT) / SINK_T, 0.0, 1.0)
	a.visible = tt < SINK_AT + SINK_T
	a.position = d * dist + Vector3(0.0, y, 0.0)
	a.rotation.y = atan2(-d.x, -d.z)


## วาบขาวตอนโดนฟัน (ขอบแสงกว้างทั้งตัว) k 0..1
func _rim_flash(i: int, k: float) -> void:
	if i >= _rims.size() or _rims[i] == null:
		return
	var m := _rims[i]
	m.set_shader_parameter("colour", Vector3(RIM_ALIEN.r, RIM_ALIEN.g, RIM_ALIEN.b).lerp(Vector3.ONE, k))
	m.set_shader_parameter("power", lerpf(2.4, 0.4, k))
	m.set_shader_parameter("strength", lerpf(0.6, 2.5, k))


func _moves() -> bool:
	return level != "min"


## ภาพนิ่ง: กลางรอบหมุน ทางดาบสว่าง ตัวแรกเพิ่งโดน
func poster_t() -> float:
	return 1.6
