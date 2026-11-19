class_name HeroLight
extends RefCounted
## ไฟของตัวละครในฉากโชว์ (CAMPAIGN_SPEC §3.3): ตั้ง uniform แสงของ figure.gdshader (sun_dir, sun_colour, ambient_colour)
## บนวัสดุของทุกเมชใต้ root · วัสดุที่มาจากไฟล์ (ใช้ร่วมกันหลายตัว) ทำสำเนาก่อน จึงไม่ไปเปลี่ยนตัวอื่นนอกฉาก
## วัสดุที่ตัวละครสร้างเอง (KitBeast duplicate แล้ว) ตั้งตรง ๆ · วัสดุอื่น (ไข่ ตัวชุดเสริมที่คิดแสงเอง) ไม่แตะ
## per_pixel: คิดแสงต่อพิกเซล (ฉากโชว์มีไม่กี่ตัว และ min วาดครั้งเดียวเป็นภาพนิ่ง)

const SHADER := "res://assets/shaders/figure.gdshader"


## คืนจำนวนวัสดุที่ตั้งค่า (นับไม่ซ้ำ) · ตัวที่คิดแสงเองด้วยวัสดุของตัวเอง (ทหาร) รับไฟผ่าน set_light ของมัน
static func apply(root: Node, sun_dir: Vector3, sun: Color, ambient: Color, per_pixel := true) -> int:
	if root == null:
		return 0
	if root.has_method("set_light"):
		root.call("set_light", sun_dir, sun, ambient, per_pixel)
		return 1
	var done := {}
	var copies := {}
	var stack: Array[Node] = [root]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		stack.append_array(n.get_children())
		if not n is MeshInstance3D:
			continue
		var mi := n as MeshInstance3D
		var m := _figure_mat(mi.material_override)
		if m != null:
			m = _own(m, copies)
			mi.material_override = m
			_assign(m, sun_dir, sun, ambient, per_pixel)
			done[m] = true
		if mi.mesh == null:
			continue
		for s in mi.get_surface_override_material_count():
			var sm := _figure_mat(mi.get_surface_override_material(s))
			if sm == null:
				continue
			sm = _own(sm, copies)
			mi.set_surface_override_material(s, sm)
			_assign(sm, sun_dir, sun, ambient, per_pixel)
			done[sm] = true
	return done.size()


static func _figure_mat(m: Material) -> ShaderMaterial:
	if m is ShaderMaterial and (m as ShaderMaterial).shader != null and (m as ShaderMaterial).shader.resource_path == SHADER:
		return m
	return null


## วัสดุจากไฟล์ = ใช้ร่วม: ทำสำเนาครั้งเดียวต่อการเรียก (เมชที่ใช้ร่วมกันได้สำเนาเดียวกัน)
static func _own(m: ShaderMaterial, copies: Dictionary) -> ShaderMaterial:
	if m.resource_path == "":
		return m
	if not copies.has(m):
		copies[m] = m.duplicate()
	return copies[m]


static func _assign(m: ShaderMaterial, sun_dir: Vector3, sun: Color, ambient: Color, per_pixel: bool) -> void:
	m.set_shader_parameter("sun_dir", sun_dir)
	m.set_shader_parameter("sun_colour", Vector3(sun.r, sun.g, sun.b))
	m.set_shader_parameter("ambient_colour", Vector3(ambient.r, ambient.g, ambient.b))
	if per_pixel:
		m.set_shader_parameter("per_vertex", false)
