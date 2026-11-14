class_name HeroKit
extends RefCounted
## ของใช้ร่วมของฉากโชว์ในตัว (CAMPAIGN_SPEC §3.2–§3.3): กล้องจัดกรอบได้ทั้ง 16:9 และแนวตั้ง ฉากหลังไล่เฉด แสงฟุ้ง ขอบแสง
## และตัวละครจากชุดโมเดลที่เดินท่าเอง (manual: ฉากเรียก step ทีละเฟรม ไม่ทำงานเองตอนหยุด) · ไม่มีชุดโมเดล = ไข่ของ KitBeast
## ฉากชุดเสริมไม่ต้องใช้ไฟล์นี้

const BACKDROP := preload("res://scenes/campaign/hero_backdrop.gdshader")
const GLOW := preload("res://scenes/campaign/hero_glow.gdshader")
const RIM := preload("res://scenes/campaign/hero_rim.gdshader")
const SHADE := preload("res://scenes/campaign/hero_shade.gdshader")
const STEP := 1.0 / 30.0
const MIN_EYE_Y := 0.1           # กล้องฉากโชว์สูงจากพื้นอย่างน้อย (ม.)
## ระดับท่าของตัวละครในฉาก: ฉากเดินท่าเองทุกระดับ (min = ฉากวาดภาพนิ่งครั้งเดียวแล้วทิ้ง)
const FIG_LEVEL := "mid"


## กล้องของฉาก (current) · fov แนวตั้งเมื่อการ์ดกว้าง แนวนอนเมื่อการ์ดตั้ง (§3.2)
static func camera(root: Node3D, fov: float) -> Camera3D:
	var cam := Camera3D.new()
	cam.name = "Camera"
	cam.fov = fov
	cam.near = 0.05
	cam.far = 80.0
	root.add_child(cam)
	cam.current = true
	return cam


## วางกล้องให้กล่อง (ครึ่งกว้าง half.x, ครึ่งสูง half.y) รอบ centre อยู่ในกรอบ มองจากทิศ dir
static func frame(cam: Camera3D, centre: Vector3, half: Vector2, aspect: float, dir: Vector3) -> void:
	aspect = maxf(aspect, 0.2)
	cam.keep_aspect = Camera3D.KEEP_HEIGHT if aspect >= 1.0 else Camera3D.KEEP_WIDTH
	var t := tan(deg_to_rad(cam.fov * 0.5))
	var tv := t if aspect >= 1.0 else t / aspect
	var th := t * aspect if aspect >= 1.0 else t
	var dist := maxf(half.y / tv, half.x / th)
	var eye := centre + dir.normalized() * dist
	# กล้องต่ำมองเงยถอยไกล (การ์ดเกือบจัตุรัส) ห้ามลงใต้พื้น: ยกขึ้นแล้วเล็งกลางเดิม
	eye.y = maxf(eye.y, MIN_EYE_Y)
	cam.transform = Transform3D(Basis.looking_at(centre - eye, Vector3.UP), eye)


## โลกของฉาก: สีพื้นหลัง (ใต้ฉากหลัง) ambient ของวัสดุมาตรฐาน และหมอก (density 0 = ไม่มี)
static func environment(root: Node3D, bg: Color, fog_colour := Color.BLACK, fog_density := 0.0) -> Environment:
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = bg
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.3, 0.3, 0.32)
	if fog_density > 0.0:
		env.fog_enabled = true
		env.fog_mode = Environment.FOG_MODE_EXPONENTIAL
		env.fog_light_color = fog_colour
		env.fog_density = fog_density
		env.fog_sky_affect = 0.0
	var we := WorldEnvironment.new()
	we.name = "Env"
	we.environment = env
	root.add_child(we)
	return env


## ฉากหลังติดกล้อง (สี่เหลี่ยมใหญ่หลังทุกอย่าง) ไล่เฉด top → bottom + แสงฟุ้งที่ at (uv จอ)
static func backdrop(cam: Camera3D, top: Color, bottom: Color, glow: Color, at: Vector2, r: float, vignette := 0.6) -> MeshInstance3D:
	var mat := ShaderMaterial.new()
	mat.shader = BACKDROP
	mat.set_shader_parameter("top_colour", _v(top))
	mat.set_shader_parameter("bottom_colour", _v(bottom))
	mat.set_shader_parameter("glow_colour", _v(glow))
	mat.set_shader_parameter("glow_at", at)
	mat.set_shader_parameter("glow_r", r)
	mat.set_shader_parameter("vignette", vignette)
	var q := QuadMesh.new()
	var d := cam.far * 0.8
	q.size = Vector2(d * 6.0, d * 6.0)
	var mi := MeshInstance3D.new()
	mi.name = "Backdrop"
	mi.mesh = q
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.position = Vector3(0.0, 0.0, -d)
	cam.add_child(mi)
	return mi


