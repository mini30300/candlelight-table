class_name TableSky
extends RefCounted
## ท้องฟ้าตามฉากจาก data/sky.json เป็นพื้นหลังของ Environment: ฟ้าไล่สีเรียบ ที่ราบในหมอก แสงเรืองรอบดวงอาทิตย์
## เส้นขอบฟ้า (ซากเมือง แนวป่า เนินทราย ยอดเขา) เฉพาะ mid/hi; lo ไม่มีเส้นขอบฟ้า; min เป็นสีเรียบสีเดียว (ไม่มีงานต่อเฟรมเพิ่ม)
## เส้นขอบฟ้าสร้างครั้งเดียวต่อฉากและ seed เป็นเท็กซ์เจอร์ 720 x 1 (หน้าเก่า panoOf); เป็นภาพล้วน ไม่ใช่กติกา

const SKY_PATH := "res://data/sky.json"
const SHADER_PATH := "res://assets/shaders/sky.gdshader"
const PANO_N := 720
const PANO_MAX := 0.25            # เรเดียน: ความสูงสุดที่เท็กซ์เจอร์เก็บได้
const SKYLINE_LEVELS := ["mid", "hi"]
const FALLBACK := {"top": "#191827", "hor": "#6A4A55", "sun": [2.3, 0.1], "glow": "255,150,96", "far": "#3A3140",
	"near": "#262130", "fog": "#4E3C40", "plain": "#1C1918", "kind": "city"}

static var _all: Dictionary = {}

var theme_name := "ruin"
var seed_value := 1
var data: Dictionary = FALLBACK
var skyline_on := false
var level := "mid"

var _material: ShaderMaterial
var _sky: Sky
var _tex: ImageTexture
var _tex_key := ""
var _heights := PackedVector2Array()


static func load_all() -> Dictionary:
	if _all.is_empty() and FileAccess.file_exists(SKY_PATH):
		var v: Variant = JSON.parse_string(FileAccess.get_file_as_string(SKY_PATH))
		if v is Dictionary:
			_all = v
	return _all


## เลือกฉากและ seed (เส้นขอบฟ้าสร้างใหม่ตอนต้องใช้ครั้งถัดไป)
func setup(theme: String, seed_v: int) -> void:
	theme_name = theme
	seed_value = seed_v
	var all := load_all()
	data = all.get(theme, all.get("ruin", FALLBACK)) if not all.is_empty() else FALLBACK


func colour(key: String) -> Color:
	return html(data.get(key, FALLBACK.get(key, "#404040")))


## ใส่ท้องฟ้าลง env ตามระดับกราฟิก
func apply(env: Environment, l: String) -> void:
	level = l
	if l == "min":
		skyline_on = false
		env.background_mode = Environment.BG_COLOR
		env.background_color = colour("fog").lerp(colour("plain"), 0.55)   # สีที่กล้องเห็นเมื่อก้มมองโต๊ะ (ที่ราบใต้ขอบฟ้า)
		env.sky = null
		return
	if _material == null:
		_material = ShaderMaterial.new()
		_material.shader = load(SHADER_PATH)
	if _sky == null:
		_sky = Sky.new()
		_sky.sky_material = _material
		_sky.radiance_size = Sky.RADIANCE_SIZE_64
	_material.set_shader_parameter("top_col", colour("top"))
	_material.set_shader_parameter("hor_col", colour("hor"))
	_material.set_shader_parameter("fog_col", colour("fog"))
	_material.set_shader_parameter("plain_col", colour("plain"))
	_material.set_shader_parameter("far_col", colour("far"))
	_material.set_shader_parameter("near_col", colour("near"))
	_material.set_shader_parameter("glow_col", rgb_text(str(data.get("glow", FALLBACK["glow"]))))
	var sun: Variant = data.get("sun", FALLBACK["sun"])
	var az := float(sun[0]) if sun is Array and (sun as Array).size() >= 2 else 2.3
	var el := float(sun[1]) if sun is Array and (sun as Array).size() >= 2 else 0.1
	_material.set_shader_parameter("sun_dir", Vector3(sin(az) * cos(el), sin(el), cos(az) * cos(el)))
	skyline_on = SKYLINE_LEVELS.has(l)
	if skyline_on:
		_material.set_shader_parameter("skyline_tex", _skyline_texture())
		_material.set_shader_parameter("skyline_max", PANO_MAX)
	_material.set_shader_parameter("skyline_on", skyline_on)
	env.sky = _sky
	env.background_mode = Environment.BG_SKY


