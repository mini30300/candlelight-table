extends SceneTree
## R1-V5 sample: ONE gothic ruin building (our own design) for the owner to judge before the whole set is made.
## Assembles a two-storey ruin from tools/ruin_kit.gd inside the rules footprint of a 'building'
## (FieldProps.bld_size at s = 1000, h = 45000), as two meshes, one MeshInstance3D per LOD:
##   hi <= 6,000 triangles (cut-out pointed-arch windows, rose window, fluted pillars, mouldings)
##   lo <= 1,500 triangles (solid walls with dark window quads, fewer flutes and pieces)
## saves them as assets/props/ruin/sample_building_hi.res / _lo.res and renders them with the app's sun and ambient
## (scenes/battle_table.tscn Sun, the ruin theme sky; Compatibility renderer) into tests/out/ruin_sample_front.png,
## _corner.png, _top.png and _lo.png (1280x720; TEST_OUT, an absolute folder, replaces tests/out):
##   timeout 900 xvfb-run -a -s "-screen 0 1280x720x24" <godot> --path godot --rendering-driver opengl3 \
##       --resolution 1280x720 --audio-driver Dummy -s tools/ruin_sample.gd
## With --headless it only builds, checks and saves the meshes. Exit code 1 when a budget or the footprint fails.

const Kit := preload("res://tools/ruin_kit.gd")

## seed ของสนามที่ bld_size(s = 1000, h = 45000) ได้ 9.81 x 8.04 ม. (ใกล้ 10 x 8 ที่ขอ)
const FIELD_SEED := 30
const S_PERMILLE := 1000
const H_Q16 := 45000
const PAD := 0.6                 # foot_of ปรับพื้นเผื่อรอบตึก 0.6 ม.
const HI_BUDGET := 6000
const LO_BUDGET := 1500
const T := 0.45                  # ความหนาผนัง
const FLOOR_TOP := 4.6           # ผิวพื้นชั้นบน
const FLOOR_T := 0.3
const RES_DIR := "res://assets/props/ruin"
const DEFAULT_OUT_DIR := "res://tests/out"
const SCENE := "res://scenes/battle_table.tscn"
const SKY_PATH := "res://data/sky.json"
const THEMES_PATH := "res://data/themes.json"
const SETTLE := 8

## มุมกล้อง: [ชื่อไฟล์, ตำแหน่ง, จุดมอง, lod]
const SHOTS := [
	["front", Vector3(0.0, 3.3, 16.5), Vector3(0.0, 4.3, 0.0), 0],
	["corner", Vector3(12.6, 7.6, 12.2), Vector3(0.2, 3.3, 0.2), 0],
	["top", Vector3(5.5, 17.5, 9.0), Vector3(-0.4, 2.4, -0.4), 0],
	["lo", Vector3(12.6, 7.6, 12.2), Vector3(0.2, 3.3, 0.2), 1],
]

## ข้อความบนภาพ (ทุกข้อความมีคู่ภาษาอังกฤษใน ui/i18n_extra.json; tests/unit/test_ruin_kit.gd ตรวจ)
const CAPTIONS: PackedStringArray = ["ตัวอย่างตึกซากโกธิก (แบบของเราเอง)", "ด้านหน้า", "มุมเฉียง", "มองจากบน",
	"แบบหยาบ lo สำหรับระยะไกลและเครื่องเล็ก", "แบบละเอียด hi", "{n} สามเหลี่ยม", "รอยเท้าตามกติกา {w} × {d} ม. สูง {h} ม.",
	"ฟิกเกอร์สูงราว 1.7 ม. ไว้เทียบขนาด"]

var _out_dir := DEFAULT_OUT_DIR
var _failed := 0
var _cam: Camera3D
var _sun: DirectionalLight3D
var _meshes: Array[MeshInstance3D] = []
var _materials: Array[StandardMaterial3D] = []
var _caption: Label
var _info: Array[Dictionary] = []
var _shot := -1
var _frame := 0
var _figures_note := false


