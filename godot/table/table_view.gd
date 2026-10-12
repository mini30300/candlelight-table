class_name TableView
extends Node3D
## รากของโต๊ะ 3 มิติ: กล้อง แดด สภาพแวดล้อม พื้น อุปกรณ์ ฟิกเกอร์ วงแหวน · ใช้ระดับกราฟิกจาก App (apply_level)
## สนามจากกติกา (R1-V1): FieldTerrain + FieldProps ของ core/field ตามค่าตั้ง (seed ขนาดโต๊ะ ฉาก ภูมิประเทศ สิ่งก่อสร้าง
## ความหนาแน่น) ค่าเริ่มต้น DEFAULT_SETUP; rebuild(setup) สร้างใหม่ · ฟิกเกอร์ ~400 ตัว 8 ทีมยังเป็นภาพทดลอง R0-E
## งานต่อเฟรม: ไม่มีในสคริปต์นี้ (วาดใหม่เมื่อมีอะไรเปลี่ยน; lo/min เปิด low_processor_usage_mode)

const THEMES_PATH := "res://data/themes.json"
const SKY_PATH := "res://data/sky.json"
const TEAMS_PATH := "res://data/teams.json"
const FACS_PATH := "res://data/facs.json"
const CORE_PATH := "res://data/core.json"
const TYPES_PATH := "res://data/types.json"
const TABLE_W := 48.0           # ขนาดโต๊ะของค่าเริ่มต้น (เมตร = นิ้วเกม); โต๊ะจริงอยู่ที่ table_w / table_d
const TABLE_D := 34.0
## ค่าตั้งสนามเริ่มต้น: seed 1 โต๊ะ 48 นิ้ว เมืองพัง เนิน มีสิ่งก่อสร้าง ความหนาแน่น x1 (ส่วนพัน)
const DEFAULT_SETUP := {"seed": 1, "w": 48, "theme": "ruin", "terrain": "hills", "buildings": true, "density": 1000}
const THEME_NAMES: PackedStringArray = ["ruin", "forest", "desert", "ice"]
const TERRAIN_NAMES: PackedStringArray = ["flat", "hills", "mountain", "forest"]
const RING_EXTRA := 64          # ที่ว่างสำหรับวงเลือก/ปลายทาง/วัตถุประสงค์
const SELECT_REACH := 1.5       # แตะใกล้ฟิกเกอร์แค่ไหนถึงเลือก (เมตร)
const MAX_KITS_PER_TEAM := 10   # กองทัพจริงซ้ำหน่วยเดิม ไม่ใช่หน่วยละตัว (และ = draw call ต่อทีมบน MultiMesh)
const PROP_CLEARANCE := 0.8     # ฟิกเกอร์ห่างอุปกรณ์อย่างน้อยเท่านี้ (เมตร) นอกเหนือจากรัศมีฐาน
const DEFAULT_TEAMS: Array = [
	{"rgb": [72, 132, 214]}, {"rgb": [212, 78, 66]}, {"rgb": [96, 182, 100]}, {"rgb": [228, 164, 58]},
	{"rgb": [170, 112, 208]}, {"rgb": [96, 204, 216]}, {"rgb": [226, 104, 168]}, {"rgb": [232, 230, 220]}]

## ค่าต่อระดับตาม ARCHITECTURE §6: scale = render scale, shadow = ขนาดแผนที่เงา (0 = ไม่มี), grid = ขั้นตาข่ายพื้น
const LEVELS := {
	"hi": {"scale": 1.0, "fps": 60, "shadow": 2048, "shadow_dist": 70.0, "splits": 1, "per_vertex": false, "grid": 1, "props_simple": false, "idle": false},
	"mid": {"scale": 1.0, "fps": 60, "shadow": 1024, "shadow_dist": 45.0, "splits": 0, "per_vertex": false, "grid": 1, "props_simple": false, "idle": false},
	"lo": {"scale": 0.75, "fps": 30, "shadow": 0, "shadow_dist": 0.0, "splits": 0, "per_vertex": true, "grid": 1, "props_simple": true, "idle": true},
	"min": {"scale": 0.6, "fps": 30, "shadow": 0, "shadow_dist": 0.0, "splits": 0, "per_vertex": true, "grid": 2, "props_simple": true, "idle": true},
}