func material() -> ShaderMaterial:
	return _material


## ความสูงเส้นขอบฟ้า (ไกล, ใกล้) เป็นเรเดียนเหนือขอบฟ้า PANO_N จุดรอบตัว
func skyline_heights() -> PackedVector2Array:
	if _heights.is_empty() or _tex_key != _key():
		_heights = pano(str(data.get("kind", "city")), seed_value)
	return _heights


func _key() -> String:
	return "%s|%d" % [theme_name, seed_value]


func _skyline_texture() -> ImageTexture:
	var key := _key()
	if _tex != null and _tex_key == key:
		return _tex
	_heights = pano(str(data.get("kind", "city")), seed_value)
	var img := Image.create(PANO_N, 1, false, Image.FORMAT_RG8)
	for i in PANO_N:
		var h := _heights[i]
		img.set_pixel(i, 0, Color(clampf(h.x / PANO_MAX, 0.0, 1.0), clampf(h.y / PANO_MAX, 0.0, 1.0), 0.0))
	_tex = ImageTexture.create_from_image(img)
	_tex_key = key
	return _tex


## เส้นขอบฟ้าแบบหน้าเก่า (panoOf): ตึกพังเป็นช่วง ๆ มีหอบ้าง, แนวสนบนเนิน, เนินทรายกับเมซา, ยอดเขาแหลม
static func pano(kind: String, s: int) -> PackedVector2Array:
	var out := PackedVector2Array()
	out.resize(PANO_N)
	var seg := 0
	var seg_h := 0.0
	var seg_end := 0
	for i in PANO_N:
		var a := float(i) / PANO_N * TAU
		var x := cos(a) * 5.0
		var z := sin(a) * 5.0
		var n1 := TerrainMesh.fbm(x + 37.0, z + 11.0, 4, s + 101) * 0.5 + 0.5
		var n2 := TerrainMesh.fbm(x * 2.2 + 91.0, z * 2.2 + 53.0, 3, s + 202) * 0.5 + 0.5
		var r := TerrainMesh.hash01(i, 17, s + 5)
		var far := 0.0
		var near := 0.0
		match kind:
			"city":
				if i >= seg_end:
					seg += 1
					seg_end = i + 5 + int(TerrainMesh.hash01(seg, 3, s + 9) * 12.0)
					var q := TerrainMesh.hash01(seg, 7, s + 2)
					seg_h = 0.006 if q < 0.18 else (0.07 + 0.03 * TerrainMesh.hash01(seg, 5, s + 1) if q > 0.9 else 0.018 + 0.04 * q * n1)
				far = seg_h + (0.012 * float(i - seg_end + 12) / 12.0 if TerrainMesh.hash01(seg, 11, s + 4) < 0.35 else 0.0)
				near = 0.008 + 0.012 * n2
			"trees":
				far = 0.02 + 0.03 * n1 + 0.012 * absf(sin(i * 1.7 + r))
				near = 0.012 + 0.03 * n2 + 0.01 * absf(sin(i * 2.9))
			"dunes":
				var mesa := TerrainMesh.fbm(x * 0.7 + 5.0, z * 0.7 + 5.0, 2, s + 303)
				far = 0.012 + 0.026 * n1 + (0.035 if mesa > 0.25 else (0.035 * (mesa - 0.18) / 0.07 if mesa > 0.18 else 0.0))
				near = 0.006 + 0.02 * n2 * n2
			_:
				var rid := 1.0 - absf(TerrainMesh.fbm(x * 1.3 + 7.0, z * 1.3 + 3.0, 4, s + 404))
				far = 0.02 + 0.13 * rid * rid * n1
				near = 0.012 + 0.05 * n2 * n2
		out[i] = Vector2(far, near)
	return out


static func html(code: Variant) -> Color:
	var s := str(code)
	return Color.html(s) if Color.html_is_valid(s) else Color(0.3, 0.3, 0.35)


## "255,150,96" → สี
static func rgb_text(s: String) -> Color:
	var p := s.split(",")
	if p.size() < 3:
		return Color(1.0, 0.6, 0.4)
	return Color(float(p[0]) / 255.0, float(p[1]) / 255.0, float(p[2]) / 255.0)
