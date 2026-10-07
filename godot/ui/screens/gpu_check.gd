extends Control
## หน้าตรวจการ์ดจอ (หน้าแรกของภาพทดลอง R0-E): ชื่อการ์ดจอ รุ่น GL เฟรม/วิ จำนวนวาด สามเหลี่ยม หน่วยความจำ จำนวนฟิกเกอร์,
## ปุ่มทดสอบหนัก (+400 แข็ง +100 ขยับได้), ตัวเลือกระดับกราฟิก (ปรับ render scale/เงาทันที แล้วบันทึก), ช่องพิมพ์ไทย
## (ทดสอบแป้นพิมพ์), สลับไทย/อังกฤษ, คัดลอกตัวเลข · ตัวเลขอัปเดตทุก 0.5 วิด้วย Timer (ไม่มี _process)
## แผงอยู่ซ้ายบน ส่วนที่เหลือของจอทะลุไปโต๊ะ (mouse_filter = ignore) กล้องจึงลาก/หนีบได้
## ปุ่ม "จัดกองทัพ ›" ส่งสัญญาณ army_requested ให้ main.gd เปิดหน้าจัดกองทัพ (กลับมาแล้ววาดข้อความใหม่ตามภาษา)

signal army_requested

const TITLE := "ตรวจการ์ดจอ"
const HINT := "แตะเพื่อเลือกฟิกเกอร์ · ลากเพื่อเลื่อน · สองนิ้วซูม/หมุน · ล้อเมาส์ซูม · คลิกขวาลากหมุน · WASD เลื่อน"
const BUTTON_TO_ENGLISH := "ENGLISH"   # ป้ายปุ่มตอนเป็นไทย — เป็นอังกฤษตั้งใจ เหมือนหน้าเก่า
const BUTTON_TO_THAI := "ไทย"
const LEVELS: PackedStringArray = ["hi", "mid", "lo", "min"]
const LEVEL_TH := {"hi": "สูง", "mid": "กลาง", "lo": "ต่ำ", "min": "ต่ำสุด (มือถืออ่อน)"}
const INFO_EVERY := 0.5
const COPIED_MS := 2000

@onready var title: Label = %Title
@onready var info: Label = %Info
@onready var level_label: Label = %LevelLabel
@onready var level_picker: OptionButton = %LevelPicker
@onready var stress_toggle: CheckButton = %StressToggle
@onready var name_label: Label = %NameLabel
@onready var name_edit: LineEdit = %NameEdit
@onready var copy_button: Button = %CopyButton
@onready var fit_button: Button = %FitButton
@onready var lang_button: Button = %LangButton
@onready var army_button: Button = %ArmyButton
@onready var hint: Label = %Hint
@onready var timer: Timer = %Timer

var table: TableView
var last_text := ""          # ข้อความตัวเลขล่าสุด (ที่ปุ่มคัดลอกใช้)

var _copied_ms := 0


func _ready() -> void:
	table = get_tree().get_first_node_in_group("table_view") as TableView
	level_picker.clear()
	for l in LEVELS:
		level_picker.add_item(l)
	level_picker.item_selected.connect(_on_level)
	stress_toggle.toggled.connect(_on_stress)
	copy_button.pressed.connect(_on_copy)
	fit_button.pressed.connect(_on_fit)
	lang_button.pressed.connect(_on_lang)
	army_button.pressed.connect(func() -> void: army_requested.emit())
	visibility_changed.connect(_on_visibility)
	timer.wait_time = INFO_EVERY
	timer.timeout.connect(_update_info)
	timer.start()
	if table != null:
		table.set_measuring(true)
	refresh()


func _exit_tree() -> void:
	if table != null:
		table.set_measuring(false)


## วาดข้อความทุกชิ้นใหม่ตามภาษาปัจจุบัน
func refresh() -> void:
	title.text = I18n.t(TITLE)
	level_label.text = I18n.t("ระดับกราฟิก")
	for i in LEVELS.size():
		level_picker.set_item_text(i, I18n.t(LEVEL_TH[LEVELS[i]]))
	var cur := LEVELS.find(App.gfx)
	if cur >= 0:
		level_picker.select(cur)
	stress_toggle.text = I18n.t("ทดสอบหนัก: +400 แข็ง +100 ขยับได้")
	name_label.text = I18n.t("พิมพ์ชื่อไทยที่นี่ (ทดสอบแป้นพิมพ์)")
	name_edit.placeholder_text = I18n.t("ชื่อของคุณ")
	copy_button.text = I18n.t("คัดลอกตัวเลข")
	fit_button.text = I18n.t("ซูมให้พอดีโต๊ะ")
	lang_button.text = BUTTON_TO_THAI if I18n.english else BUTTON_TO_ENGLISH
	army_button.text = I18n.t("จัดกองทัพ ›")
	hint.text = I18n.t(HINT)
	_update_info()


