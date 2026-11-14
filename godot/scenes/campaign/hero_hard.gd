extends Node3D
## ฉากในตัวของ "ยาก": อัศวินชุดเกราะสามตัวชุดสีน้ำเงิน ยืนเรียงเยื้องกันแบบเท่ (ชุดโมเดล knight / kcapt / kblade + KitWalker)
## TODO(track B): สามตัว ชุดสีน้ำเงิน (2f5fb0 / d6d8de) แสงเย็นจากด้านข้าง กล้องต่ำมองขึ้นเล็กน้อย · min = ท่านิ่ง
## สัญญาฉาก (CampaignHeroes): setup(ctx) สร้างทุกอย่างเองรวม Camera3D (current) · set_active(on) หยุด/เล่นต่อ

var level := "mid"
var active := false
var camera: Camera3D


func setup(ctx: Dictionary) -> void:
	level = str(ctx.get("level", "mid"))
	camera = Camera3D.new()
	camera.name = "Camera"
	camera.position = Vector3(0.0, 1.5, 3.0)
	add_child(camera)
	camera.current = true


func set_active(on: bool) -> void:
	active = on
	set_process(on and level != "min")
