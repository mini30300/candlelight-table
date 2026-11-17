extends Node3D
## ฉากทดสอบที่พัง: มีเมธอดครบแต่ setup ไม่สร้างกล้อง (เวทีต้องทิ้งแล้วใช้ฉากในตัว)


func setup(_c: Dictionary) -> void:
	var mi := MeshInstance3D.new()
	mi.mesh = BoxMesh.new()
	add_child(mi)


func set_active(_on: bool) -> void:
	pass
