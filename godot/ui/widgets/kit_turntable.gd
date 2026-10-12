class_name KitTurntable
extends SubViewportContainer
## ดูหน้าตาหน่วยแบบแท่นหมุน: ฟิกเกอร์ตัวเดียวจากชุดโมเดล (assets/kits) สีของชุดเอง ไม่ย้อมสีทีม หมุนช้า ๆ
## อยู่ใน SubViewport ที่มีโลกของตัวเอง (ไม่เห็นโต๊ะ โต๊ะก็ไม่เห็นตัวนี้) · ลากซ้าย/ขวาเพื่อหมุนเอง
## ระดับ min: ไม่หมุนเอง ไม่มีงานต่อเฟรม วาดใหม่ครั้งเดียวเมื่อเปลี่ยนตัวหรือถูกลาก (AGENTS ข้อ 6)
## ซ่อนอยู่ก็ไม่วาดและไม่หมุน

signal kit_shown(kit: String)

## ความเร็วหมุน (เรเดียน/วินาที) — ราว 18 วินาทีต่อรอบ
const SPIN := 0.35
const DRAG_TURN := 0.012
const FOV := 30.0
const PITCH_DEG := 16.0
## ที่ว่างรอบตัวในกรอบ (1 = ชิดขอบ)
const MARGIN := 1.12
const BG := Color(0.075, 0.066, 0.09)
const PLINTH := Color(0.2, 0.185, 0.23)
const PLINTH_RIM := Color(0.62, 0.5, 0.3)

var kit := ""
var spinning := false
var yaw := 0.55
var level := "mid"
var manifest: Dictionary = {}

var _vp: SubViewport
var _cam: Camera3D
var _pivot: Node3D
var _figure: Node3D
var _plinth: MeshInstance3D
var _rim: MeshInstance3D
var _box := AABB()
var _dragging := false


func _ready() -> void:
	stretch = true
	mouse_filter = Control.MOUSE_FILTER_STOP
	_vp = SubViewport.new()
	_vp.name = "View"
	_vp.own_world_3d = true
	_vp.transparent_bg = false
	_vp.msaa_3d = Viewport.MSAA_DISABLED
	_vp.handle_input_locally = false
	_vp.render_target_update_mode = SubViewport.UPDATE_ONCE
	add_child(_vp)
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = BG
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.55, 0.55, 0.6)
	var we := WorldEnvironment.new()
	we.environment = env
	_vp.add_child(we)
	var sun := DirectionalLight3D.new()
	sun.rotation = Vector3(deg_to_rad(-55.0), deg_to_rad(35.0), 0.0)
	sun.shadow_enabled = false
	_vp.add_child(sun)
	_cam = Camera3D.new()
	_cam.fov = FOV
	_cam.near = 0.05
	_cam.far = 500.0
	_cam.current = true
	_vp.add_child(_cam)
	_pivot = Node3D.new()
	_pivot.name = "Pivot"
	_vp.add_child(_pivot)
	_plinth = _disc(PLINTH, 1.0)
	_rim = _disc(PLINTH_RIM, 1.0)
	_vp.add_child(_rim)
	_vp.add_child(_plinth)
	resized.connect(_frame)
	visibility_changed.connect(_apply_mode)
	set_level(level)


## ระดับกราฟิก: min ไม่หมุนเอง (วาดครั้งเดียว) ระดับอื่นหมุนช้า ๆ
func set_level(l: String) -> void:
	level = l
	spinning = l != "min"
	_apply_mode()


## แสดงชุดโมเดลชื่อ name; ไม่มีไฟล์ชุดก็ว่างเปล่า (คืน false)
func show_kit(name: String) -> bool:
	if name == kit and _figure != null:
		return true
	_clear_figure()
	kit = name
	if _vp == null or not KitLibrary.has_kit(name):
		_redraw()
		kit_shown.emit(kit)
		return false
	var res: Resource = load(KitLibrary.kit_path(name))
	if not (res is PackedScene):
		_redraw()
		kit_shown.emit(kit)
		return false
	var inst := (res as PackedScene).instantiate()
	if not (inst is Node3D):
		inst.free()
		_redraw()
		kit_shown.emit(kit)
		return false
	_figure = inst as Node3D
	_box = KitLibrary.bounds(manifest, name)
	if _box.size == Vector3.ZERO:
		_box = _mesh_box(_figure)
	# หมุนรอบแกนตั้งที่ผ่านกลางฐาน
	var c := _box.get_center()
	_figure.position = Vector3(-c.x, 0.0, -c.z)
	_pivot.add_child(_figure)
	_frame()
	kit_shown.emit(kit)
	return true