func _initialize() -> void:
	var env := OS.get_environment("TEST_OUT")
	if env != "" and env.is_absolute_path():
		_out_dir = env
	var foot := footprint()
	print("footprint: FieldProps.bld_size(seed %d, s = %d, h = %d) = %d x %d MI -> %.3f x %.3f m (pad %.1f m)" % [
		FIELD_SEED, S_PERMILLE, H_Q16, int(foot.x * 1000.0 + 0.5), int(foot.y * 1000.0 + 0.5), foot.x, foot.y, PAD])
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(RES_DIR))
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(_out_dir))
	for level in 2:
		var b := build_mesh(level)
		_info.append(b)
		var name := "hi" if level == 0 else "lo"
		var budget := HI_BUDGET if level == 0 else LO_BUDGET
		var box: AABB = b["aabb"]
		print("%s: %d triangles (budget %d), %d surface, aabb %s .. %s" % [name, int(b["tris"]), budget,
			(b["mesh"] as ArrayMesh).get_surface_count(), str(box.position), str(box.end)])
		_check(int(b["tris"]) <= budget, "%s within %d triangles (%d)" % [name, budget, int(b["tris"])])
		_check(fits(box, foot), "%s inside the footprint + %.1f m pad" % [name, PAD])
		var path := RES_DIR + "/sample_building_%s.res" % name
		var err := ResourceSaver.save(b["mesh"], path, ResourceSaver.FLAG_COMPRESS)
		_check(err == OK, "saved " + path)
	if DisplayServer.get_name() == "headless":
		print("headless: meshes built and saved, no renders")
		_finish()
		return
	_stage()
	_shot = 0
	_frame = 0
	_apply_shot()


func _process(_delta: float) -> bool:
	if _shot < 0:
		return false
	_frame += 1
	if _frame < SETTLE:
		return false
	var name: String = SHOTS[_shot][0]
	var img := root.get_texture().get_image()
	var path := _out_dir.path_join("ruin_sample_%s.png" % name)
	var err := img.save_png(ProjectSettings.globalize_path(path) if path.begins_with("res://") else path)
	_check(err == OK and img.get_width() == 1280 and img.get_height() == 720, "rendered %s (%dx%d)" % [path, img.get_width(), img.get_height()])
	_shot += 1
	if _shot >= SHOTS.size():
		_finish()
		return true
	_frame = 0
	_apply_shot()
	return false


func _finish() -> void:
	print("%s  %d failed" % ["PASS " if _failed == 0 else "FAIL ", _failed])
	quit(0 if _failed == 0 else 1)


func _check(ok: bool, msg: String) -> void:
	print(("ok    " if ok else "FAIL  ") + msg)
	if not ok:
		_failed += 1


# ---- รอยเท้าตามกติกา ----

## ขนาดตึก (กว้าง x, ลึก z) เป็นเมตรจาก core/field/props.gd (อ่านอย่างเดียว)
static func footprint() -> Vector2:
	var p := FieldProps.new()
	p.seed_value = FIELD_SEED
	var b := p.bld_size({"kind": "building", "x": 0, "z": 0, "rot": 0, "s": S_PERMILLE, "h": H_Q16, "rad": 7000})
	return Vector2(b[0] / 1000.0, b[1] / 1000.0)


## กล่องของเมชอยู่ในรอยเท้า + ที่เผื่อปรับพื้นหรือไม่ (เศษซากล้นได้ไม่เกิน PAD)
static func fits(box: AABB, foot: Vector2) -> bool:
	var hx := foot.x * 0.5 + PAD + 0.001
	var hz := foot.y * 0.5 + PAD + 0.001
	return box.position.x >= -hx and box.end.x <= hx and box.position.z >= -hz and box.end.z <= hz


# ---- ตัวตึก ----

## ประกอบตึกตัวอย่างหนึ่งหลังที่ระดับ level (0 = hi, 1 = lo): {mesh, tris, aabb}
static func build_mesh(level: int) -> Dictionary:
	var k: Kit = Kit.new(level)
	assemble(k, footprint())
	var mesh: ArrayMesh = k.commit(Kit.make_material())
	return {"mesh": mesh, "tris": k.tris, "aabb": k.aabb}