@export var auto_build := true
@export var seed_value := 1
@export var table_in := 48             # ความกว้างโต๊ะ (นิ้ว) ความลึกตาม FieldTerrain.depth_for
@export var theme_name := "ruin"
@export var terrain_name := "hills"
@export var buildings := true
@export var density_pm := 1000         # ความหนาแน่นสิ่งก่อสร้าง ส่วนพัน (1000 = x1)
@export var figure_count := 400
@export var team_count := 8

@onready var camera_rig: CameraRig = $CameraRig
@onready var sun: DirectionalLight3D = $Sun
@onready var world_env: WorldEnvironment = $WorldEnvironment
@onready var terrain: TerrainMesh = $Terrain
@onready var props: PropsLayer = $Props
@onready var figures: FigurePool = $Figures
@onready var rings: Rings = $Rings

var level := "mid"
var teams: Array = DEFAULT_TEAMS
var theme: Dictionary = {}
var sky: Dictionary = {}
var field: FieldTerrain          # สนามของกติกา (ความสูงหลังปรับพื้นใต้ของแล้ว)
var field_props: FieldProps      # ของบนสนามของกติกา
var table_w := TABLE_W
var table_d := TABLE_D
var table_sky := TableSky.new()
var measuring := false          # หน้าตรวจการ์ดจอเปิดอยู่: ต้องวาดทุกเฟรมเพื่อวัด
var selected := -1
var built := false

var _select_ring := -1
var _env: Environment


func _ready() -> void:
	add_to_group("table_view")
	var t: Variant = _load_json(TEAMS_PATH)
	if t is Array and not (t as Array).is_empty():
		teams = t
	camera_rig.tapped.connect(_on_tapped)
	var app := get_node_or_null(^"/root/App")
	if app != null and LEVELS.has(str(app.get("gfx"))):
		level = str(app.get("gfx"))
	if auto_build:
		build_look()
	apply_level(level)


## สร้างทั้งโต๊ะ: สนามจากกติกา (ของก่อน เพราะ FieldProps ปรับพื้นใต้ของ แล้วจึงทำเมชพื้น) ฟิกเกอร์ 8 ทีม วงแหวนทีม
## ท้องฟ้าตามฉาก แล้วซูมให้พอดีโต๊ะ
func build_look() -> void:
	var t0 := Time.get_ticks_msec()
	var themes: Variant = _load_json(THEMES_PATH)
	var skies: Variant = _load_json(SKY_PATH)
	theme = themes.get(theme_name, {}) if themes is Dictionary else {}
	sky = skies.get(theme_name, {}) if skies is Dictionary else {}
	var cfg: Dictionary = LEVELS[level]
	field = FieldTerrain.make(table_in, FieldTerrain.depth_for(table_in), theme_name, terrain_name, seed_value)
	field_props = FieldProps.generate(field, buildings, density_pm)
	table_w = float(field.w_in)
	table_d = float(field.d_in)
	terrain.build(field, theme, int(cfg["grid"]))
	props.build(field_props, terrain, theme, bool(cfg["props_simple"]))
	table_sky.setup(theme_name, seed_value)
	var list := _compose_figures()
	figures.set_figures(list)
	camera_rig.fit_table(table_w, table_d)
	figures.build(level, camera_pos())
	rings.setup(list.size() + RING_EXTRA)
	for f in list:
		rings.add_ring(f.pos, terrain.normal_at(f.pos.x, f.pos.z), f.radius * 1.1, team_colour(f.team))
	selected = -1
	_select_ring = -1
	_apply_environment()
	built = true
	var c := figures.counts()
	Log.info("table: %d figures (%d skinned, %d kits), %d props in %d kinds, %d rings, seed %d %dx%d %s %s buildings %s x%d, level %s in %d ms" % [
		int(c["figures"]), int(c["skinned"]), int(c["kits"]), props.count(), props.draw_calls(), rings.count(), seed_value,
		field.w_in, field.d_in, theme_name, terrain_name, str(buildings), density_pm, level, Time.get_ticks_msec() - t0])


## ค่าตั้งสนามตอนนี้ (คีย์เดียวกับ DEFAULT_SETUP)
func setup() -> Dictionary:
	return {"seed": seed_value, "w": table_in, "theme": theme_name, "terrain": terrain_name, "buildings": buildings,
		"density": density_pm}