func has_figure() -> bool:
	return _figure != null


## มุมหมุนปัจจุบันของแท่น (เรเดียน) — ใช้ในเทส
func turn() -> float:
	return _pivot.rotation.y if _pivot != null else 0.0


func viewport() -> SubViewport:
	return _vp


func _process(delta: float) -> void:
	if spinning and _figure != null:
		yaw = fmod(yaw + SPIN * delta, TAU)
		_pivot.rotation.y = yaw


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and (event as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT:
		_dragging = (event as InputEventMouseButton).pressed
		accept_event()
	elif event is InputEventMouseMotion and _dragging:
		yaw = fmod(yaw + (event as InputEventMouseMotion).relative.x * DRAG_TURN, TAU)
		if _pivot != null:
			_pivot.rotation.y = yaw
		_redraw()
		accept_event()


## วางกล้องให้เห็นทั้งตัว (กล่องขอบเขตเป็นทรงกลม) แล้ววาดใหม่
func _frame() -> void:
	if _cam == null:
		return
	var box := _box if _box.size != Vector3.ZERO else AABB(Vector3(-0.4, 0.0, -0.4), Vector3(0.8, 1.8, 0.8))
	var half := box.size * 0.5
	var foot := maxf(0.45, Vector2(half.x, half.z).length() * 1.08)
	_plinth.scale = Vector3(foot, 1.0, foot)
	_rim.scale = Vector3(foot * 1.05, 1.0, foot * 1.05)
	_plinth.position = Vector3(0.0, -0.035, 0.0)
	_rim.position = Vector3(0.0, -0.06, 0.0)
	# ระยะกล้องให้ทั้งความสูงและความกว้าง (วงที่หมุนผ่าน = แท่น) พอดีกรอบ บวกระยะเผื่อด้านที่หันเข้าหากล้อง
	_cam.keep_aspect = Camera3D.KEEP_HEIGHT
	var aspect := size.x / size.y if size.y > 0.0 else 1.0
	var tan_v := tan(deg_to_rad(FOV * 0.5))
	var tan_h := tan_v * maxf(aspect, 0.2)
	var tall := half.y + 0.12
	var dist := maxf(tall / tan_v, foot / tan_h) * MARGIN + foot * 0.6
	var pitch := deg_to_rad(PITCH_DEG)
	var look := Vector3(0.0, box.position.y + half.y - 0.04, 0.0)
	var eye := look + Vector3(0.0, sin(pitch), cos(pitch)) * dist
	_cam.transform = Transform3D(Basis.looking_at(look - eye, Vector3.UP), eye)
	_cam.far = dist + (foot + tall) * 4.0
	if _pivot != null:
		_pivot.rotation.y = yaw
	_redraw()


func _apply_mode() -> void:
	if _vp == null:
		return
	var run := spinning and is_visible_in_tree()
	set_process(run)
	if run:
		_vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	elif is_visible_in_tree():
		_vp.render_target_update_mode = SubViewport.UPDATE_ONCE
	else:
		_vp.render_target_update_mode = SubViewport.UPDATE_DISABLED


## ขอวาดใหม่หนึ่งครั้ง (เมื่อไม่ได้หมุนอยู่)
func _redraw() -> void:
	if _vp != null and not (spinning and is_visible_in_tree()) and is_visible_in_tree():
		_vp.render_target_update_mode = SubViewport.UPDATE_ONCE


func _clear_figure() -> void:
	if _figure != null:
		_figure.get_parent().remove_child(_figure)
		_figure.queue_free()
		_figure = null
	_box = AABB()


func _disc(colour: Color, radius: float) -> MeshInstance3D:
	var m := CylinderMesh.new()
	m.top_radius = radius
	m.bottom_radius = radius
	m.height = 0.07
	m.radial_segments = 40
	m.rings = 1
	var mat := StandardMaterial3D.new()
	mat.albedo_color = colour
	mat.roughness = 0.85
	m.material = mat
	var mi := MeshInstance3D.new()
	mi.mesh = m
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return mi


static func _mesh_box(root: Node) -> AABB:
	var box := AABB()
	var first := true
	var stack: Array[Node] = [root]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		if n is MeshInstance3D and (n as MeshInstance3D).mesh != null:
			var b := (n as MeshInstance3D).get_aabb()
			box = b if first else box.merge(b)
			first = false
		for c in n.get_children():
			stack.append(c)
	return box