## วางทุกชิ้นของตึก: หน้าตึกหัน +z ผนังสี่ด้านหักไม่เท่ากัน ชั้นบนเหลือแผ่นพื้นซีกซ้ายบนคาน บันไดมุมขวาหลัง
## รูปปั้นในซุ้มซ้ายของหน้าตึก กองซากหน้าขวา แผ่นเหล็กสนิมกับท่อด้านขวา
static func assemble(k: Kit, foot: Vector2) -> void:
	var hw := foot.x * 0.5
	var hd := foot.y * 0.5
	var xs := hw - 0.85                 # แกนผนังข้าง
	var xo := xs + T * 0.5              # ผิวนอกผนังข้าง
	var xi := xs - T * 0.5              # ผิวใน
	var zf := hd - 0.82                 # แกนผนังหน้า
	var zfo := zf + T * 0.5
	var zfi := zf - T * 0.5
	var zb := -(hd - 0.4)               # แกนผนังหลัง
	var zbo := zb - T * 0.5
	var zbi := zb + T * 0.5
	_front(k, xo, zf, zfo, zfi)
	_left(k, xs, xo, zbo, zfi)
	_back(k, xi, zb)
	_right(k, xs, xo, zbo, zfi)
	_upper_floor(k, xi, zbi, zfi)
	_stair(k, xi, zbi)
	# พื้นชั้นล่างในตึก
	k.xf = Transform3D.IDENTITY
	k.slab(PackedVector2Array([Vector2(-xi - 0.02, zbi - 0.02), Vector2(xi + 0.02, zbi - 0.02), Vector2(xi + 0.02, zfi + 0.02),
		Vector2(-xi - 0.02, zfi + 0.02)]), 0.06, 0.36, Kit.FLOOR)
	_rubble(k, hw, hd, xo, zfo)


## ผนังหน้า: ซุ้มรูปปั้นซ้าย ประตูโค้งแหลมกลาง หน้าต่างขวา ชั้นบนหน้าต่างกุหลาบกลางกับหน้าต่างแหลมสองข้าง
## ยอดซ้ายสูงเป็นจั่ว ซีกขวาหักลงเป็นขั้นจนทะลุหน้าต่างบนขวา
static func _front(k: Kit, xo: float, zf: float, zfo: float, zfi: float) -> void:
	var lf := xo * 2.0
	var u := func(x: float) -> float: return x + xo
	k.seed_piece(11)
	var top := PackedVector2Array([Vector2(0.0, 8.75), Vector2(0.8, 8.75)])
	top.append_array(k.steps(Vector2(0.8, 8.75), Vector2(2.75, 8.02), 3, 0.12))
	top.append_array(PackedVector2Array([Vector2(3.0, 8.02), Vector2(4.15, 9.3), Vector2(4.4, 9.3)]))
	top.append_array(k.steps(Vector2(4.4, 9.3), Vector2(5.7, 7.98), 3, 0.12))
	top.append_array(k.steps(Vector2(5.7, 7.98), Vector2(6.3, 7.2), 2, 0.1))
	top.append_array(k.steps(Vector2(6.3, 7.2), Vector2(7.6, 5.9), 3, 0.15))
	top.append_array(k.steps(Vector2(7.6, 5.9), Vector2(lf, 5.3), 2, 0.12))
	var niche: PackedVector2Array = k.arch_hole(u.call(-2.65), 1.3, 0.55, 2.7, 1.0)
	var holes := [
		{"poly": niche, "open_lo": true},
		{"poly": k.arch_hole(u.call(0.0), 1.7, -0.6, 2.6, 0.8), "open_lo": true},
		{"poly": k.arch_hole(u.call(2.65), 1.2, 0.9, 2.75, 1.0)},
		{"poly": k.arch_hole(u.call(-2.65), 1.0, 5.3, 6.6, 1.1)},
		{"poly": k.arch_hole(u.call(2.65), 1.0, 5.3, 6.6, 1.1)},
		{"poly": k.circle_hole(u.call(0.0), 6.45, 1.25, 16 if k.hi() else 8)},
	]
	k.xf = Transform3D(Basis.IDENTITY, Vector3(-xo, 0.0, zf))
	k.wall(lf, T, top, holes, Kit.STONE)
	k.niche(niche, -T * 0.5, 0.4)
	k.rose(u.call(0.0), 6.45, 1.25, T)
	var hz := T * 0.5
	k.hood(u.call(-2.65), 1.3, 2.7, 1.0, hz, top)
	k.hood(u.call(0.0), 1.7, 2.6, 0.8, hz, top)
	k.hood(u.call(2.65), 1.2, 2.75, 1.0, hz, top)
	k.hood(u.call(-2.65), 1.0, 6.6, 1.1, hz, top)
	k.hood(u.call(2.65), 1.0, 6.6, 1.1, hz, top)
	k.mullion(u.call(2.65), 0.9, 3.55, T)
	# ชั้นบัวเขียวสนิมที่ระดับพื้นชั้นบน และฐานหินรอบโคน (เว้นประตู)
	k.band(0.0, lf, 4.38, 0.22, hz, 0.12, Kit.TRIM)
	k.band(0.0, u.call(-0.95), -0.4, 0.75, hz, 0.08, Kit.STONE_DARK)
	k.band(u.call(0.95), lf, -0.4, 0.75, hz, 0.08, Kit.STONE_DARK)
	# ธรณีประตู
	k.box(Vector3(u.call(0.0), -0.3, hz + 0.25), 1.05, 0.27, 0.42, Kit.STONE_DARK)
	k.xf = Transform3D.IDENTITY
	# เสาร่องหน้าตึก: มุมซ้ายกับข้างประตูซ้ายสูงครบมีหัวเสา ขวาหักทั้งคู่
	var pz := zfo + 0.04
	k.pillar(Vector3(-4.05, 0.0, pz), 9.15, 0.3, 4, false, 21)
	k.pillar(Vector3(-1.3, 0.0, pz), 8.7, 0.3, 4, false, 22)
	k.pillar(Vector3(1.3, 0.0, pz), 7.4, 0.3, 4, true, 23)
	k.pillar(Vector3(4.05, 0.0, pz), 5.0, 0.3, 3, true, 24)
	# รูปปั้นผู้พิทักษ์ในซุ้ม
	k.statue(Vector3(-2.65, 0.55, zfi + 0.03), 2.5, 0.0)