## สร้างโต๊ะใหม่ด้วยค่าตั้งอื่น: คีย์ seed, w (นิ้ว 24..180 เลขคู่), theme, terrain, buildings, density (ส่วนพัน 0..2500)
## คีย์ที่ไม่ใส่คงค่าเดิม; ค่าที่ไม่รู้จักใช้ค่าเริ่มต้น; ระดับกราฟิกเดิม
func rebuild(new_setup: Dictionary) -> void:
	seed_value = int(new_setup.get("seed", seed_value))
	table_in = clampi(int(new_setup.get("w", table_in)), 24, 180) / 2 * 2
	var th := str(new_setup.get("theme", theme_name))
	theme_name = th if THEME_NAMES.has(th) else str(DEFAULT_SETUP["theme"])
	var terr := str(new_setup.get("terrain", terrain_name))
	terrain_name = terr if TERRAIN_NAMES.has(terr) else str(DEFAULT_SETUP["terrain"])
	buildings = bool(new_setup.get("buildings", buildings))
	density_pm = clampi(int(new_setup.get("density", density_pm)), 0, 2500)
	build_look()
	apply_level(level)


## ใช้ระดับกราฟิก hi/mid/lo/min กับทุกส่วนทันที (render scale, เงา, fps, เมชลดรูป, การวาดตอนนิ่ง)
func apply_level(l: String) -> void:
	if not LEVELS.has(l):
		l = "mid"
	level = l
	var cfg: Dictionary = LEVELS[l]
	var vp := get_viewport()
	if vp != null:
		vp.scaling_3d_mode = Viewport.SCALING_3D_MODE_BILINEAR
		vp.scaling_3d_scale = float(cfg["scale"])
		vp.msaa_3d = Viewport.MSAA_DISABLED
	Engine.max_fps = int(cfg["fps"])
	var shadow := int(cfg["shadow"])
	if shadow > 0:
		RenderingServer.directional_shadow_atlas_set_size(shadow, true)
		sun.shadow_enabled = true
		sun.directional_shadow_max_distance = float(cfg["shadow_dist"])
		sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS if int(cfg["splits"]) > 0 else DirectionalLight3D.SHADOW_ORTHOGONAL
	else:
		sun.shadow_enabled = false
	var per_vertex := bool(cfg["per_vertex"])
	terrain.set_grid_step(int(cfg["grid"]))
	terrain.set_per_vertex(per_vertex)
	props.set_simplified(bool(cfg["props_simple"]))
	props.set_per_vertex(per_vertex)
	figures.set_per_vertex(per_vertex)
	if built:
		figures.apply_level(level, camera_pos())
	_apply_environment()
	_update_idle()


## หน้าตรวจการ์ดจอเปิด: วาดทุกเฟรมแม้บน lo/min เพื่อให้เฟรม/วิเป็นค่าจริง
func set_measuring(on: bool) -> void:
	measuring = on
	_update_idle()


func set_stress(on: bool) -> void:
	figures.set_stress(on, camera_pos(), table_w * 0.5 - 1.0, table_d * 0.5 - 1.0)


func camera_pos() -> Vector3:
	return camera_rig.camera.global_position


func team_colour(team: int) -> Color:
	var t: Variant = teams[team % teams.size()]
	if t is Dictionary and (t as Dictionary).has("rgb"):
		return TerrainMesh._rgb(t["rgb"])
	return Color.WHITE


## ตัวเลขรวมสำหรับหน้าตรวจการ์ดจอและเทสงบ
func counts() -> Dictionary:
	var c := figures.counts()
	c["props"] = props.count()
	c["prop_kinds"] = props.draw_calls()
	c["field_props"] = field_props.items.size() if field_props != null else 0
	c["rings"] = rings.count()
	c["terrain_tris"] = terrain.triangle_count()
	c["props_tris"] = props.triangle_count()
	c["ring_tris"] = rings.triangle_count()
	c["level"] = level
	c["teams"] = team_count
	return c


## เลือกฟิกเกอร์ i (วงเลือกสีขาวซ้อนวงทีม) หรือ -1 = ยกเลิก
func select_figure(i: int) -> void:
	if _select_ring >= 0:
		rings.remove_ring(_select_ring)
		_select_ring = -1
	selected = i
	if i >= 0 and i < figures.figures.size():
		var f := figures.figures[i]
		_select_ring = rings.add_kind(Rings.Kind.SELECT, f.pos, terrain.normal_at(f.pos.x, f.pos.z), f.radius * 1.1)


# ---- ภายใน ----

