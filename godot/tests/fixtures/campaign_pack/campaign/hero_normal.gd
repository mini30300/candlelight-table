extends Node3D
## ฉากทดสอบของชุดเสริม (รูปทรงพื้นฐาน): ครบสัญญา setup / set_active

var ctx: Dictionary = {}
var active := false


func setup(c: Dictionary) -> void:
	ctx = c
	var cam := Camera3D.new()
	add_child(cam)
	cam.current = true
	var mi := MeshInstance3D.new()
	mi.mesh = CapsuleMesh.new()
	add_child(mi)


func set_active(on: bool) -> void:
	active = on