## แสงฟุ้งแบบบวกสี บนสี่เหลี่ยม size (mode: 0 วงกลม 2 แถบหมอก 3 วงแหวน) · flat = วางราบกับพื้น
static func glow(parent: Node3D, mode: int, colour: Color, strength: float, size: Vector2, flat := false) -> MeshInstance3D:
	var q := QuadMesh.new()
	q.size = size
	if flat:
		q.orientation = PlaneMesh.FACE_Y
	var mi := MeshInstance3D.new()
	mi.mesh = q
	mi.material_override = glow_mat(mode, colour, strength)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mi)
	return mi


## ลำแสงทรงกรวยจากบนลงล่าง (ไม่มีฝา) ยอดอยู่ที่ top
static func cone(parent: Node3D, top: Vector3, top_r: float, bottom_r: float, h: float, colour: Color, strength: float) -> MeshInstance3D:
	var c := CylinderMesh.new()
	c.top_radius = top_r
	c.bottom_radius = bottom_r
	c.height = h
	c.radial_segments = 24
	c.rings = 1
	c.cap_top = false
	c.cap_bottom = false
	var mi := MeshInstance3D.new()
	mi.name = "Shaft"
	mi.mesh = c
	mi.material_override = glow_mat(1, colour, strength)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.position = top - Vector3(0.0, h * 0.5, 0.0)
	parent.add_child(mi)
	return mi


static func glow_mat(mode: int, colour: Color, strength: float) -> ShaderMaterial:
	var mat := ShaderMaterial.new()
	mat.shader = GLOW
	mat.set_shader_parameter("mode", mode)
	mat.set_shader_parameter("colour", _v(colour))
	mat.set_shader_parameter("strength", strength)
	return mat


## ขอบแสงบนทุกเมชของ fig ที่ยังไม่มี overlay ของตัวเอง · คืนวัสดุ (ฉากปรับ strength ได้)
## เมชที่ไม่คิดแสง (ไข่) ได้เงาจากทิศ light ด้วย (overlay คูณสี แล้วขอบแสงต่อเป็น next_pass)
static func rim(fig: Node, colour: Color, power: float, strength: float, side := Vector3.ZERO,
		light := Vector3(0.0, 1.0, 0.15)) -> ShaderMaterial:
	var mat := ShaderMaterial.new()
	mat.shader = RIM
	mat.set_shader_parameter("colour", _v(colour))
	mat.set_shader_parameter("power", power)
	mat.set_shader_parameter("strength", strength)
	mat.set_shader_parameter("side", side)
	var shade: ShaderMaterial = null
	for mi in meshes(fig):
		if mi.material_overlay != null:
			continue
		if _unshaded(mi):
			if shade == null:
				shade = ShaderMaterial.new()
				shade.shader = SHADE
				shade.set_shader_parameter("light_dir", light)
				shade.next_pass = mat
			mi.material_overlay = shade
		else:
			mi.material_overlay = mat
	return mat


static func _unshaded(mi: MeshInstance3D) -> bool:
	var m := mi.material_override
	if m == null and mi.mesh != null and mi.mesh.get_surface_count() > 0:
		m = mi.get_active_material(0)
	return m is BaseMaterial3D and (m as BaseMaterial3D).shading_mode == BaseMaterial3D.SHADING_MODE_UNSHADED


## ตัวละครจากชุดโมเดลตัวแรกที่มีใน kits (kind "fighter" = KitFighter มีท่าฟัน, "walker" = KitWalker ทาชุดสีได้,
## อื่น ๆ = KitBeast) ยังไม่ setup: ใส่ในฉากก่อนแล้วเรียก setup_figure
static func kit_figure(kits: PackedStringArray, kind: String) -> KitBeast:
	var kit := ""
	for k in kits:
		if KitLibrary.has_kit(k):
			kit = k
			break
	var fig: KitBeast
	match kind:
		"fighter":
			var f := KitFighter.new()
			f.walk_kit = kit
			fig = f
		"walker":
			var w := KitWalker.new()
			w.walk_kit = kit
			fig = w
		_:
			fig = KitBeast.new()
			fig.set_meta(&"kit", kit)
	fig.name = "Fig_" + (kit if kit != "" else "egg")
	return fig