func _on_tapped(screen_pos: Vector2) -> void:
	var cam := camera_rig.camera
	var hit: Variant = _hit_ground(cam.project_ray_origin(screen_pos), cam.project_ray_normal(screen_pos))
	if hit == null:
		select_figure(-1)
		return
	var p := hit as Vector3
	var best := -1
	var best_d := 0.0
	for i in figures.figures.size():
		var f := figures.figures[i]
		var reach := maxf(SELECT_REACH, f.radius + 0.5)
		var d := Vector2(f.pos.x - p.x, f.pos.z - p.z).length_squared()
		if d <= reach * reach and (best < 0 or d < best_d):
			best = i
			best_d = d
	select_figure(best)


## จุดตัดรังสีกับพื้น (วนปรับความสูง 4 รอบ); null เมื่อรังสีไม่ชี้ลง
func _hit_ground(from: Vector3, dir: Vector3) -> Variant:
	if dir.y >= -0.001:
		return null
	var y := 0.0
	var p := from
	for i in 4:
		var t := (y - from.y) / dir.y
		p = from + dir * t
		y = terrain.height_at(p.x, p.z)
	return p


func _update_idle() -> void:
	var cfg: Dictionary = LEVELS[level]
	OS.low_processor_usage_mode = bool(cfg["idle"]) and not measuring


## ท้องฟ้าตามฉาก (table/sky.gd จาก sky.json; เส้นขอบฟ้าเฉพาะ mid/hi; min สีเรียบ) ไม่มี glow/SSAO/หมอก ทุกระดับ
func _apply_environment() -> void:
	if _env == null:
		_env = Environment.new()
		_env.tonemap_mode = Environment.TONE_MAPPER_LINEAR
		_env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
		world_env.environment = _env
	var hor := _html(sky.get("hor", "#6A4A55"))
	_env.ambient_light_color = hor.lerp(Color.WHITE, 0.45)
	_env.ambient_light_energy = 0.3   # พื้นสีจริงของฉาก (ทราย หิมะ) ไม่สว่างจ้าจนเห็นเนินไม่ชัด; ฟิกเกอร์ใช้แค่สีแสงรอบ
	# ฟิกเกอร์ใช้แสงของ figure.gdshader เอง (ไม่รับแสง/เงาของเครื่องยนต์): ทิศเดียวกับ Sun, สีจากแดดและแสงรอบ
	figures.set_lighting(sun.global_transform.basis.z, sun.light_color * (0.5 * sun.light_energy), _env.ambient_light_color * 0.5)
	table_sky.apply(_env, level)


static func _html(code: Variant) -> Color:
	var s := str(code)
	return Color.html(s) if Color.html_is_valid(s) else Color(0.3, 0.3, 0.35)


static func _load_json(path: String) -> Variant:
	if not FileAccess.file_exists(path):
		return null
	return JSON.parse_string(FileAccess.get_file_as_string(path))


# ---- จัดทัพภาพทดลอง ----

## ที่ว่างใกล้ (x, z) ที่สุดที่ไม่ทับของบนสนาม (วนออกทีละวง 0.8 ม. ถึง 14 ม. ในโต๊ะ); ไม่เจอคืนจุดเดิม
func _free_spot(x: float, z: float, r: float) -> Vector2:
	var need := r + PROP_CLEARANCE
	if not props.blocked_at(x, z, need):
		return Vector2(x, z)
	var lim_x := table_w * 0.5 - 1.0
	var lim_z := table_d * 0.5 - 1.0
	var rr := 0.8
	while rr <= 14.0:
		var n := maxi(8, int(rr * 6.0))
		for k in n:
			var a := k * TAU / n
			var px := x + cos(a) * rr
			var pz := z + sin(a) * rr
			if absf(px) <= lim_x and absf(pz) <= lim_z and not props.blocked_at(px, pz, need):
				return Vector2(px, pz)
		rr += 0.8
	return Vector2(x, z)


