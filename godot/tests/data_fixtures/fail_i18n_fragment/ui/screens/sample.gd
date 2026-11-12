extends Control
## Fixture: a screen whose Thai string is only in a fragment file the app never loads.

const TITLE := "เมนูลับใหม่"   # คู่ภาษาอังกฤษอยู่ในไฟล์ที่ I18n ไม่โหลด


func _ready() -> void:
	print(I18n.t(TITLE))