## ผนังซ้าย (ผิวนอกหัน -x) หน้าต่างแหลมสองชั้นสองช่อง ค้ำยันสองตัว ยอดหักต่ำลงช่วงกลาง
static func _left(k: Kit, xs: float, xo: float, zbo: float, zfi: float) -> void:
	var ls := zfi + 0.025 - zbo
	var u := func(z: float) -> float: return z - zbo
	k.seed_piece(12)
	var top := PackedVector2Array([Vector2(0.0, 6.9)])
	top.append_array(k.steps(Vector2(0.0, 6.9), Vector2(1.3, 7.95), 2, 0.1))
	top.append_array(k.steps(Vector2(1.3, 7.95), Vector2(2.9, 8.05), 2, 0.05))
	top.append_array(k.steps(Vector2(2.9, 8.05), Vector2(3.45, 7.0), 2, 0.15))
	top.append(Vector2(4.05, 7.1))
	top.append_array(k.steps(Vector2(4.05, 7.1), Vector2(4.6, 8.0), 2, 0.1))
	top.append_array(k.steps(Vector2(4.6, 8.0), Vector2(6.1, 8.2), 2, 0.06))
	top.append_array(k.steps(Vector2(6.1, 8.2), Vector2(ls, 8.75), 1, 0.0))
	var holes := []
	for z: float in [-1.75, 1.35]:
		holes.append({"poly": k.arch_hole(u.call(z), 1.1, 1.0, 2.7, 1.0)})
		holes.append({"poly": k.arch_hole(u.call(z), 1.0, 5.3, 6.6, 1.1)})
	k.xf = Transform3D(Basis(Vector3.UP, -PI * 0.5), Vector3(-xs, 0.0, zbo))
	k.wall(ls, T, top, holes, Kit.STONE)
	k.band(0.0, ls, 4.38, 0.22, T * 0.5, 0.1, Kit.TRIM)
	k.xf = Transform3D.IDENTITY
	k.buttress(Vector3(-xo, 0.0, -3.5), -PI * 0.5, 0.7, 0.6, 3.4, 0.38, 6.2)
	k.buttress(Vector3(-xo, 0.0, -0.2), -PI * 0.5, 0.7, 0.6, 3.6, 0.38, 6.0, true)


