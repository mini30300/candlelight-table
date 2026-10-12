extends Control
## Fixture: a screen whose Thai string has no English entry in ui/i18n_extra.json (validate_data.py must fail).

const TITLE := "ยังไม่มีคำแปล"   # ข้อความนี้ไม่มีคู่ภาษาอังกฤษ


func _ready() -> void:
	print(I18n.t(TITLE))
