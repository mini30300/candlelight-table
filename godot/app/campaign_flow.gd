class_name CampaignFlow
extends RefCounted
## ทางเดินของหน้าจอแคมเปญ (CAMPAIGN_SPEC §1, track A เป็นเจ้าของ): ทุกทางเข้าเรียก start(from) ที่เดียว
## ความยาก (DifficultyScreen, track B) → กาแล็กซี + การ์ดดาว + บรีฟ (GalaxyScreen) → ภารกิจ (MissionScreen, track C)
## → สรุปผล (ReportScreen) → กลับกาแล็กซี หรือกลับที่เดิม (ดาดฟ้า / ห้องเสริม) ด้วย leave()
## จำความลึกของกองหน้าจอตอนเริ่ม (App.depth) แล้ว leave() ถอยจนถึงตรงนั้น · หน้าจอไม่ปิดกันเอง ไฟล์นี้เปลี่ยนหน้าทั้งหมด
## ภารกิจ: Net where = "arena" (ค่าเดิมของ NetProto) · สรุปผล: where = "deck" และเพลง deck · ไม่มีงานต่อเฟรม · ไม่มีข้อความไทย

const DIFFICULTY := "res://ui/screens/difficulty_screen.tscn"
const GALAXY := "res://ui/screens/galaxy_screen.tscn"
const MISSION := "res://ui/screens/mission_screen.tscn"
const REPORT := "res://ui/screens/report_screen.tscn"
## ป้ายบนหน้าจอที่ไฟล์นี้เปิด (meta) ไว้รู้ว่าหน้าบนสุดเป็นของแคมเปญไหม
const META := &"campaign_screen"

## ที่มา: "deck" (สถานีบนดาดฟ้า) หรือ "room" (สถานี/การ์ดในห้องเสริม)
static var from := ""
static var base_depth := -1
static var difficulty := ""
static var spec: Dictionary = {}
## เทส: แทนฉากของหน้าด้วยฉากตัวแทน {"difficulty"|"galaxy"|"mission"|"report": path} (ว่าง = ของจริง)
static var test_scenes: Dictionary = {}


static func _path(kind: String) -> String:
	if test_scenes.has(kind):
		return str(test_scenes[kind])
	match kind:
		"difficulty":
			return DIFFICULTY
		"galaxy":
			return GALAXY
		"mission":
			return MISSION
	return REPORT


static func _ready_scene(kind: String) -> PackedScene:
	var p := _path(kind)
	if not ResourceLoader.exists(p):
		return null
	return load(p) as PackedScene


static func _mark(n: Node, kind: String) -> Node:
	if n != null:
		n.set_meta(META, kind)
	return n


## หน้าบนสุดเป็นหน้าแคมเปญชนิด kind ไหม ("" = ชนิดไหนก็ได้)
static func is_top(kind := "") -> bool:
	var top := App.current()
	if top == null or not top.has_meta(META):
		return false
	return kind == "" or str(top.get_meta(META)) == kind


## อยู่ในแคมเปญ (มีหน้าแคมเปญอยู่บนสุด)
static func running() -> bool:
	return base_depth >= 0 and is_top()


## เปิดแคมเปญ (หน้าเลือกความยาก) ทับหน้าปัจจุบัน · คืนหน้าที่เปิด หรือ null เมื่อหน้ายังไม่พร้อม
## กดซ้ำตอนเปิดอยู่แล้ว = คืนหน้าบนสุดเดิม
static func start(p_from: String) -> Node:
	if running():
		return App.current()
	var ps := _ready_scene("difficulty")
	if ps == null:
		return null
	from = p_from
	base_depth = App.depth()
	spec = {}
	return _open_difficulty(App.push(ps))


## เปลี่ยนความยากจากหน้ากาแล็กซี: แทนที่กาแล็กซีด้วยหน้าเลือกความยาก
static func change_difficulty() -> Node:
	if not is_top("galaxy"):
		return null
	var ps := _ready_scene("difficulty")
	if ps == null:
		return null
	return _open_difficulty(App.replace(ps), true)


## ถอยจากหน้าความยากที่เปิดจากกาแล็กซี: กลับกาแล็กซีที่ความยากเดิม (ไม่ออกจากแคมเปญ) · false = ทำไม่ได้
static func cancel_difficulty() -> bool:
	if base_depth < 0 or not is_top("difficulty") or not CampaignGalaxy.DIFFICULTIES.has(difficulty):
		return false
	var ps := _ready_scene("galaxy")
	if ps == null:
		return false
	var gs := _mark(App.replace(ps), "galaxy")
	if gs.has_method(&"open"):
		gs.call(&"open", {"difficulty": difficulty, "week": CampaignWeek.current()})
	return true