## ผนังหลัง (ผิวนอกหัน -z): ซีกซ้ายสูงมีหน้าต่างสองชั้น ซีกขวาพังลงเหลือต่ำ
static func _back(k: Kit, xi: float, zb: float) -> void:
	var lb := (xi + 0.025) * 2.0
	var u := func(x: float) -> float: return xi + 0.025 - x
	k.seed_piece(13)
	var top := PackedVector2Array([Vector2(0.0, 3.3)])
	top.append_array(k.steps(Vector2(0.0, 3.3), Vector2(2.6, 2.9), 3, 0.3))
	top.append_array(k.steps(Vector2(2.6, 2.9), Vector2(4.4, 7.2), 4, 0.25))
	top.append_array(k.steps(Vector2(4.4, 7.2), Vector2(5.2, 8.0), 1, 0.0))
	top.append_array(k.steps(Vector2(5.2, 8.0), Vector2(6.5, 7.95), 2, 0.04))
	top.append_array(k.steps(Vector2(6.5, 7.95), Vector2(lb, 6.9), 2, 0.12))
	var holes := [
		{"poly": k.arch_hole(u.call(-2.0), 1.1, 1.0, 2.7, 1.0)},
		{"poly": k.arch_hole(u.call(-2.0), 1.0, 5.3, 6.6, 1.1)},
	]
	k.xf = Transform3D(Basis(Vector3.UP, PI), Vector3(xi + 0.025, 0.0, zb))
	k.wall(lb, T, top, holes, Kit.STONE)
	k.xf = Transform3D.IDENTITY


## ผนังขวา (ผิวนอกหัน +x): หักต่ำ ช่องโหว่ปะด้วยแผ่นเหล็กสนิมแดง ท่อสองเส้นเลียบผนังด้านหลัง
static func _right(k: Kit, xs: float, xo: float, zbo: float, zfi: float) -> void:
	var z0 := zfi + 0.025
	var ls := z0 - zbo
	k.seed_piece(14)
	var top := PackedVector2Array([Vector2(0.0, 5.3), Vector2(0.3, 5.3)])
	top.append_array(k.steps(Vector2(0.3, 5.3), Vector2(1.2, 3.4), 2, 0.2))
	top.append_array(k.steps(Vector2(1.2, 3.4), Vector2(3.0, 2.9), 3, 0.25))
	top.append(Vector2(3.2, 1.75))
	top.append_array(k.steps(Vector2(3.2, 1.75), Vector2(5.2, 1.6), 2, 0.12))
	top.append_array(k.steps(Vector2(5.2, 1.6), Vector2(ls, 3.3), 3, 0.2))
	var holes := [{"poly": k.arch_hole(z0 - 1.0, 1.1, 0.9, 2.4, 1.0)}]
	k.xf = Transform3D(Basis(Vector3.UP, PI * 0.5), Vector3(xs, 0.0, z0))
	k.wall(ls, T, top, holes, Kit.STONE)
	k.xf = Transform3D.IDENTITY
	k.panel(Vector3(xo, 0.15, -1.2), PI * 0.5, 2.3, 2.6)
	var px := xo + 0.15
	k.pipe(PackedVector3Array([Vector3(px, -0.3, -3.2), Vector3(px, 4.4, -3.2)]), 0.12)
	k.pipe(PackedVector3Array([Vector3(px, -0.3, -2.75), Vector3(px, 2.35, -2.75), Vector3(px, 2.35, -2.3)]), 0.12)


## พื้นชั้นบนที่เหลือซีกซ้าย ขอบหักขรุขระ วางบนคานเหล็ก (ปลายคานยื่นพ้นขอบหัก หนึ่งตัวหักห้อย) และเสาร่องกลางห้อง
static func _upper_floor(k: Kit, xi: float, zbi: float, zfi: float) -> void:
	k.xf = Transform3D.IDENTITY
	k.seed_piece(15)
	var x0 := -xi - 0.12
	var z0 := zbi - 0.12
	var z1 := zfi + 0.12
	var poly := PackedVector2Array([Vector2(x0, z0), Vector2(0.85, z0)])
	poly.append_array(k.jag(Vector2(0.85, -2.25), Vector2(0.25, -0.6), 3, 0.25))
	poly.append_array(k.jag(Vector2(0.25, -0.6), Vector2(-0.35, 1.2), 3, 0.3))
	poly.append_array(k.jag(Vector2(-0.35, 1.2), Vector2(-1.7, z1), 3, 0.25))
	poly.append(Vector2(-1.7, z1))
	poly.append(Vector2(x0, z1))
	k.slab(poly, FLOOR_TOP, FLOOR_T, Kit.FLOOR)
	var y := FLOOR_TOP - FLOOR_T - 0.16
	k.beam(Vector3(x0, y, -2.9), Vector3(1.35, y, -2.9), 0.22, 0.32, Kit.IRON, k.hi())
	k.beam(Vector3(x0, y, -1.2), Vector3(1.15, y, -1.2), 0.22, 0.32, Kit.IRON, k.hi())
	k.beam(Vector3(x0, y, 0.6), Vector3(0.25, y, 0.6), 0.22, 0.32, Kit.IRON, k.hi())
	k.beam(Vector3(0.25, y, 0.6), Vector3(0.95, y - 0.5, 0.75), 0.2, 0.3, Kit.RUST_DARK, true)
	k.beam(Vector3(x0, y, 2.3), Vector3(-0.6, y, 2.3), 0.22, 0.32, Kit.IRON, k.hi())
	k.pillar(Vector3(-0.95, 0.0, -0.15), FLOOR_TOP - FLOOR_T, 0.26, 2, false, 25)
	k.scatter(Vector3(-0.6, FLOOR_TOP, -1.4), 0.6, 1.1, 6, 105)