## สลับภาษาและบันทึก (เทสเรียกตรง ๆ)
func set_language(english: bool) -> void:
	App.set_lang("en" if english else "th")
	App.save_settings()
	refresh()


func _update_info() -> void:
	var screen := DisplayServer.screen_get_size()
	var win := DisplayServer.window_get_size()
	var vp := get_viewport()
	var scale := vp.scaling_3d_scale if vp != null else 1.0
	var mem := OS.get_static_memory_usage()
	var phys := int(OS.get_memory_info().get("physical", 0))
	var vram := RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_VIDEO_MEM_USED)
	var draws := RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME)
	var prims := RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_PRIMITIVES_IN_FRAME)
	var os_name := OS.get_name()
	if OS.has_feature("mobile"):
		os_name += " " + OS.get_model_name()
	var lines := PackedStringArray()
	lines.append("%s %s · %s %s" % [I18n.t("การ์ดจอ"), RenderingServer.get_video_adapter_name(), I18n.t("รุ่น GL"), RenderingServer.get_video_adapter_api_version()])
	lines.append("%s %s · %s %d×%d (%d×%d)" % [I18n.t("ระบบ"), os_name, I18n.t("จอ"), screen.x, screen.y, win.x, win.y])
	lines.append("%s %d · %s %d · %s %s" % [I18n.t("เฟรม/วิ"), Engine.get_frames_per_second(), I18n.t("จำนวนวาด"), draws, I18n.t("สามเหลี่ยม"), _k(prims)])
	lines.append("%s %s / %s · %s %s" % [I18n.t("หน่วยความจำ"), _mb(mem), _mb(phys), I18n.t("หน่วยความจำการ์ดจอ"), _mb(vram)])
	var shadow := I18n.t("เปิด") if (table != null and table.sun.shadow_enabled) else I18n.t("ปิด")
	lines.append("%s %s · %s %.2f · %s %s" % [I18n.t("ระดับที่ใช้"), I18n.t(LEVEL_TH.get(App.gfx, "กลาง")), I18n.t("สเกลภาพ"), scale, I18n.t("เงา"), shadow])
	if table != null:
		var c := table.counts()
		lines.append(I18n.t("ฟิกเกอร์ {n} ตัว (ขยับได้ {s} · แข็ง {r}) · ชุดโมเดล {k} ชุด · วงแหวน {g} วง · อุปกรณ์ {p} ชิ้น").format({
			"n": int(c["figures"]), "s": int(c["skinned"]), "r": int(c["rigid"]), "k": int(c["kits"]), "g": int(c["rings"]), "p": int(c["props"])}))
	last_text = "\n".join(lines)
	info.text = last_text
	if _copied_ms > 0 and Time.get_ticks_msec() - _copied_ms > COPIED_MS:
		_copied_ms = 0
		copy_button.text = I18n.t("คัดลอกตัวเลข")


func _on_level(index: int) -> void:
	if index < 0 or index >= LEVELS.size():
		return
	App.set_gfx(LEVELS[index])
	App.save_settings()
	if table != null:
		table.apply_level(LEVELS[index])
	_update_info()


func _on_stress(on: bool) -> void:
	if table != null:
		table.set_stress(on)
	_update_info()


func _on_copy() -> void:
	DisplayServer.clipboard_set(I18n.t(TITLE) + "\n" + last_text)
	copy_button.text = I18n.t("คัดลอกแล้ว")
	_copied_ms = Time.get_ticks_msec()


func _on_fit() -> void:
	if table != null:
		table.camera_rig.fit_table(table.table_w, table.table_d)


func _on_lang() -> void:
	set_language(not I18n.english)


## กลับมาจากหน้าอื่น (อาจสลับภาษาไว้): วาดข้อความใหม่
func _on_visibility() -> void:
	if visible:
		refresh()


static func _mb(bytes: int) -> String:
	return "%d MB" % int(bytes / 1048576)


static func _k(n: int) -> String:
	return ("%.1fk" % (n / 1000.0)) if n >= 1000 else str(n)
