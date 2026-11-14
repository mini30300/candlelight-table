extends Node3D
## ฉากในตัวของ "ภัยพิบัติ": อัศวินทรยศและปีศาจของโต๊ะรบ (ชุด cx*/dm*) ปรากฏเรียงแถวทีละตัวแบบฉากอนิเมะที่นักสู้นึกถึงศัตรูทุกตัว
## ไฟขอบแดงเข้ม หมอก (hi/mid) · AudioStreamPlayer เล่น CampaignHeroes.music_path() ถ้ามี (ไฟล์เพลงที่มินิจะส่งมา) · min = แถวนิ่ง
## TODO(track B): แถว 7 ตัว (dmc cxp cxb cxl cxs cxw dmr) cxl อยู่กลาง ปรากฏทีละตัว ~0.35 วิ เพลงหยุดเมื่อ set_active(false)
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
