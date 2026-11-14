extends Node3D
## ฉากในตัวของ "ธรรมดา": ตัวผู้เล่นตามที่แต่งตัวอยู่ (ArenaActors.player_figure(ctx.sel) + ชุดสี) ซูมครึ่งบน หันหน้าเข้ากล้อง
## ฉากหลังดำ/เทาเงามืด ไฟส่องจากเหนือศีรษะ (sun_dir ของ figure.gdshader ชี้ขึ้น ambient ต่ำ) · min = ท่านิ่งท่าเดียว
## TODO(track B): สร้างตัว กล้อง ฉากหลังไล่เฉด ท่ายืนเท่ (idle ช้า ๆ บน hi/mid) จัดกรอบให้ได้ทั้ง 16:9 และจอแนวตั้ง
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
