extends Control
## หน้าตั้งค่า (LOBBY_SPEC §5): ภาษา, ระดับกราฟิก, รูปตัวละคร (ตัวไข่ / โมเดลชุดเดิม), ปุ่มบนจอ, ปุ่มไปหน้าตรวจการ์ดจอ
## เสียง: ความดังเอฟเฟกต์ เพลง และปุ่มปิดเสียงทั้งหมด (Sfx.apply_settings() ใช้ค่าใหม่ทันที)
## ทุกปุ่มเรียกตัวตั้งค่าของ App แล้ว App.save_settings() ทันที · ฉาก 3 มิติที่เปิดอยู่อ่านค่าใหม่เองตอนกลับมาโชว์
## ทึบเต็มจอ ไม่มี _process

const GPU_CHECK := "res://ui/screens/gpu_check.tscn"
const ARMY := "res://ui/screens/army.tscn"
const BUTTON_TO_ENGLISH := "ENGLISH"   # ป้ายปุ่มตอนเป็นไทย — อังกฤษตั้งใจ เหมือนหน้าเก่า
const BUTTON_TO_THAI := "ไทย"
const LEVELS: PackedStringArray = ["hi", "mid", "lo", "min"]
const LEVEL_TH := {"hi": "สูง", "mid": "กลาง", "lo": "ต่ำ", "min": "ต่ำสุด (มือถืออ่อน)"}
const FIG_TH := {"egg": "ตัวไข่ (ชั่วคราว)", "kit": "โมเดลชุดเดิม"}
const TOUCH_TH := {"auto": "อัตโนมัติ", "on": "เปิด", "off": "ปิด"}

@onready var margin: MarginContainer = %Margin
@onready var back_button: Button = %BackButton
@onready var title: Label = %Title
@onready var gpu_button: Button = %GpuCheckButton
@onready var panel: PanelContainer = %Panel
@onready var lang_label: Label = %LangLabel
@onready var lang_button: Button = %LangButton
@onready var gfx_label: Label = %GfxLabel
@onready var fig_label: Label = %FigLabel
@onready var fig_note: Label = %FigNote
@onready var touch_label: Label = %TouchLabel
@onready var touch_note: Label = %TouchNote
@onready var sfx_label: Label = %SfxLabel
@onready var mus_label: Label = %MusLabel
@onready var sfx_slider: HSlider = %SfxSlider
@onready var mus_slider: HSlider = %MusSlider
@onready var mute_button: Button = %MuteButton
@onready var gfx_buttons := {"hi": %GfxHi, "mid": %GfxMid, "lo": %GfxLo, "min": %GfxMin}
@onready var fig_buttons := {"egg": %FigEgg, "kit": %FigKit}
@onready var touch_buttons := {"auto": %TouchAuto, "on": %TouchOn, "off": %TouchOff}

## มีชุดโมเดลในเครื่องไหม (ไม่มีก็ปิดปุ่มโมเดลชุดเดิม); เทสบังคับได้ (-1 = ตรวจจากดิสก์)
var kits_override := -1
var _has_kits := false
var _dragging := false     # ลากแถบเสียงอยู่: เปลี่ยนเสียงทันที บันทึกไฟล์ตอนปล่อย


func _ready() -> void:
	var bg := get_node(^"Bg") as ColorRect
	bg.color = CandleStyle.BG
	CandleStyle.title(title, 40)
	CandleStyle.panel(panel)
	for l in [lang_label, gfx_label, fig_label, touch_label, sfx_label, mus_label]:
		CandleStyle.text(l as Label, 22)
	for l in [fig_note, touch_note]:
		CandleStyle.text(l as Label, 17, true)
	for b in [back_button, gpu_button, lang_button, mute_button]:
		CandleStyle.button(b as Button)
	for group in [gfx_buttons, fig_buttons, touch_buttons]:
		var list: Array = (group as Dictionary).values()
		for b in list:
			CandleStyle.button(b as Button)
		CandleStyle.toggle_group(list)
	for l in gfx_buttons:
		(gfx_buttons[l] as Button).pressed.connect(set_gfx.bind(l))
	for s in fig_buttons:
		(fig_buttons[s] as Button).pressed.connect(set_fig.bind(s))
	for m in touch_buttons:
		(touch_buttons[m] as Button).pressed.connect(set_touch.bind(m))
	lang_button.pressed.connect(func() -> void: set_language(not I18n.english))
	sfx_slider.value_changed.connect(set_sfx_vol)
	mus_slider.value_changed.connect(set_mus_vol)
	for sl: Range in [sfx_slider, mus_slider]:
		sl.drag_started.connect(func() -> void: _dragging = true)
		sl.drag_ended.connect(func(_c: bool) -> void:
			_dragging = false
			App.save_settings())
	sfx_slider.drag_ended.connect(func(_c: bool) -> void: _ping())
	mute_button.toggled.connect(func(on: bool) -> void: set_mute(on))
	back_button.pressed.connect(func() -> void: App.pop())
	gpu_button.pressed.connect(open_gpu_check)
	visibility_changed.connect(func() -> void:
		if visible:
			refresh())
	get_viewport().size_changed.connect(_layout)
	_layout()
	refresh()


