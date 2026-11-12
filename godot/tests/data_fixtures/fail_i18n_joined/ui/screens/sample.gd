extends Control
## Fixture: two keys joined inside one literal; I18n.t matches whole strings, so this stays Thai (must fail).

const BOTH := "ยกเลิก · ตกลง"   # สองคีย์ต่อกันในสตริงเดียว


func _ready() -> void:
	print(I18n.t(BOTH))
