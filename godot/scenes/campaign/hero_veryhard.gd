extends Node3D
## ฉากในตัวของ "ยากมาก": อัศวินเงินถือง้าว (ชุด pike_halb สำรอง naginata) เอเลี่ยนตัวเล็ก 3–4 ตัววิ่งเข้าหา (ชุด hound / gaunt)
## เขาหมุนตัวฟันล้มทั้งหมด (หมุนทั้งตัวด้วย Tween + ท่า swing_1, ศัตรูเล่นท่า die_*) วนซ้ำ · min = ภาพนิ่งจังหวะฟัน
## TODO(track B): สร้างฉาก จังหวะวนซ้ำ ~4 วิ ไม่มีงานต่อเฟรมตอน set_active(false)
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
