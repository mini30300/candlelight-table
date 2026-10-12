extends Node
## Fixture: an autoload under app/ with one Thai string that has an English entry. Must pass.

const SETTINGS_TITLE := "ตั้งค่า"   # ชื่อหน้าตั้งค่า


func _ready() -> void:
	print(I18n.t(SETTINGS_TITLE))