## setup แบบเดินท่าเอง (manual) แล้ววางท่าแรกทันที
static func setup_figure(fig: Node3D, seed: int) -> void:
	var opts := {"role": &"deck", "level": FIG_LEVEL, "seed": seed, "manual": true,
		"team_colour": Color(0.28, 0.52, 0.84)}
	if fig.has_meta(&"kit"):
		opts["kit"] = str(fig.get_meta(&"kit"))
	fig.call("setup", opts)
	if fig.has_method("step"):
		fig.call("step", 0.0)


## ทาชุดสี (H10) ถ้าตัวนั้นรับ
static func paint(fig: Node, primary: Color, secondary: Color) -> void:
	if fig != null and fig.has_method("apply_scheme"):
		fig.call("apply_scheme", primary, secondary)


## ความสูงของข้อต่อหัวเทียบกับ root (ท่าพักของโครง) · ไม่มีโครงใช้ metrics().eye · ไม่มีเลย 1.5
static func head_y(fig: Node3D, root: Node3D) -> float:
	if fig.has_method("skeleton"):
		var sk: Skeleton3D = fig.call("skeleton")
		if sk != null:
			var i := sk.find_bone("head")
			if i >= 0:
				return (rel_xform(sk, root) * sk.get_bone_global_rest(i).origin).y
	if fig.has_method("metrics"):
		var m: Variant = fig.call("metrics")
		if m is Dictionary and (m as Dictionary).has("eye"):
			return (rel_xform(fig, root) * Vector3(0.0, float(m["eye"]), 0.0)).y
	return 1.5


## ทรานส์ฟอร์มของ n เทียบกับ ancestor (ไม่ต้องอยู่ในต้นไม้ฉาก)
static func rel_xform(n: Node, ancestor: Node) -> Transform3D:
	var t := Transform3D.IDENTITY
	var cur: Node = n
	while cur != null and cur != ancestor:
		if cur is Node3D:
			t = (cur as Node3D).transform * t
		cur = cur.get_parent()
	return t


## กล่องของเมชทั้งหมดใต้ root ในพิกัดของ root (ไม่มีเมช = AABB ว่าง)
static func box(root: Node3D) -> AABB:
	var out := AABB()
	var first := true
	for mi in meshes(root):
		if mi.mesh == null or not mi.visible:
			continue
		var b: AABB = rel_xform(mi, root) * mi.get_aabb()
		out = b if first else out.merge(b)
		first = false
	return out


static func meshes(root: Node) -> Array[MeshInstance3D]:
	var out: Array[MeshInstance3D] = []
	if root == null:
		return out
	var stack: Array[Node] = [root]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		if n is MeshInstance3D:
			out.append(n)
		stack.append_array(n.get_children())
	return out


## ไฟทิศเดียวให้วัสดุมาตรฐาน (พื้น ของประกอบ) · ตัวละครใช้ HeroLight
static func sun(root: Node3D, dir: Vector3, colour: Color, energy := 1.0) -> DirectionalLight3D:
	var l := DirectionalLight3D.new()
	l.name = "Sun"
	l.light_color = colour
	l.light_energy = energy
	l.shadow_enabled = false
	root.add_child(l)
	l.transform = Transform3D(Basis.looking_at(-dir.normalized(), Vector3.UP if absf(dir.normalized().y) < 0.99 else Vector3.BACK), Vector3.ZERO)
	return l


## พื้นวงกลมมืดแบบมีแสง (วัสดุมาตรฐาน) รัศมี r
static func floor_disc(root: Node3D, r: float, colour: Color, rough := 0.35) -> MeshInstance3D:
	var c := CylinderMesh.new()
	c.top_radius = r
	c.bottom_radius = r
	c.height = 0.04
	c.radial_segments = 40
	c.rings = 1
	var mat := StandardMaterial3D.new()
	mat.albedo_color = colour
	mat.roughness = rough
	mat.metallic = 0.3
	c.material = mat
	var mi := MeshInstance3D.new()
	mi.name = "Floor"
	mi.mesh = c
	mi.position.y = -0.02
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(mi)
	return mi


static func _v(c: Color) -> Vector3:
	return Vector3(c.r, c.g, c.b)
