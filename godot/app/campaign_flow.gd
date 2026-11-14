class_name CampaignFlow
extends RefCounted
## ทางเดินของหน้าจอแคมเปญ (CAMPAIGN_SPEC §1, track A เป็นเจ้าของ): ทุกทางเข้าเรียก start(from) ที่เดียว
## ความยาก (DifficultyScreen, track B) → กาแล็กซี + การ์ดดาว + บรีฟ (GalaxyScreen) → ภารกิจ (MissionScreen, track C)
## → สรุปผล (ReportScreen) → กลับกาแล็กซี หรือกลับที่เดิม (ดาดฟ้า / ห้องเสริม) ด้วย leave()
## จำความลึกของกองหน้าจอตอนเริ่ม (App.depth) แล้ว leave() ถอยจนถึงตรงนั้น · ไม่มีงานต่อเฟรม · ไม่มีข้อความไทย
## TODO(track A): ทำให้ครบตาม §1 (จอมืดตอนเข้า/ออกภารกิจ, กันกดซ้ำ, เพลง, Net where) และเทส flow

const DIFFICULTY := "res://ui/screens/difficulty_screen.tscn"
const GALAXY := "res://ui/screens/galaxy_screen.tscn"
const MISSION := "res://ui/screens/mission_screen.tscn"
const REPORT := "res://ui/screens/report_screen.tscn"

## ที่มา: "deck" (สถานีบนดาดฟ้า) หรือ "room" (สถานี/การ์ดในห้องเสริม)
static var from := ""
static var base_depth := -1
static var difficulty := ""
static var spec: Dictionary = {}


## เปิดแคมเปญ (หน้าเลือกความยาก) ทับหน้าปัจจุบัน · คืนหน้าที่เปิด หรือ null เมื่อหน้ายังไม่พร้อม
static func start(p_from: String) -> Node:
	if not ResourceLoader.exists(DIFFICULTY):
		return null
	from = p_from
	base_depth = App.depth()
	var ds := App.push(load(DIFFICULTY))
	if ds.has_method(&"open"):
		ds.call(&"open", {"last": CampaignSave.last_difficulty(), "from": from})
	if ds.has_signal(&"chosen"):
		ds.connect(&"chosen", _on_difficulty)
	return ds


## เลือกความยากแล้ว: จำไว้ แทนที่หน้าความยากด้วยกาแล็กซีของสัปดาห์นี้
static func _on_difficulty(id: StringName) -> void:
	difficulty = String(id)
	CampaignSave.set_last_difficulty(difficulty)
	if not ResourceLoader.exists(GALAXY):
		return
	var gs := App.replace(load(GALAXY))
	if gs.has_method(&"open"):
		gs.call(&"open", {"difficulty": difficulty, "week": CampaignWeek.current()})


## เริ่มภารกิจจากบรีฟ: s = CampaignGalaxy.mission_spec(...)
static func launch(s: Dictionary) -> Node:
	if s.is_empty() or not ResourceLoader.exists(MISSION):
		return null
	spec = s
	var ms := App.push(load(MISSION))
	if ms.has_signal(&"finished"):
		ms.connect(&"finished", _on_finished)
	if ms.has_method(&"start"):
		ms.call(&"start", s)
	return ms


## จบภารกิจ: คิดคะแนน บันทึก แล้วแทนที่หน้าภารกิจด้วยหน้าสรุปผล
static func _on_finished(result: Dictionary) -> void:
	var sc := CampaignRules.score(spec, result, {"repeat": CampaignSave.is_repeat(spec)})
	CampaignSave.record(spec, sc)
	if not ResourceLoader.exists(REPORT):
		App.pop()
		return
	var rs := App.replace(load(REPORT))
	if rs.has_method(&"open"):
		rs.call(&"open", {"spec": spec, "result": result, "score": sc, "coins": CampaignSave.coins()})


## กลับที่เดิม (ดาดฟ้า / ห้องเสริม): ถอยหน้าจอจนเหลือความลึกตอนเริ่ม
static func leave() -> void:
	while base_depth >= 0 and App.depth() > base_depth:
		if not App.pop():
			break
	base_depth = -1