## บันไดหินรูปตัวแอลที่มุมขวาหลัง: ขึ้นเลียบผนังขวาไปหลัง พักบันได แล้วเลียบผนังหลังไปทางซ้ายถึงพื้นชั้นบน
static func _stair(k: Kit, xi: float, zbi: float) -> void:
	k.xf = Transform3D.IDENTITY
	var rise := FLOOR_TOP / 14.0
	var w := 1.1
	var cx := xi - w * 0.5
	var z_land := zbi + 1.15
	var run1 := (1.6 - z_land) / 8.0
	k.stair(Vector3(cx, 0.0, 1.6), PI, w, 8, rise, run1)
	var y_land := rise * 8.0
	k.box(Vector3(cx, -0.3, (z_land + zbi) * 0.5), w * 0.5, (z_land - zbi) * 0.5 + 0.02, y_land + 0.3, Kit.STONE)
	var x_end := 0.85
	var run2 := (xi - w - x_end) / 6.0
	k.stair(Vector3(xi - w, y_land, (z_land + zbi) * 0.5), -PI * 0.5, z_land - zbi, 6, rise, run2, -0.3 - y_land)


## กองซาก: หน้าขวานอกตึก (ซีกขวาของหน้าตึกที่หักลงมา) ข้างแผ่นเหล็ก ใต้ขอบพื้นที่หักในตึก หลังขวา + ท่อนเสาล้ม
static func _rubble(k: Kit, hw: float, hd: float, xo: float, zfo: float) -> void:
	k.xf = Transform3D.IDENTITY
	k.rubble(Vector3(3.3, 0.0, zfo + 0.35), 1.5, 0.55, 0.85, 16, 101)
	k.rubble(Vector3(xo + 0.45, 0.0, -1.0), 0.42, 1.1, 0.55, 8, 102)
	k.rubble(Vector3(1.0, 0.0, 0.9), 0.9, 0.8, 0.6, 10, 103)
	k.rubble(Vector3(2.0, 0.0, -hd + 0.1), 1.5, 0.38, 0.5, 10, 104)
	k.drum(Vector3(1.65, 0.34, zfo + 0.6), 0.34, 0.75, 0.35)
	k.drum(Vector3(hw - 0.05, 0.34, zfo - 0.5), 0.34, 0.7, 1.45)
	k.drum(Vector3(2.9, 0.95, zfo + 0.4), 0.3, 0.6, 2.2, 0.25)
	k.drum(Vector3(0.3, 0.3, 2.0), 0.3, 0.6, 0.9)


# ---- ฉากถ่ายภาพ ----

