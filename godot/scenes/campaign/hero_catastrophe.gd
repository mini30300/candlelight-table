extends "res://scenes/campaign/hero_base.gd"
## ฉากในตัวของ "ภัยพิบัติ": อัศวินทรยศและปีศาจของโต๊ะรบ (ชุด cx*/dm*) ปรากฏเรียงแถวทีละตัวแบบฉากอนิเมะที่นักสู้นึกถึงศัตรูทุกตัว
## แถว 7 ตัว (dmc cxp cxb cxl cxs cxw dmr) cxl อยู่กลางยืนหน้า ปรากฏจากริมเข้าหากลางทีละตัวห่าง 0.35 วิ: โผล่จากเงามืด
## (แสงค่อย ๆ ขึ้น ขอบแสงแดงวาบ เสาแสงแดงจาง ๆ) ไฟแดงเข้มจากหลังและบน หมอกแดง (hi/mid) แถบหมอกพื้นลอยช้า ๆ
## เพลง: AudioStreamPlayer เล่น CampaignHeroes.music_path() (catastrophe.ogg ของชุดเสริม) วนซ้ำ บัส Music · หยุดใน set_active(false)
## hi/mid: ท่ายืน idle · lo: ปรากฏทีละตัวแต่ยืนนิ่ง · min: แถวครบ นิ่ง ไม่มีหมอก ไม่เล่นเพลงเอง
## สัญญาฉาก (CampaignHeroes): setup(ctx) สร้างทุกอย่างเองรวม Camera3D (current) · set_active(on) หยุด/เล่นต่อ

const FOV := 30.0
## ซ้าย → ขวา (ตัวกลาง index 3 = cxl) · ตัวสำรองเมื่อไม่มีชุดนั้น
const ROW: Array[PackedStringArray] = [["dmc", "cxw"], ["cxp", "cxw"], ["cxb", "cxw"], ["cxl", "cxp"], ["cxs", "cxw"],
	["cxw", "cxp"], ["dmr", "cxw"]]
const CENTRE := 3
## ลำดับที่ปรากฏ: จากริมเข้าหากลาง ตัวกลางสุดท้าย
const ORDER: Array[int] = [0, 6, 1, 5, 2, 4, 3]
const GAP := 0.35
const APPEAR := 0.6
const HOLD_TO := 8.0
const FADE_T := 0.8
const LOOP := 9.2
const SUN_DIR := Vector3(0.0, 0.6, -1.0)
const SUN := Color(0.62, 0.09, 0.05)
const AMBIENT := Color(0.1, 0.08, 0.09)
const RIM := Color(1.0, 0.16, 0.08)
const RIM_K := 1.25
const FOG := Color(0.12, 0.012, 0.012)

var row: Array[Node3D] = []
var _rims: Array[ShaderMaterial] = []
var _pillars: Array[MeshInstance3D] = []
var _mists: Array[MeshInstance3D] = []
var _player: AudioStreamPlayer
var _centre := Vector3(0.0, 1.15, -0.4)


func _build() -> void:
	camera = HeroKit.camera(self, FOV)
	var fog := level == "hi" or level == "mid"
	HeroKit.environment(self, Color(0.0, 0.0, 0.0), FOG, 0.035 if fog else 0.0)
	HeroKit.backdrop(camera, Color(0.06, 0.0, 0.004), Color(0.0, 0.0, 0.0), Color(0.5, 0.05, 0.025),
		Vector2(0.5, 0.64), 0.8, 0.7)
	HeroKit.sun(self, SUN_DIR, Color(0.9, 0.2, 0.12), 0.8)
	var fl := HeroKit.floor_disc(self, 10.0, Color(0.03, 0.02, 0.02), 0.85)
	((fl.mesh as CylinderMesh).material as StandardMaterial3D).metallic = 0.0
	var pool := HeroKit.glow(self, 0, Color(0.7, 0.06, 0.03), 0.45, Vector2(11.0, 5.0), true)
	pool.name = "Pool"
	pool.position = Vector3(0.0, 0.01, -0.8)
	for i in ROW.size():
		var f := HeroKit.kit_figure(ROW[i], "beast")
		add_child(f)
		HeroKit.setup_figure(f, 41 + i)
		f.call("play", &"idle", 1.0)
		HeroLight.apply(f, SUN_DIR, SUN, AMBIENT)
		_rims.append(HeroKit.rim(f, RIM, 2.0, RIM_K, Vector3(0.0, 0.5, -1.0), SUN_DIR))
		row.append(f)
		if level == "hi" or level == "mid":
			figs.append(f)
		var p := HeroKit.cone(self, Vector3(0.0, 4.5, 0.0), 0.35, 0.6, 4.5, Color(1.0, 0.15, 0.08), 0.0)
		p.name = "Pillar%d" % i
		p.visible = false
		_pillars.append(p)
	if fog:
		for k in 2:
			var m := HeroKit.glow(self, 2, Color(0.55, 0.06, 0.04), 0.35 - 0.1 * k, Vector2(14.0, 0.9 + 0.4 * k))
			m.name = "Mist%d" % k
			m.position = Vector3(0.0, 0.25 + 0.3 * k, 0.6 - 1.6 * k)
			_mists.append(m)
	_player = AudioStreamPlayer.new()
	_player.name = "Music"
	var mp := CampaignHeroes.music_path()
	if mp != "":
		var s: Variant = load(mp)
		if s is AudioStream:
			var st: AudioStream = (s as AudioStream).duplicate()
			if "loop" in st:
				st.set("loop", true)
			_player.stream = st
	if AudioServer.get_bus_index(&"Music") >= 0:
		_player.bus = &"Music"
	add_child(_player)


