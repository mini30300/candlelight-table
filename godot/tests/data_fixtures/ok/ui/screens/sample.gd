extends Control
## Fixture: a screen whose Thai strings all have English entries (ui/i18n_extra.json or a page string). Must pass.
## # a '#' inside this comment, and "quotes" too, must not confuse the literal scanner

const TITLE := "โต๊ะเทียน"                     # a page string from data/i18n_en.json... not here: i18n_extra.json has it
const HINT := "แตะเพื่อเลือกหน่วย {n} ตัว"   # a placeholder inside the string
const COUNT := "เหลือ %d หน่วย"


func _ready() -> void:
	print(I18n.t(TITLE), I18n.t('วิ่ง'), I18n.t("""ยิง"""))
	var s := "ยกเลิก · ตกลง"   # two known fragments joined with punctuation
	print(s, "no thai here", "เฟรม/วิ")