func has_kits() -> bool:
	if kits_override >= 0:
		return kits_override == 1
	return not KitLibrary.list_kits().is_empty()


## วาดข้อความใหม่ตามภาษา และกดปุ่มให้ตรงกับค่าใน App
func refresh() -> void:
	_has_kits = has_kits()
	title.text = I18n.t("ตั้งค่า")
	back_button.text = I18n.t("‹ กลับ")
	gpu_button.text = I18n.t("ตรวจการ์ดจอ ›")
	lang_label.text = I18n.t("ภาษา")
	lang_button.text = BUTTON_TO_THAI if I18n.english else BUTTON_TO_ENGLISH
	gfx_label.text = I18n.t("ระดับกราฟิก")
	fig_label.text = I18n.t("รูปตัวละคร")
	touch_label.text = I18n.t("ปุ่มบนจอ")
	for l in gfx_buttons:
		(gfx_buttons[l] as Button).text = I18n.t(LEVEL_TH[l])
		(gfx_buttons[l] as Button).set_pressed_no_signal(App.gfx == l)
	for s in fig_buttons:
		(fig_buttons[s] as Button).text = I18n.t(FIG_TH[s])
		(fig_buttons[s] as Button).set_pressed_no_signal(App.fig == s)
	(fig_buttons["kit"] as Button).disabled = not _has_kits
	fig_note.text = I18n.t("โมเดลชุดเดิมยังอยู่ครบ สลับกลับได้ทุกเมื่อ") if _has_kits else I18n.t("ไม่พบชุดโมเดลในเครื่องนี้")
	for m in touch_buttons:
		(touch_buttons[m] as Button).text = _cap(I18n.t(TOUCH_TH[m]))
		(touch_buttons[m] as Button).set_pressed_no_signal(App.touch == m)
	touch_note.text = I18n.t("อัตโนมัติ: เปิดบนมือถือ ปิดบนคอมพิวเตอร์")
	sfx_label.text = I18n.t("เสียงเอฟเฟกต์")
	mus_label.text = I18n.t("เพลง")
	mute_button.text = I18n.t("ปิดเสียง")
	sfx_slider.set_value_no_signal(App.sfx_vol)
	mus_slider.set_value_no_signal(App.mus_vol)
	mute_button.set_pressed_no_signal(not App.snd)


func set_language(english: bool) -> void:
	App.set_lang("en" if english else "th")
	App.save_settings()
	refresh()


func set_gfx(l: String) -> void:
	if App.set_gfx(l):
		App.save_settings()
	refresh()


## kit ใช้ได้เฉพาะเมื่อมีชุดโมเดลในเครื่อง
func set_fig(s: String) -> void:
	if (s != "kit" or has_kits()) and App.set_fig(s):
		App.save_settings()
	refresh()


func set_touch(m: String) -> void:
	if App.set_touch(m):
		App.save_settings()
	refresh()


func set_sfx_vol(v: float) -> void:
	App.set_sfx_vol(v)
	_apply_sound()


func set_mus_vol(v: float) -> void:
	App.set_mus_vol(v)
	_apply_sound()


## ปิดเสียงทั้งหมด (App.snd = false)
func set_mute(on: bool) -> void:
	App.snd = not on
	_apply_sound()
	refresh()


func _apply_sound() -> void:
	if not _dragging:
		App.save_settings()
	var sfx := get_node_or_null(^"/root/Sfx")
	if sfx != null:
		sfx.call("apply_settings")


## ปล่อยแถบเลื่อนเสียงเอฟเฟกต์: เล่นเสียงตัวอย่างให้ได้ยินความดังใหม่
func _ping() -> void:
	var sfx := get_node_or_null(^"/root/Sfx")
	if sfx != null:
		sfx.call("play_ui", &"hit")


## หน้าตรวจการ์ดจอ (ปุ่มจัดกองทัพของมันเปิดหน้าจัดกองทัพซ้อนต่อ)
func open_gpu_check() -> Node:
	var gpu := App.push(load(GPU_CHECK))
	if gpu.has_signal(&"army_requested"):
		gpu.connect(&"army_requested", func() -> void: App.push(load(ARMY)))
	return gpu


## คำอังกฤษของ "เปิด"/"ปิด" เป็นตัวเล็ก ("on"/"off"): ขึ้นต้นตัวใหญ่บนปุ่ม (ไทยไม่แตะ)
static func _cap(t: String) -> String:
	return t.left(1).to_upper() + t.substr(1) if I18n.english else t


func _layout() -> void:
	CandleStyle.safe_margins(margin)