static func _open_difficulty(ds: Node, change := false) -> Node:
	_mark(ds, "difficulty")
	if ds.has_method(&"open"):
		ds.call(&"open", {"last": CampaignSave.last_difficulty(), "from": from, "change": change})
	if ds.has_signal(&"chosen"):
		ds.connect(&"chosen", _on_difficulty.bind(ds))
	return ds


## เลือกความยากแล้ว: จำไว้ แทนที่หน้าความยากด้วยกาแล็กซีของสัปดาห์นี้ (ส่งซ้ำ / หน้าไม่ได้อยู่บนสุด = ข้าม)
static func _on_difficulty(id: StringName, ds: Node = null) -> void:
	if not CampaignGalaxy.DIFFICULTIES.has(String(id)):
		return
	if ds != null and App.current() != ds:
		return
	var ps := _ready_scene("galaxy")
	if ps == null:
		return
	difficulty = String(id)
	CampaignSave.set_last_difficulty(difficulty)
	var gs := _mark(App.replace(ps), "galaxy")
	if gs.has_method(&"open"):
		gs.call(&"open", {"difficulty": difficulty, "week": CampaignWeek.current()})


## เริ่มภารกิจจากบรีฟ: s = CampaignGalaxy.mission_spec(...) · กดซ้ำระหว่างภารกิจเปิดอยู่ = ไม่ทำอะไร
static func launch(s: Dictionary) -> Node:
	if s.is_empty() or is_top("mission"):
		return null
	var ps := _ready_scene("mission")
	if ps == null:
		return null
	spec = s
	return _start_mission(App.push(ps))


## เล่นภารกิจเดิมอีกครั้งจากหน้าสรุปผล (spec เดิม seed เดิม)
static func retry() -> Node:
	if spec.is_empty() or not is_top("report"):
		return null
	var ps := _ready_scene("mission")
	if ps == null:
		return null
	return _start_mission(App.replace(ps))


static func _start_mission(ms: Node) -> Node:
	_mark(ms, "mission")
	_set_where(&"arena")
	if ms.has_signal(&"finished"):
		ms.connect(&"finished", _on_finished.bind(ms), CONNECT_ONE_SHOT)
	if ms.has_method(&"start"):
		ms.call(&"start", spec)
	return ms


## จบภารกิจ: คิดคะแนน บันทึก (ครั้งเดียว) แล้วแทนที่หน้าภารกิจด้วยหน้าสรุปผล
static func _on_finished(result: Dictionary, ms: Node = null) -> void:
	if spec.is_empty():
		return
	var rep := CampaignSave.is_repeat(spec)
	var sc := CampaignRules.score(spec, result, {"repeat": rep})
	sc["repeat"] = rep
	CampaignSave.record(spec, sc)
	_set_where(&"deck")
	var music := App.get_node_or_null(^"/root/Music")
	if music != null:
		music.call("set_mood", &"deck")
	# หน้าอื่น (ตั้งค่า) ทับหน้าภารกิจอยู่: ปิดให้หน้าภารกิจอยู่บนสุดก่อน
	if ms != null and is_instance_valid(ms):
		while App.current() != ms and App.depth() > maxi(base_depth, 0) + 1:
			if not App.pop():
				break
	var ps := _ready_scene("report")
	if ps == null:
		App.pop()
		return
	var rs := _mark(App.replace(ps), "report")
	if rs.has_method(&"open"):
		rs.call(&"open", {"spec": spec, "result": result, "score": sc, "coins": CampaignSave.coins()})


## หน้าสรุปผล → กลับแผนที่กาแล็กซี (หน้ากาแล็กซีอยู่ข้างใต้)
static func back_to_galaxy() -> void:
	if is_top("report"):
		App.pop()


## กลับที่เดิม (ดาดฟ้า / ห้องเสริม): ถอยหน้าจอจนเหลือความลึกตอนเริ่ม
static func leave() -> void:
	while base_depth >= 0 and App.depth() > base_depth:
		if not App.pop():
			break
	base_depth = -1
	spec = {}


static func _set_where(w: StringName) -> void:
	var net := App.get_node_or_null(^"/root/Net")
	if net != null and net.has_method(&"set_where"):
		net.call(&"set_where", w)