## แถวโค้ง: กว้าง = ห่าง 1.15 ม. ถอยหลังเป็นรูปตัววีตื้น · แนวตั้ง = ชิดกันและวีลึก (ไม่เล็กเกินในการ์ดแคบ)
func _layout() -> void:
	if camera == null:
		return
	var tall := aspect < 1.0
	var step := 0.45 if tall else 1.15
	var depth := 0.85 if tall else 0.32
	for i in row.size():
		var o := i - CENTRE
		var base := Vector3(o * step, 0.0, 0.5 - depth * absf(o))
		row[i].set_meta(&"base", base)
		row[i].position = base
		row[i].rotation.y = -0.13 * o
		_pillars[i].position.x = base.x
		_pillars[i].position.z = base.z
	var half := Vector2(3.0 * step + 0.65, 1.4) if not tall else Vector2(3.0 * step + 0.45, 1.5)
	HeroKit.frame(camera, _centre, half, aspect, Vector3(0.0, 0.06, 1.0))


func _reset() -> void:
	for i in row.size():
		_show(i, 0.0, 0.0)


func _tick(_dt: float) -> void:
	if t >= LOOP:
		var keep := t - LOOP
		_reset()
		t = keep
	var out := clampf((t - HOLD_TO) / FADE_T, 0.0, 1.0)
	for n in ORDER.size():
		var i := ORDER[n]
		var k := clampf((t - GAP * n) / APPEAR, 0.0, 1.0)
		_show(i, k * (1.0 - out), clampf((t - GAP * n) / 0.25, 0.0, 1.0) if t >= GAP * n else 0.0)
	for k in _mists.size():
		_mists[k].position.x = (0.8 - 1.6 * k) * sin(TAU * t / (11.0 + 4.0 * k))


## ตัวที่ i: k = ความสว่าง 0..1 (0 = ซ่อน) · flash 0..1 ของจังหวะโผล่ (ขอบแสงวาบ เสาแสง)
func _show(i: int, k: float, flash: float) -> void:
	var f := row[i]
	f.visible = k > 0.001
	var e := k * k * (3.0 - 2.0 * k)
	var base: Vector3 = f.get_meta(&"base", f.position)
	f.position = base + Vector3(0.0, -0.22 * (1.0 - e), 0.0)
	HeroLight.apply(f, SUN_DIR, SUN * e, AMBIENT * e)
	var pop := (1.0 - flash) * float(flash > 0.0)
	_rims[i].set_shader_parameter("strength", RIM_K * e + 1.8 * pop * e)
	_rims[i].set_shader_parameter("power", lerpf(2.0, 0.9, pop))
	var p := _pillars[i]
	var ps := 0.55 * (1.0 - clampf(flash * 1.2, 0.0, 1.0)) if flash > 0.0 else 0.0
	if i == CENTRE:
		ps *= 1.6
	p.visible = ps > 0.01
	(p.material_override as ShaderMaterial).set_shader_parameter("strength", ps)


func _on_active(on: bool) -> void:
	if _player == null:
		return
	if on and level != "min" and _player.stream != null:
		_player.play()
	else:
		_player.stop()


func _moves() -> bool:
	return level != "min"


## ภาพนิ่ง: แถวครบ ทุกตัวสว่างเต็ม
func poster_t() -> float:
	return GAP * 6.0 + APPEAR + 0.6


## เครื่องเล่นเพลง (เทส)
func music() -> AudioStreamPlayer:
	return _player