func _stage() -> void:
	var i18n := root.get_node_or_null(^"I18n")
	if i18n != null:
		i18n.set("english", false)
	var world := Node3D.new()
	root.add_child(world)
	# แดดจาก scenes/battle_table.tscn (ทิศ สี ความแรง เหมือนแอป)
	var scene: PackedScene = load(SCENE)
	var tv := scene.instantiate()
	var src: DirectionalLight3D = tv.get_node("Sun")
	_sun = DirectionalLight3D.new()
	_sun.transform = src.transform
	_sun.light_color = src.light_color
	_sun.light_energy = src.light_energy
	tv.free()
	world.add_child(_sun)
	var sky_all: Variant = _json(SKY_PATH)
	var themes: Variant = _json(THEMES_PATH)
	var sky: Dictionary = (sky_all as Dictionary).get("ruin", {}) if sky_all is Dictionary else {}
	var theme: Dictionary = (themes as Dictionary).get("ruin", {}) if themes is Dictionary else {}
	var we := WorldEnvironment.new()
	we.environment = _environment(sky, theme)
	world.add_child(we)
	world.add_child(_ground(theme))
	for i in _info.size():
		var mi := MeshInstance3D.new()
		mi.name = "RuinHi" if i == 0 else "RuinLo"
		mi.mesh = _info[i]["mesh"]
		var m := Kit.make_material()
		mi.material_override = m
		_materials.append(m)
		world.add_child(mi)
		_meshes.append(mi)
	_cam = Camera3D.new()
	_cam.fov = 55.0
	_cam.near = 0.2
	_cam.far = 400.0
	world.add_child(_cam)
	_cam.make_current()
	_figures_note = _add_figures(world)
	var layer := CanvasLayer.new()
	root.add_child(layer)
	var panel := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.05, 0.05, 0.07, 0.62)
	sb.set_content_margin_all(10.0)
	sb.set_corner_radius_all(6)
	panel.add_theme_stylebox_override("panel", sb)
	panel.position = Vector2(16, 16)
	_caption = Label.new()
	_caption.add_theme_font_size_override("font_size", 19)
	panel.add_child(_caption)
	layer.add_child(panel)
	print("adapter: " + RenderingServer.get_video_adapter_name() + " (" + RenderingServer.get_video_adapter_api_version() + ")")


## ใช้มุมกล้องและระดับของภาพที่ _shot: hi = แบบระดับ hi ของแอป (มีเงา), lo = ระดับ lo (ไม่มีเงา แสงต่อจุดยอด)
func _apply_shot() -> void:
	var s: Array = SHOTS[_shot]
	var level: int = s[3]
	_cam.look_at_from_position(s[1], s[2], Vector3.UP)
	for i in _meshes.size():
		_meshes[i].visible = i == level
		_materials[i].shading_mode = BaseMaterial3D.SHADING_MODE_PER_VERTEX if level == 1 else BaseMaterial3D.SHADING_MODE_PER_PIXEL
	if level == 0:
		RenderingServer.directional_shadow_atlas_set_size(2048, true)
		_sun.shadow_enabled = true
		_sun.directional_shadow_max_distance = 70.0
		_sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS
	else:
		_sun.shadow_enabled = false
	# App โหลดภาษาที่บันทึกไว้หลัง _initialize: ภาพตัวอย่างให้เจ้าของเป็นภาษาไทยเสมอ
	var i18n := root.get_node_or_null(^"I18n")
	if i18n != null:
		i18n.set("english", false)
	var view := ""
	match String(s[0]):
		"front":
			view = _t("ด้านหน้า")
		"corner":
			view = _t("มุมเฉียง")
		"top":
			view = _t("มองจากบน")
		_:
			view = _t("แบบหยาบ lo สำหรับระยะไกลและเครื่องเล็ก")
	var lv := _t("แบบละเอียด hi") if level == 0 else "lo"
	var foot := footprint()
	var box: AABB = _info[level]["aabb"]
	var lines := [_t("ตัวอย่างตึกซากโกธิก (แบบของเราเอง)"),
		"%s · %s · %s" % [view, lv, _t("{n} สามเหลี่ยม").format({"n": int(_info[level]["tris"])})],
		_t("รอยเท้าตามกติกา {w} × {d} ม. สูง {h} ม.").format({"w": "%.1f" % foot.x, "d": "%.1f" % foot.y, "h": "%.1f" % box.end.y})]
	if _figures_note:
		lines.append(_t("ฟิกเกอร์สูงราว 1.7 ม. ไว้เทียบขนาด"))
	_caption.text = "\n".join(lines)


