class_name SpeechBubble
extends PanelContainer
## กรอบคำพูดของตัวละคร (ใหม่ 0.14 ข้อ 2): ข้อความเงียบ (ไม่มีเสียง) ขณะปากของตัวละครขยับ · ห้องแต่งตัว / การ์ดฮีโร่
## ไม่มีงานต่อเฟรม: ผู้ใช้วางตำแหน่ง แล้ว show_line() / hide_line() · หางชี้ลงทางซ้ายล่าง (_draw)

const BG := Color(0.96, 0.94, 0.9, 0.96)
const INK := Color(0.12, 0.1, 0.12)
const TAIL := 12.0
const MAX_W := 320.0
const FONT_SIZE := 20
## บทพูด (คีย์ไทย · คำแปลใน ui/i18n/face.json): ห้องแต่งตัวทักทาย · การ์ดฮีโร่ "ธรรมดา" · ปากขยับด้วย FaceSpeech
const LINES := {
	"greet": [
		"สวัสดี! พร้อมออกรบแล้ว", "ชุดนี้ดูดีไหม", "เลือกสีให้เข้ากับทีมนะ", "วันนี้จะไปรบที่ไหน",
		"หมุนดูได้ทุกด้านเลย", "พร้อมเสมอ สั่งมาได้เลย", "ยินดีที่ได้ร่วมทีม", "อย่าลืมบันทึกชุดนะ",
		"ขอรองเท้าคู่ใหม่ได้ไหม", "เอาล่ะ ลุยกันเลย!"],
	"hero": [
		"คนธรรมดาก็สู้ได้", "ไม่ต้องเป็นฮีโร่ก็ช่วยเพื่อนได้", "ก้าวทีละก้าว แล้วเราจะชนะ",
		"หายใจลึก ๆ แล้วเล็งให้ดี", "กลับบ้านพร้อมกันทุกคนนะ", "ไม่กลัวหรอก มากันเลย", "ระวังหลังด้วย",
		"ตามมาเลย!", "อีกนิดเดียว อดทนไว้", "ภารกิจนี้เราทำได้"],
}

var _label: Label
var _text := ""


func _init() -> void:
	name = "SpeechBubble"
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sb := StyleBoxFlat.new()
	sb.bg_color = BG
	sb.set_corner_radius_all(14)
	sb.content_margin_left = 14.0
	sb.content_margin_right = 14.0
	sb.content_margin_top = 7.0
	sb.content_margin_bottom = 9.0
	add_theme_stylebox_override("panel", sb)
	_label = Label.new()
	_label.name = "Text"
	_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_label.add_theme_color_override("font_color", INK)
	_label.add_theme_font_size_override("font_size", FONT_SIZE)
	add_child(_label)
	visible = false


## บทที่ n (วนรอบ) ของชุด kind เป็นคีย์ไทย ("" = ไม่มีชุดนี้) · ผู้เรียกแปลด้วย I18n.t
static func line(kind: String, n: int) -> String:
	var a: Array = LINES.get(kind, [])
	return "" if a.is_empty() else str(a[posmod(n, a.size())])


## แสดงข้อความ (แปลแล้ว) · กว้างตามข้อความ · เกิน MAX_W ตัดเป็นสองบรรทัดที่ช่องว่างใกล้กลางที่สุด
## (ไม่ใช้ autowrap: ความสูงของ Label ที่ตัดบรรทัดเองคิดจากความกว้างก่อนจัดวาง กรอบจึงสูงเกิน)
func show_line(text: String) -> void:
	_text = text
	var shown := text
	var font := _label.get_theme_font("font")
	if font != null and font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE).x > MAX_W:
		var mid := text.length() / 2
		var best := -1
		for i in text.length():
			if text[i] == " " and (best < 0 or absi(i - mid) < absi(best - mid)):
				best = i
		if best > 0:
			shown = text.substr(0, best) + "\n" + text.substr(best + 1)
	_label.text = shown
	visible = true
	reset_size()
	queue_redraw()


func hide_line() -> void:
	visible = false


## ข้อความที่แสดงอยู่ ("" = ซ่อน)
func shown() -> String:
	return _text if visible else ""


func _draw() -> void:
	var x := minf(26.0, size.x * 0.3)
	draw_colored_polygon(PackedVector2Array([Vector2(x, size.y - 1.0), Vector2(x + TAIL * 1.3, size.y - 1.0),
		Vector2(x - 3.0, size.y + TAIL)]), BG)
