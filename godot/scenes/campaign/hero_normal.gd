extends "res://scenes/campaign/hero_base.gd"
## ฉากในตัวของ "ธรรมดา": ตัวผู้เล่นตามที่แต่งตัวอยู่ (ArenaActors.player_figure(ctx.sel) + ชุดสี) ซูมครึ่งบน หันหน้าเข้ากล้อง
## ฉากหลังดำ/เทาเงามืด ไฟส่องจากเหนือศีรษะ (sun_dir ของ figure.gdshader ชี้ขึ้น ambient ต่ำ) ลำแสงจาง ๆ จากบน ขอบแสงเย็น
## hi/mid: ท่ายืน idle ช้า 0.6 + กล้องเลื่อนเข้าออกช้า ๆ · lo/min: ท่านิ่งท่าเดียว
## สัญญาฉาก (CampaignHeroes): setup(ctx) สร้างทุกอย่างเองรวม Camera3D (current) · set_active(on) หยุด/เล่นต่อ

const FOV := 28.0
const SUN_DIR := Vector3(0.0, 1.0, 0.15)
const SUN := Color(0.98, 0.9, 0.78)
const AMBIENT := Color(0.15, 0.15, 0.16)
const RIM := Color(0.5, 0.58, 0.75)
const IDLE_RATE := 0.6
const PUSH := 0.035          # กล้องเลื่อนเข้าออก (สัดส่วนของระยะ)
const PUSH_T := 7.0
const YAW := 0.42           # หันเฉียงเล็กน้อย (ชุดถือโล่ไม่บังหน้า) ยังหันหน้าเข้ากล้อง

var figure: Node3D
var head := 1.5
var _wide := 0.0             # ตัวที่ไม่มีโครง (ไข่) กว้างกว่าคน: กรอบกว้างตามกล่องของตัว
var _manual := false
var _eye := Vector3.ZERO
var _look := Vector3.ZERO


func _build() -> void:
	camera = HeroKit.camera(self, FOV)
	HeroKit.environment(self, Color(0.01, 0.01, 0.012))
	HeroKit.backdrop(camera, Color(0.2, 0.2, 0.215), Color(0.008, 0.008, 0.01), Color(0.26, 0.255, 0.25),
		Vector2(0.5, -0.05), 0.75, 0.9)
	var fig := ArenaActors.player_figure(sel)
	if fig == null:
		fig = HeroKit.kit_figure(PackedStringArray(), "beast")
	fig.name = "Figure"
	add_child(fig)
	figure = fig
	_manual = fig is KitBeast
	if fig.has_method("setup"):
		fig.call("setup", {"role": &"player", "level": HeroKit.FIG_LEVEL if _manual else level,
			"team_colour": Color(0.28, 0.52, 0.84), "seed": 0, "manual": true})
	Figures.dress(fig, ArenaActors.scheme_of(sel))
	if fig.has_method("set_weapon"):
		fig.call("set_weapon", &"none")
	if fig.has_method("play"):
		fig.call("play", &"idle", IDLE_RATE)
	fig.rotation.y = YAW
	if _manual:
		figs.append(fig)
	HeroLight.apply(fig, SUN_DIR, SUN, AMBIENT)
	HeroKit.rim(fig, RIM, 2.4, 1.0, Vector3(0.0, 1.0, -0.3), SUN_DIR)
	# ไฟให้วัสดุแบบมีแสงของตัวชุดเสริม (ตัวจากชุดโมเดลใช้ HeroLight)
	HeroKit.sun(self, SUN_DIR, SUN, 1.2)
	head = HeroKit.head_y(fig, self)
	if not (fig.has_method("skeleton") and fig.call("skeleton") != null):
		_wide = HeroKit.box(fig).size.x * 0.55
	# ลำแสงจากเหนือศีรษะ (บวกสีจาง ๆ) กับแสงฟุ้งหลังไหล่
	HeroKit.cone(self, Vector3(0.0, head + 2.6, -0.15), 0.12, 0.85, 3.6, Color(0.95, 0.9, 0.8), 0.13)
	var halo := HeroKit.glow(self, 0, Color(0.6, 0.58, 0.55), 0.22, Vector2(2.4, 2.4))
	halo.name = "Halo"
	halo.position = Vector3(0.0, head + 0.15, -0.9)


## ครึ่งบน: กว้าง = หัวถึงอก · แนวตั้ง = หัวถึงเอว (เห็นตัวมากขึ้น ไม่เล็กเกิน)
func _layout() -> void:
	if camera == null:
		return
	var s := maxf(head / 1.45, 0.6)
	var top := head + 0.3 * s
	var low := head - (0.62 if aspect >= 1.0 else 0.95) * s
	if _wide > 0.0:
		# ไข่/ตัวไม่มีโครง: ทั้งตัวคือ "ครึ่งบน" เห็นเต็มตัวมีที่ว่างรอบ
		low = 0.1
		top = head + 0.55
	var centre := Vector3(0.0, (top + low) * 0.5, 0.0)
	var half := Vector2(maxf(0.42 * s if aspect >= 1.0 else 0.5 * s, _wide), (top - low) * 0.5)
	# กล้องระดับอก มองเงยเล็กน้อย
	HeroKit.frame(camera, centre, half, aspect, Vector3(0.0, -0.12, 1.0))
	_eye = camera.position
	_look = centre


func _tick(_dt: float) -> void:
	if camera == null or not _moves():
		return
	var k := 1.0 - PUSH * (0.5 - 0.5 * cos(TAU * t / PUSH_T))
	var eye := _look + (_eye - _look) * k
	camera.transform = Transform3D(Basis.looking_at(_look - eye, Vector3.UP), eye)


func _on_active(on: bool) -> void:
	# ตัวที่ไม่เดินท่าตามฉาก (ไข่ ตัวชุดเสริม) หยุดทั้งตัวตอนไม่เล่น
	if figure != null and not _manual:
		figure.process_mode = Node.PROCESS_MODE_INHERIT if on else Node.PROCESS_MODE_DISABLED


func poster_t() -> float:
	return 1.2