## แสงรอบและท้องฟ้าแบบ TableView._apply_environment ของฉากเมืองพัง (ระดับ hi/mid/lo)
static func _environment(sky: Dictionary, theme: Dictionary) -> Environment:
	var env := Environment.new()
	env.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	var top := _html(sky.get("top", "#242331"))
	var hor := _html(sky.get("hor", "#6A4A55"))
	env.ambient_light_color = hor.lerp(Color.WHITE, 0.45)
	env.ambient_light_energy = 0.85
	var mat := ProceduralSkyMaterial.new()
	mat.sun_angle_max = 0.0
	mat.sky_top_color = top
	mat.sky_horizon_color = hor
	var ground := TerrainMesh._rgb(theme.get("ground2", [68, 64, 62]))
	mat.ground_horizon_color = hor.lerp(ground, 0.5)
	mat.ground_bottom_color = ground * 0.6
	var s := Sky.new()
	s.sky_material = mat
	env.sky = s
	env.background_mode = Environment.BG_SKY
	return env


## พื้นสนามเรียบสีตามธีม (ตารางด่าง ๆ) สำหรับถ่ายภาพเท่านั้น
static func _ground(theme: Dictionary) -> MeshInstance3D:
	var g1 := TerrainMesh._rgb(theme.get("ground", [112, 104, 94]))
	var g2 := TerrainMesh._rgb(theme.get("ground2", [68, 64, 62]))
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var n := 22
	var cell := 2.0
	var rng := RandomNumberGenerator.new()
	rng.seed = 5
	var cols: Array[Color] = []
	for i in (n * 2 + 1) * (n * 2 + 1):
		cols.append(g1.lerp(g2, rng.randf_range(0.18, 0.3)))
	for j in n * 2:
		for i in n * 2:
			var p := [Vector3((i - n) * cell, 0.0, (j - n) * cell), Vector3((i - n + 1) * cell, 0.0, (j - n) * cell),
				Vector3((i - n + 1) * cell, 0.0, (j - n + 1) * cell), Vector3((i - n) * cell, 0.0, (j - n + 1) * cell)]
			var c := [cols[j * (n * 2 + 1) + i], cols[j * (n * 2 + 1) + i + 1], cols[(j + 1) * (n * 2 + 1) + i + 1], cols[(j + 1) * (n * 2 + 1) + i]]
			for q in [0, 1, 2, 0, 2, 3]:
				st.set_normal(Vector3.UP)
				st.set_color(c[q])
				st.add_vertex(p[q])
	var mi := MeshInstance3D.new()
	mi.name = "Ground"
	mi.mesh = st.commit()
	var m := Kit.make_material()
	mi.material_override = m
	return mi


## ฟิกเกอร์สองตัวยืนหน้าตึกไว้เทียบขนาด (ถ้ามีชุดโมเดล); ใช้ FigurePool กับแสงแบบเดียวกับแอป
func _add_figures(world: Node3D) -> bool:
	var kits := KitLibrary.list_kits()
	var want: Array[String] = []
	for kname in ["infantry", "knight", "heavy", "archer"]:
		if kits.has(kname) and want.size() < 2:
			want.append(kname)
	if want.is_empty():
		return false
	var pool := FigurePool.new()
	pool.name = "Figures"
	world.add_child(pool)
	var list: Array[FigurePool.Figure] = []
	list.append(FigurePool.make(want[0], 0, Vector3(1.35, 0.0, 5.2), 0.3, 0.62))
	if want.size() > 1:
		list.append(FigurePool.make(want[1], 1, Vector3(-1.3, 0.0, 5.6), -0.2, 0.62))
	pool.set_figures(list)
	pool.build("hi", Vector3(0.0, 3.3, 16.5))
	var amb := _html("#6A4A55").lerp(Color.WHITE, 0.45)
	pool.set_lighting(_sun.transform.basis.z, _sun.light_color * (0.5 * _sun.light_energy), amb * 0.5)
	return true


## คำแปลผ่าน autoload I18n (สคริปต์ -s คอมไพล์ก่อนมี autoload จึงเรียกผ่านโหนด)
func _t(th: String) -> String:
	var i18n := root.get_node_or_null(^"I18n")
	return str(i18n.call("t", th)) if i18n != null else th


static func _html(code: Variant) -> Color:
	var s := str(code)
	return Color.html(s) if Color.html_is_valid(s) else Color(0.3, 0.3, 0.35)


static func _json(path: String) -> Variant:
	if not FileAccess.file_exists(path):
		return null
	return JSON.parse_string(FileAccess.get_file_as_string(path))
