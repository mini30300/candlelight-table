extends CanvasLayer
## HUD ของฉากทดสอบ: ชื่อ, ข้อมูลเครื่อง (ทุก 0.5 วิ), ปุ่มสลับภาษา

const TITLE := "โต๊ะเทียน แอปใหม่ รุ่นทดสอบ 0.0.1"
const HINT := "ลากเพื่อหมุน · ล้อเมาส์หรือสองนิ้วเพื่อซูม"
const BUTTON_TO_ENGLISH := "ENGLISH"   # ป้ายปุ่มตอนเป็นไทย — เป็นอังกฤษตั้งใจ เหมือนหน้าเก่า
const BUTTON_TO_THAI := "ไทย"
const INFO_EVERY := 0.5

@onready var title: Label = %Title
@onready var info: Label = %Info
@onready var hint: Label = %Hint
@onready var lang_button: Button = %LangButton

var _timer := 0.0
var _figures := 0
var _from_kits := false


func _ready() -> void:
	lang_button.pressed.connect(_on_lang_pressed)
	refresh()


func _process(delta: float) -> void:
	_timer += delta
	if _timer >= INFO_EVERY:
		_timer = 0.0
		_update_info()


## ฉากบอกว่ามีฟิกเกอร์กี่ตัว และมาจากชุดโมเดลจริงหรือกล่องแทน
func set_figures(count: int, from_kits: bool) -> void:
	_figures = count
	_from_kits = from_kits
	_update_info()


func refresh() -> void:
	title.text = I18n.t(TITLE)
	hint.text = I18n.t(HINT)
	lang_button.text = BUTTON_TO_THAI if I18n.english else BUTTON_TO_ENGLISH
	_update_info()


func _update_info() -> void:
	var screen := DisplayServer.screen_get_size()
	var figures_text := I18n.t("ฟิกเกอร์ {n} ตัวจากชุดโมเดล") if _from_kits else I18n.t("กล่องแทนฟิกเกอร์ {n} ใบ (ไม่พบชุดโมเดล)")
	info.text = "%s %d · %s %s · %s %s\n%s %d×%d · %s" % [
		I18n.t("เฟรม/วิ"), Engine.get_frames_per_second(),
		I18n.t("การ์ดจอ"), RenderingServer.get_video_adapter_name(),
		I18n.t("ระบบ"), OS.get_name(),
		I18n.t("จอ"), screen.x, screen.y,
		figures_text.format({"n": _figures}),
	]


func _on_lang_pressed() -> void:
	I18n.english = not I18n.english
	refresh()
