extends Node3D
## ฉากทดสอบที่พัง: setup เจอข้อผิดพลาดระหว่างทำงาน (ยังไม่ทันสร้างกล้อง) · เวทีต้องไม่ล่ม ใช้ฉากในตัวแทน


func setup(c: Dictionary) -> void:
	var parts: Array = c.get("missing_parts", [])
	var first: Node3D = parts[3]
	add_child(first)
	var cam := Camera3D.new()
	add_child(cam)
	cam.current = true


func set_active(_on: bool) -> void:
	pass