## 8 ทีม × ~50 ตัว: ทีมละกองทัพจาก facs.json เดินตามพูลบอท core.json (หน่วยที่มีชุดโมเดลจริง) วางเป็นบล็อกสองแถวริมโต๊ะ
func _compose_figures() -> Array[FigurePool.Figure]:
	var out: Array[FigurePool.Figure] = []
	var facs: Variant = _load_json(FACS_PATH)
	var core: Variant = _load_json(CORE_PATH)
	var types_arr: Variant = _load_json(TYPES_PATH)
	var on_disk := KitLibrary.list_kits()
	if not facs is Array or not core is Dictionary or not types_arr is Array or on_disk.is_empty():
		Log.warn("table: no kits or data tables; the field stays empty (run tools/export_kits.js)")
		return out
	var types: Dictionary = {}
	for t in types_arr:
		if t is Dictionary and (t as Dictionary).has("k"):
			types[t["k"]] = t
	var manifest := KitLibrary.load_manifest()
	var per_team := maxi(1, figure_count / maxi(team_count, 1))
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value * 131 + 7
	for team in team_count:
		var army: String = str((facs as Array)[team % (facs as Array).size()].get("k", ""))
		var pool: Variant = core.get(army, [])
		var squads: Array = []
		var used: Array[String] = []
		var models := 0
		var guard := 0
		while models < per_team and pool is Array and not (pool as Array).is_empty() and guard < 400:
			var key := str((pool as Array)[guard % (pool as Array).size()])
			guard += 1
			if not on_disk.has(key) or not types.has(key):
				continue
			if not used.has(key):
				if used.size() >= MAX_KITS_PER_TEAM or not figures.kit_available(key):
					continue
				used.append(key)
			var n := mini(int(types[key].get("n", 1)), per_team - models)
			squads.append([key, n])
			models += n
		_place_team(team, squads, manifest, rng, out)
	return out


## วางทีมเป็นแถว ๆ ในเขตของมัน (กว้าง 1/4 โต๊ะ ลึกถึงกลางโต๊ะ): ระยะระหว่างตัวย่อลงเมื่อกองทัพฐานใหญ่ไม่พอดีเขต
## (ฐานซ้อนกันนิดหน่อยดีกว่าเดินออกนอกโต๊ะ) และไม่มีตัวไหนออกนอกราวเด็ดขาด
func _place_team(team: int, squads: Array, manifest: Dictionary, rng: RandomNumberGenerator, out: Array[FigurePool.Figure]) -> void:
	var col := team % 4
	var row := team / 4
	var zone_w := table_w / 4.0
	var x0 := -table_w * 0.5 + col * zone_w + 1.0
	var x1 := x0 + zone_w - 2.0
	var dir := 1.0 if row == 0 else -1.0
	var z_edge := (-table_d * 0.5 + 1.4) if row == 0 else (table_d * 0.5 - 1.4)
	var z_end := 1.0   # ความลึกสุดของเขต: ถึง |z| = z_end ก่อนกลางโต๊ะ
	var face := 0.0 if row == 0 else PI
	var footprint := 0.0
	for sq in squads:
		var rr := KitLibrary.base_radius(manifest, sq[0])
		footprint += int(sq[1]) * (2.0 * rr + 0.3) * (2.0 * rr + 0.3)
	var zone_area := (x1 - x0) * (table_d * 0.5 - 1.4 - z_end)
	var scale := minf(1.0, sqrt(zone_area * 0.72 / maxf(footprint, 1.0)))
	var x := x0
	var z := z_edge
	var row_h := 0.0
	for sq in squads:
		var kit: String = sq[0]
		var r := KitLibrary.base_radius(manifest, kit)
		for i in int(sq[1]):
			var w := (2.0 * r + 0.3) * scale
			var tries := 0
			var cx := 0.0
			var cz := 0.0
			while true:
				if x + w > x1:
					x = x0
					z += dir * (row_h + 0.3 * scale)
					row_h = 0.0
				if dir * z > -z_end:   # เขตเต็ม: เริ่มชั้นใหม่เยื้องครึ่งตัว (ซ้อนกันบ้าง) แทนการออกนอกโต๊ะ
					z = z_edge + dir * 0.5
					x = x0 + 0.5 * w
				cx = x + r * scale
				cz = z + dir * r * scale
				# หลบอุปกรณ์เฉพาะตอนเขตยังเหลือที่ (ครึ่งแรก); ที่เหลือวางเลย
				if tries < 40 and dir * z < -table_d * 0.25 and props.blocked_at(cx, cz, r + PROP_CLEARANCE):
					tries += 1
					x += 0.5
					continue
				break
			cx = clampf(cx, -table_w * 0.5 + 1.0, table_w * 0.5 - 1.0)
			cz = clampf(cz, -table_d * 0.5 + 1.0, table_d * 0.5 - 1.0)
			var spot := _free_spot(cx, cz, r)
			cx = spot.x
			cz = spot.y
			var pos := Vector3(cx, terrain.height_at(cx, cz), cz)
			out.append(FigurePool.make(kit, team, pos, face + rng.randf_range(-0.25, 0.25), r))
			x += w
			row_h = maxf(row_h, 2.0 * r * scale)
		x += 0.6 * scale
