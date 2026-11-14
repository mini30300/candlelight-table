extends "res://scenes/campaign/hero_base.gd"
## ฉากในตัวของ "ยาก": อัศวินชุดเกราะสามตัวชุดสีน้ำเงิน ยืนเรียงเยื้องกันแบบเท่ (ชุดโมเดล knight / kcapt / kblade + KitWalker)
## ตัวกลางยืนหน้า สองข้างถอยหลัง 0.8 ม. หันเข้าหากลาง 20° · กล้องต่ำมองเงย · ไฟเย็นจากด้านข้าง ขอบแสงฟ้าอีกด้าน หมอกพื้นจาง ๆ
## hi/mid: ท่ายืน idle (เหลื่อมจังหวะกัน) + กล้องส่ายช้า ๆ · lo/min: ท่านิ่ง
## สัญญาฉาก (CampaignHeroes): setup(ctx) สร้างทุกอย่างเองรวม Camera3D (current) · set_active(on) หยุด/เล่นต่อ

const FOV := 30.0
const KITS: Array[PackedStringArray] = [["knight", "kblade"], ["kcapt", "knight"], ["kblade", "knight"]]
const SUN_DIR := Vector3(0.85, 0.55, 0.45)
const SUN := Color(0.62, 0.7, 0.86)
const AMBIENT := Color(0.1, 0.12, 0.18)
const RIM := Color(0.35, 0.62, 1.0)
const TURN := 0.35            # หันเข้ากลาง (เรเดียน ≈ 20°)
const BACK := 0.8             # สองข้างถอยหลัง (ม.)
const PHASE: Array[float] = [0.0, 2.7, 5.1]
const SWAY := 0.05            # กล้องส่าย (เรเดียน)
const SWAY_T := 9.0

var knights: Array[Node3D] = []
var _mist: MeshInstance3D
var _centre := Vector3.ZERO
var _dist := 6.0
const DIR := Vector3(0.12, -0.22, 1.0)
var _dir := DIR


func _build() -> void:
	camera = HeroKit.camera(self, FOV)
	HeroKit.environment(self, Color(0.004, 0.006, 0.016))
	HeroKit.backdrop(camera, Color(0.05, 0.08, 0.15), Color(0.004, 0.006, 0.018), Color(0.12, 0.22, 0.42),
		Vector2(0.5, 0.52), 0.75, 0.8)
	HeroKit.sun(self, SUN_DIR, SUN, 1.0)
	HeroKit.floor_disc(self, 6.0, Color(0.035, 0.045, 0.075))
	var pool := HeroKit.glow(self, 0, Color(0.2, 0.42, 0.9), 0.5, Vector2(6.0, 4.0), true)
	pool.name = "Pool"
	pool.position = Vector3(0.0, 0.01, -0.3)
	var sch := Figures.scheme("blue")
	for i in KITS.size():
		var k := HeroKit.kit_figure(KITS[i], "walker")
		add_child(k)
		HeroKit.setup_figure(k, 11 + i)
		HeroKit.paint(k, sch["primary"], sch["secondary"])
		k.call("play", &"idle", 1.0)
		HeroLight.apply(k, SUN_DIR, SUN, AMBIENT)
		HeroKit.rim(k, RIM, 2.2, 1.15, Vector3(-1.0, 0.25, 0.0), SUN_DIR)
		knights.append(k)
		figs.append(k)
	if level == "hi" or level == "mid":
		_mist = HeroKit.glow(self, 2, Color(0.3, 0.45, 0.8), 0.28, Vector2(9.0, 0.7))
		_mist.name = "Mist"
		_mist.position = Vector3(0.0, 0.3, -1.6)


## แถวเยื้อง: กว้าง = ห่างกัน 1.05 ม. · แนวตั้ง = ชิดขึ้นและถอยลึกขึ้น (กรอบแคบไม่เล็กเกิน)
func _layout() -> void:
	if camera == null or knights.size() < 3:
		return
	var tall := aspect < 1.0
	var gap := 0.52 if tall else 1.05
	var back := 1.1 if tall else BACK
	knights[0].position = Vector3(-gap, 0.0, -back)
	knights[0].rotation.y = TURN
	knights[1].position = Vector3.ZERO
	knights[1].rotation.y = 0.0
	knights[2].position = Vector3(gap, 0.0, -back)
	knights[2].rotation.y = -TURN
	_centre = Vector3(0.0, 1.0 if tall else 0.95, -back * 0.4)
	var half := Vector2(gap + 0.55, 1.05) if not tall else Vector2(gap + 0.42, 1.15)
	HeroKit.frame(camera, _centre, half, aspect, DIR)
	# ทิศจริงหลัง frame (อาจถูกยกให้พ้นพื้น) ใช้ตอนกล้องส่าย
	_dir = (camera.position - _centre).normalized()
	_dist = camera.position.distance_to(_centre)


func _reset() -> void:
	for i in knights.size():
		var ap: AnimationPlayer = knights[i].call("animation_player") if knights[i].has_method("animation_player") else null
		if ap != null and ap.current_animation != "":
			ap.seek(PHASE[i % PHASE.size()], true)


func _tick(_dt: float) -> void:
	if camera == null or not _moves():
		return
	var a := SWAY * sin(TAU * t / SWAY_T)
	var d := _dir.normalized().rotated(Vector3.UP, a)
	var eye := _centre + d * _dist
	camera.transform = Transform3D(Basis.looking_at(_centre - eye, Vector3.UP), eye)
	if _mist != null:
		_mist.position.x = 0.6 * sin(TAU * t / 13.0)


func poster_t() -> float:
	return 0.6
